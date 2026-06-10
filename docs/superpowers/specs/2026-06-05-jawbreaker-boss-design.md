# The Jawbreaker — Boss Design (Mountain-Pass Level)

**Date:** 2026-06-05
**Status:** Concept / design — NOT implemented in-engine yet.
**Concept art:** `docs/superpowers/assets/jawbreaker_2026-06-05/concept_1.png` … `concept_4.png`
**VO sample (intro taunt):** `/tmp/jawbreaker_intro.mp3`

---

## 1. Concept summary

The Jawbreaker is the boss of the **snowy mountain-pass level**. He is a hulking
brute built entirely out of fused **jawbreakers** — the layered hard-candy
spheres — with cracked outer shells exposing concentric rings of colored candy
strata (pink / white / blue / red). He has parked himself in a blizzard-blown
pass and treats the posse as trespassers tromping through *his* mountain.

He is a **melee bruiser** who clobbers the posse at close range, and roughly
**every 10 seconds** he winds up and unleashes a **blizzard shockwave (AOE
snow-blast)** that washes over the whole posse area. Personality-wise he is pure
**Popeye**: a mumbly, fast-talking sailor-mutter who **never stops complaining
about the weather** — the cold, the snow getting into his candy shell, his
layers freezing solid.

He should feel **distinct from the existing two bosses**:
- **Pete** — a video-anim gunslinger who duels at distance, then closes to melee.
- **The Candy Rustler** — a Terry-Gilliam collage of hinged ripped wrappers, a
  fast pure-melee contact boss (level 2).
- **The Jawbreaker** — a slow, heavy, *immovable-object* melee boss whose threat
  is his rhythmic charge-and-AOE, not approach speed. Where the Rustler is
  twitchy and ragged, the Jawbreaker is dense, planted, and glacial.

---

## 2. Appearance

**Construction:** body, limbs, and head are giant jawbreakers fused together.
Outer shells are cracked, revealing the layered candy strata inside (the classic
jawbreaker rings). Frost, rime, and packed snow crust the candy; icicles hang off
ledges. A grumpy, squinting, Popeye-style scowl is the read-at-a-glance signature
— one eye narrowed, jutting jaw, perpetual frown, puffing cheeks as he grumbles.

**Setting:** a snowy mountain pass in a raging blizzard — swirling snow, deep
drifts, grey-white storm sky. Leans directly into the existing **snow weather
type** and **mountain terrain theme** (see §5).

**Four concept directions delivered (pick one / hybridize):**
1. **`concept_1.png` — Boulder-Brute.** Low, wide, round boulder body on stubby
   arms/legs. Reads as a planted, immovable wall. Strong "you can't push past
   me" silhouette; best fit for the slow-melee fantasy.
2. **`concept_2.png` — Stacked-Totem.** A vertical snowman-totem of progressively
   smaller jawbreakers (came back wielding candy-cane pistols + a tiny hat —
   most overtly "Western," but tallest and least brute-like).
3. **`concept_3.png` — Yeti-Brute.** Hunched ape/yeti posture, packed snow as
   "fur," icicle beard, rainbow candy strata showing through. Most menacing melee
   read; long arms sell the clobber attacks.
4. **`concept_4.png` — Snowball-King.** One enormous jawbreaker as the body, half
   buried in a drift, crowned with jagged icicles. Boldest round silhouette;
   "grumpy monarch of the pass" energy.

> **Recommendation:** the **Boulder-Brute (1)** or **Yeti-Brute (3)** best sell a
> slow, heavy, *melee + planted AOE* boss. Totem (2) and Snowball-King (4) are
> the most distinctive but read more whimsical than menacing.

---

## 3. Personality + voice

**Personality:** cranky old sailor who's been freezing in this pass too long.
He mutters constantly, half to himself, *very* fast, and every other breath is a
gripe about the cold getting into his shell. Menacing but comedic — family
friendly. Popeye cadence: under-breath grumbling, "well blow me down," little
"agh-gag-gag" mutters between words.

