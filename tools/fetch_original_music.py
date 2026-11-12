#!/usr/bin/env python3
"""The original Hearthstone music for the owner's LOCAL packs (never for git, never for a distributed pack: it
belongs to Blizzard Entertainment).

Usage: python3 tools/fetch_original_music.py [--set classic ...] [--out ~/ClassicHS-local]
       (also: python3 tools/fetch_set_assets.py --set <s> --only music; --build then adds the music set `original`)

Result: <out>/<set>/music/<slot>.opus (tools/audio_codec.py, music: 128 kbit/s, 48 kHz, stereo as the original)
for `tools/pack.py build … --music-set original=<out>/<set>/music`. Slots (docs/packs/format.md, "Music"): menu,
mulligan, battle_1 … battle_N (the board's playlist), victory, defeat (the result's jingle), arena.
The originals stay in <out>/audio-src/music/: raw/ the client files as downloaded, <set>/<track>.ogg the tracks
(the game's own Vorbis streams, not re-encoded), SOURCES.md what came from where.

Source: the iOS client 4.1.10956 (November 2015, The League of Explorers) kept on archive.org (item app-id-73):
its sounds0/sounds1.unity3d (Unity 5.1, uncompressed) hold every track up to then as FSB5 Vorbis. FMOD strips the
Vorbis headers; the setup header is the one libvorbisenc makes for the quality the FSB names by CRC32 (VORBIS_SETUP)
and is checked against that CRC32. Needs libvorbis/libvorbisenc (Homebrew: brew install libvorbis) and ffmpeg.
The playlists are the client's own (its MusicConfig: UI_MainTitle, InGame_Mulligan, InGame_Default, the boards'
playlists, UI_Arena; UI_EndGameScreen has no music, only the victory/defeat jingle).
"""
import argparse
import ctypes
import ctypes.util
import struct
import subprocess
import sys
import time
import urllib.parse
import urllib.request
import zlib
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import audio_codec  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent

UA = "ClassicHSVoiceCollector/1.0 (hobby fan project)"
CLIENT = "ios-4.1.10956"
IPA = "https://archive.org/download/app-id-73/Hearthstone%204.1.10956.ipa/"
BUNDLES = {"sounds0.unity3d": "Payload/hearthstone.app/Data/Raw/Data/sounds0.unity3d",
           "sounds1.unity3d": "Payload/hearthstone.app/Data/Raw/Data/sounds1.unity3d"}

# The playlists of the client (MusicConfig). The default pool (InGame_Default) is also the Goblins vs Gnomes,
# Grand Tournament, Old Gods, Gadgetzan and Un'Goro boards' (hearthstone.wiki.gg, Battlefield); Naxxramas,
# Blackrock Mountain and the League of Explorers boards play their adventure's own.
DEFAULT_POOL = ["Bad Reputation", "Better Hand", "Don't Let Your Guard Down", "Duel", "On a Roll"]
COMMON = {"menu": "Main_Title", "mulligan": "Mulligan", "victory": "victory_jingle", "defeat": "defeat_jingle",
          "arena": "The_Forge"}
OWN = {  # set: (menu, the board's playlist); None: the common menu, the default pool
    "naxx": ("Naxx_Menu_Music", ["Naxx_Frostwyrm_Lair", "Naxx_Plague_Wing", "Naxx_Walking"]),
    "brm": ("BRM_Menu_Music", ["BRM_Bad_Down_to_the_Molten_Core", "BRM_Battle_Two", "BRM_Volcano_Man_Rising"]),
    "loe": ("LOE_FrontMenu_Music", ["LOE_Orsis", "LOE_Mine_Cart_Chase", "LOE_Uldaman"]),
}
# Karazhan, Knights of the Frozen Throne, Kobolds & Catacombs and The Witchwood had boards with their own music,
# but no copy of a client of 2016-2018 with it was found: these packs get the default pool (see SOURCES.md).
SETS = ["classic", "naxx", "gvg", "brm", "tgt", "loe", "og", "kara", "msg", "ungoro", "icc", "loot", "gil"]
HOME = {t: s for s, (m, b) in OWN.items() for t in [m] + b}  # where an original is kept (the set that brought it)

