#!/usr/bin/env python3
"""Checks the card sounds and voice lines of a LOCAL pack (Blizzard's files: it only reads them, never copies them
anywhere).

Usage:
  python3 tools/check_sounds.py ~/ClassicHS-local/og                       a set's folder (set/, voice/<lang>/)
  python3 tools/check_sounds.py ~/ClassicHS-local/og-custom-art.cardpack   a built pack (sounds/<x>/, voice/<lang>/)
  python3 tools/check_sounds.py ~/ClassicHS-local/og --manifest ~/ClassicHS-local/audio-src/og/manifest.json \\
      --report ~/ClassicHS-local/audio-src/og-check.md
  Every set at once (the audit of ~/ClassicHS-local/audio-src/AUDIT.md):
  python3 tools/check_sounds.py --all --quiet --report-dir ~/ClassicHS-local/audio-src/check
  The same with the new roles' sources (each set's ~/ClassicHS-local/audio-src/<set>/manifest.json, when it exists):
  python3 tools/check_sounds.py --all --manifests --quiet --report-dir ~/ClassicHS-local/audio-src/check-roles
  Exit code: 2 with an error, 1 with a flag, else 0.

Options: --set <name> (a folder's set when the folder is not named after it), --no-audio (skip ffmpeg: no length,
silence or byte checks), --report <file.md|file.json>, --quiet (the summary only).

Where each file came from: tools/fetch_original_sounds.py plan_card() run again over the wiki's Cargo `Sound` rows
(cached in ~/ClassicHS-local/audio-src/sound_rows.json; ids missing there are asked once and added), and the
manifests of --manifest ({card id: {role: [wiki file names]}}, which win over plan_card; a role "voice_<kind>" is the
source of voice/<lang>/<card id>_<kind>; a list under "hit" also gives hit_2, hit_3, … in order when there is no
"hit_2" key). A Russian line comes from the same wiki file name, looked up in the Drive indexes
(~/ClassicHS-local/sounds/cache/ru_index*.json).

Findings checked by hand and found right are listed in ~/ClassicHS-local/audio-src/reviewed.json ({card id: {wiki file:
why}}); they are reported as info. A file of a new role with no manifest entry is info ("pass the --manifest").

Checks, per file (error = surely wrong, flag = look at it, info = shared by design or a note):
  name     the name is <card id>_<role>, the card is in the pack, the role is known
  source   the file has a known source
  owner    the source belongs to the card: its id, its English name (CamelCase or words), or a file of the documented
           tables (fetch_original_sounds SPELLS, ORIGINAL, GENERIC, ELEMENTS); another card's VO_<id>_ file = error
  role     the role word in the source's name agrees with the role (a *_Play* file used as _death is flagged)
  length   impacts, missiles, triggers, reveals, play, attack, death <= 8 s; music 1-40 s; an aim loop >= 0.3 s;
           voice <= 15 s; and the file is as long as its source (else it was made from another file)
  silent   the loudest point is below -50 dB
  same     one source (or identical bytes) on two different cards (shared underlays and table files: info)
  ru       a Russian line has the same source name as the English one, is as long as the downloaded Russian
           original, and has an English line next to it
  missing  a file the plan expects is not there (folders only)
Tests: python3 -m unittest tools/test_check_sounds.py
"""
import argparse
import concurrent.futures as cf
import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile
import wave
import zipfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import fetch_original_sounds as snd  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
LOCAL = Path("~/ClassicHS-local").expanduser()
CACHE = LOCAL / "sounds/cache"
ROWS = LOCAL / "audio-src/sound_rows.json"
WIKI_FILES = LOCAL / "audio-src/wiki_files.json"
# Findings checked by hand ({card id: {wiki file: why it is right}}): reported as info.
REVIEWED = LOCAL / "audio-src/reviewed.json"
SETS = ["classic", "naxx", "gvg", "brm", "tgt", "loe", "og", "kara", "msg", "ungoro", "icc", "loot", "gil"]

SET_ROLES = {"play", "attack", "death", "hit", "music", "aim", "missile", "trigger", "reveal", "progress", "complete",
             "choose"}
