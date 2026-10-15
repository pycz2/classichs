#!/usr/bin/env python3
"""Synthesizes the Neonfall pack's sounds and synthwave music (pure Python, reusing the
oscillators, envelopes and reverb of tools/gen_audio.py), then encodes them to Ogg Vorbis
with ffmpeg.

Usage: python3 tools/neon_audio.py [--only name ...]
Result: packs/neon/sounds/default/<event>.ogg (the names game/sound.gd plays) and
packs/neon/music/default/{menu,battle_1,battle_2}.ogg (seamless loops). Deterministic.
"""
import math
import os
import random
import struct
import subprocess
import sys
import tempfile
import wave

sys.path.insert(0, os.path.dirname(__file__))
import gen_audio as ga  # noqa: E402

R = ga.RATE = 32000  # gen_audio's helpers read its RATE at call time
ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), ".."))
SOUNDS = os.path.join(ROOT, "packs", "neon", "sounds", "default")
MUSIC = os.path.join(ROOT, "packs", "neon", "music", "default")
tone, noise, mix, seq, note, lowpass = ga.tone, ga.noise, ga.mix, ga.seq, ga.note, ga.lowpass
rng = random.Random(2077)


def hp(x, cut):
    lo = lowpass(x, cut)
    return [a - b for a, b in zip(x, lo)]


def crush(x, levels=12, hold=3):
    """Bit and sample-rate reduction: the lo-fi digital edge."""
    out, last = [], 0.0
    for i, v in enumerate(x):
        if i % hold == 0:
            last = round(v * levels) / levels
        out.append(last)
    return out


def drive(x, k=2.5):
    return [math.tanh(k * v) / math.tanh(k) for v in x]


def echo(x, delay, fb=0.35, mixv=0.4):
    wet = ga.comb(x + [0.0] * int(delay * R * 4), delay, fb)
    return [a + mixv * (b - a) for a, b in zip(x + [0.0] * int(delay * R * 4), wet)]


def fm(f, dur, ratio=2.0, index=3.0, release=0.2, attack=0.005, vol=0.4, f1=None):
    """Two-operator FM: a glassy digital bell."""
    n = int(R * dur)
    e = ga.env(n, attack, release)
    f1 = f if f1 is None else f1
    out, pc, pm = [], 0.0, 0.0
    for i in range(n):
        ff = f + (f1 - f) * i / n
        pm += ff * ratio / R
        pc += ff / R
        out.append(math.sin(2 * math.pi * pc + index * e[i] * math.sin(2 * math.pi * pm)) * e[i] * vol)
    return out


def write_ogg(path, samples, quality=4):
    peak = max(1e-9, max(abs(s) for s in samples))
    scale = 0.9 / peak if peak > 0.9 else 1.0
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as f:
        tmp = f.name
    with wave.open(tmp, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(R)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, s * scale)) * 32767)) for s in samples))
    os.makedirs(os.path.dirname(path), exist_ok=True)
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", tmp, "-c:a", "libvorbis", "-q:a", str(quality), path], check=True)
    os.remove(tmp)


# ---------------------------------------------------------------------------- sounds

