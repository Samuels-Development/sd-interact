---@type table Job / gang checks (client.interact.groups).
local groups = require 'client.interact.groups'

-- Turning another target resource's options into sd-interact options, so ox_target, qtarget and
-- qb-target calls work unchanged (client/compat/ox_target.lua, client/compat/qb_target.lua). Every
-- converted option keeps its own name (removing by name works) and its own handler, and its
-- canInteract is called with the arguments that resource's own scripts expect.

---@type table Convert module; the table returned at end of file.
local convert = {}

-- ---- items and identity -------------------------------------------------------------------------

---How many of an item the player carries (ox_inventory, else the framework's item list).
---@param name string
---@return integer
local function count(name)
    if GetResourceState('ox_inventory') == 'started' then
        local ok, n = pcall(function() return exports.ox_inventory:Search('count', name) end)

        if ok and type(n) == 'number' then
            return n
        end
    end

    local d = groups.playerData()
    local n = 0

    for _, it in pairs(d and (d.items or d.inventory) or {}) do
        if type(it) == 'table' and it.name == name then
            n = n + (it.amount or it.count or 1)
        end
    end

    return n
end

---ox_target's `items` (a name, a list, or { name = count }) with `anyItem`; qb-target's `item`.
---@param items any
---@param any boolean one is enough
---@return boolean
function convert.hasItems(items, any)
    if items == nil then return true end

    if type(items) == 'string' then
        return count(items) > 0
    end

    if type(items) ~= 'table' then return true end

    local list = {}

    if items[1] then
        for _, n in ipairs(items) do
            list[#list + 1] = { n, 1 }
        end
    else
        for n, c in pairs(items) do
            list[#list + 1] = { n, tonumber(c) or 1 }
        end
    end

    for _, e in ipairs(list) do
        local have = count(e[1]) >= e[2]

        if any and have then return true end

        if not any and not have then return false end
    end

    return not any
end

---qb-target's `citizenid` (one id, a list, or { [id] = true }).
---@param want any
---@return boolean
function convert.isCitizen(want)
    if want == nil then return true end

    local d = groups.playerData()
    local me = d and (d.citizenid or d.identifier)

    if not me then return false end

    if type(want) == 'string' then
        return want == me
    end

    if type(want) == 'table' then
        if want[me] then return true end

        for _, v in ipairs(want) do
            if v == me then return true end
        end
    end

    return false
end

-- ---- options ---------------------------------------------------------------------------------------

---Fields ox_target takes off the option before handing it to a handler.
local OX_STRIPPED = {
    'icon', 'groups', 'items', 'canInteract', 'onSelect', 'export', 'event', 'serverEvent', 'command',
}

---What an ox_target handler is given, built as ox_target 1.17.2 builds it (getResponse): a copy of the
---option with the target's entity, zone, coords and distance set on it and its handler and gating fields
---taken off. For a server event the entity goes as its network id, 0 when it has none.
---@param o table the ox_target option
---@param data table sd-interact's { id, name, entity, coords, distance, args }
---@param zone integer|nil the zone the option is on
---@param server? boolean
---@return table
local function oxResponse(o, data, zone, server)
    local r = {}

    for k, v in pairs(o) do
        r[k] = v
    end

    -- a zone's prompt is on no entity: ox_target reports what its ray hit there, usually nothing (0)
    r.entity = data.entity or 0
    r.zone = zone
    r.coords = data.coords
    r.distance = data.distance

    if server then
        local e = r.entity
        r.entity = e ~= 0 and NetworkGetEntityIsNetworked(e) and NetworkGetNetworkIdFromEntity(e) or 0
    end

    for _, k in ipairs(OX_STRIPPED) do
        r[k] = nil
    end

    return r
end

---An ox_target option as an sd-interact option.
---@param o table the option (an export call hands sd-interact its own copy)
---@param owner string the resource that registered it: an `export` is called there, as in ox_target
---@param zone integer|nil the zone it is on
---@param bone string|nil the bone this copy of the option is on
---@return table|nil
function convert.ox(o, owner, zone, bone)
    if type(o) ~= 'table' or type(o.label) ~= 'string' then return nil end

    local out = {
        label = o.label,
        icon = o.icon,
        name = o.name,
        distance = o.distance,
        hold = o.hold,
        source = o,
    }

    local can = o.canInteract

    out.canInteract = function(entity, coords, _, dist)
        if o.groups and not groups.allowed(o.groups) then return false end

        if o.items and not convert.hasItems(o.items, o.anyItem) then return false end

        if can then
            -- ox_target passes the bone's index (not its name) and 0 for "no entity"
            local boneId = type(bone) == 'string' and GetEntityBoneIndexByName(entity, bone) or bone
            return can(entity or 0, dist, coords, o.name, boneId)
        end

        return true
    end

    out.onSelect = function(data)
        if o.onSelect then
            -- ox_target's own qtarget bridge flags its options `qtarget`: those get only the entity
            o.onSelect(o.qtarget and (data.entity or 0) or oxResponse(o, data, zone))
        elseif o.export then
            -- the export's name, on the resource that registered the option ('res.name' is not split)
            exports[o.resource or owner][o.export](nil, oxResponse(o, data, zone))
        elseif o.event then
            TriggerEvent(o.event, oxResponse(o, data, zone))
        elseif o.serverEvent then
            TriggerServerEvent(o.serverEvent, oxResponse(o, data, zone, true))
        elseif o.command then
            ExecuteCommand(o.command)
        end
    end

    return out
end

---A qb-target / qtarget option as an sd-interact option.
---@param o table
---@param maxDistance number the call's `distance`, or qb-target's default (Config.MaxDistance, 7.0)
---@return table|nil
function convert.qb(o, maxDistance)
    if type(o) ~= 'table' or type(o.label) ~= 'string' then return nil end

    -- the option as qb-target 5.5.0 stores it (SetOptions): `required_item` becomes `item` and its
    -- `distance` is capped to the call's. This table is what canInteract and the handlers are given.
    local stored = {}

    for k, v in pairs(o) do
        stored[k] = v
    end

    if stored.required_item then
        stored.item = stored.required_item
        stored.required_item = nil
    end

    if not stored.distance or stored.distance > maxDistance then
        stored.distance = maxDistance
    end

    local out = { label = o.label, icon = o.icon, name = o.name or o.label, distance = o.distance }
    local can = stored.canInteract

    out.canInteract = function(entity, _, _, dist)
        -- as qb-target: a job and a gang, when both are given, must both be met
        if stored.job and not groups.allowed(stored.job) then return false end

        if stored.gang and not groups.allowed(stored.gang) then return false end

        if stored.item and not convert.hasItems(stored.item, false) then return false end

        if stored.citizenid and not convert.isCitizen(stored.citizenid) then return false end

        if can then
            return can(entity or 0, dist, stored)
        end

        return true
    end

    out.onSelect = function(data)
        local d = {}

        for k, v in pairs(stored) do
            d[k] = v
        end

        -- qb-target sets the entity its ray hit and that entity's coords; `distance` stays the
        -- option's. A zone's prompt is on no entity (0), so it gets the prompt's position instead.
        d.entity = data.entity or 0
        d.coords = data.entity and GetEntityCoords(data.entity) or data.coords

        if d.action then
            d.action(d.entity)
        elseif d.event then
            if d.type == 'client' then
                TriggerEvent(d.event, d)
            elseif d.type == 'server' then
                TriggerServerEvent(d.event, d)
            elseif d.type == 'command' then
                ExecuteCommand(d.event)
            elseif d.type == 'qbcommand' then
                TriggerServerEvent('QBCore:CallCommand', d.event, d)
            else
                TriggerEvent(d.event, d)
            end
        else
            error('This option has no action or event.')
        end
    end

    return out
end

---ox_target options grouped by where they go on an entity: options with `bones` get one copy per
---bone (a point on each bone), options with an `offset` a point of their own, the rest share the
---entity's middle.
---@param options table[]
---@param owner string the resource that registered them
---@return { bone: string|nil, offset: vector3|nil, options: table[] }[]
function convert.oxAnchored(options, owner)
    local groupsOut, plain = {}, {}

    if type(options) == 'table' and options.label then
        options = { options }
    end

    for _, o in ipairs(type(options) == 'table' and options or {}) do
        if type(o) == 'table' and o.bones then
            for _, b in ipairs(type(o.bones) == 'table' and o.bones or { o.bones }) do
                local c = convert.ox(o, owner, nil, b)

                if c then
                    groupsOut[#groupsOut + 1] = { bone = b, options = { c } }
                end
            end
        elseif type(o) == 'table' and o.offset then
            local c = convert.ox(o, owner)

            if c then
                groupsOut[#groupsOut + 1] = { offset = o.offset, options = { c } }
            end
        else
            local c = convert.ox(o, owner)

            if c then
                plain[#plain + 1] = c
            end
        end
    end

    if #plain > 0 then
        table.insert(groupsOut, 1, { options = plain })
    end

    return groupsOut
end

---The interact distance for a set of converted options: the furthest an option allows (capped, as
---a prompt is a close thing), or the given default.
---@param options table[]
---@param default number
---@return number
function convert.reach(options, default)
    local d = 0

    for _, o in ipairs(options) do
        if o.distance and o.distance > d then
            d = o.distance
        end
    end

    if d <= 0 then
        d = default
    end

    return math.min(d, 5.0)
end

return convert
