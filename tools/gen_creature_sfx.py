#!/usr/bin/env python3
"""Generate creature sound effects (chicken coop bust, bull charge/death) via
ElevenLabs text-to-sound-effects. Offline; the MP3s are committed and played at
runtime by AudioBus.play_sfx(slug). Mirrors the VO generators' key lookup.

Run with the ElevenLabs venv:
  /home/projects/roguelike/.venv-eleven/bin/python tools/gen_creature_sfx.py
"""
from __future__ import annotations
import os, re, sys, subprocess
from pathlib import Path
from elevenlabs.client import ElevenLabs

ROOT = Path(__file__).resolve().parents[1]
OUT_DIR = ROOT / "godot" / "assets" / "sfx" / "creatures"
SFX_OUTPUT = "mp3_22050_32"
SFX_MODEL = "eleven_text_to_sound_v2"

# slug -> (prompt, duration_seconds). Existing files are skipped (saves API spend).
SFX: dict[str, tuple[str, float]] = {
    # --- creatures (iter412) ---
    "chicken_bust": (
        "a flock of panicked cartoon chickens suddenly bursting out, frantic "
        "clucking and squawking, flapping wings, brief and chaotic, comedic",
        2.2),
    "bull_snort": (
        "an angry bull snorting and huffing aggressively, short nostril blast, "
        "ready to charge, cartoon western",
        1.0),
    "bull_bellow": (
        "a big bull bellowing and groaning as it is knocked down, heavy thud, "
        "cartoon western, defeated",
        1.6),
    # --- iter413: offered extras + audit batch ---
    "bull_charge": (
        "heavy bull hooves pounding the dirt galloping fast toward you, dusty "
        "stampede rumble, cartoon western",
        1.4),
    "chicken_cluck": (
        "a few calm chickens softly clucking and pecking in a coop, gentle "
        "barnyard ambience, cartoon",
        2.0),
    "feather_poof": (
        "a soft poof of feathers bursting into the air, light airy whoosh, brief",
        0.8),
    "bonus_pickup": (
        "a bright cheerful candy power-up pickup, sparkling magical chime, short "
        "and rewarding, arcade",
        0.9),
    "gun_reload": (
        "a revolver being reloaded and cocked, cylinder spin and click, western",
        0.8),
    "impact_thud": (
        "a candy projectile splatting into wood, soft wet thud with a little "
        "crunch, short, cartoon",
        0.5),
    "outlaw_down": (
        "a cartoon outlaw grunting and collapsing to the ground, short comedic "
        "defeat, western",
        0.8),
    "win_fanfare": (
        "a short triumphant western victory fanfare, harmonica and brass sting, "
        "celebratory, candy arcade",
        2.2),
    "fail_sting": (
        "a short comedic sad western defeat sting, descending sad trombone with "
        "a harmonica whine",
        1.6),
    # --- iter414: remaining audit gaps ---
    "posse_hurt": (
        "a quick pained yelp and grunt from a cartoon cowboy taking a hit, short, western",
        0.6),
    "hole_fall": (
        "a comedic descending falling whistle ending in a small distant thud, cartoon",
        1.2),
    "puddle_splash": (
        "boots splashing through a shallow water puddle, quick wet splash, cartoon",
        0.7),
    "deputize_join": (
        "a bright heroic sparkle chime with a sheriff badge ding, a new ally joins, rewarding, arcade",
        1.0),
    "gate_step": (
        "a soft pleasant arcade blip ding as a number ticks up, short, candy",
        0.5),
    "outlaw_fire": (
        "a single distant revolver gunshot pop, dry western, short",
        0.6),
    "pete_melee": (
        "a heavy cartoon melee whoosh and body slam impact from a big boss, western",
        0.8),
    "rush_cascade": (
        "a big cascading candy chain reaction, rising sparkles and chimes into a "
        "rewarding burst, candy crush combo",
        2.4),
    "heart_regen_cheer": (
        "a short warm celebratory cheer with a tiny sparkle chime, like a heart "
        "refilling in a candy mobile game, upbeat and brief",
        1.0,
    ),
    # --- winflow: candy victory fanfare ---
    "win_fanfare_candy": (
        "a short triumphant candy-western victory fanfare, bright brass + sparkle, celebratory, ~1.5s",
        1.5,
    ),
    # --- kimmy: rockstar riff ---
    "kimmy_riff": (
        "a triumphant 3-second crescendo electric rock guitar riff, building to a "
        "big rockstar power-chord finish, celebratory, energetic",
        3.0,
    ),
    # --- Level-3 farm cast (terrain branch) ---
    "sfx_candy_corn": (
        "a quick candy pew laser pop, a bright snappy candy gunshot, short, "
        "arcade, cartoon western",
        0.7,
    ),
    "sfx_gummi_bear": (
        "a bouncy rubbery boing with a wet gummy jiggle, a hopping gummy bear "
        "springing, short, cartoon, playful",
        0.9,
    ),
    "sfx_fried_dough": (
        "a sizzling deep-fry crackle then a heavy doughy flump thud, a waddling "
        "fried-dough brute landing, short, cartoon",
        1.2,
    ),
    "sfx_triffid": (
        "a wet plant snap and leafy hiss ending in a quick chomp, a snapping "
        "candy flytrap biting, short, cartoon",
        1.0,
    ),
    "sfx_hot_fudge": (
        "a thick gloopy squelch and gurgling glorp ooze, a squelching fudge blob "
        "moving, short, cartoon",
        1.1,
    ),
    "sfx_pie_splat": (
        "a wet cream and fruit pie splat impact, a thrown cherry pie hitting hard, "
        "short, comedic, cartoon",
        0.8,
    ),
    "sfx_boss_stooges": (
        "a cartoon Three-Stooges slapstick taunt, woob woob woob and nyuk nyuk "
        "nyuk vocals ending in a comedic metal bonk, a goofy cotton-candy trio boss",
        2.6,
    ),
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
    for path in (ROOT / "secrets.env", Path("/home/projects/roguelike/secrets.env")):
        if path.exists():
            for line in path.read_text().splitlines():
                m = re.match(r'\s*ELEVEN_?LABS_API_?key\s*=\s*"?([^"\n]+)"?', line, re.I)
                if m:
                    return m.group(1).strip()
    sys.exit("FATAL: no ElevenLabs API key (env / GSM / secrets.env)")


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    client = ElevenLabs(api_key=read_api_key())
    for slug, (prompt, dur) in SFX.items():
        path = OUT_DIR / f"{slug}.mp3"
        if path.exists():
            print(f"skip {slug} (exists)")
            continue
        print(f"generating {slug} ({dur}s) ...")
        audio = client.text_to_sound_effects.convert(
            text=prompt, duration_seconds=dur,
            output_format=SFX_OUTPUT, model_id=SFX_MODEL)
        with open(path, "wb") as fh:
            for chunk in audio:
                if chunk:
                    fh.write(chunk)
        print(f"  wrote {path} ({path.stat().st_size} bytes)")


if __name__ == "__main__":
    main()
