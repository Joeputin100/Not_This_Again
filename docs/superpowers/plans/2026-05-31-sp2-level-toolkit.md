# SP2 Level Toolkit — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make a gameplay level *data* — a `LevelDef` resource gameplay plays — instead of hardcoded logic in `level_3d.gd`. Slice 1 builds the data spine (`LevelEvent`, `LevelPlayer`, extended `LevelDef`) and proves it end-to-end by driving the boss spawn from a data event.

**Architecture:** A `LevelPlayer` (pure logic, RefCounted) holds a distance-sorted `events` list and fires each as the scrolled `distance` crosses it. `level_3d` loads the `LevelDef` for `GameState.current_level` (the `.tres` files already exist but are currently inert), accumulates distance from the world scroll, and dispatches fired events to the existing `_spawn_*` functions. Boss migration is the first event-kind wired; the rest follow in later slices.

**Tech Stack:** Godot 4.6.1 GDScript; GUT unit tests (`godot/test/`, run via `addons/gut/gut_cmdln.gd`). Spec: `docs/superpowers/specs/2026-05-31-sp2-level-toolkit-design.md`.

---

## File Structure

- **Create** `godot/scripts/level_event.gd` — `class_name LevelEvent extends Resource`. One timeline entry: `distance`, `kind` (enum `EventKind`), `params` (Dictionary). Pure data.
- **Create** `godot/scripts/level_player.gd` — `class_name LevelPlayer extends RefCounted`. Pure logic: sort events by distance, `advance(to_distance)` returns the events newly crossed. No engine deps → unit-testable.
- **Modify** `godot/scripts/level_def.gd` — add `goal`, `goal_param`, `length`, `events: Array[LevelEvent]`.
- **Modify** `godot/scripts/level_3d.gd` — load the `LevelDef`, own a `LevelPlayer`, accumulate `_level_distance`, dispatch fired events; migrate the boss trigger to a `BOSS` event (hardcoded timer kept only as the no-data fallback).
- **Modify** `godot/resources/levels/level_1.tres` … `level_4.tres` — add a `BOSS` event at distance 75 (= the current 30s × `OBSTACLE_SPEED` 2.5).
- **Create** `godot/test/test_level_player.gd` — GUT tests for `LevelPlayer`.

Run a single GUT file headless:
```
DISPLAY=:99 /home/projects/.local/bin/godot --headless --path godot \
  -s res://addons/gut/gut_cmdln.gd -gtest=res://test/test_level_player.gd -gexit -gconfig=res://.gutconfig.json
```
Expected on pass: GUT prints `1/1 passing` style summary and exits 0 (`Tests ... Passing N`).

---

## Slice 1 — LevelDef plays a data-driven boss

### Task 1: `LevelEvent` resource

**Files:**
- Create: `godot/scripts/level_event.gd`

- [ ] **Step 1: Write the failing test** (covers creation + enum) — append to a new test file (created fully in Task 2; for now create it minimal):

`godot/test/test_level_player.gd`:
```gdscript
extends GutTest

const LevelEvent = preload("res://scripts/level_event.gd")

func test_level_event_holds_fields():
	var e := LevelEvent.new()
	e.distance = 75.0
	e.kind = LevelEvent.EventKind.BOSS
	e.params = {"boss": "pete"}
	assert_eq(e.distance, 75.0)
	assert_eq(e.kind, LevelEvent.EventKind.BOSS)
	assert_eq(e.params.get("boss"), "pete")
```

