-- Production custom UI scale behavior with controlled frame events and combat queue.
local timers, queued, messages = {}, {}, 0
local combat=false
local frame
function CreateFrame()
    frame={events={},RegisterEvent=function(self,e) self.events[e]=true end,SetScript=function(self,_,f) self.event=f end}
    return frame
end
local scale=0.8
UIParent={GetScale=function() return scale end,SetScale=function(_,s) scale=s end}
function GetCVar() return '1920x1080' end
local addon={db={global={}},core={SendMessage=function(_,event) assert(event=='DRAGONUI_UI_SCALE_CHANGED'); messages=messages+1 end},
    After=function(_,_,f) timers[#timers+1]=f end,
    SafeExecute=function(_,_,_,f) if combat then queued.sync=f else f() end end}
assert(loadfile('DragonUI/core/uiscale.lua'))('DragonUI',addon)
local ui=addon.UIScale
ui.Apply(); assert(scale==0.8 and messages==0)
ui.SetEnabled(true); assert(ui.Get()==0.8)
ui.SetValue(0.2); ui.Apply(); assert(scale==0.4 and messages==1)
ui.SetValue(2); ui.Apply(); assert(scale==1 and messages==2)
ui.SetValue('invalid'); assert(ui.Get()==1)
ui.SetValue(0.5); combat=true; ui.Apply(); assert(scale==1)
combat=false; queued.sync(); assert(scale==0.5 and messages==3)
-- The client's scale changing underneath ours is remembered for disabling later.
scale=0.7
frame.event(); frame.event(); assert(#timers==1)
table.remove(timers,1)(); assert(scale==0.5 and messages==4)
ui.SetEnabled(false); ui.Apply(); assert(scale==0.7 and messages==5)
frame.event(); assert(#timers==0)
ui.Apply(); assert(messages==5)
assert(math.abs(ui.GetAutoScale()-768/1080)<0.00001)
addon.db.global.uiScale=false; ui.SetEnabled(true); assert(ui.Get()==0.7)
print('UI scale: default ownership, clamps, invalid input, combat deferral, event coalescing and restoration passed')
