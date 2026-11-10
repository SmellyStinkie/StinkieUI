#!/usr/bin/env python3
"""Builds the list of real game API names that dev/tests/check_api.py checks the addon against.

It reads Blizzard's own UI code as the game exports it. To export: start the game with the
-console argument, open the console at the login screen with the ` key, and run
    ExportInterfaceFiles code
The game writes a BlizzardInterfaceCode folder next to Wow.exe (in _retail_ or _forever_).

    python dev/tools/make_api_list.py "<game>/_retail_/BlizzardInterfaceCode" retail
    python dev/tools/make_api_list.py "<game>/_forever_/BlizzardInterfaceCode" forever

Output: dev/tests/api/<client>.txt, one name per line with its kind:
    F  a documented game function          (C_Map.GetMapInfo, UnitName)
    M  a method on a frame, widget or mixin (SetPoint, SetQuestPartyProgress)
    E  an event                             (PLAYER_ENTERING_WORLD)
    L  a global Blizzard's Lua code defines (QuestMapFrame_OpenToQuestDetails, GameTooltip)
    U  a global Blizzard's code calls but that is neither documented nor defined in Lua: an
       undocumented game function                (CreateFrame, InCombatLockdown)
    D  a method or table function Blizzard's Lua code defines (UpdateAll, OpenQuestDetails)
    W  a documented widget method, which the game itself provides (SetPoint, IsShown)
Methods include the ones Blizzard's code calls, since many widget methods aren't documented.
Only names are kept; none of Blizzard's code is copied into the repo.

Needs: pip install lupa
"""
import os, re, sys
import lupa.lua51 as lupa

HERE = os.path.dirname(os.path.abspath(__file__))
OUT_DIR = os.environ.get("STINKIE_API_DIR") or os.path.normpath(os.path.join(HERE, "..", "tests", "api"))

# the documentation files register plain tables; collect them instead of building Blizzard's viewer
COLLECT = """
DOCS = {}
APIDocumentation = { AddDocumentationTable = function(_, t) DOCS[#DOCS + 1] = t end }
Enum = setmetatable({}, { __index = function(t, k) local v = setmetatable({}, { __index = function() return 0 end }); rawset(t, k, v); return v end })
Constants = Enum
"""


def read(path):
    with open(path, encoding="utf-8", errors="replace") as f:
        return f.read()


def documented(doc_dir):
    """Functions, methods and events from the generated documentation tables."""
    funcs, methods, events = set(), set(), set()
    lua = lupa.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(COLLECT)
    bad = 0
    for fn in sorted(os.listdir(doc_dir)):
        if not fn.endswith(".lua"):
            continue
        try:
            lua.execute(read(os.path.join(doc_dir, fn)))
        except Exception:
            bad += 1
    docs = lua.globals().DOCS
    for i in range(1, len(docs) + 1):
        t = docs[i]
        ns = t["Namespace"]
        is_object = t["Type"] == "ScriptObject"
        for key in ("Functions",):
            items = t[key]
            if items:
                for j in range(1, len(items) + 1):
                    name = items[j]["Name"]
                    if not name:
                        continue
                    if is_object:
                        methods.add(name)
                    elif ns:
                        funcs.add(ns + "." + name)
                    else:
                        funcs.add(name)
        ev = t["Events"]
        if ev:
            for j in range(1, len(ev) + 1):
                lit = ev[j]["LiteralName"]
                if lit:
                    events.add(lit)
    return funcs, methods, events, bad


