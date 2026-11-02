#!/usr/bin/env python3
"""Builds the site's pages for game makers ("For developers") into <out>/dev:

- the guides, written in Markdown in English and Russian: site/dev/<lang>/<page>.md
  -> dev/<lang>/<page>.html;
- the API reference, made from the engine itself (tools/lua_api.py: rust/engine/src/lua.rs,
  with the words of docs/packs/api.md) -> dev/<lang>/api.html;
- the format reference, docs/packs/*.md as they are (English) -> dev/ref/<page>.html.

The game's name comes from site/name.js ({name}, {full_name} in the texts). A small
Markdown subset: headings, paragraphs, lists, tables, fenced code (Lua, JSON and shell
are coloured), > notes, inline code, bold, italics and links. Used by tools/build_site.sh.

Usage: python3 tools/site_docs.py <out dir>      (self-check: python3 tools/site_docs.py --test)
"""
import html
import json
import re
import shutil
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import lua_api  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
SITE = ROOT / "site"
LANGS = ["en", "ru"]
GITHUB = "https://github.com/pycz2/classichs/blob/main/"
## The guides in the sidebar's order: page -> its menu label per language.
PAGES = {
    "index": {"en": "Overview", "ru": "Обзор"},
    "packs": {"en": "Make your own game", "ru": "Своя игра"},
    "lua": {"en": "Card scripts in Lua", "ru": "Скрипты карт на Lua"},
    "api": {"en": "Engine API (g.*)", "ru": "API движка (g.*)"},
    "testing": {"en": "Testing and validating", "ru": "Проверка и тесты"},
}
## docs/packs/<name>.md rendered as the reference (English).
REFERENCE = {"format": "Pack format", "rules": "rules.json", "cards": "cards.json", "fx": "Visual effects",
             "lua": "The Lua subset", "api": "Hooks and g.* (source)"}
WORDS = {
    "en": {"guides": "Guides", "reference": "Reference (English)", "contents": "On this page", "home": "Home",
           "play": "Play", "other": "Русский", "edit": "Source of this page", "lang_name": "English",
           "generated": "Generated from rust/engine/src/lua.rs by tools/lua_api.py, with the words of docs/packs/api.md.",
           "menu": "Menu"},
    "ru": {"guides": "Руководства", "reference": "Справочник (English)", "contents": "На этой странице", "home": "Главная",
           "play": "Играть", "other": "English", "edit": "Исходник страницы", "lang_name": "Русский",
           "generated": "Собрано из rust/engine/src/lua.rs инструментом tools/lua_api.py, описания — из docs/packs/api.md (на английском).",
           "menu": "Меню"},
}


def names():
    """{name, full_name} from site/name.js: the one place the game's name is written."""
    src = (SITE / "name.js").read_text(encoding="utf-8")
    return {k: re.search(k + r':\s*"([^"]+)"', src).group(1) for k in ("name", "full_name")}


# --- Markdown -----------------------------------------------------------------------------------

def slug(text):
    """GitHub's heading anchors: lower case, punctuation dropped, spaces to dashes."""
    text = re.sub(r"<[^>]+>", "", text).lower()
    return re.sub(r"[^\w\- ]", "", text, flags=re.U).strip().replace(" ", "-")


LUA_KEYWORDS = r"\b(and|break|do|else|elseif|end|false|for|function|if|in|local|nil|not|or|repeat|return|then|true|until|while)\b"
TOKENS = {
    "lua": [("c", r"--\[\[[\s\S]*?\]\]|--[^\n]*"), ("s", r'"(?:\\.|[^"\\\n])*"|\'(?:\\.|[^\'\\\n])*\'|\[\[[\s\S]*?\]\]'),
            ("k", LUA_KEYWORDS), ("f", r"\bg\.\w+|\blib\.\w+|\blist\.\w+"), ("n", r"\b0x[0-9a-fA-F]+\b|\b\d+\b")],
    "json": [("c", r"//[^\n]*"), ("p", r'"(?:\\.|[^"\\])*"(?=\s*:)'), ("s", r'"(?:\\.|[^"\\])*"'),
             ("k", r"\b(true|false|null)\b"), ("n", r"-?\b\d+\b")],
    "sh": [("c", r"(?<![\w$])#[^\n]*"), ("s", r'"(?:\\.|[^"\\])*"|\'[^\']*\''), ("k", r"(?<![\w/.-])(cd|godot|python3|cargo|tools/[\w./-]+)\b")],
}


