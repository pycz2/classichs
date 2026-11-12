#!/usr/bin/env python3
"""The owner's local report of the expansions after Naxxramas (plan 2026-11-11, step 12): one HTML page with
each set's facts (release day, build, cards, older cards changed, mechanics, engine features, decks) and
screenshots of the real client, with the owner's local custom packs (Blizzard art: the report stays local,
never committed or published) and the distributed pack for comparison.

Facts come from git (the step commits), data/<set>_cards.json, packs/<set>/ and docs/packs/api.md; the shots'
scenes from tools/expansions_report/<set>.json (data/card_tests' scene and steps format). A set whose pack is
not there yet (K&C, The Witchwood) gets an empty slot: add its scenes file and rerun.

Usage (from the repo root):
  python3 tools/expansions_report.py                    # the page from the facts and the shots there are
  python3 tools/expansions_report.py check [set ...]    # headless: plays each scene, prints the tables
  python3 tools/expansions_report.py shots [set ...] [--custom|--dist] [--only=name,...] [--langs=en,ru]
  python3 tools/expansions_report.py selftest           # the commit text parser's own check
Shots need a window and run one at a time (a lock file); each run has its own user dir. Out:
~/ClassicHS-local/report-expansions/ (index.html, shots/<set>/<custom|dist>/<lang>_<name>.jpg, assets/).
"""
import fcntl
import html
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LOCAL = Path.home() / "ClassicHS-local"
OUT = LOCAL / "report-expansions"
SCENES = ROOT / "tools" / "expansions_report"
GODOT = shutil.which("godot") or "godot"

# dir, English name, Russian name, release day, step of the plan, HearthstoneJSON set code
SETS = [
    ("gvg", "Goblins vs Gnomes", "Гоблины и гномы", "2014-12-08", 1, "GVG"),
    ("brm", "Blackrock Mountain", "Чёрная гора", "2015-04-02", 2, "BRM"),
    ("tgt", "The Grand Tournament", "Большой турнир", "2015-08-24", 3, "TGT"),
    ("loe", "The League of Explorers", "Лига исследователей", "2015-11-12", 4, "LOE"),
    ("og", "Whispers of the Old Gods", "Пробуждение древних богов", "2016-04-26", 5, "OG"),
    ("kara", "One Night in Karazhan", "Вечеринка в Каражане", "2016-08-11", 6, "KARA"),
    ("msg", "Mean Streets of Gadgetzan", "Злачный город Прибамбасск", "2016-12-01", 7, "GANGS"),
    ("ungoro", "Journey to Un'Goro", "Экспедиция в Ун'Горо", "2017-04-06", 8, "UNGORO"),
    ("icc", "Knights of the Frozen Throne", "Рыцари Ледяного Трона", "2017-08-10", 9, "ICECROWN"),
    ("loot", "Kobolds & Catacombs", "Кобольды и катакомбы", "2017-12-07", 10, "LOOTAPALOOZA"),
    ("gil", "The Witchwood", "Ведьмин лес", "2018-04-12", 11, "GILNEAS"),
]
CLASSES = {"HERO_01": "Воин", "HERO_02": "Шаман", "HERO_03": "Разбойник", "HERO_04": "Паладин", "HERO_05": "Охотник",
           "HERO_06": "Друид", "HERO_07": "Чернокнижник", "HERO_08": "Маг", "HERO_09": "Жрец"}
FIELDS = {"cost": "стоимость", "attack": "атака", "health": "здоровье", "durability": "прочность", "race": "раса",
          "keywords": "ключевые слова", "text": "текст", "rarity": "редкость", "mechanics": "механики",
          "classes": "классы", "set": "набор", "collectible": "коллекционная"}
FIXED_CAPTIONS = {"menu": "Меню игры: фон и оформление набора", "collection": "Коллекция с фильтром по набору (значок набора на картах)"}


def git(*args):
    return subprocess.run(["git", *args], cwd=ROOT, capture_output=True, text=True, check=True).stdout


def load(path, default=None):
    try:
        return json.loads(Path(path).read_text())
    except (OSError, ValueError):
        return default


def local_name(v, loc="ruRU"):
    if isinstance(v, dict):
        return v.get(loc) or v.get("enUS") or next(iter(v.values()), "")
    return v or ""


_names = None


def card_name(cid, loc="ruRU"):
    """A card's name in the release data of its set (Classic's ids carry VAN_ in the packs)."""
    global _names
    if _names is None:
        _names = {}
        for f in sorted((ROOT / "data").glob("*cards.json")):
            for c in load(f, []):
                _names[c["id"]] = c.get("name")
    return local_name(_names.get(cid) or _names.get(cid.removeprefix("VAN_")), loc) or cid