def sounds():
    s = {}
    s["click"] = mix(tone(2400, 0.03, "square", release=0.008, vol=0.15), tone(4800, 0.02, "sine", release=0.006, vol=0.1))
    s["play_card"] = mix(hp(noise(0.18, 0.07, 0.35, 0.3), 1500),
                         crush(tone(330, 0.16, "saw", 990, release=0.06, vol=0.25), 10, 2), offsets=[0, 0.02])
    s["draw"] = mix(lowpass(hp(noise(0.14, 0.05, 0.3, 0.0), 2500), 7000), fm(1320, 0.06, 2, 1, 0.03, vol=0.12), offsets=[0, 0.05])
    s["attack"] = drive(mix(tone(220, 0.28, "saw", 45, release=0.1, vol=0.5), noise(0.2, 0.05, 0.5, 0.5),
                            tone(60, 0.3, "sine", 40, release=0.15, vol=0.6)), 2.0)
    s["damage"] = crush(mix(noise(0.16, 0.05, 0.6, 0.4), tone(400, 0.14, "square", 80, release=0.05, vol=0.3)), 8, 4)
    s["trigger"] = seq(fm(1568, 0.07, 3, 2, 0.04, vol=0.25), fm(2093, 0.16, 3, 2, 0.08, vol=0.25))
    s["hit_big"] = drive(mix(tone(80, 0.8, "sine", 30, release=0.45, vol=0.8), tone(160, 0.35, "saw", 50, release=0.12, vol=0.35),
                             crush(noise(0.5, 0.18, 0.6, 0.3), 6, 5), offsets=[0, 0, 0.01]), 3.0)
    s["death"] = mix(crush(seq(*[tone(f, 0.07, "square", f * 0.8, release=0.04, vol=0.25) for f in (880, 660, 494, 370, 277)]), 6, 6),
                     lowpass(noise(0.6, 0.25, 0.25, 0.0), 3000), offsets=[0, 0.1])
    s["spell"] = echo(mix(*[fm(ga.note(n), 0.35, 2, 2.5, 0.2, attack=0.01, vol=0.18) for n in ("A4", "E5", "A5", "C6")],
                          hp(noise(0.5, 0.25, 0.12, 0.0), 4000), offsets=[0, 0.05, 0.1, 0.15, 0]), 0.09, 0.3, 0.35)
    s["hero_power"] = mix(tone(110, 0.5, "saw", 880, attack=0.02, release=0.25, vol=0.3),
                          tone(111, 0.5, "saw", 886, attack=0.02, release=0.25, vol=0.3), hp(noise(0.45, 0.2, 0.15, 0.0), 3000))
    s["turn_start"] = echo(seq(fm(note("E5"), 0.12, 1, 1.5, 0.08, vol=0.3), fm(note("B5"), 0.35, 1, 1.5, 0.25, vol=0.3)), 0.14, 0.35, 0.4)
    s["heal"] = echo(mix(*[tone(note(n), 0.6, "sine", attack=0.04, release=0.3, vol=0.2) for n in ("C5", "G5", "C6", "E6")]
                         + [tone(note(n) * 1.004, 0.6, "tri", attack=0.04, release=0.3, vol=0.1) for n in ("C5", "G5")],
                         offsets=[0, 0.07, 0.14, 0.21, 0, 0.07]), 0.12, 0.3, 0.3)
    s["armor"] = mix(*[tone(f, 0.4, "sine", attack=0.001, release=0.15, vol=0.18) for f in (523, 1197, 1871, 2793)],
                     noise(0.08, 0.02, 0.4, 0.2))
    s["equip"] = seq(mix(noise(0.06, 0.02, 0.5, 0.3), tone(140, 0.08, "square", 90, release=0.03, vol=0.3)),
                     tone(300, 0.35, "saw", 1200, attack=0.05, release=0.15, vol=0.15))
    s["secret"] = echo(mix(tone(note("D4"), 0.8, "saw", attack=0.08, release=0.4, vol=0.15),
                           tone(note("D4") * 1.01, 0.8, "saw", attack=0.08, release=0.4, vol=0.15),
                           tone(note("G#4"), 0.8, "sine", attack=0.08, release=0.4, vol=0.2)), 0.2, 0.35, 0.35)
    s["freeze"] = mix(crush(hp(noise(0.5, 0.2, 0.4, 0.0), 2500), 5, 3), tone(3000, 0.5, "sine", 4200, release=0.2, vol=0.1))
    s["shield"] = mix(fm(1760, 0.4, 1.5, 4, 0.15, vol=0.25, f1=440), hp(noise(0.3, 0.1, 0.15, 0.0), 5000))
    s["victory"] = echo(seq(*[mix(tone(note(n), d, "saw", release=d * 0.7, vol=0.18), tone(note(n) * 1.006, d, "saw", release=d * 0.7, vol=0.18),
                                  tone(note(n) / 2, d, "square", release=d * 0.7, vol=0.1))
                              for n, d in (("A4", 0.14), ("C#5", 0.14), ("E5", 0.14), ("A5", 0.7))]), 0.15, 0.3, 0.35)
    s["defeat"] = seq(*[mix(tone(note(n), d, "saw", note(n) * 0.97, release=d * 0.8, vol=0.2),
                            tone(note(n) * 1.01, d, "saw", note(n) * 0.95, release=d * 0.8, vol=0.2))
                        for n, d in (("E4", 0.3), ("C4", 0.3), ("A3", 0.3), ("E3", 1.0))])
    loud = {"click": -24, "draw": -24, "hit_big": -14, "attack": -16}  # mean level in dB, as the Classic set (about -19)
    out = {}
    for k, x in s.items():
        x = lowpass(x, 9000)
        rms = math.sqrt(sum(v * v for v in x) / len(x))
        g = min(10 ** (loud.get(k, -19) / 20) / rms, 0.9 / max(abs(v) for v in x))
        out[k] = [v * g for v in x]
    return out


