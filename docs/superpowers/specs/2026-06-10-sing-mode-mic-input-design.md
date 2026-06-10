# Sing Mode — Microphone Input for the Level-6 Sing-Duel — Design Spec

**Date:** 2026-06-10
**Status:** Design approved in chat (toggle placement, bleed mitigation, bad-take handling, debug access all signed off). Ships WITH Level 6 v1 — not deferred.
**Related:** [Queen of the Night design](2026-06-08-queen-of-the-night-design.md), [[project_queen_sing_mic_mode]], [[project_debug_menu]].

---

## 1. Concept

The Level-6 sing-duel gains an **optional microphone input mode**: instead of swiping the phrase contour, the player **sings/hums it back**. The mic's pitch-over-time curve becomes the same point series a swipe produces and is scored by the **unchanged** `QueenDuelState.score_trace` — its position/scale invariance gives octave-and-key forgiveness for free (only the melody's *shape* matters).

**Swipe stays the default.** Sing is opt-in per attempt.

## 2. Locked decisions (owner, 2026-06-10)

| Decision | Choice |
|---|---|
| Toggle placement | **Choice before the fight** — modal when the Queen engages: "How will you answer the Queen?" SWIPE (default-highlighted) / SING. Holds for the attempt; re-asked on retry. |
| Speaker→mic bleed | **Both**: duck game audio to a hush during the player's response window (doubles as opera-drama) AND a one-time "best with headphones" hint on first-ever SING pick. |
| Empty/noisy take | **Gentle retry**: first silent window per fight = no penalty + HUD nudge ("Sing out, sugar — she can't hear you!"); subsequent = normal miss (drain). |
| Tutorial | Papageno duet stays **swipe-only** (teaches the shapes; no permission popups in the comedy beat). |
| Debug access | **Both sing minigames in the debug menu**: "QUEEN SING-DUEL" and "PAPAGENO DUET" buttons jump straight into each on Level 6. |

## 3. Components

1. **`mic_pitch_tracker.gd`** (`class_name MicPitchTracker extends RefCounted`, pure, GUT-tested on CI): consumes mono float frames + sample rate; autocorrelation pitch per hop (~46 ms); emits a normalized curve `Array[Vector2]` of (time, −log2(pitch)) — negated so higher pitch = smaller y = up on screen, matching contour space; tracks `voiced_frames` so the caller can detect an empty take. Range clamp ~80–1000 Hz; unvoiced hops (low autocorr peak / low energy) skipped.
2. **`mic_capture.gd`** (`extends Node`, runtime glue, parse-tested): owns the Record audio bus + `AudioStreamMicrophone` player + `AudioEffectCapture`; `start()`/`stop()`; polls captured frames in `_process` into a `MicPitchTracker`; `curve()` and `voiced()` pass-throughs. Handles `audio/driver/enable_input` and is inert on platforms without a mic.
3. **Pre-fight choice modal** (built in code inside `level_3d.gd`, level-start-modal style): two candy buttons; SING requests `RECORD_AUDIO` permission (`OS.request_permission`); denial ⇒ falls back to SWIPE with a polite HUD note. Modal pauses the duel start (Queen intro fires after the pick).
4. **`level_3d.gd` glue:** in SING mode, `response_open` ⇒ duck audio (Master bus dim) + `mic.start()` + live trail (`_sing_fx.feed_point` fed from the tracker's latest curve point mapped to the contour band); window end ⇒ `mic.stop()`, restore audio, map curve → screen-space points → `submit_swipe(points)` (unchanged). Empty-take = first-time nudge / then miss. One-time headphone hint via a persisted `GameState` flag.
5. **Android plumbing:** `permissions/record_audio=true` in `export_presets.cfg`; `audio/driver/enable_input=true` in `project.godot` (input stream only opens when the Record bus is active).
6. **Debug menu:** `DebugPreview.pending_queen_duel` / `pending_papageno_duet` flags (the established pattern); `level_3d._ready` consumes them — forces Level 6 context, skips the run, triggers the boss engage (with mode modal) or the tutorial immediately.

## 4. Scoring & fairness

- The curve is normalized exactly like a swipe (resample + unit-box) — **no new scoring rules**, same `GOOD_THRESHOLD`, damage and drain.
- Time axis = window time; pitch axis = −log2(Hz) (relative pitch; key/octave independent after box-normalization).
- Tutorial-mode (`QueenDuelState.new(true)`) still never penalizes, so if SING is later allowed in the tutorial nothing breaks.

## 5. Out of scope (YAGNI)

Absolute-pitch grading; vibrato/timing micro-analysis; echo cancellation; recording storage of ANY kind (frames are processed and discarded — say so in the privacy policy); sing mode for the Papageno tutorial; iOS specifics.

## 6. Testing

- `test_mic_pitch_tracker.gd` (GUT, CI): synthesized sine (440 Hz) → detected within tolerance; rising sweep → monotonic curve y-decrease; silence/white-noise → no voiced frames; chirp split across pushes → hop continuity.
- Parse coverage: `mic_capture.gd` + new `level_3d.gd` code paths compile in headless CI (the established guarantee).
- Mic hardware, permission flow, duck feel, threshold tuning: **device pass only** (owner's phone).