VOICE_KINDS = ({"play", "attack", "death", "trigger"} | set(snd.HERO_KINDS.values())
               | {"error_" + e for e in snd.ERRORS})
# The words of a source's name that tell its role, per role.
ROLE_TAGS = {
    "play": {"play", "cast", "precast", "summon", "birth", "enter", "spawn", "start", "launch", "equip"},
    "attack": {"attack", "swing"},
    "death": {"death", "die", "dies", "destroy", "destruction", "break"},
    "hit": {"impact", "hit", "target", "damage", "explode", "explosion", "ae"},
    "music": {"stinger", "music"},
    "aim": {"loop", "aim", "channel", "target", "idle"},
    "missile": {"missile", "missle", "projectile", "launch", "travel"},
    "trigger": {"trigger", "proc", "activate"},
    "reveal": {"reveal", "trigger", "secret"},
    "progress": {"progress", "quest"},
    "complete": {"complete", "quest", "reward"},
    "choose": {"choose", "discover", "adapt", "select", "choice"},
}
ALL_TAGS = set().union(*ROLE_TAGS.values())
# Words too common in sound names to tie a file to a card whose name has them.
COMMON = {"the", "of", "and", "play", "attack", "death", "impact", "cast", "shared", "minion", "spell", "fire", "frost",
          "holy", "shadow", "arcane", "nature", "underlay", "stinger", "pegasus", "male", "female", "human", "trigger",
          "small", "large", "loop", "start", "target", "event", "custom", "spawn", "summon", "blade", "flame", "ice",
          "storm", "lightning", "poison", "golden", "card", "hero", "power", "weapon"}
MAX_LEN = {"music": 40.0, "voice": 15.0, "aim": None}
SILENT_DB = -50.0
LEVELS = ("error", "flag", "info")


# ---- the pure rules (tools/test_check_sounds.py) ----

def parse_name(name, ids, voice=False):
    """(card id, role, known role?) of a file name without extension; (None, None, False) when no card id starts it
    (the longest id wins: GVG_110t_play is GVG_110t's)."""
    parts = name.split("_")
    for k in range(len(parts) - 1, 0, -1):
        cid = "_".join(parts[:k])
        if cid in ids:
            role = "_".join(parts[k:])
            known = role in VOICE_KINDS if voice else (role in SET_ROLES or bool(re.fullmatch(r"hit_\d+", role)))
            return cid, role, known
    return None, None, False


def words(src):
    """The lowercase words of a file name: VO_OG_133_Male_OldGod_EnterPlay_01.wav -> vo og 133 male old god enter play
    01 (CamelCase and digits split)."""
    stem = src.rsplit(".", 1)[0]
    return [w.lower() for w in re.findall(r"[A-Z]+(?=[A-Z][a-z])|[A-Z]?[a-z]+|[A-Z]+|\d+", stem)]


def role_agrees(role, src, voice=False):
    """False when the role words of src's name are all of another role (a *_Play* file used as _death); True when
    they agree or the name has none. A hero's emote lines are not judged (plan_card names them by their words)."""
    base = "hit" if re.fullmatch(r"hit_\d+", role) else role
    if voice and base not in ("play", "attack", "death", "trigger"):
        return True
    tags = set(words(src)) & ALL_TAGS
    if voice:
        tags &= {"play", "enter", "summon", "attack", "death", "trigger"}
        if base == "trigger" or not tags:
            return True  # (a voice trigger line may be any line the card says on an effect)
    return not tags or bool(tags & ROLE_TAGS[base])


def norm(s):
    return re.sub(r"[^a-z0-9]", "", s.lower())


def ids_in(src, ids_upper):
    """The known card ids that stand as whole parts of src's name (VO_OG_133_Male_… -> {"OG_133"})."""
    segs = src.rsplit(".", 1)[0].upper().split("_")
    found = set()
    for i in range(len(segs)):
        for j in range(i + 1, min(i + 4, len(segs)) + 1):
            hit = ids_upper.get("_".join(segs[i:j]))
            if hit:
                found.add(hit)
    return found


