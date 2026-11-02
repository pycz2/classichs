#!/usr/bin/env python3
"""The card-script API as the engine registers it: the hooks a card may have, the target
kinds and every g.* function with its arguments, read from rust/engine/src/lua.rs, and
the words for each from docs/packs/api.md. The site's API reference is made from it
(tools/site_docs.py), so it always lists what the engine really has.

  python3 tools/lua_api.py           # the extracted API as JSON
  python3 tools/lua_api.py --check   # exit 1 when lua.rs and api.md disagree (a function, a hook,
                                     # an argument count missing or extra on one side)
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LUA_RS = ROOT / "rust/engine/src/lua.rs"
API_MD = ROOT / "docs/packs/api.md"

# How lua.rs reads argument i of a g.* function -> (type, optional)
READERS = [
    (r"\bmatch a\.get\((\d)\) \{\s+L::Nil => g\.em", "boolean, integer, string or nil", True),
    (r"L::Table\(_\) = a\.get\((\d)\)", "table", True),
    (r"\bopt_ent\(\w+, &a, (\d)\)", "entity", True),
    (r"\bent\(\w+, &a, (\d)\)", "entity", False),
    (r"\bplayer\(&a, (\d)\)", "player", False),
    (r"\bnum\(&a, (\d), -?\d+\)", "integer", True),
    (r"\bcard_arg\([^,]+, &a, (\d), \"\"\)", "card id", False),
    (r"\bcard_arg\([^,]+, &a, (\d), \"(\w+)\"\)", "card id ({})", False),
    (r"\btag_arg\(\w+, &a, (\d)\)", "tag", False),
    (r"\ba\.int\((\d)\)", "integer", False),
    (r"\ba\.opt_int\((\d)\)", "integer", True),
    (r"\ba\.string\((\d)\)", "string", False),
    (r"\ba\.table\((\d)\)", "table", False),
    (r"\ba\.get\((\d)\)\.truthy\(\)", "boolean", True),
    (r"\ba\.get\((\d)\)", "any", True),
    (r"\bevent_arg\(\w+, &a\)", "event table", False),  # always argument 0
]


def _bodies(src):
    """Function name -> its source text (fn items and q!/ql! one-liners)."""
    out = {}
    for m in re.finditer(r"^(?:fn (\w+)|q!\((\w+),|ql!\((\w+),)", src, re.M):
        name = m.group(1) or m.group(2) or m.group(3)
        nxt = re.compile(r"^(?:fn |q!\(|ql!\(|const |macro_rules!|///|// ---)", re.M).search(src, m.end())
        out[name] = (src[m.start():nxt.start() if nxt else len(src)], bool(m.group(3)))
    return out


def _args(body):
    """[{type, optional}] by position, from how the body reads its arguments."""
    seen = {}
    for pat, ty, opt in READERS:
        for m in re.finditer(pat, body):
            i = int(m.group(1)) if m.groups() else 0
            t = ty.format(m.group(2).lower()) if "{}" in ty else ty
            if i not in seen:
                seen[i] = {"type": t, "optional": opt}
            elif seen[i]["type"] == "any":  # a.get(i) checked for nil first, then read typed
                seen[i] = {"type": t, "optional": True}
            elif ty == "any" and seen[i]["type"] not in ("boolean",):
                seen[i]["optional"] = True
    return [seen.get(i, {"type": "any", "optional": True}) for i in range(max(seen) + 1)] if seen else []


def _returns(body, is_list):
    if is_list or "ids(" in body:
        return "list of entities"
    if ".list(" in body:
        return "list"
    if "new_table()" in body:
        return "table"
    if "opt_id(" in body or "map_or(L::Nil" in body:
        return "value or nil"
    if "none()" in body:
        return "nothing"
    return "value"


def extract(src=None):
    src = src if src is not None else LUA_RS.read_text()
    bodies = _bodies(src)

    def table(start):
        block = src[src.index(start):]
        block = block[block.index("&[\n"):]
        block = block[:block.index("]")]
        return re.findall(r'\("(g\.\w+)", (\w+?)(?:::<\$t>)?\)', block)

    funcs = []
    for kind, start in (("query", "macro_rules! queries"), ("action", "const ACTIONS")):
        for name, fn in table(start):
            body, is_list = bodies[fn]
            funcs.append({"name": name, "kind": kind, "args": _args(body), "returns": _returns(body, is_list)})
    hooks_src = src[src.index("fn hooks("):]
    hooks_src = hooks_src[:hooks_src.index("unknown hook")]
    hooks = []
    for arm in re.findall(r'^\s+((?:"\w+"(?: \| )?)+) =>', hooks_src, re.M):
        names = re.findall(r'"(\w+)"', arm)
        if any(f'key == "{n}"' in hooks_src for n in names):  # one arm, different hooks ("on" | "now")
            hooks += [[n] for n in names]
        else:
            hooks.append(names)  # a name and its aliases
    readonly = re.findall(r'"(\w+)" => h\.\w+ = Some\(f!\(true\)\)', hooks_src)
    bases_src = src[src.index("let base_of"):]
    bases = re.findall(r'"(\w+)"(?: \| "\w+")* => Base::', bases_src[:bases_src.index("};")])
    return {"functions": funcs, "hooks": [{"name": h[0], "aliases": h[1:], "readonly": h[0] in readonly} for h in hooks],
            "targets": bases}


def _code_spans(cell):
    return re.findall(r"`([^`]+)`", cell)


def documented(md=None):
    """From api.md: g.* function -> {signature, text, section}; hook -> text."""
    md = md if md is not None else API_MD.read_text()
    funcs, hooks, section = {}, {}, ""
    for line in md.splitlines():
        if line.startswith("#"):
            section = line.lstrip("# ").strip()
        if not line.startswith("| `"):
            continue
        cells = [c.strip() for c in re.split(r"(?<!\\)\|", line)[1:-1]]
        if section == "Hooks":
            name = _code_spans(cells[0])[0]
            hooks[name] = {"signature": cells[1], "text": cells[2]}
            continue
        for sig in _code_spans(cells[0]):
            m = re.match(r"(g\.\w+)\((.*)\)$", sig)
            if m:
                funcs[m.group(1)] = {"signature": sig, "params": re.findall(r"\w+", m.group(2)),
                                     "text": cells[1], "section": section}
    return funcs, hooks


def check():
    api, (docs, hook_docs) = extract(), documented()
    problems = []
    names = {f["name"] for f in api["functions"]}
    for f in api["functions"]:
        d = docs.get(f["name"])
        if not d:
            problems.append(f"{f['name']} is in lua.rs but not in docs/packs/api.md")
        elif len(d["params"]) != len(f["args"]):
            problems.append(f"{f['name']}: api.md names {len(d['params'])} arguments ({d['signature']}), "
                            f"lua.rs reads {len(f['args'])}")
    problems += [f"{n} is in docs/packs/api.md but not in lua.rs" for n in sorted(set(docs) - names)]
    hook_names = {h["name"] for h in api["hooks"]}
    problems += [f"hook {n} is in lua.rs but not in api.md" for n in sorted(hook_names - set(hook_docs))]
    problems += [f"hook {n} is in api.md but not in lua.rs" for n in sorted(set(hook_docs) - hook_names)]
    return problems


if __name__ == "__main__":
    if "--check" in sys.argv:
        bad = check()
        for p in bad:
            print("ERROR:", p)
        api = extract()
        print(f"lua_api: {len(api['functions'])} functions, {len(api['hooks'])} hooks, {len(bad)} problems")
        sys.exit(1 if bad else 0)
    print(json.dumps(extract(), indent=1))
