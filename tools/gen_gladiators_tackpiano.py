#!/usr/bin/env python3
"""Entry of the Gladiators (Julius Fucik, 1897) as a TACK-PIANO circus
arrangement for the chicken-chase minigame.

CLEAN-ROOM NOTE DATA: transcribed by eye from the public-domain 1903 Carl
Fischer piano edition "Thunder and Blazes" (IMSLP #39293) — we own this
arrangement outright. Melody note-accurate from the engraving; the inner
accompaniment is simplified into an oom-pah (bass on beats 1+3, chord stab on
2+4) from the printed harmony.

Render chain: note data -> MIDI (mido) -> fluidsynth + FluidR3_GM.sf2 (MIT
license) -> wav -> ogg. GM patch 3 (Honky-tonk Piano) for melody AND
accompaniment. Cut time, half note ~ 104.

Run: python3 tools/gen_gladiators_tackpiano.py
Out: godot/assets/audio/music/gladiators_tack_piano.ogg (+ .import)
"""
import hashlib
import subprocess
from pathlib import Path

import mido

ROOT = Path(__file__).resolve().parents[1]
OUT_DIR = ROOT / "godot" / "assets" / "audio" / "music"
SF2 = "/usr/share/sounds/sf2/FluidR3_GM.sf2"
BPM = 208                      # quarter bpm: half-note = 104 in cut time
TPB = 480                      # ticks per quarter
EIG = TPB // 2                 # an eighth note
# grid unit = EIGHTH notes; cut-time bar = 4 quarters = 8 eighths per bar

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
    "C":   ("C2",  ["G3", "C4", "E4"]),
    "G7":  ("G2",  ["G3", "B3", "F4"]),
    "G":   ("G2",  ["G3", "B3", "D4"]),
    "F":   ("F2",  ["A3", "C4", "F4"]),
    "D7":  ("D2",  ["F#3", "C4", "D4"]),
    "Am":  ("A2",  ["A3", "C4", "E4"]),
    "C/G": ("G2",  ["G3", "C4", "E4"]),
    "Dm":  ("D2",  ["A3", "D4", "F4"]),
}

# Sections return (melody, chords_per_halfbar_or_bar, nbars).
# Melody entries: (pitch or [pitches] or None, start_eighth, dur_eighths)
# with start counted from the section start.  Chord chart: 2 symbols per bar
# (one per half-bar) so harmony can change mid-bar; use None to silence.

# ---- sections (filled in system by system from the scan) ---------------------

def _fanfare(m, bar, low, high):
    """dotted-half octave + two eighths, as engraved in intro bars 1-2/5-6/9-10."""
    b = bar * 8
    m.append(([low, high], b + 0, 6))
    m.append(([low, high], b + 6, 1))
    m.append(([low, high], b + 7, 1))

def _chromatic(m, start_eighth, from_pitch, n, step):
    """n chromatic eighths from midi pitch (ints, rendered via raw midi)."""
    for i in range(n):
        m.append((from_pitch + i * step, start_eighth + i, 1))

def intro():
    # bars 1-2: ff fanfare on E octaves (engraving: dotted-half + 2 eighths, bass tacet)
    m = []
    _fanfare(m, 0, "E4", "E5")
    _fanfare(m, 1, "E4", "E5")
    # bars 3-4: held E octave whole notes over a descending chromatic run (LH)
    m.append((["E4", "E5"], 2 * 8, 16))
    _chromatic(m, 2 * 8, p("F4"), 16, -1)          # F4 down to D3
    # bars 5-6: fanfare on F# octaves (engraved sharps)
    _fanfare(m, 4, "F#4", "F#5")
    _fanfare(m, 5, "F#4", "F#5")
    # bars 7-8: held F# octave over the second run
    m.append((["F#4", "F#5"], 6 * 8, 16))
    _chromatic(m, 6 * 8, p("G4"), 16, -1)          # G4 down to E3
    # bars 9-10: ff fanfare on G octaves, bass chords kick in
    _fanfare(m, 8, "G4", "G5")
    _fanfare(m, 9, "G4", "G5")
    # bars 11-12: chromatic ascent into the strain (E4 up to G5)
    _chromatic(m, 10 * 8, p("E4"), 16, +1)
    chords = [None, None, None, None, None, None, None, None,
              None, None, None, None, None, None, None, None,
              "G", "G", "G", "G", "G7", "G7", "G7", "G7"]
    return m, chords, 12

