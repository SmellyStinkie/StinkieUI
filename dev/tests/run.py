#!/usr/bin/env python3
"""Loads Stinkie UI into the mock client (mock.lua) and runs a Lua test script.

From the repo root:
    python dev/tests/run.py                      # the main checks (tests.lua)
    python dev/tests/run.py dev/tests/test_import.lua   # Rated Tracker import, needs STINKIE_RT

Needs: pip install lupa
STINKIE_RT: path to a RatedTracker.lua SavedVariables file (only for test_import / test_mem).
"""
import sys, os, re, tempfile
import lupa.lua51 as lupa

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

lua = lupa.LuaRuntime(unpack_returned_tuples=True)
lua.execute(open(os.path.join(HERE, "mock.lua"), encoding="utf-8").read())
lua.globals().LOCALFUNCS_PATH = localfuncs
lua.globals().TMP_DIR = TMP.replace("\\", "/")

def toc_files(path):
    files = []
    for line in open(path, encoding="utf-8"):
        line = line.strip()
        if line and not line.startswith("#"):
            files.append(line.replace("\\", "/"))
    return files

loader = lua.eval("""function(code, chunkname, addon, ns)
    local f, err = loadstring(code, chunkname)
    if not f then error(err) end
    f(addon, ns)
end""")

def load_addon(name, folder):
    ns = lua.eval("{}")
    for f in toc_files(os.path.join(folder, name + ".toc")):
        code = open(os.path.join(folder, f), encoding="utf-8").read()
        loader(code, "@" + name + "/" + f, name, ns)
    return ns

ns = load_addon("StinkieUI", ROOT)
lua.globals().TEST_NS = ns
rt = os.environ.get("STINKIE_RT")
if rt:
    lua.globals().RT_PATH = rt.replace("\\", "/")

def load_history(name):
    if name != "StinkieUI_History":
        return False, "MISSING"
    load_addon("StinkieUI_History", os.path.join(ROOT, "StinkieUI_History"))
    lua.globals().MOCK.Fire("ADDON_LOADED", "StinkieUI_History")
    return True, None

lua.globals().MOCK.LoadAddOn = lambda name: load_history(name)

script = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "tests.lua")
if os.path.basename(script) in ("test_import.lua", "test_mem.lua") and not rt:
    sys.exit("Set STINKIE_RT to your RatedTracker.lua SavedVariables file to run " + os.path.basename(script))
lua.execute(open(script, encoding="utf-8").read())
