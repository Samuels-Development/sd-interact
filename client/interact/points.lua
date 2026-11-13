---@type table sd-interact config root (configs/config.lua).
local config = require 'configs.config'

-- Every interaction point, and the API other resources register them with (client/main.lua turns
-- these into exports). A point is where a prompt opens: fixed coordinates, an entity (local or by
-- network id) with an offset or a bone, every entity of some models, or every vehicle / ped / object /
-- player. It carries its options and its distances. Points belong to the resource that made them and
-- go when it stops.

---@class InteractOption
---@field label string what it does ("Take Pump Shotgun")
---@field icon? string Font Awesome classes ('fa-solid fa-gun') or a lucide name ('phone')
---@field description? string a second line, shown under the label
---@field hold? integer hold the key this long (ms) instead of pressing it
---@field name? string an id, for removing or updating one option
---@field distance? number this option needs the player closer than the point's interact distance
---@field groups? string|string[]|table<string, integer> jobs / gangs allowed (as ox_target)
---@field canInteract? fun(entity: integer|nil, coords: vector3, args: any, distance: number): boolean, string? (a second value: the label to show now)
---@field onSelect? fun(data: table) called with { id, name, entity, coords, distance, args }
---@field event? string TriggerEvent(event, data)
---@field serverEvent? string TriggerServerEvent(serverEvent, data), the entity as its network id
---@field export? string 'resource.export', called with data
---@field command? string ExecuteCommand(command)
---@field args? any passed through to canInteract and the handler

---@class InteractPoint
---@field id integer
---@field kind 'coords'|'entity'|'net'|'model'|'global'
---@field coords? vector3
---@field entity? integer
---@field netId? integer
---@field models? table<integer, true>
---@field global? 'vehicle'|'ped'|'object'|'player'
---@field offset? vector3 from the entity, in its own space
---@field bone? string|integer
---@field surface boolean with no bone or offset: on the entity where it is nearest the player, not its middle
---@field options InteractOption[]
---@field distance number
---@field interactDistance number
---@field lineOfSight boolean
---@field allowInVehicle boolean
---@field groups? any
---@field name? string
---@field resource string

---@type table Points module; the table returned at end of file.
local points = {}

---@type table<integer, InteractPoint> Every point, by id.
local all = {}
---@type integer
local lastId = 0
---@type integer Bumped on every change to the registry.
points.version = 0

local DEF = config.Interact