# ---------------------------------------------------------------------------- music
# Synthwave: four-on-the-floor drums, an eighth-note saw bass, a detuned saw pad ducked
# by the kick, a square arpeggio with a dotted echo and a saw lead on generated motifs.

def saw_note(f, dur, detune=0.0, attack=0.01, release=0.1, vol=0.3, kind="saw"):
    n = int(R * dur)
    a, r = max(1, int(R * attack)), max(1, int(R * release))
    out, p1, p2 = [], rng.random(), rng.random()
    f2 = f * (1 + detune)
    for i in range(n):
        p1 += f / R
        p2 += f2 / R
        e = min(1.0, i / a) * min(1.0, (n - i) / r)
        v = ga.osc(kind, p1) + (ga.osc(kind, p2) if detune else 0.0)
        out.append(v * e * vol)
    return out


def kick():
    return mix(tone(140, 0.32, "sine", 42, attack=0.001, release=0.16, vol=0.9), tone(1000, 0.01, "square", release=0.004, vol=0.15))


def snare():
    return mix(hp(noise(0.25, 0.1, 0.5, 0.0), 1200), tone(190, 0.12, "tri", 150, release=0.05, vol=0.35))


def hat(open_=False):
    return hp(noise(0.2 if open_ else 0.05, 0.08 if open_ else 0.015, 0.25, 0.0), 7000)


CHORD = {"m": (0, 3, 7), "M": (0, 4, 7), "s": (0, 5, 7)}


def chord(name):
    """'A:m' -> (root pitch class, intervals)."""
    root, q = name.split(":")
    return ga.PC[root[0]] + (1 if "#" in root else 0) - (1 if root.endswith("b") else 0), CHORD[q]


