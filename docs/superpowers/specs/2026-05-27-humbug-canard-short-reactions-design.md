# Humbug + Canard Short Reactions — Design

**Date:** 2026-05-27
**Status:** Brainstorm captured; pending implementation
**Scope:** Splash screen + level selector only — tutorial levels keep their existing verbal VO

## Why

Current menu reactions for Professor Humbug and his Canard sidekick use full verbal lines (`humbug_menu_0–5.mp3`), which feel laggy and grating on rapid touch. Candy Crush / Candy Crush Soda use sub-second non-verbal vocalizations on character touch — the player gets immediate cute feedback without committing the audio bus to a 3-second line. This spec aligns the menu/splash interactions with that idiom while preserving the existing tutorial VO and the existing annoyed-response verbal line for intentional rapid-tap.

## Goals

- Single tap → short non-verbal vocalization (1 syllable, <500 ms) + matching motion
- Rapid tap (5 within 2 sec) → existing annoyed verbal line (re-use one of the existing menu lines or generate a dedicated one)
- 5 reaction variants per character, random no-repeat selection
- Tutorial levels untouched — `humbug_tip_*`, `humbug_thought_*`, `humbug_joke_*` all keep firing as before

## Non-Goals

- Re-recording the tutorial VO
- Changing Canard's gameplay role
- Generating new voice clones (the existing ElevenLabs voice IDs for Humbug + Canard are reused)

## Audio Spec

### Humbug — 5 short reaction variants (~300–500 ms each)

| File | Prompt sketch |
|------|---------------|
| `humbug_react_harumph.mp3` | Short curmudgeonly "harumph" / throat-clear, single syllable, dry character |
| `humbug_react_snort.mp3` | Single quick nose-snort, dismissive but warm |
| `humbug_react_hmm.mp3` | Pondering "hmmm" with a tiny rise at the end, brief |
| `humbug_react_huff.mp3` | Sigh-huff, single exhale, slightly amused |
| `humbug_react_tut.mp3` | A "tut-tut" cluck, two quick syllables, friendly disapproval |

Voice ID: same as existing humbug VO (`reference_elevenlabs_vo` memory).

### Canard — 5 short reaction variants (~300–500 ms each)

| File | Prompt sketch |
|------|---------------|
| `canard_react_quack.mp3` | Single short duck-cane quack |
| `canard_react_giggle.mp3` | One-shot bright giggle, ~half second |
| `canard_react_squeak.mp3` | Rubber-duck squeak, single syllable |
| `canard_react_honk.mp3` | Short cartoony honk, half syllable |
| `canard_react_chitter.mp3` | Quick chatter-burst, like a brief amused mumble |

Voice/SFX style: matches existing `canard_quack_*` aesthetic — squeaky-cane character (`project_professor_humbug` memory).

### Annoyed response (rapid tap, ≥5 within 2 sec)

Re-use one existing menu line for now (e.g. `humbug_menu_3.mp3` if it sounds annoyed-friendly). If none fit, generate one dedicated:
- `humbug_annoyed.mp3`: short verbal line like "Now, now — that tickles!" or "I'm trying to think over here!" — 2 sec max, single take.

## Animation Spec

Each reaction variant has a matching motion. Two possible sources:

1. **Existing atlases**: `humbug_tip.png` (head-bob), `humbug_thought.png` (puzzled scratch), `humbug_canard.png` (canard wing-flap). Each is a short looping animation in an atlas.
2. **New Veo clips** for variants without a fitting existing animation.

### Pairing strategy

| Variant | Animation source |
|---------|------------------|
| harumph | re-use `humbug_tip` (head-bob fits a harumph) |
| snort   | NEW Veo clip — quick nose-twitch + recoil, 1.5 sec |
| hmm     | re-use `humbug_thought` (pondering scratch matches "hmm") |
| huff    | NEW Veo clip — shoulder-rise + drop, 1.5 sec |
| tut     | NEW Veo clip — finger-wag + head-shake, 1.5 sec |

| Canard variant | Animation source |
|---------|------------------|
| quack   | re-use `humbug_canard` (existing wing-flap) |
| giggle  | NEW Veo clip — head-tilt with body-shake, 1.5 sec |
| squeak  | NEW Veo clip — quick squeeze-compress (the cane handle is rubber), 1.5 sec |
| honk    | NEW Veo clip — beak-open beak-close, 1.5 sec |
| chitter | NEW Veo clip — fast head-jiggle, 1.5 sec |

Total new Veo clips: 7 × ~$0.20 = ~$1.40.

## Trigger Logic

```gdscript
const ANNOYED_THRESHOLD := 5
const ANNOYED_WINDOW_SEC := 2.0

var _tap_times: Array[float] = []
var _last_variant := {"humbug": "", "canard": ""}

func _on_character_tap(body_key: String) -> void:
    var now := Time.get_ticks_msec() / 1000.0
    _tap_times = _tap_times.filter(func(t): return now - t < ANNOYED_WINDOW_SEC)
    _tap_times.append(now)
    if _tap_times.size() >= ANNOYED_THRESHOLD:
        _play_annoyed(body_key)
        _tap_times.clear()
    else:
        _play_random_short(body_key)
```

## Integration

- `godot/scripts/main_menu.gd` — find existing humbug/canard tap handlers and route through new logic
- `godot/scripts/level_select.gd` — same
- DO NOT touch `godot/scripts/level_3d.gd` (in-game tutorial code path stays verbal)
- Probably worth a shared `scripts/sky_react.gd` or `scripts/character_react.gd` helper since both menu/select use the same logic

## Files

**New:**
- `godot/assets/audio/characters/humbug_react_*.mp3` × 5
- `godot/assets/audio/characters/canard_react_*.mp3` × 5
- `godot/assets/audio/characters/humbug_annoyed.mp3` (maybe — if re-use doesn't fit)
- `godot/assets/sprites/atlases/humbug_snort.png` + `.atlas.json` (and 6 more for the NEW Veo clips listed above)
- `scripts/gen_humbug_canard_reactions.py` — ElevenLabs wrapper for the 10 new reactions

**Modified:**
- `godot/scripts/main_menu.gd`
- `godot/scripts/level_select.gd`
- `godot/scenes/main_menu.tscn` (if AudioStreamPlayer wiring changes)

## Existing assets audit (2026-05-27)

- 3 existing humbug video clips → atlases: `tip`, `thought`, `canard`
- 6 existing `humbug_menu_*.mp3` verbal lines (to be DEPRECATED for menu — keep as fallback options for annoyed-response)
- 3 existing `canard_quack_*.mp3` (to be REPLACED by 5 new short reactions)
- Tutorial VO untouched: `humbug_tip_*`, `humbug_thought_*`, `humbug_joke_*`

## Open Questions

- Should the menu-screen animation play on EVERY tap, or only when the sound's duration warrants it? (Tap-while-animating: queue, interrupt, or ignore?)
- For variants whose existing animation gets re-used, should the animation be SHORTENED on the menu (loop a sub-range) so it doesn't feel long while a 400ms sound plays?

Both deferred to implementation review.
