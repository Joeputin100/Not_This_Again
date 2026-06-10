#!/usr/bin/env python3
"""Golliwogg's Cake Walk (Debussy, Children's Corner VI, 1908 — public domain)
as a CALLIOPE carnival arrangement for the Level-4 mountain pass.

CLEAN-ROOM NOTE DATA: transcribed by eye + notehead measurement from the
IMSLP #252526 scan of the 1908 Durand first edition (pages 26-30), which is
public domain. Every downloadable MIDI of this piece carries a non-commercial
or share-alike license, so this file is OUR OWN transcription/arrangement —
we own it outright. The melody follows the engraving (Allegro giusto, E-flat
major, 2/4 — including the famous accented C-flats of the opening cascade and
the low-register cakewalk theme); inner voicings are simplified into a
carnival oom-pah (tuba bass + reed-organ chords) under the calliope lead.

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
# "NC" = tacet bar (no oom-pah).
CHORDS = {
    "Eb":   ("Eb2", ["Eb3", "G3", "Bb3"]),
    "Eb5":  ("Eb2", ["Eb3", "Bb3"]),          # the open-fifth vamp (as engraved)
    "Eb7":  ("Eb2", ["Eb3", "G3", "Db4"]),    # the bluesy flat-7 colour
    "Ab":   ("Ab2", ["Ab3", "C4", "Eb4"]),
    "Bb7":  ("Bb2", ["Ab3", "Bb3", "D4", "F4"]),
    "Cm":   ("C3",  ["Eb3", "G3", "C4"]),
    "F7":   ("F2",  ["Eb3", "F3", "A3", "C4"]),
    "Gb":   ("Gb2", ["Gb3", "Bb3", "Db4"]),
    "Gb5":  ("Gb2", ["Gb3", "Db4"]),          # middle-section pedal fifth
    "Cb":   ("Cb3", ["Cb4", "Eb4", "Gb4"]),
    "Db7":  ("Db3", ["Cb4", "Db4", "F4", "Ab4"]),
}

# ---- the piece ---------------------------------------------------------------
# Melody entries: (pitch_name or None=rest, start_16th, dur_16ths) per SECTION,
# with a per-section bar count and chord chart (one symbol per bar, 2/4 = 8
# sixteenths per bar). Several entries may overlap in time (dyads/stabs).

def snap(m, bar, n1, n2, n3):
    """The cakewalk snap: 16th, 16th, 8th starting on the bar."""
    b = bar * 8
    m.append((n1, b + 0, 1)); m.append((n2, b + 1, 1)); m.append((n3, b + 2, 2))

# Intro (Durand mm.1-5): the f octave cascade — Bb-Ab-Bb,F-Bb / then the
# Ab-F-Eb..Cb figure falling through three octaves, sff stab, one silent bar.
def intro():
    m = []
    # m1: Bb5(>) Ab5 Bb5 (snap), F5 Bb5 (8ths)
    snap(m, 0, "Bb5", "Ab5", "Bb5")
    m.append(("F5", 4, 2)); m.append(("Bb5", 6, 2))
    # m2: Ab5 F5 Eb5 (snap), Cb5 (accented quarter — the famous C-flat)
    snap(m, 1, "Ab5", "F5", "Eb5")
    m.append(("Cb5", 8 + 4, 4))
    # m3: same an octave down, Cb4 marcato
    snap(m, 2, "Ab4", "F4", "Eb4")
    m.append(("Cb4", 16 + 4, 4))
    # m4: 16th-rest, Ab3 F3 Eb3 16ths; Cb3(>) 8th + sff Eb stab on the off-8th
    b = 3 * 8
    m.append(("Ab3", b + 1, 1)); m.append(("F3", b + 2, 1)); m.append(("Eb3", b + 3, 1))
    m.append(("Cb3", b + 4, 2))
    for n in ("Eb3", "Bb3", "Eb4"):          # the sff crash chord
        m.append((n, b + 6, 2))
    # m5: silence (grand pause before the strut)
    chords = ["NC", "NC", "NC", "NC", "NC"]
    return m, chords, 5

# Vamp (mm.6-9): the strutting open-fifth oom-pah; RH stabs on the off-8ths,
# with the 16th-16th kick closing bars 1 and 3 (as engraved, f< on the kick).
def vamp():
    m = []
    for bar in range(4):
        b = bar * 8
        stab = [("Bb3", 1), ("Eb4", 1)]      # RH dyad Eb4/Bb3
        for n, _ in stab:
            m.append((n, b + 2, 2))
        if bar in (0, 2):                    # ...pah pa-pah (16,16)
            for n, _ in stab:
                m.append((n, b + 6, 1)); m.append((n, b + 7, 1))
        else:
            for n, _ in stab:
                m.append((n, b + 6, 2))
    chords = ["Eb5", "Eb5", "Eb5", "Eb5"]
    return m, chords, 4

# A strain (mm.10-25, "très net et très sec"): the cakewalk theme proper.
def a_strain():
    m = []
    # phrase 1 (mid register) — m10: Bb4 Ab4 Bb4 (snap), F4 Bb4 (stacc 8ths)
    snap(m, 0, "Bb4", "Ab4", "Bb4")
    m.append(("F4", 4, 2)); m.append(("Bb4", 6, 2))
    # m11: Ab4 F4 Eb4 (snap), C4 (8th)
    snap(m, 1, "Ab4", "F4", "Eb4")
    m.append(("C4", 8 + 4, 2))
    # m12: C4 half (the cheeky sixth-degree cadence, marcato)
    m.append(("C4", 2 * 8, 8))
    # phrase 2 (low register, with the C-flat sting) — m13/m14
    for bar in (3, 4):
        snap(m, bar, "Bb3", "Ab3", "Bb3")
        m.append(("Cb4", bar * 8 + 4, 2)); m.append(("Ab3", bar * 8 + 6, 2))
    # m15: descending run Bb3 G3 F3 Eb3 (16ths), D3 quarter
    b = 5 * 8
    for i, n in enumerate(["Bb3", "G3", "F3", "Eb3"]):
        m.append((n, b + i, 1))
    m.append(("D3", b + 4, 4))
    # m16: bass walk C3 G2 C3 D3 (8ths) back up to the theme
    b = 6 * 8
    for i, n in enumerate(["C3", "G2", "C3", "D3"]):
        m.append((n, b + i * 2, 2))
    # m17/m18: theme statement again (mid register)
    snap(m, 7, "Bb4", "Ab4", "Bb4")
    m.append(("F4", 7 * 8 + 4, 2)); m.append(("Bb4", 7 * 8 + 6, 2))
    snap(m, 8, "Ab4", "F4", "Eb4")
    m.append(("C4", 8 * 8 + 4, 2)); m.append(("Eb4", 8 * 8 + 6, 2))
    # m19: Bb3 Bb3 Cb4 Bb3 (16ths) + the banged Eb/Bb chord answer
    b = 9 * 8
    for i, n in enumerate(["Bb3", "Bb3", "Cb4", "Bb3"]):
        m.append((n, b + i, 1))
    for n in ("Eb4", "Bb4"):
        m.append((n, b + 4, 4))
    # m20: held D4 (marcato half)
    m.append(("D4", 10 * 8, 8))
    # m21: rising kick D4 Eb4 F4 Eb4 (16ths), G4 F4 (8ths)
    b = 11 * 8
    for i, n in enumerate(["D4", "Eb4", "F4", "Eb4"]):
        m.append((n, b + i, 1))
    m.append(("G4", b + 4, 2)); m.append(("F4", b + 6, 2))
    # m22: F4 G4 F4 G4 (16ths), then the stomp dyad G4/D5
    b = 12 * 8
    for i, n in enumerate(["F4", "G4", "F4", "G4"]):
        m.append((n, b + i, 1))
    for n in ("G4", "D5"):
        m.append((n, b + 4, 2))
    for n in ("Bb4", "Eb5"):
        m.append((n, b + 6, 2))
    # m23: the ff banged chord (>>^), then off
    b = 13 * 8
    for n in ("Bb4", "Eb5", "G5"):
        m.append((n, b, 4))
    # m24/m25: p wind-down stabs (tenuto off-beat chords over the vamp)
    for bar in (14, 15):
        b = bar * 8
        for n in ("Bb3", "Eb4"):
            m.append((n, b + 2, 2)); m.append((n, b + 6, 2))
    chords = ["Eb", "Eb7", "Eb", "Eb", "Eb", "Eb", "Cm",
              "Eb", "Eb7", "Eb", "Bb7", "Ab", "Bb7", "Eb", "Eb5", "Eb5"]
    return m, chords, 16

# Middle (p.27 "Un peu moins vite" -> p.29, G-flat side): the swaying wah-wah
# grace chords, then the "p avec une grande émotion" Tristan-parody phrase
# (Cédez), harmony simplified to block chords.
def middle():
    m = []
    # m1-4: the wah vamp — grace 16th into an off-beat dyad stab
    for bar in range(4):
        b = bar * 8
        m.append(("F4", b + 1, 1))                       # grace lean
        m.append(("Gb4", b + 2, 2)); m.append(("Bb3", b + 2, 2))
        if bar % 2 == 1:
            m.append(("Gb4", b + 6, 2)); m.append(("Bb3", b + 6, 2))
    # m5-7: the yearning phrase: Ab3 pickup, long F4, chromatic F-E-Eb fall
    m.append(("Ab3", 4 * 8, 2)); m.append(("F4", 4 * 8 + 2, 6))
    m.append(("E4", 5 * 8, 2)); m.append(("Eb4", 5 * 8 + 2, 6))
    m.append(("Db4", 6 * 8, 8))
    # m8: wah answer (the mocking giggle)
    m.append(("F4", 7 * 8 + 1, 1))
    m.append(("Gb4", 7 * 8 + 2, 2)); m.append(("Bb3", 7 * 8 + 2, 2))
    # m9-11: phrase again, sinking further
    m.append(("Ab3", 8 * 8, 2)); m.append(("F4", 8 * 8 + 2, 6))
    m.append(("E4", 9 * 8, 2)); m.append(("Eb4", 9 * 8 + 2, 2)); m.append(("Db4", 9 * 8 + 4, 4))
    m.append(("Gb3", 10 * 8, 8))
    # m12: wah out
    m.append(("F4", 11 * 8 + 1, 1))
    m.append(("Gb4", 11 * 8 + 2, 2)); m.append(("Bb3", 11 * 8 + 2, 2))
    chords = ["Gb5", "Gb5", "Gb5", "Gb5", "Gb", "Cb", "Db7", "Gb5",
              "Gb", "Cb", "Db7", "Gb5"]
    return m, chords, 12

# Coda (p.30, last system): the intro cascade returns f, crashes ff, the vamp
# tiptoes back p, and two banged chords have the last word.
def coda():
    m = []
    # m1: Ab4 F4 Eb4 (snap), Cb4 quarter (the cascade, mid register)
    snap(m, 0, "Ab4", "F4", "Eb4")
    m.append(("Cb4", 4, 4))
    # m2: 16th-rest + Ab3 F3 Eb3, Cb3 8th + ff crash chord
    b = 8
    m.append(("Ab3", b + 1, 1)); m.append(("F3", b + 2, 1)); m.append(("Eb3", b + 3, 1))
    m.append(("Cb3", b + 4, 2))
    for n in ("Eb3", "Bb3", "Eb4"):
        m.append((n, b + 6, 2))
    # m3: p vamp echo stabs
    b = 16
    for n in ("Bb3", "Eb4"):
        m.append((n, b + 2, 2)); m.append((n, b + 6, 2))
    # m4: silence (wait for it...)
    # m5: p vamp echo again
    b = 32
    for n in ("Bb3", "Eb4"):
        m.append((n, b + 2, 2)); m.append((n, b + 6, 2))
    # m6: the last word — two ff Eb bangs
    b = 40
    for n in ("Eb3", "Bb3", "Eb4", "G4"):
        m.append((n, b, 2))
    for n in ("Eb3", "Bb3", "Eb4", "G4"):
        m.append((n, b + 4, 4))
    chords = ["NC", "NC", "Eb5", "NC", "Eb5", "Eb"]
    return m, chords, 6

# ---- assembly ----------------------------------------------------------------
def main() -> None:
    sections = [intro(), vamp(), a_strain(), middle(), a_strain(), coda()]
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
        soft = any(c.startswith("Gb") for c in chords)   # middle section plays gentler
        vel_m = 78 if soft else 96
        for (note, start, dur) in melody:
            if note is None:
                continue
            t0 = (bar0 * 8 + start) * SIXT
            lead_ev.append((t0, "on", p(note), vel_m))
            lead_ev.append((t0 + dur * SIXT - 8, "off", p(note), 0))
        for i, sym in enumerate(chords):
            if sym == "NC":
                continue
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
