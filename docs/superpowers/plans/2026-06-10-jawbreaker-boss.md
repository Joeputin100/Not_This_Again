# Jawbreaker Boss (Level 4) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the Level-4 Jawbreaker boss (Boulder-Brute: slow melee advancer + phase-based ~10s AOE snow-blast) plus the 3-kind mountain outlaw cast (stacked_totem / yeti_brute / snowball_roller).

**Architecture:** Blast-cycle/phase/shed logic in a pure `JawbreakerState` RefCounted (GUT on CI); `level_3d.gd` drives rendering/VO/drain from its events, cloning the Rustler melee loop. Boss + outlaws are chroma-key Veo video billboards. VO = ElevenLabs (owner voice `w80xe5dXbsBW24dNaND0`, eleven_v3, `[exaggerated muttering] [rapido]`), lines verbatim from the spec §3, en.json as source of truth.

**Tech Stack:** Godot 4.6 GDScript, GUT on GitHub Actions (NEVER local Godot), NB Pro green-seed → `tools/veo_render.sh` → ogv, `tools/gen_*_vo.py` pattern.

**Spec:** `docs/superpowers/specs/2026-06-05-jawbreaker-boss-design.md` (incl. §11 locked decisions).

---

## Task 1: `JawbreakerState` — pure blast/phase/shed logic (TDD)

**Files:** Create `godot/scripts/jawbreaker_state.gd`, `godot/test/test_jawbreaker_state.gd`.

Constants: `MAX_HP=400`, `BLAST_INTERVAL=10.0`, `CHARGE_T=1.8`, `PHASE2_FRAC=0.5`, shed thresholds `[0.75,0.5,0.25]`, P1 blast `{freeze:1.5, loss:3}`, P2 blast `{freeze:0.8, loss_frac:0.12, loss_min:4}`.

- [ ] **Step 1: failing tests** — fresh state: hp=MAX, phase=1, idle; `tick` accumulates to `charge_start` at INTERVAL−CHARGE_T… actually: timer counts down from INTERVAL; at CHARGE_T remaining emit `charge_start`; at 0 emit `blast` + reset. `blast_payload(posse)` returns `{freeze, loss}` per phase (P2 loss = max(loss_min, int(posse*loss_frac))). `apply_damage(n)` lowers hp, emits `shed` once per threshold crossed and `phase2` once at ≤50%. `hp<=0` → `defeat` event once, `is_over()`.
- [ ] **Step 2: implement** (RefCounted, `class_name JawbreakerState`; `tick(delta)->Array`, `apply_damage(n)->Array`, `blast_payload(posse_count)->Dictionary`, `var charging: bool`).
- [ ] **Step 3: commit; push with later tasks; CI green.**

## Task 2: VO — en.json banks + full bark set render

**Files:** Modify `godot/assets/text/en.json` (boss block), extend `tools/gen_jawbreaker_vo.py` (en.json-keyed like `gen_raisin_vo.py`, keep voice + tags), output `godot/assets/audio/characters/jawbreaker_*.mp3` + `.import` sidecars (md5(res-path) pattern).

Banks (lines VERBATIM from spec §3): `jawbreaker_dialog_intro`(1), `_taunts`(2: grumble 1+2), `_when_hit`(1: cracked corner), `_charge`(1: BRACE YERSELVES), `_blast`(1: blow YOU down too), `_dying`(1). Slugs `jawbreaker_{intro,taunt,hit,charge,blast,dying}_<n>`.

- [ ] en.json banks → generator → render → sidecars → commit.

## Task 3: Level-4 wiring + tests

**Files:** Modify `godot/resources/levels/level_4.tres` (boss param `"pete"`→`"jawbreaker"`), `godot/scripts/level_3d.gd` `_boss_kind` (`if lvl == 4: return "jawbreaker"`). Create `godot/test/test_level_4_def.gd` (mirror `test_level_6_def.gd`: terrain mountain, weather SNOW, boss jawbreaker).

## Task 4: Mountain outlaw cast (3 kinds)

