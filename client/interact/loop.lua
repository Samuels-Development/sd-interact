---@type table sd-interact config root (configs/config.lua).
local config = require 'configs.config'
---@type table Points in range and their usable options (client.interact.scan).
local scan = require 'client.interact.scan'
---@type table Which point gets the prompt (client.interact.focus).
local focus = require 'client.interact.focus'
---@type table What the player is looking at (client.interact.state).
local state = require 'client.interact.state'
---@type table The prompt page (client.interact.dui).
local dui = require 'client.interact.dui'
---@type table Controls (client.interact.input).
local input = require 'client.interact.input'

-- Two threads. The scan thread refreshes the candidates a few times a second. The frame thread, only
-- while there are candidates, moves each to where its entity is now, projects it, picks the focused
-- one (checking it can be seen), keeps the prompt page in step and paints the prompt and the dots.

---@type table Loop module; the table returned at end of file.
local loop = {}

local CFG = config.Interact
local DRAW = config.Draw

---@type table<string, { at: integer, clear: boolean }> line-of-sight answers by candidate key
local sight = {}

---Should prompts be hidden altogether right now?
---@param ped integer
---@return boolean
local function hidden(ped)
    if next(state.disabled) then return true end

    if IsPauseMenuActive() then return true end

    if CFG.HideWhenNuiFocused and IsNuiFocused() then return true end

    if CFG.HideWhenDead and IsEntityDead(ped) then return true end

    if CFG.HideWhileAiming and IsPlayerFreeAiming(PlayerId()) then return true end

    return false
end

---Can the camera see this point? A ray from the camera to it, ignoring the point's own entity (a
---prompt on a door is not hidden by the door); a hit just short of the point counts as seeing it.
---@param c InteractCandidate
---@param cam vector3
---@return boolean
local function canSee(c, cam)
    local now = GetGameTimer()
    local s = sight[c.key]

    if s and now - s.at < CFG.LosEveryMs then
        return s.clear
    end

    local p = c.pos
    local ignore = c.entity or cache.ped
    local flags = 1 | 2 | 16 -- map, vehicles, objects
    local handle = StartExpensiveSynchronousShapeTestLosProbe(cam.x, cam.y, cam.z, p.x, p.y, p.z, flags, ignore, 7)
    local _, hit, at = GetShapeTestResult(handle)
    local clear = not (hit == 1 or hit == true) or #(at - p) < 0.2

    sight[c.key] = { at = now, clear = clear }
    return clear
end

---The options as the page shows them.
---@param c InteractCandidate
---@return table[]
local function shown(c)
    local out = {}

    for i, e in ipairs(c.options) do
        local o = e.option
        out[i] = { label = e.label or o.label, icon = o.icon, description = o.description, hold = o.hold }
    end

    return out
end

---@param c InteractCandidate
---@return string a signature of what the prompt shows: re-sent when it changes
local function signature(c)
    local parts = {}

    for i, e in ipairs(c.options) do
        parts[i] = ('%s|%s|%s'):format(e.label or e.option.label, e.option.icon or '', e.option.hold or 0)
    end

    return table.concat(parts, ';')
end

---@type string|nil the signature shown for the focused candidate
local shownSig = nil

-- Motion. The prompt is drawn at `at` (screen 0..1). Opening, it springs out of its point (the page
-- animates); moving to another point it glides there over GlideMs while the label swaps; closing, it
-- keeps being drawn where it was for LeaveMs while the page plays its exit.
---@type { x: number, y: number }|nil
local at = nil
---@type { fx: number, fy: number, t0: integer }|nil a glide in progress, from (fx, fy)
local glide = nil
---@type { key: string, untilAt: integer }|nil the prompt on its way out
local leaving = nil

---@param t number 0..1
---@return number
local function easeOut(t)
    local u = 1 - t
    return 1 - u * u * u
end