def highlight(code, lang, api_names=()):
    rules = TOKENS.get({"shell": "sh", "bash": "sh", "console": "sh"}.get(lang, lang))
    if not rules:
        return html.escape(code)
    rx = re.compile("|".join(f"(?P<{k}{i}>{p})" for i, (k, p) in enumerate(rules)))
    out, pos = [], 0
    for m in rx.finditer(code):
        out.append(html.escape(code[pos:m.start()]))
        kind, text = m.lastgroup[0], m.group(0)
        word = html.escape(text)
        if kind == "f" and text in api_names:
            word = f'<a href="{api_names[text]}">{word}</a>'
        out.append(f'<span class="t{kind}">{word}</span>')
        pos = m.end()
    out.append(html.escape(code[pos:]))
    return "".join(out)


def inline(text, ctx):
    """Inline Markdown: `code`, **bold**, *italics*, [links](url); the rest escaped."""
    codes = []

    def keep(m):  # a code span becomes a placeholder, so ** and * may wrap it
        code = m.group(2).replace("\\|", "|")
        fn = re.match(r"(g\.\w+)(\(|$)", code)
        body = html.escape(code)
        if fn and fn.group(1) in ctx.api and "<a " not in body:
            body = f'<a href="{ctx.api[fn.group(1)]}">{body}</a>'
        codes.append(f"<code>{body}</code>")
        return f"\x00{len(codes) - 1}\x00"

    s = html.escape(re.sub(r"(`+)(.+?)\1", keep, text), quote=False)
    s = re.sub(r"\[([^\]]+)\]\(([^)\s]+)\)", lambda m: f'<a href="{ctx.link(m.group(2))}">{m.group(1)}</a>', s)
    s = re.sub(r"\*\*(.+?)\*\*", r"<b>\1</b>", s)
    s = re.sub(r"(?<![\w*])\*(?!\s)(.+?)(?<!\s)\*(?![\w*])", r"<i>\1</i>", s)
    s = s.replace("\\|", "|")
    return re.sub("\x00(\\d+)\x00", lambda m: codes[int(m.group(1))], s)


class Ctx:
    """How a page links: Markdown links to .md become .html pages; repo paths go to GitHub."""

    def __init__(self, api=None, md_dir=None):
        self.api = api or {}
        self.md_dir = md_dir  # a reference page: the docs/packs folder its links are relative to

    def link(self, url):
        if re.match(r"^(https?:|mailto:|#)", url):
            return url
        if self.md_dir is not None:
            path, _, frag = url.partition("#")
            if path.endswith(".md") and (ROOT / self.md_dir / path).exists() and Path(path).stem in REFERENCE:
                return Path(path).stem + ".html" + ("#" + frag if frag else "")
            return GITHUB + (Path(self.md_dir) / path).as_posix().rstrip("/") + ("#" + frag if frag else "")
        return url


