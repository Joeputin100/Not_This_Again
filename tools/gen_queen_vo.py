#!/usr/bin/env python3
"""Generate Level-6 Queen of the Night + Papageno voice lines via ElevenLabs.

Renders one MP3 per en.json line; file slugs match level_3d.gd exactly
(`_queen_say` banks + the Papageno tutorial calls). AudioBus loads
`res://assets/audio/characters/<slug>.mp3`, missing-safe.

  queen_intro_<n>.mp3     (2)   boss.queen_dialog_intro
  queen_sing_<n>.mp3      (3)   boss.queen_dialog_sing      (she belts a phrase)
  queen_highnote_<n>.mp3  (3)   boss.queen_dialog_highnote  (player missed -> drain)
  queen_phase2_<n>.mp3    (2)   boss.queen_dialog_phase2    (50% HP)
  queen_dying_<n>.mp3     (2)   boss.queen_dialog_dying     (she loses)
  papageno_intro_<n>.mp3  (1)   papageno.papageno_dialog_intro
  papageno_cheer_<n>.mp3  (1)   papageno.papageno_dialog_cheer

SOURCE OF TRUTH — verbatim text is `godot/assets/text/en.json` under
`boss.queen_dialog_*` and `papageno.papageno_dialog_*`. en.json is never
modified here — only the API payload is tagged with eleven_v3 delivery tags.

VOICES (PLACEHOLDERS — owner to confirm/swap before release):
  Queen    = pFZP5JQG7iQjIQuC4Bku  "Lily - Velvety Actress" (dramatic female).
             Override with --voice <id> once the owner adds an operatic
             Queen-of-the-Night clone (every other boss got a hand-picked voice;
             this one was not provided when the overnight build ran).
  Papageno = fmR785nA5jqTzoTNg3Jk  "Bob - Silly Millionaire Narrator" (comic male).

PERFORMANCE — the Queen is a baroque coloratura villainess belting *Der Hoelle
Rache*: imperious, operatic, vengeful, candy-cute. Papageno is the giddy comic
bird-catcher of the tutorial duet. Lines carry inline eleven_v3 delivery tags;
the verbatim en.json wording is kept identical — only the tags differ.

Run with the roguelike ElevenLabs venv (SDK + key):
  /home/projects/roguelike/.venv-eleven/bin/python tools/gen_queen_vo.py
  /home/projects/roguelike/.venv-eleven/bin/python tools/gen_queen_vo.py --voice <queen_id>

Key lookup: $ELEVENLABS_API_KEY / $ELEVEN_LABS_API_KEY, else Google Secret
Manager (secret ELEVENLABS_API_KEY), else a secrets.env.

Output: godot/assets/audio/characters/<slug>.mp3
"""
import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
from pathlib import Path

from elevenlabs.client import ElevenLabs

ROOT = Path(__file__).resolve().parents[1]
EN_JSON = ROOT / "godot" / "assets" / "text" / "en.json"
OUT_DIR = ROOT / "godot" / "assets" / "audio" / "characters"

QUEEN_VOICE = "pFZP5JQG7iQjIQuC4Bku"     # PLACEHOLDER: Lily - Velvety Actress
PAPAGENO_VOICE = "fmR785nA5jqTzoTNg3Jk"  # PLACEHOLDER: Bob - Silly Millionaire
MODEL = "eleven_v3"                        # required for audio tags
OUTPUT_FMT = "mp3_44100_128"

# (en.json block, key) -> (filename slug prefix, voice).  Voice is resolved at
# run time so --voice can override the Queen.
def banks(queen_voice: str):
    return [
        ("boss", "queen_dialog_intro", "queen_intro_", queen_voice),
        ("boss", "queen_dialog_sing", "queen_sing_", queen_voice),
        ("boss", "queen_dialog_highnote", "queen_highnote_", queen_voice),
        ("boss", "queen_dialog_phase2", "queen_phase2_", queen_voice),
        ("boss", "queen_dialog_dying", "queen_dying_", queen_voice),
        ("papageno", "papageno_dialog_intro", "papageno_intro_", PAPAGENO_VOICE),
        ("papageno", "papageno_dialog_cheer", "papageno_cheer_", PAPAGENO_VOICE),
    ]

