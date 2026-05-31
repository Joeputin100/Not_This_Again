# SP2 — Level Toolkit (data-driven levels) Design

**Goal:** Turn a gameplay level from hardcoded logic in `level_3d.gd` into **data** — a single `LevelDef` resource that describes the path/terrain, everything that happens along it, and the win condition. Gameplay *plays* a `LevelDef`. This is the foundation the **SP3 Level Editor** will author.

**Architecture (one line):** `LevelDef` (a `.tres`) is the single source of truth; `level_3d` reads it and, as the world scrolls, triggers a **distance-indexed timeline** of events and applies a **pacing track**, over a **curved/hilly path** that can have **holes/cliffs** entities fall into.

**Tech stack:** Godot 4.6.1 GDScript. Extends the existing `LevelDef` (`godot/scripts/level_def.gd`), `terrain_3d.gd` (height field + `height_at`), and the existing `_spawn_*` functions in `level_3d.gd`. No new engine deps.

---

## Background — current state

- `level_3d.gd` (~5,000 lines) hardcodes a level: a **flat straight path**, world scroll gated by one scalar `motion_delta = delta if (PLAYING and not _cart_encounter) else 0.0`, random scenery via `_spawn_scenery_item`, outlaws/gates/bonuses on internal timers, and the boss (`_spawn_pete` / `_spawn_candy_rustler`) at `_level_elapsed >= PETE_SPAWN_DELAY (30s)`.
- `LevelDef` (`level_def.gd`) already exists as a per-level `Resource` (difficulty, terrain, display_name, seed, weather_type) but only carries a few header fields.
- `terrain_3d.gd` already does curved/hilly terrain (`height_at(lx,lz)`, `hilly`, `build_grass`) — used by the **level-select**, not by gameplay. The level-select also has a serpentine **path curve** (`_path_world`, arc-length sampling).
- Level launch: level-select `_start_level` sets `GameState.current_level` and loads `level_3d.tscn`; `level_3d` reads `current_level`.

**Problem:** levels can't be created or varied without editing a giant script, and the path is always flat/straight.

---

## The `LevelDef` data model

Extend `LevelDef` (Resource) to be the full toolkit. Fields:

**Header**
- `display_name: String`, `difficulty: int`, `terrain: String`, `weather_type: String`, `seed: int` (existing).
- `goal: int` (enum `GOAL { REACH_END, DEFEAT_BOSS, SURVIVE }`) + `goal_param: float` (e.g. survive seconds, or end-distance).
- `length: float` — total path distance (world units) for `REACH_END`.

**Terrain / path** (`PathProfile` sub-resource)
- `lateral: Curve` — path x-offset as a function of normalized distance (0..1): the **bends**.
- `height_amp: float`, `height_freq: float` (+ optional `height_curve: Curve`) — the **hills**, fed to `terrain_3d.height_at`.
- `holes: Array[Hole]` where `Hole = { dist_start, dist_end: float; x_min, x_max: float; kind: int (HOLE|CLIFF_LEFT|CLIFF_RIGHT) }` — regions of absent/negative ground an entity **falls into**.

**Timeline** — `events: Array[LevelEvent]`, each:
- `distance: float` — world distance from the start at which it fires (events are sorted; the player triggers each as the scrolled distance crosses it).
- `kind: int` — enum `EventKind { OUTLAW, GATE, PROP, BONUS, PUSHED_WAGON, BOSS, GOLD_RUSH, PACING, APPROACH_ZONE }`.
- `params: Dictionary` — kind-specific (see below). (Typed sub-resources per kind are a possible later refinement; a tagged dict keeps the editor simple.)

**Per-kind `params`:**
- `OUTLAW` — `{ x, count, formation, z_speed, behavior }` → calls `_spawn_outlaw`-family.
- `GATE` — `{ op: "×"|"÷"|"+"|"−", value, x }` → `_spawn_gate`.
- `PROP` — `{ slug, side, scale }` → `_spawn_prop_from_slug` / scenery spawners.
- `BONUS` — `{ bonus_type: candy|rifle|frostbite|frenzy|..., x }` → `_spawn_bonus`.
- `PUSHED_WAGON` — `{ hero_slug, container_slug, pusher_count }` → `_spawn_pushed_wagon` (sets `_cart_encounter`).
- `BOSS` — `{ boss: pete|rustler }` → `_spawn_pete` / `_spawn_candy_rustler`; flips `LevelState.BOSS`.
- `GOLD_RUSH` — `{ beat_id }` → the per-level chain-reaction flourish.
- `PACING` — `{ speed_factor: float }` — cruise speed from here until the next PACING. Scale: **`1.0` = today's normal scroll, `0` = halt, `>1` = faster** (the **reactive** easing modulates within bounds; see below).
- `APPROACH_ZONE` — `{ exit: CLEAR|TIMER|EVENT, timeout, x_band }` — halts the scroll; enemies/props advance on the stationary posse; resumes per its authored exit.

---

## Gameplay plays a `LevelDef`

