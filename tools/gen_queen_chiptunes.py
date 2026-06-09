#!/usr/bin/env python3
"""Synthesize the Queen's sung phrases as candy chip-tune melodies.

ElevenLabs VO can't perform a *specific* melody, so the duel's sung phrases
(the contours the player traces back) are chip-tunes instead: each note's
pitch follows the contour's y exactly (screen-up = higher pitch), so what you
HEAR is what you TRACE. Spoken taunts stay ElevenLabs VO.

SOURCE OF TRUTH — the contours mirror QueenDuelState.PHRASES in
godot/scripts/queen_duel_state.gd (keep in sync by hand; a GUT test isn't
worth the coupling for 3 short arrays).

Pure-stdlib synth (square lead + soft triangle sub, exp decay) -> wav ->
ffmpeg -> mp3 + Godot .import sidecar (md5 = md5(res-path), the VO pattern).

Run: python3 tools/gen_queen_chiptunes.py
Output: godot/assets/audio/characters/queen_phrase_<n>.mp3
Played by level_3d.gd on the duel's phrase_start (slug queen_phrase_<i%3>)
and in the Papageno tutorial rounds.
"""
import hashlib
import math
import struct
import subprocess
import wave
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT_DIR = ROOT / "godot" / "assets" / "audio" / "characters"
SR = 44100

# QueenDuelState.PHRASES (y: 0 = top of screen = HIGH pitch, 3 = low).
PHRASES = [
    [(0, 2), (1, 0), (2, 0), (3, 2)],                       # gentle arc
    [(0, 3), (1, 2), (2, 1), (3, 0)],                       # rising run
    [(0, 3), (1, 0), (2, 3), (3, 0), (4, 3), (5, 0)],       # staccato zig-zag
]
# y -> frequency: a C-major arpeggio reads instantly as "candy music-box".
Y_TO_HZ = {0: 1046.50, 1: 783.99, 2: 659.25, 3: 523.25}  # C6 G5 E5 C5
PHRASE_SPAN = 1.4   # seconds of melody inside the 1.6s SING_T window


def note(freq: float, dur: float, staccato: bool) -> list:
    n = int(SR * dur)
    gate = int(n * (0.55 if staccato else 0.92))  # silence tail between notes
    out = []
    for i in range(n):
        if i >= gate:
            out.append(0.0)
            continue
        t = i / SR
        env = math.exp(-t * (9.0 if staccato else 4.5))
        # square lead (chip) + quiet triangle one octave down (body)
        sq = 1.0 if math.sin(2 * math.pi * freq * t) >= 0 else -1.0
        tri = 2.0 / math.pi * math.asin(math.sin(math.pi * freq * t))
        out.append(env * (0.62 * sq + 0.30 * tri))
    return out


def render(idx: int, contour: list) -> None:
    staccato = len(contour) > 4
    dur = PHRASE_SPAN / len(contour)
    samples: list = []
    for (_x, y) in contour:
        samples += note(Y_TO_HZ[int(y)], dur, staccato)
    samples += [0.0] * int(SR * 0.15)  # release tail
    peak = max(abs(s) for s in samples)
    pcm = b"".join(struct.pack("<h", int(s / peak * 32000)) for s in samples)

    wav_path = Path("/tmp/queen_phrase_%d.wav" % idx)
    with wave.open(str(wav_path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm)
    mp3 = OUT_DIR / ("queen_phrase_%d.mp3" % idx)
    subprocess.run(["ffmpeg", "-y", "-i", str(wav_path), "-b:a", "128k",
                    str(mp3)], check=True, capture_output=True)
    write_import_sidecar(mp3)
    print("wrote %s (%d bytes, %d notes%s)" % (
        mp3.name, mp3.stat().st_size, len(contour),
        ", staccato" if staccato else ""))


def write_import_sidecar(mp3: Path) -> None:
    res_path = "res://assets/audio/characters/%s" % mp3.name
    md5 = hashlib.md5(res_path.encode()).hexdigest()
    sidecar = mp3.with_suffix(mp3.suffix + ".import")
    sidecar.write_text(
        "[remap]\n\n"
        'importer="mp3"\ntype="AudioStreamMP3"\n'
        'uid="uid://q%s"\n'
        'path="res://.godot/imported/%s-%s.mp3str"\n\n'
        "[deps]\n\n"
        'source_file="%s"\n'
        'dest_files=["res://.godot/imported/%s-%s.mp3str"]\n\n'
        "[params]\n\nloop=false\nloop_offset=0\nbpm=0\nbeat_count=0\nbar_beats=4\n"
        % (md5[:12], mp3.name, md5, res_path, mp3.name, md5))


if __name__ == "__main__":
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for i, c in enumerate(PHRASES):
        render(i, c)
    print("done: %d chip-tune phrases" % len(PHRASES))
