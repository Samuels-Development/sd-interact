---@type table Every interaction point (client.interact.points).
local points = require 'client.interact.points'
---@type table What the player is looking at (client.interact.state).
local state = require 'client.interact.state'
---@type table Option conversion (client.compat.convert).
local convert = require 'client.compat.convert'
---@type table Which points each call made (client.compat.book).
local book = require 'client.compat.book'

-- ox_target's client exports, answered by sd-interact: a script calling exports.ox_target:addBoxZone
-- (or any other) gets a prompt instead of a target, without a line of it changed. Registered only when
-- the server owner turns it on (configs/client/replace.lua). Modelled on ox_target 1.17.2.
--
-- What maps to what: a zone (box, sphere, poly) is a point at its middle, close enough to use when the
-- player is within the options' distance of its edge; an entity, a network entity, a model and the
-- globals are points on the entity's middle, or on its bones (options with `bones`) or at their
-- `offset`. As in ox_target, an option added again under its name by the same resource replaces the
-- old one, and removing by name only touches the calling resource's options.

---@type table Ox module; the table returned at end of file.
local ox = {}

-- ox_target shows self targets while its cursor is on the player's own ped. A prompt has no cursor:
-- here they are a point on the player's ped that opens only while the camera looks down at it (the
-- gameplay camera pitched below this many degrees). Without that, it would sit on the player whenever
-- nothing else is nearer the middle of the screen.
local SELF_PITCH = -30.0

local function caller() return GetInvokingResource() or GetCurrentResourceName() end

local function list(v) return type(v) == 'table' and v or { v } end

---ox_target's options argument: a list, or one option given bare.
---@param options any
---@return table[]
local function optionList(options)
    if type(options) ~= 'table' then
        return {}
    end

    if options.label then
        return { options }
    end

    return options
end

---@param v any
---@return vector3|nil
local function vec(v)
    if type(v) == 'vector3' or type(v) == 'vector4' then
        return vector3(v.x, v.y, v.z)
    end

    if type(v) == 'table' and v.x then
        return vector3(v.x + 0.0, v.y + 0.0, (v.z or 0.0) + 0.0)
    end

    return nil
end

---@param m string|integer
---@return integer
local function hash(m)
    return type(m) == 'string' and joaat(m) or m
end

---@param entity integer
---@return integer|false
local function netIdOf(entity)
    return NetworkGetEntityIsNetworked(entity) and NetworkGetNetworkIdFromEntity(entity)
end

---Which global list an entity falls under, as ox_target picks it from GetEntityType.
---@param entity integer
---@param entityType integer 1 ped, 2 vehicle, 3 object
---@return string key
local function globalKey(entity, entityType)
    if entityType == 1 then
        return IsPedAPlayer(entity) and 'global:player' or 'global:ped'
    end

    return entityType == 2 and 'global:vehicle' or 'global:object'
end

---Is the camera looking down at the player (see SELF_PITCH)?
---@return boolean
local function lookingAtSelf()
    return GetGameplayCamRelativePitch() <= SELF_PITCH
end

