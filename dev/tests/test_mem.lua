local ns = TEST_NS
local function out(...) io.write(table.concat({...}, " ") .. "\n") end
MOCK.Fire("ADDON_LOADED", "StinkieUI"); MOCK.Fire("PLAYER_LOGIN"); MOCK.Fire("PLAYER_ENTERING_WORLD", true, false); MOCK.Advance(0.5)
ns.MatchRecorder.Open() StinkieUI_MatchHistory:Hide()
collectgarbage("collect")
local base = collectgarbage("count")
do local f = assert(loadfile(RT_PATH)); f() end
ns.MatchRecorder.Import()
local g = 0
while StinkieUI_History.Import.running and g < 10000 do MOCK.Advance(0.02); g = g + 1 end
RatedTrackerDB = nil
MOCK.prints = {}
collectgarbage("collect"); collectgarbage("collect")
out(string.format("after import: %.1f MB over baseline", (collectgarbage("count") - base) / 1024))
local recs = StinkieUI_History.Data.Archive().records
local bytes = 0 for _, l in ipairs(recs) do bytes = bytes + #l end
out(string.format("record strings: %.1f MB", bytes / 1048576))
-- simulate a fresh login: saved variables re-read from text (only strings + tables)
local saved = StinkieUIMatchHistory
StinkieUIMatchHistory = nil
StinkieUI_History.Data.SetArchive({})
collectgarbage("collect"); collectgarbage("collect")
local empty = collectgarbage("count")
StinkieUIMatchHistory = { v = 1, dict = saved.dict, records = saved.records, statNames = saved.statNames }
saved = nil
StinkieUI_History.Data.SetArchive(StinkieUIMatchHistory)
collectgarbage("collect")
out(string.format("archive alone (what loads on /mh after a relog): %.1f MB", (collectgarbage("count") - empty) / 1024))
StinkieUI_History.Data.BuildSummaries()
collectgarbage("collect")
out(string.format("plus decoded summaries while the window is open: %.1f MB", (collectgarbage("count") - empty) / 1024))
local fh = io.open(TMP_DIR .. "/archive_sv.lua", "w")
fh:write("StinkieUIMatchHistory = { v = 1, dict = {\n")
for _, s in ipairs(StinkieUIMatchHistory.dict) do fh:write(string.format("%q,\n", s)) end
fh:write("}, records = {\n")
for _, s in ipairs(StinkieUIMatchHistory.records) do fh:write(string.format("%q,\n", s)) end
fh:write("}, statNames = {} }\n")
fh:close()