def first_strain():
    # The world-famous chromatic theme, ff stacc. 8-bar phrase, played twice
    # (engraved repeat) = 16 bars.  q=quarter(2 eighths), h=half(4 eighths).
    m = []
    chords = []
    def phrase(bar0, final):
        b = bar0 * 8
        # m1: C6 q, B5 q, then eighths Bb5 A5 Ab5 G5  (engraving-verified)
        m.append(("C6", b + 0, 2)); m.append(("B5", b + 2, 2))
        for i, n in enumerate(["Bb5", "A5", "Ab5", "G5"]):
            m.append((n, b + 4 + i, 1))
        # m2: A5 q, G5 q, then chromatic turn E5 Eb5 D5 D#5
        m.append(("A5", b + 8, 2)); m.append(("G5", b + 10, 2))
        for i, n in enumerate(["E5", "Eb5", "D5", "D#5"]):
            m.append((n, b + 12 + i, 1))
        # m3: E5 q, G5 q, F#5 half (accented, tied pair in the engraving)
        m.append(("E5", b + 16, 2)); m.append(("G5", b + 18, 2))
        m.append(("F#5", b + 20, 4))
        if not final:
            # m4: chord stabs + accented half on the dominant (D7 -> back to C6)
            m.append((["B4", "D5"], b + 24, 1))
            m.append((["B4", "D5"], b + 26, 1)); m.append((["B4", "D5"], b + 27, 1))
            m.append((["A4", "D5", "F#5"], b + 28, 4))
            chords.extend(["C", "C", "C", "C", "C", "D7", "G", "G7"])
        else:
            # m8: full cadence home to C
            m.append((["E5", "G5"], b + 24, 2))
            m.append((["D5", "F5"], b + 26, 2))
            m.append((["C5", "E5", "G5"], b + 28, 3))
            m.append((["C4", "G4", "C5"], b + 31, 1))
            chords.extend(["C", "C", "C", "C", "C", "D7", "G7", "C"])
    phrase(0, final=False)
    phrase(4, final=True)
    phrase(8, final=False)
    phrase(12, final=True)
    return m, chords, 16

SECTIONS = [intro, first_strain]

# ---- assembly ----------------------------------------------------------------
def main() -> None:
    mid = mido.MidiFile(ticks_per_beat=TPB)
    tempo = mido.bpm2tempo(BPM)

    lead = mido.MidiTrack(); mid.tracks.append(lead)
    lead.append(mido.MetaMessage("set_tempo", tempo=tempo, time=0))
    lead.append(mido.Message("program_change", channel=0, program=3, time=0))   # Honky-tonk
    acc = mido.MidiTrack(); mid.tracks.append(acc)
    acc.append(mido.Message("program_change", channel=1, program=3, time=0))    # Honky-tonk

    lead_ev: list = []
    acc_ev: list = []
    bar0 = 0
    for sec in SECTIONS:
        melody, chords, nbars = sec()
        for (note, start, dur) in melody:
            if note is None:
                continue
            notes = note if isinstance(note, list) else [note]
            t0 = (bar0 * 8 + start) * EIG
            for n in notes:
                num = n if isinstance(n, int) else p(n)
                gate = max(EIG // 2, dur * EIG - 60)   # ff stacc. feel
                lead_ev.append((t0, "on", num, 100))
                lead_ev.append((t0 + gate, "off", num, 0))
        for i, sym in enumerate(chords):          # one symbol per HALF-bar
            if sym is None:
                continue
            bass, chord = CHORDS[sym]
            b = (bar0 * 8 + i * 4) * EIG
            # oom (beat 1 of the half-bar)
            acc_ev.append((b, "on", p(bass), 86))
            acc_ev.append((b + 2 * EIG - 20, "off", p(bass), 0))
            # pah (beat 2 of the half-bar)
            for cn in chord:
                acc_ev.append((b + 2 * EIG, "on", p(cn), 62))
                acc_ev.append((b + 4 * EIG - 60, "off", p(cn), 0))
        bar0 += nbars

    for track, evs, ch in ((lead, lead_ev, 0), (acc, acc_ev, 1)):
        evs.sort(key=lambda e: (e[0], 0 if e[1] == "off" else 1))
        t_prev = 0
        for (t, kind, note, vel) in evs:
            msg = "note_on" if kind == "on" else "note_off"
            track.append(mido.Message(msg, channel=ch, note=note, velocity=vel, time=t - t_prev))
            t_prev = t

    mid_path = Path("/tmp/gladiators_tackpiano.mid")
    mid.save(mid_path)
    print("MIDI written:", mid_path, f"({bar0} bars, ~{bar0 * 4 * 60 / BPM:.0f}s)")

    wav = Path("/tmp/gladiators_tackpiano.wav")
    subprocess.run(["fluidsynth", "-ni", "-g", "0.8", SF2, str(mid_path),
                    "-F", str(wav), "-r", "44100"], check=True, capture_output=True)
    ogg = OUT_DIR / "gladiators_tack_piano.ogg"
    subprocess.run(["ffmpeg", "-y", "-i", str(wav), "-c:a", "libvorbis", "-q:a", "5",
                    str(ogg)], check=True, capture_output=True)
    res = f"res://assets/audio/music/{ogg.name}"
    md5 = hashlib.md5(res.encode()).hexdigest()
    ogg.with_suffix(".ogg.import").write_text(
        '[remap]\n\nimporter="oggvorbisstr"\ntype="AudioStreamOggVorbis"\n'
        f'uid="uid://m{md5[:12]}"\npath="res://.godot/imported/{ogg.name}-{md5}.oggvorbisstr"\n\n'
        '[deps]\n\n'
        f'source_file="{res}"\ndest_files=["res://.godot/imported/{ogg.name}-{md5}.oggvorbisstr"]\n\n'
        '[params]\n\nloop=true\nloop_offset=0\nbpm=0\nbeat_count=0\nbar_beats=4\n')
    print("OGG:", ogg, ogg.stat().st_size, "bytes")

if __name__ == "__main__":
    main()
