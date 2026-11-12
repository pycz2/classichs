#!/usr/bin/env python3
"""The client's own menu music (audio/shell/menu.wav, the source, and menu.opus, what the client plays): a calm
loop of soft pads and a few bell notes, of no game in particular (the main menu, the settings, the library, the
connections).
Built with tools/gen_audio.py's instruments; deterministic.

Usage: python3 tools/gen_shell_music.py
"""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import gen_audio as g  # noqa: E402

BAR = 4.0  # seconds a chord
CHORDS = [[50, 57, 61, 66], [47, 54, 57, 62], [43, 50, 54, 59], [45, 52, 57, 61]]  # Dmaj7 Bm7 Gmaj7 A
BELLS = [[74, 78, 81], [73, 78, 81], [71, 74, 78], [73, 76, 81]]  # an arpeggio over each chord


def build():
    n = int(g.RATE * BAR * len(CHORDS) * 2)
    out = [0.0] * n

    def put(at, samples, gain):
        k0 = int(at * g.RATE)
        for k, v in enumerate(samples):
            out[(k0 + k) % n] += v * gain  # tails wrap to the start: a seamless loop

    for rep in range(2):
        for i, chord in enumerate(CHORDS):
            t = (rep * len(CHORDS) + i) * BAR
            put(t, g.pad(chord, BAR, attack=1.2, release=1.6), 0.10)
            for j, m in enumerate(BELLS[i] if rep == 1 or i % 2 == 0 else BELLS[i][:1]):
                put(t + 0.5 + j * 1.1, g.pluck(m, 2.4, bright=0.35, t60=2.2), 0.22)
    wet = g.looped(lambda x: g.reverb(g.lowpass(x, 4000)), out)
    out = [0.45 * (a + 0.08 * b) for a, b in zip(out, wet)]  # about as loud as the games' menu music
    g.OUT = os.path.join(os.path.dirname(__file__), "..", "audio", "shell")
    g.save("menu", out)


if __name__ == "__main__":
    build()