def shared_kind(src, tables):
    """Why src may sit on many cards: a documented table file, an underlay, a stinger with no card in its name; or
    None."""
    if src in tables:
        return "table"
    w = set(words(src))
    if "underlay" in w:
        return "underlay"
    if "stinger" in w:
        return "themed music stinger"
    return None


def belongs(src, cid, name, ids_upper, names, tables=frozenset(), names_of=None):
    """(level, note) of the source src on card cid (English name `name`):
    ok    src has the card's id or its name (all its words, or a rare word of it)
    info  a documented table file or an underlay (shared by design); a file of the card's parent/token
    error src is another card's voice (VO_<other id>_…)
    flag  another card's id or name, or nothing of the card at all."""
    names_of = names_of or {}
    base = cid.removeprefix("VAN_")
    found = {i.removeprefix("VAN_") for i in ids_in(src, ids_upper)}
    if base in found:
        return "ok", "card id"
    others = sorted(i for i in found if i != base)
    related = [i for i in others if base.startswith(i) or i.startswith(base)]
    flat = norm(src)
    own = [w for w in re.findall(r"[a-z0-9]+", (name or "").lower().replace("'", "")) if w not in ("the", "of", "and")]
    if own and all(w in flat for w in own):
        return "ok", "card name"
    kind = shared_kind(src, tables)
    if kind == "table":
        return "info", "documented table file"
    if others and not related and all(names_of.get(i) == norm(name or "-") for i in others):
        return "info", "another card of the same character: " + ", ".join(others)
    if others and not related:
        return ("error" if src.upper().startswith("VO_") else "flag"), "another card's file: " + ", ".join(others)
    if related:
        return "info", "the file of a related card: " + ", ".join(related)
    if any(len(w) >= 4 and w not in COMMON and w in flat for w in own):
        return "ok", "part of the card name"
    if kind == "underlay":
        return "info", kind
    other = sorted(n for n, i in names.items() if len(n) >= 7 and n in flat and i != base)
    if other:
        return "flag", "named after another card: " + names[other[-1]]
    if kind:
        return "info", kind
    return "flag", "nothing of the card in the name"


def length_problem(role, seconds, voice=False):
    """None, or why `seconds` is a wrong length for the role."""
    if seconds is None:
        return None
    if voice:
        return f"voice line of {seconds:.1f} s (> 15)" if seconds > 15 else None
    if role == "music":
        return None if 1.0 <= seconds <= 40.0 else f"music of {seconds:.1f} s (want 1-40)"
    if role == "aim":
        return None if seconds >= 0.3 else f"aim loop of {seconds:.2f} s (< 0.3)"
    return f"{role} of {seconds:.1f} s (> 8)" if seconds > 8.0 else None


def ru_key(src, ru):
    """The Russian index key of an English source file (fetch_original_sounds.run's lookup), or None."""
    for k in (src.lower().replace(" ", "_"), src.lower().replace(" ", "_").replace("wellplayed", "well_played")):
        if k in ru:
            return k
    return None


def plan_sources(cards, rows, manifests=()):
    """{("set"|"voice", name): [wiki files]} for cards [(id, type)]: plan_card's choice, then the manifests'."""
    out = {}
    for cid, ctype in cards:
        row = rows.get(cid) or rows.get(cid.removeprefix("VAN_")) or {}
        for kind, name, f in snd.plan_card(cid, row, ctype):
            out[(kind, name)] = [f]
    for man in manifests:
        for cid, roles in man.items():
            for role, files in roles.items():
                files = [files] if isinstance(files, str) else list(files)
                if role.startswith("voice_"):
                    out[("voice", f"{cid}_{role[6:]}")] = files
                    continue
                out[("set", f"{cid}_{role}")] = files
                if role == "hit":
                    for n, f in enumerate(files[1:], 2):
                        if f"hit_{n}" not in roles:
                            out[("set", f"{cid}_hit_{n}")] = [f]
                    out[("set", f"{cid}_hit")] = files[:1]
    return out


def tables():
    t = set(snd.GENERIC.values())
    for pair in list(snd.ELEMENTS.values()) + list(snd.SPELLS.values()):
        t |= {f for f in pair if f}
    for d in snd.ORIGINAL.values():
        t |= set(d.values())
    return frozenset(t)


