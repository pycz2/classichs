#!/usr/bin/env python3
"""Synthesizes the game's sounds and music loops into audio/*.wav (pure Python, no dependencies).

Usage: python3 tools/gen_audio.py
Output is deterministic: the same script gives the same files.
"""
import math
import os
import random
import struct
import wave

RATE = 22050
OUT = os.path.join(os.path.dirname(__file__), "..", "audio")
rng = random.Random(2014)


def silence(dur):
    return [0.0] * int(RATE * dur)


def env(n, attack=0.01, release=0.2):
    """Linear attack, exponential decay over n samples."""
    a = max(1, int(RATE * attack))
    out = []
    for i in range(n):
        x = i / RATE
        e = min(1.0, i / a) * math.exp(-x / max(release, 1e-3))
        out.append(e)
    return out


def osc(kind, phase):
    p = phase % 1.0
    if kind == "sine":
        return math.sin(2 * math.pi * p)
    if kind == "square":
        return 1.0 if p < 0.5 else -1.0
    if kind == "saw":
        return 2 * p - 1
    if kind == "tri":
        return 4 * abs(p - 0.5) - 1
    return rng.uniform(-1, 1)  # noise


def tone(f0, dur, kind="sine", f1=None, attack=0.005, release=0.15, vol=0.5):
    """A note sliding from f0 to f1 Hz."""
    n = int(RATE * dur)
    f1 = f0 if f1 is None else f1
    e = env(n, attack, release)
    out, phase = [], 0.0
    for i in range(n):
        f = f0 + (f1 - f0) * i / n
        phase += f / RATE
        out.append(osc(kind, phase) * e[i] * vol)
    return out


def noise(dur, release=0.1, vol=0.4, lowpass=0.0):
    n = int(RATE * dur)
    e = env(n, 0.002, release)
    out, last = [], 0.0
    for i in range(n):
        last = last * lowpass + rng.uniform(-1, 1) * (1 - lowpass)
        out.append(last * e[i] * vol)
    return out


def mix(*tracks, offsets=None):
    offsets = offsets or [0.0] * len(tracks)
    n = max(int(o * RATE) + len(t) for t, o in zip(tracks, offsets))
    out = [0.0] * n
    for t, o in zip(tracks, offsets):
        s = int(o * RATE)
        for i, v in enumerate(t):
            out[s + i] += v
    return out


def seq(*parts):
    out = []
    for p in parts:
        out += p
    return out


def note(name):
    """'A4' → Hz."""
    names = {"C": -9, "D": -7, "E": -5, "F": -4, "G": -2, "A": 0, "B": 2}
    semis = names[name[0]] + (1 if "#" in name else 0) + 12 * (int(name[-1]) - 4)
    return 440.0 * 2 ** (semis / 12)


def save(name, samples):
    os.makedirs(OUT, exist_ok=True)
    peak = max(1e-9, max(abs(s) for s in samples))
    scale = 0.9 / peak if peak > 0.9 else 1.0
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, s * scale)) * 32767)) for s in samples))


# ---------------------------------------------------------------------------- music
# A song is a score (chords by name, melody in scale degrees) played by a few soft
# instruments: Karplus-Strong lute, harp and bass, an additive flute with vibrato,
# a detuned pad and hand percussion (frame drum, rim, shaker, tambourine), with an
# echo on the lead and a small Schroeder reverb. Note and reverb tails wrap around
# to the song's start, so the file loops without a seam.

TABLE = 4096
SOFT = [math.sin(2 * math.pi * i / TABLE) + 0.22 * math.sin(4 * math.pi * i / TABLE)
        + 0.08 * math.sin(6 * math.pi * i / TABLE) for i in range(TABLE)]
FLUTE = [math.sin(2 * math.pi * i / TABLE) + 0.16 * math.sin(4 * math.pi * i / TABLE)
         + 0.05 * math.sin(6 * math.pi * i / TABLE) for i in range(TABLE)]
SCALES = {"major": (0, 2, 4, 5, 7, 9, 11), "minor": (0, 2, 3, 5, 7, 8, 10), "dorian": (0, 2, 3, 5, 7, 9, 10)}
PC = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}
BEATS = {"waltz": 3, "four": 4, "gallop": 4, "jig": 6}  # jig = 6/8 counted in eighths
mrng = random.Random(1)


def hz(midi):
    return 440.0 * 2 ** ((midi - 69) / 12)


def lowpass(x, cut):
    """One-pole low-pass at cut Hz."""
    a = 1 - math.exp(-2 * math.pi * cut / RATE)
    out, y = [], 0.0
    for v in x:
        y += a * (v - y)
        out.append(y)
    return out


