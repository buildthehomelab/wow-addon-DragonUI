-- Run with Lua 5.1. Exercise Evermore's portrait control against upstream's real reload staging.
local addon = { _dir='', db={profile={modules={characterpanel={enabled=true}}}}, LO=setmetatable({}, {__index=function(_,k) return k end}), L=setmetatable({}, {__index=function(_,k) return k end}) }
DragonUI = addon
function wipe(t) for k in pairs(t) do t[k]=nil end end
function strsplit(_, path)
    local keys={}; for key in path:gmatch('[^%.]+') do keys[#keys+1]=key end
    return unpack(keys)
end
StaticPopupDialogs = {}
CANCEL = 'Cancel'
local visible, reloads = false, 0
function StaticPopup_Visible() return visible end
function StaticPopup_Hide() visible=false end
function StaticPopup_Show() visible=true; return {} end
function ReloadUI() reloads=reloads+1 end
assert(loadfile('DragonUI/core/reload.lua'))('DragonUI',addon)
local cfg=addon.db.profile.modules.characterpanel
local updates=0
function CreateFrame() return {RegisterEvent=function() end, SetScript=function() end} end
addon.CharacterPanel={Config=function() return cfg end,RegisterBuilder=function() end}
assert(loadfile('DragonUI/modules/characterpanel/portrait.lua'))('DragonUI',addon)
addon.CharacterPanel.UpdatePortrait=function() updates=updates+1 end
local portrait, build
local controls={EnsureModuleTable=function(_,name) return addon.db.profile.modules[name] end}
setmetatable(controls,{__index=function(_,name)
    return function(_,parent,opts)
        if name=='AddDropdown' and opts.label=='Portrait' then portrait=opts end
        return parent
    end
end})
addon.PanelControls=controls
addon.OptionsPanel={RegisterTab=function(_,_,_,fn) build=fn end}
assert(loadfile('DragonUI_Options/panel/tab_panels.lua'))()
build({})
assert(portrait)
portrait.setFunc('class')
assert(visible and cfg.portrait_style==nil and updates==0 and portrait.getFunc()=='class')
StaticPopupDialogs.DRAGONUI_RELOAD_PENDING.OnCancel()
assert(not addon.Reload.HasStaged() and portrait.getFunc()=='none' and cfg.portrait_style==nil)
portrait.setFunc('class')
StaticPopupDialogs.DRAGONUI_RELOAD_PENDING.OnAccept()
assert(cfg.portrait_style=='class' and reloads==1 and updates==0)
portrait.setFunc('spec')
assert(cfg.portrait_style=='spec' and updates==1 and not addon.Reload.HasStaged())
portrait.setFunc('none')
assert(cfg.portrait_style=='spec' and portrait.getFunc()=='none' and addon.Reload.HasStaged())
portrait.setFunc('character')
assert(cfg.portrait_style=='character' and updates==2 and not addon.Reload.HasStaged())
-- Production migration: legacy false means character; true falls back to the configured style/default.
cfg.portrait_style=nil; cfg.class_portrait=false
assert(portrait.getFunc()=='character' and cfg.class_portrait==nil)
portrait.setFunc('none'); assert(cfg.portrait_style=='character')
addon.Reload.Discard(); assert(portrait.getFunc()=='character')
portrait.setFunc('none'); addon.Reload.Commit()
assert(cfg.portrait_style=='none' and portrait.getFunc()=='none')
cfg.portrait_style=nil; cfg.class_portrait=true
assert(portrait.getFunc()=='none' and cfg.class_portrait==nil)
print('upstream integration: portrait reload staging, cancellation, commit, live swaps and legacy settings passed')
