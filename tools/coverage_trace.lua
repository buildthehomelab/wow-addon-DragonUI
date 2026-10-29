-- Lua 5.1 line tracer for the standalone behavioral suites. Never loaded by the addon.
local hits = {}
debug.sethook(function(_, line)
    local source = debug.getinfo(2, 'S').source
    if source:sub(1, 1) ~= '@' then return end
    source = source:sub(2):gsub('^%./', '')
    if not (source:match('^DragonUI/') or source:match('^DragonUI_Options/')) then return end
    hits[source] = hits[source] or {}
    hits[source][line] = true
end, 'l')
local ok, err = pcall(dofile, arg[1])
debug.sethook()
if not ok then io.stderr:write(tostring(err), '\n'); os.exit(1) end
local out = assert(io.open(arg[2], 'w'))
for source, lines in pairs(hits) do
    for line in pairs(lines) do out:write(source, '\t', line, '\n') end
end
out:close()
