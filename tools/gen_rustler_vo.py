#!/usr/bin/env python3
"""Generate The Candy Rustler's 14 voice lines via ElevenLabs.

Renders one MP3 per en.json line under `boss.candy_rustler_dialog_*`:
  candy_rustler_intro_<n>.mp3   (2)
  candy_rustler_taunt_<n>.mp3   (4)
  candy_rustler_hit_<n>.mp3     (4)
  candy_rustler_dying_<n>.mp3   (4)

SOURCE OF TRUTH — verbatim text is `godot/assets/text/en.json` under
`boss.candy_rustler_dialog_{intro,taunts,when_hit,dying}`. en.json is
never modified — only the API payload is tagged.

PERFORMANCE — the Rustler is a cranky Yosemite-Sam blustering register
made of crumpled wrappers and twist-ties. Each line is performed with
inline eleven_v3 delivery tags so the model wires the mood into the
audio:
  - [cranky]    — leading flavour; he's perpetually irritated
  - [annoyed]   — softer cranky for less-explosive beats
  - [stuttering] — sputtery outbursts on the louder lines
  - [belch]     — wrapper/litter-themed digestive grumble; placed
                  mid-line for rhythmic punctuation, not at every beat
The verbatim wording is kept identical to en.json — only the tags differ.

Voice: ElevenLabs jjZSV1sTgxaee6zZ4AHG (the Rustler's new cranky voice),
model eleven_v3 (audio tags require eleven_v3), with
apply_text_normalization='on' for the cleanest interpretation of the
tagged input.

Run with the roguelike ElevenLabs venv (it has the SDK + the key):
  /home/projects/roguelike/.venv-eleven/bin/python tools/gen_rustler_vo.py

Key lookup: $ELEVENLABS_API_KEY / $ELEVEN_LABS_API_KEY, else Google
Secret Manager (secret ELEVENLABS_API_KEY), else a secrets.env (this
repo's, else the roguelike project's).

Output: godot/assets/audio/characters/candy_rustler_<slot>_<n>.mp3
"""
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
RUSTLER_VOICE = "jjZSV1sTgxaee6zZ4AHG"   # ElevenLabs — Rustler's new cranky voice
MODEL = "eleven_v3"                        # required for audio tags
OUTPUT_FMT = "mp3_44100_128"

# en.json key  ->  filename slot suffix
SLOTS = {
    "candy_rustler_dialog_intro": "intro",
    "candy_rustler_dialog_taunts": "taunt",
    "candy_rustler_dialog_when_hit": "hit",
    "candy_rustler_dialog_dying": "dying",
}

# Hand-tagged performance per en.json line. The text after the tags is the
# verbatim en.json wording. Tags chosen per the line's punch — explosive
# lines get [stuttering], lower-energy snarls get [annoyed], every line
# gets a [cranky] or [annoyed] lead, and [belch] is placed mid-line for
# rhythm (not at every beat — overuse dulls it).
PERFORMANCE = {
    # --- intro ---
    "WELL, RUSTLE MY WRAPPERS! Fresh sugar struttin' into MY territory!":
        "[cranky] [stuttering] WELL, RUSTLE MY WRAPPERS! [belch] [annoyed] "
        "Fresh sugar struttin' into MY territory!",

    "Ya unwrap this whole frontier an' pitch the rest aside?! I AM the rest!":
        "[cranky] [annoyed] Ya unwrap this whole frontier an' pitch the rest "
        "aside?! [belch] [stuttering] I AM the rest!",

    # --- taunts ---
    "RASSA-FRACKIN' sugar-tramps — hold STILL so's I can crinkle ya!":
        "[cranky] [stuttering] RASSA-FRACKIN' sugar-tramps — [belch] "
        "[annoyed] hold STILL so's I can crinkle ya!",

    "Every wrapper ya ever balled up an' threw away? It's ME now!":
        "[annoyed] [stuttering] Every wrapper ya ever balled up an' threw "
        "away? [belch] [cranky] It's ME now!",

    "C'mere, c'mere — I just wanna give ya a little... CRINKLE.":
        "[cranky] [stuttering] C'mere, c'mere — [annoyed] I just wanna give "
        "ya a little... [belch] CRINKLE.",

    "I'm FIT TO BE TIED — an' I'm MADE outta twist-ties!":
        "[annoyed] [stuttering] I'm FIT TO BE TIED — [belch] [cranky] an' "
        "I'm MADE outta twist-ties!",

    # --- when hit ---
    "OW! Me good foil!":
        "[annoyed] OW! [belch] [cranky] Me good foil!",

    "YEEOWCH! Ya tore me wrapper!":
        "[cranky] [stuttering] YEEOWCH! [annoyed] Ya tore me wrapper!",

    "CONSARN your sticky fingers!":
        "[cranky] [stuttering] CONSARN your [belch] sticky fingers!",

    "Rrrgh — that's comin' straight outta yer DEPOSIT!":
        "[annoyed] [stuttering] Rrrgh — [belch] [cranky] that's comin' "
        "straight outta yer DEPOSIT!",

    # --- dying ---
    "Noooo! I'm comin' apart at the SEEEAMS!":
        "[cranky] [stuttering] Noooo! [annoyed] I'm comin' apart at the "
        "[belch] SEEEAMS!",

    "Ya can't... recycle... a LEGEND...":
        "[annoyed] [stuttering] Ya can't... [belch] recycle... a LEGEND...",

    "Crinkle... crinkle... *sigh*":
        "[cranky] Crinkle... [belch] crinkle... [stuttering] *sigh*",

    "RA-SSAA-FRACKIN' biodegradable—":
        "[annoyed] [stuttering] RA-SSAA-FRACKIN' [belch] biodegradable—",
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
    """Look up the tagged performance for one en.json line. Falls back to a
    plain [cranky]-prefixed read if the line was edited in en.json without
    updating PERFORMANCE — so the build never silently breaks."""
    spoken = PERFORMANCE.get(line)
    if spoken is not None:
        return spoken
    print("  WARN line not in PERFORMANCE — plain tagged fallback: %r" % line)
    return "[cranky] %s" % line


def render(client: ElevenLabs, dst: Path, spoken: str) -> None:
    audio = client.text_to_speech.convert(
        voice_id=RUSTLER_VOICE,
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
    print("wrote %-32s  %6d bytes  %s" % (dst.name, size, spoken[:64]))


def main() -> None:
    client = ElevenLabs(api_key=read_api_key())
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    boss = json.loads(EN_JSON.read_text())["boss"]
    written = 0
    for key, slot in SLOTS.items():
        for i, line in enumerate(boss[key]):
            dst = OUT_DIR / ("candy_rustler_%s_%d.mp3" % (slot, i))
            render(client, dst, perform(line))
            written += 1
    print("\ndone: %d Rustler VO files rendered" % written)


if __name__ == "__main__":
    main()