local function lose()
    if not state.focus then return end

    input.cancelHold()
    leaving = { key = state.focus.key, untilAt = GetGameTimer() + DRAW.LeaveMs }
    state.focus = nil
    shownSig = nil
    glide = nil
    dui.hide()
end

---@param c InteractCandidate
local function take(c)
    local prev = state.focus
    local same = prev and prev.key == c.key

    if not same then
        input.cancelHold()
        state.selected = 1
    end

    local sig = signature(c)
    state.focus = c

    if same and sig == shownSig then return end

    if state.selected > #c.options then
        state.selected = #c.options
    end

    -- from one point straight to another: glide and swap the label; from nothing: open
    local swap = prev ~= nil and not same and at ~= nil

    if swap then
        glide = { fx = at.x, fy = at.y, t0 = GetGameTimer() }
    elseif not same then
        glide = nil
        at = { x = c.sx, y = c.sy }
    end

    leaving = nil
    dui.show(c.key, shown(c), state.selected, input.hint(), (swap or same) and 'swap' or 'enter')
    shownSig = sig

    if config.Debug then
        lib.print.info(('Showing %s (%d options).'):format(c.key, #c.options))
    end
end

---Where the prompt is drawn this frame.
---@param list InteractCandidate[]
---@return number|nil x, number|nil y
local function placePrompt(list)
    local now = GetGameTimer()
    local c = state.focus

    if c then
        local x, y = c.sx, c.sy

        if glide then
            local t = (now - glide.t0) / DRAW.GlideMs

            if t >= 1 then
                glide = nil
            else
                local e = easeOut(t)
                x, y = glide.fx + (x - glide.fx) * e, glide.fy + (y - glide.fy) * e
            end
        end

        at = { x = x, y = y }
        return x, y
    end

    if not leaving or not at then return nil end

    if now >= leaving.untilAt then
        leaving, at = nil, nil
        return nil
    end

    -- still follow the point it was on, if it is still there
    for _, o in ipairs(list) do
        if o.key == leaving.key and o.onScreen then
            at = { x = o.sx, y = o.sy }
        end
    end

    return at.x, at.y
end

-- Dots: a point in range that is not focused. Hidden near the open prompt and on the same entity as it
-- (a rack's other slots: the prompt follows the eye along the rack), merged where several sit close
-- together on screen, faded in and out rather than switched.
---@type table<string, number> each candidate's dot opacity now (0..1), eased toward where it should be
local dotAlpha = {}

---@param list InteractCandidate[]
---@param px number|nil the prompt's screen position, if one is drawn
---@param py number|nil
---@param dt number seconds since the last frame
local function drawDots(list, px, py, dt)
    local sw, sh = dui.screen()
    local k1080 = sh / 1080.0
    local clear = DRAW.DotClear * k1080
    local merge = DRAW.DotMerge * k1080
    local speed = DRAW.DotFade
    local f = state.focus
    local seen = {}
    local clusters = {}

    for _, c in ipairs(list) do
        seen[c.key] = true
        local want = 0.0

        if c ~= f and c.onScreen then
            want = math.max(0.25, 1.0 - c.dist / c.point.distance)

            if f then
                if f.entity and c.entity == f.entity then
                    want = 0.0
                elseif px and math.abs((c.sx - px) * sw) < clear and math.abs((c.sy - py) * sh) < clear then
                    want = 0.0
                else
                    want = want * 0.6
                end
            end
        end
        local a = dotAlpha[c.key] or 0.0
        a = a + (want - a) * math.min(1.0, dt * speed)
        dotAlpha[c.key] = a

        if a > 0.02 and c.onScreen then
            local x, y = c.sx * sw, c.sy * sh
            local into

            for _, cl in ipairs(clusters) do
                if math.abs(cl.x - x) < merge and math.abs(cl.y - y) < merge then
                    into = cl
                    break
                end
            end

            if into then
                local w = into.w + a
                into.x, into.y = (into.x * into.w + x * a) / w, (into.y * into.w + y * a) / w
                into.w, into.a = w, math.max(into.a, a)
                into.ring = into.ring or c.dist <= c.reach
            else
                clusters[#clusters + 1] = { x = x, y = y, w = a, a = a, ring = c.dist <= c.reach }
            end
        end
    end

    for key in pairs(dotAlpha) do
        if not seen[key] then
            dotAlpha[key] = nil
        end
    end

    for _, cl in ipairs(clusters) do
        dui.dot(cl.x / sw, cl.y / sh, cl.ring, cl.a)
    end
end

local function scanThread()
    local pruned = 0

    while true do
        local ped = cache.ped

        if hidden(ped) then
            scan.candidates = {}
        else
            scan.run(ped, cache.vehicle ~= false and cache.vehicle ~= nil)
        end

        -- line-of-sight answers for points long gone
        local now = GetGameTimer()

        if now - pruned > 5000 then
            pruned = now

            for k, s in pairs(sight) do
                if now - s.at > 5000 then
                    sight[k] = nil
                end
            end
        end

        Wait(CFG.ScanEveryMs)
    end
end

local function frameThread()
    local lastDevice = 0

    while true do
        local list = scan.candidates

        if #list == 0 and not leaving and not next(dotAlpha) then
            lose()
            Wait(120)
        else
            local ped = cache.ped
            local from = GetEntityCoords(ped)
            local cam = GetFinalRenderedCamCoord()
            local aspect = dui.aspect()

            -- where each is this frame
            for _, c in ipairs(list) do
                if c.entity and DoesEntityExist(c.entity) then
                    c.pos = scan.anchor(c.point, c.entity)
                end

                c.dist = #(c.pos - from)
                local on, sx, sy = GetScreenCoordFromWorldCoord(c.pos.x, c.pos.y, c.pos.z)
                c.onScreen = on == 1 or on == true
                c.sx, c.sy = sx, sy
                c.blocked = nil
            end

            -- who gets the prompt (the first pick hidden behind something gives way to the next)
            local current = state.focus and state.focus.key
            local pick = focus.choose(list, current, aspect, CFG.FocusRadius, CFG.Stickiness)

            for _ = 1, 3 do
                if not pick or not pick.point.lineOfSight or canSee(pick, cam) then break end

                pick.blocked = true
                pick = focus.choose(list, current, aspect, CFG.FocusRadius, CFG.Stickiness)
            end

            if pick then
                take(pick)
            else
                lose()
            end

            -- which device the player is on (the key glyph follows it)
            local now = GetGameTimer()

            if now - lastDevice > 250 then
                lastDevice = now
                local device = IsUsingKeyboard(2) and 'keyboard' or 'pad'

                if device ~= state.device then
                    state.device = device

                    if state.focus then
                        dui.key(input.hint())
                    end
                end
            end

            local px, py = placePrompt(list)

            if px then
                dui.draw(px, py)
            end

            if state.focus and #state.focus.options > 1 then
                input.block()
            end

            if DRAW.Dots then
                drawDots(list, px, py, GetFrameTime())
            end

            if config.Debug then
                for _, c in ipairs(list) do
                    DrawMarker(
                        28,
                        c.pos.x, c.pos.y, c.pos.z,
                        0, 0, 0,
                        0, 0, 0,
                        0.02, 0.02, 0.02,
                        255, 80, 80, 200,
                        false, false, 2, false, nil, nil, false
                    )
                end
            end

            Wait(0)
        end
    end
end

function loop.start()
    CreateThread(scanThread)
    CreateThread(frameThread)
end

---The prompt currently open, for other resources (exports.getFocus).
---@return table|nil
function loop.focused()
    local c = state.focus

    if not c then return nil end

    return { id = c.point.id, entity = c.entity, coords = c.pos, option = state.selected }
end

return loop