---The exports for one name sd-interact answers as. Every key it books is scoped to that name.
---@param name string 'ox_target'
---@return table<string, function>
local function build(name)
    local api = {}
    local own = book.scope(name)

    ---@type table<string|integer, string> zone ids and names -> book key
    local zones = {}
    ---@type integer
    local zoneSeq = 0

    ---A zone as one point at its middle.
    ---@param data table ox zone data (name, options, debug, ...)
    ---@param centre vector3
    ---@param halfSize number how far its edge is from its middle
    ---@return integer|nil id
    local function addZone(data, centre, halfSize)
        if not centre then return nil end

        zoneSeq = zoneSeq + 1
        local id = zoneSeq
        local key = ('zone:%d'):format(id)
        local res = caller()
        local opts = {}

        for _, o in ipairs(optionList(data.options)) do
            local c = convert.ox(o, res, id)

            if c then
                opts[#opts + 1] = c
            end
        end

        local reach = math.min(convert.reach(opts, 3.0) + math.min(halfSize, 1.5), 5.5)
        local pointData = { options = opts, interactDistance = reach, distance = reach + 3.0 }

        own.add(key, points.addCoords(centre, pointData, res))
        zones[id] = key

        if data.name then
            zones[data.name] = key
        end

        return id
    end

    ---Points on something (an entity, a model, a global type, the player): one per anchor group.
    ---@param key string
    ---@param options any
    ---@param res string the resource registering them
    ---@param add fun(data: table): integer|nil ... the point(s) made for one anchor group
    ---@param gate? fun(): boolean an extra condition on every option
    local function addOn(key, options, res, add, gate)
        local opts = optionList(options)
        local names = {}

        for _, o in ipairs(opts) do
            if type(o) == 'table' then
                o.resource = res

                if o.name then
                    names[#names + 1] = o.name
                end
            end
        end

        if names[1] then
            own.remove(key, names, 'name', res)
        end

        for _, g in ipairs(convert.oxAnchored(opts, res)) do
            if gate then
                for _, c in ipairs(g.options) do
                    local inner = c.canInteract

                    c.canInteract = function(...)
                        if not gate() then return false end

                        return inner(...)
                    end
                end
            end

            local reach = convert.reach(g.options, 3.0)

            local ids = table.pack(add({
                options = g.options,
                bone = g.bone,
                offset = g.offset,
                -- on no bone or offset, ox_target measures to where the aim hits the entity
                surface = g.bone == nil and g.offset == nil,
                interactDistance = reach,
                distance = reach + 3.0,
            }))

            for i = 1, ids.n do
                own.add(key, ids[i])
            end
        end
    end

    ---Remove from something by option name, the calling resource's only (ox_target's removeTarget).
    ---Without names a list-type target (globals, self) loses nothing, as in ox_target.
    ---@param key string
    ---@param names string|string[]|nil
    local function removeNamed(key, names)
        if names == nil then return end

        own.remove(key, names, 'name', caller())
    end

    ---Remove a model / entity / local entity: everything on it without names, else the calling
    ---resource's options by name.
    ---@param key string
    ---@param names string|string[]|nil
    local function removeOn(key, names)
        if names == nil then
            own.remove(key)
            return
        end

        own.remove(key, names, 'name', caller())
    end

    ---The options ox_target would list for an entity (getTargetOptions with an entity).
    ---@param entity integer
    ---@param entityType integer
    ---@param model integer|nil
    ---@return table
    local function optionsFor(entity, entityType, model)
        if IsPedAPlayer(entity) then
            return { global = own.sources('global:player') or {} }
        end

        local netId = netIdOf(entity)

        return {
            global = own.sources(globalKey(entity, entityType)) or {},
            model = model and own.sources(('model:%d'):format(model)),
            entity = netId and own.sources(('net:%d'):format(netId)) or nil,
            localEntity = own.sources(('local:%d'):format(entity)),
        }
    end

    ---The model, network-entity and local-entity option lists on an entity (no globals).
    ---@param entity integer
    ---@param model integer|nil
    ---@return table[][]
    local function specific(entity, model)
        local netId = netIdOf(entity)

        return {
            model and own.sources(('model:%d'):format(model)) or {},
            netId and own.sources(('net:%d'):format(netId)) or {},
            own.sources(('local:%d'):format(entity)) or {},
        }
    end

    function api.addBoxZone(data)
        local size = vec(data.size) or vector3(2.0, 2.0, 2.0)
        return addZone(data, vec(data.coords), math.max(size.x, size.y) / 2)
    end

    function api.addSphereZone(data)
        return addZone(data, vec(data.coords), tonumber(data.radius) or 1.0)
    end

    function api.addPolyZone(data)
        local pts = data.points or {}
        local sx, sy, n, z = 0.0, 0.0, 0, 0.0
        local minx, maxx, miny, maxy = math.huge, -math.huge, math.huge, -math.huge

        for _, p in ipairs(pts) do
            sx, sy, n = sx + p.x, sy + p.y, n + 1
            z = z + (p.z or 0.0)
            minx = math.min(minx, p.x)
            maxx = math.max(maxx, p.x)
            miny = math.min(miny, p.y)
            maxy = math.max(maxy, p.y)
        end

        if n == 0 then return nil end

        local thick = tonumber(data.thickness) or 4.0
        local centre = vector3(sx / n, sy / n, z / n + thick / 4)

        return addZone(data, centre, math.max(maxx - minx, maxy - miny) / 2)
    end

    function api.removeZone(id)
        local key = zones[id]

        if not key then return end

        own.remove(key)

        for k, v in pairs(zones) do
            if v == key then
                zones[k] = nil
            end
        end
    end

    function api.zoneExists(id)
        local key = zones[id]
        return key ~= nil and own.has(key)
    end

    function api.addLocalEntity(entities, options)
        local res = caller()

        for _, e in ipairs(list(entities)) do
            addOn(('local:%d'):format(e), options, res, function(d) return points.addLocalEntity(e, d, res) end)
        end
    end

    function api.removeLocalEntity(entities, names)
        for _, e in ipairs(list(entities)) do
            removeOn(('local:%d'):format(e), names)
        end
    end

    function api.addEntity(netIds, options)
        local res = caller()

        for _, n in ipairs(list(netIds)) do
            addOn(('net:%d'):format(n), options, res, function(d) return points.addEntity(n, d, res) end)
        end
    end

    function api.removeEntity(netIds, names)
        for _, n in ipairs(list(netIds)) do
            removeOn(('net:%d'):format(n), names)
        end
    end

    function api.addModel(models, options)
        local res = caller()

        for _, m in ipairs(list(models)) do
            local h = hash(m)
            addOn(('model:%d'):format(h), options, res, function(d) return points.addModel({ h }, d, res) end)
        end
    end

    function api.removeModel(models, names)
        for _, m in ipairs(list(models)) do
            removeOn(('model:%d'):format(hash(m)), names)
        end
    end

    for _, kind in ipairs({ 'Ped', 'Vehicle', 'Object', 'Player' }) do
        local g = kind:lower()

        api['addGlobal' .. kind] = function(options)
            local res = caller()
            addOn('global:' .. g, options, res, function(d) return points.addGlobal(g, d, res) end)
        end

        api['removeGlobal' .. kind] = function(names) removeNamed('global:' .. g, names) end
    end

    ---ox_target's "on everything" options: here, on every ped, vehicle and object nearby. They are a
    ---list of their own, as in ox_target, so removeGlobalPed and the like do not touch them.
    function api.addGlobalOption(options)
        local res = caller()

        addOn('option', options, res, function(d)
            local ped = points.addGlobal('ped', d, res)
            local vehicle = points.addGlobal('vehicle', d, res)
            return ped, vehicle, points.addGlobal('object', d, res)
        end)
    end

    function api.removeGlobalOption(names)
        removeNamed('option', names)
    end

    function api.addSelfTarget(options)
        local res = caller()
        addOn('self', options, res, function(d) return points.addLocalEntity(cache.ped, d, res) end, lookingAtSelf)
    end

    function api.removeSelfTarget(names)
        removeNamed('self', names)
    end

    -- the self points follow the player's ped (respawn, model change)
    lib.onCache('ped', function(ped)
        for _, id in ipairs(own.ids('self')) do
            points.update(id, { entity = ped })
        end
    end)

    ---With an entity: its option lists, as ox_target returns them. Without one, ox_target returns the
    ---lists of whatever its cursor is on; there is no cursor here, so this answers for the open prompt
    ---(`__global` alone when the prompt is not on an entity, or none is open).
    function api.getTargetOptions(entity, entityType, model)
        if entity then
            return optionsFor(entity, entityType, model)
        end

        local current = { __global = own.sources('option') or {} }
        local e = state.focus and state.focus.entity

        if not e then
            return current
        end

        if e == cache.ped then
            current.selfTarget = own.sources('self')
            return current
        end

        local found = optionsFor(e, GetEntityType(e), GetEntityModel(e))
        current.globalTarget = found.global
        current.model = found.model
        current.entity = found.entity
        current.localEntity = found.localEntity
        return current
    end

    function api.entityHasTargets(entity, entityType, model)
        if not entity or entity == 0 then return false end

        if (own.sources(globalKey(entity, entityType)) or {})[1] then return true end

        for _, opts in ipairs(specific(entity, model)) do
            if opts[1] then return true end
        end

        return false
    end

    function api.entityHasSpecificTargets(entity, model)
        if not entity or entity == 0 then return false end

        for _, opts in ipairs(specific(entity, model)) do
            if opts[1] then return true end
        end

        return false
    end

    ---The nearest distance any option on the entity allows (an option without one counts as 7), at most 7.
    function api.getEntityTargetDistance(entity, entityType, model)
        if not entity or entity == 0 then return 7 end

        local min = 7
        local lists = specific(entity, model)
        lists[#lists + 1] = own.sources(globalKey(entity, entityType)) or {}

        for _, opts in ipairs(lists) do
            for _, o in ipairs(opts) do
                min = math.min(min, o.distance or 7)
            end
        end

        return min
    end

    ---The furthest distance an option on the entity allows, globals left out; 0 when it has none.
    function api.getEntitySpecificTargetDistance(entity, model)
        if not entity or entity == 0 then return 0 end

        local max = 0

        for _, opts in ipairs(specific(entity, model)) do
            for _, o in ipairs(opts) do
                max = math.max(max, o.distance or 7)
            end
        end

        return max
    end

    function api.disableTargeting(off)
        state.disabled[caller()] = off and true or nil
    end

    function api.isActive()
        return state.focus ~= nil
    end

    return api
end

---Answer exports.<resource>:<name> with this layer, its keys scoped to that resource name.
---@param resource string 'ox_target'
---@return table<string, function> the exports answered
function ox.provide(resource)
    local api = build(resource)

    for name, fn in pairs(api) do
        AddEventHandler(('__cfx_export_%s_%s'):format(resource, name), function(setCB) setCB(fn) end)
    end

    return api
end

return ox
