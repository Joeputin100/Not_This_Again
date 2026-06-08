#!/usr/bin/env python3
"""Generate Raisin Kidd's voice lines via ElevenLabs.

Renders one MP3 per en.json line under `boss.raisin_dialog_*`:
  raisin_intro_<n>.mp3     (2)
  raisin_gow_<n>.mp3       (3)   Grapes-of-Wrath flurry shout
  raisin_warp_<n>.mp3      (3)
  raisin_phase2_<n>.mp3    (2)
  raisin_hit_<n>.mp3       (4)   when a shot lands through his guard
  raisin_dying_<n>.mp3     (2)   he LOSES (player wins) — death groan
  raisin_finisher_<n>.mp3  (2)   he WINS — triumphant Five-Point cackle

File slugs match level_3d.gd `_raisin_say` banks exactly. AudioBus loads
`res://assets/audio/characters/<slug>.mp3`.

SOURCE OF TRUTH — verbatim text is `godot/assets/text/en.json` under
`boss.raisin_dialog_*`. en.json is never modified here — only the API
payload is tagged.

PERFORMANCE — Raisin Kidd is an ancient, arrogant Pai-Mei-style kung-fu
grandmaster (a dried grape, all wrinkles), contemptuous and theatrical,
punctuating everything with a sinister cackle. Lines are performed with
inline eleven_v3 delivery tags ([mischievously], [laughs], [whispers],
[shouting], [sarcastic], [sighs], [annoyed]); the verbatim en.json wording
is kept identical — only the tags differ.

Voice: ElevenLabs 1a0nAYA3FcNQcMMfbddY (owner-added Raisin Kidd voice),
model eleven_v3 (audio tags require eleven_v3), apply_text_normalization='on'.

Run with the roguelike ElevenLabs venv (it has the SDK + the key):
  /home/projects/roguelike/.venv-eleven/bin/python tools/gen_raisin_vo.py

Key lookup: $ELEVENLABS_API_KEY / $ELEVEN_LABS_API_KEY, else Google Secret
Manager (secret ELEVENLABS_API_KEY), else a secrets.env.

Output: godot/assets/audio/characters/raisin_<slot>_<n>.mp3
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
RAISIN_VOICE = "1a0nAYA3FcNQcMMfbddY"   # owner-added Raisin Kidd voice
MODEL = "eleven_v3"                       # required for audio tags
OUTPUT_FMT = "mp3_44100_128"

# en.json key  ->  filename slot suffix (must match level_3d.gd _raisin_say)
SLOTS = {
    "raisin_dialog_intro": "intro",
    "raisin_dialog_gow": "gow",
    "raisin_dialog_warp": "warp",
    "raisin_dialog_phase2": "phase2",
    "raisin_dialog_when_hit": "hit",
    "raisin_dialog_dying": "dying",
    "raisin_dialog_finisher": "finisher",
}

# Hand-tagged performance per en.json line. Text after the tags is the
# verbatim en.json wording.
PERFORMANCE = {
    # --- intro ---
    "Ahh... fresh sugar, so eager to be crushed. You face Raisin Kidd — old, wrinkled, and utterly untouchable.":
        "[mischievously] Ahh... fresh sugar, [sarcastic] so eager to be crushed. "
        "[whispers] You face Raisin Kidd — old, wrinkled, [shouting] and utterly untouchable.",
    "Come, little candies. Throw yourselves upon my palms. I have waited a hundred dry years for a snack.":
        "[mischievously] Come, little candies. Throw yourselves upon my palms. "
        "[laughs] I have waited a hundred dry years for a snack.",
    # --- gow (Grapes of Wrath flurry shout) ---
    "Behold — the GRAPES of WRATH!":
        "[shouting] Behold — the GRAPES of WRATH!",
    "Witness a thousand strikes you will never see!":
        "[shouting] Witness a thousand strikes you will never see!",
    "Dance for me, sugar-dust... GRAPES OF WRATH!":
        "[mischievously] Dance for me, sugar-dust... [shouting] GRAPES OF WRATH!",
    # --- warp ---
    "Too slow. Always too slow.":
        "[sarcastic] Too slow. [whispers] Always too slow.",
    "Where is the old raisin now? Heh heh heh...":
        "[whispers] Where is the old raisin now? [laughs] Heh heh heh...",
    "You cannot strike what you cannot follow.":
        "[mischievously] You cannot strike what you cannot follow.",
    # --- phase2 ---
    "Hmph. So the candy has a little crunch after all. Now I am awake.":
        "[sarcastic] Hmph. So the candy has a little crunch after all. "
        "[shouting] Now I am awake.",
    "Enough games. You have angered the Kidd.":
        "[shouting] Enough games. [annoyed] You have angered the Kidd.",
    # --- when hit ---
    "Gah! A lucky grain!":
        "[shouting] Gah! [annoyed] A lucky grain!",
    "You... touched me?!":
        "[annoyed] You... [shouting] touched me?!",
    "Impossible — no one breaks the guard of Raisin Kidd!":
        "[shouting] Impossible — no one breaks the guard of Raisin Kidd!",
    "Rrrgh — sticky little pests!":
        "[annoyed] Rrrgh — sticky little pests!",
    # --- dying (he loses) ---
    "Impossible... wrinkled... but never... beaten...":
        "[whispers] Impossible... wrinkled... but never... beaten...",
    "A hundred years... undone by... jellybeans...":
        "[sighs] A hundred years... undone by... jellybeans...",
    # --- finisher (he wins) ---
    "Heh heh heh... Five-Point... Exploding... GUMDROP!":
        "[laughs] Heh heh heh... Five-Point... Exploding... [shouting] GUMDROP!",
    "Sleep now, little candies. The Kidd has won.":
        "[mischievously] Sleep now, little candies. [whispers] The Kidd has won.",
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
        voice_id=RAISIN_VOICE,
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
    boss = json.loads(EN_JSON.read_text())["boss"]
    written = 0
    for key, slot in SLOTS.items():
        for i, line in enumerate(boss[key]):
            dst = OUT_DIR / ("raisin_%s_%d.mp3" % (slot, i))
            render(client, dst, perform(line))
            written += 1
    print("\ndone: %d Raisin Kidd VO files rendered" % written)


if __name__ == "__main__":
    main()
