#!/usr/bin/env python3
"""Generate Candy Granny's voice lines via ElevenLabs.

Renders one MP3 per en.json line under `granny.granny_dialog_*`:
  granny_intro_<n>.mp3        (3)   plea / guilt-trip
  granny_chatter_<n>.mp3      (5)   ambient candy-house chatter
  granny_chase_<n>.mp3        (2)   heckle/cheer during the run
  granny_win_full_<n>.mp3     (1)   caught all 8
  granny_win_partial_<n>.mp3  (1)   caught 1-7
  granny_win_zero_<n>.mp3     (1)   caught 0
  granny_cooldown_<n>.mp3     (1)   on cooldown / dismissed

NOTE: the `cackle` bank is NOT generated here — the owner supplied real cackle
SFX, already committed as granny_cackle_0..3.mp3.

File slugs match the chicken_chase.gd / granny_popup.gd calls. AudioBus loads
`res://assets/audio/characters/<slug>.mp3`. en.json is the text source-of-truth.

Candy Granny is a sly, hunched, cackling candy-witch grandma, sweet-but-scheming
and delighted with her candy house. Performed with inline eleven_v3 delivery
tags ([mischievously], [laughs], [whispers], [cackles]); verbatim en.json
wording kept identical — only the tags differ.

Voice: ElevenLabs vFLqXa8bgbofGarf6fZh (owner-provided Candy Granny voice),
model eleven_v3, apply_text_normalization='on'.

Run with the roguelike ElevenLabs venv:
  /home/projects/roguelike/.venv-eleven/bin/python tools/gen_granny_vo.py

Output: godot/assets/audio/characters/granny_<slot>_<n>.mp3
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
GRANNY_VOICE = "vFLqXa8bgbofGarf6fZh"
MODEL = "eleven_v3"
OUTPUT_FMT = "mp3_44100_128"

# en.json key -> filename slot suffix (must match the in-game slugs)
SLOTS = {
    "granny_dialog_intro": "intro",
    "granny_dialog_chatter": "chatter",
    "granny_dialog_chase": "chase",
    "granny_dialog_win_full": "win_full",
    "granny_dialog_win_partial": "win_partial",
    "granny_dialog_win_zero": "win_zero",
    "granny_dialog_cooldown": "cooldown",
}

PERFORMANCE = {
    # intro
    "Ooh, a strappin' young gunslinger — just the sugar I need! My hens have flown the coop, on account of YOUR posse stampin' it flat, I might add.":
        "[mischievously] Ooh, a strappin' young gunslinger — just the sugar I need! "
        "[annoyed] My hens have flown the coop, on account of YOUR posse stampin' it flat, I might add.",
    "Don't give Granny that look, dearie. Somebody's six-shooters turned my henhouse to kindlin'. Help an old gal round 'em up?":
        "[mischievously] Don't give Granny that look, dearie. Somebody's six-shooters turned my henhouse to kindlin'. "
        "[whispers] Help an old gal round 'em up?",
    "Catch my hens and I'll brew ye a little pick-me-up. Straight from the cauldron. Heh heh heh.":
        "[whispers] Catch my hens and I'll brew ye a little pick-me-up. Straight from the cauldron. [laughs] Heh heh heh.",
    # chatter
    "Built this whole place out of gingerbread and gumdrops, I did. Who wouldn't want to live in a house made of candy?":
        "[mischievously] Built this whole place out of gingerbread and gumdrops, I did. Who wouldn't want to live in a house made of candy?",
    "Mind the walls, sugar — last fella took a bite, and I had to re-frost the entire parlor.":
        "[mischievously] Mind the walls, sugar — last fella took a bite, and [annoyed] I had to re-frost the entire parlor.",
    "That cauldron's been bubblin' since before yer granny was a twinkle. Smells divine, don't it?":
        "[whispers] That cauldron's been bubblin' since before yer granny was a twinkle. [mischievously] Smells divine, don't it?",
    "Real marzipan roof, that. The popcorn hens keep peckin' it — cheeky little kernels.":
        "[mischievously] Real marzipan roof, that. The popcorn hens keep peckin' it — [annoyed] cheeky little kernels.",
    "Oh, I do love comp'ny. Stay a while, won't ye? ...Stay forever, even. Heh heh heh.":
        "[mischievously] Oh, I do love comp'ny. Stay a while, won't ye? [whispers] ...Stay forever, even. [laughs] Heh heh heh.",
    # chase
    "Faster, sugar — they're poppin' off ever' which way!":
        "[excited] Faster, sugar — they're poppin' off ever' which way!",
    "Ooh, slippery little kernels, ain't they?":
        "[mischievously] Ooh, slippery little kernels, ain't they?",
    # wins
    "HA! Every last hen! Yer a natural, dearie — drink up, the posse's on Granny!":
        "[laughs] HA! Every last hen! Yer a natural, dearie — [excited] drink up, the posse's on Granny!",
    "Well, a few hens'll have to do. Half a brew's better than none — sip it down, sugar.":
        "[mischievously] Well, a few hens'll have to do. Half a brew's better than none — sip it down, sugar.",
    "Bah! Not a single one?! My cauldron stays COLD for that. Off with ye.":
        "[annoyed] Bah! Not a single one?! My cauldron stays COLD for that. Off with ye.",
    # cooldown
    "Cauldron's got to simmer, dearie. Come back tomorrow and we'll have another go.":
        "[mischievously] Cauldron's got to simmer, dearie. Come back tomorrow and we'll have another go.",
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
    return "[mischievously] %s" % line


def render(client: ElevenLabs, dst: Path, spoken: str) -> None:
    audio = client.text_to_speech.convert(
        voice_id=GRANNY_VOICE,
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
    print("wrote %-28s  %6d bytes  %s" % (dst.name, size, spoken[:60]))


def main() -> None:
    client = ElevenLabs(api_key=read_api_key())
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    granny = json.loads(EN_JSON.read_text())["granny"]
    written = 0
    for key, slot in SLOTS.items():
        for i, line in enumerate(granny[key]):
            dst = OUT_DIR / ("granny_%s_%d.mp3" % (slot, i))
            render(client, dst, perform(line))
            written += 1
    print("\ndone: %d Candy Granny VO files rendered" % written)


if __name__ == "__main__":
    main()
