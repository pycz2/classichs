#!/usr/bin/env python3
"""The architecture map of the developer pages (dev/<lang>/architecture.html).

The content lives in tools/arch_data.py: the system's blocks, each block's parts, data and
protocols, and the step-by-step flows, in English and Russian. A source reference there is
("path", "a substring of one line"): this script finds that line in the current code and turns
the reference into a GitHub link to it (…/blob/main/<path>#L<n>), so the line numbers never go
stale. A missing file, an anchor found on no line or on several lines, or an unknown block id
stops the build (tools/build_site.sh runs this through tools/site_docs.py).

Usage: python3 tools/arch_page.py --check     (every reference and id, without building)
"""
import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import arch_data as D  # noqa: E402
import site_docs  # noqa: E402

ROOT = site_docs.ROOT
## The name a reference points at, when its anchor is a definition: "func show_menu(" -> show_menu.
SYMBOL = re.compile(r"\b(?:func|fn|def|function|struct|enum|class|trait|const|static var|var|type)\s+(\w+)")
WORDS = {
    "en": {"where": "Where you are", "search": "Search: a file, a function, a message…", "zoom": "Zoom", "zoom_in": "Zoom in",
           "zoom_out": "Zoom out", "fit": "Fit", "system": "The system", "components": "Components", "flows": "Flows",
           "flows_n": "flows", "parts": "Parts", "steps": "steps", "data": "Data and state", "protocol": "Protocols and messages",
           "talks_to": "Talks to:", "takes_part": "Takes part:", "runtime": "while playing", "buildtime": "build, ship, deploy",
           "hint_system": "Click a block to open it. Drag to move; +/−, Ctrl + wheel or a pinch to zoom; ⤢ shows it whole.",
           "hint_comp": "Click a part to read about it; a dashed block opens another component.",
           "hint_flow": "Each numbered arrow is one step, in order. Click a step to see it below; the links open the code.",
           "k_comp": "Component", "k_flow": "Flow", "nothing": "Nothing found"},
    "ru": {"where": "Где вы", "search": "Поиск: файл, функция, сообщение…", "zoom": "Масштаб", "zoom_in": "Крупнее",
           "zoom_out": "Мельче", "fit": "Целиком", "system": "Система", "components": "Компоненты", "flows": "Потоки",
           "flows_n": "потоков", "parts": "Части", "steps": "шагов", "data": "Данные и состояние", "protocol": "Протоколы и сообщения",
           "talks_to": "Связан с:", "takes_part": "Участвуют:", "runtime": "во время игры", "buildtime": "сборка, выпуск, развёртывание",
           "hint_system": "Нажмите на блок, чтобы открыть его. Тащите, чтобы сдвинуть; +/−, Ctrl + колесо или щипок — масштаб; ⤢ — целиком.",
           "hint_comp": "Нажмите на часть, чтобы прочитать о ней; пунктирный блок открывает другой компонент.",
           "hint_flow": "Каждая пронумерованная стрелка — один шаг, по порядку. Нажмите на шаг, чтобы увидеть его ниже; ссылки ведут в код.",
           "k_comp": "Компонент", "k_flow": "Поток", "nothing": "Ничего не найдено"},
}


class Refs:
    """Source references -> {href, label}; every problem is collected, then reported at once."""

    def __init__(self):
        self.errors, self.lines, self.count = [], {}, 0

    def __call__(self, ref, where):
        path, anchor = (ref, None) if isinstance(ref, str) else ref
        f = ROOT / path
        if not f.exists():
            self.errors.append(f"{where}: no file {path}")
            return {"href": site_docs.GITHUB + path, "label": path}
        self.count += 1
        if anchor is None:
            return {"href": site_docs.GITHUB + path.rstrip("/"), "label": path}
        if path not in self.lines:
            self.lines[path] = f.read_text(encoding="utf-8", errors="replace").split("\n")
        hits = [i + 1 for i, line in enumerate(self.lines[path]) if anchor in line]
        if len(hits) != 1:
            self.errors.append(f"{where}: {path}: {anchor!r} is on {len(hits)} lines {hits[:5]} (needs exactly one)")
            return {"href": site_docs.GITHUB + path, "label": path}
        name = SYMBOL.search(anchor)
        label = f"{path}:{hits[0]}" + (f" {name.group(1)}" if name else "")
        return {"href": f"{site_docs.GITHUB}{path}#L{hits[0]}", "label": label}


