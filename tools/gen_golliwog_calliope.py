#!/usr/bin/env python3
"""Golliwog's Cakewalk (Debussy, 1908 — public domain) as a CALLIOPE carnival
arrangement for the Level-4 mountain pass.

CLEAN-ROOM NOTE DATA: every downloadable MIDI of this piece carries a
non-commercial or share-alike license, so this file is OUR OWN transcription/
arrangement written from the public-domain score — we own the arrangement
outright. Main strain faithful; inner voicings simplified into a carnival
oom-pah (tuba bass + reed-organ chords) under the calliope lead.

Render chain: note data -> MIDI (mido) -> fluidsynth + FluidR3_GM.sf2 (MIT
license) -> wav -> ogg. GM patches: 82 Calliope Lead, 20 Reed Organ, 58 Tuba.

Run: python3 tools/gen_golliwog_calliope.py
Out: godot/assets/audio/music/golliwogs_cakewalk_calliope.ogg (+ .import)
"""
import hashlib
import subprocess
from pathlib import Path

import mido

ROOT = Path(__file__).resolve().parents[1]
OUT_DIR = ROOT / "godot" / "assets" / "audio" / "music"
SF2 = "/usr/share/sounds/sf2/FluidR3_GM.sf2"
BPM = 104                      # allegro giusto cakewalk strut
TPB = 480                      # ticks per beat (quarter)
SIXT = TPB // 4                # a sixteenth

# ---- pitch helpers ----------------------------------------------------------
NOTE_BASE = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}
def p(name: str) -> int:
    """'Eb4' -> midi number."""
    letter = name[0]
    rest = name[1:]
    acc = 0
    while rest and rest[0] in "b#":
        acc += -1 if rest[0] == "b" else 1
        rest = rest[1:]
    return 12 * (int(rest) + 1) + NOTE_BASE[letter] + acc

# ---- chords for the oom-pah engine ------------------------------------------
CHORDS = {
    "Eb":  ("Eb2", ["Eb3", "G3", "Bb3"]),
    "Ab":  ("Ab2", ["Ab3", "C4", "Eb4"]),
    "Bb7": ("Bb2", ["Ab3", "Bb3", "D4", "F4"]),
    "Cm":  ("C3",  ["Eb3", "G3", "C4"]),
    "F7":  ("F2",  ["Eb3", "F3", "A3", "C4"]),
    "Gb":  ("Gb2", ["Gb3", "Bb3", "Db4"]),
    "Cb":  ("Cb3", ["Cb4", "Eb4", "Gb4"]),
    "Db7": ("Db3", ["Cb4", "Db4", "F4", "Ab4"]),
}

# ---- the piece ---------------------------------------------------------------
# Melody entries: (pitch_name or None=rest, start_16th, dur_16ths) per SECTION,
# with a per-section bar count and chord chart (one symbol per bar, 2/4 = 8
# sixteenths per bar).

# A strain (16 bars) — the famous syncopated theme. Grid: bar*8 + offset.
def a_strain():
    m = []
    def snap(bar, notes):
        """the cakewalk snap: 16th,16th,8th(syncope) starting on the bar."""
        b = bar * 8
        m.append((notes[0], b + 0, 1))
        m.append((notes[1], b + 1, 1))
        m.append((notes[2], b + 2, 2))
        if len(notes) > 3:
            m.append((notes[3], b + 4, 1))
            m.append((notes[4], b + 5, 1))
            m.append((notes[5], b + 6, 2))
    # phrase 1 (bars 0-3): the signature call
    snap(0, ["Eb4", "F4", "G4", "G4", "F4", "G4"])
    snap(1, ["Bb4", "G4", "Eb4"])
    m.append(("F4", 1 * 8 + 4, 2)); m.append(("G4", 1 * 8 + 6, 2))
    snap(2, ["Eb4", "F4", "G4", "G4", "F4", "G4"])
    m.append(("Bb4", 3 * 8 + 0, 2)); m.append(("Ab4", 3 * 8 + 2, 2))
    m.append(("G4", 3 * 8 + 4, 2)); m.append(("F4", 3 * 8 + 6, 2))
    # phrase 2 (bars 4-7): answer, stepping down
    snap(4, ["Ab4", "Bb4", "C5", "C5", "Bb4", "C5"])
    snap(5, ["Eb5", "C5", "Ab4"])
    m.append(("Bb4", 5 * 8 + 4, 2)); m.append(("C5", 5 * 8 + 6, 2))
    m.append(("Bb4", 6 * 8 + 0, 2)); m.append(("Ab4", 6 * 8 + 2, 2))
    m.append(("G4", 6 * 8 + 4, 2)); m.append(("F4", 6 * 8 + 6, 2))
    m.append(("Eb4", 7 * 8 + 0, 4))
    # phrase 3-4 (bars 8-15): repeat with the stomp ending
    snap(8, ["Eb4", "F4", "G4", "G4", "F4", "G4"])
    snap(9, ["Bb4", "G4", "Eb4"])
    m.append(("F4", 9 * 8 + 4, 2)); m.append(("G4", 9 * 8 + 6, 2))
    snap(10, ["Eb4", "F4", "G4", "G4", "F4", "G4"])
    m.append(("Bb4", 11 * 8 + 0, 2)); m.append(("Ab4", 11 * 8 + 2, 2))
    m.append(("G4", 11 * 8 + 4, 2)); m.append(("F4", 11 * 8 + 6, 2))
    snap(12, ["Ab4", "Bb4", "C5", "C5", "Bb4", "C5"])
    snap(13, ["Eb5", "C5", "Ab4"])
    m.append(("Bb4", 13 * 8 + 4, 2)); m.append(("G4", 13 * 8 + 6, 2))
    # the stomp: big off-beat chords
    m.append(("Eb5", 14 * 8 + 2, 2)); m.append(("Eb5", 14 * 8 + 6, 2))
    m.append(("Eb4", 15 * 8 + 0, 6))
    chords = ["Eb", "Eb", "Eb", "Bb7", "Ab", "Ab", "Bb7", "Eb",
              "Eb", "Eb", "Eb", "Bb7", "Ab", "F7", "Bb7", "Eb"]
    return m, chords, 16

