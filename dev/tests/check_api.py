#!/usr/bin/env python3
"""Checks every game function, method and event the addon uses against the real clients' lists.

The mock client answers any unknown call with a harmless stub, so a misspelled or made-up game
function passes the other tests. This reads the addon's source and looks each name up in
dev/tests/api/retail.txt and forever.txt (built by dev/tools/make_api_list.py from the game's own
exported UI code).

A name fails when:
  - no client has it (a typo, or a function that doesn't exist)
  - only one client has it and the addon never tests for it before calling
  - it's a function Blizzard wrote in Lua (calling one from an addon is how taint starts)
unless it's listed in dev/tests/api/reviewed.txt with a reason. That file is the list of things
someone looked at and accepted, so anything new shows up as a failure until it's looked at too.

    python dev/tests/check_api.py            # report
    python dev/tests/check_api.py --update   # add today's findings to reviewed.txt, to review by hand

run.py runs the same check after the other tests. With no list files it's skipped, with a notice.
"""
import os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
# STINKIE_API_DIR: another folder for the lists (used to try the check on a made-up export)
API_DIR = os.environ.get("STINKIE_API_DIR") or os.path.join(HERE, "api")
REVIEWED = os.path.join(API_DIR, "reviewed.txt")
CLIENTS = ("retail", "forever")

KEYWORDS = set("and break do else elseif end false for function if in local nil not or repeat return then true until while".split())
# Lua itself, and the few globals WoW adds to it that aren't in the API documentation
LUA = set("""assert collectgarbage date error gcinfo getfenv getmetatable ipairs loadstring next newproxy pairs pcall
print rawequal rawget rawset select setfenv setmetatable time tonumber tostring type unpack xpcall
abs ceil cos deg exp floor frexp ldexp log log10 max min mod rad random sin sqrt tan
format gmatch gsub strbyte strchar strfind strlen strlower strmatch strrep strrev strsub strupper
strtrim strsplit strjoin strconcat strsplittable tostringall
foreach foreachi getn sort tinsert tremove wipe tContains tInvert CopyTable Mixin CreateFromMixins
bit string table math coroutine debugstack debugprofilestop debuglocals geterrorhandler seterrorhandler
hooksecurefunc issecurevariable securecall securecallfunction issecure forceinsecure scrub
issecret issecretvalue canaccessvalue canaccesstable""".split())
STRING_METHODS = set("byte char find format gmatch gsub len lower match rep reverse sub upper trim".split())

EVENT_RE = re.compile(r"^[A-Z][A-Z0-9]*(_[A-Z0-9]+)+$")