# --- facts ---------------------------------------------------------------------------------------------------

def commits(s):
    """The set's commits, oldest first: its step's and the later fixes that name the set."""
    _, en, _, _, step, _ = s
    out = []
    for line in git("log", "--reverse", "--format=%H\x1f%ad\x1f%s", "--date=short").splitlines():
        h, day, subj = line.split("\x1f")
        if f"step {step}:" in subj or en in subj:
            body = git("log", "-1", "--format=%b", h)
            body = "\n".join(l for l in body.splitlines() if not re.match(r"(Co-Authored-By|Claude-Session):", l)).strip()
            out.append({"hash": h[:7], "full": h, "day": day, "subject": subj, "body": body})
    return out


def api_rows(cs):
    """docs/packs/api.md rows the set's commits added: [(name, what)]."""
    rows = {}
    for c in cs:
        for l in git("show", "--format=", c["full"], "--", "docs/packs/api.md").splitlines():
            m = re.match(r"^\+\| `([^`]+)`[^|]*\|(.*)", l)
            if m and not l.startswith("+++"):
                rows[m.group(1)] = re.sub(r"\s*\|\s*$", "", m.group(2)).replace("|", " · ").strip()
    return list(rows.items())


def facts(s):
    d, en, ru, day, step, code = s
    src = ROOT / "packs" / d
    f = {"dir": d, "en": en, "ru": ru, "day": day, "step": step, "code": code, "ready": (src / "manifest.json").exists()}
    if not f["ready"]:
        return f
    man = load(src / "manifest.json", {})
    f["id"], f["version"] = man.get("id"), man.get("version")
    f["about_ru"] = man.get("description", {}).get("ru", "")
    cards = load(ROOT / "data" / f"{d}_cards.json", [])
    ids = {c["id"] for c in cards}
    col = [c for c in cards if c.get("collectible")]
    f["collectible"], f["tokens"] = len(col), len(cards) - len(col)
    f["rarity"] = {r: sum(1 for c in col if c.get("rarity") == r) for r in ["COMMON", "RARE", "EPIC", "LEGENDARY"]}
    patch = load(src / "cards.patch.json", {})
    f["older"] = []
    for cid, p in patch.items():
        if cid in ids:
            continue
        what = [f"{FIELDS.get(k, k)} {v if not isinstance(v, list) else ', '.join(map(str, v)) or '—'}"
                for k, v in p.items() if k not in ("script", "fx", "text")]
        if "text" in p:
            what.append("текст")
        if "script" in p:
            what.append("поведение (скрипт)")
        f["older"].append((card_name(cid), cid, "; ".join(what)))
    f["texts"] = len(load(src / "cards.texts.json", {}))
    loc_ru, loc_en = load(src / "locales" / "ru.json", {}), load(src / "locales" / "en.json", {})
    f["mechanics"] = [(k, v.get("name", k), v.get("tip", ""), loc_en.get("mechanics", {}).get(k, {}).get("name", k))
                      for k, v in loc_ru.get("mechanics", {}).items()]
    f["decks"] = []
    for p in sorted((src / "decks").glob("*.json")):
        dk = load(p, {})
        desc = dk.get("description", {})
        f["decks"].append((dk.get("name", p.stem), CLASSES.get(dk.get("champion"), dk.get("champion", "")),
                           desc.get("ru", "") if isinstance(desc, dict) else str(desc)))
    theme = load(src / "ui" / "theme.json", {}).get("colors", {})
    f["accent"] = "#" + theme.get("accent", "f1c24b")[:6]
    f["accent2"] = "#" + theme.get("panel_border", theme.get("button_border", "c99a2e"))[:6]
    f["commits"] = commits(s)
    f["api"] = api_rows(f["commits"])
    pack_body = next((c["body"] for c in f["commits"] if c["subject"].startswith(f"Expansions, step {step}:")
                      and "engine" not in c["subject"]), "")
    m = re.search(r"patch\s+([\d.]+)(\s+of\s+[\d-]+)?", pack_body)
    f["patch"] = " ".join((m.group(1) + (m.group(2) or "")).split()) if m else ""
    m = re.search(r"HearthstoneJSON\s+build\s+(\d+)", pack_body)
    f["build"] = m.group(1) if m else ""
    for kind, path in [("dist_size", ROOT / "build" / "packs" / f"{d}.cardpack"), ("custom_size", LOCAL / f"{d}-custom-art.cardpack")]:
        f[kind] = path.stat().st_size if path.exists() else 0
    return f


# --- shots ---------------------------------------------------------------------------------------------------

def scenes_of(d):
    return load(SCENES / f"{d}.json")