- [ ] **Step 2: Run it — expect FAIL** (script `level_event.gd` doesn't exist → load error):
```
DISPLAY=:99 /home/projects/.local/bin/godot --headless --path godot -s res://addons/gut/gut_cmdln.gd -gtest=res://test/test_level_player.gd -gexit -gconfig=res://.gutconfig.json
```
Expected: failure / load error referencing `res://scripts/level_event.gd`.

- [ ] **Step 3: Implement** `godot/scripts/level_event.gd`:
```gdscript
class_name LevelEvent
extends Resource

# One entry on a level's distance-indexed timeline. `kind` selects which
# gameplay piece to spawn/trigger; `params` carries the kind-specific args
# (see the SP2 spec). Plain data — gameplay dispatches on it.
enum EventKind { OUTLAW, GATE, PROP, BONUS, PUSHED_WAGON, BOSS, GOLD_RUSH, PACING, APPROACH_ZONE }

@export var distance: float = 0.0           # world distance from level start at which it fires
@export var kind: int = EventKind.OUTLAW
@export var params: Dictionary = {}
```

- [ ] **Step 4: Run it — expect PASS** (same command). Expected: `test_level_event_holds_fields` passes.

- [ ] **Step 5: Commit**
```bash
git add godot/scripts/level_event.gd godot/test/test_level_player.gd
git commit -m "sp2 slice1: LevelEvent resource (distance/kind/params timeline entry)"
```

### Task 2: `LevelPlayer` — fire events as distance crosses them

**Files:**
- Create: `godot/scripts/level_player.gd`
- Modify: `godot/test/test_level_player.gd`

- [ ] **Step 1: Write the failing tests** — add to `godot/test/test_level_player.gd`:
```gdscript
const LevelPlayer = preload("res://scripts/level_player.gd")

func _ev(dist: float, kind: int) -> LevelEvent:
	var e := LevelEvent.new()
	e.distance = dist
	e.kind = kind
	return e

func test_fires_due_events_sorted_once_only():
	# input intentionally out of distance order
	var p := LevelPlayer.new([_ev(75.0, LevelEvent.EventKind.BOSS), _ev(10.0, LevelEvent.EventKind.OUTLAW)])
	assert_eq(p.advance(5.0).size(), 0, "nothing before the first event")
	var due := p.advance(12.0)
	assert_eq(due.size(), 1, "one event crossed at 12")
	assert_eq(due[0].kind, LevelEvent.EventKind.OUTLAW, "earliest fires first")
	due = p.advance(80.0)
	assert_eq(due.size(), 1, "boss crossed at 80")
	assert_eq(due[0].kind, LevelEvent.EventKind.BOSS)
	assert_eq(p.advance(999.0).size(), 0, "no event re-fires")

func test_multiple_cross_in_one_advance():
	var p := LevelPlayer.new([_ev(10.0, LevelEvent.EventKind.OUTLAW), _ev(20.0, LevelEvent.EventKind.GATE)])
	var due := p.advance(50.0)
	assert_eq(due.size(), 2, "both crossed in one jump")
	assert_eq(due[0].distance, 10.0, "returned in distance order")
```

- [ ] **Step 2: Run — expect FAIL** (`level_player.gd` missing). Command as Task 1 Step 2.

- [ ] **Step 3: Implement** `godot/scripts/level_player.gd`:
```gdscript
class_name LevelPlayer
extends RefCounted

# Plays a level's timeline: holds events sorted by distance and, as the world's
# scrolled `distance` advances, returns the events newly crossed (each once).
# Pure logic — gameplay feeds distance + dispatches the returned events.
var _events: Array = []
var _cursor: int = 0
var distance: float = 0.0

func _init(events: Array = []) -> void:
	_events = events.duplicate()
	_events.sort_custom(func(a, b): return a.distance < b.distance)

# Advance to an absolute distance; return the events crossed since last call.
func advance(to_distance: float) -> Array:
	distance = to_distance
	var due: Array = []
	while _cursor < _events.size() and _events[_cursor].distance <= to_distance:
		due.append(_events[_cursor])
		_cursor += 1
	return due
```

- [ ] **Step 4: Run — expect PASS** (3 tests pass).

- [ ] **Step 5: Commit**
```bash
git add godot/scripts/level_player.gd godot/test/test_level_player.gd
git commit -m "sp2 slice1: LevelPlayer — distance-sorted timeline, fires each event once"
```

### Task 3: Extend `LevelDef` with goal + events

**Files:**
- Modify: `godot/scripts/level_def.gd`

- [ ] **Step 1: Write the failing test** — add to `godot/test/test_level_player.gd`:
```gdscript
const LevelDef = preload("res://scripts/level_def.gd")

func test_leveldef_has_events_and_goal():
	var d := LevelDef.new()
	d.goal = LevelDef.Goal.DEFEAT_BOSS
	var e := LevelEvent.new()
	e.distance = 75.0
	e.kind = LevelEvent.EventKind.BOSS
	d.events = [e]
	assert_eq(d.goal, LevelDef.Goal.DEFEAT_BOSS)
	assert_eq(d.events.size(), 1)
```

- [ ] **Step 2: Run — expect FAIL** (`Goal`/`events` not defined on LevelDef).

- [ ] **Step 3: Implement** — append to `godot/scripts/level_def.gd` (keep existing fields):
```gdscript
enum Goal { REACH_END, DEFEAT_BOSS, SURVIVE }

@export var goal: int = Goal.DEFEAT_BOSS
@export var goal_param: float = 0.0   # REACH_END: end-distance · SURVIVE: seconds
@export var length: float = 0.0       # total path distance (world units)
@export var events: Array[LevelEvent] = []
```

- [ ] **Step 4: Run — expect PASS**.

- [ ] **Step 5: Commit**
```bash
git add godot/scripts/level_def.gd godot/test/test_level_player.gd
git commit -m "sp2 slice1: LevelDef gains goal + distance-indexed events list"
```

### Task 4: Author the boss event into the level `.tres` files

**Files:**
- Modify: `godot/resources/levels/level_1.tres` (and `level_2/3/4.tres`)

- [ ] **Step 1:** Edit `godot/resources/levels/level_1.tres` to add a sub-resource boss event and reference it from `events`. Distance 75.0 = current `PETE_SPAWN_DELAY` 30s × `OBSTACLE_SPEED` 2.5. Result:
```
[gd_resource type="Resource" script_class="LevelDef" load_steps=3 format=3 uid="uid://b0nttg_lvldef_1"]

[ext_resource type="Script" path="res://scripts/level_def.gd" id="1_def"]
[ext_resource type="Script" path="res://scripts/level_event.gd" id="2_ev"]

[sub_resource type="Resource" id="ev_boss"]
script = ExtResource("2_ev")
distance = 75.0
kind = 5
params = { "boss": "pete" }

[resource]
script = ExtResource("1_def")
difficulty = 1
terrain = "frontier"
display_name = "FRONTIER STANDOFF"
seed = 1
weather_type = ""
goal = 1
events = [SubResource("ev_boss")]
```
(`kind = 5` = `EventKind.BOSS`; `goal = 1` = `Goal.DEFEAT_BOSS`.) Do the same for `level_2.tres` with `params = { "boss": "rustler" }` (matches the existing level-2→rustler rule), and `level_3/4.tres` with `"pete"`.

- [ ] **Step 2: Verify the resources load** — open the project headless to force import; expect no parse/load error for the levels:
```
DISPLAY=:99 /home/projects/.local/bin/godot --headless --path godot --import 2>&1 | grep -iE "ERROR.*level_|SCRIPT ERROR" || echo "levels load clean"
```
Expected: `levels load clean`.

- [ ] **Step 3: Commit**
```bash
git add godot/resources/levels/level_1.tres godot/resources/levels/level_2.tres godot/resources/levels/level_3.tres godot/resources/levels/level_4.tres
git commit -m "sp2 slice1: author BOSS timeline event into level_1..4 .tres (dist 75)"
```

### Task 5: `level_3d` loads the LevelDef + plays its timeline (boss from data)

**Files:**
- Modify: `godot/scripts/level_3d.gd`

- [ ] **Step 1:** Add state + load near the other `var`s and in `_ready` (after `_gun_state` is set up). The `.tres` path matches the existing files:
```gdscript
var _level_def: LevelDef = null
var _level_player: LevelPlayer = null
var _level_distance: float = 0.0
var _boss_from_data: bool = false
```
In `_ready` (after the gun/HUD setup, before the first `_refresh_hud`):
```gdscript
	# SP2: load the data-driven level definition for the current level.
	var lvl: int = GameState.current_level if get_node_or_null("/root/GameState") else 1
	var def_path := "res://resources/levels/level_%d.tres" % lvl
	if ResourceLoader.exists(def_path):
		_level_def = load(def_path)
	if _level_def != null and not _level_def.events.is_empty():
		_level_player = LevelPlayer.new(_level_def.events)
		for ev in _level_def.events:
			if ev.kind == LevelEvent.EventKind.BOSS:
				_boss_from_data = true
```

- [ ] **Step 2:** In `_process`, where the scroll is computed (the `motion_delta` line ~4807), after `motion_delta` is known, advance the timeline:
```gdscript
	# SP2: advance the data timeline by the scrolled distance + dispatch.
	if _level_player != null:
		_level_distance += OBSTACLE_SPEED * motion_delta
		for ev in _level_player.advance(_level_distance):
			_dispatch_level_event(ev)
```

- [ ] **Step 3:** Add the dispatcher (near the `_spawn_*` functions):
```gdscript
# SP2: route a timeline event to its gameplay spawner. Only BOSS is wired in
# slice 1; later slices add the other EventKinds.
func _dispatch_level_event(ev: LevelEvent) -> void:
	match ev.kind:
		LevelEvent.EventKind.BOSS:
			if not _pete_spawned and not _test_range_mode:
				_pete_spawned = true
				if String(ev.params.get("boss", "pete")) == "rustler":
					_spawn_candy_rustler()
				else:
					_spawn_pete()
				_level_state = LevelState.BOSS
				DebugLog.add("SP2: boss spawned from data event at dist %.1f" % ev.distance)
```

- [ ] **Step 4:** Guard the hardcoded boss trigger so data wins. At the existing block `if _level_state == LevelState.PLAYING and not _pete_spawned and not _test_range_mode and _level_elapsed >= PETE_SPAWN_DELAY:` change the condition to also require `and not _boss_from_data`:
```gdscript
	if _level_state == LevelState.PLAYING and not _pete_spawned and not _test_range_mode and not _boss_from_data and _level_elapsed >= PETE_SPAWN_DELAY:
```
(So levels whose `.tres` has a BOSS event spawn from data; levels without one keep the legacy timer — no regression.)

- [ ] **Step 5: Verify in-engine** — render the gameplay scene headlessly to confirm no parse error and the scene loads:
```
.claude/skills/sp1-screenshot/capture.sh res://scenes/level_3d.tscn /tmp/sp2_s1.png 2>&1 | grep -iE "SCRIPT ERROR|Parse Error" || echo "level_3d loads clean"
```
Expected: `level_3d loads clean`. (Boss timing itself is verified on-device via sideload — Pete should still appear ~30s in on L1, now driven by the data event; the legacy timer no longer fires it.)

- [ ] **Step 6: Run the full GUT suite** to confirm no regressions:
```
DISPLAY=:99 /home/projects/.local/bin/godot --headless --path godot -s res://addons/gut/gut_cmdln.gd -gexit -gconfig=res://.gutconfig.json 2>&1 | tail -5
```
Expected: all tests passing.

- [ ] **Step 7: Commit**
```bash
git add godot/scripts/level_3d.gd
git commit -m "sp2 slice1: level_3d loads LevelDef + plays its timeline; boss spawns from a data event (legacy timer kept as no-data fallback)"
```

**Slice 1 done-when:** GUT green; L1 sideload shows Pete still arriving ~30s in, now logged as "boss spawned from data event"; no behaviour change otherwise.

---

## Slice 2 — Pacing + approach zones (outline)

- **`LevelDirector`** (`godot/scripts/level_director.gd`, RefCounted, GUT-tested): consumes `PACING`/`APPROACH_ZONE` events + live-enemy count; outputs `speed_factor` (1.0 normal / 0 halt / >1 fast) and `world_held`. Hybrid: authored cruise eased by action intensity (reuse the `_update_dynamic_camera` active-outlaw signal).
- **Generalize the scroll**: `motion_delta = delta * speed_factor` (replacing the `{0, delta}` gate; `_cart_encounter` ⇒ factor 0). Approach-zone `world_held` ⇒ factor 0 while outlaws keep advancing on real delta.
- **Approach-zone state machine** with per-zone exit: `CLEAR` (no live enemies in band + safety `timeout`), `TIMER`, `EVENT` (named flag).
- Author a `PACING` change + one `APPROACH_ZONE` into `level_1.tres`. Verify variable speed + a stand-and-fight halt (sideload).
- Tests: `LevelDirector` stepped through a synthetic track asserts factor/`world_held` transitions + exit conditions.

## Slice 3 — Curved/hilly path + holes/falling (outline)

- **`PathProfile`** sub-resource on `LevelDef`: `lateral: Curve` (bends), `height_amp/height_freq` (hills via `terrain_3d.height_at`), `holes: Array` of `{dist_start,dist_end,x_min,x_max,kind}`.
- Build the gameplay terrain from `PathProfile` (reuse `terrain_3d.gd`); place props/outlaws by `(distance, lateral)` → world via the curve + `height_at`.
- **Falling**: per-frame, sample each posse member + outlaw against `holes`; inside ⇒ fall tween + remove (posse via `_posse_count_3d` decrement like the cliff mechanic; outlaws via death path). Active only while the world moves or a zone is live.
- Verify: a visible curve, a hill, an outlaw + a posse member dropping into a hole.

## Slice 4 — Port remaining EventKinds + author a demo L2 (outline)

- Extend `_dispatch_level_event` for `OUTLAW, GATE, PROP, BONUS, PUSHED_WAGON, GOLD_RUSH` → existing `_spawn_*` with `params`; retire the corresponding internal timers (guarded by "this level is data-driven").
- Add `goal`/win-condition checking (`REACH_END` at `length`, `SURVIVE` seconds, `DEFEAT_BOSS`).
- Hand-author a distinct `level_2.tres` proving the toolkit composes a new level. → then **SP3 = the editor** (UI over `LevelDef`).

---

## Self-Review

- **Spec coverage:** data model (Tasks 1-4), gameplay-plays-it (Task 5), pacing (slice 2), terrain/holes/falling (slice 3), remaining pieces + goal (slice 4), fallback-no-regression (Task 5 step 4). ✔
- **Type consistency:** `LevelEvent.EventKind.BOSS` (=5), `LevelDef.Goal.DEFEAT_BOSS` (=1), `LevelPlayer.new(events)` / `advance()->Array`, `_dispatch_level_event(LevelEvent)` — used consistently across tasks + the `.tres` (`kind = 5`, `goal = 1`). ✔
- **No placeholders:** every code/edit/command step is concrete. ✔
- **Regression guard:** `_boss_from_data` gate means non-data levels keep the legacy boss timer; GUT suite run in Task 5 step 6. ✔