def markdown(text, ctx):
    """(html, [(level, id, title)]) of a Markdown text."""
    lines = text.split("\n")
    out, toc, para, i = [], [], [], 0
    ids = set()

    def flush():
        if para:
            out.append(f"<p>{inline(' '.join(para), ctx)}</p>")
            para.clear()

    while i < len(lines):
        line = lines[i]
        fence = re.match(r"^```(\w*)\s*$", line)
        if fence:
            flush()
            j = i + 1
            while j < len(lines) and not lines[j].startswith("```"):
                j += 1
            code = "\n".join(lines[i + 1:j])
            lang = fence.group(1)
            label = f'<span class="code-lang">{lang}</span>' if lang else ""
            out.append(f'<pre class="code">{label}<code>{highlight(code, lang, ctx.api)}</code></pre>')
            i = j + 1
            continue
        h = re.match(r"^(#{1,4}) (.+)$", line)
        if h:
            flush()
            level, title = len(h.group(1)), inline(h.group(2).strip(), Ctx(md_dir=ctx.md_dir))
            hid = slug(title)
            while hid in ids:
                hid += "-1"
            ids.add(hid)
            if level > 1:
                toc.append((level, hid, html.unescape(re.sub(r"<[^>]+>", "", title))))
            anchor = f'<a class="anchor" href="#{hid}" aria-hidden="true">#</a>' if level > 1 else ""
            out.append(f'<h{level} id="{hid}">{title}{anchor}</h{level}>')
            i += 1
            continue
        if line.startswith("|") and i + 1 < len(lines) and re.match(r"^\|[\s:|-]+\|\s*$", lines[i + 1]):
            flush()
            rows = []
            while i < len(lines) and lines[i].startswith("|"):
                rows.append([c.strip() for c in re.split(r"(?<!\\)\|", lines[i].strip())[1:-1]])
                i += 1
            head = "".join(f"<th>{inline(c, ctx)}</th>" for c in rows[0])
            body = "".join("<tr>" + "".join(f"<td>{inline(c, ctx)}</td>" for c in r) + "</tr>" for r in rows[2:])
            out.append(f'<div class="table"><table><thead><tr>{head}</tr></thead><tbody>{body}</tbody></table></div>')
            continue
        item = re.match(r"^(\s*)([-*]|\d+\.) (.*)$", line)
        if item and not item.group(1):
            flush()
            tag = "ol" if item.group(2)[0].isdigit() else "ul"
            items = []
            while i < len(lines):
                m = re.match(r"^([-*]|\d+\.) (.*)$", lines[i])
                if m and (m.group(1)[0].isdigit()) == (tag == "ol"):
                    items.append([m.group(2)])
                elif items and lines[i].startswith("  ") and lines[i].strip():
                    items[-1].append(lines[i].lstrip(" ") if not re.match(r"^\s+([-*]|\d+\.) ", lines[i]) else lines[i].strip())
                else:
                    break
                i += 1

            def item(x):  # its text, then a list nested under it (indented "- " lines)
                k = next((j for j, s in enumerate(x) if j and re.match(r"^([-*]|\d+\.) ", s)), len(x))
                return inline(" ".join(x[:k]), ctx) + (markdown("\n".join(x[k:]), ctx)[0] if k < len(x) else "")

            out.append(f"<{tag}>" + "".join(f"<li>{item(x)}</li>" for x in items) + f"</{tag}>")
            continue
        if line.startswith(">"):
            flush()
            quote = []
            while i < len(lines) and lines[i].startswith(">"):
                quote.append(lines[i][1:].strip())
                i += 1
            kind = "tip" if quote and quote[0].lower().startswith(("**tip", "**совет")) else "note"
            out.append(f'<aside class="{kind}">{markdown(chr(10).join(quote), ctx)[0]}</aside>')
            continue
        if not line.strip():
            flush()
        elif line.strip() == "<!-- -->":
            pass
        else:
            para.append(line.strip())
        i += 1
    flush()
    return "\n".join(out), toc


# --- the API reference ---------------------------------------------------------------------------