def run_driver(d, variant, sc, langs, only, check=False):
    pack = LOCAL / f"{d}-custom-art.cardpack" if variant == "custom" else ROOT / "build" / "packs" / f"{d}.cardpack"
    if not pack.exists():
        print(f"{d} {variant}: no {pack}")
        return 1
    set_code = next(s[5] for s in SETS if s[0] == d)
    job = {"pack": str(pack), "set_key": set_code, "langs": langs, "out": str(OUT / "shots" / d / variant),
           "tab": sc.get("tab", ""), "signature": sc.get("signature", []), "scenes": sc.get("scenes", []), "check": check}
    if variant == "custom":
        job.update(art="custom", sound="original")
    if only:
        job["only"] = only
    with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as t:
        json.dump(job, t)
    user_dir = f"classichs-report/{d}-{variant}{'-check' if check else ''}"
    env = dict(os.environ, REPORT_USER_DIR=user_dir)
    cmd = [GODOT, *(["--headless"] if check else []), "--path", str(ROOT), "--script", "res://tools/expansions_shots.gd", "--", t.name]
    try:
        r = subprocess.run(cmd, env=env, capture_output=True, text=True, timeout=900)
    finally:
        os.unlink(t.name)
        # the run's own user dir (its installed copy of the pack): Godot's data dir on macOS
        shutil.rmtree(Path.home() / "Library" / "Application Support" / user_dir, ignore_errors=True)
    lines = [l for l in r.stdout.splitlines() if check or l.startswith(("ERROR", "saved", "SHOTS"))]
    lines += [l for l in r.stderr.splitlines() if "SCRIPT ERROR" in l or "Parse Error" in l]
    print(f"== {d} {variant}\n" + "\n".join(lines))
    done = any(l.startswith(("SHOTS DONE: 0", "CHECK DONE: 0")) for l in lines)
    return 0 if done else 1


def shots(args):
    want = [a for a in args if not a.startswith("--")]
    opt = dict(a[2:].split("=", 1) if "=" in a else (a[2:], "") for a in args if a.startswith("--"))
    check = opt.pop("check", None) is not None
    variants = ["custom"] if "custom" in opt else ["dist"] if "dist" in opt else ["custom", "dist"]
    sets = [s[0] for s in SETS if (not want or s[0] in want) and scenes_of(s[0])]
    bad = 0
    OUT.mkdir(parents=True, exist_ok=True)
    with open(OUT / ".shots.lock", "w") as lock:
        if not check:
            fcntl.flock(lock, fcntl.LOCK_EX)  # one window at a time: the runs never fight over the screen
        for d in sets:
            sc = scenes_of(d)
            for v in variants:
                if check and v == "dist":
                    continue
                only = opt["only"].split(",") if opt.get("only") else (sc.get("dist") if v == "dist" else None)
                langs = opt["langs"].split(",") if opt.get("langs") else (["en"] if v == "dist" else ["en", "ru"])
                bad += run_driver(d, v, sc, langs, only, check)
    return 1 if bad else 0


# --- the page ------------------------------------------------------------------------------------------------

def esc(s):
    return html.escape(str(s), quote=True)


def md_inline(s):
    """Commit text: `code` and plain text, escaped."""
    return re.sub(r"`([^`]+)`", r"<code>\1</code>", esc(s))


def commit_html(c):
    """A commit as HTML: its paragraphs (wrapped lines joined) and its "- " lists."""
    items = []  # ["p" | "li", text]; a wrapped line continues the item before it
    for l in c["body"].splitlines():
        if not l.strip():
            items.append(["", ""])
        elif l.startswith("- "):
            items.append(["li", l[2:]])
        elif items and items[-1][0] and (l.startswith("  ") or items[-1][0] == "p"):
            items[-1][1] += " " + l.strip()
        else:
            items.append(["p", l.strip()])
    out, lis = [], []
    for kind, text in items + [["", ""]]:
        if kind != "li" and lis:
            out.append("<ul>" + "".join(f"<li>{md_inline(x)}</li>" for x in lis) + "</ul>")
            lis = []
        if kind == "li":
            lis.append(text)
        elif kind == "p":
            out.append(f"<p>{md_inline(text)}</p>")
    return (f'<div class="commit"><div class="csub"><code>{c["hash"]}</code> {c["day"]} · {md_inline(c["subject"])}</div>'
            + "".join(out) + "</div>")


