-- Offline checks of sd-interact's pure parts under stock Lua 5.4: which point takes focus, the point
-- registry, and the stand-in layers (option conversion, handler data, the ox_target / qtarget exports).
-- Run from the resource folder:  lua tests/run.lua
package.path = './?.lua;./?/init.lua;' .. package.path

-- just enough of FiveM for the registry
local function vec(x, y, z)
    return setmetatable({ x = x, y = y, z = z }, {
        __add = function(a, b) return vec(a.x + b.x, a.y + b.y, a.z + b.z) end,
        __sub = function(a, b) return vec(a.x - b.x, a.y - b.y, a.z - b.z) end,
        __len = function(a) return math.sqrt(a.x * a.x + a.y * a.y + a.z * a.z) end,
    })
end

vector3 = vec

local realType = type

type = function(v) -- FiveM reports its vectors as 'vector3'
    if realType(v) == 'table' and getmetatable(v) and v.x and v.z then
        return 'vector3'
    end

    return realType(v)
end

joaat = function(s)
    local h = 0

    for i = 1, #s do
        h = (h * 31 + s:byte(i)) % 4294967296
    end

    return h
end

local pass, fail = 0, 0

local function check(name, ok)
    if ok then
        pass = pass + 1
    else
        fail = fail + 1
        print('FAIL ' .. name)
    end
end

local focus = dofile('client/interact/focus.lua')
local A = 16 / 9

local function cand(key, sx, sy, dist, reach)
    return { key = key, onScreen = true, sx = sx, sy = sy, dist = dist, reach = reach or 1.8 }
end

-- the one nearest the middle wins
local l = { cand('a', 0.62, 0.5, 1.0), cand('b', 0.52, 0.5, 1.2) }
check('nearest the centre', focus.choose(l, nil, A, 0.22, 0.03).key == 'b')
-- out of reach: not eligible
l = { cand('a', 0.5, 0.5, 2.5, 1.8) }
check('out of reach', focus.choose(l, nil, A, 0.22, 0.03) == nil)
-- too far off centre
l = { cand('a', 0.95, 0.5, 1.0) }
check('off centre', focus.choose(l, nil, A, 0.22, 0.03) == nil)
-- stickiness: the held one keeps focus against a slightly better one
l = { cand('a', 0.53, 0.5, 1.0), cand('b', 0.515, 0.5, 1.0) }
check('sticky keeps', focus.choose(l, 'a', A, 0.22, 0.03).key == 'a')
check('without hold, better wins', focus.choose(l, nil, A, 0.22, 0.03).key == 'b')
-- but not against a clearly better one
l = { cand('a', 0.68, 0.5, 1.0), cand('b', 0.5, 0.5, 1.0) }
check('sticky gives way', focus.choose(l, 'a', A, 0.22, 0.03).key == 'b')
-- blocked is skipped
l = { cand('a', 0.5, 0.5, 1.0), cand('b', 0.56, 0.5, 1.0) }
l[1].blocked = true
check('blocked skipped', focus.choose(l, nil, A, 0.22, 0.03).key == 'b')
-- off screen
l = { cand('a', 0.5, 0.5, 1.0) }
l[1].onScreen = false
check('off screen', focus.choose(l, nil, A, 0.22, 0.03) == nil)
-- vertical offset is aspect corrected (a point as far up as one is to the side is nearer)
l = { cand('side', 0.6, 0.5, 1.0), cand('up', 0.5, 0.4, 1.0) }
check('aspect corrected', focus.choose(l, nil, A, 0.22, 0.03).key == 'up')

-- ox_lib's printer. Warnings are counted, so the registry's can be checked.
local warned = 0
local libPrint = { info = function() end, error = function() end, warn = function() warned = warned + 1 end }
lib = { print = libPrint }

-- the registry
package.loaded['configs.config'] = { Interact = { Distance = 5.0, InteractDistance = 1.8, LineOfSight = true } }
local points = dofile('client/interact/points.lua')

