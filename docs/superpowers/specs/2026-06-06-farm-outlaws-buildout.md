# Farm Outlaws Build-Out — Spec

**Date:** 2026-06-06
**Goal:** Turn the 4 approved Level-3 farm outlaw concepts (Candy Corn, Gummi Bear, Fried Dough, Triffid) into real in-engine enemy TYPES, each with its own billboard art + animation, movement style, and offense/defense. Concepts in `docs/superpowers/assets/farm_cast_2026-06-06/`.

## Engine surface (how outlaws work today)
- `_spawn_outlaw()` (level_3d.gd) makes a `Node3D` with a `_make_video_billboard(...)` child, meta `hp`/`fire_timer`/`track_offset_x`/`is_outlaw`/`dying`, HP bar, added to `outlaws_root`. All outlaws are one "vagrant" type.
- The per-frame outlaw loop advances z (`OUTLAW_SPEED`), x-tracks the cowboy (+ per-unit offset), slows near the posse, fires via `_outlaw_fire` every `OUTLAW_FIRE_INTERVAL` (3.6s) within `OUTLAW_FIRE_RANGE_Z` (10), and runs bullet↔outlaw collision (`OUTLAW_HIT_RADIUS_SQ`).
- `OUTLAW_HP=10`, `OUTLAW_SPEED=1.5`.

## Architecture: an `outlaw_kind` system
Add a `kind` meta to each outlaw. `_spawn_outlaw(kind := "vagrant")` picks per-kind art/HP/meta; the outlaw loop branches on `kind` for movement + offense; collision branches for defense; a per-kind procedural animation runs each frame. Per-level the spawner chooses kinds from the level's roster (farm → the 4 below; other levels keep "vagrant"). **No Veo needed** — each outlaw is a matted billboard sprite (green-screen re-render → matte) animated PROCEDURALLY (sway + per-kind motion), mobile-safe.

## Art (asset step)
Re-render each of the 4 outlaws on a **green plate** and matte to a transparent billboard sprite → `godot/assets/sprites/props/outlaw_<kind>.png` (candy_corn / gummi_bear / fried_dough / triffid). (The current concept PNGs have farm backgrounds; billboards need alpha.) Reuse the project's green-key matte pipeline.

## Per-outlaw specs

### 1. Candy Corn — RANGED KITER
- **Art/anim:** tri-color kernel gunslinger; idle **sway** (breathing shader) + a quick **recoil lean** on each shot.
- **Movement:** advances, then **HOLDS at mid-range** (stops closing at ~`cowboy.z − 6`) to snipe — a kiter that keeps its distance.
- **Offense:** ranged **triple-volley** — fires 3 candy-corn bullets in a fast burst each `~3.6s` (extend `_outlaw_fire` with a 3-shot burst for this kind).
- **Defense:** standard. **HP 10.**

### 2. Gummi Bear — BOUNCY CLOSER
- **Art/anim:** translucent jiggly bear; **hop** (sine y-arc) toward the posse with **squash-on-land / stretch-at-apex**.
- **Movement:** **hops** toward the posse (closer; effective speed `OUTLAW_SPEED×1.3`), not a straight glide.
- **Offense:** **contact** — bounces into the posse and drains a member on contact (no projectile).
- **Defense:** **hard to hit** — only takes bullet damage near the **apex of its hop** (mid-air, stretched); bullets "pass through" while it's squashed/grounded. **HP 8** but evasive.

### 3. Fried Dough — MELEE RUSHER
- **Art/anim:** pudgy funnel-cake bandit; **waddle wobble** + a **lunge** on attack.
- **Movement:** **rushes** the posse fast (`OUTLAW_SPEED×1.6`), closing to melee.
- **Offense:** **melee** — a heavy contact hit when it reaches the posse.
- **Defense:** **tanky** beefcake. **HP 16.**

### 4. Triffid — ROOTED LASHER
- **Art/anim:** snapping candy flytrap on a licorice vine; **rooted sway** + a **lash snap** (head whips forward, quick scale/rotate) on attack.
- **Movement:** **ROOTED** — sprouts in a fixed lane and does NOT advance on the posse; it just scrolls in with the world. (Skip the x-track + z-advance for this kind.)
- **Offense:** **reach-lash** — when the posse is within a short z-range, it lashes and hits members in its lane (a melee whip with reach, on a cooldown).
- **Defense:** rooted, can't dodge, **tanky HP 14.**

## Placement (level_3.tres)
Add the farm roster to Level 3 so `_spawn_outlaw` draws from {candy_corn, gummi_bear, fried_dough, triffid} (weights TBD). Keep the existing quota; these replace the generic vagrants on the farm.

## Verification
- GUT for any pure helper (e.g. kind→stats table, gummi apex-hittable check) if extracted.
- sp1-screenshot via a temp force-spawn of each kind to confirm the billboard + animation read.
- Device: each outlaw's movement + offense/defense feel on L3.

## Open questions
- Roster weights (how common each kind)? Boss gating (does the Cotton Candy boss arrive after a quota like Pete)?
- Gummi "apex-only" hit: keep it strict (only at apex) or just reduced-damage while grounded?
- Triffid: cluster in patches (sprout in 2-3s) or singles?
