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

- **Setting:** a short, sunny lane on the existing **farm terrain theme**, starting at a **busted chicken coop** (the guilt callback — feathers everywhere). No outlaws, gates, or pits — *chickens, plus a few light obstacles.*
- **Duration:** a fixed **allotted time** (≈25 s, device-tuned) — the length of the lane. There is **no hard fail**; the run simply ends when time/lane runs out.
- **The cowboy auto-runs** forward (same movement/steering code as the main game). The player **swipes left/right** to steer toward birds.
- **A flock of 8 popcorn chickens** flutters ahead, juking, hopping, and scattering. The hens are **made of popcorn** — puffed-popcorn bodies, little kernel beaks, butter-yellow tufts (owner-loved detail). Restyle of the existing chicken sprites into the popcorn look.
- **A few obstacles** dot the lane (candy-farm props — e.g. candy-straw **haybales**, **barrels**, **fence posts**; reuse the existing obstacle/scenery system). They are **non-lethal**: clipping one makes the cowboy **stumble** (a brief ~0.6 s recovery where he can't lunge and the flock scoots ahead) — a tax on your haul, never a death. Swerve to chase cleanly.
- **Catch input:** tap/flick toward a nearby chicken → the cowboy performs a **lunge-grab** (a quick dive) with a short **recovery window** so mashing doesn't work.
- **Chickens are slippery:** a chicken in range can **juke at the last instant** — telegraphed by a wind-up *cluck* + feather puff — so a mistimed lunge **whiffs** and the bird scoots past. Catching cleanly means reading the juke.
- **Catch feedback (Soda-Crush collection):** a caught popcorn chicken **arcs/flies to a "wrapped taffy" collection candy** (the existing taffy cutout, the same juicy fly-to-the-jar feel as Soda Crush's rescued bears), then **pops into the counter** (+1, squash-stretch + sparkle). The taffy candy *is* the catch counter — it reads `caught / 8` and fills up as hens fly in.
- **Score = your haul:** the taffy's `caught / 8` is the score. Uncaught hens at the end simply don't count.

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

**Voice-over** — ElevenLabs voice **`vFLqXa8bgbofGarf6fZh`** (owner-provided), via the boss VO pipeline (`tools/gen_granny_vo.py` like `gen_rustler_vo.py`, eleven_v3, `apply_text_normalization="on"`, en.json `granny_dialog_*` as text source-of-truth). She is **chatty** — sweet-but-sly, cackling, and *delighted* with her candy house. Banks:

- **`intro`** (plea / guilt-trip, played when she offers the chase):
  - "Ooh, a strappin' young gunslinger — just the sugar I need! My hens have flown the coop, on account of YOUR posse stampin' it flat, I might add."
  - "Don't give Granny that look, dearie. Somebody's six-shooters turned my henhouse to kindlin'. Help an old gal round 'em up?"
  - "Catch my hens and I'll brew ye a little pick-me-up. Straight from the cauldron. Heh heh heh."
- **`chatter`** (ambient, she loves her candy house — rotates while idle / on the results screen):
  - "Built this whole place out of gingerbread and gumdrops, I did. Who wouldn't want to live in a house made of candy?"
  - "Mind the walls, sugar — last fella took a bite, and I had to re-frost the entire parlor."
  - "That cauldron's been bubblin' since before yer granny was a twinkle. Smells divine, don't it?"
  - "Real marzipan roof, that. The popcorn hens keep peckin' it — cheeky little kernels."
  - "Oh, I do love comp'ny. Stay a while, won't ye? ...Stay forever, even. Heh heh heh."
- **`chase`** (heckle/cheer during the run):
  - "Faster, sugar — they're poppin' off ever' which way!"
  - "Ooh, slippery little kernels, ain't they?"
- **`win_full`** (all 8): "HA! Every last hen! Yer a natural, dearie — drink up, the posse's on Granny!"
- **`win_partial`** (1–7): "Well, a few hens'll have to do. Half a brew's better than none — sip it down, sugar."
- **`win_zero`** (0): "Bah! Not a single one?! My cauldron stays COLD for that. Off with ye."
- **`cooldown`** (when she's on cooldown / dismissed): "Cauldron's got to simmer, dearie. Come back tomorrow and we'll have another go."

**Concept art:** `granny_concept_study.png` (character), `granny_hut_scene_a/b.png` (her stationed in front of the hut with the bubbling/steaming cauldron). Animation later via Veo claymation green-screen billboard (the boss pattern).

---

## 7. Mobile-safe build approach + reuse

Reuse the proven main-game tech; add as little new as possible.

- **Reuse:** the 3D auto-runner movement + swipe steering; the **paper-cutout breathing/sway prop pipeline** (`_make_breathing_prop` + `breathing_prop.gdshader`) for the **popcorn chickens** (cutout sprites, NOT video billboards); the optional **jointed cutout rig** (`candy_rustler_rig.gd`) for Granny; the existing **obstacle/scenery spawn system** (barrel/haybale/fence props) for the lane obstacles + the stumble reaction; the **wrapped-taffy cutout** (the winflow taffy used for hearts/counter) as the catch-collection candy + a **fly-to-target tween** for the caught hen; the **farm terrain theme**; the **win/fail modal** pattern (repurposed as the results screen); the **feather/coop FX**; the level-select map + terrain-anchored characters (for the Granny badge).
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