# FSB5 Vorbis CRC32 of the setup header -> (FMOD quality 1..100, channels, rate): the entries these tracks use.
VORBIS_SETUP = {2767611644: (81, 2, 48000), 1777296130: (90, 2, 48000), 542711418: (63, 2, 48000)}
FREQ = {1: 8000, 2: 11000, 3: 11025, 4: 16000, 5: 22050, 6: 24000, 7: 32000, 8: 44100, 9: 48000}


def plan(set_id):
    """{slot: original track name} of a set's music."""
    menu, board = OWN.get(set_id, (COMMON["menu"], DEFAULT_POOL))
    out = dict(COMMON, menu=menu)
    out.update({f"battle_{i}": t for i, t in enumerate(board, 1)})
    return out


# --- the client's files ----------------------------------------------------------------------------------------

def download(raw):
    raw.mkdir(parents=True, exist_ok=True)
    for name, member in BUNDLES.items():
        dst = raw / name
        if dst.exists():
            continue
        url = IPA + urllib.parse.quote(member, safe="")
        print(f"downloading {url}")
        req = urllib.request.Request(url, headers={"User-Agent": UA})
        with urllib.request.urlopen(req, timeout=600) as r:
            dst.with_suffix(".part").write_bytes(r.read())
        dst.with_suffix(".part").rename(dst)
        time.sleep(2)


def clips(data):
    """{AudioClip name: FSB5 bytes} of a Unity 5 bundle (UnityRaw): each clip's m_Name … m_Resource (source,
    offset, size) points into the bundle's .resource file, whose start is where every clip lands on 'FSB5'."""
    recs = []
    pos = 0
    while (pos := data.find(b"archive:/", pos)) >= 0:
        n = struct.unpack_from("<i", data, pos - 4)[0]
        if 0 < n < 300 and data[pos:pos + n].endswith(b".resource"):
            off, size = struct.unpack_from("<QQ", data, pos + n + (-n % 4))
            name = _name_before(data, pos - 4)
            if name and size:
                recs.append((name, off, size))
        pos += 9
    if not recs:
        return {}
    first = min(r[1] for r in recs)
    p = 0
    while (p := data.find(b"FSB5", p)) >= 0:
        base = p - first
        if all(data[base + o:base + o + 4] == b"FSB5" for _, o, _ in recs):
            return {name: data[base + o:base + o + s] for name, o, s in recs}
        p += 4
    raise ValueError("no .resource start found")


def _name_before(data, pos):
    """The last length-prefixed name in the 200 bytes before pos (the clip's m_Name)."""
    best = None
    for i in range(max(0, pos - 200), pos - 5):
        n = struct.unpack_from("<i", data, i)[0]
        if 3 <= n <= 120 and i + 4 + n <= pos:
            s = data[i + 4:i + 4 + n]
            if all(c in b"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_ .-'()&,!" for c in s):
                best = s.decode()
    return best


# --- FSB5 Vorbis -> Ogg Vorbis ---------------------------------------------------------------------------------

class _Packet(ctypes.Structure):
    _fields_ = [("packet", ctypes.c_void_p), ("bytes", ctypes.c_long), ("b_o_s", ctypes.c_long),
                ("e_o_s", ctypes.c_long), ("granulepos", ctypes.c_longlong), ("packetno", ctypes.c_longlong)]


def _lib(name):
    for path in (ctypes.util.find_library(name), f"/opt/homebrew/lib/lib{name}.dylib", f"/usr/local/lib/lib{name}.dylib",
                 f"lib{name}.so.0", f"lib{name}.so.2"):
        try:
            return ctypes.CDLL(path) if path else None
        except OSError:
            continue
    raise SystemExit(f"lib{name} is missing (brew install libvorbis)")


