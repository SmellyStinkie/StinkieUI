#!/usr/bin/env python3
"""Turns a Stinkie UI export string into Preset.lua: only the values that differ from the
built-in defaults (Core.lua alone, before any preset).
Usage (from the repo root): python dev/tools/make_preset.py export.txt Preset.lua
Needs: pip install lupa cbor2"""
import sys, os, base64, zlib, math
import cbor2
import lupa.lua51 as lupa

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
s = open(sys.argv[1]).read().strip()
assert s.startswith("STINKIEUI1:")
prof = cbor2.loads(zlib.decompress(base64.b64decode(s[len("STINKIEUI1:"):]), -15))

lua = lupa.LuaRuntime(unpack_returned_tuples=True)
lua.execute(open(os.path.join(ROOT, "dev", "tests", "mock.lua"), encoding="utf-8").read())
loader = lua.eval("""function(code, name, ns) local f, e = loadstring(code, name); if not f then error(e) end; f("StinkieUI", ns) end""")
ns = lua.eval("{}")
loader(open(os.path.join(ROOT, "Core.lua"), encoding="utf-8").read(), "@Core.lua", ns)

def to_py(t):
    if lupa.lua_type(t) != "table":
        return t
    keys = list(t.keys())
    if keys and all(isinstance(k, int) for k in keys) and sorted(keys) == list(range(1, len(keys) + 1)):
        return [to_py(t[k]) for k in sorted(keys)]
    return {k: to_py(t[k]) for k in keys}

defaults = to_py(ns.defaults)

def is_list(v):
    return isinstance(v, list)

def norm(v):
    if isinstance(v, bytes):
        return v.decode("utf-8")
    if isinstance(v, dict):
        v = {(k.decode("utf-8") if isinstance(k, bytes) else k): x for k, x in v.items()}
    # CBOR may hand back an array as a dict {1:..}
    if isinstance(v, dict) and v and all(isinstance(k, int) for k in v) and sorted(v) == list(range(1, len(v) + 1)):
        return [norm(v[k]) for k in sorted(v)]
    if isinstance(v, dict):
        return {k: norm(x) for k, x in v.items()}
    if isinstance(v, list):
        return [norm(x) for x in v]
    return v

prof = norm(prof)
SKIP = {"version"}
# remembered window spots are where one person dragged things on one screen, not settings
DROP = {("windowMover", "frames")}

def same(a, b):
    if (a == {} or a == []) and (b == {} or b == []):
        return True
    if isinstance(a, float) or isinstance(b, float):
        try:
            return abs(float(a) - float(b)) < 1e-6
        except Exception:
            return False
    if isinstance(a, dict) and isinstance(b, dict):
        return a.keys() == b.keys() and all(same(a[k], b[k]) for k in a)
    if isinstance(a, list) and isinstance(b, list):
        return len(a) == len(b) and all(same(x, y) for x, y in zip(a, b))
    return a == b

def diff(p, d, path=""):
    out = {}
    for k, v in p.items():
        if path == "" and k in SKIP:
            continue
        if k not in d:
            # only free-form maps (empty in the defaults) take new keys
            if isinstance(d, dict) and len(d) == 0:
                out[k] = v
            continue
        dv = d[k]
        if isinstance(v, dict) and isinstance(dv, dict) and dv:
            sub = diff(v, dv, path + "." + str(k))
            if sub:
                out[k] = sub
        elif isinstance(dv, dict) and not dv and isinstance(v, dict):
            if v:
                out[k] = v
        elif not same(v, dv):
            out[k] = v
    return out

delta = diff(prof, defaults)
for a, b in DROP:
    if a in delta and b in delta[a]:
        del delta[a][b]
        if not delta[a]:
            del delta[a]

def lua_val(v, ind):
    pad = "\t" * ind
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int,)):
        return str(v)
    if isinstance(v, float):
        r = round(v, 6)
        return str(int(r)) if r == int(r) else repr(r)
    if isinstance(v, str):
        return '"' + v.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'
    if isinstance(v, list):
        if all(not isinstance(x, (dict, list)) for x in v):
            return "{ " + ", ".join(lua_val(x, ind) for x in v) + " }" if v else "{}"
        return "{\n" + "".join(pad + "\t" + lua_val(x, ind + 1) + ",\n" for x in v) + pad + "}"
    if isinstance(v, dict):
        if not v:
            return "{}"
        lines = []
        for k in sorted(v, key=lambda x: (isinstance(x, int), str(x))):
            key = k if isinstance(k, str) and k.isidentifier() else "[" + lua_val(k, 0) + "]"
            lines.append(pad + "\t" + key + " = " + lua_val(v[k], ind + 1) + ",\n")
        return "{\n" + "".join(lines) + pad + "}"
    raise TypeError(type(v))

head = open(os.path.join(ROOT, "Preset.lua"), encoding="utf-8").read()
pre = head[:head.index("local PRESET = ")]
post = head[head.index("\nlocal function Merge"):]
open(sys.argv[2], "w", encoding="utf-8", newline="\n").write(pre + "local PRESET = " + lua_val(delta, 0) + "\n" + post)
import json
print(json.dumps(delta, indent=1, default=str)[:200000])