---Tidy a list of options: drop anything without a label, keep the rest in order.
---@param list any
---@return InteractOption[]
local function cleanOptions(list)
    local out = {}
    local invalid = 0

    if type(list) ~= 'table' then
        return out
    end

    if list.label then
        list = { list } -- a single option given bare
    end

    for _, o in ipairs(list) do
        if type(o) == 'table' and type(o.label) == 'string' and o.label ~= '' then
            out[#out + 1] = o
        else
            invalid = invalid + 1
        end
    end

    return out, invalid
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

    if type(v) == 'table' and v[1] then
        return vector3(v[1] + 0.0, v[2] + 0.0, (v[3] or 0.0) + 0.0)
    end

    return nil
end

---Make a point from a registration's data table.
---@param kind string
---@param data table
---@param resource string
---@return InteractPoint
local function make(kind, data, resource)
    lastId = lastId + 1
    data = type(data) == 'table' and data or {}

    local options, invalid = cleanOptions(data.options or data)

    if invalid > 0 then
        lib.print.warn(('Resource "%s": skipped %d option(s) with no valid label. Each option needs a text label.')
            :format(resource, invalid))
    end

    local p = {
        id = lastId,
        kind = kind,
        options = options,
        distance = tonumber(data.distance) or DEF.Distance,
        interactDistance = tonumber(data.interactDistance) or DEF.InteractDistance,
        lineOfSight = data.lineOfSight == nil and DEF.LineOfSight or data.lineOfSight == true,
        allowInVehicle = data.allowInVehicle == true,
        offset = vec(data.offset),
        bone = data.bone,
        surface = data.surface == true,
        groups = data.groups,
        name = data.name,
        resource = resource,
    }

    if p.interactDistance > p.distance then
        p.distance = p.interactDistance
    end

    return p
end

---@param p InteractPoint
---@return integer id
local function put(p)
    if #p.options == 0 then
        lib.print.warn(('Resource "%s": skipped a point with no valid options.')
            :format(p.resource))
        return nil
    end

    all[p.id] = p
    points.version = points.version + 1
    return p.id
end

---A point at fixed coordinates.
---@param coords vector3|table
---@param data table { options, distance?, interactDistance?, lineOfSight?, groups?, name? }
---@param resource string
---@return integer|nil id
function points.addCoords(coords, data, resource)
    local c = vec(coords)

    if not c then return nil end

    local p = make('coords', data, resource)
    p.coords = c

    if p.offset then
        p.coords = p.coords + p.offset
    end

    return put(p)
end

---A point on a local (client-side) entity; offset in the entity's own space, or a bone.
---@param entity integer
---@param data table
---@param resource string
---@return integer|nil id
function points.addLocalEntity(entity, data, resource)
    if type(entity) ~= 'number' or entity == 0 then return nil end

    local p = make('entity', data, resource)
    p.entity = entity
    return put(p)
end

---A point on a networked entity, by its network id (it may stream in and out).
---@param netId integer
---@param data table
---@param resource string
---@return integer|nil id
function points.addEntity(netId, data, resource)
    if type(netId) ~= 'number' then return nil end

    local p = make('net', data, resource)
    p.netId = netId
    return put(p)
end

---A point on every entity of these models near the player.
---@param models string|integer|(string|integer)[]
---@param data table
---@param resource string
---@return integer id
function points.addModel(models, data, resource)
    local p = make('model', data, resource)
    p.models = {}

    for _, m in ipairs(type(models) == 'table' and models or { models }) do
        p.models[type(m) == 'string' and joaat(m) or m] = true
    end

    return put(p)
end

---A point on every vehicle / ped / object / other player near the player.
---@param kind 'vehicle'|'ped'|'object'|'player'
---@param data table
---@param resource string
---@return integer id
function points.addGlobal(kind, data, resource)
    local p = make('global', data, resource)
    p.global = kind
    return put(p)
end

---@param id integer
---@return boolean removed
function points.remove(id)
    if not all[id] then return false end

    all[id] = nil
    points.version = points.version + 1
    return true
end

---Remove points matching a test (and, given a name, only those registered under that name).
---@param test fun(p: InteractPoint): boolean
---@param name? string
---@return integer count
local function removeWhere(test, name)
    local n = 0

    for id, p in pairs(all) do
        if test(p) and (name == nil or p.name == name) then
            all[id] = nil
            n = n + 1
        end
    end

    if n > 0 then
        points.version = points.version + 1
    end

    return n
end

function points.removeLocalEntity(entity, name)
    return removeWhere(function(p) return p.kind == 'entity' and p.entity == entity end, name)
end

function points.removeEntity(netId, name)
    return removeWhere(function(p) return p.kind == 'net' and p.netId == netId end, name)
end

function points.removeModel(models, name)
    local set = {}

    for _, m in ipairs(type(models) == 'table' and models or { models }) do
        set[type(m) == 'string' and joaat(m) or m] = true
    end

    return removeWhere(function(p)
        if p.kind ~= 'model' then return false end

        for h in pairs(p.models) do
            if set[h] then return true end
        end

        return false
    end, name)
end

function points.removeGlobal(kind, name)
    return removeWhere(function(p) return p.kind == 'global' and p.global == kind end, name)
end

---Every point a resource made (it stopped).
---@param resource string
---@return integer count
function points.removeResource(resource)
    return removeWhere(function(p) return p.resource == resource end)
end

---Change a point: new options, distances, coords (for a coords point), entity (for a local entity point).
---@param id integer
---@param data table
---@return boolean updated
function points.update(id, data)
    local p = all[id]

    if not p or type(data) ~= 'table' then return false end

    if data.options then
        local options, invalid = cleanOptions(data.options)

        if invalid > 0 then
            lib.print.warn(('Resource "%s": skipped %d option(s) with no valid label while updating point %d.')
                :format(p.resource, invalid, id))
        end

        if #options == 0 then
            lib.print.warn(('Resource "%s": point %d needs at least one valid option. Update skipped.')
                :format(p.resource, id))
            return false
        end

        p.options = options
    end

    if data.distance then
        p.distance = tonumber(data.distance) or p.distance
    end

    if data.interactDistance then
        p.interactDistance = tonumber(data.interactDistance) or p.interactDistance
    end

    if data.lineOfSight ~= nil then
        p.lineOfSight = data.lineOfSight == true
    end

    if p.interactDistance > p.distance then
        p.distance = p.interactDistance
    end

    if data.coords and p.kind == 'coords' then
        p.coords = vec(data.coords) or p.coords
    end

    if type(data.entity) == 'number' and data.entity ~= 0 and p.kind == 'entity' then
        p.entity = data.entity
    end

    if data.groups ~= nil then
        p.groups = data.groups
    end

    points.version = points.version + 1
    return true
end

---@param id integer
---@return InteractPoint|nil
function points.get(id)
    return all[id]
end

---@return table<integer, InteractPoint>
function points.all()
    return all
end

return points