def shot_list(d, sc):
    """[(variant, lang, name, file, caption)] of the shots there are, in the scenes file's order."""
    order = ["menu", "collection"] + [f"card_{i}" for i in sc.get("signature", [])]
    caps = {}
    for x in sc.get("scenes", []):
        cap = x.get("caption", {}).get("ru", x["name"])
        order += [x["name"], x["name"] + "_card", x["name"] + "_history"]
        caps[x["name"]] = cap
        caps[x["name"] + "_card"] = cap + ". Карта крупно"
        caps[x["name"] + "_history"] = cap + ". Строка истории"
    out = []
    for v in ["custom", "dist"]:
        folder = OUT / "shots" / d / v
        files = {p.name: p for p in folder.glob("*.jpg")} if folder.exists() else {}
        for lang in ["ru", "en"]:
            for n in order:
                fn = f"{lang}_{n}.jpg"
                if fn in files:
                    cap = FIXED_CAPTIONS.get(n) or caps.get(n) or (card_name(n[5:]) if n.startswith("card_") else n)
                    out.append((v, lang, n, f"shots/{d}/{v}/{fn}", cap))
    return out


CSS = """
:root{--bg:#0f0c0a;--card:#1d1813;--card2:#262019;--line:#3d3226;--text:#efe6d6;--muted:#b1a38c;--dim:#7d705e;
--gold:#f1c24b;--radius:14px;--shadow:0 10px 30px rgba(0,0,0,.45);--acc:#f1c24b;--acc2:#c99a2e}
*{box-sizing:border-box}html{scroll-behavior:smooth;scroll-padding-top:64px}
body{margin:0;background:radial-gradient(1200px 600px at 70% -10%,#33240f 0,transparent 60%),var(--bg);color:var(--text);
font:15px/1.6 Inter,system-ui,-apple-system,sans-serif}
a{color:var(--acc)}code{font:13px ui-monospace,Menlo,monospace;background:rgba(255,255,255,.06);padding:1px 5px;border-radius:5px}
h1,h2,h3{font-family:Alegreya,Georgia,serif;margin:0;letter-spacing:.2px}
.wrap{max-width:1200px;margin:0 auto;padding:0 20px}
nav{position:sticky;top:0;z-index:50;background:rgba(15,12,10,.9);backdrop-filter:blur(8px);border-bottom:1px solid var(--line)}
nav .wrap{display:flex;gap:10px;align-items:center;padding:9px 20px}
nav .links{display:flex;gap:4px;align-items:center;overflow-x:auto;scrollbar-width:none;flex:1;min-width:0}
nav a{white-space:nowrap;text-decoration:none;color:var(--muted);padding:5px 11px;border-radius:999px;font-weight:600;font-size:13.5px;
display:flex;gap:6px;align-items:center;border:1px solid transparent}
nav a img{width:18px;height:18px;object-fit:contain}
nav a:hover{color:var(--text);border-color:var(--line)}nav a.todo{opacity:.45}
nav .lang{margin-left:auto;display:flex;gap:4px}nav .lang button{background:var(--card2);color:var(--muted);border:1px solid var(--line);
border-radius:999px;padding:4px 10px;font-weight:700;cursor:pointer}nav .lang button.on{color:#120d09;background:var(--gold);border-color:var(--gold)}
header.hero{padding:48px 0 18px}
.kicker{color:var(--gold);font-weight:700;text-transform:uppercase;letter-spacing:2px;font-size:12px}
.hero h1{font-size:46px;line-height:1.08;margin:8px 0 12px;background:linear-gradient(180deg,#ffe28a,#d39a2a);-webkit-background-clip:text;background-clip:text;color:transparent}
.lead{font-size:17px;color:var(--muted);max-width:880px}
.stats{display:grid;grid-template-columns:repeat(auto-fit,minmax(150px,1fr));gap:12px;margin:24px 0}
.stat{background:linear-gradient(180deg,var(--card2),var(--card));border:1px solid var(--line);border-radius:var(--radius);padding:13px 16px}
.stat b{display:block;font:800 28px Alegreya,Georgia,serif;color:var(--gold)}.stat span{color:var(--muted);font-size:13px}
.box{background:linear-gradient(180deg,var(--card2),var(--card));border:1px solid var(--line);border-radius:var(--radius);padding:18px 20px;margin:14px 0}
.box h3{font-size:19px;margin-bottom:8px;color:var(--acc)}
.cols{display:grid;grid-template-columns:1fr 1fr;gap:14px}@media(max-width:860px){.cols{grid-template-columns:1fr}.hero h1{font-size:34px}}
@media(max-width:600px){.wrap,nav .wrap,.banner .wrap{padding-left:16px;padding-right:16px}.box{padding:14px}.banner h2{font-size:28px}
.gallery{grid-template-columns:1fr}td,th{padding:5px 4px}}
body{overflow-wrap:anywhere}
ul{padding-left:20px;margin:6px 0}li{margin:3px 0}
table{width:100%;border-collapse:collapse;font-size:14px}td,th{text-align:left;padding:6px 8px;border-bottom:1px solid var(--line);vertical-align:top}
th{color:var(--muted);font-weight:600;font-size:12.5px;text-transform:uppercase;letter-spacing:.6px}
.chips{display:flex;flex-wrap:wrap;gap:6px}.chip{background:rgba(255,255,255,.05);border:1px solid var(--line);border-radius:999px;padding:2px 10px;font-size:13px}
.chip code{background:none;padding:0}
section.set{border-top:1px solid var(--line);padding:0 0 30px;--acc:var(--sacc);--acc2:var(--sacc2)}
.banner{position:relative;min-height:220px;display:flex;align-items:flex-end;background:#000 center/cover no-repeat;border-bottom:3px solid var(--acc)}
.banner:before{content:"";position:absolute;inset:0;background:linear-gradient(180deg,rgba(0,0,0,.05),rgba(0,0,0,.82))}
.banner .wrap{position:relative;width:100%;padding:26px 20px;display:flex;gap:18px;align-items:flex-end}
.banner img.mark{width:74px;height:74px;object-fit:contain;filter:drop-shadow(0 4px 10px #000)}
.banner h2{font-size:38px;color:#fff;text-shadow:0 2px 12px #000;line-height:1.1}.banner .sub{color:var(--acc);font-weight:700}
.facts{display:grid;grid-template-columns:repeat(auto-fit,minmax(160px,1fr));gap:10px;margin:18px 0}
.fact{border-left:3px solid var(--acc);background:var(--card);padding:8px 12px;border-radius:0 10px 10px 0}
.fact b{display:block;font-size:20px;color:var(--text)}.fact span{color:var(--muted);font-size:12.5px}
.gallery{display:grid;grid-template-columns:repeat(auto-fill,minmax(270px,1fr));gap:12px;margin-top:10px}
figure{margin:0;background:var(--card);border:1px solid var(--line);border-radius:12px;overflow:hidden;cursor:zoom-in;transition:transform .15s,border-color .15s}
figure:hover{transform:translateY(-2px);border-color:var(--acc)}figure img{display:block;width:100%;aspect-ratio:16/9;object-fit:cover}
figcaption{padding:7px 10px;font-size:13px;color:var(--muted)}figcaption .tag{float:right;font-size:11px;font-weight:700;color:var(--acc);margin-left:6px}
body.l-ru .only-en,body.l-en .only-ru{display:none}
details{margin:8px 0}summary{cursor:pointer;color:var(--acc);font-weight:600}
.commit{border-left:2px solid var(--line);padding:4px 0 4px 12px;margin:10px 0;font-size:13.5px}.csub{font-weight:600;margin-bottom:4px}
.todo-slot{padding:40px 20px;text-align:center;color:var(--dim);border:2px dashed var(--line);border-radius:var(--radius);margin:20px 0}
.about{color:var(--muted);font-style:italic;max-width:900px}
#lb{position:fixed;inset:0;background:rgba(0,0,0,.92);display:none;z-index:100;align-items:center;justify-content:center;flex-direction:column}
#lb.on{display:flex}#lb img{max-width:96vw;max-height:86vh;box-shadow:var(--shadow);border-radius:6px}
#lb .cap{color:#ddd;margin-top:10px;font-size:14px;padding:0 16px;text-align:center}
#lb button{position:absolute;top:50%;transform:translateY(-50%);background:rgba(255,255,255,.08);color:#fff;border:0;font-size:34px;width:52px;height:72px;cursor:pointer;border-radius:8px}
#lb .prev{left:10px}#lb .next{right:10px}#lb .x{top:30px;right:14px;left:auto;height:52px;transform:none}
footer{color:var(--dim);font-size:13px;padding:30px 0 50px}
"""