API_TEXT = {
    "en": {"title": "Engine API: hooks and g.*", "lead":
           "Everything a card script can call and every hook it can have, as the engine registers them. "
           "Arguments in *italics* are optional. Types: *entity* — an entity id (a number), *player* — 0 or 1, "
           "*tag* — a mechanic name (the pack's or the engine's), *card id* — a string from cards.json. "
           "How these pieces fit together: [Card scripts in Lua](lua.html).",
           "hooks": "Hooks", "hooks_lead": "The keys of a card's hook set (a table returned from a script file). "
           "Read-only hooks run while the engine only looks at the game: their `g` has the queries only.",
           "targets": "Target kinds", "targets_lead": "For `target = \"…\"` or `target = {base = \"…\", filter = fn}`:",
           "queries": "Queries", "queries_lead": "Every hook can call these, read-only hooks too.",
           "actions": "Actions", "actions_lead": "They change the game; not in read-only hooks. An action on `nil` "
           "(or `-1`) as the entity does nothing.",
           "events": "Events", "fn": "Function", "args": "Arguments", "ret": "Returns", "what": "What it does",
           "hook": "Hook", "sig": "Value", "when": "When it runs", "ro": "read-only", "alias": "alias"},
    "ru": {"title": "API движка: хуки и g.*", "lead":
           "Всё, что скрипт карты может вызвать, и все хуки, которые у карты могут быть, — ровно так, как их "
           "регистрирует движок. Аргументы *курсивом* необязательны. Типы: *entity* — номер сущности (число), "
           "*player* — 0 или 1, *tag* — название механики (пака или движка), *card id* — строка из cards.json. "
           "Как всё это складывается вместе: [Скрипты карт на Lua](lua.html).",
           "hooks": "Хуки", "hooks_lead": "Ключи набора хуков карты (таблицы, которую возвращает файл скрипта). "
           "Хуки «только чтение» движок вызывает, когда лишь смотрит на игру: в их `g` есть только запросы.",
           "targets": "Виды целей", "targets_lead": "Для `target = \"…\"` или `target = {base = \"…\", filter = fn}`:",
           "queries": "Запросы", "queries_lead": "Их можно вызывать из любого хука, в том числе «только чтение».",
           "actions": "Действия", "actions_lead": "Меняют игру; в хуках «только чтение» недоступны. Действие над `nil` "
           "(или `-1`) ничего не делает.",
           "events": "События", "fn": "Функция", "args": "Аргументы", "ret": "Возвращает", "what": "Что делает",
           "hook": "Хук", "sig": "Значение", "when": "Когда вызывается", "ro": "только чтение", "alias": "синоним"},
}


def api_markdown_events():
    md = lua_api.API_MD.read_text(encoding="utf-8")
    part = md[md.index("## Events"):]
    return part[part.index("\n") + 1:part.index("\n## ", 1)]


def api_page(lang, ctx):
    w = API_TEXT[lang]
    api = lua_api.extract()
    funcs, hooks = lua_api.documented()
    out = [f"<h1>{w['title']}</h1>", f'<p class="lead">{inline(w["lead"], ctx)}</p>',
           f'<p class="generated">{html.escape(WORDS[lang]["generated"])}</p>']
    toc = []

    def h2(key):
        toc.append((2, key, w[key]))
        out.append(f'<h2 id="{key}">{w[key]}<a class="anchor" href="#{key}" aria-hidden="true">#</a></h2>')

    h2("hooks")
    out.append(f"<p>{inline(w['hooks_lead'], ctx)}</p>")
    rows = []
    for h in api["hooks"]:
        d = hooks.get(h["name"], {})
        tags = "".join(f' <span class="badge">{w["alias"]} <code>{a}</code></span>' for a in h["aliases"])
        tags += f' <span class="badge ro">{w["ro"]}</span>' if h["readonly"] else ""
        rows.append(f'<tr id="hook-{h["name"]}"><td><code>{h["name"]}</code>{tags}</td>'
                    f'<td>{inline(d.get("signature", ""), ctx)}</td><td>{inline(d.get("text", ""), ctx)}</td></tr>')
    out.append(f'<div class="table"><table><thead><tr><th>{w["hook"]}</th><th>{w["sig"]}</th><th>{w["when"]}</th>'
               f'</tr></thead><tbody>{"".join(rows)}</tbody></table></div>')
    h2("targets")
    out.append(f"<p>{inline(w['targets_lead'], ctx)} " + ", ".join(f"<code>{t}</code>" for t in api["targets"]) + "</p>")
    for kind, key in (("query", "queries"), ("action", "actions")):
        h2(key)
        out.append(f"<p>{inline(w[key + '_lead'], ctx)}</p>")
        rows = []
        for f in (x for x in api["functions"] if x["kind"] == kind):
            d = funcs[f["name"]]
            params = []
            for p, a in zip(d["params"], f["args"]):
                p = f"<i>{p}</i>" if a["optional"] else p
                params.append(f'{p}<span class="ty">: {html.escape(a["type"])}</span>')
            rows.append(f'<tr id="{f["name"]}"><td><code class="fn">{f["name"]}</code></td><td class="sig">'
                        f'({", ".join(params)})</td><td class="ty">{f["returns"]}</td><td>{inline(d["text"], ctx)}</td></tr>')
        out.append(f'<div class="table api"><table><thead><tr><th>{w["fn"]}</th><th>{w["args"]}</th><th>{w["ret"]}</th>'
                   f'<th>{w["what"]}</th></tr></thead><tbody>{"".join(rows)}</tbody></table></div>')
    h2("events")
    out.append(markdown(api_markdown_events(), ctx)[0])
    return "\n".join(out), toc


