-- What the player is looking at right now, shared by the frame loop (which sets it) and the input
-- (which acts on it).

---@class InteractState
---@field focus InteractCandidate|nil the candidate with the prompt open
---@field selected integer 1-based, into focus.options
---@field holding table|nil { key, index, option, started, ms } while a hold is under way
---@field disabled table<string, true> resources that have switched prompts off (exports.disable)
---@field device string 'keyboard'|'pad', what the player last used

---@type InteractState
local state = {
    focus = nil,
    selected = 1,
    holding = nil,
    disabled = {},
    device = 'keyboard',
}

return state
