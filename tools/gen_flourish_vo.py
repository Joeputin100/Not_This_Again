#!/usr/bin/env python3
"""Generate the FlourishBanner celebration voice-overs via ElevenLabs.

Renders one MP3 per flourish banner to
godot/assets/audio/flourishes/flourish_<slug>.mp3 — the 21 files covering
the regular flourishes, the Sugar Rush flourishes (JELLY_FRENZY,
SUGAR_CASCADE) and the Gold Rush event flourishes (AVALANCHE, STAMPEDE,
LOCOMOTIVE, etc).

SOURCE OF TRUTH — the spoken words are the `text` field of each entry in
the PRESETS dictionary in godot/scripts/flourish_banner.gd. The MP3 slug
is the PRESETS *key* lowercased with any trailing "!" removed
("TASTY!" -> flourish_tasty.mp3), but the spoken text is the *text* field
of that preset (preset TASTY! displays/says "ACCEPTABLE."). flourish_banner.gd
is never modified — this script only re-renders the audio.

PERFORMANCE — these are short, punchy celebration shouts. Each line is
sent with ElevenLabs delivery tags (eleven_v3 supports inline tags) chosen
per the banner's mood, per [[project_flourish_voiceover]]:
  - Loud cause-and-effect banners (DOUBLE!/MEGA!/YEEHAW!/RAMPAGE! and the
    Gold Rush cascade finales) get hyped [excited]/[shouting] delivery.
  - The Murderbot-narrator quality banners (ACCEPTABLE./EFFICIENT./
    ADEQUATE./RELUCTANTLY COMPETENT.) get a dry, deadpan, world-weary read.
  - The 3D-preview countdown (READY / 3 / 2 / 1 / GO) gets a clean,
    punchy announcer read.
The words themselves are kept verbatim to flourish_banner.gd's `text`
field — only the delivery tags differ.

Voice: ElevenLabs 61Qg29Wr3AuLLXn122Hd, model eleven_v3 (inline audio
tags require eleven_v3).

Run with the roguelike ElevenLabs venv (it has the SDK + the key):
  /home/projects/roguelike/.venv-eleven/bin/python tools/gen_flourish_vo.py

Key lookup: $ELEVENLABS_API_KEY / $ELEVEN_LABS_API_KEY, else Google
Secret Manager (secret ELEVENLABS_API_KEY), else a secrets.env (this
repo's, else the roguelike project's).

Output: godot/assets/audio/flourishes/flourish_<slug>.mp3
"""
import os
import re
import subprocess
import sys
from pathlib import Path

from elevenlabs.client import ElevenLabs

ROOT = Path(__file__).resolve().parents[1]
OUT_DIR = ROOT / "godot" / "assets" / "audio" / "flourishes"
FLOURISH_VOICE = "61Qg29Wr3AuLLXn122Hd"   # ElevenLabs — new flourish voice
MODEL = "eleven_v3"                        # required for inline delivery tags
OUTPUT_FMT = "mp3_44100_128"

# slug -> (spoken text from flourish_banner.gd PRESETS `text` field,
#          delivery-tag prefix tuned to that banner's mood).
# The slug is the PRESETS key lowercased with trailing "!" dropped.
# Keep this list in sync with flourish_banner.gd's PRESETS dictionary.
FLOURISHES = {
    # --- loud cause-and-effect combo banners: full hype ---
    "double":         ("DOUBLE!",                "[excited]"),
    "mega":           ("MEGA!",                  "[excited, shouting]"),
    "yeehaw":         ("YEEHAW!",                "[excited, shouting]"),
    "rampage":        ("RAMPAGE!",               "[shouting, intense]"),
    # --- Murderbot-narrator quality banners: dry, deadpan ---
    "tasty":          ("ACCEPTABLE.",            "[deadpan, unimpressed]"),
    "juicy":          ("EFFICIENT.",             "[deadpan, dry]"),
    "sweet":          ("ADEQUATE.",              "[deadpan, unimpressed]"),
    "flawless":       ("RELUCTANTLY COMPETENT.", "[deadpan, grudging]"),
    # --- Sugar Rush flourishes: big celebratory hype ---
    "jelly_frenzy":   ("JELLY BEAN FRENZY!",     "[excited, shouting]"),
    "sugar_cascade":  ("SUGAR CASCADE!",         "[excited, shouting]"),
    # --- Gold Rush cascade-finale flourishes: big celebratory hype ---
    "perfect_volley": ("PERFECT VOLLEY!",        "[excited]"),
    "rolled":         ("ROLLED!",                "[excited]"),
    "chain":          ("CHAIN!",                 "[excited, shouting]"),
    "locomotive":     ("LOCOMOTIVE!",            "[excited, shouting]"),
    "avalanche":      ("AVALANCHE!",             "[shouting, intense]"),
    "stampede":       ("STAMPEDE!",              "[shouting, intense]"),
    # --- 3D-preview start countdown: clean punchy announcer ---
    "ready":          ("READY",                  "[announcer]"),
    "count_3":        ("3",                      "[announcer]"),
    "count_2":        ("2",                      "[announcer]"),
    "count_1":        ("1",                      "[announcer]"),
    "go":             ("GO",                     "[excited, shouting]"),
}


def read_api_key() -> str:
    for env in ("ELEVENLABS_API_KEY", "ELEVEN_LABS_API_KEY"):
        val = os.getenv(env)
        if val:
            return val
    # Google Secret Manager — the key lives at secret ELEVENLABS_API_KEY.
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


def main() -> None:
    client = ElevenLabs(api_key=read_api_key())
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    written = 0
    for slug, (text, tag) in FLOURISHES.items():
        dst = OUT_DIR / ("flourish_%s.mp3" % slug)
        spoken = "%s %s" % (tag, text)
        audio = client.text_to_speech.convert(
            voice_id=FLOURISH_VOICE,
            text=spoken,
            model_id=MODEL,
            output_format=OUTPUT_FMT,
            apply_text_normalization="on",  # ElevenLabs best-practice: force text normalization
        )
        with open(dst, "wb") as f:
            for chunk in audio:
                f.write(chunk)
        size = dst.stat().st_size
        if size == 0:
            sys.exit("FATAL: %s rendered empty" % dst.name)
        written += 1
        print("wrote %-26s %6d bytes  %s" % (dst.name, size, spoken))
    print("\ndone: %d / %d flourish VO files rendered" % (written, len(FLOURISHES)))


if __name__ == "__main__":
    main()