# ---- the files ----

def card_data():
    """{id: (type, English name)} of every card the repo knows (data/cards.json and data/<set>_cards.json)."""
    out = {}
    for p in [ROOT / "data/cards.json"] + sorted((ROOT / "data").glob("*_cards.json")):
        for c in json.loads(p.read_text()):
            n = c.get("name")
            out[c["id"]] = (c.get("type"), n.get("enUS") if isinstance(n, dict) else n)
    return out


def set_cards(name):
    p = ROOT / ("data/cards.json" if name == "classic" else f"data/{name}_cards.json")
    return [(c["id"], c["type"]) for c in json.loads(p.read_text())]


def load_rows(ids):
    rows = json.loads(ROWS.read_text()) if ROWS.exists() else {}
    want = sorted({i.removeprefix("VAN_") for i in ids} - set(rows))
    if want:
        print(f"asking the wiki for {len(want)} Sound rows", file=sys.stderr)
        got = snd.wiki_sounds(want)
        rows.update({i: got.get(i) or {} for i in want})
        ROWS.parent.mkdir(parents=True, exist_ok=True)
        ROWS.write_text(json.dumps(rows))
    return rows


def ru_union():
    out = {}
    for p in sorted(CACHE.glob("ru_index*.json")):
        out.update(json.loads(p.read_text()))
    return out


def probe(path):
    """(seconds, max dB, md5) of an audio file."""
    r = subprocess.run(["ffmpeg", "-hide_banner", "-nostats", "-i", str(path), "-af", "volumedetect", "-f", "null",
                        "-"], capture_output=True, text=True)
    d = re.search(r"Duration: (\d+):(\d+):([\d.]+)", r.stderr)
    v = re.search(r"max_volume: (-?[\d.]+|-inf) dB", r.stderr)
    sec = int(d[1]) * 3600 + int(d[2]) * 60 + float(d[3]) if d else None
    return sec, (float(v[1]) if v else None), hashlib.md5(Path(path).read_bytes()).hexdigest()


def wav_seconds(path):
    try:
        with wave.open(str(path)) as w:
            return w.getnframes() / w.getframerate()
    except Exception:
        return None


def source_seconds(src, wiki_len, ru=False):
    if ru:
        return wav_seconds(CACHE / "ru" / src)
    if src in wiki_len:
        return wiki_len[src][1]
    return wav_seconds(CACHE / "wiki" / src)


def gather(target, tmp):
    """[(kind, lang, name, path)] of the audio files, and the pack's cards [(id, type)] (None for a folder)."""
    files, cards = [], None
    if target.is_dir():
        for p in sorted((target / "set").glob("*.opus")):
            files.append(("set", None, p.stem, p))
        for p in sorted((target / "voice").glob("*/*.opus")):
            files.append(("voice", p.parent.name, p.stem, p))
        return files, cards
    with zipfile.ZipFile(target) as z:
        cards = [(c["id"], c.get("type")) for c in json.loads(z.read("cards.json"))]
        for n in z.namelist():
            m = re.fullmatch(r"(sounds|voice)/([^/]+)/([^/]+)\.opus", n)
            if m:
                z.extract(n, tmp)
                files.append(("set" if m[1] == "sounds" else "voice", None if m[1] == "sounds" else m[2], m[3],
                              Path(tmp) / n))
    return sorted(files, key=lambda f: str(f[3])), cards