**Voice (already created by owner):**
- **Voice id:** `w80xe5dXbsBW24dNaND0`
- **Model:** `eleven_v3` (required for audio tags)
- **Tags:** every line leads with **`[exaggerated muttering]`** for the Popeye
  mumble and **`[rapido]`** so he talks fast. Place them inline at the start of
  the line (and re-assert before the punch on longer lines).
- **Project standard:** `apply_text_normalization="on"`.
- Generator: `tools/gen_jawbreaker_vo.py` (renders the intro sample; mirror
  `gen_rustler_vo.py`'s en.json-keyed structure for the full set later).

### Sample barks (tags inline)

**Intro taunt** *(this is the rendered `/tmp/jawbreaker_intro.mp3` sample)*
> `[exaggerated muttering] [rapido]` Well blow me down, more sugar-tramps
> trompin' through MY pass — an' in THIS weather?! Snow's gettin' in me good
> candy-shell agh-gag-gag, freezin' me layers solid, I oughtta clobber the lot
> o' ya just to warm up me knuckles!

**Mid-fight grumble 1**
> `[exaggerated muttering] [rapido]` Brrr-agh, can't feel me own jaw — hold
> STILL so's I can warm up on ya, ya little jelly-beans!

**Mid-fight grumble 2**
> `[exaggerated muttering] [rapido]` Snow down me shell, frost in me layers,
> blibber-blabber — this pass ain't big enough for the both of us an' the
> WEATHER!

**Mid-fight grumble 3 (when hit)**
> `[exaggerated muttering] [rapido]` Ooh me cracked corner! Ya chipped me good
> candy — an' it's TOO COLD to be chippin' a feller, blow me down!

**Snow-blast charge-up line** *(plays on the ~10s wind-up telegraph)*
> `[exaggerated muttering] [rapido]` Hrrrm-gg, I'm froze stiff an' I'm sharin' it
> — here comes the COLD, ya warm little tramps, BRACE YERSELVES!

**Snow-blast follow-through (optional, on release)**
> `[exaggerated muttering] [rapido]` BLOW ME DOWN an' blow YOU down too!

**Defeat line**
> `[exaggerated muttering] [rapido]` Awgh… me layers… all… thawin' apart… shoulda
> stayed in me wrapper… g'night, ya frostbit varmints…

---

## 4. Combat design

Reference: existing boss code in `godot/scripts/level_3d.gd`. The Jawbreaker is a
**melee boss like the Candy Rustler**, so it can reuse most of `_process_rustler`
(approach → hold at a duel Z → drain posse by contact → take bullet hits → rig
dismantles → WIN flow), with an added **periodic AOE charge** layered on top.

### 4a. Melee (baseline — mirror the Rustler)
- Strides in to a hold distance (`JAWBREAKER_STAY_Z`, ~`-7` like the Rustler) but
  **slower** than the Rustler's `RUSTLER_SPEED = 15.0` — he's a heavy boulder, so
  ~`6–8` u/s sells the weight and makes him the *immovable* boss.
- While engaged, drain the posse by contact via the same accumulator pattern
  (`_rustler_melee_accum += delta * DPS`; special followers soak first via
  `_nearest_special_follower` / `_damage_special_follower`, then `_posse_count_3d`).
  Suggested `JAWBREAKER_MELEE_DPS` ≈ 2–3.
- Bullet hits reuse the Rustler/Pete loop (`PETE_HIT_RADIUS_SQ`, per-bullet, no
  per-frame break). HP in the Rustler's ballpark (`RUSTLER_HP = 400`); the rig can
  shed cracked layers at 75/50/25% just like the Rustler sheds wrapper pieces.

### 4b. The ~10s charge-up + AOE snow-blast (the signature)
A new timer on top of the melee loop:
- `var _jawbreaker_blast_timer: float` counts down from `JAWBREAKER_BLAST_INTERVAL
  = 10.0`.
- **Telegraph / charge-up (~1.5–2.0s):** when the timer hits the wind-up window,
  enter a `charging` state:
  - Visual: he hunkers down, frost/snow visibly spirals *inward* toward him
    (suck-in), candy shell glows cold/blue, a growing ring decal appears on the
    ground marking the blast radius (give players a clear "get-ready" read).
  - Audio: play the **charge-up bark** (§3) + a rising wind/howl SFX.
  - He does **not** move during charge (planted boulder reinforces the read).
- **Release (the AOE):** a **blizzard shockwave** expands outward across the whole
  posse area — an expanding snow ring + screen-wide flurry burst:
  - Damage model (pick with owner): EITHER a **flat chunk** of posse loss (e.g.
    knock out N followers / a % of the posse), OR a **brief stagger/slow** on the
    posse (snow-frozen) plus light losses. Because it hits the *whole* area on a
    rhythm, it should be **dodge-by-DPS** — the pressure that makes the player
    burn the boss down before too many blasts land, not an instakill.
  - It can reuse the existing AOE/impact-blast visual hooks (e.g.
    `_spawn_impact_blast`) scaled up, tinted white/ice, plus the snow weather
    particle system already in the level.
- After release, reset `_jawbreaker_blast_timer = JAWBREAKER_BLAST_INTERVAL` and
  return to the melee loop.

### 4c. Pacing notes
- The 10s cadence gives a clean **rhythm**: ~8s of melee pressure + dodging, ~2s
  telegraph, then the blast — repeat. Tune interval/charge/damage post-sideload.
- Terrain already **stops scrolling on boss engagement** (per project directive),
  so the fight is a fixed-arena slugfest — ideal for a planted AOE boss.

---

## 5. Where it fits

- **Level:** the **mountain-pass level**, using the existing **snow weather type**
  and **mountain terrain theme** (per the level-themes / weather work). The
  blizzard isn't set dressing — it's the boss's whole identity and his AOE
  source, so this is the natural level to deploy snow weather at full strength.
- Slots into the boss roster after Pete (L1-ish duel) and the Candy Rustler (L2
  collage melee) as a heavier, rhythm-based melee+AOE encounter — a different
  *texture* of fight from both.

---

## 6. Open questions for the owner

1. **Which silhouette?** Boulder-Brute (1), Stacked-Totem (2), Yeti-Brute (3), or
   Snowball-King (4) — or a hybrid? (Design leans 1 or 3 for the slow-melee read.)
2. **AOE damage model:** flat posse-loss chunk vs. stagger/slow + light loss?
   How punishing should one blast be relative to the player's clear DPS?
3. **Blast cadence:** is a flat 10s right, or should it **ramp** (faster blasts as
   his HP drops — a desperate freezing finale)?
4. **Does he move during the fight at all,** or is "totally planted boulder" the
   intended fantasy (he never advances, just melees whatever's in reach + blasts)?
5. **Layer-shedding:** should cracked jawbreaker layers visibly pop off at HP
   thresholds (like the Rustler), and does that change his look/behavior (e.g.
   smaller, faster, angrier as he's chipped down)?
6. **Western flavor:** the totem concept came back with candy-cane six-shooters —
   keep any ranged candy-cane flourish, or is he strictly melee + snow-AOE?
7. **VO scope:** approve the bark set + tag style here, then wire lines into
   `en.json` (under a `boss.jawbreaker_dialog_*` block) and expand
   `gen_jawbreaker_vo.py` to render the full set like `gen_rustler_vo.py`?

---

## 11. LOCKED DECISIONS (owner, 2026-06-10)

1. **Silhouette: Concept 1 — Boulder-Brute** (low, wide, planted wall) is THE Jawbreaker.
2. **Concepts 2/3/4 become the Level-4 mountain OUTLAW cast** (the farm/badlands/canyon roster pattern):
   | kind | concept | behavior |
   |---|---|---|
   | `stacked_totem` | 2 (totem w/ candy-cane pistols) | ranged potshot harasser, keeps distance |
   | `yeti_brute` | 3 (hunched yeti) | rusher — charges to melee, long-arm clobber |
   | `snowball_roller` | 4 (giant snowball) | roller — bowls through lanes on a cooldown |
3. **Snow-blast damage: BOTH, phase-based** — Phase 1 (HP > 50%): brief posse freeze (~1.5s no firing) + light losses; Phase 2 (HP ≤ 50%): bigger flat chunks + shorter freeze. Escalating drama, tuned on device.
4. Blast-cycle/phase/shed logic lives in a pure `JawbreakerState` RefCounted (RaisinKidd/Queen pattern) for GUT on CI.