def comb(x, delay, g):
    """y[n] = x[n] + g * y[n - delay], computed a block of `delay` samples at a time."""
    d = max(1, int(delay * RATE))
    y = list(x)
    for s in range(d, len(y), d):
        e = min(s + d, len(y))
        y[s:e] = [a + g * b for a, b in zip(y[s:e], y[s - d:e - d])]
    return y


def allpass(x, delay, g):
    d = max(1, int(delay * RATE))
    y = [-g * v for v in x]
    for s in range(d, len(y), d):
        e = min(s + d, len(y))
        y[s:e] = [a + b + g * c for a, b, c in zip(y[s:e], x[s - d:e - d], y[s - d:e - d])]
    return y


def reverb(x):
    out = [0.0] * len(x)
    for delay, g in ((0.0297, 0.8), (0.0371, 0.79), (0.0411, 0.78), (0.0437, 0.77)):
        out = [a + b for a, b in zip(out, comb(x, delay, g))]
    return allpass(allpass(out, 0.005, 0.6), 0.0017, 0.6)


def looped(fn, x, warm=3.0):
    """fn over a looping signal: the end runs in first, so the start already has its tail."""
    w = int(warm * RATE)
    return fn(x[-w:] + x)[w:]


_plucks = {}


def pluck(midi, dur, bright=0.5, t60=1.5):
    """Karplus-Strong string with all-pass fine tuning; two cached takes per note."""
    takes = _plucks.setdefault((midi, round(dur, 2), bright, t60), [])
    if len(takes) == 2:
        takes.reverse()
        return takes[0]
    period = RATE / hz(midi) - 0.5  # the two-point average adds half a sample
    size = int(period)
    frac = period - size
    if frac < 0.2:
        size, frac = size - 1, frac + 1
    c = (1 - frac) / (1 + frac)
    loss = 0.001 ** (1 / (t60 * hz(midi)))
    line, y = [], 0.0
    for _ in range(size):
        y += bright * (mrng.uniform(-1, 1) - y)
        line.append(y)
    mean = sum(line) / size
    peak = max(abs(v - mean) for v in line) or 1.0
    line = [(v - mean) / peak for v in line]
    n = int(RATE * dur)
    out = [0.0] * n
    i, prev, ap_x, ap_y = 0, 0.0, 0.0, 0.0
    for k in range(n):
        v = line[i]
        out[k] = v
        avg = 0.5 * (v + prev)
        prev = v
        ap_y = c * (avg - ap_y) + ap_x
        ap_x = avg
        line[i] = ap_y * loss
        i += 1
        if i == size:
            i = 0
    fade = min(n // 4, int(RATE * 0.05))
    for k in range(fade):
        out[n - 1 - k] *= k / fade
    takes.append(out)
    return out


def flute(midi, dur, attack=0.06, vib=0.006, breath=0.25, table=FLUTE):
    """Additive soft tone: delayed vibrato, a breath of noise, attack and release."""
    f = hz(midi)
    held, rel = int(RATE * dur), int(RATE * 0.15)
    a = max(1, int(RATE * attack))
    rate = 5.0 + mrng.uniform(-0.4, 0.4)
    out = [0.0] * (held + rel)
    phase, nz, last = mrng.random(), 0.0, 0.0
    for k in range(held + rel):
        t = k / RATE
        if k < held:
            e = last = min(1.0, k / a) * (0.82 + 0.18 * math.exp(-t / 0.3))
        else:
            e = last * (1 - (k - held) / rel)
        phase += f * (1 + vib * min(1.0, t / 0.35) * math.sin(2 * math.pi * rate * t)) / RATE
        nz += 0.15 * (mrng.uniform(-1, 1) - nz)
        out[k] = (table[int(phase * TABLE) & (TABLE - 1)] + breath * nz) * e
    return out


def pad(midis, dur, attack=0.5, release=0.8):
    """Two slightly detuned soft voices per note, slow swell, low-passed."""
    held, n = int(RATE * dur), int(RATE * (dur + release))
    out = [0.0] * n
    for m in midis:
        for det in (0.996, 1.004):
            step = hz(m) * det * TABLE / RATE
            ph = mrng.random() * TABLE
            out = [o + SOFT[int(ph + step * k) & (TABLE - 1)] for k, o in enumerate(out)]
    a, r = int(RATE * attack), n - held
    top = min(1.0, held / a)
    out = [v * (min(1.0, k / a) if k < held else top * (n - k) / r) for k, v in enumerate(out)]
    return lowpass(out, 1800)


def drum_hit(f0, f1, decay, slap):
    n = int(RATE * min(1.0, decay * 5))
    out, ph, nz = [], 0.0, 0.0
    for k in range(n):
        t = k / RATE
        ph += (f1 + (f0 - f1) * math.exp(-t / 0.03)) / RATE
        nz += 0.25 * (mrng.uniform(-1, 1) - nz)
        out.append(math.sin(2 * math.pi * ph) * math.exp(-t / decay) + slap * nz * math.exp(-t / 0.012))
    return out


def hiss(dur, decay, attack, hp, ring=0.0):
    """High-passed noise burst; ring adds tambourine jingles."""
    n = int(RATE * dur)
    out, lp = [], 0.0
    for k in range(n):
        t = k / RATE
        x = mrng.uniform(-1, 1)
        lp += hp * (x - lp)
        jingle = 1 + ring * (math.sin(2 * math.pi * 5600 * t) + 0.7 * math.sin(2 * math.pi * 7400 * t))
        out.append((x - lp) * jingle * min(1.0, k / max(1, attack * RATE)) * math.exp(-t / decay))
    return out


def kit():
    """Three takes of each hand-percussion sound."""
    return {
        "drum": [drum_hit(105 + 6 * i, 62, 0.26, 1.2) for i in range(3)],
        "rim": [drum_hit(340 + 15 * i, 240, 0.05, 1.5) for i in range(3)],
        "shaker": [hiss(0.15, 0.04, 0.012, 0.35) for _ in range(3)],
        "tamb": [hiss(0.4, 0.11, 0.002, 0.5, 0.25) for _ in range(3)],
    }


KIT_GAIN = {"drum": 0.5, "rim": 0.16, "shaker": 0.07, "tamb": 0.07}


def _eighths(inst, vel, accent, beats):
    return [(i * 0.5, inst, accent if i % 2 == 0 else vel) for i in range(beats * 2)]


def _jig_shaker(on, off):
    return [(i, "shaker", on if i % 3 == 0 else off) for i in range(6)]


# Percussion per groove and level: (beat, sound, velocity). "h" = half-time pulse.
PERC = {
    "waltz": {
        1: [(0, "drum", 0.8), (1, "shaker", 0.5), (2, "shaker", 0.5)],
        2: [(0, "drum", 0.9), (2, "tamb", 0.5)] + _eighths("shaker", 0.35, 0.6, 3),
    },
    "four": {
        1: [(0, "drum", 0.9), (2, "drum", 0.7)] + _eighths("shaker", 0.3, 0.45, 4),
        2: [(0, "drum", 1), (2, "drum", 0.8), (2.5, "drum", 0.45), (1, "rim", 0.5), (3, "rim", 0.5),
            (1, "tamb", 0.5), (3, "tamb", 0.5)] + _eighths("shaker", 0.3, 0.45, 4),
        3: [(0, "drum", 1), (1.5, "drum", 0.55), (2, "drum", 0.9), (3.5, "drum", 0.5), (1, "rim", 0.7),
            (3, "rim", 0.7), (1, "tamb", 0.6), (3, "tamb", 0.6)]
           + [(i * 0.25, "shaker", 0.45 if i % 2 == 0 else 0.22) for i in range(16)],
        "h": [(0, "drum", 0.7), (1, "shaker", 0.35), (3, "shaker", 0.35)],
    },
    "gallop": {
        1: [(0, "drum", 0.9), (2, "drum", 0.75)] + [(b, "shaker", 0.35) for b in (0, 0.75, 1, 2, 2.75, 3)],
        2: [(b, "drum", v) for b, v in ((0, 1), (0.75, 0.5), (1, 0.7), (2, 0.9), (2.75, 0.5), (3, 0.7))]
           + [(1, "rim", 0.4), (3, "rim", 0.4), (1, "tamb", 0.5), (3, "tamb", 0.5)] + _eighths("shaker", 0.25, 0.4, 4),
        3: [(b, "drum", v) for b, v in ((0, 1), (0.75, 0.55), (1, 0.75), (2, 0.95), (2.75, 0.55), (3, 0.75), (3.5, 0.5))]
           + [(1, "rim", 0.6), (3, "rim", 0.6), (3.75, "rim", 0.4), (1, "tamb", 0.6), (3, "tamb", 0.6)]
           + _eighths("shaker", 0.3, 0.45, 4),
        "h": [(0, "drum", 0.75), (1, "shaker", 0.35), (3, "shaker", 0.35)],
    },
    "jig": {
        1: [(0, "drum", 0.9), (3, "drum", 0.6)] + _jig_shaker(0.45, 0.28),
        2: [(0, "drum", 1), (3, "drum", 0.7), (2, "rim", 0.4), (5, "rim", 0.4), (3, "tamb", 0.55)]
           + _jig_shaker(0.45, 0.28),
        3: [(0, "drum", 1), (3, "drum", 0.8), (5, "drum", 0.45), (2, "rim", 0.5), (4, "rim", 0.35), (5, "rim", 0.5),
            (0, "tamb", 0.4), (3, "tamb", 0.6)] + _jig_shaker(0.5, 0.3),
        "h": [(0, "drum", 0.7), (3, "shaker", 0.4)],
    },
}
# A small fill replaces the end of a section's last bar at levels 2 and 3: (from beat, hits).
FILL = {"waltz": (2, [(2, "drum", 0.6), (2.5, "drum", 0.75)]),
        "four": (2.5, [(2.5, "rim", 0.5), (3, "drum", 0.6), (3.25, "rim", 0.4), (3.5, "drum", 0.75), (3.75, "rim", 0.55)]),
        "gallop": (3, [(3, "drum", 0.7), (3.25, "drum", 0.5), (3.5, "drum", 0.8), (3.75, "rim", 0.55)]),
        "jig": (4, [(4, "drum", 0.6), (4.5, "rim", 0.4), (5, "drum", 0.8)])}
# Lute strums (beat, velocity) and bass notes (beat, interval above the root, velocity) per groove.
STRUM = {"waltz": {"strum": [(1, 1), (2, 0.9), (2.5, 0.35)], "drive": [(0, 0.6), (1, 0.8), (1.5, 0.4), (2, 0.7), (2.5, 0.4)]},
         "four": {"strum": [(0, 1), (1.5, 0.6), (2, 0.8), (3, 0.6), (3.5, 0.5)],
                  "drive": [(i * 0.5, v) for i, v in enumerate((1, 0.45, 0.7, 0.45, 0.9, 0.45, 0.7, 0.5))]},
         "gallop": {"strum": [(0, 1), (2, 0.8), (3, 0.6)],
                    "drive": [(0, 1), (0.75, 0.5), (1, 0.7), (2, 0.9), (2.75, 0.5), (3, 0.7)]},
         "jig": {"strum": [(0, 1), (2, 0.6), (3, 0.85), (5, 0.6)],
                 "drive": [(0, 1), (1, 0.4), (2, 0.6), (3, 0.85), (4, 0.4), (5, 0.6)]}}
BASS = {"waltz": {"calm": [(0, 0, 1)], "drive": [(0, 0, 1), (1, 7, 0.6), (2, 12, 0.6)]},
        "four": {"calm": [(0, 0, 1), (2, 7, 0.75)],
                 "drive": [(0, 0, 1), (0.5, 0, 0.5), (1, 0, 0.7), (1.5, 0, 0.5), (2, 0, 0.9), (2.5, 0, 0.5),
                           (3, 7, 0.7), (3.5, 12, 0.6)]},
        "gallop": {"calm": [(0, 0, 1), (2, 7, 0.75)],
                   "drive": [(0, 0, 1), (0.75, 0, 0.5), (1, 0, 0.7), (2, 0, 0.9), (2.75, 0, 0.5), (3, 7, 0.7)]},
        "jig": {"calm": [(0, 0, 1), (3, 7, 0.7)], "drive": [(0, 0, 1), (2, 0, 0.5), (3, 7, 0.8), (5, 0, 0.5)]}}


def parse_melody(text, beats):
    """'5:1 1\\':1.5 | r:3' -> [(scale step or None, accidental, beats)]. Every bar must add up."""
    notes, dur = [], 1.0
    for bar in text.split("|") if text else []:
        total = 0.0
        for tok in bar.split():
            deg, _, d = tok.partition(":")
            dur = float(d) if d else dur
            total += dur
            if deg == "r":
                notes.append((None, 0, dur))
            else:
                step = int(deg.strip("#b',")) - 1 + 7 * (deg.count("'") - deg.count(","))
                notes.append((step, deg.count("#") - deg.count("b"), dur))
        assert abs(total - beats) < 1e-6, "bar %r has %s beats, not %s" % (bar, total, beats)
    return notes


def chord_tones(name):
    """'Bbm' -> pitch classes of root, third, fifth."""
    root = (PC[name[0]] + name.count("#") - name[1:].count("b")) % 12
    return [root, (root + (3 if name.endswith("m") else 4)) % 12, (root + 7) % 12]


def above(pc, lo):
    """The lowest MIDI note of pitch class pc at or above lo."""
    return lo + (pc - lo) % 12


def song(tonic, scale, beat, groove, sections, seed):
    """Renders the sections into looped, normalized samples. tonic = MIDI note of degree 1."""
    mrng.seed(seed)
    _plucks.clear()
    drums = kit()
    bpb = BEATS[groove]
    bar = beat * bpb
    bars = sum(len(s["chords"].split()) for s in sections)
    size = int(round(bars * bar * RATE))
    band = [0.0] * (size + RATE * 5)
    lead = [0.0] * (size + RATE * 5)
    steps = SCALES[scale]

    def put(buf, t, samples, gain, jitter=0.0):
        s = max(0, int((t + mrng.uniform(-jitter, jitter)) * RATE))
        buf[s:s + len(samples)] = [a + gain * b for a, b in zip(buf[s:s + len(samples)], samples)]

    def note_of(step, acc=0):
        return tonic + 12 * (step // 7) + steps[step % 7] + acc

    t = 0.0
    for sec in sections:
        names = sec["chords"].split()
        perc = sec.get("perc", 0)
        levels = perc if isinstance(perc, list) else [perc] * len(names)
        counter = tonic
        for i, name in enumerate(names):
            t0 = t + i * bar
            tones = chord_tones(name)
            root = tones[0]
            if sec.get("pad") and (i == 0 or names[i - 1] != name):
                run = 1
                while i + run < len(names) and names[i + run] == name:
                    run += 1
                voicing = [above(root, 45), above(tones[1], 52), above(tones[2], 52), above(root, 57)]
                put(band, t0, pad(voicing, run * bar - 0.1), 0.028)
            if sec.get("lute"):
                strum = sorted(above(pc, 55) for pc in tones) + [above(root, 55) + 12]
                for b, vel in STRUM[groove][sec["lute"]]:
                    for k, m in enumerate(strum):
                        put(band, t0 + b * beat + 0.012 * k, pluck(m, 1.2, 0.45, 1.3),
                            0.22 * vel * (1 - 0.12 * k) * mrng.uniform(0.9, 1.05), 0.005)
            if sec.get("harp") == "arp":
                notes = sorted([above(root, 50), above(tones[1], 50), above(tones[2], 50)])
                notes += [n + 12 for n in notes]
                order = (0, 1, 2, 3, 4, 5, 4, 2) if bpb == 4 else (0, 1, 2, 3, 4, 5)
                step = beat / 2 if bpb < 6 else beat
                for k, idx in enumerate(order):
                    put(band, t0 + k * step, pluck(notes[idx], 2.0, 0.7, 2.5), 0.2 if k == 0 else 0.16, 0.004)
            if sec.get("bass"):
                kind = sec["bass"]
                long = kind == "long"
                for b, interval, vel in BASS[groove]["calm" if long else kind]:
                    m = above(root, 38) + interval
                    put(band, t0 + b * beat, pluck(m, 2.5 if long else 1.2, 0.3, 3.0 if long else 1.4), 0.55 * vel, 0.004)
            level = levels[i]
            if level:
                hits = PERC[groove][level]
                if i == len(names) - 1 and level in (2, 3):
                    cut, fill = FILL[groove]
                    hits = [h for h in hits if h[0] < cut or h[1] == "shaker"] + fill
                for b, inst, vel in hits:
                    put(band, t0 + b * beat, mrng.choice(drums[inst]), KIT_GAIN[inst] * vel * mrng.uniform(0.85, 1.1), 0.006)
            if sec.get("counter"):  # a soft second voice walking the nearest chord tones below the tune
                unit = 2 if bpb == 4 else 3
                for b in range(0, bpb, unit):
                    pool = [m for m in range(tonic - 8, tonic + 5) if m % 12 in tones]
                    pool.sort(key=lambda m: (abs(m - counter) or 2.5) + mrng.random())
                    counter = pool[0]
                    put(lead, t0 + b * beat, flute(counter, unit * beat * 0.95, 0.15, 0.003, 0.1, SOFT), 0.11)
        mel = parse_melody(sec.get("mel", ""), bpb)
        tt = t
        for j, (step, acc, beats) in enumerate(mel):
            d = beats * beat
            if step is None:
                tt += d
                continue
            m = note_of(step, acc)
            events = [(m, tt, d)]
            if sec.get("orn"):  # mordents, grace notes from above, passing tones across thirds
                nxt = mel[j + 1][0] if j + 1 < len(mel) else None
                r, g = mrng.random(), 0.07
                if d >= 0.7 and r < 0.3:
                    events = [(m, tt, g), (note_of(step + 1), tt + g, g), (m, tt + 2 * g, d - 2 * g)]
                elif d >= 0.35 and r < 0.6:
                    events = [(note_of(step + 1), tt, g), (m, tt + g, d - g)]
                elif nxt is not None and abs(nxt - step) == 2 and d >= 0.5 and acc == 0:
                    events = [(m, tt, d / 2), (note_of((step + nxt) // 2), tt + d / 2, d / 2)]
            for em, et, ed in events:
                put(lead, et, flute(em, ed * 0.97, min(0.06, ed / 3)), 0.2)
                if sec.get("harp") == "double" and ed > 0.1:
                    put(band, et, pluck(em - 12, 1.6, 0.6, 2.0), 0.16, 0.003)
            tt += d
        t += len(names) * bar

    def fold(buf):  # tails past the end ring on over the start, as they do when looping
        out = buf[:size]
        for k in range(size, len(buf)):
            out[k - size] += buf[k]
        return out

    band, lead = fold(band), fold(lead)
    lead = looped(lambda x: comb(x, beat * (3 if bpb == 6 else 0.75), 0.28), lead)
    dry = [a + b for a, b in zip(band, lead)]
    wet = looped(lambda x: reverb(lowpass(x, 4000)), dry)
    out = looped(lambda x: lowpass(x, 7500), [a + 0.07 * b for a, b in zip(dry, wet)], 0.1)
    peak = max(abs(v) for v in out)
    out = [0.89 * v / peak for v in out]
    edge = int(RATE * 0.004)  # restarting the player leaves a tiny gap: meet it at zero
    for k in range(edge):
        out[k] *= k / edge
        out[-1 - k] *= k / edge
    return out


MENU = [  # G major waltz: a calm tavern
    dict(chords="G C G D", pad=True, harp="arp", bass="long"),
    dict(chords="G Em C D G C D G", lute="strum", bass="calm", perc=1,
         mel="5:1 1':1.5 2':.5 | 3':1.5 2':.5 1':1 | 6:1 4':1 3':.5 2':.5 | 2':2 5:1 | "
             "5:1 1':1.5 2':.5 | 3':1 4':.5 3':.5 2':1 | 2':1 1':1 7:1 | 1':3"),
    dict(chords="Em Bm C G Em Bm Am D", lute="strum", bass="calm", perc=2, counter=True,
         mel="3':.5 2':.5 1':.5 7:.5 6:1 | 7:1 5:1 3':1 | 4':.5 3':.5 1':1 6:1 | 5:1.5 6:.5 7:1 | "
             "1':.5 2':.5 3':1 6:1 | 7:.5 1':.5 2':1 7:1 | 2':1 1':.5 7:.5 6:1 | 2':1.5 1':.5 7:1"),
    dict(chords="F C G G F C D D", pad=True, harp="arp", bass="long",
         mel="r:3 | r:3 | r:3 | r:3 | 4':2 2':1 | 1':3 | 2':1.5 1':.5 7:1 | 5:3"),
    dict(chords="G Em C D G C D G", lute="strum", harp="double", bass="calm", perc=2, orn=True,
         mel="5:1 1':1.5 2':.5 | 3':1.5 2':.5 1':1 | 6:1 4':1 3':.5 2':.5 | 2':2 5:1 | "
             "5:1 1':1.5 2':.5 | 3':1 4':.5 3':.5 2':1 | 2':1 1':1 7:1 | 1':3"),
    dict(chords="Em C Am D", lute="strum", pad=True, bass="calm", perc=[1, 1, 1, 0],
         mel="3':2 2':1 | 1':3 | 6:1 7:1 1':1 | 2':3"),
]

BATTLE_1_A = ("1:1.5 5,:.5 1:1 3:1 | 4:.5 3:.5 2:.5 3:.5 1:2 | 4:1.5 2:.5 7,:1 2:1 | 3:1 1:1 5,:2 | "
              "1:1.5 5,:.5 1:1 3:.5 5:.5 | 6:1.5 5:.5 4:1 3:1 | 4:1 6:1 1':1 6:.5 4:.5 | 5:1 2:1 #7,:2")
BATTLE_1 = [  # D minor, straight four, driving eighths
    dict(chords="Dm Dm Bb A", lute="strum", pad=True, bass="drive", perc=[1, 1, 2, 2]),
    dict(chords="Dm Bb C Dm Dm Bb Gm A", lute="drive", bass="drive", perc=2, mel=BATTLE_1_A),
    dict(chords="F C Gm Dm F C Bb A", lute="drive", bass="drive", perc=3, counter=True,
         mel="5:1 3:.5 5:.5 7:2 | 7:.5 6:.5 5:.5 4:.5 2:2 | 4:1 6:1 1':1.5 6:.5 | 5:3 r:1 | "
             "5:1 3:.5 5:.5 1':1 7:1 | 7:1 4:.5 5:.5 6:.5 5:.5 4:1 | 3:1 4:1 6:1 1':1 | #7:1.5 6:.5 5:2"),
    dict(chords="Bb Bb F F Gm Gm A A", pad=True, harp="arp", bass="long", perc="h",
         mel="r:4 | r:4 | 1':3 7:1 | 5:4 | 4:3 6:1 | 1':4 | #7:2 6:1 5:1 | 5:4"),
    dict(chords="Dm Bb C Dm Dm Bb Gm A", lute="drive", harp="double", bass="drive", perc=3, orn=True, mel=BATTLE_1_A),
    dict(chords="Gm Bb A A", lute="strum", pad=True, bass="calm", perc=[2, 2, 1, 1],
         mel="4:2 6:2 | 1':2 6:1 4:1 | 5:4 | #7,:2 5,:2"),
]

BATTLE_2_A = ("5,:1 1:1 3:1 5:1 | 4:1.5 3:.5 2:1 7,:1 | 1:1.5 3:.5 6,:2 | #7,:1 2:1 5,:2 | "
              "5,:.5 1:.5 3:1 5:1.5 6:.5 | 5:1 3:1 7,:1 3:1 | 4:1 6:1 1':1 6:1 | 5:1.5 4:.5 #7,:1 2:1")
BATTLE_2 = [  # E minor, galloping
    dict(chords="Em Em C D", pad=True, harp="arp", bass="long", perc=["h", "h", 1, 2]),
    dict(chords="Em D C B Em G Am B", lute="drive", bass="drive", perc=2, mel=BATTLE_2_A),
    dict(chords="C G D Em C G Am B", lute="drive", bass="drive", perc=3, counter=True,
         mel="3:1.5 1:.5 6,:1 1:1 | 7,:1 3:1 5:2 | 4:1.5 2:.5 7,:1 4:1 | 3:2 1:2 | "
             "6,:1 1:1 3:1.5 1:.5 | 7,:1 3:1 5:1 3:1 | 4:1.5 3:.5 1:1 6,:1 | #7,:2 2:1 #7,:1"),
    dict(chords="Am Am Em Em C C B B", pad=True, harp="arp", bass="long", perc="h",
         mel="r:4 | r:4 | 5:4 | 3:4 | 3:2 1:2 | 6,:4 | #7,:2 2:2 | 5,:4"),
    dict(chords="Em D C B Em G Am B", lute="drive", harp="double", bass="drive", perc=3, orn=True, mel=BATTLE_2_A),
    dict(chords="Am C B B", lute="strum", pad=True, bass="calm", perc=[2, 2, 1, "h"],
         mel="1:2 6,:2 | 3:2 1:2 | #7,:4 | 5,:4"),
]

JIG_A = ("5:2 1':1 7:2 5:1 | 4:2 7,:1 2:1 3:1 4:1 | 5:1 3:1 5:1 1':2 7:1 | 6:2 4:1 1:3 | "
         "5:2 1':1 7:2 5:1 | 4:1 5:1 7:1 2':2 1':1 | 7:1 5:1 2:1 5:2 4:1 | 3:1 2:1 7,:1 1:3")
JIG_B = ("3':2 2':1 1':2 7:1 | 2':2 7:1 4:3 | 6:1 1':1 2':1 1':2 6:1 | 5:3 1':3 | "
         "7:1 1':1 2':1 3':2 2':1 | 2':2 1':1 7:2 4:1 | 5:1 7:1 2':1 1':1 7:1 5:1 | 6:3 4:3")
BATTLE_3 = [  # A dorian 6/8 jig: a tavern brawl
    dict(chords="Am G Am E", lute="drive", bass="drive", perc=[1, 1, 2, 2]),
    dict(chords="Am G Am D Am G Em Am", lute="strum", bass="calm", perc=1, mel=JIG_A),
    dict(chords="Am G Am D Am G Em Am", lute="strum", bass="drive", perc=2, counter=True, mel=JIG_A),
    dict(chords="C G D Am C G Em D", lute="strum", harp="double", bass="drive", perc=2, mel=JIG_B),
    dict(chords="C G D Am C G Em D", lute="drive", bass="drive", perc=3, counter=True, orn=True, mel=JIG_B),
    dict(chords="C D Am Am C D Em Em", pad=True, harp="arp", bass="long", perc="h",
         mel="r:6 | r:6 | 1':6 | 5:6 | 3':6 | 1':6 | 7:6 | 5:6"),
    dict(chords="Am G Am D Am G Em Am", lute="drive", harp="double", bass="drive", perc=3, orn=True, mel=JIG_A),
    dict(chords="C D E E", lute="strum", bass="calm", perc=[2, 2, 2, 1],
         mel="3':2 2':1 1':3 | 1':2 6:1 4:3 | #7:3 2':3 | 5:6"),
]


def build():
    save("click", tone(1200, 0.05, "square", release=0.015, vol=0.25))
    save("play_card", mix(noise(0.12, 0.05, 0.3, 0.6), tone(220, 0.2, "sine", 110, release=0.08, vol=0.5)))
    save("attack", mix(noise(0.25, 0.08, 0.5, 0.3), tone(160, 0.25, "saw", 60, release=0.1, vol=0.35)))
    save("damage", mix(noise(0.18, 0.06, 0.5, 0.5), tone(300, 0.15, "square", 90, release=0.05, vol=0.25)))
    # a heavy blow on a hero (more than 5 damage): a deep thud under a crunch
    save("hit_big", mix(tone(90, 0.6, "sine", 38, release=0.35, vol=0.7), tone(180, 0.3, "saw", 60, release=0.12, vol=0.3),
                        noise(0.4, 0.15, 0.6, 0.35), noise(0.12, 0.04, 0.4, 0.8), offsets=[0, 0, 0, 0.01]))
    save("death", mix(tone(330, 0.5, "saw", 80, release=0.25, vol=0.3), noise(0.5, 0.2, 0.25, 0.85)))
    save("spell", mix(*[tone(f, 0.45, "sine", f * 1.5, attack=0.02, release=0.2, vol=0.2) for f in (440, 554, 659, 880)],
                      offsets=[0, 0.04, 0.08, 0.12]))
    save("hero_power", mix(tone(392, 0.35, "tri", 784, release=0.15, vol=0.4), noise(0.3, 0.1, 0.15, 0.9)))
    save("turn_start", seq(tone(note("E5"), 0.12, "tri", vol=0.4), tone(note("A5"), 0.3, "tri", release=0.2, vol=0.4)))
    save("heal", mix(*[tone(note(n), 0.5, "sine", attack=0.03, release=0.25, vol=0.25) for n in ("C5", "E5", "G5", "C6")],
                     offsets=[0, 0.06, 0.12, 0.18]))
    save("armor", mix(tone(180, 0.3, "square", 170, release=0.1, vol=0.2), noise(0.3, 0.08, 0.3, 0.2)))
    save("equip", mix(tone(900, 0.35, "tri", 850, release=0.2, vol=0.3), tone(1350, 0.35, "sine", release=0.15, vol=0.15)))
    save("secret", mix(tone(note("B4"), 0.6, "sine", attack=0.05, release=0.3, vol=0.3),
                       tone(note("F5"), 0.6, "sine", attack=0.05, release=0.3, vol=0.25), offsets=[0, 0.15]))
    save("freeze", mix(noise(0.5, 0.25, 0.25, 0.0), tone(2000, 0.5, "sine", 3000, release=0.2, vol=0.12)))
    save("shield", tone(1500, 0.3, "tri", 600, release=0.12, vol=0.35))
    save("victory", seq(*[tone(note(n), d, "square", release=d * 0.8, vol=0.25) for n, d in
                          (("C5", 0.15), ("E5", 0.15), ("G5", 0.15), ("C6", 0.6))]))
    save("defeat", seq(*[tone(note(n), d, "tri", release=d * 0.8, vol=0.3) for n, d in
                         (("G4", 0.3), ("E4", 0.3), ("C4", 0.3), ("C3", 0.9))]))
    # Music: 60-90 s songs (intro, A, B, bridge, A with ornaments, ending that leads back).
    save("menu", song(67, "major", 60 / 108, "waltz", MENU, 1))
    save("battle_1", song(74, "minor", 60 / 126, "four", BATTLE_1, 2))
    save("battle_2", song(76, "minor", 60 / 112, "gallop", BATTLE_2, 3))
    save("battle_3", song(69, "dorian", 0.2, "jig", BATTLE_3, 4))


if __name__ == "__main__":
    build()
    for f in sorted(os.listdir(OUT)):
        if f.endswith(".wav"):
            print(f, os.path.getsize(os.path.join(OUT, f)))
