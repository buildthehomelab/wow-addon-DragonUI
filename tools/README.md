# DragonUI checks

Run from the repository root with Lua 5.1:

```sh
lua5.1 tools/achievement_search_test.lua
lua5.1 tools/bartender_handoff_test.lua
lua5.1 tools/feral_ap_tooltip_test.lua
lua5.1 tools/keybinding_search_test.lua
lua5.1 tools/latency_test.lua
lua5.1 tools/movement_speed_test.lua
lua5.1 tools/quest_givers_test.lua
lua5.1 tools/review_regression_test.lua
lua5.1 tools/window_positions_test.lua
lua5.1 tools/upstream_integration_test.lua
lua5.1 tools/ui_scale_test.lua
lua5.1 tools/profile_actions_test.lua
lua5.1 tools/raid_browser_skin_test.lua
python3 tools/recolour_grounds.py --check
python3 tools/link_icon_bubble.py --check
```

The Bartender4 hand-off test covers switching the bar modules off while Bartender4 is loaded, keeping Bartender4's micro menu, bag bar and XP/Rep bars off without changing its settings, the once-per-change login line, restoring only the handed modules on a later load (never mid-session), and the opt-out. It does not load mainbars.lua or noop.lua, whose Bartender4 paths need a game client.
The quest givers test covers the world map's quest giver pins against a faked mod-quest-map: no requests at all once the hello goes unanswered (and its echo ignored), parsing the server's rows, hiding trivial quests unless the filter is on, the blue daily and grey trivial icons, the tooltip, no refetch on objective updates but one when a quest is taken or on level-up, the busy retry (only for the map still shown, with a later try once the retries run out), a lost answer, and a refetch after entering another zone.
The Raid Browser skin test covers the stock art hidden, red List Me / Set Comment / Leave Queue / Send Message / Invite / Refresh buttons, the raid list, comment box and member list each fitting their inset over the button row, the Browse buttons spread evenly across the seats, and a tab another addon adds later (RaidFinder's third) joining the strip, which re-chains on every open.
The movement speed test covers the reading (percent of 7 yd/s, vehicles, the last reading dimmed when standing), the spot under the ring for each minimap style, stepping beside the durability figure, editor drag/reset and the toggle.
The latency test covers the self-whisper round trip (ignoring other senders, channels, prefixes and stale answers), the colour bands, the reading climbing while the server is slow, the 30 s resend, dropping a ping across a loading screen, hanging under the speed line or taking its spot, editor drag/reset and the toggle.
The key binding search test covers filtering by command name and key, kept section headers, scrolling the filtered list, selection highlight, deselect on focus and reset on close.
The achievement test covers reward matching, translated type aliases, tier chains,
UI selection, cache reuse, debounced typing and invalidation while shown/hidden.
The regression test loads the production modules with Wrath-style API mocks and
covers position-preset round trips/rejection/rollback, vendor acknowledgements and
auto-repair sequencing, and mail capacity/timeout/COD/GM/close handling.
The texture check requires Pillow. These checks do not simulate protected frames or
prove server behavior in a real client.

Not yet checked in a game client: the Raid Browser skin (with or without RaidFinder's tab), the server lag line under the minimap, the quest giver pins on the world map, the movement speed line under the minimap, the Bartender4 hand-off, the Key Bindings search box, position presets and window dragging across the panels, grey-item
auto-sell and auto-repair, Open All with full bags, achievement search, and the unit-frame styles
and combo-point modes after the last upstream merge. Also not checked: portrait-off unit frames
(beta) with their decorations and icons, /reload in an LFG party, tooltip sharing with other
addons, empty-loot auto-hide, large alt-gold totals, and Mind Sear / Volley ticks.

After merging upstream, `python3 tools/recolour_grounds.py --check` says whether `ui-background-rock`
and `ui-background-marble` need their warm brown recolour regenerated.

See [the October 28 upstream integration report](UPSTREAM-2026-10-28.md) for source
parents, conflict decisions, validation and the pending client/delivery checklist.

Measure behavioral line coverage with Lua/luac 5.1:
`python3 tools/measure_coverage.py --output /tmp/dragonui-coverage.json`.
See `coverage-baseline.json` for the measured baseline and the integration report
for remaining gaps; this is not full line or branch coverage.