def vorbis_headers(quality, channels, rate):
    """The id, comment and setup header libvorbisenc makes for FMOD's quality (1..100), and the block sizes."""
    vorbis, enc = _lib("vorbis"), _lib("vorbisenc")
    enc.vorbis_encode_setup_vbr.argtypes = [ctypes.c_void_p, ctypes.c_long, ctypes.c_long, ctypes.c_float]
    info, dsp, comment = (ctypes.create_string_buffer(n) for n in (4096, 16384, 1024))  # (larger than the structs)
    vorbis.vorbis_info_init(info)
    q = -0.1 + 1.1 * (quality - 1) / 99
    ok = enc.vorbis_encode_setup_vbr(info, channels, rate, q) == 0 \
        and enc.vorbis_encode_ctl(info, 0x41, ctypes.byref(ctypes.c_int(1))) == 0 \
        and enc.vorbis_encode_setup_init(info) == 0 and vorbis.vorbis_analysis_init(dsp, info) == 0
    if not ok:
        raise ValueError("libvorbisenc refused the setup")
    vorbis.vorbis_comment_init(comment)
    ps = [_Packet() for _ in range(3)]
    vorbis.vorbis_analysis_headerout(dsp, comment, *[ctypes.byref(p) for p in ps])
    out = [ctypes.string_at(p.packet, p.bytes) for p in ps]
    sizes = (vorbis.vorbis_info_blocksize(info, 0), vorbis.vorbis_info_blocksize(info, 1))
    vorbis.vorbis_dsp_clear(dsp)
    return out, sizes


def mode_blockflags(setup):
    """Each mode's block flag, read backwards from the end of a setup header (as ffmpeg's vorbis_parser does):
    … [mode count - 1: 6 bits] [blockflag 1, window 16 = 0, transform 16 = 0, mapping 8] × count, framing bit."""
    bits = [(b >> i) & 1 for b in setup for i in range(8)]  # Vorbis packs bits LSB first
    p = len(bits) - 1
    while not bits[p]:
        p -= 1
    flags, best = [], None
    while p - 41 >= 6 and len(flags) < 64:
        mode = bits[p - 41:p]
        if any(mode[1:33]):
            break
        flags.insert(0, mode[0])
        p -= 41
        if sum(b << i for i, b in enumerate(bits[p - 6:p])) + 1 == len(flags):
            best = list(flags)  # the largest consistent count (a smaller one can match by chance)
    if best is None:
        raise ValueError("no Vorbis modes found")
    return best


def _crc_table():
    t = []
    for i in range(256):
        r = i << 24
        for _ in range(8):
            r = ((r << 1) ^ 0x04C11DB7) if r & 0x80000000 else r << 1
        t.append(r & 0xFFFFFFFF)
    return t


_CRC = _crc_table()