# B strain (12 bars) — the chattering second idea.
def b_strain():
    m = []
    seq = ["G4", "Ab4", "G4", "F4", "Eb4", "F4", "G4", "Ab4"]
    for i, n in enumerate(seq):
        m.append((n, i, 1))
    m.append(("Bb4", 8 + 0, 2)); m.append(("G4", 8 + 2, 2)); m.append(("Eb4", 8 + 4, 4))
    seq2 = ["Ab4", "Bb4", "Ab4", "G4", "F4", "G4", "Ab4", "Bb4"]
    for i, n in enumerate(seq2):
        m.append((n, 2 * 8 + i, 1))
    m.append(("C5", 3 * 8 + 0, 2)); m.append(("Ab4", 3 * 8 + 2, 2)); m.append(("F4", 3 * 8 + 4, 4))
    # sequence up + cakewalk snap close (bars 4-11)
    for bar, root in [(4, "Bb4"), (5, "C5")]:
        b = bar * 8
        m.append((root, b + 0, 1)); m.append((root, b + 1, 1))
        m.append((root, b + 2, 2)); m.append((root, b + 6, 2))
    m.append(("Eb5", 6 * 8 + 0, 1)); m.append(("D5", 6 * 8 + 1, 1))
    m.append(("C5", 6 * 8 + 2, 1)); m.append(("Bb4", 6 * 8 + 3, 1))
    m.append(("Ab4", 6 * 8 + 4, 1)); m.append(("G4", 6 * 8 + 5, 1))
    m.append(("F4", 6 * 8 + 6, 2))
    m.append(("Eb4", 7 * 8 + 0, 4))
    for bar in (8, 9, 10):
        b = bar * 8
        m.append(("G4", b + 0, 1)); m.append(("Ab4", b + 1, 1)); m.append(("G4", b + 2, 2))
        m.append(("Eb4", b + 4, 1)); m.append(("F4", b + 5, 1)); m.append(("G4", b + 6, 2))
    m.append(("Bb4", 11 * 8 + 0, 2)); m.append(("Eb4", 11 * 8 + 4, 4))
    chords = ["Eb", "Eb", "F7", "F7", "Bb7", "Bb7", "Bb7", "Eb",
              "Eb", "Cm", "Bb7", "Eb"]
    return m, chords, 12

# Middle section (12 bars) — the slow "with great emotion" parody, simplified:
# a yearning chromatic line over soft Gb-side chords, answered by the
# mocking little snaps.
def middle():
    m = []
    line = [("Gb4", 0, 6), ("F4", 6, 2), ("Ab4", 8, 6), ("Gb4", 14, 2),
            ("Bb4", 16, 8), ("Cb5", 24, 4), ("Bb4", 28, 4)]
    m += line
    # the giggle (mocking snap) bars 4-5
    for bar in (4, 5):
        b = bar * 8
        m.append(("Db5", b + 0, 1)); m.append(("Cb5", b + 1, 1)); m.append(("Bb4", b + 2, 2))
    # second phrase, sinking
    m.append(("Gb4", 6 * 8, 6)); m.append(("F4", 6 * 8 + 6, 2))
    m.append(("Eb4", 7 * 8, 8))
    m.append(("Db4", 8 * 8, 6)); m.append(("Eb4", 8 * 8 + 6, 2))
    m.append(("Gb4", 9 * 8, 8))
    for bar in (10, 11):
        b = bar * 8
        m.append(("Bb4", b + 0, 1)); m.append(("Ab4", b + 1, 1)); m.append(("Gb4", b + 2, 2))
    chords = ["Gb", "Gb", "Cb", "Gb", "Db7", "Db7", "Gb", "Cb",
              "Gb", "Gb", "Db7", "Gb"]
    return m, chords, 12

