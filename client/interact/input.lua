---@type table sd-interact config root (configs/config.lua).
local config = require 'configs.config'
---@type table What the player is looking at (client.interact.state).
local state = require 'client.interact.state'
---@type table The prompt page (client.interact.dui).
local dui = require 'client.interact.dui'
---@type table Option handlers (client.interact.run).
local run = require 'client.interact.run'

-- The controls, as FiveM key mappings: every player can rebind them (Settings > Key Bindings > FiveM),
-- on keyboard and on a pad separately. Confirm is a +/- pair so an option can be held: press starts
-- the hold (the ring fills), release before it is full cancels it. Next / previous move the drum.
-- Nothing here acts unless a prompt is open.

---@type table Input module; the table returned at end of file.
local input = {}

local KEYS = config.Controls

---The key or pad button that confirms, as the player is playing now: the bound key's own name on
---keyboard (read back from the key mapping, so a rebind shows), the configured button's glyph on a pad.
---@return table { device, key }
function input.hint()
    if state.device == 'pad' then
        return { device = 'pad', key = KEYS.Pad }
    end

    local text = GetControlInstructionalButton(0, joaat('+sd_interact') | 0x80000000, true)

    if type(text) == 'string' and text:sub(1, 2) == 't_' then
        text = text:sub(3)
    else
        text = KEYS.Key
    end

    return { device = 'keyboard', key = text }
end

---Stop a hold in progress (released early, or the prompt went away).
function input.cancelHold()
    if state.holding then
        state.holding = nil
        dui.release()
    end
end

---@param c InteractCandidate
---@param entry { option: InteractOption, point: InteractPoint } the option picked, and the point it is from
local function confirmed(c, entry)
    dui.confirm()
    run.option(c, entry.option, entry.point)
end

local function press()
    local c = state.focus

    if not c then return end

    local entry = c.options[state.selected]

    if not entry then return end

    local o = entry.option

    if not (o.hold and o.hold > 0) then
        confirmed(c, entry)
        return
    end

    local h = { key = c.key, index = state.selected, option = o, started = GetGameTimer(), ms = o.hold }
    state.holding = h
    dui.hold(o.hold)

    CreateThread(function()
        while state.holding == h do
            if GetGameTimer() - h.started >= h.ms then
                state.holding = nil
                local f = state.focus

                -- (still the same option: a merged prompt's list can change while it is held)
                local e = f and f.key == h.key and state.selected == h.index and f.options[h.index]

                if e and e.option == h.option then
                    confirmed(f, e)
                end

                return
            end

            Wait(0)
        end
    end)
end

local function release()
    input.cancelHold()
end

---@param step integer +1 next, -1 previous
local function move(step)
    local c = state.focus

    if not c or #c.options < 2 then return end

    local n = math.max(1, math.min(#c.options, state.selected + step))

    if n ~= state.selected then
        input.cancelHold()
        state.selected = n
        dui.select(n)
    end
end

---Register the commands and their default bindings.
function input.register()
    RegisterCommand('+sd_interact', press, false)
    RegisterCommand('-sd_interact', release, false)
    RegisterCommand('+sd_interact_pad', function()
        state.device = 'pad'
        press()
    end, false)
    RegisterCommand('-sd_interact_pad', release, false)
    RegisterCommand('sd_interact_next', function() move(1) end, false)
    RegisterCommand('sd_interact_prev', function() move(-1) end, false)
    RegisterCommand('+sd_interact_next_pad', function() move(1) end, false)
    RegisterCommand('-sd_interact_next_pad', function() end, false)
    RegisterCommand('+sd_interact_prev_pad', function() move(-1) end, false)
    RegisterCommand('-sd_interact_prev_pad', function() end, false)

    RegisterKeyMapping('+sd_interact', locale('keymap.interact'), 'keyboard', KEYS.Key)
    RegisterKeyMapping('sd_interact_next', locale('keymap.next'), 'MOUSE_WHEEL', KEYS.Next)
    RegisterKeyMapping('sd_interact_prev', locale('keymap.prev'), 'MOUSE_WHEEL', KEYS.Prev)
    RegisterKeyMapping('+sd_interact_pad', locale('keymap.interact_pad'), 'PAD_DIGITALBUTTON', KEYS.Pad)
    RegisterKeyMapping('+sd_interact_next_pad', locale('keymap.next_pad'), 'PAD_DIGITALBUTTON', KEYS.PadNext)
    RegisterKeyMapping('+sd_interact_prev_pad', locale('keymap.prev_pad'), 'PAD_DIGITALBUTTON', KEYS.PadPrev)
end

---Each frame a prompt with more than one option is open: the wheel and the D-pad pick options, so the
---game must not also switch weapons, open the phone or change the radio.
function input.block()
    for _, c in ipairs(KEYS.Block) do
        DisableControlAction(0, c, true)
    end
end

return input