def data(lang, refs=None):
    """The page's window.ARCH for one language."""
    refs = refs or Refs()
    nm = site_docs.names()
    ctx = site_docs.Ctx()
    i = 0 if lang == "en" else 1
    t = lambda v: site_docs.fill(v[i] if isinstance(v, tuple) else v, nm) if v is not None else ""  # noqa: E731
    md = lambda v: site_docs.markdown(t(v), ctx)[0] if v else ""  # noqa: E731
    line = lambda v: site_docs.inline(t(v), ctx) if v else ""  # noqa: E731
    errors = refs.errors
    comp_ids = {c["id"] for c in D.COMPS}
    flow_ids = {f["id"] for f in D.FLOWS}

    def need(cond, msg):
        if not cond:
            errors.append(msg)

    comps = []
    for c in D.COMPS:
        need(c["layer"] in D.LAYERS, f"{c['id']}: unknown layer {c['layer']}")
        parts = []
        for p in c.get("parts", []):
            ext = p.get("ext")
            need(not ext or ext in comp_ids, f"{c['id']}/{p['id']}: unknown component {ext}")
            name = t(p.get("name")) or (t(next(x["name"] for x in D.COMPS if x["id"] == ext)) if ext in comp_ids else "?")
            parts.append({"id": p["id"], "name": name, "sub": t(p.get("sub")), "x": p["x"], "y": p["y"], "span": p.get("span", 1),
                          "ext": ext, "text": line(p.get("text")),
                          "files": [refs(r, f"{c['id']}/{p['id']}") for r in p.get("files", [])]})
        part_ids = {p["id"] for p in parts}
        for e in c.get("arrows", []):
            need(e["from"] in part_ids and e["to"] in part_ids, f"{c['id']}: arrow {e['from']} -> {e['to']}: unknown part")
        for f in c.get("flows", []):
            need(f in flow_ids, f"{c['id']}: unknown flow {f}")
        comps.append({"id": c["id"], "name": t(c["name"]), "sub": t(c.get("sub")), "layer": c["layer"], "x": c["x"], "y": c["y"],
                      "w": c.get("w"), "h": c.get("h"), "short": line(c["short"]), "text": md(c.get("text")),
                      "gx": c.get("gx"), "gy": c.get("gy"), "bw": c.get("bw"), "parts": parts,
                      "arrows": [dict(e, label=t(e.get("label"))) for e in c.get("arrows", [])],
                      "data": [[line(a), line(b)] for a, b in c.get("data", [])],
                      "protocol": [[line(a), line(b)] for a, b in c.get("protocol", [])],
                      "flows": c.get("flows", [])})
    for e in D.ARROWS:
        need(e["from"] in comp_ids and e["to"] in comp_ids, f"system arrow {e['from']} -> {e['to']}: unknown component")
    flows = []
    for f in D.FLOWS:
        need(f["home"] in comp_ids, f"flow {f['id']}: unknown home {f['home']}")
        lanes = []
        for ln in f["lanes"]:
            ln = {"id": ln} if isinstance(ln, str) else ln
            comp = ln.get("comp", ln["id"] if ln["id"] in comp_ids else None)
            need(comp is None or comp in comp_ids, f"flow {f['id']}: lane {ln['id']}: unknown component {comp}")
            base = next((x for x in D.COMPS if x["id"] == comp), None)
            lanes.append({"id": ln["id"], "name": t(ln.get("name")) or (t(base["name"]) if base else ln["id"]), "sub": t(ln.get("sub")),
                          "layer": ln.get("layer") or (base["layer"] if base else "ext"), "comp": comp})
        lane_ids = {ln["id"] for ln in lanes}
        steps = []
        for k, s in enumerate(f["steps"], 1):
            need(s[0] in lane_ids and s[1] in lane_ids, f"flow {f['id']} step {k}: unknown lane {s[0]} or {s[1]}")
            steps.append({"from": s[0], "to": s[1], "label": t(s[2]), "text": line(s[3]),
                          "refs": [refs(r, f"flow {f['id']} step {k}") for r in (s[4] if len(s) > 4 else [])]})
        flows.append({"id": f["id"], "home": f["home"], "title": t(f["title"]), "short": line(f["short"]), "lanes": lanes, "steps": steps,
                      "more": md(f.get("more"))})
    used = {x for c in D.COMPS for x in c.get("flows", [])}
    for f in D.FLOWS:
        need(f["id"] in used, f"flow {f['id']} is listed by no component")
    return {"lang": lang, "title": t(D.TITLE), "doc_title": f"{t(D.TITLE)} — {nm['name']}", "words": WORDS[lang],
            "layers": {k: {"name": t(v["name"]), "color": v["color"]} for k, v in D.LAYERS.items()},
            "system": {"text": md(D.SYSTEM)}, "comps": comps,
            "arrows": [dict(e, label=t(e.get("label"))) for e in D.ARROWS], "flows": flows}


def body(lang):
    """(html, toc) of the page body for tools/site_docs.py; raises SystemExit on a broken reference."""
    refs = Refs()
    arch = data(lang, refs)
    if refs.errors:
        raise SystemExit("architecture page: broken references in tools/arch_data.py:\n  " + "\n  ".join(refs.errors))
    lead = site_docs.inline(site_docs.fill(D.LEAD[0 if lang == "en" else 1], site_docs.names()), site_docs.Ctx())
    blob = json.dumps(arch, ensure_ascii=False, separators=(",", ":")).replace("</", "<\\/")
    return (f'<h1>{arch["title"]}</h1>\n<p class="lead">{lead}</p>\n<div id="arch" class="arch"></div>\n'
            f'<noscript><p>{arch["system"]["text"]}</p></noscript>\n<script>window.ARCH={blob}</script>\n'
            f'<script src="../arch.js"></script>'), []


def check():
    refs = Refs()
    for lang in ("en", "ru"):
        data(lang, refs)
    if refs.errors:
        print("architecture page: broken references:\n  " + "\n  ".join(sorted(set(refs.errors))))
        return 1
    print(f"arch_page: ok ({refs.count // 2} references, {len(D.COMPS)} components, {len(D.FLOWS)} flows)")
    return 0


if __name__ == "__main__":
    sys.exit(check() if sys.argv[1:] == ["--check"] else print(__doc__) or 2)
