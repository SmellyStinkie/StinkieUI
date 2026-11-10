#!/usr/bin/env python3
"""Loads Stinkie UI into the mock client (mock.lua) and runs a Lua test script.

From the repo root:
    python dev/tests/run.py                      # the main checks (tests.lua) and the module scenarios
    python dev/tests/run.py dev/tests/test_import.lua   # Rated Tracker import, needs STINKIE_RT

Each module scenario (modules.lua) runs in a fresh client, so it starts from its own saved
variables: a fresh install, an upgrade, one module off, everything off, WoW Forever, and so on.

Needs: pip install lupa
STINKIE_RT: path to a RatedTracker.lua SavedVariables file (only for test_import / test_mem).
"""
import sys, os, re, tempfile
import lupa.lua51 as lupa

# Lua writes straight to stdout; keep Python's lines in order with it when piped
sys.stdout.reconfigure(line_buffering=True)

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
TMP = tempfile.gettempdir()

# names of every "local function X" in the addon: calling one as a global means it was used
# before (or outside) its definition
names = set()
for d, dirs, files in os.walk(ROOT):
    dirs[:] = [x for x in dirs if x not in (".git", "dev", ".github")]
    for fn in files:
        if fn.endswith(".lua"):
            text = open(os.path.join(d, fn), encoding="utf-8").read()
            for m in re.finditer(r"^local function ([A-Z][A-Za-z0-9_]*)", text, re.M):
                names.add(m.group(1))
localfuncs = os.path.join(TMP, "stinkie_localfuncs.txt")
open(localfuncs, "w").write("\n".join(sorted(names)) + "\n")

MOCK_SRC = open(os.path.join(HERE, "mock.lua"), encoding="utf-8").read()
rt = os.environ.get("STINKIE_RT")


def toc_files(path):
    files = []
    for line in open(path, encoding="utf-8"):
        line = line.strip()
        if line and not line.startswith("#"):
            files.append(line.replace("\\", "/"))
    return files


def boot(before_load=None):
    """A fresh mock client with the addon's files loaded (no events fired yet)."""
    lua = lupa.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(MOCK_SRC)
    g = lua.globals()
    g.LOCALFUNCS_PATH = localfuncs
    g.TMP_DIR = TMP.replace("\\", "/")
    if before_load:
        lua.execute(before_load)
    loader = lua.eval("""function(code, chunkname, addon, ns)
        local f, err = loadstring(code, chunkname)
        if not f then error(err) end
        f(addon, ns)
    end""")

    def load_addon(name, folder):
        ns = lua.eval("{}")
        # SKIP_FILES (set before load): files a /reload after an update wouldn't have loaded
        skip = lua.eval("rawget(_G, \"SKIP_FILES\") or {}")
        skipped = set(skip.values())
        for f in toc_files(os.path.join(folder, name + ".toc")):
            if f in skipped:
                continue
            code = open(os.path.join(folder, f), encoding="utf-8").read()
            loader(code, "@" + name + "/" + f, name, ns)
        return ns

    g.TEST_NS = load_addon("StinkieUI", ROOT)
    if rt:
        g.RT_PATH = rt.replace("\\", "/")

    def load_history(name):
        if name != "StinkieUI_History":
            return False, "MISSING"
        load_addon("StinkieUI_History", os.path.join(ROOT, "StinkieUI_History"))
        lua.globals().MOCK.Fire("ADDON_LOADED", "StinkieUI_History")
        return True, None

    g.MOCK.LoadAddOn = lambda name: load_history(name)
    return lua


def run(script, scenario=None, arg=None, before_load=None):
    lua = boot(before_load)
    g = lua.globals()
    g.SCENARIO, g.ARG = scenario, arg
    lua.execute(open(script, encoding="utf-8").read())
    lua.execute("io.stdout:flush()")
    res = g.RESULT
    return (res.passed, res.failed) if res else (0, 0)


# WoW Forever: the project constants say Camelot
FOREVER = "WOW_PROJECT_ID, WOW_PROJECT_CAMELOT = 5, 5"
# updated and only /reloaded: the TOC's new files aren't loaded yet
NO_RESTART = 'SKIP_FILES = { "Report.lua", "BossFrames.lua" }'

if len(sys.argv) > 1:
    script = sys.argv[1]
    if os.path.basename(script) in ("test_import.lua", "test_mem.lua") and not rt:
        sys.exit("Set STINKIE_RT to your RatedTracker.lua SavedVariables file to run " + os.path.basename(script))
    lua = boot()
    lua.execute(open(script, encoding="utf-8").read())
    res = lua.globals().RESULT
    if res:
        print("\n%d passed, %d failed" % (res.passed, res.failed))
        sys.exit(1 if res.failed > 0 else 0)
    sys.exit(0)

passed, failed = run(os.path.join(HERE, "tests.lua"))

# module scenarios, each in its own client
MODS = os.path.join(HERE, "modules.lua")
ids = list(boot().eval("(function() local t = {} for i, m in ipairs(TEST_NS.Modules.LIST) do t[i] = m.id end return t end)()").values())
scenarios = [("fresh", None, None), ("fresh-in-match", None, None), ("upgrade", None, None),
             ("all-on", None, None), ("all-off", None, None), ("restore", None, None),
             ("spec-profiles", None, None), ("report", None, None), ("no-restart", None, NO_RESTART),
             ("forever", None, FOREVER), ("forever-off", None, FOREVER)]
scenarios += [("one-off", i, None) for i in ids]
for name, arg, before in scenarios:
    p, f = run(MODS, name, arg, before)
    if f:
        print("scenario %s%s: %d failed" % (name, " " + arg if arg else "", f))
    passed, failed = passed + p, failed + f
print("module scenarios: %d" % len(scenarios))

# every game function, method and event the addon uses, against the real clients' lists
sys.path.insert(0, HERE)
import check_api
p, f, lines = check_api.check()
print("\n".join(lines))
passed, failed = passed + p, failed + f

print("\n%d passed, %d failed" % (passed, failed))
sys.exit(1 if failed > 0 else 0)
