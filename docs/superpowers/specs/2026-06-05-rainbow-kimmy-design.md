# Rainbow Kimmy — Sugar Rush Rescue — Design Spec

**Date:** 2026-06-05
**Status:** Approved design (pre-implementation)
**Goal:** A high-effort, missable rescue set-piece: free the captive peppermint stallion from a cage-wagon using a special Rainbow weapon; on rescue she transforms into **Rainbow Kimmy** (shades + electric guitar) and rips a guitar riff that detonates every on-screen outlaw and destructible obstacle in a rainbow Skittles screen-clear.

---

## 1. Player experience (the flow)

A per-level set-piece (placed by the level designer; for now **Level 3 only**):

1. **Rainbow crate (earlier in the level).** A special Rainbow crate rolls in (distinct from the random bonus crates). Shoot it to equip the **Rainbow weapon** — rainbow Skittles bullets that fire like a normal weapon against outlaws, but are the *only* thing that can dent Kimmy's cage.
2. **The cage blocks the path.** Kimmy's cage-wagon — holding the **plain peppermint stallion** (no shades/guitar yet) — arrives and **halts forward scroll** (like the boss-engagement stop). A **cage-HP bar** appears; it only drops from **Rainbow hits** (other fire modes ping off with a "RAINBOW ONLY" cue). The cage has **high HP** — a sustained fight, not a quick burst — while outlaws keep harassing you. A **rescue timer** runs.
3a. **Rescue (HP→0 with Rainbow before the timer):** the cage bursts, the stallion **transforms into Rainbow Kimmy** (shades + electric guitar), and the **Sugar Rush** fires — a rainbow Skittles wave destroys all on-screen outlaws + destructible obstacles, a "RAINBOW KIMMY!" flourish banner shows, a ~3s crescendo rock-guitar riff plays, bounty rains, then the path clears and scrolling resumes.
3b. **Miss (no Rainbow weapon, or timer expires):** the candy-outlaw pushers **haul the wagon off**, scrolling resumes, a quick "SHE GOT AWAY!" beat plays, **no rush**. No soft-lock — the path always clears.

**Why it's earned:** two efforts gate the payoff — (1) find + equip the Rainbow weapon earlier, and (2) crack a high-HP cage under fire before the timer. Because it's missable, pulling it off feels like an accomplishment.

---

## 2. Components

Built on three existing systems (most of this is new content on proven rails):

### 2a. Rainbow weapon (FireMode.RAINBOW)
- Add `RAINBOW` to the `FireMode` enum (`level_3d.gd`, currently `{CANDY, RIFLE, FROSTBITE, FRENZY}`).
- A **special Rainbow crate**: reuse the `_spawn_bonus`/bonus-crate path but as a **designer-placed `BONUS` event** with `type = "rainbow"` (NOT added to the random `BONUS_TYPES` rotation). Art: `bonus_crate_rainbow.png`. Collecting sets `_fire_mode = RAINBOW` (same as the other weapon pickups).
- Bullets: `CANDY_BULLET_TEX[RAINBOW]` = rainbow Skittles art. Behaves like a normal weapon vs outlaws (damage, fire interval, range — pick values comparable to FRENZY).
- **Unique rule:** only `RAINBOW` bullets damage Kimmy's cage; all other fire modes do 0 cage damage (and surface a brief "RAINBOW ONLY" popup the first time the player hits the cage with the wrong weapon).

### 2b. Kimmy rescue set-piece
- Reuse `_spawn_captive_hero(container_slug, hero_slug, ...)` (it already makes a captive `Node3D` with `hp`/`max_hp`/`is_captive` meta). Spawn the cage-wagon with `hero = "kimmy_caged"` (plain stallion), a **high cage HP** (`KIMMY_CAGE_HP`, tuned high — a multi-second sustained-fire crack), and a cage-HP bar.
- **Blocks the path:** when the cage reaches its hold position, halt the world scroll (reuse the boss-engagement scroll-stop) until resolved.
- **Rainbow-only damage:** in the bullet↔captive collision, a bullet reduces `KIMMY` cage HP only if `_fire_mode == RAINBOW` (or the bullet carries a `rainbow` meta); otherwise 0 (+ the "RAINBOW ONLY" cue).
- **Rescue timer** (`KIMMY_RESCUE_WINDOW`, generous enough that a focused player with Rainbow can win): on expiry → **haul-away** (pushers tow the cage off / it scrolls away), resume scroll, "SHE GOT AWAY!" flourish, no rush.
- **On crack (HP→0):** trigger the Sugar Rush (2c).
- A new level event drives it: add `EventKind.KIMMY` (or reuse `PUSHED_WAGON` with a `kimmy: true` param) at a distance in the level timeline.

