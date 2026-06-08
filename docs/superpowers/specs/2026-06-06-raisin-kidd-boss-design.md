# Raisin Kidd — Level 5 Boss Design Spec

**Date:** 2026-06-06
**Status:** Design approved (look, animations, combat niche, level setting, outlaw cast all signed off in companion review). Ready for implementation planning.
**Related:** [Jawbreaker boss](2026-06-05-jawbreaker-boss-design.md), [farm cast](2026-06-06-farm-cast-design.md), [realistic ground terrain](2026-06-05-realistic-ground-terrain-design.md).

---

## 1. Concept

**Raisin Kidd** is the Level 5 boss: an ancient, deeply wrinkled **raisin** (a dried-out grape — literally made of wrinkles) recast as an arrogant **Pai Mei-style kung-fu grandmaster**. The name is ironic — an elder called "the Kidd." He is contemptuous, untouchable, and treats the posse as beneath him, punctuating everything with a **sinister cackle**.

He fills a combat niche none of the existing four bosses occupy:

| Boss | Level | Niche |
|------|-------|-------|
| Pete | 1 | stationary ranged duel |
| Candy Rustler | 2 | fast contact melee |
| Cotton Candy trio | 3 | sticky crowd-control |
| Jawbreaker | 4 | slow brute + AOE blast |
| **Raisin Kidd** | **5** | **defensive deflect-and-counter "untouchable" timing boss** |

The fight is about **timing your fire to his openings**, not out-DPSing a health bar.

---

## 2. Appearance & Animation

**Look (approved):** the "Leaping Trickster" render direction — a wrinkled dark-purple raisin grandmaster with huge bushy white eyebrows and a long flowing white beard, dark robes studded with colorful gumdrop buttons — with the candy-cane **replaced by glowing magic hands** (pink/purple gumdrop-energy orbs orbiting his open palms). Mischievous, acrobatic.

**Two poses → two movement states** (both approved):
- **Guard** (`final_trickster_glow_v2.png` → `guard_idle` clip): grounded wushu stance, both glowing palms raised. His default idle / deflecting posture.
- **Leap** (`final_trickster_glow_v1.png` → `leap` clip): high mid-air strike, one glowing palm extended. Used for his attack commit and his warp re-entry.

**Rendered assets** (`docs/superpowers/assets/raisin_kidd_2026-06-06/`):
- Concept exploration: `concept_1_paimei.png`, `concept_2_western.png`, `concept_3_pressure.png`, `concept_4_cackle.png`
- Final look: `final_trickster_glow_v1.png` (leap), `final_trickster_glow_v2.png` (guard)
- Animations (Veo claymation, studio-bg): `godot/assets/videos/raisin_kidd/guard_idle.{mp4,ogv}`, `leap.{mp4,ogv}`

