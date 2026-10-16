#!/usr/bin/env python3
"""Builds, checks and hashes .cardpack game packs (docs/packs/format.md). Stdlib only.

  tools/pack.py build packs/classic -o build/packs/classic.cardpack [--art-set id=path ...]
  tools/pack.py check build/packs/classic.cardpack
  tools/pack.py info  build/packs/classic.cardpack
  tools/pack.py hash  build/packs/classic.cardpack

Unit tests: python3 -m unittest tools/test_pack.py
"""
import argparse
import fnmatch
import hashlib
import io
import json
import re
import stat
import sys
import zipfile
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
SCHEMAS = REPO / "docs/packs/schema"

MiB = 1024 * 1024
LIMITS = {
    "pack": 128 * MiB,       # the .cardpack file
    "unpacked": 256 * MiB,   # all files, uncompressed
    "files": 10000,
    "file": 16 * MiB,        # any one file
    "image": 2 * MiB,        # one picture
    "rules": 8 * MiB,        # rules.json + cards.json + missions/ + scripts/, uncompressed
    "text": 32 * MiB,        # locales/ + layout/, uncompressed
    "ratio": 200,            # uncompressed / compressed size of one entry (zip bombs)
}
PATH_RE = re.compile(r"^[A-Za-z0-9_][A-Za-z0-9_.-]*(/[A-Za-z0-9_][A-Za-z0-9_.-]*)*$")
IMAGES = (".png", ".jpg", ".jpeg", ".webp")
AUDIO = (".ogg", ".wav", ".mp3")
# Top-level files and, per directory, the extensions it may hold and how deep it goes.
TOP_FILES = {"manifest.json", "rules.json", "cards.json", "README.md", "CREDITS.md", "LICENSE.txt"}
DIRS = {  # dir -> (extensions, depth below dir: 1 = files right in it, 2 = in a sub-folder (a set / a language))
    "scripts": ((".lua", ".md"), None),
    "locales": ((".json",), 1),
    "layout": ((".json",), 1),
    "decks": ((".json",), 1),
    "missions": ((".json",), 1),
    "ui": (IMAGES, 1),
    "art": (IMAGES + (".md",), 2),
    "sounds": (AUDIO + (".md",), 2),
    "music": (AUDIO + (".md",), 2),
    "voice": (AUDIO + (".md",), None),
}
# Card fields that only change how a card looks or sounds: left out of rules_hash.
PRESENTATION = ("fx", "sounds", "voice")
NO_COMPRESS = IMAGES + (".ogg", ".mp3")
ZIP_TIME = (1980, 1, 1, 0, 0, 0)


class PackError(Exception):
    pass


# --- JSON: strict reading and the canonical form ------------------------------------------------

def _no_dupes(pairs):
    out = {}
    for k, v in pairs:
        if k in out:
            raise PackError(f"duplicate key {k!r}")
        out[k] = v
    return out


def _no_constant(name):
    raise PackError(f"{name} is not JSON")


def load_json(data, where="?"):
    """JSON from UTF-8 bytes without a BOM; duplicate keys, NaN and Infinity are errors."""
    if data.startswith(b"\xef\xbb\xbf"):
        raise PackError(f"{where}: UTF-8 BOM")
    try:
        return json.loads(data.decode("utf-8"), object_pairs_hook=_no_dupes, parse_constant=_no_constant)
    except (UnicodeDecodeError, ValueError, PackError) as e:
        raise PackError(f"{where}: {e}") from None


def _ints_only(v, where):
    if isinstance(v, float):
        raise PackError(f"{where}: fractions are not allowed ({v})")
    if isinstance(v, dict):
        for x in v.values():
            _ints_only(x, where)
    elif isinstance(v, list):
        for x in v:
            _ints_only(x, where)


def canonical(v, where="?"):
    """The canonical JSON bytes: keys sorted by code point, no spaces, UTF-8, minimal escapes, no fractions."""
    _ints_only(v, where)
    return json.dumps(v, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False).encode("utf-8")


def pretty(v):
    """Readable JSON; a list of objects (cards.json) gets one object per line."""
    if isinstance(v, list) and v and all(isinstance(x, dict) for x in v):
        body = ",\n".join(json.dumps(x, ensure_ascii=False) for x in v)
        return f"[\n{body}\n]\n".encode("utf-8")
    return (json.dumps(v, ensure_ascii=False, indent=1) + "\n").encode("utf-8")


# --- hashes ------------------------------------------------------------------------------------

def is_rules_file(path):
    return path in ("rules.json", "cards.json") or (path.startswith("missions/") and path.endswith(".json")) \
        or (path.startswith("scripts/") and path.endswith(".lua"))