### 2c. The Sugar Rush (`_rush_kimmy()`)
Dispatched on rescue (directly, or via `_play_rush_3d("KIMMY")` styled like the other rushes):
- **Transform:** swap the caged plain-stallion art → **Rainbow Kimmy** (`kimmy_rainbow.png`, shades + guitar); pop her to the fore with a bounce.
- **Skittles screen-clear:** iterate `outlaws_root` AND the destructible obstacles in `obstacles_root` — barrels, cacti, **and bulls** (everything destructible on screen) — and destroy each with a rainbow Skittles burst; award bounty per kill via `_add_bounty`. The only thing NOT destroyed is the captive/cage itself (Kimmy) and the player's own posse. A big rainbow-Skittles particle wave sells it (in-engine `CPUParticles`, rainbow palette — **no custom shaders**).
- **Audio/flourish:** play the ~3s crescendo rock-guitar riff SFX (`kimmy_riff`), show a `FlourishBanner` "RAINBOW KIMMY!" / "SUGAR RUSH!".
- **Resolve:** after the riff, clear the cage, resume scroll, continue. Counts toward the outlaw quota appropriately (destroyed outlaws decrement `_outlaws_remaining` via the existing `_outlaw_left_field` chokepoint).

---

## 3. Placement & data

- **Level 3 only for now.** In `godot/resources/levels/level_3.tres`: add a `BONUS` event (`type="rainbow"`) at an early distance, and the Kimmy cage event later (after the player has had a chance to grab the crate, before the boss). Tuned so the crate clearly precedes the cage.
- Cadence/placement is a **per-level designer decision** (future level editor) — there is no global "once per level." Other levels get her only when a designer places the events.

---

## 4. Assets

- `kimmy_caged.png` — plain peppermint stallion (captive, no shades/guitar). NB Pro, green-screen → matte.
- `kimmy_rainbow.png` — Rainbow Kimmy: peppermint stallion in **sunglasses holding an electric guitar**, rockstar pose. NB Pro.
- `bonus_crate_rainbow.png` — the Rainbow weapon crate (matches the existing `bonus_crate_*` style, rainbow).
- Rainbow Skittles **bullet** art for `CANDY_BULLET_TEX[RAINBOW]` (rainbow candy disc).
- Cage-wagon art (reuse an existing wagon/container sprite if one fits, else a new `kimmy_cage.png`).
- Skittles **burst** — in-engine `CPUParticles` with a rainbow color ramp (no shader).
- `kimmy_riff` SFX — a ~3s **crescendo rock-guitar riff** via the ElevenLabs text-to-sound pipeline (`tools/gen_creature_sfx.py`, duration ~3s) → `godot/assets/sfx/creatures/kimmy_riff.mp3`, played by `AudioBus.play_sfx("kimmy_riff")`.

---

## 5. Verification

- **GUT (pure logic):** the cage-damage rule (only RAINBOW reduces cage HP, others 0); the rescue state machine if extractable (caged → cracked vs caged → timed-out); the Skittles-rush target selection (which nodes get destroyed). Keep these as small testable helpers where practical.
- **DebugPreview:** add a Kimmy-rescue + Rainbow-rush preview path (the debug menu already has `pending_captive_hero` and `pending_rush` flags) so the encounter + rush can be previewed without playing to Level 3.
- **sp1-screenshot stills:** the caged plain stallion, freed Rainbow Kimmy, the Rainbow crate, and a Skittles-bullet — via the force-state debug-preview pattern (removed before commit).
- **Device:** the full encounter — grab crate → cage blocks → crack with Rainbow under fire → transform + screen-clear + riff; and the miss/haul-away path; on Level 3.

---

## 6. Out of scope
- IAP / boosters. Player-facing meter UI. Rainbow Kimmy on any level other than 3 (designer-placed later). Making Rainbow part of the random bonus rotation. A full level-editor for placing her (that's SP3).