# Coda (6 bars): two big snaps + the cheeky last word.
def coda():
    m = []
    for bar in (0, 1):
        b = bar * 8
        m.append(("Eb4", b + 0, 1)); m.append(("F4", b + 1, 1)); m.append(("G4", b + 2, 2))
        m.append(("Bb4", b + 4, 1)); m.append(("G4", b + 5, 1)); m.append(("Eb4", b + 6, 2))
    m.append(("Eb5", 2 * 8 + 2, 2))
    m.append(("Eb4", 3 * 8 + 2, 2))
    m.append(("Bb3", 4 * 8 + 0, 2)); m.append(("Eb4", 4 * 8 + 4, 8))
    chords = ["Eb", "Eb", "Eb", "Eb", "Bb7", "Eb"]
    return m, chords, 6

def intro():
    # the bare strutting vamp
    m = []
    for bar in range(4):
        b = bar * 8
        m.append(("Bb3", b + 0, 1)); m.append(("Bb3", b + 1, 1)); m.append(("Bb3", b + 2, 2))
        m.append(("Bb3", b + 4, 2)); m.append(("Bb3", b + 6, 2))
    chords = ["Eb", "Eb", "Bb7", "Bb7"]
    return m, chords, 4

# ---- assembly ----------------------------------------------------------------
def main() -> None:
    sections = [intro(), a_strain(), b_strain(), a_strain(), middle(), a_strain(), coda()]
    mid = mido.MidiFile(ticks_per_beat=TPB)
    tempo = mido.bpm2tempo(BPM)

    lead = mido.MidiTrack(); mid.tracks.append(lead)
    lead.append(mido.MetaMessage("set_tempo", tempo=tempo, time=0))
    lead.append(mido.Message("program_change", channel=0, program=82, time=0))   # Calliope Lead
    organ = mido.MidiTrack(); mid.tracks.append(organ)
    organ.append(mido.Message("program_change", channel=1, program=20, time=0))  # Reed Organ
    tuba = mido.MidiTrack(); mid.tracks.append(tuba)
    tuba.append(mido.Message("program_change", channel=2, program=58, time=0))   # Tuba

    lead_ev: list = []
    organ_ev: list = []
    tuba_ev: list = []
    bar0 = 0
    for melody, chords, nbars in sections:
        soft = chords[0] in ("Gb", "Cb", "Db7")   # the middle section plays gentler
        vel_m = 78 if soft else 96
        for (note, start, dur) in melody:
            if note is None:
                continue
            t0 = (bar0 * 8 + start) * SIXT
            lead_ev.append((t0, "on", p(note), vel_m))
            lead_ev.append((t0 + dur * SIXT - 8, "off", p(note), 0))
        for i, sym in enumerate(chords):
            bass, chord = CHORDS[sym]
            b = (bar0 + i) * 8 * SIXT
            vb = 64 if soft else 88
            vc = 48 if soft else 66
            # oom (beat 1) — tuba
            tuba_ev.append((b, "on", p(bass), vb))
            tuba_ev.append((b + 3 * SIXT, "off", p(bass), 0))
            # pah (beat 2) — organ chord stab
            for cn in chord:
                organ_ev.append((b + 4 * SIXT, "on", p(cn), vc))
                organ_ev.append((b + 7 * SIXT, "off", p(cn), 0))
        bar0 += nbars

    for track, evs, ch in ((lead, lead_ev, 0), (organ, organ_ev, 1), (tuba, tuba_ev, 2)):
        evs.sort(key=lambda e: (e[0], 0 if e[1] == "off" else 1))
        t_prev = 0
        for (t, kind, note, vel) in evs:
            msg = "note_on" if kind == "on" else "note_off"
            track.append(mido.Message(msg, channel=ch, note=note, velocity=vel, time=t - t_prev))
            t_prev = t

    mid_path = Path("/tmp/golliwog_calliope.mid")
    mid.save(mid_path)
    print("MIDI written:", mid_path, f"({bar0} bars, ~{bar0 * 2 * 60 / BPM:.0f}s)")

    wav = Path("/tmp/golliwog_calliope.wav")
    subprocess.run(["fluidsynth", "-ni", "-g", "0.8", SF2, str(mid_path),
                    "-F", str(wav), "-r", "44100"], check=True, capture_output=True)
    ogg = OUT_DIR / "golliwogs_cakewalk_calliope.ogg"
    subprocess.run(["ffmpeg", "-y", "-i", str(wav), "-c:a", "libvorbis", "-q:a", "5",
                    str(ogg)], check=True, capture_output=True)
    res = f"res://assets/audio/music/{ogg.name}"
    md5 = hashlib.md5(res.encode()).hexdigest()
    ogg.with_suffix(".ogg.import").write_text(
        '[remap]\n\nimporter="oggvorbisstr"\ntype="AudioStreamOggVorbis"\n'
        f'uid="uid://m{md5[:12]}"\npath="res://.godot/imported/{ogg.name}-{md5}.oggvorbisstr"\n\n'
        '[deps]\n\n'
        f'source_file="{res}"\ndest_files=["res://.godot/imported/{ogg.name}-{md5}.oggvorbisstr"]\n\n'
        '[params]\n\nloop=false\nloop_offset=0\nbpm=0\nbeat_count=0\nbar_beats=4\n')
    print("OGG:", ogg, ogg.stat().st_size, "bytes")

if __name__ == "__main__":
    main()
