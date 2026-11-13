---@type table sd-interact config root (configs/config.lua).
local config = require 'configs.config'
---@type table Every interaction point (client.interact.points).
local points = require 'client.interact.points'
---@type table Job / gang checks (client.interact.groups).
local groups = require 'client.interact.groups'

-- A few times a second: which points are near enough to matter, where they are, and which of their
-- options the player may use right now. The frame loop (client.interact.loop) only draws and picks
-- from this list, so the expensive parts (entity pools, canInteract callbacks into other resources)
-- run at ScanEveryMs, not every frame. Entity-anchored candidates keep their entity, and the loop
-- re-reads their position every frame so a prompt rides a moving door or vehicle.

---@class InteractCandidate
---@field key string point id + entity: one prompt per point per entity
---@field point InteractPoint
---@field entity integer|nil
---@field pos vector3
---@field dist number
---@field options { option: InteractOption, index: integer, label: string, point: InteractPoint }[] the options shown, in order (each with the point it is from: a merged prompt has several)
---@field reach number the interact distance

---@type table Scan module; the table returned at end of file.
local scan = {}

---@type InteractCandidate[] The points in range, as of the last scan.
scan.candidates = {}

local CFG = config.Interact

---@type table<integer, { lo: vector3, hi: vector3, mid: vector3 }> A model's bounding box, and its middle (the default anchor on an entity).
local boxes = {}