JS = """
const lb=document.getElementById('lb'),li=lb.querySelector('img'),lc=lb.querySelector('.cap');let list=[],at=0;
function show(){const f=list[at];li.src=f.querySelector('img').src;lc.textContent=f.querySelector('figcaption').textContent}
document.querySelectorAll('figure').forEach(f=>f.addEventListener('click',()=>{
 list=[...f.closest('.gallery').querySelectorAll('figure')].filter(x=>x.offsetParent);at=list.indexOf(f);show();lb.classList.add('on')}));
lb.querySelector('.prev').onclick=e=>{e.stopPropagation();at=(at+list.length-1)%list.length;show()};
lb.querySelector('.next').onclick=e=>{e.stopPropagation();at=(at+1)%list.length;show()};
lb.onclick=()=>lb.classList.remove('on');
addEventListener('keydown',e=>{if(!lb.classList.contains('on'))return;if(e.key=='Escape')lb.classList.remove('on');
 if(e.key=='ArrowLeft')lb.querySelector('.prev').click();if(e.key=='ArrowRight')lb.querySelector('.next').click()});
function lang(l){document.body.className='l-'+l;document.querySelectorAll('nav .lang button').forEach(b=>b.classList.toggle('on',b.dataset.l==l));
 try{localStorage.setItem('exp-lang',l)}catch(e){}}
document.querySelectorAll('nav .lang button').forEach(b=>b.onclick=()=>lang(b.dataset.l));
try{lang(localStorage.getItem('exp-lang')||'ru')}catch(e){lang('ru')}
"""


