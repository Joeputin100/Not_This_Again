#!/usr/bin/env python3
"""Generate Professor Humbug's voice lines via ElevenLabs.

Renders one MP3 per level-selector line (tip / thought / easter-joke) AND
per main-menu tap-to-banter line. The level-selector SPEECH-BUBBLE text is
read straight from godot/assets/text/en.json (the single source of truth)
— keep this script and en.json in sync by re-running after editing the
humbug lines. The 6 main-menu lines have no on-screen text (they are
audio-only banter); their verbatim source text lives in MENU_LINES below.

The SPOKEN line is NOT a verbatim read of the bubble text. Each line is
transformed at render time into a "King Candy" performance before being
sent to ElevenLabs (see PERFORMANCE below). en.json is never modified —
only the API payload is respelled and tagged.

PERFORMANCE — every line sent to ElevenLabs gets all three of:
  1. Phonetic lisp respelling: "s" sounds rewritten as "th" (yes->yeth,
     Professor->Profethor). "sh" / "ch" sounds are left alone. Respelled
     by hand per line (LISP_LINES below) so words don't mangle.
  2. [lisp] tags, roughly one at the start of each sentence / clause.
  3. [giggles] tags at playful / punchy beats and line ends.
Style reference: the COMBINED_LISP A/B/C/D test sample the user approved.

Voice: ElevenLabs PRZec1rpHH9FRamLcdLq, model eleven_v3 (the audio tags
above require eleven_v3).

Run with the roguelike ElevenLabs venv (it has the SDK + the key):
  /home/projects/roguelike/.venv-eleven/bin/python tools/gen_humbug_vo.py

Key lookup: $ELEVENLABS_API_KEY / $ELEVEN_LABS_API_KEY, else a secrets.env
(this repo's, else the roguelike project's).

Output: godot/assets/audio/characters/humbug_{tip,thought,joke,menu}_<n>.mp3

Render scope: pass "menu" to render ONLY the 6 main-menu clips (leaves the
already-rendered selector clips untouched); pass "selector" for only the
tip/thought/joke clips; no argument renders everything.
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
HUMBUG_VOICE = "PRZec1rpHH9FRamLcdLq"   # ElevenLabs — Humbug's "King Candy" voice
MODEL = "eleven_v3"                     # required for [lisp] / [giggles] tags
OUTPUT_FMT = "mp3_44100_128"
# en.json  humbug.<key>  array  ->  humbug_<slug>_<n>.mp3
GROUPS = {"tips": "tip", "thoughts": "thought", "easter_jokes": "joke"}

# Render-time "King Candy" performance: maps each en.json line (verbatim) to
# its lisped + [lisp]/[giggles]-tagged spoken version. en.json itself stays
# normal-spelled — only this API payload is transformed. Hand-respelled per
# line ("s" -> "th", "sh"/"ch" left intact) so words don't mangle. If a line
# is edited in en.json without updating this map, lisp_perform() falls back
# to a plain tagged read so the build never silently breaks.
LISP_LINES = {
    # --- tips ---
    "Choose the MULTIPLY doors, my sugar-dusted darlings — a posse grows "
    "grandest by ×, never by mere addition!":
        "[lisp] Chooth the MULTIPLY doorth, my thugar-duthted darlingth "
        "[giggles] — a pothy growth grandetht by multiplying, [lisp] never "
        "by mere addithion! [giggles]",

    "Mind the DIVIDE gates! Naught thins a posse faster than careless "
    "division. A capital blunder, that.":
        "[lisp] Mind the DIVIDE gateth! [giggles] [lisp] Naught thinth a "
        "pothy fathter than careleth divithion. [lisp] A capital blunder, "
        "that. [giggles]",

    "Keep that trigger-finger lively — an empty six-shooter reloads itself, "
    "but oh, the DRAMA of the pause!":
        "[lisp] Keep that trigger-finger lively [giggles] — an empty "
        "thix-shooter reloadth itthelf, [lisp] but oh, the DRAMA of the "
        "pauth! [giggles]",

    "Swerve, my darlings, SWERVE! A cactus is no respecter of a fine hat.":
        "[lisp] Thwerve, my darlingth, THWERVE! [giggles] [lisp] A cactuth "
        "ith no rethpecter of a fine hat. [giggles]",

    "The boss is all bluster and brittle wrapper. Stand firm, fire true, "
    "and do give him a proper send-off.":
        "[lisp] The both ith all bluthter and brittle wrapper. [giggles] "
        "[lisp] Thtand firm, fire true, [lisp] and do give him a proper "
        "thend-off. [giggles]",

    "A wider posse breaks a barricade sooner — numbers, my dears, are the "
    "truest gunslinger of all!":
        "[lisp] A wider pothy breakth a barricade thooner [giggles] — "
        "numberth, my dearth, [lisp] are the truetht gunthlinger of all! "
        "[giggles]",

    # --- thoughts ---
    "I do wonder if Monsieur Canard dreams of ponds...":
        "[lisp] I do wonder [giggles] if Monthieur Canard dreamth of "
        "pondth... [giggles]",

    "Forty years on the frontier, and still that monocle fogs at the worst "
    "moment.":
        "[lisp] Forty yearth on the frontier, [lisp] and thtill that "
        "monocle fogth at the wortht moment. [giggles]",

    "Was I ever truly an outlaw — or merely a man who announced himself "
    "politely?":
        "[lisp] Wath I ever truly an outlaw [giggles] — or merely a man "
        "who announthed himthelf politely? [giggles]",

    "One peppermint stripe for every honest day. I have quite run out of "
    "trouser.":
        "[lisp] One peppermint thtripe for every honetht day. [giggles] "
        "[lisp] I have quite run out of trouther. [giggles]",

    "Somewhere a sheriff is being dreadfully unreasonable. I can feel it.":
        "[lisp] Thomewhere a sheriff ith being dreadfully unreathonable. "
        "[giggles] [lisp] I can feel it. [giggles]",

    # --- easter_jokes ---
    "Are you still touching me?":
        "[lisp] Are you thtill touching me? [giggles]",

    "Hee hee hee! That tickles.":
        "[giggles] Hee hee hee! [lisp] That tickleth. [giggles]",

    "I am not listening.":
        "[lisp] I am not lithtening. [giggles]",
}

# Main-menu tap-to-banter lines. Unlike the selector lines these have NO
# en.json entry — they are audio-only (played by main_menu.gd straight from
# humbug_menu_<n>.mp3, no speech bubble). This list is therefore the
# verbatim source text. Each tuple is (verbatim, performance): the spoken
# version gets the SAME "King Candy" treatment as LISP_LINES — hand
# phonetic-lisp respelling ("s" -> "th"; "sh"/"ch" left intact, e.g.
# "shall", "shoe", "Monsieur" -> "Monthieur") plus [lisp] / [giggles] tags.
MENU_LINES = [
    ("Ah, a poke? How delightfully forward. Professor Humbug at your "
     "service and the Academy's.",
     "[lisp] Ah, a poke? [giggles] How delightfully forward. [lisp] "
     "Profethor Humbug at your thervithe [lisp] and the Academy'th. "
     "[giggles]"),

    ("Patience, my sugar-dusted darling. The training trail opens soon. "
     "I shall make a legend of you or a cautionary tale, either is "
     "educational.",
     "[lisp] Patienthe, my thugar-duthted darling. [giggles] [lisp] The "
     "training trail openth thoon. [lisp] I shall make a legend of you "
     "or a cautionary tale, [lisp] either ith educational. [giggles]"),

    ("You have the look of a natural. Monsieur Canard disagrees, pay him "
     "no mind.",
     "[lisp] You have the look of a natural. [giggles] [lisp] Monthieur "
     "Canard dithagreeth, [lisp] pay him no mind. [giggles]"),

    ("Mind the monocle. It cost me a stagecoach. It did not. But it "
     "should have.",
     "[lisp] Mind the monocle. [lisp] It coth me a thtagecoach. "
     "[giggles] [lisp] It did not. [lisp] But it should have. [giggles]"),

    ("When the academy opens, I shall teach you the noble arts— the "
     "saunter, the salute, the six-shooter soft shoe. Riveting stuff.",
     "[lisp] When the academy openth, [lisp] I shall teach you the "
     "noble artth [giggles] — the thaunter, the thalute, [lisp] the "
     "thix-shooter thoft shoe. [lisp] Riveting thtuff. [giggles]"),

    ("Monsieur Canard and I have all the time in the world for you, he "
     "just quacked. He means it, mostly.",
     "[lisp] Monthieur Canard and I have all the time in the world for "
     "you, [giggles] he jutht quacked. [lisp] He meanth it, mothtly. "
     "[giggles]"),
]


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
                m = re.match(r'\s*ELEVEN_?LABS_API_?key\s*=\s*"?([^"\n]+)"?',
                             line, re.I)
                if m:
                    return m.group(1).strip()
    sys.exit("FATAL: no ElevenLabs API key (env / GSM / secrets.env)")


def for_speech(text: str) -> str:
    """Bubble glyphs the TTS shouldn't read literally."""
    return (text.replace("×", "multiplying")   # ×
                .replace("÷", "dividing")       # ÷
                .replace(" — ", ", ")           # spaced em-dash → pause
                .replace("—", ", "))