def song(bpm, key, prog, form, seed):
    """prog: 4 chord names, one per bar; form: list of (bars, layers) sections."""
    r = random.Random(seed)
    beat = 60 / bpm
    bars = sum(b for b, _ in form)
    n = int(round(bars * 4 * beat * R))
    bus = {k: [0.0] * (n + R * 2) for k in ("drums", "bass", "pad", "arp", "lead")}

    def put(b, t, x, g=1.0):
        s = int(t * R)
        buf = bus[b]
        for i, v in enumerate(x):
            buf[s + i] += v * g

    # two lead motifs (8 eighths per bar, 4 bars): chord tones on strong beats, scale steps between
    scale = ga.SCALES["minor"]

    def motif():
        out = []
        for bar in range(4):
            pc, iv = chord(prog[bar])
            tones_ = [pc + i for i in iv]
            rhythm = r.choice([[1, 0, 1, 1, 0, 1, 1, 0], [1, 0, 0, 1, 0, 0, 1, 0], [1, 1, 0, 1, 1, 0, 1, 1], [1, 0, 0, 0, 1, 0, 1, 0]])
            for k, on in enumerate(rhythm):
                if not on:
                    out.append(None)
                    continue
                if k % 4 == 0:
                    p = r.choice(tones_)
                else:
                    p = key + scale[r.randrange(7)]
                out.append(p)
        return out

    motifs = [motif(), motif()]
    t, bar_i = 0.0, 0
    for bars_n, layers in form:
        for b in range(bars_n):
            pc, iv = chord(prog[bar_i % 4])
            root = 36 + (pc - 36) % 12  # C2..B2
            if "drums" in layers:
                for k in range(4):
                    put("drums", t + k * beat, kick(), 0.9)
                    put("drums", t + k * beat + beat / 2, hat(k == 3 and b % 2), 0.3)
                    if k in (1, 3):
                        put("drums", t + k * beat, snare(), 0.6)
                if "fill" in layers and b == bars_n - 1:
                    for k in range(4):
                        put("drums", t + 3 * beat + k * beat / 4, snare(), 0.25 + 0.1 * k)
            if "bass" in layers:
                for k in range(8):
                    f = ga.hz(root + (12 if k % 4 == 3 else 0))
                    put("bass", t + k * beat / 2, saw_note(f, beat / 2 * 0.9, 0.0, 0.005, 0.05, 0.35), 1.0)
                    put("bass", t + k * beat / 2, tone(f / 2, beat / 2 * 0.9, "sine", release=0.2, vol=0.35))
            if "pad" in layers:
                for i in iv:
                    f = ga.hz(60 + (pc + i - 60) % 12 + (12 if pc + i < 3 else 0))
                    put("pad", t, saw_note(f, 4 * beat, 0.008, 0.25, 0.4, 0.09), 1.0)
            if "arp" in layers:
                seq_ = [pc + i for i in iv] + [pc + iv[1] + 12]
                for k in range(16):
                    p = 72 + (seq_[k % 4] - 72) % 12 + (12 if k % 8 >= 4 else 0)
                    put("arp", t + k * beat / 4, saw_note(ga.hz(p), beat / 4 * 0.8, 0.0, 0.002, 0.04, 0.12, "square"))
            if "lead" in layers:
                m = motifs[(bar_i // 4) % 2]
                for k in range(8):
                    p = m[(bar_i % 4) * 8 + k]
                    if p is not None:
                        f = ga.hz(72 + (p - 72) % 12)
                        put("lead", t + k * beat / 2, saw_note(f, beat / 2 * 0.95, 0.004, 0.01, 0.08, 0.16), 1.0)
            t += 4 * beat
            bar_i += 1

    def fold(buf):  # tails past the end ring on over the start, so the loop has no seam
        out = buf[:n]
        for i, v in enumerate(buf[n:]):
            out[i % n] += v
        return out

    duck = [1 - 0.55 * math.exp(-((i / R) % beat) / 0.11) for i in range(n)]
    drums = fold(bus["drums"])
    bass = [v * (0.6 + 0.4 * d) for v, d in zip(ga.looped(lambda x: lowpass(lowpass(x, 700), 900), fold(bus["bass"]), 0.5), duck)]
    pad = [v * d for v, d in zip(ga.looped(lambda x: lowpass(lowpass(x, 1600), 2400), fold(bus["pad"]), 1.0), duck)]
    arp = ga.looped(lambda x: echo(lowpass(x, 3500), beat * 0.75, 0.4, 0.45)[:len(x)], fold(bus["arp"]), 2.0)
    lead = ga.looped(lambda x: echo(lowpass(x, 3200), beat * 0.75, 0.3, 0.3)[:len(x)], fold(bus["lead"]), 2.0)
    dry = [a + b + c + d + e for a, b, c, d, e in zip(drums, bass, pad, arp, lead)]
    wet = ga.looped(lambda x: ga.reverb(lowpass(hp(x, 300), 5000)), [p + a + l + 0.3 * dr for p, a, l, dr in zip(pad, arp, lead, drums)])
    out = [a + 0.18 * b for a, b in zip(dry, wet)]
    rms = math.sqrt(sum(v * v for v in out) / n)
    g = min(10 ** (-17 / 20) / rms, 0.95 / max(abs(v) for v in out))  # about the Classic music level
    out = [v * g for v in out]
    edge = int(R * 0.004)
    for k in range(edge):
        out[k] *= k / edge
        out[-1 - k] *= k / edge
    return out


D, B, P, A, L, F = "drums", "bass", "pad", "arp", "lead", "fill"
TRACKS = {
    # A minor, 96 bpm: a slow night drive above the city
    "menu": (96, 57, ["A:m", "F:M", "C:M", "G:M"],
             [(4, {P, A}), (8, {P, A, B}), (8, {P, A, B, D, L}), (4, {P, A}), (8, {P, A, B, D, L, F})], 11),
    # E minor, 118 bpm: street fight
    "battle_1": (118, 64, ["E:m", "C:M", "G:M", "D:M"],
                 [(4, {P, A, D}), (8, {P, A, B, D}), (8, {P, A, B, D, L, F}), (4, {P, B, D}), (8, {P, A, B, D, L, F})], 12),
    # D minor, 126 bpm: corporate pursuit
    "battle_2": (126, 62, ["D:m", "A#:M", "F:M", "C:M"],
                 [(4, {P, B}), (8, {P, A, B, D}), (8, {P, A, B, D, L}), (4, {A, D}), (8, {P, A, B, D, L, F}), (4, {P, A, B, D})], 13),
}


def main():
    only = sys.argv[sys.argv.index("--only") + 1:] if "--only" in sys.argv else None
    for name, x in sounds().items():
        if not only or name in only:
            write_ogg(os.path.join(SOUNDS, name + ".ogg"), x)
    for name, (bpm, key, prog, form, seed) in TRACKS.items():
        if not only or name in only:
            write_ogg(os.path.join(MUSIC, name + ".ogg"), song(bpm, key, prog, form, seed), 3)
            print(name, "done", flush=True)
    for d in (SOUNDS, MUSIC):
        for f in sorted(os.listdir(d)):
            print(os.path.relpath(os.path.join(d, f), ROOT), os.path.getsize(os.path.join(d, f)))


if __name__ == "__main__":
    main()