def plural(n, one, few, many):
    """'21 карта', '3 карты', '534 карты', '11 карт'."""
    k = many if n % 100 in range(11, 15) else one if n % 10 == 1 else few if n % 10 in (2, 3, 4) else many
    return f"{n} {k}"


def mb(n):
    return f"{n / 1048576:.0f} МБ" if n else "—"


def set_section(f, assets):
    d = f["dir"]
    mark = f"assets/set_{d}.png" if (assets / f"set_{d}.png").exists() else ""
    bg = f"assets/menu_{d}.jpg" if (assets / f"menu_{d}.jpg").exists() else ""
    style = f'style="--sacc:{f.get("accent", "#f1c24b")};--sacc2:{f.get("accent2", "#c99a2e")}"'
    h = [f'<section class="set" id="{d}" {style}>',
         f'<div class="banner" style="background-image:url({bg})"><div class="wrap">' + (f'<img class="mark" src="{mark}" alt="">' if mark else "") +
         f'<div><div class="sub">Шаг {f["step"]} · {f["day"]}</div><h2>{esc(f["ru"])}</h2><div style="color:#ddd">{esc(f["en"])}</div></div></div></div>',
         '<div class="wrap">']
    if not f["ready"]:
        h.append(f'<div class="todo-slot">Набор ещё в работе. Когда появятся packs/{d}/ и tools/expansions_report/{d}.json, '
                 f'запустите <code>python3 tools/expansions_report.py shots {d}</code> и <code>python3 tools/expansions_report.py</code>.</div></div></section>')
        return "".join(h)
    h.append(f'<p class="about">{esc(f["about_ru"])}</p>')
    facts_ = [(f["day"], "день выхода"), (f["patch"] or "—", "патч"), (f["build"] or "—", "сборка HearthstoneJSON"),
              (f["collectible"], "новых коллекционных карт"), (f["tokens"], "жетонов и служебных карт"),
              (len(f["older"]), "старых карт изменено"), (f["rarity"]["LEGENDARY"], "легендарных"), (len(f["decks"]), "готовых колод"),
              (mb(f["dist_size"]), "пакет для всех"), (mb(f["custom_size"]), "свой пакет с артом")]
    h.append('<div class="facts">' + "".join(f'<div class="fact"><b>{esc(a)}</b><span>{b}</span></div>' for a, b in facts_) + "</div>")
    sc = scenes_of(d) or {}
    sh = shot_list(d, sc)
    custom = [x for x in sh if x[0] == "custom"]
    dist = [x for x in sh if x[0] == "dist"]

    def fig(x):
        v, lang, n, src, cap = x
        cls = f"only-{lang}"
        tag = ("RU" if lang == "ru" else "EN") + (" · пакет для всех" if v == "dist" else "")
        return f'<figure class="{cls}"><img loading="lazy" src="{src}" alt=""><figcaption><span class="tag">{tag}</span>{esc(cap)}</figcaption></figure>'

    if custom:
        h.append('<div class="box"><h3>Снимки из клиента</h3><p style="margin:0;color:var(--muted)">Свой локальный пакет с картинками Blizzard. '
                 'Язык снимков переключается вверху справа.</p><div class="gallery">' + "".join(fig(x) for x in custom) + "</div></div>")
    if dist:
        pairs = []
        for x in dist:
            twin = next((y for y in custom if y[1] == x[1] and y[2] == x[2]), None)
            if twin:
                pairs.append(twin)
            pairs.append(x)
        h.append('<div class="box"><h3>Свой пакет и пакет для всех</h3><p style="margin:0;color:var(--muted)">Слева картинки Blizzard из своего пакета, '
                 'справа процедурные рисунки распространяемого пакета (build/packs). Снимки на английском.</p><div class="gallery">' +
                 "".join(fig(x).replace(' class="only-en"', "").replace(' class="only-ru"', "") for x in pairs) + "</div></div>")
    if not sh:
        h.append(f'<div class="todo-slot">Снимков пока нет: <code>python3 tools/expansions_report.py shots {d}</code></div>')
    mech = "".join(f'<tr><td><b>{esc(n)}</b><br><span style="color:var(--dim)">{esc(e)}</span></td><td>{esc(t)}</td></tr>' for _, n, t, e in f["mechanics"])
    api = "".join(f'<span class="chip" title="{esc(w)}"><code>{esc(n)}</code></span>' for n, w in f["api"])
    h.append('<div class="cols"><div class="box"><h3>Новые механики</h3>' +
             (f"<table>{mech}</table>" if mech else '<p style="color:var(--muted)">Новых ключевых слов нет: механики набора сделаны скриптами карт.</p>') +
             '</div><div class="box"><h3>Возможности движка</h3><p style="margin:0 0 8px;color:var(--muted);font-size:13.5px">Что добавилось в '
             'docs/packs/api.md на этом шаге (наведите, чтобы прочитать описание).</p>' + (f'<div class="chips">{api}</div>' if api else "—") + "</div></div>")
    decks = "".join(f'<tr><td><b>{esc(n)}</b></td><td>{esc(c)}</td><td>{esc(t)}</td></tr>' for n, c, t in f["decks"])
    h.append(f'<div class="box"><h3>Готовые колоды</h3><table><tr><th>Колода</th><th>Класс</th><th>Описание и источник</th></tr>{decks}</table></div>')
    older = "".join(f'<tr><td><b>{esc(n)}</b> <code>{esc(c)}</code></td><td>{esc(w)}</td></tr>' for n, c, w in f["older"])
    h.append(f'<div class="box"><h3>Старые карты на день выхода</h3><p style="margin:0 0 8px;color:var(--muted);font-size:13.5px">Карты прошлых '
             f'наборов, которые пакет меняет (cards.patch.json). Имена и тексты сборки того дня (cards.texts.json): {plural(f["texts"], "карта", "карты", "карт")}.</p>'
             f'<details><summary>{plural(len(f["older"]), "карта", "карты", "карт")}</summary><table>{older}</table></details></div>')
    h.append('<div class="box"><h3>Из журнала изменений</h3><details><summary>Сообщения коммитов набора (' + str(len(f["commits"])) +
             ', по-английски)</summary>' + "".join(commit_html(c) for c in f["commits"]) + "</details></div>")
    h.append("</div></section>")
    return "".join(h)