def normalized(path, data):
    """The bytes of a rules file that rules_hash covers (format.md, 'Hashes')."""
    if path.endswith(".lua"):
        if data.startswith(b"\xef\xbb\xbf"):
            data = data[3:]
        return data.replace(b"\r\n", b"\n").replace(b"\r", b"\n")
    v = load_json(data, path)
    if path == "cards.json" and isinstance(v, list):
        v = [{k: x for k, x in c.items() if k not in PRESENTATION} if isinstance(c, dict) else c for c in v]
    return canonical(v, path)


def _digest(tag, items):
    h = hashlib.sha256(tag.encode() + b"\n")
    for path, data in sorted(items, key=lambda it: it[0].encode()):
        h.update(f"{path}:{hashlib.sha256(data).hexdigest()}\n".encode())
    return h.hexdigest()


def rules_hash(files):
    return _digest("cardpack-rules/1", [(p, normalized(p, d)) for p, d in files.items() if is_rules_file(p)])


def content_hash(files):
    return _digest("cardpack-content/1", files.items())


# --- a small JSON Schema subset (the schemas in docs/packs/schema use only this) ---------------

_TYPES = {"object": dict, "array": list, "string": str, "boolean": bool, "null": type(None)}


def _is(v, t):
    if t == "integer":
        return isinstance(v, int) and not isinstance(v, bool)
    if t == "number":
        return isinstance(v, (int, float)) and not isinstance(v, bool)
    return isinstance(v, _TYPES[t])


def validate(v, schema, root=None, at="$"):
    """Errors of v against schema: type, enum, const, pattern, min/max(Length|Items|imum), uniqueItems,
    properties, required, additionalProperties, propertyNames, items, anyOf, $ref (#/$defs/...)."""
    root = root or schema
    if "$ref" in schema:
        node = root
        for part in schema["$ref"].lstrip("#/").split("/"):
            node = node[part]
        return validate(v, node, root, at)
    if "anyOf" in schema:
        if any(not validate(v, s, root, at) for s in schema["anyOf"]):
            return []
        return [f"{at}: matches none of the allowed forms"]
    errs = []
    types = schema.get("type")
    if types is not None:
        types = [types] if isinstance(types, str) else types
        if not any(_is(v, t) for t in types):
            return [f"{at}: expected {'/'.join(types)}, got {type(v).__name__}"]
    if "const" in schema and v != schema["const"]:
        errs.append(f"{at}: must be {schema['const']!r}")
    if "enum" in schema and v not in schema["enum"]:
        errs.append(f"{at}: {v!r} is not one of {schema['enum']}")
    if isinstance(v, str):
        if "pattern" in schema and not re.search(schema["pattern"], v):
            errs.append(f"{at}: {v!r} does not match {schema['pattern']}")
        if len(v) > schema.get("maxLength", len(v)) or len(v) < schema.get("minLength", 0):
            errs.append(f"{at}: length {len(v)} out of range")
    if _is(v, "number"):
        if v < schema.get("minimum", v) or v > schema.get("maximum", v):
            errs.append(f"{at}: {v} out of range")
    if isinstance(v, list):
        if len(v) > schema.get("maxItems", len(v)) or len(v) < schema.get("minItems", 0):
            errs.append(f"{at}: {len(v)} items, out of range")
        if schema.get("uniqueItems") and len({json.dumps(x, sort_keys=True) for x in v}) != len(v):
            errs.append(f"{at}: items repeat")
        if "items" in schema:
            for i, x in enumerate(v):
                errs += validate(x, schema["items"], root, f"{at}[{i}]")
    if isinstance(v, dict):
        props = schema.get("properties", {})
        for k in schema.get("required", []):
            if k not in v:
                errs.append(f"{at}: missing {k!r}")
        for k, x in v.items():
            if "propertyNames" in schema:
                errs += validate(k, schema["propertyNames"], root, f"{at}.{k} (key)")
            if k in props:
                errs += validate(x, props[k], root, f"{at}.{k}")
            elif schema.get("additionalProperties") is False:
                errs.append(f"{at}: unknown field {k!r}")
            elif isinstance(schema.get("additionalProperties"), dict):
                errs += validate(x, schema["additionalProperties"], root, f"{at}.{k}")
    return errs


def schema(name):
    return json.loads((SCHEMAS / name).read_text("utf-8"))


def vocabulary():
    return json.loads((SCHEMAS / "keywords.json").read_text("utf-8"))


def fx_catalog():
    return json.loads((SCHEMAS / "fx.json").read_text("utf-8"))


# --- checking a pack (files: path -> bytes) -------------------------------------------------

class Report:
    def __init__(self):
        self.errors = []
        self.warnings = []

    def error(self, msg):
        self.errors.append(msg)

    def warn(self, msg):
        self.warnings.append(msg)