def check(target, set_name=None, manifests=(), audio=True):
    """[(level, check, file, note)] and counts of a folder or a .cardpack."""
    data = card_data()
    with tempfile.TemporaryDirectory() as tmp:
        files, cards = gather(target, tmp)
        if cards is None:
            cards = set_cards(set_name or target.name)
        rows = load_rows([c for c, _ in cards])
        plan = plan_sources(cards, rows, manifests)
        ids = {c for c, _ in cards}
        ids_upper = {i.removeprefix("VAN_").upper(): i.removeprefix("VAN_") for i in set(data) | ids}
        names = {norm(n): i.removeprefix("VAN_") for i, (_, n) in data.items() if n}
        names_of = {i.removeprefix("VAN_"): norm(n) for i, (_, n) in data.items() if n}
        tabs = tables()
        wiki_len = json.loads(WIKI_FILES.read_text()) if WIKI_FILES.exists() else {}
        ru = ru_union()
        board = set(snd.GENERIC) | {f"{p}_{e}" for e in snd.ELEMENTS for p in ("spell", "hit")}
        with cf.ThreadPoolExecutor(os.cpu_count() or 4) as pool:
            probes = dict(zip([f[3] for f in files], pool.map(probe, [f[3] for f in files]))) if audio else {}
    out = []

    def add(level, what, f, note):
        out.append((level, what, f, note))

    by_src, by_md5, label_src, doubtful = {}, {}, {}, set()
    reviewed = json.loads(REVIEWED.read_text()) if REVIEWED.exists() else {}
    present = set()
    english = {n for k, la, n, _ in files if la == "en"}
    for kind, lang, name, path in files:
        label = f"{kind}/{lang + '/' if lang else ''}{name}"
        present.add((kind, lang, name))
        sec, db, md5 = probes.get(path, (None, None, None))
        if db is not None and db < SILENT_DB:
            add("flag", "silent", label, f"max {db} dB")
        if kind == "set" and name in board:
            continue
        cid, role, known = parse_name(name, ids, voice=kind == "voice")
        if cid is None:
            add("flag", "name", label, "no card of the pack starts the name")
            continue
        if not known:
            add("flag", "name", label, f"unknown role {role!r}")
        voice = kind == "voice"
        srcs = plan.get((kind, name))
        problem = length_problem(role, sec, voice)
        if problem:
            why = srcs and reviewed.get(cid.removeprefix("VAN_"), {}).get(srcs[0])
            add("info" if why else "flag", "length", label, problem + (f" (reviewed: {why})" if why else ""))
        if not srcs:
            new = not voice and role not in ("play", "attack", "death", "music", "hit")
            add("info" if new else "flag", "source", label,
                "new role: pass the lead's --manifest" if new else "no source in the wiki row (a stale file?)")
            continue
        base = cid.removeprefix("VAN_")
        if md5:
            by_md5.setdefault(md5, set()).add((base, label))
        label_src[label] = tuple(srcs)
        for src in srcs:
            level, note = belongs(src, cid, data.get(cid, (None, None))[1] or data.get(base, (None, None))[1],
                                  ids_upper, names, tabs, names_of)
            why = reviewed.get(base, {}).get(src)
            if level != "ok":
                add(*(("info", "owner", label, f"{src}: reviewed: {why}") if why else (level, "owner", label,
                                                                                      f"{src}: {note}")))
            if not role_agrees(role, src, voice):
                add("info" if src in tabs or why else "flag", "role", label,
                    f"{src} used as {role}" + (f" (reviewed: {why})" if why else ""))
            if lang != "ru":
                by_src.setdefault(src, set()).add((base, label))
                if level in ("flag", "error") and not why:
                    doubtful.add(src)
        if lang == "ru":
            if name not in english:
                add("flag", "ru", label, "a Russian line with no English one")
            if srcs[0].endswith("_Original.wav"):
                add("flag", "ru", label, f"{srcs[0]} is a 2014 English file: the Russian one is a later recording")
            elif not ru_key(srcs[0], ru):
                add("flag", "ru", label, f"no Russian file named {srcs[0]} in the Drive index")
        if len(srcs) == 1 and sec is not None:
            want = source_seconds(srcs[0], wiki_len, ru=lang == "ru")
            if want is not None and abs(want - sec) > max(0.3, 0.06 * want):
                add("flag", "length", label, f"{sec:.2f} s, its source {srcs[0]} is {want:.2f} s: made from another "
                    "file?")
    for src, users in sorted(by_src.items()):
        cards_ = {b for b, _ in users}
        if len(cards_) > 1:
            shared = shared_kind(src, tabs) or ("" if src in doubtful else "each card's own wiki row")
            add("info" if shared else "flag", "same", ", ".join(sorted(lbl for _, lbl in users)),
                f"{src} on {len(cards_)} cards" + (f" ({shared})" if shared else ""))
    for md5, users in by_md5.items():
        cards_ = {b for b, _ in users}
        labels = sorted(lbl for _, lbl in users)
        if len(cards_) > 1 and len({label_src.get(lbl) for lbl in labels}) > 1:
            add("flag", "same", ", ".join(labels), "identical bytes on different cards")
    missing = 0
    if target.is_dir():
        for (kind, name), srcs in sorted(plan.items()):
            langs = [None] if kind == "set" else ["en", "ru"]
            for lang in langs:
                if (kind, lang, name) in present:
                    continue
                if lang == "ru" and (srcs[0].endswith("_Original.wav") or not ru_key(srcs[0], ru)):
                    continue
                missing += 1
                add("info", "missing", f"{kind}/{lang + '/' if lang else ''}{name}", ", ".join(srcs))
    counts = {"files": len(files), "missing": missing}
    bad = {f for lvl, _, f, _ in out if lvl in ("error", "flag")}
    counts["ok"] = sum(1 for k, la, n, _ in files if f"{k}/{la + '/' if la else ''}{n}" not in bad)
    return out, counts


