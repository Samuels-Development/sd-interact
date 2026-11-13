---@type table Every interaction point (client.interact.points).
local points = require 'client.interact.points'
---@type table What the player is looking at (client.interact.state).
local state = require 'client.interact.state'
---@type table Option conversion (client.compat.convert).
local convert = require 'client.compat.convert'
---@type table Which points each call made (client.compat.book).
local book = require 'client.compat.book'

-- qb-target's (and qtarget's: the same API) client exports, answered by sd-interact. Registered only
-- when turned on (configs/client/replace.lua), once per name, each with keys of its own. Modelled on
-- qb-target 5.5.0. Zones are points at their middle; entities, models, bones and the globals are points
-- on the entity (on the bone for AddTargetBone). As in qb-target, options are kept by label: one added
-- again under its label replaces the old one, and removing is by label.

---@type table Qb module; the table returned at end of file.
local qb = {}

---qb-target's Config.MaxDistance default: a call without `distance` caps its options to this.
local MAX_DISTANCE = 7.0

local function caller() return GetInvokingResource() or GetCurrentResourceName() end

local function list(v) return type(v) == 'table' and v or { v } end

---@param params table { options = {...}, distance = 2.5 }
---@return table[] options, number reach
local function convertAll(params)
    params = type(params) == 'table' and params or {}
    local maxDistance = tonumber(params.distance) or MAX_DISTANCE
    local opts = {}

    for _, o in ipairs(list(params.options or {})) do
        local c = convert.qb(o, maxDistance)

        if c then
            opts[#opts + 1] = c
        end
    end

    local reach = math.min(tonumber(params.distance) or convert.reach(opts, 3.0), 5.0)
    return opts, reach
end

---The registration data for a point with these options. On an entity, qb-target measures to where
---the aim hits it, so the prompt sits where the entity is nearest the player (`surface`).
---@param opts table[]
---@param reach number
---@return table
local function pointData(opts, reach)
    return { options = opts, interactDistance = reach, distance = reach + 3.0, surface = true }
end

---@param opts table|nil qb zone options { minZ, maxZ }
---@param z number
---@return number the zone's middle height
local function midZ(opts, z)
    if type(opts) == 'table' and opts.minZ and opts.maxZ then
        return (opts.minZ + opts.maxZ) / 2
    end

    return z
end

---The exports for one name sd-interact answers as. Every key it books is scoped to that name.
---@param name string 'qb-target' or 'qtarget'
---@return table<string, function>
local function build(name)
    local api = {}
    local own = book.scope(name)

    ---Book new points under a key, first dropping options there with the same labels.
    ---@param key string
    ---@param opts table[] converted options
    ---@param add fun(): integer|nil makes the point
    local function addOn(key, opts, add)
        local labels = {}

        for _, o in ipairs(opts) do
            labels[#labels + 1] = o.label
        end

        if labels[1] then
            own.remove(key, labels, 'label')
        end

        own.add(key, add())
    end

    ---@param zoneName string
    ---@param centre vector3
    ---@param half number
    ---@param params table
    local function zone(zoneName, centre, half, params)
        local opts, reach = convertAll(params)
        local key = 'zone:' .. tostring(zoneName)

        own.remove(key) -- a zone added again under its name replaces the old one, as in qb-target

        reach = math.min(reach + math.min(half, 1.5), 5.5)
        own.add(key, points.addCoords(centre, pointData(opts, reach), caller()))
        return zoneName
    end

    function api.AddBoxZone(zoneName, center, length, width, zoneOptions, targetoptions)
        local centre = vector3(center.x, center.y, midZ(zoneOptions, center.z))
        return zone(zoneName, centre, math.max(length or 1, width or 1) / 2, targetoptions)
    end

    function api.AddCircleZone(zoneName, center, radius, zoneOptions, targetoptions)
        return zone(zoneName, vector3(center.x, center.y, center.z), tonumber(radius) or 1.0, targetoptions)
    end

    function api.AddPolyZone(zoneName, pts, zoneOptions, targetoptions)
        local sx, sy, n = 0.0, 0.0, 0
        local minx, maxx, miny, maxy = math.huge, -math.huge, math.huge, -math.huge

        for _, p in ipairs(pts or {}) do
            sx, sy, n = sx + p.x, sy + p.y, n + 1
            minx = math.min(minx, p.x)
            maxx = math.max(maxx, p.x)
            miny = math.min(miny, p.y)
            maxy = math.max(maxy, p.y)
        end

        if n == 0 then return nil end

        local centre = vector3(sx / n, sy / n, midZ(zoneOptions, 0.0))
        return zone(zoneName, centre, math.max(maxx - minx, maxy - miny) / 2, targetoptions)
    end

    function api.AddComboZone(zones, zoneOptions, targetoptions)
        -- a combo of PolyZones: one point at the first zone's middle is the closest honest stand-in
        local first = type(zones) == 'table' and zones[1]
        local c = first and (first.getBoundingBoxCenter and first:getBoundingBoxCenter() or first.center)

        if not c then return nil end

        local zoneName = (zoneOptions and zoneOptions.name) or ('combo_%d'):format(GetGameTimer())
        return zone(zoneName, vector3(c.x, c.y, c.z or 0.0), 1.0, targetoptions)
    end

    function api.AddEntityZone(zoneName, entity, zoneOptions, targetoptions)
        local opts, reach = convertAll(targetoptions)
        local key = 'zone:' .. tostring(zoneName)

        own.remove(key)
        own.add(key, points.addLocalEntity(entity, pointData(opts, reach), caller()))
        return zoneName
    end

    function api.RemoveZone(zoneName)
        own.remove('zone:' .. tostring(zoneName))
    end

    function api.AddTargetEntity(entities, params)
        local opts, reach = convertAll(params)
        local res = caller()

        for _, e in ipairs(list(entities)) do
            addOn(('local:%d'):format(e), opts, function()
                return points.addLocalEntity(e, pointData(opts, reach), res)
            end)
        end
    end

    function api.RemoveTargetEntity(entities, labels)
        for _, e in ipairs(list(entities)) do
            own.remove(('local:%d'):format(e), labels, 'label')
        end
    end

    function api.AddTargetModel(models, params)
        local opts, reach = convertAll(params)
        local res = caller()

        for _, m in ipairs(list(models)) do
            local h = type(m) == 'string' and joaat(m) or m

            addOn(('model:%d'):format(h), opts, function()
                return points.addModel({ h }, pointData(opts, reach), res)
            end)
        end
    end

    function api.RemoveTargetModel(models, labels)
        for _, m in ipairs(list(models)) do
            own.remove(('model:%d'):format(type(m) == 'string' and joaat(m) or m), labels, 'label')
        end
    end

    function api.AddTargetBone(bones, params)
        local opts, reach = convertAll(params)
        local res = caller()

        for _, b in ipairs(list(bones)) do
            addOn('bone:' .. b, opts, function()
                local data = pointData(opts, reach)
                data.bone, data.surface = b, false
                return points.addGlobal('vehicle', data, res)
            end)
        end
    end

    function api.RemoveTargetBone(bones, labels)
        for _, b in ipairs(list(bones)) do
            own.remove('bone:' .. b, labels, 'label')
        end
    end

    for _, kind in ipairs({ 'Ped', 'Vehicle', 'Object', 'Player' }) do
        local g = kind:lower()

        api['AddGlobal' .. kind] = function(params)
            local opts, reach = convertAll(params)
            local res = caller()

            addOn('global:' .. g, opts, function()
                return points.addGlobal(g, pointData(opts, reach), res)
            end)
        end

        api['RemoveGlobal' .. kind] = function(labels) own.remove('global:' .. g, labels, 'label') end
    end

    function api.AllowTargeting(on)
        state.disabled[caller()] = (on == false) and true or nil
    end

    function api.IsTargetActive()
        return state.focus ~= nil
    end

    function api.IsTargetSuccess()
        return state.focus ~= nil
    end

    return api
end

---Answer exports.<resource>:<name> with this layer, its keys scoped to that resource name.
---@param resource string 'qb-target' or 'qtarget'
---@return table<string, function> the exports answered
function qb.provide(resource)
    local api = build(resource)

    for name, fn in pairs(api) do
        AddEventHandler(('__cfx_export_%s_%s'):format(resource, name), function(setCB) setCB(fn) end)
    end

    return api
end

return qb