def check_paths(files, r):
    total = text = rules = 0
    for p, data in files.items():
        size = len(data)
        total += size
        if not PATH_RE.match(p) or len(p) > 200 or ".." in p.split("/"):
            r.error(f"{p}: bad path (letters, digits, _ . - and /, no leading dot, at most 200 chars)")
            continue
        if size > LIMITS["file"]:
            r.error(f"{p}: {size} bytes, more than {LIMITS['file']}")
        parts = p.split("/")
        if len(parts) == 1:
            if p not in TOP_FILES:
                r.error(f"{p}: not allowed at the top (allowed: {', '.join(sorted(TOP_FILES))})")
            continue
        top = parts[0]
        if top not in DIRS:
            r.error(f"{p}: unknown folder {top}/")
            continue
        exts, depth = DIRS[top]
        if not p.lower().endswith(exts):
            r.error(f"{p}: {top}/ holds only {' '.join(exts)}")
        if depth is not None and len(parts) - 1 != depth:
            r.error(f"{p}: {top}/ files go {'right in it' if depth == 1 else 'in a sub-folder (a set)'}")
        if p.lower().endswith(IMAGES) and size > LIMITS["image"]:
            r.error(f"{p}: picture of {size} bytes, more than {LIMITS['image']}")
        if top in ("locales", "layout"):
            text += size
        if is_rules_file(p):
            rules += size
    if len(files) > LIMITS["files"]:
        r.error(f"{len(files)} files, more than {LIMITS['files']}")
    for what, n in (("unpacked", total), ("rules", rules), ("text", text)):
        if n > LIMITS[what]:
            r.error(f"{what} size {n} is more than {LIMITS[what]}")


def _json(files, p, r, schema_name=None):
    try:
        v = load_json(files[p], p)
    except PackError as e:
        r.error(str(e))
        return None
    if schema_name:
        errs = validate(v, schema(schema_name))
        for e in errs[:20]:
            r.error(f"{p}: {e[2:] if e.startswith('$.') else e}")
        if len(errs) > 20:
            r.error(f"{p}: … and {len(errs) - 20} more schema errors")
        if errs:
            return None
    return v


def deck_error(deck, cards, rules):
    """Why a deck is illegal by the pack's rules ('' = legal). The engine's Deck::validate in data."""
    by_class = {c["id"]: c for c in rules["classes"]}
    champ_class = {c["champion"]: c["id"] for c in rules["classes"] if "champion" in c}
    neutral = {c["id"] for c in rules["classes"] if c.get("neutral")}
    limits = rules["limits"]
    arena = deck.get("arena", False)
    mode = rules["modes"]["arena" if arena else "constructed"]
    cls = champ_class.get(deck["champion"])
    if cls is None or by_class[cls].get("playable", True) is False:
        return f"unknown champion {deck['champion']}"
    counts = {}
    for cid in deck["cards"]:
        c = cards.get(cid)
        if c is None or not c.get("collectible") or c.get("set") not in mode["sets"] or c["type"] == "CHAMPION":
            return f"{cid} can't be put in a deck"
        if c["class"] not in neutral and c["class"] != cls:
            return f"{cid} belongs to another class"
        counts[cid] = counts.get(cid, 0) + 1
        most = mode.get("copies", 0) if arena else limits.get("copies_by_rarity", {}).get(c.get("rarity"), limits["copies"])
        if most and counts[cid] > most:
            return f"more than {most} copies of {cid}"
    if len(deck["cards"]) != limits["deck_size"]:
        return f"a deck needs exactly {limits['deck_size']} cards, it has {len(deck['cards'])}"
    return ""