# --- pages ----------------------------------------------------------------------------------------

def page(title, body, toc, lang, here, depth, nm, other=None):
    """A whole HTML page. depth: folders below dev/ (1 for dev/en/x.html); here: the page key."""
    up = "../" * (depth + 1)  # to the site's root
    dev = "../" * depth  # to dev/
    w = WORDS[lang if lang in WORDS else "en"]
    lang_dir = lang if lang in LANGS else "en"
    guide = "".join(f'<li><a href="{dev}{lang_dir}/{k}.html"{" aria-current=page" if here == k else ""}>{v[lang_dir]}</a></li>'
                    for k, v in PAGES.items())
    ref = "".join(f'<li><a href="{dev}ref/{k}.html"{" aria-current=page" if here == "ref/" + k else ""}>{v}</a></li>'
                  for k, v in REFERENCE.items())
    contents = "".join(f'<li class="l{lv}"><a href="#{i}">{html.escape(t)}</a></li>' for lv, i, t in toc)
    switch = f'<a class="lang-link" href="{other}" hreflang="{"ru" if lang_dir == "en" else "en"}">{w["other"]}</a>' if other else ""
    title_text = re.sub(r"<[^>]+>", "", title)
    return f"""<!doctype html>
<html lang="{lang_dir}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{html.escape(title_text)} — {html.escape(nm['name'])} for developers</title>
<meta name="description" content="{html.escape(nm['full_name'])}: how to make your own card game — the game pack format, Lua card scripts, the engine API, testing.">
<link rel="icon" href="{up}favicon.svg" type="image/svg+xml">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link href="https://fonts.googleapis.com/css2?family=Tektur:wght@500;700;800&family=Exo+2:ital,wght@0,400;0,600;0,700;1,400&family=JetBrains+Mono:wght@400;600&display=swap" rel="stylesheet">
<link rel="stylesheet" href="{up}style.css">
<link rel="stylesheet" href="{up}dev.css">
</head>
<body class="docs">
<header class="top">
  <a class="brand" href="{up}">{html.escape(nm['name'])}<span class="brand-sub">dev</span></a>
  <nav>
    <a href="{up}">{w['home']}</a>
    <a href="{up}play/" class="nav-play">{w['play']}</a>
    <a href="https://github.com/pycz2/classichs" target="_blank" rel="noopener">GitHub</a>
    {switch}
  </nav>
</header>
<div class="docs-wrap">
  <aside class="side">
    <p class="side-h">{w['guides']}</p><ul>{guide}</ul>
    <p class="side-h">{w['reference']}</p><ul>{ref}</ul>
  </aside>
  <main class="doc">
  <details class="side-m"><summary>{w['menu']}</summary>
    <p class="side-h">{w['guides']}</p><ul>{guide}</ul>
    <p class="side-h">{w['reference']}</p><ul>{ref}</ul>
  </details>
{body}
  </main>
  <aside class="toc"><p class="side-h">{w['contents']}</p><ul>{contents}</ul></aside>
</div>
<footer><p>{html.escape(nm['full_name'])} · MIT · <a href="https://github.com/pycz2/classichs">GitHub</a></p></footer>
</body>
</html>
"""


def fill(text, nm):
    return text.replace("{name}", nm["name"]).replace("{full_name}", nm["full_name"])


