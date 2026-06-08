# Granny's Chicken Chase — Minigame Design Spec

**Date:** 2026-06-08
**Status:** Design approved (loop, reward, daily gate, entry, Candy Granny look all signed off in chat). Ready for implementation planning.
**Related:** [[project_chicken_minigame_boosters]], the win/retry flow ([2026-06-04 winflow spec]), the farm cast ([2026-06-06-farm-cast-design.md]), the level-select decoration plan.

---

## 1. Concept

A short, optional **booster-earning minigame**: **Candy Granny** — a sly, hunched candy-witch with a cackle and a bubbling cauldron — guilts the cowboy into rounding up chickens the **posse set loose when it smashed their coops** mid-firefight. The cowboy agrees out of guilt. The chickens are slippery and hard to catch. Your haul is brewed into a **Posse Brew** that reinforces your next level.

A "nice diversion" — bite-sized, comedic, family-friendly, and **never pay-to-win** (the reward is earned, not bought). Tone: PG comic mischief — Granny *looks* like she might be up to something with that cauldron, but it never turns actually menacing.

---

## 2. The Loop — a mini auto-runner

Reuses the main game's 3D auto-runner, shrunk to a single self-contained chase:

- **Setting:** a short, sunny lane on the existing **farm terrain theme**, starting at a **busted chicken coop** (the guilt callback — feathers everywhere). No outlaws, gates, pits, or obstacles — *only chickens.*
- **Duration:** a fixed **allotted time** (≈25 s, device-tuned) — the length of the lane. There is **no hard fail**; the run simply ends when time/lane runs out.
- **The cowboy auto-runs** forward (same movement/steering code as the main game). The player **swipes left/right** to steer toward birds.
- **A flock of 8 popcorn chickens** flutters ahead, juking, hopping, and scattering. The hens are **made of popcorn** — puffed-popcorn bodies, little kernel beaks, butter-yellow tufts (owner-loved detail). Restyle of the existing chicken sprites into the popcorn look.
- **Catch input:** tap/flick toward a nearby chicken → the cowboy performs a **lunge-grab** (a quick dive) with a short **recovery window** so mashing doesn't work.
- **Chickens are slippery:** a chicken in range can **juke at the last instant** — telegraphed by a wind-up *cluck* + feather puff — so a mistimed lunge **whiffs** and the bird scoots past. Catching cleanly means reading the juke.
- **Score = your haul:** the `caught / 8` counter is the score. Uncaught hens at the end simply don't count.

**Fairness principle:** because it's one attempt per day (§4) *and* the reward is proportional (§3), the run should feel rewarding at any skill level — a focused player can sweep all 8, a sloppy run still nets a few. The difficulty is in **maximizing** the haul (reading jukes, not whiffing), never in raw speed or luck.

---

## 3. Reward — the proportional Posse Brew

Granny ladles a **Posse Brew** sized to your haul. The brew grants a **one-shot bonus to your starting posse on the next level played**, scaling linearly **+0 to +20 cowboys for 0–8 chickens** (≈2.5 per hen, rounded):

| Caught | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 |
|--------|---|---|---|---|---|---|---|---|---|
| **+Starting posse** | 0 | 3 | 5 | 8 | 10 | 13 | 15 | 18 | 20 |

Formula: `bonus = round(caught / 8 * 20)`.