def check_files(files):
    """Every rule of format.md on the unpacked files. Returns a Report."""
    r = Report()
    check_paths(files, r)
    for need in ("manifest.json", "rules.json", "cards.json"):
        if need not in files:
            r.error(f"{need} is missing")
    if r.errors:
        return r
    man = _json(files, "manifest.json", r, "manifest.schema.json")
    rules = _json(files, "rules.json", r, "rules.schema.json")
    card_list = _json(files, "cards.json", r, "cards.schema.json")
    if man is None or rules is None or card_list is None:
        return r
    try:
        canonical(rules, "rules.json")
        canonical(card_list, "cards.json")
    except PackError as e:
        r.error(str(e))
    voc = vocabulary()
    engine_ids = {k["id"] for k in voc["keywords"]}
    cards = {}
    for c in card_list:
        if c["id"] in cards:
            r.error(f"cards.json: card {c['id']} twice")
        cards[c["id"]] = c

    def card(cid, where, kind=None):
        c = cards.get(cid)
        if c is None:
            r.error(f"{where}: unknown card {cid}")
        elif kind and c["type"] != kind:
            r.error(f"{where}: {cid} is a {c['type']}, not a {kind}")
        return c

    # rules
    for name, m in rules["mechanics"].items():
        if m["engine"] not in engine_ids:
            r.error(f"rules.json: mechanic {name} maps to {m['engine']}, not an engine keyword (docs/packs/schema/keywords.json)")
    classes = {c["id"] for c in rules["classes"]}
    if not any(c.get("neutral") for c in rules["classes"]):
        r.warn("rules.json: no class is neutral")
    for c in rules["classes"]:
        if "champion" in c:
            champ = card(c["champion"], f"rules.json class {c['id']}", "CHAMPION")
            if champ and champ["class"] != c["id"]:
                r.error(f"rules.json: champion {c['champion']} of {c['id']} is of class {champ['class']}")
    rarities = {x["id"] for x in rules["rarities"]}
    for rid in rules["limits"].get("copies_by_rarity", {}):
        if rid not in rarities:
            r.error(f"rules.json: copies_by_rarity names unknown rarity {rid}")
    sets = set(rules.get("sets", []))
    races = set(rules.get("races", []))
    if rules["start"].get("coin"):
        card(rules["start"]["coin"], "rules.json start.coin", "SPELL")
    if "default_power" in rules:
        card(rules["default_power"], "rules.json default_power", "POWER")
    modes = rules["modes"]
    for mname, mode in modes.items():
        for s in mode["sets"]:
            if s not in sets:
                r.error(f"rules.json: modes.{mname} uses unknown set {s}")
    for cid in modes["constructed"].get("starter_core", []):
        c = card(cid, "rules.json starter_core")
        if c and not c.get("collectible"):
            r.error(f"rules.json: starter_core card {cid} is not collectible")
    if "arena" in modes:
        a = modes["arena"]
        for cls in a["classes"]:
            if cls not in classes:
                r.error(f"rules.json: arena class {cls} unknown")
        if sum(a["tier_weights"].values()) <= 0:
            r.error("rules.json: arena tier_weights add up to 0")
        for n in a.get("special_picks", []):
            if n > a["picks"]:
                r.error(f"rules.json: arena special pick {n} is after the last pick")
    ranked = rules.get("ranked")
    if ranked:
        nums = [x["rank"] for x in ranked["ranks"]]
        if nums != sorted(nums, reverse=True) or len(set(nums)) != len(nums) or nums[-1] != 1 or nums[0] != len(nums):
            r.error("rules.json: ranked.ranks must run from the lowest rank (N) down to 1, one each")
        for x in ranked["ranks"] + ([ranked["legend"]] if ranked.get("legend") else []):
            em = x.get("emblem")
            if em and "card" in em:
                card(em["card"], f"rules.json rank {x.get('rank', 'legend')} emblem")
            if em and "image" in em and em["image"] not in files:
                r.error(f"rules.json: emblem {em['image']} is not in the pack")

    # cards
    fxc = fx_catalog()
    fx_names = {"element": fxc["elements"]}
    for slot in ("cast", "hit", "play", "death"):
        fx_names[slot] = fxc[slot]
    for c in card_list:
        at = f"cards.json {c['id']}"
        if c["class"] not in classes:
            r.error(f"{at}: unknown class {c['class']}")
        if "rarity" in c and c["rarity"] not in rarities:
            r.error(f"{at}: unknown rarity {c['rarity']}")
        if "set" in c and sets and c["set"] not in sets:
            r.error(f"{at}: unknown set {c['set']}")
        if "race" in c and c["race"] not in races:
            r.error(f"{at}: unknown race {c['race']}")
        for k in c.get("keywords", []) + c.get("refs", []):
            if k not in rules["mechanics"]:
                r.error(f"{at}: mechanic {k} is not in rules.json mechanics")
        if c["type"] == "CHAMPION":
            if "power" in c:
                card(c["power"], f"{at} power", "POWER")
            elif "default_power" not in rules:
                r.error(f"{at}: a champion needs a power (or rules.json default_power)")
        elif "power" in c:
            r.error(f"{at}: only a CHAMPION has a power")
        if "script" in c and c["script"].split("#")[0] not in files:
            r.error(f"{at}: script {c['script'].split('#')[0]} is not in the pack")
        for slot, name in c.get("fx", {}).items():
            if name not in fx_names[slot]:
                r.warn(f"{at}: fx.{slot} {name!r} is not in the catalog (the client shows its default)")
        for slot, name in c.get("sounds", {}).items():
            if not any(p.startswith("sounds/") and p.rsplit("/", 1)[1].rsplit(".", 1)[0] == name for p in files):
                r.warn(f"{at}: sound {name} is in no sound set")

    # manifest and the files it names
    langs = man["locales"]
    if man["default_locale"] not in langs:
        r.error("manifest.json: default_locale is not in locales")
    if man.get("rules_hash") and man["rules_hash"] != rules_hash(files):
        r.error("manifest.json: rules_hash does not match the pack (rebuild it)")
    for key in ("card_back", "logo"):
        if man.get(key) and man[key] not in files:
            r.error(f"manifest.json: {key} {man[key]} is not in the pack")
    for kind, top in (("art_sets", "art"), ("sound_sets", "sounds"), ("music_sets", "music")):
        listed = {s["id"] for s in man.get(kind, [])}
        present = {p.split("/")[1] for p in files if p.startswith(top + "/")}
        for s in sorted(listed - present):
            r.error(f"manifest.json: {kind} {s} has no files in {top}/{s}/")
        for s in sorted(present - listed):
            r.error(f"{top}/{s}/ is not listed in manifest.json {kind}")
        if len([s for s in man.get(kind, []) if s.get("default")]) > 1:
            r.error(f"manifest.json: more than one default in {kind}")
    for s in man.get("art_sets", []):
        stems = {p.split("/")[2].rsplit(".", 1)[0] for p in files if p.startswith(f"art/{s['id']}/") and not p.endswith(".md")}
        unknown = sorted(stems - cards.keys())
        if unknown:
            r.warn(f"art/{s['id']}/: {len(unknown)} pictures of no card ({', '.join(unknown[:5])})")
        missing = sorted(cards.keys() - stems)
        if missing and s.get("default"):
            r.warn(f"art/{s['id']}/: no picture for {len(missing)} cards ({', '.join(missing[:5])})")

    # locales and layouts
    for p in sorted(x for x in files if x.startswith(("locales/", "layout/"))):
        lang = p.split("/")[1][:-5]
        if lang not in langs:
            r.error(f"{p}: {lang} is not in manifest.json locales")
    for lang in langs:
        p = f"locales/{lang}.json"
        if p not in files:
            r.error(f"{p} is missing (manifest.json lists {lang})")
            continue
        loc = _json(files, p, r, "locale.schema.json")
        if loc is None:
            continue
        names = loc.get("cards", {})
        for cid in names:
            if cid not in cards:
                r.warn(f"{p}: text of unknown card {cid}")
        nameless = [cid for cid in cards if not names.get(cid, {}).get("name")]
        if nameless:
            (r.error if lang == man["default_locale"] else r.warn)(
                f"{p}: {len(nameless)} cards without a name ({', '.join(nameless[:5])})")
        if lang == man["default_locale"]:
            kinds = {k["id"]: k["kind"] for k in voc["keywords"]}
            used = {k for c in card_list for k in c.get("keywords", [])}
            for k in sorted(used):
                engine = rules["mechanics"].get(k, {}).get("engine")
                if kinds.get(engine) in ("keyword", "hook") and k not in loc.get("mechanics", {}):
                    r.warn(f"{p}: mechanic {k} has no name or tip")
    for p in sorted(x for x in files if x.startswith("layout/")):
        lay = _json(files, p, r, "layout.schema.json")
        if lay is not None:
            stray = [cid for cid in lay if cid not in cards]
            if stray:
                r.warn(f"{p}: layout of {len(stray)} unknown cards")

    # decks and missions
    for p in sorted(x for x in files if x.startswith("decks/")):
        d = _json(files, p, r, "deck.schema.json")
        if d is not None:
            why = deck_error(d, cards, rules)
            if why:
                r.error(f"{p}: illegal deck: {why}")
    for p in sorted(x for x in files if x.startswith("missions/")):
        m = _json(files, p, r, "mission.schema.json")
        if m is None:
            continue
        card(m["champion"], f"{p} champion", "CHAMPION")
        card(m["boss"], f"{p} boss", "CHAMPION")
        if "boss_power" in m:
            card(m["boss_power"], f"{p} boss_power", "POWER")
        for cid in m["player"]["hand"] + m["player"]["deck"] + m["boss_deck"] + ([m["reward"]] if "reward" in m else []):
            card(cid, p)
        if m.get("script") and m["script"].split("#")[0] not in files:
            r.error(f"{p}: script {m['script']} is not in the pack")
    return r