---@param entity integer
---@return { lo: vector3, hi: vector3, mid: vector3 } in the entity's own space
local function box(entity)
    local model = GetEntityModel(entity)
    local b = boxes[model]

    if not b then
        local lo, hi = GetModelDimensions(model)
        b = { lo = lo, hi = hi, mid = vector3((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, (lo.z + hi.z) / 2) }
        boxes[model] = b
    end

    return b
end

---The point of an entity's bounding box nearest `from` (`from` itself when it is inside the box).
---ox_target and qb-target measure an option's distance to where the player's aim hits the entity,
---which on a car can be its boot: measured to the car's middle, ox_inventory's trunk (1.5 m, and
---only from behind the car) could never be reached.
---@param entity integer
---@param from vector3
---@return vector3
local function nearestOn(entity, from)
    local b = box(entity)
    local l = GetOffsetFromEntityGivenWorldCoords(entity, from.x, from.y, from.z)
    local x = math.min(math.max(l.x, b.lo.x), b.hi.x)
    local y = math.min(math.max(l.y, b.lo.y), b.hi.y)
    local z = math.min(math.max(l.z, b.lo.z), b.hi.z)
    return GetOffsetFromEntityInWorldCoords(entity, x, y, z)
end

---Where a point's prompt goes on an entity: its bone, its offset, where the entity is nearest the
---player (a `surface` point, given `from`), or the middle of its model.
---@param p InteractPoint
---@param entity integer
---@param from? vector3 the player
---@return vector3
function scan.anchor(p, entity, from)
    if p.bone then
        local idx

        if type(p.bone) == 'string' then
            idx = GetEntityBoneIndexByName(entity, p.bone)
        else
            idx = GetPedBoneIndex(entity, p.bone)
        end

        if idx and idx ~= -1 then
            local b = GetWorldPositionOfEntityBone(entity, idx)

            if p.offset then
                return b + p.offset
            end

            return b
        end
    end

    if p.surface and from and not p.offset then
        return nearestOn(entity, from)
    end

    local o = p.offset or box(entity).mid
    return GetOffsetFromEntityInWorldCoords(entity, o.x, o.y, o.z)
end

---The options of a point the player may use here and now, in order.
---@param p InteractPoint
---@param entity integer|nil
---@param pos vector3
---@param dist number
---@return { option: InteractOption, index: integer }[]
local function usable(p, entity, pos, dist)
    local out = {}

    if p.groups and not groups.allowed(p.groups) then
        return out
    end

    for i, o in ipairs(p.options) do
        local ok = true
        local label

        if o.groups and not groups.allowed(o.groups) then
            ok = false
        end

        if ok and o.distance and dist > o.distance + CFG.Slack then
            ok = false
        end

        if ok and o.canInteract then
            -- a second return value is the label to show now ("Take Pump Shotgun"): an option table
            -- crosses into this resource as a copy, so its owner cannot just rewrite o.label
            local fine, res, now = pcall(o.canInteract, entity, pos, o.args, dist)
            ok = fine and res and true or false

            if ok and type(now) == 'string' and now ~= '' then
                label = now
            end
        end

        if ok then
            out[#out + 1] = { option = o, index = i, label = label or o.label, point = p }
        end
    end

    return out
end

---@param list InteractCandidate[]
---@param p InteractPoint
---@param entity integer|nil
---@param pos vector3
---@param from vector3 the player
local function consider(list, p, entity, pos, from)
    local dist = #(pos - from)

    if dist > p.distance then return end

    local opts = usable(p, entity, pos, dist)

    if #opts == 0 then return end

    list[#list + 1] = {
        key = entity and ('%d:%d'):format(p.id, entity) or tostring(p.id),
        point = p,
        entity = entity,
        pos = pos,
        dist = dist,
        options = opts,
        reach = p.interactDistance + CFG.Slack,
    }
end

---Prompts on the same entity at the same spot become one, its options scrolled through like any
---other prompt's. That is every point on the entity with no bone or offset (they all sit in its
---middle, or all where it is nearest the player): ox_target shows all of an entity's options in one
---menu, and apart they lie on top of each other and only the first can ever be picked (ox_inventory's
---trunk under sd-wraps' "Design livery"). The closest-range point's options come first: what the
---player is standing right at is the likeliest pick.
---@param list InteractCandidate[]
---@return InteractCandidate[]
function scan.merge(list)
    local out, spots = {}, {}

    for _, c in ipairs(list) do
        local p = c.point
        local spot = c.entity and not p.bone and not p.offset and ('%d:%s'):format(c.entity, p.surface and 'near' or 'mid')
        local g = spot and spots[spot]

        if not spot then
            out[#out + 1] = c
        elseif not g then
            -- (the same key merged or not: stepping into one more option's range keeps the prompt open)
            c.key = 'spot:' .. spot
            spots[spot] = { first = c, parts = { c } }
            out[#out + 1] = c
        else
            g.parts[#g.parts + 1] = c
        end
    end

    for _, g in pairs(spots) do
        if #g.parts > 1 then
            local function range(c)
                local d = math.huge

                for _, e in ipairs(c.options) do
                    d = math.min(d, e.option.distance or c.point.interactDistance)
                end

                return d
            end

            table.sort(g.parts, function(a, b)
                local ra, rb = range(a), range(b)
                if ra ~= rb then return ra < rb end
                return a.point.id < b.point.id
            end)

            local m = g.first
            local options, reach = {}, 0

            for _, c in ipairs(g.parts) do
                for _, e in ipairs(c.options) do
                    options[#options + 1] = e
                end

                reach = math.max(reach, c.reach)
            end

            m.options = options
            m.reach = reach
            m.point = g.parts[1].point
        end
    end

    return out
end

---Entities of the given pool near the player.
---@param pool string
---@param from vector3
---@param range number
---@return integer[]
local function near(pool, from, range)
    local out = {}

    for _, e in ipairs(GetGamePool(pool)) do
        if #(GetEntityCoords(e) - from) <= range then
            out[#out + 1] = e
        end
    end

    return out
end

---Is this entity one a global point of this kind goes on? (Players and other peds share a pool.)
---@param kind 'vehicle'|'ped'|'object'|'player'
---@param entity integer
---@return boolean
local function isKind(kind, entity)
    if kind == 'object' or kind == 'vehicle' then return true end

    local isPlayer = IsPedAPlayer(entity)

    if kind == 'player' then
        return isPlayer
    end

    return kind == 'ped' and not isPlayer
end

---Rebuild the candidate list.
---@param ped integer the player's ped
---@param inVehicle boolean
function scan.run(ped, inVehicle)
    local from = GetEntityCoords(ped)
    local list = {}
    local wantModels, wantGlobal = false, {}

    for _, p in pairs(points.all()) do
        if inVehicle and not p.allowInVehicle and CFG.HideInVehicle then goto continue end

        if p.kind == 'coords' then
            consider(list, p, nil, p.coords, from)
        elseif p.kind == 'entity' then
            if DoesEntityExist(p.entity) then
                consider(list, p, p.entity, scan.anchor(p, p.entity, from), from)
            end
        elseif p.kind == 'net' then
            if NetworkDoesNetworkIdExist(p.netId) then
                local e = NetworkGetEntityFromNetworkId(p.netId)

                if e and e ~= 0 and DoesEntityExist(e) then
                    consider(list, p, e, scan.anchor(p, e, from), from)
                end
            end
        elseif p.kind == 'model' then
            wantModels = true
        elseif p.kind == 'global' then
            wantGlobal[p.global] = true
        end

        ::continue::
    end

    local wantObjects = wantModels or wantGlobal.object
    local wantPeds = wantModels or wantGlobal.ped or wantGlobal.player
    local wantVehicles = wantModels or wantGlobal.vehicle

    if not wantObjects and not wantPeds and not wantVehicles then
        scan.candidates = scan.merge(list)
        return
    end

    local range = CFG.ModelScanRange
    local pools = {}

    if wantObjects then
        pools.CObject = near('CObject', from, range)
    end

    if wantPeds then
        pools.CPed = near('CPed', from, range)
    end

    if wantVehicles then
        pools.CVehicle = near('CVehicle', from, range)
    end

    for _, p in pairs(points.all()) do
        if inVehicle and not p.allowInVehicle and CFG.HideInVehicle then goto skip end

        if p.kind == 'model' then
            for _, pool in pairs(pools) do
                for _, e in ipairs(pool) do
                    if p.models[GetEntityModel(e)] and e ~= ped then
                        consider(list, p, e, scan.anchor(p, e, from), from)
                    end
                end
            end
        elseif p.kind == 'global' then
            local pool = pools.CPed

            if p.global == 'object' then
                pool = pools.CObject
            elseif p.global == 'vehicle' then
                pool = pools.CVehicle
            end

            for _, e in ipairs(pool or {}) do
                if e ~= ped and isKind(p.global, e) then
                    consider(list, p, e, scan.anchor(p, e, from), from)
                end
            end
        end

        ::skip::
    end

    scan.candidates = scan.merge(list)
end

return scan
