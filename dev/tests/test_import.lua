local ns = TEST_NS
local function out(...) local p = {} for i = 1, select("#", ...) do p[#p + 1] = tostring((select(i, ...))) end io.write(table.concat(p, " ") .. "\n") end
MOCK.Fire("ADDON_LOADED", "StinkieUI")
MOCK.Fire("PLAYER_LOGIN")
MOCK.Fire("PLAYER_ENTERING_WORLD", true, false)
MOCK.Advance(0.5)
for _, e in ipairs(MOCK.errors) do out("BOOT ERROR", e) end
MOCK.errors = {}
-- preset check
out("preset flagCap layout:", ns.db.flagCap.layout, "height", ns.db.flagCap.height, "width", ns.db.flagCap.width, "bgTimers width", ns.db.bgTimers.width)
collectgarbage("collect")
local before = collectgarbage("count")
-- Rated Tracker's saved data is loaded (as if it's enabled)
local t0 = os.clock()
local f = assert(loadfile(RT_PATH))
f()
collectgarbage("collect")
out(string.format("RatedTrackerDB in memory: %.1f MB (load %.1fs)", (collectgarbage("count") - before) / 1024, os.clock() - t0))
-- import before the window was ever opened, from the options button path
t0 = os.clock()
ns.MatchRecorder.Import()
local guard = 0
while StinkieUI_History.Import.running and guard < 10000 do MOCK.Advance(0.02); guard = guard + 1 end
out(string.format("import took %.1fs of Lua time over %d frames", os.clock() - t0, guard))
for _, p in ipairs(MOCK.prints) do if p:find("Stinkie UI") then out(p) end end
for _, e in ipairs(MOCK.errors) do out("ERROR", e) end
MOCK.errors = {}
local D = StinkieUI_History.Data
out("archive records:", #D.Archive().records, "dict strings:", #D.Archive().dict)
out(string.format("archive size: %.2f MB (%.0f bytes/match)", D.SizeBytes() / 1048576, D.SizeBytes() / #D.Archive().records))
-- what RT's memory would be gone: drop it and measure the archive alone
RatedTrackerDB = nil
f = nil
collectgarbage("collect"); collectgarbage("collect")
out(string.format("archive in memory after import (Rated Tracker data released): %.1f MB", (collectgarbage("count") - before) / 1024))
f = assert(loadfile(RT_PATH))
-- per bracket sizes
local by = {}
for _, line in ipairs(D.Archive().records) do
	local b = line:match("^v1;[^;]*;[^;]*;([^;]*)")
	b = D.Resolve(b or "")
	by[b] = by[b] or { n = 0, bytes = 0 }
	by[b].n = by[b].n + 1; by[b].bytes = by[b].bytes + #line
end
for b, v in pairs(by) do out(string.format("  %-8s %5d matches, %.0f bytes each", b, v.n, v.bytes / v.n)) end
-- re-import: everything is a duplicate
f()
ns.MatchRecorder.Import()
guard = 0
while StinkieUI_History.Import.running and guard < 10000 do MOCK.Advance(0.02); guard = guard + 1 end
out(MOCK.prints[#MOCK.prints])
RatedTrackerDB = nil
-- stats over everything
t0 = os.clock()
D.BuildSummaries()
out(string.format("summaries: %d in %.2fs", #D.summaries, os.clock() - t0))
local agg = D.Aggregate(D.Filter(D.summaries, { bracket = "shuffle" }))
out(string.format("shuffle: %d games, round win rate %.1f%% (%.1f-%.1f)", agg.games, agg.winRate * 100, agg.lo * 100, agg.hi * 100))
local function show(bracket, by, n)
	local rows = D.Group(D.Filter(D.summaries, { bracket = bracket }), by)
	for i = 1, math.min(n, #rows) do
		local r = rows[i]
		out(string.format("  %-10s %-28s %4d games  %5.1f%%  net %+d", bracket, tostring(r.key), r.games, (r.winRate or 0) * 100, r.net))
	end
end
show("3v3", "map", 4)
show("blitz", "map", 4)
show("shuffle", "char", 3)
show("2v2", "teammate", 3)
-- open the window on the imported data and a few details
StinkieUI_History.Toggle("stats")
StinkieUI_History.Toggle("matches")
for _, s in ipairs({ D.summaries[1], D.summaries[50] }) do StinkieUI_History.ShowDetail(s) end
for _, s in ipairs(D.summaries) do
	if s.bracket == "shuffle" then
		local m = D.Get(s.i)
		if m.srounds then
			StinkieUI_History.ShowDetail(s)
			out("shuffle detail line3:", StinkieUI_MatchHistory and "" or "", (select(1, m.srounds)))
			break
		end
	end
end
for _, e in ipairs(MOCK.errors) do out("ERROR", e) end
out("errors:", #MOCK.errors)