# --- zip ---------------------------------------------------------------------------------------

def read_pack(path):
    """path -> bytes of every file in a .cardpack, refusing what a pack may not hold."""
    size = Path(path).stat().st_size
    if size > LIMITS["pack"]:
        raise PackError(f"{path}: {size} bytes, more than {LIMITS['pack']}")
    files = {}
    with zipfile.ZipFile(path) as z:
        infos = z.infolist()
        if len(infos) > LIMITS["files"] + 100:
            raise PackError(f"{len(infos)} entries")
        if sum(i.file_size for i in infos) > LIMITS["unpacked"]:
            raise PackError("too big unpacked")
        for i in infos:
            if i.is_dir():
                continue
            if i.flag_bits & 0x1:
                raise PackError(f"{i.filename}: encrypted")
            if stat.S_ISLNK(i.external_attr >> 16):
                raise PackError(f"{i.filename}: a symbolic link")
            if i.file_size > LIMITS["file"] or (i.compress_size and i.file_size / i.compress_size > LIMITS["ratio"]):
                raise PackError(f"{i.filename}: too big or too compressed")
            if i.filename in files:
                raise PackError(f"{i.filename}: twice in the zip")
            files[i.filename] = z.read(i)
    return files


def write_pack(files, out):
    """A zip with sorted entries, fixed times and attributes: the same files give the same bytes
    (with the same zlib)."""
    out = Path(out)
    out.parent.mkdir(parents=True, exist_ok=True)
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w") as z:
        for p in sorted(files, key=str.encode):
            zi = zipfile.ZipInfo(p, ZIP_TIME)
            zi.create_system = 3
            zi.external_attr = (stat.S_IFREG | 0o644) << 16
            zi.compress_type = zipfile.ZIP_STORED if p.lower().endswith(NO_COMPRESS) else zipfile.ZIP_DEFLATED
            z.writestr(zi, files[p], compresslevel=9)
    out.write_bytes(buf.getvalue())