def read(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


def load_lists():
    lists = {}
    for c in CLIENTS:
        p = os.path.join(API_DIR, c + ".txt")
        if os.path.exists(p):
            kinds = {"F": set(), "M": set(), "E": set(), "L": set(), "U": set(), "D": set(), "W": set()}
            for line in read(p).splitlines():
                if len(line) > 2 and line[0] in kinds and line[1] == " ":
                    kinds[line[0]].add(line[2:].strip())
            lists[c] = kinds
    return lists


def load_reviewed():
    out = {}
    if os.path.exists(REVIEWED):
        for line in read(REVIEWED).splitlines():
            line = line.strip()
            if line and not line.startswith("#"):
                name, _, why = line.partition("#")
                out[name.strip()] = why.strip()
    return out


def strip(text):
    """Source with comments blanked and string contents replaced by spaces; also the strings."""
    out, strings = [], []
    i, n = 0, len(text)
    while i < n:
        c = text[i]
        if text.startswith("--", i):
            m = re.match(r"--\[(=*)\[", text[i:])
            if m:
                end = text.find("]" + m.group(1) + "]", i)
                end = n if end < 0 else end + len(m.group(1)) + 2
            else:
                end = text.find("\n", i)
                end = n if end < 0 else end
            out.append(re.sub(r"[^\n]", " ", text[i:end]))
            i = end
        elif c in "\"'":
            j = i + 1
            while j < n and text[j] != c and text[j] != "\n":
                j += 2 if text[j] == "\\" else 1
            strings.append((len("".join(out)), text[i + 1:j]))
            out.append(c + " " * (j - i - 1) + c)
            i = j + 1
        elif c == "[" and re.match(r"\[(=*)\[", text[i:]):
            m = re.match(r"\[(=*)\[", text[i:])
            end = text.find("]" + m.group(1) + "]", i)
            end = n if end < 0 else end + len(m.group(1)) + 2
            out.append(re.sub(r"[^\n]", " ", text[i:end]))
            i = end
        else:
            out.append(c)
            i += 1
    return "".join(out), strings


def addon_files():
    files = []
    for d, dirs, names in os.walk(ROOT):
        dirs[:] = [x for x in dirs if x not in (".git", "dev", ".github", ".claude")]
        for fn in names:
            if fn.endswith(".lua"):
                files.append(os.path.join(d, fn))
    return sorted(files)


LOCAL_FUNC = re.compile(r"\blocal\s+function\s+([A-Za-z_]\w*)")
LOCAL_VARS = re.compile(r"\blocal\s+([A-Za-z_][\w\s,]*?)\s*(?:=|\n|$)", re.M)
PARAMS = re.compile(r"\bfunction\b[^(\n]*\(([^)]*)\)")
FOR_VARS = re.compile(r"\bfor\s+([A-Za-z_][\w\s,]*?)\s+(?:in\b|=)")
GLOBAL_DEF = re.compile(r"^(?:function\s+([A-Za-z_]\w*)\s*\(|([A-Za-z_]\w*)\s*=[^=])", re.M)
METHOD_DEF = re.compile(r"\bfunction\s+[A-Za-z_][\w.]*[:.]([A-Za-z_]\w*)\s*\(")
FIELD_DEF = re.compile(r"[.\s,{]([A-Za-z_]\w*)\s*=\s*function\b")
FIELD_SET = re.compile(r"\.([A-Za-z_]\w*)\s*=[^=]")
NS_USE = re.compile(r"(?<![\w.])(C_\w+)\.([A-Za-z_]\w*)(\s*\()?")
BARE_CALL = re.compile(r"(?<![\w.:])([A-Za-z_]\w*)\s*\(")
BARE_REF = re.compile(r"(?<![\w.:])([A-Za-z_]\w*)\b(?!\s*\()")
# a call through one of Blizzard's global tables or frames: QuestUtil.OpenQuestDetails(...),
# ObjectiveTrackerManager:UpdateAll()
VIA_GLOBAL = re.compile(r"(?<![\w.:])([A-Z]\w*)([.:])([A-Za-z_]\w*)\s*\(")
METHOD_CALL = re.compile(r":([A-Za-z_]\w*)\s*\(")
FIELD_REF = re.compile(r"\.([A-Za-z_]\w*)\b(?!\s*\()")
REGISTER = re.compile(r"(?:RegisterEvent|RegisterUnitEvent|ns:On)\s*\(\s*$")
LOOP_REGISTER = re.compile(r"RegisterEvent|RegisterUnitEvent|ns:On\(")


def names_in(lists_text):
    out = set()
    for chunk in lists_text:
        for part in chunk.split(","):
            part = part.strip().split(" ")[0]
            if re.match(r"^[A-Za-z_]\w*$", part):
                out.add(part)
    return out


def scan():
    """What the addon uses: namespaced functions, bare calls, methods and events."""
    use = {"ns": {}, "call": {}, "method": {}, "event": {}, "via": {}}
    tested = set()        # names referenced without being called: an existence test, or passed to pcall
    own_methods, own_globals = set(), set()
    per_file = []
    for path in addon_files():
        code, strings = strip(read(path))
        rel = os.path.relpath(path, ROOT).replace("\\", "/")
        own_methods.update(METHOD_DEF.findall(code))
        own_methods.update(FIELD_DEF.findall(code))
        own_methods.update(FIELD_SET.findall(code))
        for a, b in GLOBAL_DEF.findall(code):
            own_globals.add(a or b)
        per_file.append((rel, code, strings))
    for rel, code, strings in per_file:
        local = set(LOCAL_FUNC.findall(code)) | names_in(LOCAL_VARS.findall(code)) | names_in(PARAMS.findall(code)) \
            | names_in(FOR_VARS.findall(code))
        for m in NS_USE.finditer(code):
            name = m.group(1) + "." + m.group(2)
            if m.group(3):
                use["ns"].setdefault(name, rel)
            else:
                tested.add(name)
            use["ns"].setdefault(name, rel)
        for m in re.finditer(r"(?<![\w.])(C_\w+)\b(?!\s*\.)", code):
            tested.add(m.group(1))
        for m in BARE_CALL.finditer(code):
            name = m.group(1)
            if name in KEYWORDS or name in LUA or name in local or name in own_globals or name.startswith("C_"):
                continue
            use["call"].setdefault(name, rel)
        for m in VIA_GLOBAL.finditer(code):
            owner = m.group(1)
            if owner in local or owner in own_globals or owner.startswith("C_") or owner in LUA:
                continue
            use["via"].setdefault(owner + m.group(2) + m.group(3), rel)
        for m in BARE_REF.finditer(code):
            tested.add(m.group(1))
        for m in FIELD_REF.finditer(code):
            tested.add("." + m.group(1))
        for m in METHOD_CALL.finditer(code):
            use["method"].setdefault(m.group(1), rel)
        lines = code.split("\n")
        for pos, s in strings:
            if not EVENT_RE.match(s):
                continue
            before = code[:pos]
            line_no = before.count("\n")
            head = before[before.rfind("\n") + 1:]
            direct = REGISTER.search(head)
            in_loop = "{" in head and any(LOOP_REGISTER.search(l) for l in lines[line_no:line_no + 6])
            if direct or in_loop:
                use["event"].setdefault(s, rel)
    return use, tested, own_methods


def check(update=False):
    """Returns (passed, failed, lines to print)."""
    lists = load_lists()
    if not lists:
        return 0, 0, ["API check skipped: no dev/tests/api/retail.txt or forever.txt (see dev/tools/make_api_list.py)."]
    reviewed = load_reviewed()
    use, tested, own_methods = scan()
    clients = sorted(lists)
    problems = []  # (key, where, what)

    def have(kind, name):
        return [c for c in clients if name in lists[c][kind]]

    def judge(kind_label, name, where, kinds, guarded, exact=None):
        """guarded: tested for before use, possibly only through its namespace. exact: the name
        itself is tested, which is what excuses a name no client has."""
        found = set()
        for k in kinds:
            found.update(have(k, name))
        if not found:
            if guarded if exact is None else exact:
                return  # tested for before use: harmless where it doesn't exist
            problems.append((name, where, "%s isn't in any client's list" % kind_label))
        elif len(found) < len(clients) and not guarded:
            missing = [c for c in clients if c not in found]
            problems.append((name, where, "%s is missing on %s and is never tested for before use" % (kind_label, ", ".join(missing))))

    for name, where in sorted(use["ns"].items()):
        namespace = name.split(".")[0]
        judge("game function", name, where, ("F",), name in tested or namespace in tested, exact=name in tested)
    for name, where in sorted(use["call"].items()):
        if have("F", name) or have("U", name):
            judge("game function", name, where, ("F", "U"), name in tested)
        elif have("L", name):
            problems.append((name, where, "is Blizzard Lua code; calling it from the addon can taint"))
        elif name not in tested:
            problems.append((name, where, "global call isn't in any client's list"))
    for name, where in sorted(use["via"].items()):
        owner, method = re.split(r"[.:]", name)
        # a widget method the game provides isn't Blizzard Lua, even where a mixin redefines the name
        if have("L", owner) and have("D", method) and not have("W", method):
            problems.append((name, where, "is Blizzard Lua code; calling it from the addon can taint"))
    for name, where in sorted(use["method"].items()):
        if name in own_methods or name in STRING_METHODS:
            continue
        judge("method", name, where, ("M",), ("." + name) in tested)
    for name, where in sorted(use["event"].items()):
        judge("event", name, where, ("E",), False)

    new = [p for p in problems if p[0] not in reviewed]
    stale = sorted(n for n in reviewed if n not in {p[0] for p in problems})
    lines = []
    total = sum(len(v) for v in use.values())
    if update:
        fresh = not os.path.exists(REVIEWED) or os.path.getsize(REVIEWED) == 0
        with open(REVIEWED, "a", encoding="utf-8", newline="\n") as f:
            if fresh:
                f.write("# Names the API check would flag, each looked at and accepted, with the reason.\n")
            for name, where, what in new:
                f.write("%s  # TODO review: %s (%s)\n" % (name, what, where))
        lines.append("Added %d entries to %s. Replace each TODO with the reason it's fine, or fix the code." % (len(new), os.path.relpath(REVIEWED, ROOT)))
        return total - len(new), 0, lines
    for name, where, what in new:
        lines.append("FAIL api: %s (%s): %s" % (name, where, what))
    todo = sorted(n for n, why in reviewed.items() if why.startswith("TODO"))
    lines.append("API check (%s): %d names used, %d accepted in reviewed.txt, %d new problems."
                 % (" + ".join(clients), total, len(problems) - len(new), len(new)))
    if todo:
        lines.append("  %d reviewed entries still say TODO." % len(todo))
    risks = sorted(n for n, why in reviewed.items() if why.startswith("RISK"))
    if risks:
        lines.append("  %d known taint risks still to fix: %s" % (len(risks), ", ".join(risks)))
    if stale:
        lines.append("  No longer needed in reviewed.txt: " + ", ".join(stale[:12]) + (" ..." if len(stale) > 12 else ""))
    return total - len(new), len(new), lines


if __name__ == "__main__":
    p, f, out = check(update="--update" in sys.argv)
    print("\n".join(out))
    sys.exit(1 if f else 0)
