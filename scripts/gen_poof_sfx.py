#!/usr/bin/env python3
"""Synthesize a soft cartoon "poof" for the Canard explosion easter egg
(iter 160) — Monsieur Canard comically bursts, then a fresh duck-head
springs from the cane.

Pure stdlib. A descending low "thump" mixed with noise, run through a
short moving-average low-pass so it lands as a soft "fwoomp" rather than
a harsh hiss, with a fast exponential decay. Deterministic (seeded), so
re-running produces the identical committed WAV.

Run: python3 scripts/gen_poof_sfx.py
"""
import math
import os
import random
import struct
import wave

SR = 44100
OUT = os.path.join(os.path.dirname(__file__), os.pardir,
                   "godot", "assets", "sfx", "poof.wav")


def main() -> None:
    random.seed(160)
    dur = 0.44
    n = int(SR * dur)
    raw = []
    for i in range(n):
        t = i / SR
        env = math.exp(-t * 8.5)
        noise = random.uniform(-1.0, 1.0)
        # descending low tone — the comedic "boomf"
        thump_f = 120.0 - 70.0 * (t / dur)
        thump = math.sin(2.0 * math.pi * thump_f * t)
        raw.append((noise * 0.68 + thump * 0.52) * env)

    # moving-average low-pass: turns the hiss into a soft poof
    k = 9
    buf = []
    acc = 0.0
    for i in range(n):
        acc += raw[i]
        if i >= k:
            acc -= raw[i - k]
        buf.append(acc / float(min(i + 1, k)))
    for i in range(88):                  # ~2ms fade-in, no click
        buf[i] *= i / 88.0

    peak = max((abs(x) for x in buf), default=1.0) or 1.0
    gain = 0.9 / peak
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
