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


def chord_pad(notes, dur, vol=0.12):
    return mix(*[tone(note(n), dur, "tri", attack=0.3, release=dur, vol=vol) for n in notes])


def music(chords, bass, melody, beat, kind):
    """chords: list of note lists (one per bar, 4 beats); melody: list of (note or None, beats)."""
    bar = beat * 4
    pads = seq(*[chord_pad(c, bar) for c in chords])
    low = seq(*[seq(tone(note(b), beat * 2, "sine", release=beat, vol=0.3),
                    tone(note(b), beat * 2, "sine", release=beat, vol=0.22)) for b in bass])
    mel = []
    for n, beats in melody:
        mel += silence(beat * beats) if n is None else tone(note(n), beat * beats, kind, attack=0.01, release=beat * beats * 0.6, vol=0.22)
    return mix(pads, low, mel)


def build():
    save("click", tone(1200, 0.05, "square", release=0.015, vol=0.25))
    save("play_card", mix(noise(0.12, 0.05, 0.3, 0.6), tone(220, 0.2, "sine", 110, release=0.08, vol=0.5)))
    save("attack", mix(noise(0.25, 0.08, 0.5, 0.3), tone(160, 0.25, "saw", 60, release=0.1, vol=0.35)))
    save("damage", mix(noise(0.18, 0.06, 0.5, 0.5), tone(300, 0.15, "square", 90, release=0.05, vol=0.25)))
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
    # Music: loops of 8 bars. A calm tavern tune for the menu, a faster one for the match.
    save("menu", music(
        [["A3", "C4", "E4"], ["F3", "A3", "C4"], ["C4", "E4", "G4"], ["G3", "B3", "D4"]] * 2,
        ["A2", "F2", "C3", "G2"] * 2,
        [("E5", 1), ("D5", 0.5), ("C5", 0.5), ("A4", 2), ("C5", 1), ("A4", 1), ("F4", 2),
         ("G4", 1), ("C5", 1), ("E5", 2), ("D5", 1.5), ("B4", 0.5), ("G4", 2),
         ("A4", 1), ("C5", 1), ("E5", 1), ("A5", 1), ("G5", 1), ("F5", 1), ("C5", 2),
         ("E5", 1), ("G5", 1), ("C5", 2), ("B4", 2), ("D5", 1), (None, 1)],
        0.42, "tri"))
    save("battle", music(
        [["D4", "F4", "A4"], ["A#3", "D4", "F4"], ["C4", "E4", "G4"], ["A3", "C#4", "E4"]] * 2,
        ["D3", "A#2", "C3", "A2"] * 2,
        [("D5", 0.5), ("F5", 0.5), ("A5", 1), ("G5", 0.5), ("F5", 0.5), ("E5", 1),
         ("D5", 0.5), ("F5", 0.5), ("A#5", 1), ("A5", 1), ("F5", 1),
         ("E5", 0.5), ("G5", 0.5), ("C6", 1), ("A#5", 0.5), ("A5", 0.5), ("G5", 1),
         ("E5", 1), ("C#5", 1), ("E5", 1), ("A4", 1)] * 2,
        0.33, "square"))


if __name__ == "__main__":
    build()
    for f in sorted(os.listdir(OUT)):
        if f.endswith(".wav"):
            print(f, os.path.getsize(os.path.join(OUT, f)))