# Hand-tagged performance per en.json line. Text after the tags is the
# verbatim en.json wording.
PERFORMANCE = {
    # --- Queen intro ---
    "So... the little posse dares my starlit stage. Sing for me, sugar-children — or be silenced forever.":
        "[dramatic] So... [whispers] the little posse dares my starlit stage. "
        "[singing] Sing for me, sugar-children — [shouting] or be silenced forever.",
    "Hell's own vengeance boils in this candied heart. Match my voice, note for note, or shatter.":
        "[dramatic] Hell's own vengeance boils in this candied heart. "
        "[singing] Match my voice, note for note, [shouting] or shatter.",
    # --- Queen sing (she belts a phrase to trace) ---
    "Follow this, if your throats are sweet enough!":
        "[singing] Follow this, [dramatic] if your throats are sweet enough!",
    "Trace my fury — and do not fall behind!":
        "[singing] Trace my fury — [shouting] and do not fall behind!",
    "Now... sing it BACK to me!":
        "[dramatic] Now... [singing] sing it [shouting] BACK to me!",
    # --- Queen highnote (player missed; she drains the posse) ---
    "Flat! Pathetic! Feel my high F!":
        "[shouting] Flat! [sarcastic] Pathetic! [singing] Feel my high F!",
    "Off the beat — and off with your sugar!":
        "[sarcastic] Off the beat — [shouting] and off with your sugar!",
    "You crack... while I soar!":
        "[whispers] You crack... [singing] while I soar!",
    # --- Queen phase 2 (50% HP) ---
    "Enough! Now you face the TRUE aria of the night!":
        "[shouting] Enough! [dramatic] Now you face the TRUE aria of the night!",
    "My vengeance has scarcely begun — louder! FASTER!":
        "[dramatic] My vengeance has scarcely begun — [shouting] louder! FASTER!",
    # --- Queen dying (she loses) ---
    "Impossible... out-sung... by a chorus of... candy...":
        "[whispers] Impossible... out-sung... [sighs] by a chorus of... candy...",
    "My final note... fades... to sugar...":
        "[sighs] My final note... [whispers] fades... to sugar...",
    # --- Papageno tutorial ---
    "Pa-pa-pa! Hallo, little posse! Sing along with old Papageno — just trace what I tweet, ja?":
        "[cheerfully] Pa-pa-pa! Hallo, little posse! Sing along with old Papageno — "
        "[laughs] just trace what I tweet, ja?",
    "Pa-pa-pa-PERFECT! Papagena would be so proud! Ho ho ho!":
        "[excited] Pa-pa-pa-PERFECT! Papagena would be so proud! [laughs] Ho ho ho!",
}


def read_api_key() -> str:
    for env in ("ELEVENLABS_API_KEY", "ELEVEN_LABS_API_KEY"):
        val = os.getenv(env)
        if val:
            return val
    try:
        out = subprocess.run(
            ["gcloud", "secrets", "versions", "access", "latest",
             "--secret=ELEVENLABS_API_KEY"],
            capture_output=True, text=True, timeout=30)
        if out.returncode == 0 and out.stdout.strip():
            return out.stdout.strip()
    except (OSError, subprocess.SubprocessError):
        pass
    for path in (ROOT / "secrets.env",
                 Path("/home/projects/roguelike/secrets.env")):
        if path.exists():
            for line in path.read_text().splitlines():
                m = re.match(r'\s*ELEVEN_?LABS_API_?KEY\s*=\s*"?([^"\n]+)"?',
                             line, re.I)
                if m:
                    return m.group(1).strip()
    sys.exit("FATAL: no ElevenLabs API key (env / GSM / secrets.env)")


def perform(line: str) -> str:
    spoken = PERFORMANCE.get(line)
    if spoken is not None:
        return spoken
    print("  WARN line not in PERFORMANCE — plain tagged fallback: %r" % line)
    return "[dramatic] %s" % line


def render(client: ElevenLabs, dst: Path, spoken: str, voice: str) -> None:
    audio = client.text_to_speech.convert(
        voice_id=voice,
        text=spoken,
        model_id=MODEL,
        output_format=OUTPUT_FMT,
        apply_text_normalization="on",
    )
    with open(dst, "wb") as f:
        for chunk in audio:
            f.write(chunk)
    size = dst.stat().st_size
    if size == 0:
        sys.exit("FATAL: %s rendered empty" % dst.name)
    print("wrote %-26s  %6d bytes  %s" % (dst.name, size, spoken[:54]))
    write_import_sidecar(dst)


def write_import_sidecar(mp3: Path) -> None:
    """Author the Godot .import sidecar so CI's headless import picks the file
    up deterministically (mirrors the committed Raisin/Granny VO sidecars).

    The imported-path hash is md5(res-path); the uid is derived the same way so
    it is stable across machines without a Godot editor round-trip."""
    res_path = "res://assets/audio/characters/%s" % mp3.name
    md5 = hashlib.md5(res_path.encode()).hexdigest()
    uid = "uid://q%s" % md5[:12]  # stable, unique-enough per res-path
    sidecar = mp3.with_suffix(mp3.suffix + ".import")
    sidecar.write_text(
        "[remap]\n\n"
        'importer="mp3"\n'
        'type="AudioStreamMP3"\n'
        'uid="%s"\n'
        'path="res://.godot/imported/%s-%s.mp3str"\n\n'
        "[deps]\n\n"
        'source_file="%s"\n'
        'dest_files=["res://.godot/imported/%s-%s.mp3str"]\n\n'
        "[params]\n\n"
        "loop=false\n"
        "loop_offset=0\n"
        "bpm=0\n"
        "beat_count=0\n"
        "bar_beats=4\n"
        % (uid, mp3.name, md5, res_path, mp3.name, md5))


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--voice", default=QUEEN_VOICE,
                    help="override the Queen voice id (Papageno is unaffected)")
    args = ap.parse_args()

    client = ElevenLabs(api_key=read_api_key())
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    en = json.loads(EN_JSON.read_text())
    written = 0
    for block, key, prefix, voice in banks(args.voice):
        lines = en[block][key]
        for i, line in enumerate(lines):
            dst = OUT_DIR / ("%s%d.mp3" % (prefix, i))
            render(client, dst, perform(line), voice)
            written += 1
    print("\ndone: %d Level-6 VO files rendered (Queen=%s, Papageno=%s)"
          % (written, args.voice, PAPAGENO_VOICE))


if __name__ == "__main__":
    main()