**Voice:** ElevenLabs voice-library `1a0nAYA3FcNQcMMfbddY`. **Must be added to our EL account** before TTS use (library voices aren't usable until added). VO lines needed: idle taunts, deflect cackles, Grapes-of-Wrath shout, warp quip, the Five-Point finisher line, defeat groan. Generated via the existing `tools/gen_*_vo.py` pattern (`apply_text_normalization="on"`). See [[reference_elevenlabs_vo]].

---

## 3. Combat — "The Untouchable" (deflect & counter)

On engagement the terrain scrolling stops at the temple arena (same trigger used by the other bosses). Raisin Kidd takes the arena center in his Guard pose. The fight reuses the existing `_process_rustler` / `_spawn_pete` boss loop in `level_3d.gd` (special-follower soak, rig dismantle, WIN flow) with these signature additions:

### 3.1 Deflect guard + Guard-Break meter
- While guarding, the posse's jellybean fire **pings off him** — he is invulnerable. Each deflect spawns a contemptuous "tink" spark + occasional cackle VO.
- Sustained fire fills an invisible **Guard-Break meter** (per-second accumulation while he's being hit; decays slowly when not). When it fills, **his guard shatters**: he is stunned and **open to damage for ~3 s** (the big window), then re-guards and the meter resets.
- This rewards concentrated fire and gives the player agency over creating windows.

### 3.2 The Grapes of Wrath (his offensive flurry)
- Periodically (every ~6 s, faster in phase 2) he **commits** to the flurry: a telegraphed wind-up — **anime speed-lines converge** on him + a written-out **manga onomatopoeia SFX** ("TAME…") — then he unleashes a **lane-spanning barrage of raisin-grapes / blur-strikes** the posse must be spread against (it thins a clustered posse).
- **Key counter:** immediately after the flurry he is in **recovery for ~1.5 s = a guaranteed (smaller) damage window**, even if his guard hasn't been broken. So the core loop is: *survive Grapes of Wrath → punish the recovery → chip the Guard-Break meter → shatter for the big window.*

### 3.3 Blinding-speed warp (~every 10 s)
- He strokes his beard, **vanishes in a candy-dust puff**, and **reappears at a new spot** in the arena, resetting the player's aim and sometimes flanking. Brief reappear telegraph (a shimmer) so it reads as fair.
- Cadence ~10 s in phase 1.

### 3.4 Phases
- **Phase 1** → at **50% HP** transition to **Phase 2**: warp cadence tightens to ~7 s, Grapes of Wrath fires more often, speed-lines shift **red**, cackle gets more frantic. No new mechanics — just intensity.

### 3.5 Win
- On defeat: standard boss rig-dismantle + the existing WIN flow (stars, hearts, level-select progression).

---

## 4. Five-Point Raisin Exploding Gumdrop Technique (lose-screen finisher)

This is the candy riff on Pai Mei's "Five Point Palm Exploding Heart Technique," reserved as the **defeat cinematic** — what Raisin Kidd does when **he beats the player** (posse wiped / hearts exhausted at this boss). The full beat sequence:
1. **Fighting-anime special-move title card** slams in — a dramatic Rye name-drop **"FIVE-POINT RAISIN / EXPLODING GUMDROP!"** with star-burst backing + converging speed-lines.
2. He dashes in and lands a rapid **five-point strike** on the lead cowboy (BAP×5 impact pops).
3. **Five glowing gumdrop pips** appear and **count down** 5→1 (screen edges darken with the tension).
4. On zero, a comic candy **KA-BLOOM!** — the figure bursts into a shower of gumdrops (no gore — family-friendly), white flash.
5. **DEFEATED** stamp + his **sinister cackle**, then the standard Fail modal.
- It is a non-interactive flourish on the lose state, NOT a player-survivable attack during the fight.

---

## 5. Level 5 — Sun-Baked Badlands & Dried Candy-Vineyard

A scorched desert finale (hot contrast to Level 4's snow), justifying "raisin = sun-dried grape," with a **candy-Shaolin desert temple** as the boss arena.

- **New terrain theme `badlands`** in `terrain_themes.gd` (alongside frontier/mine/farm/mountain): scorched red-orange cracked ground albedo+normal, warm fog tint, dusty trail; **scatter** = withered candy-grape vines on drying racks, dead candy-cacti, sun-bleached props (reuse rock/scrub where it fits).
- **Weather:** heat-shimmer (additive 2D heat-haze overlay) and/or blowing dust, wired through the existing per-level weather system.
- **Boss arena:** the temple at the end of the run; terrain stops here on boss engagement.
- **LevelDef** (`godot/resources/levels/level_5.tres`): `terrain="badlands"`, weather, `star_thresholds`, `outlaw_quota`, boss reference — following the existing LevelDef pattern. Star thresholds / quota tuned to sit one step harder than Level 4.

---

## 6. Level-5 Outlaws — Shaolin Candy-Monks (no guns)

A round mochi / sesame-ball desert martial-arts monk, shipped as **two visually-distinct types via tint** (same model, two colors — readable at a glance in a crowd, and cheap):

| Type | Tint | Attack | Role |
|------|------|--------|------|
| **Fireball Monk** | warm **orange** | Hadouken Candy-Fireball — cups & conjures a swirling candy orb, lobs it | heavy / telegraphed hitter |
| **Star Monk** | cool **blue** | Candy-Star Throw — quick flick of a glowing cyan candy star | fast, light, multi-shot harasser |

- **Spawn weighting:** add a `badlands` branch to the `outlaw_kind` system (mirrors `FARM_OUTLAW_WEIGHTS` / `_pick_outlaw_kind`), e.g. `{fireball_monk: 45, star_monk: 55}` (tune on device).
- **Behavior:** both are **ranged, no guns** (fits family-friendly + rhymes with the boss's energy hands). Fireball monk = slower cadence, telegraphed lob, higher damage; star monk = fast cadence, low damage per shot, comes in numbers. Both drain via the existing `_outlaw_drain_posse()` (special follower soaks first).
- **Assets:** `outlaw_hadouken.png` + `godot/assets/videos/candy_monk/hadouken.{mp4,ogv}` (orange); `outlaw_candystar_blue.png` + `candy_star_blue.{mp4,ogv}` (blue). (Orange `candy_star.*` and `outlaw_candystar.png` are superseded by the blue recolor.)

---

## 7. Mobile-Safe Build Approach

All effects use only the techniques proven on our Android mobile renderer — **no custom spatial (3D) shaders** (they white-rect on device).

- **Boss + both monks = chroma-key video billboards** via `_make_video_billboard(<ogv>, height)` (the vagrant/Pete/farm approach). The two boss **attack** clips are already green-screened + key cleanly (`grapes_of_wrath_green`, `five_point_strike_green`); remaining build task: green-screen versions of the boss idle/movement (`guard_idle`, `leap`) and the two monks. Green-screen technique: NB-Pro a flat-green-bg seed still first, then Veo from it (Veo ignores a bare "green screen" prompt otherwise) — see the boss memory.
  - **Keep the happy accident:** during Grapes of Wrath the keyed sprite goes **partially translucent** (energy frames key through). The owner chose to KEEP this — it reads as the master "phasing." Do NOT tighten the key to remove it for that move.
- **Grapes-of-Wrath speed-lines, the written-out manga onomatopoeia, and all gumdrop energy = additive 2D-canvas overlays** in the `frost_bolts.gd` / `rainbow_bolts.gd` style (the FROSTBITE-caliber tech). The manga SFX are drawn text + speed-lines on the additive canvas. **All manga lettering (the title cards + onomatopoeia SFX) uses the `Rye` font** (the game's Western display face) with a dark outline + white edge for punch.
- **Deflect "tink" sparks + guard-break shatter** = additive sprites and `CPUParticles3D` (must carry a mesh, or they render nothing).
- **Fight logic** extends the existing `_process_rustler`/`_spawn_pete` loop, special-follower soak, rig dismantle, and the WIN/FAIL modal flow already in `level_3d.gd`.

---

## 8. Open Items / Build-Time TODOs

- **Green-screen Veo clips** for boss (guard, leap) + both monks (hadouken, candy_star_blue) — current clips are studio-bg previews.
- **Add voice `1a0nAYA3FcNQcMMfbddY` to the EL account**, then generate the VO line set.
- **Tune numbers on device:** Guard-Break fill rate + open window, Grapes-of-Wrath cadence + recovery window, warp cadence, phase-2 thresholds, boss HP, outlaw spawn weights, Level-5 star thresholds/quota.
- **Additional boss VO/FX polish** (idle taunts, warp quip) can follow once the loop is in.

---

## 9. Asset Inventory

**Concepts & finals:** `docs/superpowers/assets/raisin_kidd_2026-06-06/` — `concept_1_paimei.png`, `concept_2_western.png`, `concept_3_pressure.png`, `concept_4_cackle.png`, `final_trickster_glow_v1.png`, `final_trickster_glow_v2.png`, `outlaw_hadouken.png`, `outlaw_candystar.png`, `outlaw_candystar_blue.png` + companion preview HTMLs.
**Animations:** `godot/assets/videos/raisin_kidd/{guard_idle,leap}.{mp4,ogv}`, `godot/assets/videos/candy_monk/{hadouken,candy_star,candy_star_blue}.{mp4,ogv}`.
