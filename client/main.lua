---@type table sd-interact config root (configs/config.lua).
local config = require 'configs.config'
lib.locale(config.Locale) -- before input registers its key-mapping descriptions

---@type table Every interaction point and the registration API (client.interact.points).
local points = require 'client.interact.points'
---@type table What the player is looking at (client.interact.state).
local state = require 'client.interact.state'
---@type table The prompt page (client.interact.dui).
local dui = require 'client.interact.dui'
---@type table Controls (client.interact.input).
local input = require 'client.interact.input'
---@type table The scan and frame threads (client.interact.loop).
local loop = require 'client.interact.loop'

input.register()

-- Standing in for other target resources (configs/client/replace.lua): their exports answered with
-- prompts, so scripts written for them work unchanged. Only for the names turned on there: the real
-- resource must be gone, as two resources answering one export would fight.
do
    ---@type table ox_target's API (client.compat.ox_target).
    local ox = require 'client.compat.ox_target'
    ---@type table qb-target's / qtarget's API (client.compat.qb_target).
    local qb = require 'client.compat.qb_target'
    local layers = { ox_target = ox, qtarget = qb, ['qb-target'] = qb }
    local warning = 'Can’t replace %s while resource "%s" is running. '
        .. 'Stop the real %s resource or remove it from server.cfg.'

    for name, on in pairs(config.Replace) do
        local layer = layers[name]

        if on and layer then
            -- Turning Replace on is the owner saying "that resource is gone": answer its exports. A name
            -- can still report as started without the real thing running (our own `provide`, an empty
            -- stand-in that only satisfies dependencies, or a server that started the old entry of a moved
            -- folder), so this only warns, and not for a stand-in that says it is one.
            local st = GetResourceState(name)
            local started = st == 'started' or st == 'starting'
            local ours = GetResourceMetadata(name, 'name', 0) == GetCurrentResourceName()
                or GetResourceMetadata(name, 'sd_interact_stand_in', 0) == 'yes'

            if started and not ours then
                lib.print.warn(warning:format(name, name, name))
            end

            layer.provide(name)
            lib.print.info(('Using %s compatibility exports.'):format(name))
        end
    end
end

CreateThread(function()
    dui.ensure()
    loop.start()

    -- a changed resolution gets a new page at the new size
    while true do
        Wait(3000)
        dui.ensure()
    end
end)

-- The API. Every add* returns the point's id; a point belongs to the resource that made it and is
-- removed when that resource stops. docs: README.md.
local function caller() return GetInvokingResource() or GetCurrentResourceName() end

exports('addCoords', function(coords, data) return points.addCoords(coords, data, caller()) end)
exports('addLocalEntity', function(entity, data) return points.addLocalEntity(entity, data, caller()) end)
exports('addEntity', function(netId, data) return points.addEntity(netId, data, caller()) end)
exports('addModel', function(models, data) return points.addModel(models, data, caller()) end)
exports('addGlobalVehicle', function(data) return points.addGlobal('vehicle', data, caller()) end)
exports('addGlobalPed', function(data) return points.addGlobal('ped', data, caller()) end)
exports('addGlobalPlayer', function(data) return points.addGlobal('player', data, caller()) end)
exports('addGlobalObject', function(data) return points.addGlobal('object', data, caller()) end)

exports('remove', function(id) return points.remove(id) end)
exports('removeLocalEntity', function(entity, name) return points.removeLocalEntity(entity, name) end)
exports('removeEntity', function(netId, name) return points.removeEntity(netId, name) end)
exports('removeModel', function(models, name) return points.removeModel(models, name) end)
exports('removeGlobalVehicle', function(name) return points.removeGlobal('vehicle', name) end)
exports('removeGlobalPed', function(name) return points.removeGlobal('ped', name) end)
exports('removeGlobalPlayer', function(name) return points.removeGlobal('player', name) end)
exports('removeGlobalObject', function(name) return points.removeGlobal('object', name) end)
exports('update', function(id, data) return points.update(id, data) end)

---Switch every prompt off (true) or back on (false) for the calling resource: a minigame, a cutscene.
---Prompts show again once no resource has them switched off.
exports('disable', function(off)
    local res = caller()
    state.disabled[res] = off and true or nil
end)

exports('getFocus', function() return loop.focused() end)

AddEventHandler('onClientResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        dui.destroy()
        return
    end

    points.removeResource(resource)
    state.disabled[resource] = nil
    require('client.compat.book').prune()
end)