**Files:** Modify `godot/scripts/level_3d.gd`: `MOUNTAIN_OUTLAW_VIDEOS` (`stacked_totem`/`yeti_brute`/`snowball_roller` → `res://assets/videos/mountain_outlaws/*.ogv`), `MOUNTAIN_OUTLAW_WEIGHTS [["stacked_totem",40],["yeti_brute",35],["snowball_roller",25]]`, OUTLAW_KINDS rows (hp: totem 10, yeti 14, snowball 12), `_pick_outlaw_kind` mountain arm, `_spawn_outlaw` billboard branch, per-kind AI mirroring the farm cast (totem = hold range + potshot cadence; yeti = rusher; snowball = lane-roll on cooldown). Create `godot/test/test_mountain_outlaws.gd` (mirror `test_canyon_outlaws.gd`: weights sum, kinds exist, videos paths registered).

## Task 5: Spawn + drive the boss in `level_3d.gd`

**Files:** Modify `godot/scripts/level_3d.gd`.

- `_spawn_jawbreaker()`: Rustler-pattern boss node + `_make_video_billboard(res://assets/videos/jawbreaker/idle.ogv, height ~5.5)` + plate "THE JAWBREAKER" + `_install_pete_hud` + `jawbreaker_intro_0`.
- `_process_jawbreaker(boss, delta)`: approach at `JAWBREAKER_SPEED=7.0` to `JAWBREAKER_STAY_Z=-7.0`; melee accumulator (`JAWBREAKER_MELEE_DPS=2.5`, special-soak first — clone Rustler); bullet-hit loop (`PETE_HIT_RADIUS_SQ`) → `state.apply_damage`; drive `state.tick` events: `charge_start` → swap billboard to charge.ogv, `jawbreaker_charge_0`, ground frost-ring telegraph (additive 2D ring via the frost_bolts/manga_fx canvas pattern, expanding alpha ring at the posse's screen anchor); `blast` → blast.ogv flash + white `_spawn_impact_blast`-style burst + `blast_payload(_posse_count_3d)`: freeze = gate auto-fire timer for `freeze` seconds (`_posse_frozen_t`), losses via `_outlaw_drain_posse` loop; `shed` → crack flash on billboard (modulate pulse); `phase2` → `jawbreaker_taunt` + faster INTERVAL (state handles); `defeat` → dying meta + `jawbreaker_dying_0` + `_show_win("The Jawbreaker", …)`.
- Dispatch: add `"jawbreaker"` beside rustler/raisin/queen in spawn + process dispatch + Pete-guard lists.
- Freeze visual: posse tint cool-blue while `_posse_frozen_t > 0` (modulate on crowd material params — keep cheap).

## Task 6: Veo billboard clips (boss + 3 outlaws)

**Files:** `godot/assets/videos/jawbreaker/{idle,charge,blast}.ogv`, `godot/assets/videos/mountain_outlaws/{stacked_totem,yeti_brute,snowball_roller}.ogv`.

NB Pro: restyle each locked concept onto flat green #00FF00, full body, centered → Veo green clip (idle loop sway for outlaws + boss idle; boss charge = hunker + inward frost spiral; boss blast = outward ring burst) → ogv + mp4, runtime chromakey (the Pete/Raisin/Queen pipeline). Concept sources: `docs/superpowers/assets/jawbreaker_2026-06-05/concept_{1,2,3,4}.png`.

## Task 7: Debug + close-out

- DebugPreview `pending_jawbreaker` + debug-menu button "JAWBREAKER (L4 BOSS)" (current_level=4, the queen-duel jump-in pattern).
- Push; GUT + smoke green; update memory (`project_jawbreaker_boss.md` → built, device-pass items).

**Device pass (owner):** blast feel/timing, freeze readability, melee DPS, outlaw weights, billboard sizes.

---

## Self-review
Spec §4a melee → Task 5; §4b charge/AOE + §11.3 phase model → Tasks 1+5; §3 VO verbatim → Task 2; §11.1 silhouette → Task 6; §11.2 outlaw cast → Tasks 4+6; testing → Tasks 1/3/4 + parse. Types: `JawbreakerState.{tick,apply_damage,blast_payload,charging,hp,phase}` consistent across 1/5. No placeholders. ✓