On `_ready`, `level_3d` loads `LevelDef` for `GameState.current_level` (path convention e.g. `res://levels/level_%d.tres`, falling back to a **default LevelDef that reproduces today's L1** if absent — so nothing regresses).

A `LevelPlayer` (focused class owned by `level_3d`) holds: the sorted `events`, a cursor, and **`distance`** (accumulated `OBSTACLE_SPEED * motion_delta`). Each frame:
1. Advance `distance` by the scroll.
2. Fire every event whose `distance` ≤ current distance (cursor walk), dispatching by `kind` to the existing `_spawn_*` functions with `params`.
3. Ask the **`LevelDirector`** (pacing sub-component) for the current `speed_factor`, and compute `motion_delta = delta * speed_factor` (generalizing the current `{0, delta}` gate; `_cart_encounter` and approach-zones force `speed_factor = 0`).
4. Check the **goal**; on satisfaction → win flow.

This *replaces* the hardcoded scenery/outlaw/gate/boss timers. The existing `_spawn_*` functions are reused unchanged (just called from data instead of internal timers).

## Pacing sub-system — `LevelDirector`

A focused `RefCounted` (`level_director.gd`), unit-testable in isolation. Inputs each frame: `distance`, live-enemy count, `delta`. Output: `speed_factor` (0..N) and `world_held: bool`.

- **Hybrid (authored + reactive):** `PACING` events set a target cruise `speed_factor` per segment; between updates the director **eases** the actual factor toward a value scaled by **action intensity** (reuse the camera's active-outlaw signal from `_update_dynamic_camera`) — busier ⇒ slower, quiet ⇒ the authored cruise. Smooth `lerp`, no snapping.
- **Distance axis:** the track is keyed on `distance`, so segments line up with where set-pieces actually are; an approach-zone halt (`speed_factor=0`) **pauses distance progress**, so the next event/segment waits until the zone resolves.
- **Approach zone state machine:** entering an `APPROACH_ZONE` event sets `world_held = true` (scroll 0); enemies/props keep advancing under their own velocity (the pursuit path already moves outlaws on real `delta`). Exit per authored `exit`:
  - `CLEAR` — resume when no live enemies remain in the zone's `x_band`/range (+ `timeout` safety to prevent soft-lock).
  - `TIMER` — resume after `timeout` seconds.
  - `EVENT` — resume when a named flag is set (e.g. a set-piece prop reaches the posse).

## Terrain / path + holes + falling

- Build the gameplay ground from the `PathProfile`: reuse `terrain_3d.gd` (`hilly` + `height_at`) for hills, and the level-select **path-curve** approach (lateral offset along distance) for bends. Gameplay scrolls *along the path*; props/outlaws are placed by `(distance, lateral)` then converted to world position via the curve + `height_at`.
- **Holes/cliffs:** a `Hole` marks a `(dist, x)` region with no ground. Each frame, for every posse member + outlaw, sample whether its `(dist, x)` is inside a hole; if so it **falls** (tween down + fade) and is removed — posse via the existing posse-loss bookkeeping (`_posse_count_3d` decrement, like the cliff in the pushed-wagon mechanic), outlaws via their death path. This makes holes a **two-way hazard** (drive outlaws in; lose posse that strays in).

---

## Build slices (each shippable + sideload-verifiable)

1. **`LevelDef` plays today's L1.** Extend `LevelDef`; add `LevelPlayer`; author a default L1 `LevelDef` whose events reproduce the current L1 (same scenery/outlaw/gate cadence + Pete at the same point). Gameplay loads it; flat path unchanged. *Verify L1 is unchanged.*
2. **Pacing + approach zones.** Add `LevelDirector`; generalize `motion_delta = delta * speed_factor`; add `PACING` + `APPROACH_ZONE` events; author a couple into L1. *Verify variable speed + a stand-and-fight halt.*
3. **Curved/hilly path + holes/falling.** `PathProfile` drives the gameplay terrain (bends + hills) via `terrain_3d`; add `Hole` regions + the fall check for posse + outlaws. *Verify a curve, a hill, and an outlaw + a posse member falling into a hole.*
4. **Port remaining piece-types to data + author L2.** Ensure every `EventKind` is data-driven; hand-author a distinct L2 `.tres` to prove the toolkit composes a new level. (→ then **SP3 editor** authors `LevelDef`s with a UI.)

## Error handling / edge cases

- **Missing/invalid `LevelDef`** → load the bundled default (today's L1) so gameplay never hard-fails.
- **Approach-zone soft-lock** → every `CLEAR`/`EVENT` zone has a `timeout` safety that force-resumes.
- **Boss vs pacing** → `BOSS` event forces `LevelState.BOSS`; the director yields (boss already drives its own camera/behaviour).
- **Falling during a boss/cart hold** → holes are only active while `speed_factor > 0` *or* an approach zone is live, so a frozen world doesn't drop idle members.

## Testing

- Per slice: the `sp1-screenshot` skill on `level_3d.tscn` for visual checks (path shape, a halt, a fall) + sideload for feel.
- Slice 1 acceptance: L1 plays identically to pre-SP2 (regression guard).
- `LevelDirector` is pure logic → a small headless test scene can step it through a synthetic track and assert `speed_factor`/`world_held` transitions.

## Non-goals (this spec)

- The **Level Editor** (SP3) — authoring UI over `LevelDef`. SP2 authors `.tres` by hand.
- New content beyond L1 parity (slice 1) + one demo L2 (slice 4).
- Reworking weapons/posse/boss internals — SP2 only changes *how they're triggered* (data vs hardcoded), not their behaviour.

## Open decisions (defaults chosen; flag to change)

- **Event params as tagged `Dictionary`** (vs typed sub-resource per kind) — chosen for editor simplicity; can specialize later.
- **`LevelDef` path** `res://levels/level_%d.tres` keyed by `current_level`.
- **Reactive intensity** reuses the camera's active-outlaw count (consistency with the dynamic camera).