def ogg_page(packets, granule, seq, flags, serial=1):
    """One Ogg page of whole packets (flags: 2 first page, 4 last)."""
    lacing = b"".join(b"\xff" * (len(p) // 255) + bytes([len(p) % 255]) for p in packets)
    page = bytearray(struct.pack("<4sBBqIIIB", b"OggS", 0, flags, granule, serial, seq, 0, len(lacing)) + lacing
                     + b"".join(packets))
    c = 0
    for b in page:
        c = ((c << 8) & 0xFFFFFFFF) ^ _CRC[((c >> 24) ^ b) & 0xFF]
    page[22:26] = struct.pack("<I", c)
    return bytes(page)


def fsb_to_ogg(fsb):
    """The first sample of an FSB5 Vorbis bank as an Ogg Vorbis file: (bytes, channels, rate, seconds)."""
    if fsb[:4] != b"FSB5":
        raise ValueError("not an FSB5 bank")
    ver, _n, heads, names, size, mode = struct.unpack_from("<6I", fsb, 4)
    if mode != 15:
        raise ValueError(f"not Vorbis (FSB mode {mode})")
    p = 60 + (4 if ver == 0 else 0)
    head = p
    raw = struct.unpack_from("<Q", fsb, p)[0]
    more, rate, ch, total = raw & 1, FREQ.get((raw >> 1) & 0xF), ((raw >> 5) & 1) + 1, (raw >> 34) & (2 ** 30 - 1)
    p += 8
    crc = None
    while more:
        c = struct.unpack_from("<I", fsb, p)[0]
        more, n, kind = c & 1, (c >> 1) & 0xFFFFFF, (c >> 25) & 0x7F
        body = fsb[p + 4:p + 4 + n]
        crc = struct.unpack_from("<I", body)[0] if kind == 11 else crc
        rate = struct.unpack_from("<I", body)[0] if kind == 2 else rate
        ch = body[0] if kind == 1 else ch
        p += 4 + n
    if crc not in VORBIS_SETUP:
        raise ValueError(f"unknown Vorbis setup (crc32 {crc}): add it to VORBIS_SETUP")
    (ident, comment, setup), (short, long_) = vorbis_headers(*VORBIS_SETUP[crc])
    if zlib.crc32(setup) != crc:
        raise ValueError("the rebuilt setup header does not match the bank's")
    ident = ident[:11] + bytes([ch]) + struct.pack("<I", rate) + ident[16:]
    flags = mode_blockflags(setup)
    mbits = max(1, (len(flags) - 1).bit_length())
    audio = fsb[head + heads + names:head + heads + names + size]
    packets, i = [], 0
    while i + 2 <= len(audio) and (n := struct.unpack_from("<H", audio, i)[0]):
        packets.append(audio[i + 2:i + 2 + n])
        i += 2 + n
    pages, seq, granule, prev, pend = [ogg_page([ident], 0, 0, 2), ogg_page([comment, setup], 0, 1, 0)], 2, 0, 0, []
    for k, pk in enumerate(packets):
        bs = long_ if flags[(pk[0] >> 1) & ((1 << mbits) - 1)] else short
        granule = granule + (bs + prev) // 4 if prev else 0
        prev = bs
        pend.append(pk)
        last = k == len(packets) - 1
        if last or sum(map(len, pend)) > 4000 or sum(len(x) // 255 + 1 for x in pend) > 200:
            pages.append(ogg_page(pend, min(granule, total) if last else granule, seq, 4 if last else 0))
            seq, pend = seq + 1, []
    return b"".join(pages), ch, rate, total / rate


# --- the work ----------------------------------------------------------------------------------------------------

def originals(src, names):
    """The wanted tracks as <src>/<set that brought it>/<name>.ogg, extracted once from the cached client."""
    want = {n for n in names if not (src / HOME.get(n, "classic") / f"{n}.ogg").exists()}
    if want:
        download(src / "raw" / CLIENT)
        for bundle in BUNDLES:
            for name, fsb in clips((src / "raw" / CLIENT / bundle).read_bytes()).items():
                if name in want:
                    ogg = fsb_to_ogg(fsb)[0]
                    dst = src / HOME.get(name, "classic") / f"{name}.ogg"
                    dst.parent.mkdir(parents=True, exist_ok=True)
                    dst.write_bytes(ogg)
                    want.discard(name)
    if want:
        raise SystemExit(f"not in the client: {sorted(want)}")
    return {n: src / HOME.get(n, "classic") / f"{n}.ogg" for n in names}


def probe(path):
    """(seconds, channels, rate) of an audio file (ffprobe)."""
    r = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration:stream=channels,sample_rate",
                        "-of", "default=nw=1", str(path)], capture_output=True, text=True)
    v = dict(line.split("=", 1) for line in r.stdout.split() if "=" in line)
    return float(v.get("duration", 0)), int(v.get("channels", 0)), int(v.get("sample_rate", 0))


def run(sets, out, ffmpeg=None):
    src = out / "audio-src/music"
    plans = {s: plan(s) for s in sets}
    files = originals(src, sorted({t for p in plans.values() for t in p.values()}))
    for s, p in plans.items():
        dest = out / s / "music"
        dest.mkdir(parents=True, exist_ok=True)
        for old in dest.glob("battle_*.opus"):  # (a playlist that got shorter)
            if old.stem not in p:
                old.unlink()
        for slot, track in p.items():
            dst = dest / f"{slot}.opus"
            if not dst.exists() and not audio_codec.encode_opus(files[track], dst, "music", ffmpeg):
                raise SystemExit(f"ffmpeg could not encode {dst} (it needs libopus)")
        print(f"{s}: {len(p)} tracks in {dest}")
    sources(src, files)


def sources(src, files):
    users = {}
    for s in SETS:
        for slot, t in plan(s).items():
            users.setdefault(t, {}).setdefault(slot, []).append(s)
    rows = []
    for t, path in sorted(files.items(), key=lambda kv: (HOME.get(kv[0], "classic"), kv[0])):
        secs, ch, rate = probe(path)
        slots = "; ".join(f"{slot}: {', '.join(ss)}" for slot, ss in users.get(t, {}).items())
        rows.append(f"| {t} | {path.relative_to(src)} | {secs:.1f} s, {ch} ch, {rate} Hz | {slots} |")
    (src / "SOURCES.md").write_text(f"""# Original Hearthstone music (local only, never in git or a distributed pack)

Made by tools/fetch_original_music.py. The tracks are the game's own Vorbis streams, taken out of the iOS
client 4.1.10956 (November 2015) kept on archive.org (item app-id-73, the file "Hearthstone 4.1.10956.ipa"):
{IPA}{urllib.parse.quote(BUNDLES['sounds0.unity3d'], safe='')}
{IPA}{urllib.parse.quote(BUNDLES['sounds1.unity3d'], safe='')}
(cached in raw/{CLIENT}/). FSB5 Vorbis -> Ogg Vorbis without re-encoding (the setup header rebuilt with
libvorbisenc and checked against the bank's CRC32). The packs get <set>/music/<slot>.opus (128 kbit/s).

Playlists: the client's MusicConfig (UI_MainTitle, InGame_Mulligan, InGame_Default, InGame_GvGBoard = the default
pool, the Naxxramas, Blackrock and League of Explorers boards' own, UI_Arena; UI_EndGameScreen plays no music,
the result plays victory_jingle / defeat_jingle). The default pool is also the board music of The Grand Tournament,
Whispers of the Old Gods, Mean Streets of Gadgetzan and Journey to Un'Goro (hearthstone.wiki.gg, Battlefield).
Naxxramas, Blackrock Mountain, the League of Explorers: their adventure's menu music as the pack's menu.

Not found: the own board music of One Night in Karazhan, Knights of the Frozen Throne, Kobolds & Catacombs and
The Witchwood (2016-2018). The wiki keeps only short stingers; the iOS client of 2019 on archive.org
(Hearthstone_15.2.34104_ios_8.0) has these expansions' music outside its base install. Those packs play the
default pool until a copy of the original files turns up.

| Track | File | Original | Slot: packs |
|---|---|---|---|
""" + "\n".join(rows) + "\n")


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--set", action="append", choices=SETS, help="the pack (several allowed; default: all)")
    ap.add_argument("--out", default="~/ClassicHS-local")
    ap.add_argument("--ffmpeg", default=None)
    a = ap.parse_args(argv)
    out = Path(a.out).expanduser().resolve()
    if ROOT in out.parents or out == ROOT:
        raise SystemExit("--out must be outside the repository (these files never go into git)")
    run(a.set or SETS, out, a.ffmpeg)


if __name__ == "__main__":
    main()
