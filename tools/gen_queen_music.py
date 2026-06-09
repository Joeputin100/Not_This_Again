#!/usr/bin/env python3
"""Generate the Level-6 instrumental backing track via ElevenLabs Music.

A candy music-box arrangement of Mozart's *Der Hoelle Rache* (the Queen of the
Night aria) — the bed under the starlit-canyon run and the sing-duel. Public-
domain melody, our own AI-performed instrumental, so no recording licence.

Renders mp3 -> converts to ogg (matches the other LEVEL_TRACKS) -> authors the
Godot .import sidecar. Wire in music_player.gd LEVEL_TRACKS[6].

Run with the roguelike ElevenLabs venv:
  /home/projects/roguelike/.venv-eleven/bin/python tools/gen_queen_music.py
"""
import hashlib
import os
import subprocess
import sys
from pathlib import Path

from elevenlabs.client import ElevenLabs

ROOT = Path(__file__).resolve().parents[1]
OUT_DIR = ROOT / "godot" / "assets" / "audio" / "music"
NAME = "queen_of_the_night_canyon"
LENGTH_MS = 90000  # ~1.5 min loopable bed

# NOTE: naming the composer/work ("Mozart", "Der Hoelle Rache") trips the
# Music API's TOS filter (bad_prompt). We use the style-only phrasing the API
# itself suggested back — "inspired by baroque opera", no named work — which is
# the same prompt-filter fallback pattern we use on Veo.
PROMPT = (
    "An instrumental music-box style arrangement inspired by baroque opera, "
    "featuring lead glockenspiel and celesta with plucked harp, light staccato "
    "pizzicato strings, harpsichord flourishes, and a dark twinkling synth pad "
    "underneath. The piece should be eerie-pretty, theatrical, nocturnal, and "
    "magical with a touch of villainy, building in intensity toward a fast "
    "staccato climax. Moderate-fast tempo, steady danceable pulse, seamlessly "
    "loopable, purely instrumental with no vocals or drum kit."
)


def read_api_key() -> str:
    for env in ("ELEVENLABS_API_KEY", "ELEVEN_LABS_API_KEY"):
        if os.getenv(env):
            return os.getenv(env)
    out = subprocess.run(
        ["gcloud", "secrets", "versions", "access", "latest",
         "--secret=ELEVENLABS_API_KEY"],
        capture_output=True, text=True, timeout=30)
    if out.returncode == 0 and out.stdout.strip():
        return out.stdout.strip()
    sys.exit("FATAL: no ElevenLabs API key")


def write_import_sidecar(ogg: Path) -> None:
    res_path = "res://assets/audio/music/%s" % ogg.name
    md5 = hashlib.md5(res_path.encode()).hexdigest()
    uid = "uid://m%s" % md5[:12]
    sidecar = ogg.with_suffix(ogg.suffix + ".import")
    sidecar.write_text(
        "[remap]\n\n"
        'importer="oggvorbisstr"\n'
        'type="AudioStreamOggVorbis"\n'
        'uid="%s"\n'
        'path="res://.godot/imported/%s-%s.oggvorbisstr"\n\n'
        "[deps]\n\n"
        'source_file="%s"\n'
        'dest_files=["res://.godot/imported/%s-%s.oggvorbisstr"]\n\n'
        "[params]\n\n"
        "loop=false\nloop_offset=0\nbpm=0\nbeat_count=0\nbar_beats=4\n"
        % (uid, ogg.name, md5, res_path, ogg.name, md5))


def main() -> None:
    client = ElevenLabs(api_key=read_api_key())
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    mp3 = OUT_DIR / ("%s.mp3" % NAME)
    ogg = OUT_DIR / ("%s.ogg" % NAME)

    print("composing %.0fs instrumental ..." % (LENGTH_MS / 1000.0))
    audio = client.music.compose(
        prompt=PROMPT,
        music_length_ms=LENGTH_MS,
        model_id="music_v1",
        force_instrumental=True,
        output_format="mp3_44100_128",
    )
    with open(mp3, "wb") as f:
        for chunk in audio:
            f.write(chunk)
    if mp3.stat().st_size == 0:
        sys.exit("FATAL: empty mp3")
    print("wrote %s (%d bytes)" % (mp3.name, mp3.stat().st_size))

    print("converting -> ogg ...")
    subprocess.run(
        ["ffmpeg", "-y", "-i", str(mp3), "-c:a", "libvorbis", "-q:a", "5",
         str(ogg)], check=True, capture_output=True)
    mp3.unlink()
    write_import_sidecar(ogg)
    print("wrote %s (%d bytes) + .import" % (ogg.name, ogg.stat().st_size))


if __name__ == "__main__":
    main()