FOUNDATION = ["20e4e28", "d8d5463", "017fdc8", "6129eff", "d419399"]


def page():
    fs = [facts(s) for s in SETS]
    assets = OUT / "assets"
    assets.mkdir(parents=True, exist_ok=True)
    for f in fs:
        ui = ROOT / "packs" / f["dir"] / "ui"
        for src, dst in [(ui / f"set_{f['dir']}.png", f"set_{f['dir']}.png"), (ui / "menu.jpg", f"menu_{f['dir']}.jpg")]:
            if src.exists():
                shutil.copyfile(src, assets / dst)
    ready = [f for f in fs if f["ready"]]
    n_shots = sum(len(shot_list(f["dir"], scenes_of(f["dir"]) or {})) for f in fs)
    stats = [(f"{len(ready)} из {len(SETS)}", "наборов готово"), (sum(f["collectible"] for f in ready), "новых коллекционных карт"),
             (sum(f["tokens"] for f in ready), "жетонов"), (sum(len(f["older"]) for f in ready), "правок старых карт"),
             (sum(len(f["decks"]) for f in ready), "готовых колод"), (sum(len(f["api"]) for f in ready), "строк в api.md"),
             (n_shots, "снимков")]
    nav = "".join(f'<a href="#{f["dir"]}" class="{"" if f["ready"] else "todo"}">' +
                  (f'<img src="assets/set_{f["dir"]}.png" alt="">' if (assets / f"set_{f['dir']}.png").exists() else "") + f'{esc(f["ru"])}</a>' for f in fs)
    found = []
    for h_ in FOUNDATION:
        try:
            subj = git("log", "-1", "--format=%s", h_).strip()
            body = git("log", "-1", "--format=%b", h_)
            day = git("log", "-1", "--format=%ad", "--date=short", h_).strip()
        except subprocess.CalledProcessError:
            continue
        body = "\n".join(l for l in body.splitlines() if not re.match(r"(Co-Authored-By|Claude-Session):", l)).strip()
        found.append(commit_html({"hash": h_, "day": day, "subject": subj, "body": body}))
    def engine_line(f):
        kw = ", ".join(m[1] for m in f["mechanics"]) or "новых ключевых слов нет"
        subj = next((c["subject"] for c in f["commits"] if "engine features" in c["subject"]), "")
        what = re.sub(r"^.*?engine features of [^(;]*", "", subj).strip(" ;()")
        return (f'<li><b>{esc(f["ru"])}</b>: {esc(kw)}' + (f'; <span style="color:var(--muted)">{md_inline(what)}</span>' if what else "")
                + f'; {plural(len(f["api"]), "новая строка", "новые строки", "новых строк")} в api.md</li>')
    engine = "".join(engine_line(f) for f in ready)
    top = f"""
<header class="hero"><div class="wrap">
<div class="kicker">Classic HS · дополнения после Наксрамаса · локальный отчёт</div>
<h1>Одиннадцать наборов, каждый как в день выхода</h1>
<p class="lead">Каждое дополнение стало отдельной игрой (пакетом): в нём все карты наборов до него, и каждая карта такая, какой была в день выхода
этого набора. Стоимость, характеристики, тексты на 8 языках, расы и поведение взяты из сборки того дня. Отчёт только для себя. Снимки сделаны со своими
пакетами с картинками Blizzard, поэтому публиковать отчёт нельзя.</p>
<div class="stats">{"".join(f'<div class="stat"><b>{esc(a)}</b><span>{b}</span></div>' for a, b in stats)}</div>
<div class="cols">
<div class="box"><h3>Что сделано</h3><ul>
<li>Пакеты по цепочке: каждый строится на предыдущем (packs/&lt;набор&gt;/recipe.json, поле <code>base</code>), правки и скрипты идут по порядку, поздняя правка побеждает.</li>
<li>Каждый пакет самодостаточный: ему не нужен другой установленный пакет, все картинки цепочки лежат внутри.</li>
<li>Ограничения размера: до 1 ГиБ на пакет и до 2 ГиБ в распакованном виде.</li>
<li>Пакеты наборов не входят в сборки клиента (APK, настольная и веб-версия остаются маленькими): это файлы выпуска и пакеты на сервере.</li>
<li>У каждой карты есть тест (data/card_tests), у каждого набора есть готовые колоды той меты и боты, которые ими играют.</li>
<li>Тесты идут параллельно: 8 процессов Godot, у каждого свой каталог user://, полный прогон около минуты; тесты Rust на всех ядрах.</li>
<li>Клиент: жёлтое свечение карты в руке, когда её условие выполнено; фитиль горит справа налево; значок набора на карте и фильтр по набору в коллекции; музыка легендарных карт.</li>
</ul></div>
<div class="box"><h3>Движок правил по наборам</h3><ul>{engine}</ul></div>
</div>
<div class="box"><h3>Основа: общие изменения для всех наборов</h3><details><summary>Сообщения коммитов ({len(found)}, по-английски)</summary>{"".join(found)}</details></div>
</div></header>"""
    sections = "".join(set_section(f, assets) for f in fs)
    doc = f"""<!doctype html><html lang="ru"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Дополнения Classic HS</title>
<link href="https://fonts.googleapis.com/css2?family=Alegreya:wght@700;800&family=Inter:wght@400;600;700&display=swap" rel="stylesheet">
<style>{CSS}</style></head><body class="l-ru">
<nav><div class="wrap"><div class="links"><a href="#top" style="color:var(--gold)">Classic HS</a>{nav}</div><div class="lang"><button data-l="ru">RU</button><button data-l="en">EN</button></div></div></nav>
<div id="top"></div>{top}{sections}
<footer><div class="wrap">Собрано скриптом tools/expansions_report.py из git, data/ и packs/. Снимки: tools/expansions_shots.gd.</div></footer>
<div id="lb"><button class="x">×</button><button class="prev">‹</button><img alt=""><div class="cap"></div><button class="next">›</button></div>
<script>{JS}</script></body></html>"""
    (OUT / "index.html").write_text(doc)
    print(f"{OUT / 'index.html'}: {len(ready)} sets, {n_shots} shots")
    return 0


def selftest():
    h = commit_html({"hash": "abc", "day": "d", "subject": "s", "body": "A pack\nbuilt on `x`:\n- one\n  more\n- two\nDone.\n\nLast."})
    assert "<p>A pack built on <code>x</code>:</p><ul><li>one more</li><li>two</li></ul><p>Done.</p><p>Last.</p>" in h, h
    print("selftest ok")
    return 0


if __name__ == "__main__":
    a = sys.argv[1:]
    if a and a[0] == "selftest":
        sys.exit(selftest())
    if a and a[0] == "shots":
        sys.exit(shots(a[1:]))
    if a and a[0] == "check":
        sys.exit(shots(a[1:] + ["--check"]))
    sys.exit(page())
