-- Exercise production profile controls/reload staging against the bundled real AceDB.
strmatch=string.match
function CreateFrame() return {SetScript=function() end,RegisterEvent=function() end} end
function GetRealmName() return 'EvermoreTest' end
function UnitName() return 'Tester' end
function UnitClass() return 'Warrior','WARRIOR' end
function UnitRace() return 'Human','Human' end
function UnitFactionGroup() return 'Alliance' end
assert(loadfile('DragonUI/libs/LibStub/LibStub.lua'))()
assert(loadfile('DragonUI/libs/AceDB-3.0/AceDB-3.0.lua'))()
local widget
local gui=LibStub:NewLibrary('AceGUI-3.0',1)
function gui:Create()
    widget={SetLabel=function() end,SetWidth=function() end,SetText=function() end,
        SetCallback=function(self,_,fn) self.enter=fn end}
    return widget
end
local strings=setmetatable({}, {__index=function(_,key) return key end})
local errors, printed, reloads = {}, {}, 0
function geterrorhandler() return function(err) errors[#errors+1]=err end end
function wipe(t) for k in pairs(t) do t[k]=nil end end
function strsplit(_,path)
    local keys={}; for key in path:gmatch('[^%.]+') do keys[#keys+1]=key end
    return unpack(keys)
end
CANCEL='Cancel'; StaticPopupDialogs={}
local visible=false
local lastPopup
function StaticPopup_Visible() return visible end
function StaticPopup_Show(name)
    if name=='DRAGONUI_RELOAD_PENDING' then visible=true end
    lastPopup={}; return lastPopup
end
function StaticPopup_Hide() visible=false end
function ReloadUI() reloads=reloads+1 end
local addon={L=strings,LO=strings,Print=function(_,msg) printed[#printed+1]=msg end}
DragonUI=addon
assert(loadfile('DragonUI/core/reload.lua'))('DragonUI',addon)
local choices, build
local section={AddChild=function() end}
addon.PanelControls={Theme={textGold={},accentHex='ffffff'},SkinEditBox=function() end,
    AddLabel=function() end,AddDescription=function() end,AddSpacer=function() end,
    AddSection=function() return section end,AddButton=function() end,
    AddDropdown=function(_,_,opts) choices[opts.label]=opts end}
addon.OptionsPanel={RegisterTab=function(_,_,_,fn) build=fn end,SelectTab=function() end}
local locale=LibStub:NewLibrary('AceLocale-3.0-DragonUI',1)
function locale:GetLocale() return strings end
assert(loadfile('DragonUI_Options/core.lua'))()
assert(loadfile('DragonUI_Options/panel/tab_profiles.lua'))()
local function setup()
    addon.Reload.Discard(); visible=false
    errors,printed={},{}
    local db=LibStub('AceDB-3.0'):New({}, {profile={marker='default'}}, 'A')
    for _,name in ipairs({'A','B','C'}) do db:SetProfile(name); db.profile.marker=name end
    db:SetProfile('A'); addon.db=db
    choices={}; build(section)
    return db
end
local function accept()
    StaticPopupDialogs.DRAGONUI_RELOAD_PENDING.OnAccept()
    assert(#errors==0, 'Staged action raised: '..tostring(errors[1]))
    assert(not addon.Reload.HasStaged())
end
local db=setup()
choices['Select Profile'].setFunc('B'); choices['Copy From'].setFunc('B')
assert(db:GetCurrentProfile()=='A' and db.profile.marker=='A', 'Changed before confirmation')
accept()
assert(db:GetCurrentProfile()=='A' and db.profile.marker=='B', 'Copy must replace the staged switch')
assert(#printed==1)
db=setup()
choices['Copy From'].setFunc('B'); choices['Select Profile'].setFunc('C'); accept()
assert(db:GetCurrentProfile()=='C' and db.profile.marker=='C' and db.profiles.A.marker=='A', 'Switch must replace staged copy')
assert(#printed==0)
db=setup()
choices['Select Profile'].setFunc('B'); choices['Copy From'].setFunc('C'); accept()
assert(db:GetCurrentProfile()=='A' and db.profile.marker=='C', 'Copy used a staged destination')
db=setup()
choices['Copy From'].setFunc('B'); widget.enter(widget,'OnEnterPressed','New'); accept()
assert(db:GetCurrentProfile()=='New' and db.profile.marker=='default' and db.profiles.A.marker=='A')
db=setup()
choices['Copy From'].setFunc('B'); choices['Select Profile'].setFunc('A')
assert(not addon.Reload.HasStaged() and not visible, 'Returning to current profile must cancel pending operation')
choices['Select Profile'].setFunc('B'); choices['Copy From'].setFunc('B')
StaticPopupDialogs.DRAGONUI_RELOAD_PENDING.OnCancel()
assert(not addon.Reload.HasStaged() and db:GetCurrentProfile()=='A' and db.profile.marker=='A')
db=setup(); choices['Copy From'].setFunc('A')
assert(not addon.Reload.HasStaged(), 'Current profile offered as a copy source')
-- Confirming deletion cancels a staged operation referencing the old profile list.
local function delete(name)
    choices['Delete'].setFunc(name)
    assert(lastPopup.data==name)
    StaticPopupDialogs.DRAGONUI_DELETE_PROFILE.OnAccept(lastPopup)
end
db=setup(); choices['Copy From'].setFunc('B'); delete('B')
assert(not addon.Reload.HasStaged() and not visible and db.profiles.B==nil)
addon.Reload.Commit()
assert(db:GetCurrentProfile()=='A' and db.profile.marker=='A' and #errors==0)
db=setup(); choices['Select Profile'].setFunc('B'); delete('B'); addon.Reload.Commit()
assert(not addon.Reload.HasStaged() and db.profiles.B==nil and db:GetCurrentProfile()=='A')
-- Deletion must not discard unrelated staged settings in the current profile.
db=setup(); addon.Reload.Stage('marker','stagedA'); choices['Copy From'].setFunc('B'); delete('B')
assert(addon.Reload.HasStaged()); accept()
assert(db:GetCurrentProfile()=='A' and db.profile.marker=='stagedA' and db.profiles.B==nil)
-- Asking for deletion and declining it leaves the staged copy intact.
db=setup(); choices['Copy From'].setFunc('B'); choices['Delete'].setFunc('B')
assert(addon.Reload.HasStaged()); accept()
assert(db:GetCurrentProfile()=='A' and db.profile.marker=='B')
print('profiles: switch/copy ordering, same-source guard, create, cancellation and actual AceDB passed')
