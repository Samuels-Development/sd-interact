-- Doing what an option does: the same handler fields ox_target options take, so a resource moving from
-- ox_target keeps its option tables. The first of onSelect, export, event, serverEvent, command an
-- option has is the one used. A handler that errors is reported, not allowed to stop the prompt loop.

---@type table Run module; the table returned at end of file.
local run = {}

---@param c InteractCandidate
---@param o InteractOption
---@param p? InteractPoint the point the option is from (a merged prompt has several; default the candidate's)
function run.option(c, o, p)
    p = p or c.point
    local data = {
        id = p.id,
        name = o.name,
        entity = c.entity,
        coords = c.pos,
        distance = c.dist,
        args = o.args,
    }

    local ok, err = pcall(function()
        if o.onSelect then
            o.onSelect(data)
        elseif o.export then
            local res, fn = o.export:match('^(.-)%.(.+)$')

            if res and fn then
                exports[res][fn](nil, data)
            end
        elseif o.event then
            TriggerEvent(o.event, data)
        elseif o.serverEvent then
            -- the server cannot use a client's entity handle: send its network id instead
            local e = data.entity
            data.entity = (e and NetworkGetEntityIsNetworked(e)) and NetworkGetNetworkIdFromEntity(e) or 0
            TriggerServerEvent(o.serverEvent, data)
        elseif o.command then
            ExecuteCommand(o.command)
        end
    end)

    if not ok then
        lib.print.error(('Option "%s" from resource "%s" failed: %s'):format(o.label, p.resource, tostring(err)))
    end
end

return run