# --- building from a source folder -------------------------------------------------------------

class Build:
    def __init__(self, src):
        self.src = Path(src)
        self.files = {}
        self.cards = None
        self.locales = {}  # lang -> dict (starts as the source's locales/<lang>.json)
        self.manifest = None
        self.rules = None

    def loc(self, lang):
        return self.locales.setdefault(lang, {})

    def put(self, lang, value, *keys):
        """Sets locales[lang][k1][k2]... = value unless the source already has it."""
        d = self.loc(lang)
        for k in keys[:-1]:
            d = d.setdefault(k, {})
        d.setdefault(keys[-1], value)


def _match(name, pats):
    return any(fnmatch.fnmatchcase(name, p) for p in pats)


def step_copy(b, root, s):
    src = root / s["from"]
    if not src.is_dir():
        raise PackError(f"copy: {src} is not a folder")
    n = 0
    for f in sorted(src.iterdir()):
        if f.is_file() and _match(f.name, s["files"]) and not _match(f.name, s.get("except", [])) \
                and not f.name.endswith(".import"):
            b.files[f"{s['to']}/{f.name}"] = f.read_bytes()
            n += 1
    if n == 0:
        raise PackError(f"copy: nothing matched in {src}")


def step_hsjson(b, root, s):
    """Cards and their names and texts from HearthstoneJSON (data/cards.json)."""
    data = load_json((root / s["from"]).read_bytes(), s["from"])
    patch = load_json((b.src / s["patch"]).read_bytes(), s["patch"]) if s.get("patch") else {}
    rename = s.get("rename", {})
    fields = [("cardClass", "class"), ("rarity", "rarity"), ("set", "set"), ("collectible", "collectible"),
              ("cost", "cost"), ("attack", "attack"), ("health", "health"), ("durability", "durability"),
              ("race", "race"), ("mechanics", "keywords"), ("referencedTags", "refs"), ("spellDamage", "spell_power"),
              ("overload", "mana_lock"), ("elite", "unique"), ("dbfId", "code_id"), ("legacyDbfId", "legacy_code_id")]
    out = []
    for c in sorted(data, key=lambda c: c["id"]):
        card = {"id": c["id"], "type": rename.get(c["type"], c["type"])}
        for a, k in fields:
            if c.get(a) is not None and c[a] is not False and c[a] != []:
                card[k] = c[a]
        card.update(patch.get(c["id"], {}))
        out.append(card)
        for lang, hs in s["locales"].items():
            for field in ("name", "text"):
                t = c.get(field, {}).get(hs)
                if t:
                    b.put(lang, t, "cards", c["id"], field)
    unknown = sorted(set(patch) - {c["id"] for c in out})
    if unknown:
        raise PackError(f"{s['patch']}: unknown cards {unknown[:5]}")
    b.cards = out


def step_keywords(b, root, s):
    for name, kw in load_json((root / s["from"]).read_bytes(), s["from"]).items():
        for field, to in (("name", "name"), ("text", "tip")):
            for lang, t in kw.get(field, {}).items():
                b.put(lang, t, "mechanics", name, to)