def lisp_perform(line: str) -> str:
    """Render-time 'King Candy' transform of one en.json line.

    Returns the hand-respelled, [lisp]/[giggles]-tagged spoken version from
    LISP_LINES. If the line is not in the map (e.g. en.json was edited
    without updating LISP_LINES), fall back to a plain [lisp]-prefixed,
    [giggles]-suffixed read of the glyph-cleaned text so the build still
    produces audible audio and the mismatch is loud in the console.
    """
    spoken = LISP_LINES.get(line)
    if spoken is not None:
        return spoken
    print("  WARN line not in LISP_LINES — plain tagged fallback: %r" % line)
    return "[lisp] %s [giggles]" % for_speech(line)


def render(client: ElevenLabs, dst: Path, spoken: str) -> None:
    """Convert one spoken line to MP3 at dst."""
    audio = client.text_to_speech.convert(
        voice_id=HUMBUG_VOICE,
        text=spoken,
        model_id=MODEL,
        output_format=OUTPUT_FMT,
    )
    with open(dst, "wb") as f:
        for chunk in audio:
            f.write(chunk)
    print("wrote %-22s  %s" % (dst.name, spoken[:56]))


def main() -> None:
    # Optional scope arg: "menu" (only the 6 main-menu clips), "selector"
    # (only the en.json tip/thought/joke clips), or nothing (everything).
    scope = sys.argv[1] if len(sys.argv) > 1 else "all"
    if scope not in ("all", "menu", "selector"):
        sys.exit("usage: gen_humbug_vo.py [all|menu|selector]")
    client = ElevenLabs(api_key=read_api_key())
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    if scope in ("all", "selector"):
        humbug = json.loads(EN_JSON.read_text())["humbug"]
        for key, slug in GROUPS.items():
            for i, line in enumerate(humbug[key]):
                dst = OUT_DIR / ("humbug_%s_%d.mp3" % (slug, i))
                render(client, dst, lisp_perform(line))

    if scope in ("all", "menu"):
        for i, (verbatim, spoken) in enumerate(MENU_LINES):
            dst = OUT_DIR / ("humbug_menu_%d.mp3" % i)
            render(client, dst, spoken)


if __name__ == "__main__":
    main()
