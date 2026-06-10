#!/usr/bin/env python3
"""Generate The Jawbreaker's full bark set via ElevenLabs.

Renders one MP3 per en.json line under `boss.jawbreaker_dialog_*`:
  jawbreaker_intro_<n>.mp3   (1)
  jawbreaker_taunt_<n>.mp3   (2)   mid-fight cold-griping grumbles
  jawbreaker_hit_<n>.mp3     (1)   shell chipped
  jawbreaker_charge_<n>.mp3  (1)   ~10s snow-blast wind-up telegraph
  jawbreaker_blast_<n>.mp3   (1)   on release
  jawbreaker_dying_<n>.mp3   (1)

File slugs match level_3d.gd `_jawbreaker_say` banks. AudioBus loads
`res://assets/audio/characters/<slug>.mp3`, missing-safe.

SOURCE OF TRUTH — verbatim text is `godot/assets/text/en.json` under
`boss.jawbreaker_dialog_*` (lines themselves are verbatim from the design
doc 2026-06-05-jawbreaker-boss-design.md §3). en.json is never modified
here — every line is performed with the Popeye treatment: prefix
`[exaggerated muttering] [rapido]` (eleven_v3 audio tags).

Voice: ElevenLabs w80xe5dXbsBW24dNaND0 (owner-created Jawbreaker voice),
model eleven_v3, apply_text_normalization='on'.

Run with the roguelike ElevenLabs venv (it has the SDK + the key):
  /home/projects/roguelike/.venv-eleven/bin/python tools/gen_jawbreaker_vo.py

Key lookup: $ELEVENLABS_API_KEY / $ELEVEN_LABS_API_KEY, else Google Secret
Manager (secret ELEVENLABS_API_KEY), else a secrets.env.

Output: godot/assets/audio/characters/jawbreaker_<slot>_<n>.mp3 (+ .import)
"""
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
JAWBREAKER_VOICE = "w80xe5dXbsBW24dNaND0"   # owner-created Jawbreaker voice
MODEL = "eleven_v3"                           # required for audio tags
OUTPUT_FMT = "mp3_44100_128"

# The Popeye treatment: fast under-breath sailor mutter on every line.
TAG_PREFIX = "[exaggerated muttering] [rapido] "

# en.json key -> filename slot suffix (must match level_3d.gd _jawbreaker_say)
SLOTS = {
    "jawbreaker_dialog_intro": "intro",
    "jawbreaker_dialog_taunts": "taunt",
    "jawbreaker_dialog_when_hit": "hit",
    "jawbreaker_dialog_charge": "charge",
    "jawbreaker_dialog_blast": "blast",
    "jawbreaker_dialog_dying": "dying",
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


def write_import_sidecar(mp3: Path) -> None:
    """Godot .import sidecar (md5 = md5(res-path), the committed-VO pattern)."""
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


def render(client: ElevenLabs, dst: Path, spoken: str) -> None:
    audio = client.text_to_speech.convert(
        voice_id=JAWBREAKER_VOICE,
        text=spoken,
        model_id=MODEL,
        output_format=OUTPUT_FMT,
        apply_text_normalization="on",
    )
    with open(dst, "wb") as f:
        for chunk in audio:
            f.write(chunk)
    if dst.stat().st_size == 0:
        sys.exit("FATAL: %s rendered empty" % dst.name)
    print("wrote %-26s  %6d bytes" % (dst.name, dst.stat().st_size))
    write_import_sidecar(dst)


def main() -> None:
    client = ElevenLabs(api_key=read_api_key())
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    boss = json.loads(EN_JSON.read_text())["boss"]
    written = 0
    for key, slot in SLOTS.items():
        for i, line in enumerate(boss[key]):
            dst = OUT_DIR / ("jawbreaker_%s_%d.mp3" % (slot, i))
            render(client, dst, TAG_PREFIX + line)
            written += 1
    print("\ndone: %d Jawbreaker VO files rendered" % written)


if __name__ == "__main__":
    main()