local id = points.addCoords(vec(1, 2, 3), {
    options = { { label = 'Open' }, { icon = 'x' }, { label = 'Close', hold = 800 } },
}, 'res_a')
local p = points.get(id)
check('coords point made', p and p.kind == 'coords' and #p.options == 2)
check('unlabelled option dropped', p.options[2].label == 'Close')
check('unlabelled option warned', warned == 1)
check('defaults', p.distance == 5.0 and p.interactDistance == 1.8 and p.lineOfSight == true)

local id2 = points.addCoords({ x = 0, y = 0, z = 0 }, {
    label = 'Bare option',
    distance = 1.0,
    interactDistance = 3.0,
}, 'res_b')
local p2 = points.get(id2)
check('bare option accepted', #p2.options == 1)
check('show distance covers interact distance', p2.distance == 3.0)

local eid = points.addLocalEntity(123, {
    options = { { label = 'Use' } },
    offset = { 0, 0, 1 },
    name = 'door',
}, 'res_a')
check('entity point', points.get(eid).entity == 123 and points.get(eid).offset.z == 1)

local keptOther = points.removeLocalEntity(123, 'other') == 0
check('remove by entity + name', keptOther and points.removeLocalEntity(123, 'door') == 1)

local mid = points.addModel({ 'prop_a', 'prop_b' }, { options = { { label = 'Sit' } } }, 'res_b')
check('model hashes', points.get(mid).models[joaat('prop_a')] == true)

local updated = points.update(id, { options = { { label = 'Only' } }, interactDistance = 2.5 })
check('update', updated and #points.get(id).options == 1)

points.update(id, { interactDistance = 8.0 })
check('update keeps the point in range', points.get(id).distance == 8.0)

local v0 = points.version
points.removeResource('res_b')
check('resource cleanup', points.get(id2) == nil and points.get(mid) == nil and points.get(id) ~= nil)
check('version bumped', points.version > v0)
check('bad coords refused', points.addCoords('nope', {}, 'res_a') == nil)

warned = 0
check('point with no valid option refused', points.addCoords(vec(0, 0, 0), {
    options = { { icon = 'x' }, { label = '' } },
}, 'res_a') == nil and warned == 2)
check('update with no valid option refused', points.update(id, { options = { { label = '' } } }) == false
    and points.get(id).options[1].label == 'Only')

-- the stand-in layer: option conversion and removing by name
local job = { name = 'police', grade = 2 }

package.loaded['client.interact.groups'] = {
    allowed = function(want)
        if want == nil then return true end

        if type(want) == 'string' then
            return want == job.name
        end

        if want[1] then
            for _, n in ipairs(want) do
                if n == job.name then return true end
            end

            return false
        end

        return want[job.name] ~= nil and job.grade >= want[job.name]
    end,
}

GetResourceState = function() return 'missing' end
NetworkGetEntityIsNetworked = function(e) return e == 55 end
NetworkGetNetworkIdFromEntity = function() return 900 end
GetEntityBoneIndexByName = function() return 12 end
GetEntityCoords = function(e) return 'coords of ' .. e end

local events = {}
TriggerEvent = function(name, data) events[#events + 1] = { name, data } end

local served
TriggerServerEvent = function(name, data) served = { name, data } end

local called
exports = setmetatable({}, {
    __index = function(_, res)
        return setmetatable({}, {
            __index = function(_, fn) return function(_, data) called = { res, fn, data } end end,
        })
    end,
})

package.loaded['client.interact.points'] = points
local convert = dofile('client/compat/convert.lua')

local got
local ox = convert.ox({
    name = 'a',
    label = 'Open',
    canInteract = function(e, d, c, n, b)
        got = { e, d, c, n, b }
        return true
    end,
    onSelect = function(data) got = data end,
}, 'res_x', 7, 'door_dside_f')

local allowed = ox.canInteract(55, 'C', nil, 1.5)
local order = allowed and got[1] == 55 and got[2] == 1.5 and got[3] == 'C' and got[4] == 'a'
check('ox canInteract order (entity, distance, coords, name, bone index)', order and got[5] == 12)

ox.onSelect({ entity = 55, coords = 'C', distance = 1.5, name = 'a' })
check('ox onSelect gets zone', got.zone == 7 and got.entity == 55)

local gated = convert.ox({ label = 'Cuff', groups = { police = 3 } }, 'res_x')
check('ox groups grade', gated.canInteract(1, 'C', nil, 1) == false)

local qbo = convert.qb({ label = 'Open stash', type = 'client', event = 'stash:open', job = 'police', extra = 9 }, 7.0)
check('qb job passes', qbo.canInteract(1, 'C', nil, 1) == true)

qbo.onSelect({ entity = 3, coords = 'C', distance = 1 })
local last = events[#events]
check('qb client event with the option', last[1] == 'stash:open' and last[2].extra == 9 and last[2].entity == 3)

local acted
local qba = convert.qb({ label = 'Rob', gang = 'ballas', action = function(e) acted = e end }, 7.0)
check('qb gang refused', qba.canInteract(1, 'C', nil, 1) == false)

qba.onSelect({ entity = 42 })
check('qb action(entity)', acted == 42)

local groupsOut = convert.oxAnchored({
    { label = 'A' },
    { label = 'B', bones = { 'b1', 'b2' } },
    { label = 'C', offset = vec(0, 0, 1) },
}, 'res_x')
local anchored = #groupsOut == 4 and #groupsOut[1].options == 1
check('ox anchors: plain, two bones, offset', anchored and groupsOut[2].bone == 'b1')

local book = dofile('client/compat/book.lua')
local pid = points.addCoords(vec(0, 0, 0), {
    options = { { label = 'Keep', name = 'k' }, { label = 'Drop', name = 'd' } },
}, 'res_c')
book.add('zone:1', pid)
book.remove('zone:1', { 'd' }, 'name')
check('remove by option name', #points.get(pid).options == 1 and points.get(pid).options[1].name == 'k')

book.remove('zone:1', 'Keep', 'label')
check('remove last option removes the point', points.get(pid) == nil and not book.has('zone:1'))

-- fix 1: an ox_target handler gets what ox_target's getResponse builds: the option copied, the target's
-- entity / zone / coords / distance set on it, handlers and gates taken off
convert.ox({
    name = 'search',
    label = 'Search',
    icon = 'fa-solid fa-box',
    groups = 'police',
    event = 'bin:search',
    args = { bin = 3 },
    custom = 'kept',
}, 'res_x', 4).onSelect({ coords = 'C', distance = 1.2, name = 'search' })
local r = events[#events][2]
check('ox handler data: the option, copied', r.args.bin == 3 and r.custom == 'kept' and r.label == 'Search')
check('ox handler data: handlers and gates taken off', r.icon == nil and r.groups == nil and r.event == nil)
check('ox handler data: target fields', r.entity == 0 and r.zone == 4 and r.coords == 'C' and r.distance == 1.2)

convert.ox({ label = 'Tow', serverEvent = 'tow:hook' }, 'res_x').onSelect({ entity = 55, coords = 'C', distance = 2 })
check('ox server event: the entity as its network id', served[1] == 'tow:hook' and served[2].entity == 900)

local flagged
convert.ox({ label = 'Q', qtarget = true, onSelect = function(v) flagged = v end }, 'res_x').onSelect({ entity = 31 })
check('ox option flagged qtarget: onSelect gets the entity', flagged == 31)

-- fix 1, qb side: the handler gets the option as qb-target stores it, with the hit entity's coords
local qbStored = convert.qb({
    label = 'Pick',
    type = 'client',
    event = 'door:pick',
    distance = 9.0,
    required_item = 'lockpick',
}, 2.5)
qbStored.onSelect({ entity = 8, coords = 'C', distance = 1.1 })
local q = events[#events][2]
check('qb handler data: distance capped, required_item as item', q.distance == 2.5 and q.item == 'lockpick')
check('qb handler data: entity and its coords', q.entity == 8 and q.coords == 'coords of 8' and q.required_item == nil)

-- fix 2: `export` is an export name on the resource that registered the option
convert.ox({ label = 'Open', export = 'openStash' }, 'res_x').onSelect({ entity = 5, coords = 'C', distance = 1 })
local exported = called[1] == 'res_x' and called[2] == 'openStash'
check('ox export: on the registering resource', exported and called[3].entity == 5)

convert.ox({ label = 'Open', export = 'other.openStash' }, 'res_x').onSelect({ entity = 5 })
check('ox export: "res.name" is not split, as in ox_target', called[1] == 'res_x' and called[2] == 'other.openStash')

-- the stand-in layers, as two resources would call them
local invoker = 'res_t'
GetInvokingResource = function() return invoker end
GetCurrentResourceName = function() return 'sd-interact' end
AddEventHandler = function() end

local onPed
lib = { print = libPrint, onCache = function(key, fn) if key == 'ped' then onPed = fn end end }
cache = { ped = 77 }
IsPedAPlayer = function(e) return e == 77 end

local pitch = 0.0
GetGameplayCamRelativePitch = function() return pitch end

package.loaded['client.compat.convert'] = convert
package.loaded['client.compat.book'] = book
local oxApi = dofile('client/compat/ox_target.lua').provide('ox_target')
local qtApi = dofile('client/compat/qb_target.lua').provide('qtarget')

-- fix 3: the ox_target exports that were missing
oxApi.addSelfTarget({ name = 'id', label = 'Show ID' })
local selfId = book.ids('ox_target|self')[1]
local sp = points.get(selfId)
check('ox addSelfTarget: a point on the player ped', sp and sp.kind == 'entity' and sp.entity == 77)

local idle = sp.options[1].canInteract(77, 'C', nil, 0.2)
pitch = -45.0
local lookingDown = sp.options[1].canInteract(77, 'C', nil, 0.2)
check('ox self target opens only looking down at yourself', idle == false and lookingDown)

onPed(78)
check('ox self target follows the ped', points.get(selfId).entity == 78)

oxApi.removeSelfTarget('id')
check('ox removeSelfTarget by name', points.get(selfId) == nil)

local binHash = joaat('prop_bin')
oxApi.addModel('prop_bin', { { name = 'search', label = 'Search', distance = 2.0 } })
local has = oxApi.entityHasTargets(500, 3, binHash) and oxApi.entityHasSpecificTargets(500, binHash)
check('ox entityHasTargets / entityHasSpecificTargets', has and not oxApi.entityHasSpecificTargets(500, joaat('x')))

local listed = oxApi.getTargetOptions(500, 3, binHash)
local first = listed.model[1]
check('ox getTargetOptions: the option tables', first.label == 'Search' and first.resource == 'res_t')

local near = oxApi.getEntityTargetDistance(500, 3, binHash)
check('ox target distances', near == 2.0 and oxApi.getEntitySpecificTargetDistance(500, binHash) == 2.0)

GetEntityType = function() return 3 end
GetEntityModel = function() return binHash end
require('client.interact.state').focus = { entity = 500 }
check('ox getTargetOptions(): the open prompt', oxApi.getTargetOptions().model[1].label == 'Search')

oxApi.addModel('prop_bin', { { name = 'search', label = 'Search again' } })
local again = oxApi.getTargetOptions(500, 3, binHash).model
check('ox: an option added again under its name replaces it', #again == 1 and again[1].label == 'Search again')

invoker = 'res_u'
oxApi.removeModel('prop_bin', 'search')
invoker = 'res_t'
check('ox: removing by name only touches the calling resource', oxApi.entityHasSpecificTargets(500, binHash))

local zoneId = oxApi.addSphereZone({ coords = vec(1, 1, 1), radius = 1.0, options = { label = 'Bare' } })
local zp = points.get(book.ids('ox_target|zone:' .. zoneId)[1])
check('ox zone takes one option given bare', zp and #zp.options == 1)

-- fix 4: each layer has its own keys
qtApi.AddTargetModel('prop_bin', { options = { { label = 'Kick', event = 'bin:kick' } } })
oxApi.removeModel('prop_bin')
check('ox_target and qtarget keys are apart', not book.has('ox_target|model:' .. binHash)
    and book.has('qtarget|model:' .. binHash))

qtApi.AddTargetModel('prop_bin', { options = { { label = 'Kick', event = 'bin:kick2' } } })
check('qtarget: an option added again under its label replaces it', #book.ids('qtarget|model:' .. binHash) == 1)

print(('%d passed, %d failed'):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
