#!/usr/bin/env python3
"""Generate level-select cowboy tap VO + per-prop tap SFX via ElevenLabs.

Cowboy uses the Murderbot narrator voice (61Qg29Wr3AuLLXn122Hd), eleven_v3,
deadpan delivery (see project_levelselect_character_audio_todo). 6 warm
"regular" tap lines + 6 abrasive "annoyed" lines (rotated after 8 quick taps).
Per-prop SFX use the sound-generation API. Committed to the repo, not
regenerated each build.

  /home/projects/roguelike/.venv-eleven/bin/python tools/gen_levelselect_audio.py
"""
import json
import subprocess
import sys
import urllib.request
from pathlib import Path

from elevenlabs.client import ElevenLabs

ROOT = Path(__file__).resolve().parents[1]
SFX_DIR = ROOT / "godot" / "assets" / "sfx"
VOICE = "61Qg29Wr3AuLLXn122Hd"   # Murderbot narrator (shared with flourish VO)
MODEL = "eleven_v3"              # inline delivery tags

REGULAR = [   # warm, dry, loyal — deadpan but on the player's side
    "Ready when you are. Always am. It's a curse.",
    "Point me at a level. I'll handle the messy parts.",
    "Still here. Still on your side.",
    "You bring the plan, I'll bring the trouble.",
    "Whatever you're cooking up, count me in.",
    "Tap away. I've got nowhere better to be.",
]
ANNOYED = [   # abrasive deadpan — only after 8 quick taps
    "Poke me again. I'll allow it. Once.",
    "I'm counting. You won't like the number.",
    "That finger and I are going to have words.",
    "I'm a gunslinger, not a doorbell.",
    "Fascinating. Do it again and find out.",
    "Somewhere, a tumbleweed is judging you.",
]
PROPS = {
    "prop_cactus": ("A short dry spiny rustle with a soft hollow boing, about 500 "
                    "milliseconds: a potted desert cactus jiggling, papery spines "
                    "shivering, no music, no reverb tail", 0.7),
    "prop_wagon": ("A short heavy wooden rattle, about 700 milliseconds: an old "
                   "covered wagon shaking, timber planks knocking together, a chain "
                   "and a wheel creak, no music, no reverb tail", 0.9),
    "prop_rock": ("A short dull stone thunk, about 400 milliseconds: a solid heavy "
                  "boulder tapped once, low knock with a little loose gravel, no "
                  "music, no reverb tail", 0.6),
    "prop_tumbleweed": ("A short dry whoosh and papery roll, about 500 milliseconds: "
                        "a light tumbleweed bouncing and skittering, brittle twigs "
                        "rustling, no music, no reverb tail", 0.7),
}


def api_key() -> str:
    import os
    if os.environ.get("ELEVENLABS_API_KEY"):
        return os.environ["ELEVENLABS_API_KEY"]
    out = subprocess.run(["gcloud", "secrets", "versions", "access", "latest",
                          "--secret=ELEVENLABS_API_KEY"],
                         capture_output=True, text=True, timeout=30)
    if out.returncode == 0 and out.stdout.strip():
        return out.stdout.strip()
    sys.exit("FATAL: no ElevenLabs API key")


def to_ogg(mp3: Path, ogg: Path) -> None:
    subprocess.run(["ffmpeg", "-y", "-i", str(mp3), "-c:a", "libvorbis",
                    "-q:a", "4", str(ogg)], check=True, capture_output=True)
    mp3.unlink()


def gen_vo(client: ElevenLabs, text: str, dst: Path) -> None:
    audio = client.text_to_speech.convert(
        voice_id=VOICE, text="[deadpan, dry] " + text,
        model_id=MODEL, output_format="mp3_44100_128")
    mp3 = dst.with_suffix(".mp3")
    with open(mp3, "wb") as f:
        for ch in audio:
            f.write(ch)
    to_ogg(mp3, dst)
    print("VO  %-22s %7d  %s" % (dst.name, dst.stat().st_size, text))


def gen_sfx(key: str, prompt: str, dur: float, dst: Path) -> None:
    req = urllib.request.Request(
        "https://api.elevenlabs.io/v1/sound-generation",
        data=json.dumps({"text": prompt, "duration_seconds": dur,
                         "prompt_influence": 0.5,
                         "output_format": "mp3_44100_128"}).encode(),
        headers={"xi-api-key": key, "Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=90) as r:
        data = r.read()
    mp3 = dst.with_suffix(".mp3")
    mp3.write_bytes(data)
    to_ogg(mp3, dst)
    print("SFX %-22s %7d" % (dst.name, dst.stat().st_size))


def main() -> None:
    SFX_DIR.mkdir(parents=True, exist_ok=True)
    key = api_key()
    client = ElevenLabs(api_key=key)
    for i, t in enumerate(REGULAR):
        gen_vo(client, t, SFX_DIR / ("cowboy_tap_%d.ogg" % i))
    for i, t in enumerate(ANNOYED):
        gen_vo(client, t, SFX_DIR / ("cowboy_annoyed_%d.ogg" % i))
    for slug, (p, d) in PROPS.items():
        gen_sfx(key, p, d, SFX_DIR / (slug + ".ogg"))
    print("done")


if __name__ == "__main__":
    main()
