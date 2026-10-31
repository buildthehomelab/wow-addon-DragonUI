-- Run from the repository root with Lua 5.1.
if jit then jit.off() end -- count hooks do not fire in compiled code

local loaded = {}
local frames = {}
function IsAddOnLoaded(name) return loaded[name] or false end
function GetNumAddOns() return 0 end
function GetAddOnInfo() return nil end
function GetCVar() return nil end
function InCombatLockdown() return false end
function UnitHasVehicleUI() return false end
function hooksecurefunc() end
function CreateFrame()
    local frame = { scripts = {}, events = {} }
    function frame:RegisterEvent(event) self.events[event] = true end
    function frame:UnregisterEvent(event) self.events[event] = nil end
    function frame:SetScript(event, fn) self.scripts[event] = fn end
    frames[#frames + 1] = frame
    return frame
end
StaticPopupDialogs, SlashCmdList = {}, {}
UIParent = {}
local printed = {}
function print(text) printed[#printed + 1] = text end

local function fire(event)
    for _, frame in ipairs(frames) do
        if frame.events[event] then frame.scripts.OnEvent(frame, event) end
    end
end

local function read(path)
    local file = assert(io.open(path, 'rb'))
    local text = file:read('*a')
    file:close()
    return text
end

-- Shadowed Unit Frames has to load first for IsAddOnLoaded to see it while DragonUI's files run.
assert(read('DragonUI/DragonUI.toc'):match('## OptionalDeps:[^\r\n]*ShadowedUnitFrames'), 'ShadowedUnitFrames is not an OptionalDep')

-- The flag, fixed when compatibility.lua runs; a character's db.char survives between its loads.
local char = {}
local function load(withShadowUF)
    loaded.ShadowedUnitFrames = withShadowUF
    frames, printed = {}, {}
    local addon = {
        db = { profile = { modules = {}, compatibility = {} }, char = char },
        L = setmetatable({}, { __index = function(_, key) return key end }),
        After = function() end,
    }
    function addon:IsModuleEnabled() return false end
    assert(loadfile('DragonUI/modules/compatibility.lua'))('DragonUI', addon)
    fire('PLAYER_LOGIN')
    local said = false
    for _, text in ipairs(printed) do
        if text:find('Shadowed Unit Frames runs your unit frames', 1, true) then said = true end
    end
    return addon.compatibility.shadowUFRuns, said
end

local runs, said = load(false)
assert(runs == false and not said, 'without Shadowed Unit Frames DragonUI keeps the unit frames, unannounced')
runs, said = load(true)
assert(runs == true and said, 'Shadowed Unit Frames runs them, and the first load says so')
runs, said = load(true)
assert(runs == true and not said, 'said once, not on every load')
load(false)
runs, said = load(true)
assert(runs == true and said, 'said again after a load without it')

-- Every unit frame file except the two helpers returns before reading any global but select: no frame, hook,
-- event or module. Taken from unitframes.xml, so a file added there later is checked too.
local KEPT = { ['uf_core.lua'] = true, ['text_system.lua'] = true }
local files = {}
for name in read('DragonUI/modules/unitframes/unitframes.xml'):gmatch('<Script file="([^"]+)"') do
    if not KEPT[name] then files[#files + 1] = name end
end
assert(#files >= 15, 'unitframes.xml lists fewer files than expected')

-- Any global read past `select`, and any use of addon past its compatibility flag, is recorded; reads return a stub that is callable and indexable all the way down.
local stub = setmetatable({}, {})
getmetatable(stub).__index = function() return stub end
getmetatable(stub).__call = function() return stub end
getmetatable(stub).__newindex = function() end

local function run(name, shadowUFRuns)
    local reads = {}
    local env = setmetatable({}, {
        __index = function(_, key)
            if key == 'select' then return select end
            reads[#reads + 1] = key
            return stub
        end,
        __newindex = function(_, key) reads[#reads + 1] = '=' .. key end,
    })
    local chunk = assert(loadfile('DragonUI/modules/unitframes/' .. name))
    setfenv(chunk, env)
    -- addon and addon.UF record use too: small_frame only adds a factory to UF.
    local UF = setmetatable({}, {
        __index = function(_, key) reads[#reads + 1] = 'UF.' .. key return stub end,
        __newindex = function(_, key) reads[#reads + 1] = '=UF.' .. key end,
    })
    local addon = setmetatable({ compatibility = { shadowUFRuns = shadowUFRuns } }, {
        __index = function(_, key)
            reads[#reads + 1] = 'addon.' .. key
            return key == 'UF' and UF or stub
        end,
        __newindex = function(_, key) reads[#reads + 1] = '=addon.' .. key end,
    })
    -- The stub runs loops forever (`while stub do`), so a run is cut off: the guard comes long before that.
    debug.sethook(function() error('cut off') end, '', 1e6)
    pcall(chunk, 'DragonUI', addon)
    debug.sethook()
    return reads
end

for _, name in ipairs(files) do
    local reads = run(name, true)
    assert(#reads == 0, name .. ' read ' .. tostring(reads[1]) .. ' with Shadowed Unit Frames running')
    assert(#run(name, false) > 0, name .. ' did nothing without Shadowed Unit Frames')
end

-- The kept helpers answer "off" for every frame, so their callers (combo points, the editor's modules) stand down.
local function loadCore(shadowUFRuns)
    local addon = {
        compatibility = { shadowUFRuns = shadowUFRuns },
        defaults = { profile = { unitframe = { player = { enabled = true }, boss = { enabled = true } } } },
        db = { profile = { unitframe = { player = {}, boss = { enabled = false } } } },
        L = setmetatable({}, { __index = function(_, key) return key end }),
    }
    assert(loadfile('DragonUI/modules/unitframes/uf_core.lua'))('DragonUI', addon)
    return addon.UF
end
local UF = loadCore(false)
assert(UF.IsEnabled('player') == true and UF.IsEnabled('boss') == false, 'IsEnabled follows the settings')
UF = loadCore(true)
assert(UF.IsEnabled('player') == false and UF.IsEnabled('boss') == false, 'IsEnabled is off for every frame')

io.write('shadowed unit frames hand-off test passed\n')