def step_voice(b, root, s):
    for cid, kinds in load_json((root / s["from"]).read_bytes(), s["from"]).items():
        for kind, by_lang in kinds.items():
            if isinstance(by_lang, dict):
                for lang, t in by_lang.items():
                    b.put(lang, t, "voice", cid, kind)


def step_translate(b, root, s):
    """Fills sections of the other languages from the default language's English strings, looked up in
    the game's UI translations (data/i18n/<lang>.json: English -> text)."""
    base = b.manifest["default_locale"]

    def walk(src, keys, table, lang):
        for k, v in src.items():
            if isinstance(v, dict):
                walk(v, keys + [k], table, lang)
            elif isinstance(v, str) and v in table:
                b.put(lang, table[v], *keys, k)

    for lang in b.manifest["locales"]:
        f = root / s["from"] / f"{lang}.json"
        if lang == base or not f.exists():
            continue
        table = load_json(f.read_bytes(), str(f))
        for sec in s["sections"]:
            walk(b.loc(base).get(sec, {}), [sec], table, lang)


def step_rank_names(b, root, s):
    """A rank whose emblem is a card is named after that card (as the Classic client did)."""
    for x in (b.rules.get("ranked") or {}).get("ranks", []):
        cid = (x.get("emblem") or {}).get("card")
        for lang in b.manifest["locales"]:
            name = b.loc(lang).get("cards", {}).get(cid, {}).get("name")
            if name:
                b.put(lang, name, "ranks", str(x["rank"]))


def step_source(b, root, s):
    """A pack source written in its own shape (packs/neon): drops source-only card fields and files, moves files
    (pictures of the pack into ui/), takes each locale's `pack` {name, description} into the manifest
    and its `terms` into `ui` (keys lowercased)."""
    if s.get("drop_card_fields") and "cards.json" in b.files:
        cards = load_json(b.files["cards.json"], "cards.json")
        b.files["cards.json"] = pretty([{k: v for k, v in c.items() if k not in s["drop_card_fields"]} for c in cards])
    names = b.locales.get(b.manifest.get("default_locale", "en"), {}).get("decks", {})
    for p in [p for p in b.files if p.startswith("decks/") and p.endswith(".json")]:
        d = load_json(b.files[p], p)
        if "id" in d and "name" not in d:  # {id, …} -> {name: the deck's name in the default locale, …}
            d = {"name": names.get(d["id"], d["id"]), **{k: v for k, v in d.items() if k != "id"}}
            b.files[p] = pretty(d)
    for f in s.get("drop_files", []):
        b.files.pop(f, None)
    for frm, to in s.get("move", {}).items():
        if frm not in b.files:
            raise PackError(f"source: {frm} is not in the source")
        b.files[to] = b.files.pop(frm)
    for lang, loc in b.locales.items():
        meta = loc.pop("pack", {})
        for k in ("name", "description"):
            if k in meta:
                b.manifest.setdefault(k, {}).setdefault(lang, meta[k])
        for k, v in loc.pop("terms", {}).items():
            loc.setdefault("ui", {}).setdefault(k.lower(), v)


STEPS = {"source": step_source, "copy": step_copy, "hsjson": step_hsjson, "keywords": step_keywords, "voice": step_voice,
         "translate": step_translate, "rank_names": step_rank_names}


def build(src, out=None, art_sets=()):
    """Builds the pack in folder src; writes it to out if given. Returns (files, report)."""
    src = Path(src)
    b = Build(src)
    skip = {"recipe.json"}
    for f in sorted(src.rglob("*")):
        rel = f.relative_to(src).as_posix()
        if not f.is_file() or rel in skip or rel.endswith(".patch.json") or f.name.startswith(".") \
                or f.name.endswith(".import"):
            continue
        if rel.startswith("locales/") and rel.endswith(".json"):
            b.locales[f.stem] = load_json(f.read_bytes(), rel)
            continue
        b.files[rel] = f.read_bytes()
    b.manifest = load_json(b.files.get("manifest.json", b"{}"), "manifest.json")
    b.rules = load_json(b.files.get("rules.json", b"{}"), "rules.json")
    if (src / "recipe.json").exists():
        recipe = load_json((src / "recipe.json").read_bytes(), "recipe.json")
        root = (src / recipe.get("root", ".")).resolve()
        for s in recipe["steps"]:
            if s["do"] not in STEPS:
                raise PackError(f"recipe.json: unknown step {s['do']}")
            STEPS[s["do"]](b, root, s)
    for spec in art_sets:
        set_id, _, folder = spec.partition("=")
        folder = Path(folder).resolve()
        if not re.match(r"^[a-z0-9_]{1,32}$", set_id) or not folder.is_dir():
            raise PackError(f"--art-set {spec}: want id=folder")
        if folder == (REPO / "art/original").resolve():
            raise PackError("art/original never goes into a pack")
        n = 0
        for f in sorted(folder.iterdir()):
            if f.is_file() and f.suffix.lower() in IMAGES:
                b.files[f"art/{set_id}/{f.name}"] = f.read_bytes()
                n += 1
        if not n:
            raise PackError(f"--art-set {spec}: no pictures")
        b.manifest.setdefault("art_sets", []).append({"id": set_id, "local": True})
    if b.cards is not None:
        b.files["cards.json"] = pretty(b.cards)
    for lang, loc in b.locales.items():
        b.files[f"locales/{lang}.json"] = pretty(loc)
    cards = load_json(b.files.get("cards.json", b"[]"), "cards.json")
    b.manifest["fx"] = sorted({v for c in cards for v in c.get("fx", {}).values()})
    b.manifest["rules_hash"] = rules_hash(b.files)
    b.files["manifest.json"] = pretty(b.manifest)
    report = check_files(b.files)
    if out and not report.errors:
        write_pack(b.files, out)
    return b.files, report