def build(out):
    out = Path(out) / "dev"
    nm = names()
    api_links = {f["name"]: f"api.html#{f['name']}" for f in lua_api.extract()["functions"]}
    written = []
    for lang in LANGS:
        (out / lang).mkdir(parents=True, exist_ok=True)
        other_lang = "ru" if lang == "en" else "en"
        for key in PAGES:
            if key == "api":
                body, toc = api_page(lang, Ctx(api_links))
                title = API_TEXT[lang]["title"]
            else:
                src = SITE / "dev" / lang / f"{key}.md"
                body, toc = markdown(fill(src.read_text(encoding="utf-8"), nm), Ctx(api_links))
                title = re.search(r"<h1[^>]*>(.*?)</h1>", body).group(1)
                body += f'\n<p class="src"><a href="{GITHUB}site/dev/{lang}/{key}.md">{WORDS[lang]["edit"]}</a></p>'
            (out / lang / f"{key}.html").write_text(page(title, body, toc, lang, key, 1, nm, f"../{other_lang}/{key}.html"),
                                                    encoding="utf-8")
            written.append(f"{lang}/{key}.html")
    (out / "ref").mkdir(parents=True, exist_ok=True)
    ref_api = {k: "../en/" + v for k, v in api_links.items()}
    for key in REFERENCE:
        md = (ROOT / "docs/packs" / f"{key}.md").read_text(encoding="utf-8")
        body, toc = markdown(md, Ctx(ref_api, md_dir="docs/packs"))
        title = re.search(r"<h1[^>]*>(.*?)</h1>", body).group(1)
        body += f'\n<p class="src"><a href="{GITHUB}docs/packs/{key}.md">docs/packs/{key}.md</a></p>'
        (out / "ref" / f"{key}.html").write_text(page(title, body, [t for t in toc if t[0] == 2], "en", "ref/" + key, 1, nm),
                                                 encoding="utf-8")
        written.append(f"ref/{key}.html")
    # dev/ itself: the guide in the page language the landing remembered (or the browser's)
    (out / "index.html").write_text(f"""<!doctype html>
<html lang="en"><head><meta charset="utf-8"><title>{html.escape(nm['name'])} for developers</title>
<meta name="viewport" content="width=device-width, initial-scale=1">
<script>var l;try{{l=localStorage.getItem("lang")}}catch(e){{}}l=l||navigator.language||"";location.replace((/^ru/.test(l)?"ru":"en")+"/index.html")</script>
</head><body style="background:#070a14;color:#e8f4ff;font-family:sans-serif"><p><a href="en/index.html" style="color:#3ee8ff">English</a> · <a href="ru/index.html" style="color:#3ee8ff">Русский</a></p></body></html>
""", encoding="utf-8")
    shutil.copy(SITE / "dev.css", out.parent / "dev.css")
    print(f"site docs: {len(written)} pages in {out}")
    return written


def _test():
    c = Ctx({"g.damage": "api.html#g.damage"})
    h, toc = markdown("# T\n\n## A `x`\n\ntext *it* **b** [l](x.html)\n\n- one\n  more\n- two\n\n| a | b |\n|---|---|\n| `p\\|q` | 2 |\n\n"
                      "```lua\nlocal x = g.damage(me, t, 2) -- hit\n```\n\n> **Tip:** ok", c)
    assert '<h2 id="a-x">' in h and toc == [(2, "a-x", "A x")], h
    assert "<i>it</i>" in h and "<b>b</b>" in h and '<a href="x.html">l</a>' in h
    assert "<li>one more</li>" in h and "<code>p|q</code>" in h
    assert '<a href="api.html#g.damage">g.damage</a>' in h and '<span class="tc">-- hit</span>' in h
    assert '<aside class="tip">' in h
    n = markdown("1. a\n   - b\n   - c\n2. d", c)[0]
    assert n == "<ol><li>a<ul><li>b</li><li>c</li></ul></li><li>d</li></ol>", n
    assert inline("**`.x`** *a*", c) == "<b><code>.x</code></b> <i>a</i>"
    assert slug("The `g` library") == "the-g-library" and slug("10. Build recipes and `tools/pack.py`") == "10-build-recipes-and-toolspackpy"
    r = Ctx(md_dir="docs/packs")
    assert r.link("rules.md") == "rules.html" and r.link("schema/") == GITHUB + "docs/packs/schema"
    assert names()["name"]
    print("site_docs: ok")


if __name__ == "__main__":
    if sys.argv[1:] == ["--test"]:
        _test()
    else:
        build(sys.argv[1])