TOP_FUNC = re.compile(r"^function\s+([A-Za-z_]\w*)\s*\(", re.M)
TOP_ASSIGN = re.compile(r"^([A-Za-z_]\w*)\s*=", re.M)
METHOD_DEF = re.compile(r"^\s*function\s+[A-Za-z_][\w.]*[:.]([A-Za-z_]\w*)\s*\(", re.M)
FIELD_FUNC = re.compile(r"^\s*([A-Za-z_]\w*)\s*=\s*function\b", re.M)
BARE_CALL = re.compile(r"(?<![\w.:])([A-Za-z_]\w*)\s*\(")
METHOD_CALL = re.compile(r":([A-Za-z_]\w*)\s*\(")
TOOLTIP_MAP = re.compile(r"^\s*(Set[A-Za-z]\w*)\s*=\s*\"Get", re.M)
LOCALS = re.compile(r"local\s+(?:function\s+)?([A-Za-z_][\w\s,]*)")
XML_NAME = re.compile(r'\bname="([A-Za-z_]\w*)"')
XML_MIXIN_METHOD = re.compile(r'\bmethod="([A-Za-z_]\w*)"')


def from_code(root, skip_dir):
    """Globals and method names Blizzard's own Lua and XML define."""
    globs, methods, called, defined = set(), set(), set(), set()
    for d, dirs, files in os.walk(root):
        if os.path.normpath(d) == os.path.normpath(skip_dir):
            continue
        for fn in files:
            path = os.path.join(d, fn)
            if fn.endswith(".lua"):
                text = read(path)
                globs.update(TOP_FUNC.findall(text))
                globs.update(TOP_ASSIGN.findall(text))
                defined.update(METHOD_DEF.findall(text))
                defined.update(FIELD_FUNC.findall(text))
                methods.update(METHOD_DEF.findall(text))
                methods.update(FIELD_FUNC.findall(text))
                methods.update(METHOD_CALL.findall(text))
                methods.update(TOOLTIP_MAP.findall(text))
                # bare calls, minus this file's own locals (a rough cut: a local of the same name
                # anywhere in the file hides the global)
                local = set()
                for chunk in LOCALS.findall(text):
                    for part in chunk.split(","):
                        local.add(part.strip().split(" ")[0])
                called.update(n for n in BARE_CALL.findall(text) if n not in local)
            elif fn.endswith(".xml"):
                text = read(path)
                # frames with a plain name are globals; ones built from $parent aren't listed
                globs.update(XML_NAME.findall(text))
                methods.update(XML_MIXIN_METHOD.findall(text))
    return globs, methods, called, defined


def find_doc_dir(root):
    for d, dirs, files in os.walk(root):
        if os.path.basename(d) == "Blizzard_APIDocumentationGenerated":
            return d
    return None


def main():
    if len(sys.argv) != 3 or sys.argv[2] not in ("retail", "forever"):
        sys.exit(__doc__)
    root, client = sys.argv[1], sys.argv[2]
    if not os.path.isdir(root):
        sys.exit("No such folder: " + root)
    doc_dir = find_doc_dir(root)
    if not doc_dir:
        sys.exit("No Blizzard_APIDocumentationGenerated folder under " + root + ". Was the code exported?")
    funcs, methods, events, bad = documented(doc_dir)
    widget = set(methods)
    globs, code_methods, called, defined = from_code(root, doc_dir)
    methods |= code_methods
    globs -= funcs
    keywords = set("and break do else elseif end false for function if in local nil not or repeat return then true until while".split())
    used = called - funcs - globs - keywords
    os.makedirs(OUT_DIR, exist_ok=True)
    out = os.path.join(OUT_DIR, client + ".txt")
    with open(out, "w", encoding="utf-8", newline="\n") as f:
        for kind, names in (("F", funcs), ("M", methods), ("E", events), ("L", globs), ("U", used), ("D", defined), ("W", widget)):
            for n in sorted(names):
                f.write(kind + " " + n + "\n")
    print("%s: %d functions, %d methods, %d events, %d Blizzard Lua globals, %d undocumented -> %s"
          % (client, len(funcs), len(methods), len(events), len(globs), len(used), out))
    if bad:
        print("%d documentation files couldn't be read and were skipped" % bad)
    if len(funcs) < 1000 or len(events) < 300:
        print("That is fewer names than a full client has. Check the export before trusting the list.")


if __name__ == "__main__":
    main()