- The bonus is stored as a **pending one-shot booster** and **consumed at the start of the next level** (added to the level's starting posse count), then cleared. It does not stack across levels or persist after use.
- **Granny's reaction scales:** full sweep (8) → big cackle + brimming ladle; partial → "well, a few'll have to do"; **zero → she grumbles, no brew** (but the attempt is still spent — see §4).

---

## 4. The 24-hour gate — one attempt per day

- The player gets **one attempt per rolling 24 hours**, win-much or win-little. The attempt is **spent the moment a run actually begins** (not when Granny is offered).
- On run end, `GameState` records the timestamp; the cauldron is **cold for 24 h**. A readable countdown ("ready in 7:42") is available wherever Granny's state shows.
- One attempt + proportional reward means a single run is **never wasted** (any catch ≥1 pays out), but a clean 8 is worth pushing for.

---

## 5. Entry — Granny pops up when ready (+ safeguard)

- When the 24 h cooldown is up, **Candy Granny cackles in** with a **dismissible** prompt (e.g. on returning to the level-select map, or after a level-complete): *"Help an old gal round up her hens, sugar?"* with **PLAY** / **Not now**.
- **Safeguard (prevents a burned day):** tapping **Not now** does **not** spend the attempt. A small **"Granny waiting" badge/icon** persists (on the level-select map) so the player can start the chase whenever they like that day. The attempt is consumed only when the run **begins**.
- Once an attempt is spent (run completed), Granny + the badge disappear until the next 24 h window.

---

## 6. Candy Granny — character

**Visual style (LOCKED 2026-06-08): 2D paper-cut-out illustration, Candy-Crush / Soda-Crush register** — juicy, flat-illustration, paper-cutout — NOT the 3D-claymation/Veo-billboard look the bosses use. Granny, her hut/cauldron, and the popcorn chickens are all **paper-cutout sprites**, animated with the project's existing **breathing/sway cutout shader** (the "popsicle-stick puppet with bounce" motion — see [[feedback_prop_motion_aesthetic]]); Granny can use a small **jointed cutout rig** (the Candy Rustler `candy_rustler_rig.gd` pattern) for the cackle/ladle if richer motion is wanted. The rendered concept art (`granny_concept_study.png`, `granny_hut_scene_a/b.png`) is direction/personality reference; **final assets are paper-cutout illustration** (the `granny_hut_scene_a` illustration look, not the claymation `_b`).

Adapted from the owner's reference (`granny_ref.webp`). **Keep the reference's silhouette + personality:** wild frazzled hair, hunched posture, long draped cloak, **heavy-lidded sly half-smiling eyes** (harmless-frazzled on the surface, clearly scheming underneath). Recast in candy:

- Hair → wild tangle of greyed **spun-sugar / cotton-candy floss**
- Cloak/shawl → draped **grey licorice-taffy** wrap
- Skin → pale **sugar-paste / gingerbread** with age-lines
- A flour-dusted **apron**, beside her bubbling, steaming **candy cauldron** (caramel syrup, candy-colored glowing bubbles, sweet curling steam)

**Her gingerbread cottage** (ref `granny_hut_ref.webp`): frosting-iced scalloped roof, gumdrop + peppermint trim, candy-cane posts, glowing warm windows, a gumdrop-and-peppermint garden path. It frames the entry prompt and the chase's start.

**Voice-over** — ElevenLabs voice **`vFLqXa8bgbofGarf6fZh`** (owner-provided), via the boss VO pipeline (`tools/gen_*_vo.py` pattern, eleven_v3, `apply_text_normalization="on"`, en.json as text source-of-truth). Lines: a cackle, an intro guilt-trip plea, a scaled win line (full cackle vs. "a few'll have to do"), and a grumble on a goose-egg. Cackling sweet-but-sly register.

**Concept art:** `granny_concept_study.png` (character), `granny_hut_scene_a/b.png` (her stationed in front of the hut with the bubbling/steaming cauldron). Animation later via Veo claymation green-screen billboard (the boss pattern).

---

## 7. Mobile-safe build approach + reuse

Reuse the proven main-game tech; add as little new as possible.

- **Reuse:** the 3D auto-runner movement + swipe steering; the **paper-cutout breathing/sway prop pipeline** (`_make_breathing_prop` + `breathing_prop.gdshader`) for the **popcorn chickens** (cutout sprites, NOT video billboards); the optional **jointed cutout rig** (`candy_rustler_rig.gd`) for Granny; the **farm terrain theme**; the **win/fail modal** pattern (repurposed as the results screen); the **feather/coop FX**; the level-select map + terrain-anchored characters (for the Granny badge).
- **New (all paper-cutout illustration assets):** swipe-to-**lunge-grab** input + the popcorn-chicken **juke AI**; the **catch counter** UI; the **popcorn-chicken** cutout sprite(s); **Candy Granny** cutout (+ optional rig) + VO + her **cauldron** + **gingerbread hut** cutout; the **pop-up + cooldown/badge** UI; the **pending-booster** plumbing and the **"+N starting posse" hook** at level start.
- **No new custom 3D shaders** (mobile white-rects them — reuse the breathing-prop + chroma-key shaders already in the project). The Candy-Crush juice (squash/stretch, bounce, pop FX) comes from the cutout breathing/sway + additive 2D-canvas FX, not new spatial shaders.

---

## 8. Data / persistence

- `GameState` gains: `chicken_chase_last_ts` (unix seconds of the last spent attempt) and `pending_posse_bonus` (int, 0–20).
- **Availability:** `now - chicken_chase_last_ts >= 24h`.
- **Spend:** set `chicken_chase_last_ts = now` when a run begins.
- **Award:** on run end, `pending_posse_bonus = round(caught/8*20)`.
- **Consume:** at the next level's posse init, add `pending_posse_bonus` to the starting count, then reset it to 0.
- Persists via the existing GameState save (same store as hearts/stars/level_best).

---

## 9. Out of scope (YAGNI)

Scores/leaderboards; multiple brew types or a brew-choice menu; difficulty tiers; a permanent playable map building (the pop-up + badge is the entry); IAP/currency; chicken variety beyond the existing breeds as cosmetic skins. **One flock of 8, one proportional brew, one attempt per 24 h.**

---

## 10. Build-time TODOs

- Candy Granny **paper-cutout** art (illustration style, from the concepts) + her cauldron + gingerbread-hut cutouts; animate via breathing/sway (and/or a jointed cutout rig for the cackle/ladle). EL VO line set (voice `vFLqXa8bgbofGarf6fZh`).
- **Popcorn-chicken** cutout sprite(s) — puffed-popcorn body, kernel beak — as a breathing/sway cutout (a couple of frames/poses for the flap if cheap).
- Cauldron steam/bubble FX = additive 2D-canvas or CPUParticles (with a mesh).
- Device tuning: allotted time, chicken speed/juke frequency, lunge recovery window, flock spacing — tuned so a focused player can sweep 8 but a casual run still nets a few.