# --- info --------------------------------------------------------------------------------------

def info(files, packed_size=None):
    man = load_json(files["manifest.json"], "manifest.json")
    cards = load_json(files["cards.json"], "cards.json")
    sizes = {}
    for p, d in files.items():
        top = p.split("/")[0] if "/" in p else "(top)"
        if top in ("art", "sounds", "music", "voice"):
            top = "/".join(p.split("/")[:2])
        n, s = sizes.get(top, (0, 0))
        sizes[top] = (n + 1, s + len(d))
    types = {}
    for c in cards:
        types[c["type"]] = types.get(c["type"], 0) + 1
    lines = [f"{man['id']} {man['version']} ({man['name'].get(man['default_locale'], '')})"]
    if packed_size is not None:
        lines.append(f"file: {packed_size} bytes ({packed_size / MiB:.1f} MiB)")
    lines.append(f"files: {len(files)}, unpacked {sum(len(d) for d in files.values()) / MiB:.1f} MiB")
    lines += [f"  {k:<20} {n:>5} files {s / MiB:8.2f} MiB" for k, (n, s) in sorted(sizes.items())]
    lines.append(f"cards: {len(cards)} ({', '.join(f'{k} {v}' for k, v in sorted(types.items()))}), "
                 f"collectible {sum(1 for c in cards if c.get('collectible'))}")
    lines.append(f"locales: {', '.join(man['locales'])}")
    for kind in ("art_sets", "sound_sets", "music_sets"):
        lines.append(f"{kind}: {', '.join(s['id'] + (' (local)' if s.get('local') else '') for s in man.get(kind, []))}")
    lines.append(f"decks: {sum(1 for p in files if p.startswith('decks/'))}, "
                 f"missions: {sum(1 for p in files if p.startswith('missions/'))}, "
                 f"scripts: {sum(1 for p in files if p.startswith('scripts/') and p.endswith('.lua'))}")
    lines.append(f"rules_hash:   {rules_hash(files)}")
    lines.append(f"content_hash: {content_hash(files)}")
    return "\n".join(lines)


# --- command line ------------------------------------------------------------------------------

def _print_report(r, what):
    for e in r.errors:
        print(f"ERROR: {e}")
    for w in r.warnings:
        print(f"warning: {w}")
    print(f"{what}: {len(r.errors)} errors, {len(r.warnings)} warnings")


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    pb = sub.add_parser("build", help="build a pack from a source folder")
    pb.add_argument("src")
    pb.add_argument("-o", "--out", required=True)
    pb.add_argument("--art-set", action="append", default=[], metavar="ID=FOLDER",
                    help="add a local art set (never for distribution; art/original is refused)")
    for name, text in (("check", "validate a pack"), ("info", "sizes, counts, hashes"), ("hash", "rules_hash and content_hash")):
        sub.add_parser(name, help=text).add_argument("pack")
    a = ap.parse_args(argv)
    try:
        if a.cmd == "build":
            files, r = build(a.src, a.out, a.art_set)
            _print_report(r, "build")
            if r.errors:
                return 1
            print(info(files, Path(a.out).stat().st_size))
            return 0
        files = read_pack(a.pack)
        if a.cmd == "check":
            r = check_files(files)
            _print_report(r, a.pack)
            return 1 if r.errors else 0
        if a.cmd == "info":
            print(info(files, Path(a.pack).stat().st_size))
        else:
            print(f"rules_hash   {rules_hash(files)}\ncontent_hash {content_hash(files)}")
        return 0
    except (PackError, zipfile.BadZipFile, OSError, KeyError) as e:
        print(f"ERROR: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