def summary(name, out, counts):
    tally = {}
    for level, what, _, _ in out:
        tally.setdefault(what, {}).setdefault(level, 0)
        tally[what][level] += 1
    parts = [f"{what}: " + " ".join(f"{lvl} {n}" for lvl, n in sorted(lv.items())) for what, lv in sorted(tally.items())]
    return f"{name}: {counts['files']} files, {counts['ok']} ok, {counts['missing']} missing | " + "; ".join(parts)


def write_report(path, name, out, counts):
    path = Path(path).expanduser()
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.suffix == ".json":
        path.write_text(json.dumps({"target": name, "counts": counts, "issues": out}, indent=1, ensure_ascii=False))
        return
    lines = [f"# Sound check: {name}", "", summary(name, out, counts), ""]
    for level in LEVELS:
        rows = sorted(r for r in out if r[0] == level)
        if rows:
            lines += [f"## {level} ({len(rows)})", "", "| Check | File | Note |", "|---|---|---|"]
            lines += [f"| {w} | {f} | {n} |" for _, w, f, n in rows]
            lines.append("")
    path.write_text("\n".join(lines))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("target", nargs="?", help="a set's folder or a .cardpack")
    ap.add_argument("--all", action="store_true", help=f"every set's folder under {LOCAL}")
    ap.add_argument("--set", help="the folder's set (default: the folder's name)")
    ap.add_argument("--manifest", action="append", default=[], help="a manifest.json of new roles (repeatable)")
    ap.add_argument("--manifests", action="store_true", help="with --all: each set's audio-src/<set>/manifest.json")
    ap.add_argument("--report", help="write the findings (.md or .json)")
    ap.add_argument("--report-dir", help="with --all: one <set>.md each")
    ap.add_argument("--no-audio", action="store_true", help="no ffmpeg (no length, silence, byte checks)")
    ap.add_argument("--quiet", action="store_true", help="the summary only")
    a = ap.parse_args()
    targets = [(s, LOCAL / s) for s in SETS] if a.all else [(a.set, Path(a.target).expanduser())]
    worst = 0
    for set_name, target in targets:
        mans = [json.loads(Path(m).expanduser().read_text()) for m in a.manifest]
        if a.manifests and (LOCAL / f"audio-src/{target.name}/manifest.json").exists():
            mans.append(json.loads((LOCAL / f"audio-src/{target.name}/manifest.json").read_text()))
        out, counts = check(target, set_name, mans, audio=not a.no_audio)
        if not a.quiet:
            for row in sorted(out):
                if row[0] != "info":
                    print(" | ".join(row))
        print(summary(target.name, out, counts))
        if a.report:
            write_report(a.report, target.name, out, counts)
        if a.report_dir:
            write_report(Path(a.report_dir).expanduser() / f"{target.stem}.md", target.name, out, counts)
        worst = max(worst, 2 if any(r[0] == "error" for r in out) else 1 if any(r[0] == "flag" for r in out) else 0)
    return worst


if __name__ == "__main__":
    sys.exit(main())
