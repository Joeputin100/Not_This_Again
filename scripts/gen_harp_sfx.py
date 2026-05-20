#!/usr/bin/env python3
"""Synthesize a gentle harp glissando for Professor Humbug's "thought"
interaction on the level selector (iter 159).

Pure stdlib — no sample library, no API. An ascending pentatonic
arpeggio of plucked strings (decaying sine + 2 harmonics), notes
overlapping so it reads as one dreamy shimmer. Output is committed as
godot/assets/sfx/harp_thought.wav so the build needs no external assets.

Run: python3 scripts/gen_harp_sfx.py
"""
import math
import os
import struct
import wave

SR = 44100
OUT = os.path.join(os.path.dirname(__file__), os.pardir,
                   "godot", "assets", "sfx", "harp_thought.wav")


def pluck(freq: float, dur: float) -> list[float]:
    """One plucked-string note: fundamental + 2 harmonics, exp decay."""
    n = int(SR * dur)
    out = []
    for i in range(n):
        t = i / SR
        env = math.exp(-t * 4.2)
        if i < 132:                       # ~3ms fade-in kills the click
            env *= i / 132.0
        v = (math.sin(2 * math.pi * freq * t)
             + 0.5 * math.sin(2 * math.pi * freq * 2 * t)
             + 0.22 * math.sin(2 * math.pi * freq * 3 * t))
        out.append(v * env / 1.72)
    return out


def main() -> None:
    # Ascending C-major pentatonic — consonant under any overlap.
    freqs = [392.0, 440.0, 523.25, 587.33, 659.25, 783.99, 880.0, 1046.5]
    step = 0.072                          # seconds between note onsets
    buf: list[float] = []
    for i, f in enumerate(freqs):
        note = pluck(f, 1.0)
        start = int(i * step * SR)
        while len(buf) < start + len(note):
            buf.append(0.0)
        for j, v in enumerate(note):
            buf[start + j] += v

    peak = max((abs(x) for x in buf), default=1.0) or 1.0
    gain = 0.86 / peak                    # headroom, no hard clipping
    with wave.open(OUT, "w") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        frames = bytearray()
        for x in buf:
            s = max(-1.0, min(1.0, x * gain))
            frames += struct.pack("<h", int(s * 32767))
        w.writeframes(bytes(frames))
    print("wrote %s  (%.2fs, %d frames)" % (OUT, len(buf) / SR, len(buf)))


if __name__ == "__main__":
    main()
