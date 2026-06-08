# Granny's Chicken Chase — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build "Granny's Chicken Chase" — a once-per-24h booster minigame where the cowboy auto-runs a short candy-farm lane catching 8 popcorn chickens (with a few stumble-obstacles), each caught hen flying to a wrapped-taffy collection candy, for a proportional +0–20 starting-posse "Posse Brew" awarded by the chatty Candy Granny.

**Architecture:** All testable logic is pure: the **24h gate + proportional reward + pending-booster** live as fields and static functions on the `GameState` autoload (the `stars_for`/`win_header` pattern, unit-tested in GUT), and the **run rules** (countdown, caught tally, stumble cooldown, end condition) live in a pure `ChickenChaseRun` RefCounted (the `RaisinKiddState` pattern). The scene `chicken_chase.gd` does only rendering/input/juice and is device-verified. All visuals are **2D paper-cutout** (Candy-Crush register) via the existing breathing/sway prop pipeline — no new 3D shaders.

**Tech Stack:** Godot 4.6.1, GDScript, GUT tests (`godot/test/`). **Tests run on GitHub Actions CI (`.github/workflows/test.yml`), NOT locally** (this VPS is memory-constrained — see project memory). The red→green check happens in CI after `git push`; verify with `gh run watch`.

**Source spec:** `docs/superpowers/specs/2026-06-08-chicken-chase-minigame-design.md`. **Memory:** `[[project_chicken_minigame_boosters]]`.

**Asset-track prerequisite (parallel, Tasks 8–9):** popcorn-chicken + Granny + hut paper-cutout art and Granny VO (voice `vFLqXa8bgbofGarf6fZh`). Code Tasks 1–7 do NOT block on these — they wire against placeholder sprites / silent VO and swap in finals when ready.

---

## File Structure

**New files:**
- `godot/scripts/chicken_chase_run.gd` — pure run-rules RefCounted (timer, caught/8 tally, stumble cooldown, end condition, per-tick events). No scene refs.
- `godot/test/test_chicken_chase_run.gd` — GUT tests for the run rules.
- `godot/test/test_chicken_chase_gamestate.gd` — GUT tests for the GameState gate/reward additions.
- `godot/scenes/chicken_chase.tscn` + `godot/scripts/chicken_chase.gd` — the minigame scene (runner, swipe, lunge-catch, obstacles, fly-to-taffy, counter, results).
- `godot/scripts/granny_popup.gd` + `godot/scenes/ui/granny_popup.tscn` — the "ready" pop-up + cooldown badge.
- `tools/gen_granny_vo.py` — Granny VO generator.

**Modified files:**
- `godot/scripts/game_state.gd` — the 24h gate, `pending_posse_bonus`, static `posse_bonus_for`, persistence.
- `godot/test/test_game_state.gd` — (left as-is; new GameState tests go in the dedicated new test file to keep diffs focused).
- `godot/scripts/level_3d.gd:705-706` — apply (and clear) the pending posse bonus at level start.
- `godot/scripts/level_select.gd` — show the Granny pop-up/badge when available; route to the minigame.

**How to run a single test in CI terms:** push the branch; the GUT job runs the full suite. To watch: `gh run list --branch <branch> --workflow=test.yml --limit 1` then `gh run watch <id> --exit-status`. (The workflow runs `godot --headless --path godot -s res://addons/gut/gut_cmdln.gd -gconfig=res://.gutconfig.json`.) Each TDD task below still writes the test first and the implementation second; "verify fail/pass" happens on the CI run for that task's push (batch a few tasks per push to save CI minutes).

---

## Task 1: GameState — 24h gate + proportional reward + pending booster

**Files:**
- Modify: `godot/scripts/game_state.gd`
- Test: `godot/test/test_chicken_chase_gamestate.gd` (new)

- [ ] **Step 1: Write the failing test.** Create `godot/test/test_chicken_chase_gamestate.gd`:
```gdscript
extends GutTest

const GameStateScript = preload("res://scripts/game_state.gd")

var state

func before_each():
	state = autofree(GameStateScript.new())

# --- proportional reward mapping (pure static) ---
func test_posse_bonus_zero_for_zero_caught():
	assert_eq(GameStateScript.posse_bonus_for(0), 0)

func test_posse_bonus_max_for_full_haul():
	assert_eq(GameStateScript.posse_bonus_for(8), 20)

func test_posse_bonus_is_rounded_proportion():
	# round(caught/8 * 20): 1->3, 3->8, 5->13, 7->18
	assert_eq(GameStateScript.posse_bonus_for(1), 3)
	assert_eq(GameStateScript.posse_bonus_for(3), 8)
	assert_eq(GameStateScript.posse_bonus_for(5), 13)
	assert_eq(GameStateScript.posse_bonus_for(7), 18)

func test_posse_bonus_clamps_out_of_range():
	assert_eq(GameStateScript.posse_bonus_for(-2), 0)
	assert_eq(GameStateScript.posse_bonus_for(99), 20)

# --- 24h gate ---
func test_chase_available_when_never_played():
	assert_true(state.chicken_chase_available(), "available before first play")

func test_chase_unavailable_right_after_spend():
	state.chicken_chase_spend()
	assert_false(state.chicken_chase_available(), "locked immediately after a run begins")

func test_chase_available_again_after_24h():
	state.chicken_chase_spend()
	# fast-forward the recorded timestamp 24h+ into the past
	state.chicken_chase_last_unix -= 24 * 3600 + 1
	assert_true(state.chicken_chase_available(), "re-available after 24h")

func test_seconds_until_chase_decreases_with_time():
	state.chicken_chase_spend()
	var full: int = state.seconds_until_chase()
	state.chicken_chase_last_unix -= 1000
	assert_lt(state.seconds_until_chase(), full)
	assert_eq(state.seconds_until_chase() if state.chicken_chase_available() else -1, -1) if false else null

# --- pending booster ---
func test_award_sets_pending_bonus_from_haul():
	state.chicken_chase_award(6)
	assert_eq(state.pending_posse_bonus, 15)

func test_claim_returns_and_clears_pending_bonus():
	state.chicken_chase_award(8)
	assert_eq(state.claim_posse_bonus(), 20, "claim returns the pending bonus")
	assert_eq(state.pending_posse_bonus, 0, "claim clears it")
	assert_eq(state.claim_posse_bonus(), 0, "second claim is zero")
```
(Delete the deliberately-awkward `assert_eq(... if false else null)` line — it was a placeholder; replace `test_seconds_until_chase_decreases_with_time` body with just the first three asserts.)

Corrected `test_seconds_until_chase_decreases_with_time`:
```gdscript
func test_seconds_until_chase_decreases_with_time():
	state.chicken_chase_spend()
	var full: int = state.seconds_until_chase()
	state.chicken_chase_last_unix -= 1000
	assert_lt(state.seconds_until_chase(), full)
```

- [ ] **Step 2: Implement in `game_state.gd`.** Add the field near the other persisted vars (after `var just_won_level` / `continue_to_next`, ~line 41):
```gdscript
# Chicken-chase minigame: unix time the last attempt was SPENT (0 = never),
# and the one-shot starting-posse bonus awarded by the brew (consumed at the
# next level start). Both persisted.
const CHICKEN_CHASE_COOLDOWN_S: int = 24 * 3600
var chicken_chase_last_unix: int = 0
var pending_posse_bonus: int = 0
```
Add the methods (put the static one near `stars_for`, ~line 198; the instance ones near `apply_regen`):
```gdscript
# Proportional Posse Brew: round(caught/8 * 20), clamped 0..20. Pure + testable.
static func posse_bonus_for(caught: int) -> int:
	var c: int = clampi(caught, 0, 8)
	return int(round(float(c) / 8.0 * 20.0))

func chicken_chase_available() -> bool:
	if chicken_chase_last_unix == 0:
		return true
	return int(Time.get_unix_time_from_system()) - chicken_chase_last_unix >= CHICKEN_CHASE_COOLDOWN_S

# Seconds until the chase is available again (0 if available now).
func seconds_until_chase() -> int:
	if chicken_chase_available():
		return 0
	return CHICKEN_CHASE_COOLDOWN_S - (int(Time.get_unix_time_from_system()) - chicken_chase_last_unix)

# Spend the daily attempt (call when a run actually BEGINS).
func chicken_chase_spend() -> void:
	chicken_chase_last_unix = int(Time.get_unix_time_from_system())
	_save_to_disk()

# Award the brew for a finished run's haul (sets the pending one-shot bonus).
func chicken_chase_award(caught: int) -> void:
	pending_posse_bonus = posse_bonus_for(caught)
	_save_to_disk()

# Consume the pending bonus at level start: returns it and clears to 0.
func claim_posse_bonus() -> int:
	var b: int = pending_posse_bonus
	pending_posse_bonus = 0
	if b != 0:
		_save_to_disk()
	return b
```
Persist the two fields: in `_save_to_disk()` (after the `meta`/`level_best` set, ~line 159) add:
```gdscript
	cfg.set_value("minigame", "chicken_chase_last_unix", chicken_chase_last_unix)
	cfg.set_value("minigame", "pending_posse_bonus", pending_posse_bonus)
```
In `_load_from_disk()` (after `level_best`, ~line 175) add:
```gdscript
	chicken_chase_last_unix = int(cfg.get_value("minigame", "chicken_chase_last_unix", 0))
	pending_posse_bonus = int(cfg.get_value("minigame", "pending_posse_bonus", 0))
```

- [ ] **Step 3: Commit** (push batched with Task 3 to run CI once):
```bash
git add godot/scripts/game_state.gd godot/test/test_chicken_chase_gamestate.gd
git commit -m "feat(chicken): GameState 24h gate + proportional posse-brew reward"
```

---

## Task 2: Apply the pending posse bonus at level start

**Files:**
- Modify: `godot/scripts/level_3d.gd:705-706`

The current code (around line 705) is:
```gdscript
	if _level_def != null and _level_def.start_posse > 0 and _level_def.start_posse != _posse_count_3d:
		_posse_count_3d = _level_def.start_posse
```

- [ ] **Step 1: Add the booster claim.** Replace that block with:
```gdscript
	if _level_def != null and _level_def.start_posse > 0 and _level_def.start_posse != _posse_count_3d:
		_posse_count_3d = _level_def.start_posse
	# Chicken-chase Posse Brew: one-shot starting-posse bonus, consumed here.
	if get_node_or_null("/root/GameState") != null:
		var _brew: int = GameState.claim_posse_bonus()
		if _brew > 0:
			_posse_count_3d += _brew
			DebugLog.add("posse brew applied: +%d (start now %d)" % [_brew, _posse_count_3d])
```
Note: `claim_posse_bonus()` clears the pending bonus, so it only applies to the very next level start (exactly one level), matching the spec. No test here (it's a one-line scene hook over the already-tested `claim_posse_bonus`); verified on device in Task 10.

- [ ] **Step 2: Commit:**
```bash
git add godot/scripts/level_3d.gd
git commit -m "feat(chicken): apply pending posse-brew bonus at level start"
```

---

## Task 3: `ChickenChaseRun` — pure run rules (timer, tally, stumble, end)

**Files:**
- Create: `godot/scripts/chicken_chase_run.gd`
- Test: `godot/test/test_chicken_chase_run.gd`

The scene drives this each frame: it reports catches and stumbles; the run owns the clock, the `caught` tally, the stumble lockout, and the end condition.

- [ ] **Step 1: Write the failing test.** Create `godot/test/test_chicken_chase_run.gd`:
```gdscript
extends GutTest

const ChickenChaseRun = preload("res://scripts/chicken_chase_run.gd")

func _run() -> ChickenChaseRun:
	return ChickenChaseRun.new()

func test_starts_unfinished_zero_caught_full_timer():
	var r = _run()
	assert_eq(r.caught, 0)
	assert_false(r.is_over())
	assert_almost_eq(r.time_left, ChickenChaseRun.DURATION, 0.001)

func test_register_catch_increments_and_caps_at_flock():
	var r = _run()
	for i in range(ChickenChaseRun.FLOCK + 3):
		r.register_catch()
	assert_eq(r.caught, ChickenChaseRun.FLOCK, "caught caps at the flock size")

func test_can_lunge_unless_stumbling():
	var r = _run()
	assert_true(r.can_lunge(), "can lunge at start")
	r.stumble()
	assert_false(r.can_lunge(), "cannot lunge while stumbling")

func test_stumble_recovers_after_lockout():
	var r = _run()
	r.stumble()
	r.tick(ChickenChaseRun.STUMBLE_LOCKOUT + 0.05)
	assert_true(r.can_lunge(), "lunge restored after the stumble lockout elapses")

func test_catch_blocked_while_stumbling():
	var r = _run()
	r.stumble()
	var ok: bool = r.try_catch()
	assert_false(ok, "try_catch returns false mid-stumble")
	assert_eq(r.caught, 0, "no catch credited mid-stumble")

func test_try_catch_credits_when_clear():
	var r = _run()
	assert_true(r.try_catch())
	assert_eq(r.caught, 1)

func test_timer_ends_the_run():
	var r = _run()
	r.tick(ChickenChaseRun.DURATION + 0.1)
	assert_true(r.is_over(), "run ends when the timer expires")
	assert_almost_eq(r.time_left, 0.0, 0.001)

func test_run_ends_early_when_flock_complete():
	var r = _run()
	for i in range(ChickenChaseRun.FLOCK):
		r.try_catch()
	assert_true(r.is_over(), "catching the whole flock ends the run early")

func test_tick_after_over_is_noop():
	var r = _run()
	r.tick(ChickenChaseRun.DURATION + 1.0)
	var t: float = r.time_left
	r.tick(5.0)
	assert_eq(r.time_left, t, "ticking after over does nothing")
```

- [ ] **Step 2: Implement `chicken_chase_run.gd`:**
```gdscript
class_name ChickenChaseRun
extends RefCounted

# Pure run-rules for Granny's Chicken Chase. The scene reports catches/stumbles
# and ticks the clock; this owns the tally, the stumble lockout, and the end
# condition. No scene refs — unit-tested in GUT (the RaisinKiddState pattern).

const DURATION: float = 25.0          # allotted seconds (device-tuned)
const FLOCK: int = 8                  # hens in the flock
const STUMBLE_LOCKOUT: float = 0.6    # seconds the cowboy can't lunge after an obstacle

var caught: int = 0
var time_left: float = DURATION
var _stumble_t: float = 0.0
var _over: bool = false

func is_over() -> bool:
	return _over

func can_lunge() -> bool:
	return _stumble_t <= 0.0 and not _over

# Credit a catch (caps at FLOCK). Use register_catch when the scene has already
# decided a catch lands; use try_catch when the run should gate on stumble state.
func register_catch() -> void:
	if _over:
		return
	caught = mini(FLOCK, caught + 1)
	if caught >= FLOCK:
		_finish()

func try_catch() -> bool:
	if not can_lunge():
		return false
	register_catch()
	return true

func stumble() -> void:
	if _over:
		return
	_stumble_t = STUMBLE_LOCKOUT

func tick(delta: float) -> void:
	if _over:
		return
	_stumble_t = maxf(0.0, _stumble_t - delta)
	time_left = maxf(0.0, time_left - delta)
	if time_left <= 0.0:
		_finish()

func _finish() -> void:
	_over = true
	time_left = 0.0
```

- [ ] **Step 3: Commit + push (batched with Task 1) and watch CI:**
```bash
git add godot/scripts/chicken_chase_run.gd godot/test/test_chicken_chase_run.gd
git commit -m "feat(chicken): ChickenChaseRun pure run-rules + tests"
git push origin <branch>
# watch: gh run list --branch <branch> --workflow=test.yml --limit 1 ; gh run watch <id> --exit-status
```
Expected: GUT job green (Task 1 + Task 3 tests pass).

---

## Task 4: The `chicken_chase` scene (runner + catch + obstacles + fly-to-taffy)

**Files:**
- Create: `godot/scenes/chicken_chase.tscn`, `godot/scripts/chicken_chase.gd`

This is scene wiring (device-verified, no unit test). It reuses the farm terrain + breathing-prop cutout pipeline and drives a `ChickenChaseRun`. Build it as a self-contained 3D auto-runner — do NOT pull in `level_3d.gd`'s combat. Keep `chicken_chase.gd` focused.

- [ ] **Step 1: Scene skeleton.** Create `godot/scenes/chicken_chase.tscn` with root `Node3D` (script `chicken_chase.gd`), children: a `Camera3D` (angled like the main game's gameplay cam ~-35°), a `DirectionalLight3D`, a `Node3D` named `Lane` (holds terrain + scatter), a `Node3D` named `Cowboy` (the running cutout), a `Node3D` named `Flock`, a `Node3D` named `Obstacles`, and a `CanvasLayer` named `UI` holding: a `Control` `TaffyCounter` (the wrapped-taffy collection candy + a `caught/8` Label, Rye font, mirroring `$UI/HeartsCutout` styling), a `Label` `Timer`, and a `Control` `Results` (hidden until the run ends).

- [ ] **Step 2: Implement `chicken_chase.gd`** with this structure (complete, runnable; tuning constants are device-adjusted in Task 10):
```gdscript
extends Node3D

# Granny's Chicken Chase minigame. Self-contained auto-runner: the cowboy runs
# a candy-farm lane, the player swipes to steer + taps to lunge-grab popcorn
# hens; caught hens fly to the wrapped-taffy counter. Rules live in the pure
# ChickenChaseRun; this does rendering, input, and Soda-Crush juice.

const ChickenChaseRun := preload("res://scripts/chicken_chase_run.gd")
const _BREATHING_SHADER := preload("res://shaders/breathing_prop.gdshader")

const RUN_SPEED: float = 8.0           # forward auto-run speed
const STEER_SPEED: float = 9.0         # lateral steering response
const LANE_HALF_W: float = 4.0         # how far the cowboy can steer
const LUNGE_RANGE_Z: float = 3.0       # forward reach of a lunge-grab
const LUNGE_RANGE_X: float = 1.6
const CHICKEN_JUKE_CHANCE: float = 0.45 # chance a hen jukes a lunge if in range
const OBSTACLE_HIT_RADIUS: float = 1.1

var _run: ChickenChaseRun = null
var _started: bool = false

@onready var _cowboy: Node3D = $Cowboy
@onready var _flock: Node3D = $Flock
@onready var _obstacles: Node3D = $Obstacles
@onready var _taffy_label: Label = $UI/TaffyCounter/Count
@onready var _timer_label: Label = $UI/Timer
@onready var _results: Control = $UI/Results

func _ready() -> void:
	_run = ChickenChaseRun.new()
	# Spend the daily attempt the moment the run begins (spec §4/§5).
	if get_node_or_null("/root/GameState"):
		GameState.chicken_chase_spend()
	_spawn_flock()
	_spawn_obstacles()
	if get_node_or_null("/root/AudioBus") and AudioBus.has_method("play_character_line"):
		AudioBus.play_character_line("granny_chase_%d" % (randi() % 2))
	_refresh_hud()

func _process(delta: float) -> void:
	if _run == null or _run.is_over():
		return
	_run.tick(delta)
	_cowboy.position.z -= RUN_SPEED * delta          # run "into" the screen (-Z)
	_advance_flock(delta)
	_advance_obstacles(delta)
	_check_obstacle_contact()
	_refresh_hud()
	if _run.is_over():
		_end_run()

func _unhandled_input(ev: InputEvent) -> void:
	if _run == null or _run.is_over():
		return
	if ev is InputEventScreenDrag:
		_cowboy.position.x = clampf(_cowboy.position.x + ev.relative.x * 0.01 * STEER_SPEED * get_process_delta_time(), -LANE_HALF_W, LANE_HALF_W)
	elif ev is InputEventScreenTouch and ev.pressed:
		_attempt_lunge()
	elif ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		_attempt_lunge()   # desktop/debug

func _attempt_lunge() -> void:
	if not _run.can_lunge():
		return
	var target: Node3D = _nearest_catchable_hen()
	if target == null:
		return
	# Slippery: a hen in range may juke (telegraph handled in _advance_flock).
	if randf() < CHICKEN_JUKE_CHANCE and not target.get_meta("committed", false):
		target.set_meta("juking", true)        # whiff — it darts aside next frames
		return
	if _run.try_catch():
		_fly_hen_to_taffy(target)

func _nearest_catchable_hen() -> Node3D:
	var best: Node3D = null
	var best_d := 1e9
	for h in _flock.get_children():
		if not (h is Node3D) or h.get_meta("caught", false):
			continue
		var dz: float = _cowboy.position.z - h.position.z   # hen is ahead (more -Z)
		var dx: float = absf(h.position.x - _cowboy.position.x)
		if dz >= 0.0 and dz <= LUNGE_RANGE_Z and dx <= LUNGE_RANGE_X and dz < best_d:
			best_d = dz; best = h
	return best

func _fly_hen_to_taffy(hen: Node3D) -> void:
	hen.set_meta("caught", true)
	# Soda-Crush collection: arc the hen up to the taffy counter, then pop.
	var taffy_world := $UI/TaffyCounter as Control
	var tw := create_tween()
	tw.tween_property(hen, "position", hen.position + Vector3(0, 3.0, 2.0), 0.18)
	tw.parallel().tween_property(hen, "scale", hen.scale * 0.4, 0.35)
	tw.tween_callback(func():
		hen.visible = false
		if get_node_or_null("/root/AudioBus") and AudioBus.has_method("play_sfx"):
			AudioBus.play_sfx("posse_join")   # reuse a juicy pop sfx; swap if a bespoke one is added
		_pop_taffy_counter())

func _pop_taffy_counter() -> void:
	var t := $UI/TaffyCounter as Control
	var tw := create_tween()
	t.scale = Vector2(1.25, 1.25)
	tw.tween_property(t, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _spawn_flock() -> void:
	# Place FLOCK popcorn-hen cutouts ahead of the cowboy at varied x/z.
	var tex: Texture2D = _load_or_placeholder("res://assets/sprites/props/chicken_popcorn.png")
	for i in range(ChickenChaseRun.FLOCK):
		var hen := _make_cutout(tex, 1.0, 1.0)
		hen.position = Vector3(randf_range(-LANE_HALF_W, LANE_HALF_W), 0.6, _cowboy.position.z - 8.0 - i * 3.0)
		hen.set_meta("caught", false)
		hen.set_meta("phase", randf() * TAU)
		_flock.add_child(hen)

func _advance_flock(delta: float) -> void:
	for h in _flock.get_children():
		if not (h is Node3D) or h.get_meta("caught", false):
			continue
		# slow drift + bob; juking hens dart laterally away from the cowboy
		var ph: float = h.get_meta("phase", 0.0) + delta
		h.set_meta("phase", ph)
		h.position.x += sin(ph * 3.0) * 0.6 * delta
		if h.get_meta("juking", false):
			var away: float = signf(h.position.x - _cowboy.position.x)
			h.position.x = clampf(h.position.x + away * 4.0 * delta, -LANE_HALF_W, LANE_HALF_W)

func _spawn_obstacles() -> void:
	# A few non-lethal candy-farm obstacles along the lane.
	var tex: Texture2D = _load_or_placeholder("res://assets/sprites/props/barrel.png")
	for i in range(4):
		var ob := _make_cutout(tex, 1.2, 1.4)
		ob.position = Vector3(randf_range(-LANE_HALF_W, LANE_HALF_W), 0.7, _cowboy.position.z - 12.0 - i * 6.0)
		_obstacles.add_child(ob)

func _advance_obstacles(_delta: float) -> void:
	pass   # obstacles are static in world; the cowboy runs past/into them

func _check_obstacle_contact() -> void:
	if not _run.can_lunge():
		return
	for ob in _obstacles.get_children():
		if not (ob is Node3D) or ob.get_meta("spent", false):
			continue
		var dz: float = absf(ob.position.z - _cowboy.position.z)
		var dx: float = absf(ob.position.x - _cowboy.position.x)
		if dz < OBSTACLE_HIT_RADIUS and dx < OBSTACLE_HIT_RADIUS:
			ob.set_meta("spent", true)
			_run.stumble()
			# small juice: shake the cowboy
			var tw := create_tween()
			tw.tween_property(_cowboy, "rotation:z", 0.3, 0.08)
			tw.tween_property(_cowboy, "rotation:z", 0.0, 0.2)

func _refresh_hud() -> void:
	_taffy_label.text = "%d/%d" % [_run.caught, ChickenChaseRun.FLOCK]
	_timer_label.text = "%0.0f" % ceil(_run.time_left)

func _end_run() -> void:
	# Award the brew, show results + Granny's scaled reaction.
	if get_node_or_null("/root/GameState"):
		GameState.chicken_chase_award(_run.caught)
	var line := "granny_win_zero_0"
	if _run.caught >= ChickenChaseRun.FLOCK:
		line = "granny_win_full_0"
	elif _run.caught > 0:
		line = "granny_win_partial_0"
	if get_node_or_null("/root/AudioBus") and AudioBus.has_method("play_character_line"):
		AudioBus.play_character_line(line)
	_show_results()

func _show_results() -> void:
	_results.visible = true
	var bonus: int = GameState.posse_bonus_for(_run.caught) if get_node_or_null("/root/GameState") else 0
	($UI/Results/Headline as Label).text = "+%d POSSE BREW" % bonus
	# Continue button (wired in the .tscn) → back to the map.

# Return to the level-select map (button callback wired in the .tscn).
func _on_continue_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/level_select.tscn")

# ── cutout helpers (mirror level_3d's breathing-prop approach, self-contained) ──
func _make_cutout(tex: Texture2D, w: float, h: float) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(w, h)
	plane.subdivide_width = 5
	plane.subdivide_depth = 7
	plane.orientation = 2   # FACE_Z
	mesh.mesh = plane
	var mat := ShaderMaterial.new()
	mat.shader = _BREATHING_SHADER
	mat.set_shader_parameter("albedo_tex", tex)
	mat.set_shader_parameter("modulate", Color(1, 1, 1, 1))
	mat.set_shader_parameter("sway_amp", 0.06)
	mat.set_shader_parameter("sway_freq", 2.0)
	mat.set_shader_parameter("bob_amp", 0.03)
	mat.set_shader_parameter("bob_freq", 3.0)
	mat.set_shader_parameter("time_offset", randf() * 6.28)
	mat.set_shader_parameter("mesh_height", h)
	mesh.material_override = mat
	return mesh

func _load_or_placeholder(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	return load("res://assets/sprites/props/chicken_static.png") as Texture2D  # placeholder until popcorn art lands
```
Notes for the implementer: confirm `breathing_prop.gdshader` exposes the uniforms used (`albedo_tex, modulate, sway_amp, sway_freq, bob_amp, bob_freq, time_offset, mesh_height`) — they match `level_3d.gd`'s `_make_breathing_prop`. The farm terrain in `Lane` can be added by instancing the same terrain build the main game uses, or a simple textured ground plane with the `ground_farm.png` texture for v1 (the chase is short). Wire the `Continue` button's `pressed` signal to `_on_continue_pressed`.

- [ ] **Step 3: Headless parse check via CI** — push; the GUT job imports the project (parse-checks all scripts). Expected: no parse errors for `chicken_chase.gd`. (Visual correctness is Task 10.)

- [ ] **Step 4: Commit:**
```bash
git add godot/scenes/chicken_chase.tscn godot/scripts/chicken_chase.gd
git commit -m "feat(chicken): chicken-chase scene (runner, lunge-catch, obstacles, fly-to-taffy)"
```

---

## Task 5: Granny pop-up entry + cooldown badge (level-select)

**Files:**
- Create: `godot/scenes/ui/granny_popup.tscn`, `godot/scripts/granny_popup.gd`
- Modify: `godot/scripts/level_select.gd`

- [ ] **Step 1: Build the pop-up.** Create `godot/scripts/granny_popup.gd`:
```gdscript
extends Control

# "Help an old gal round up her hens?" pop-up + persistent cooldown badge for
# Granny's Chicken Chase. Shown on the level-select map when the chase is
# available; the daily attempt is only spent when the run actually begins
# (in chicken_chase.gd), so dismissing here never burns the day.

signal play_pressed

@onready var _prompt: Control = $Prompt
@onready var _badge: Control = $Badge
@onready var _badge_timer: Label = $Badge/Cooldown

func _ready() -> void:
	($Prompt/Play as BaseButton).pressed.connect(func():
		emit_signal("play_pressed"))
	($Prompt/NotNow as BaseButton).pressed.connect(func():
		_prompt.visible = false)   # keep the badge so they can start later
	_refresh()

func _refresh() -> void:
	var available: bool = get_node_or_null("/root/GameState") == null or GameState.chicken_chase_available()
	_prompt.visible = available
	_badge.visible = true
	if available:
		_badge_timer.text = "Ready!"
	else:
		var s: int = GameState.seconds_until_chase()
		_badge_timer.text = "%02d:%02d" % [s / 3600, (s % 3600) / 60]

func _process(_dt: float) -> void:
	# cheap minute-resolution refresh of the cooldown label
	if _badge.visible and not _prompt.visible:
		_refresh()
```
Create `granny_popup.tscn`: root `Control` (script above) with a `Prompt` panel (Granny cutout art `granny_concept_study.png` placeholder, the intro line text, a `Play` button + a `NotNow` button) and a `Badge` (a small Granny-head icon + `Cooldown` Label). Tapping the badge when available re-shows `Prompt` (wire the badge's `gui_input`/a button to set `_prompt.visible = true`).

- [ ] **Step 2: Wire into `level_select.gd`.** In `level_select.gd` `_ready()` (the map scene), instance the pop-up into the UI layer and route `play_pressed` to the minigame:
```gdscript
	var granny := preload("res://scenes/ui/granny_popup.tscn").instantiate()
	add_child(granny)
	granny.play_pressed.connect(func():
		get_tree().change_scene_to_file("res://scenes/chicken_chase.tscn"))
```
(Place it in the same CanvasLayer/UI the map uses; match the existing add-child pattern in `level_select.gd`.)

- [ ] **Step 3: Commit:**
```bash
git add godot/scenes/ui/granny_popup.tscn godot/scripts/granny_popup.gd godot/scripts/level_select.gd
git commit -m "feat(chicken): Granny pop-up entry + cooldown badge on the map"
```

---

## Task 6: Debug-menu hook (jump straight to the chase)

**Files:**
- Modify: `godot/scenes/debug_menu.tscn` + `godot/scripts/debug_menu.gd`

So the chase is testable without waiting 24h.

- [ ] **Step 1:** Add a "CHICKEN CHASE" button to `debug_menu.tscn` and, in `debug_menu.gd` (mirroring the existing button handlers ~line 231), a handler:
```gdscript
func _on_chicken_chase_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/chicken_chase.tscn")
```
Connect the button's `pressed` to it.

- [ ] **Step 2: Commit:**
```bash
git add godot/scenes/debug_menu.tscn godot/scripts/debug_menu.gd
git commit -m "feat(chicken): debug-menu jump to the chicken chase"
```

---

## Task 7: Granny VO (chatty banks)

**Files:**
- Modify: `godot/assets/text/en.json` (add `boss.granny_dialog_*` — or a new `granny` block)
- Create: `tools/gen_granny_vo.py`
- Output: `godot/assets/audio/characters/granny_*.mp3` (+ authored `.import`)

The slugs the scene/pop-up call: `granny_chase_0..1`, `granny_win_full_0`, `granny_win_partial_0`, `granny_win_zero_0`, `granny_cackle_0..3`; plus `granny_intro_0..2`, `granny_chatter_0..4`, `granny_cooldown_0`.

- [ ] **Step 1:** Add the line banks to `en.json` (verbatim text from spec §6) under a `granny` object: `granny_dialog_intro` (3), `granny_dialog_chatter` (5), `granny_dialog_chase` (2), `granny_dialog_win_full` (1), `granny_dialog_win_partial` (1), `granny_dialog_win_zero` (1), `granny_dialog_cooldown` (1). **NOTE: the `cackle` bank is NOT TTS** — the owner supplied 4 real cackle SFX, already committed as `godot/assets/audio/characters/granny_cackle_0..3.mp3` (+ `.import`). Do not generate or overwrite the cackle slots.
- [ ] **Step 2:** Create `tools/gen_granny_vo.py` modeled on `tools/gen_rustler_vo.py`: voice `vFLqXa8bgbofGarf6fZh`, model `eleven_v3`, `apply_text_normalization="on"`, `SLOTS` mapping the en.json keys → slugs (`intro/chatter/chase/win_full/win_partial/win_zero/cooldown` — **omit `cackle`**, it's the owner SFX), a `PERFORMANCE` dict tagging each line for a chatty sweet-but-sly delivery (`[cackles]`, `[laughs]`, `[whispers]`, `[mischievously]`), output `godot/assets/audio/characters/granny_<slot>_<n>.mp3`.
- [ ] **Step 3:** Run it: `/home/projects/roguelike/.venv-eleven/bin/python tools/gen_granny_vo.py`. Author `.import` sidecars (md5 = `md5(res-path)`, unique uids) the same way the Raisin VO did. Register the slugs work via `AudioBus.play_character_line` (it loads `characters/<slug>.mp3` directly — no registration needed).
- [ ] **Step 4: Commit:**
```bash
git add godot/assets/text/en.json tools/gen_granny_vo.py godot/assets/audio/characters/granny_*
git commit -m "feat(chicken): Candy Granny chatty voice-over set"
```

---

## Task 8: Paper-cutout art — popcorn chicken, Granny, hut/cauldron

**Files:**
- Create: `godot/assets/sprites/props/chicken_popcorn.png`, `granny_cutout.png`, `granny_hut.png`, `granny_cauldron.png` (+ `.import`)

- [ ] **Step 1:** Via NB Pro (`tools/nb_pro_render.py`), generate **paper-cutout illustration** assets (Candy-Crush register, transparent/flat background for alpha-cutout), using the committed concept art + refs in `docs/superpowers/assets/chicken_minigame_2026-06-08/` as style references:
  - `chicken_popcorn.png` — a popcorn hen (puffed-popcorn body, kernel beak, butter tuft), side ¾ view, alpha cutout.
  - `granny_cutout.png` — Candy Granny full-body paper-cutout, neutral pose (from `granny_concept_study.png`).
  - **`granny_cackle_0..3.png`** — a 4-frame **cackle flipbook**: (0) neutral, (1) wind-up/inhale, (2) head-back + jaw-open mid-cackle, (3) settling grin. Consistent registration/anchor across frames so they swap cleanly. (This IS the "good cackle animation" deliverable.)
  - `granny_hut.png`, `granny_cauldron.png` — the cottage + bubbling cauldron cutouts.
- [ ] **Step 2:** Place sprites under `res://assets/sprites/props/`, author `.import` (Godot texture default), confirm `chicken_chase.gd`'s `_load_or_placeholder` finds the real popcorn-hen texture (drop the placeholder), and wire the `granny_cackle_*` frames into the cackle player from Task 8b.
- [ ] **Step 3: Commit.**

---

## Task 8b: Random "inappropriate" cackle (animation + VO trigger)

**Files:**
- Create: `godot/scripts/granny_cackler.gd`
- Modify: `godot/scripts/granny_popup.gd` (and the results `Control` in `chicken_chase.gd`) to host a cackler.

Granny cackles at random, slightly-wrong moments wherever she's on screen (spec §6). Build one reusable component.

- [ ] **Step 1:** Create `godot/scripts/granny_cackler.gd` — a node that, given a `TextureRect`/`Sprite2D` showing Granny, plays the cackle flipbook + a `granny_cackle_*` VO line on a random timer:
```gdscript
extends Node

# Fires Granny's cackle (flipbook frames + VO burst) at random intervals so she
# cackles "inappropriately" wherever she's shown (pop-up, results, idle).

const FRAMES: Array[String] = [
	"res://assets/sprites/props/granny_cackle_0.png",
	"res://assets/sprites/props/granny_cackle_1.png",
	"res://assets/sprites/props/granny_cackle_2.png",
	"res://assets/sprites/props/granny_cackle_3.png",
]
const MIN_GAP: float = 5.0
const MAX_GAP: float = 12.0
const FRAME_T: float = 0.12          # seconds per cackle frame

@export var sprite_path: NodePath    # the TextureRect/Sprite2D to animate
var _t: float = 0.0
var _neutral: Texture2D = null
var _sprite: CanvasItem = null

func _ready() -> void:
	_sprite = get_node_or_null(sprite_path)
	if _sprite and "texture" in _sprite:
		_neutral = _sprite.texture
	_arm()

func _arm() -> void:
	_t = randf_range(MIN_GAP, MAX_GAP)

func _process(delta: float) -> void:
	if _sprite == null:
		return
	_t -= delta
	if _t <= 0.0:
		_cackle()
		_arm()

func _cackle() -> void:
	if get_node_or_null("/root/AudioBus") and AudioBus.has_method("play_character_line"):
		AudioBus.play_character_line("granny_cackle_%d" % (randi() % 4))
	var frames: Array[Texture2D] = []
	for p in FRAMES:
		if ResourceLoader.exists(p):
			frames.append(load(p))
	if frames.is_empty():
		return
	var tw := create_tween()
	for f in frames:
		tw.tween_callback(func(): _sprite.set("texture", f))
		tw.tween_interval(FRAME_T)
	# settle back to neutral
	tw.tween_callback(func():
		if _neutral != null:
			_sprite.set("texture", _neutral))
```

- [ ] **Step 2:** In `granny_popup.tscn`, add a `GrannyCackler` (script above) child with `sprite_path` pointing at the Granny `TextureRect` in the `Prompt` panel; likewise add one to the `Results` panel's Granny image in `chicken_chase.tscn`. No code beyond setting the exported `sprite_path` in the scene.

- [ ] **Step 3: Commit:**
```bash
git add godot/scripts/granny_cackler.gd godot/scenes/ui/granny_popup.tscn godot/scenes/chicken_chase.tscn
git commit -m "feat(chicken): Granny's random inappropriate cackle (flipbook + VO)"
```

---

## Task 9: Device pass + tuning

**Files:** tune constants in `chicken_chase_run.gd` (`DURATION`, `FLOCK`, `STUMBLE_LOCKOUT`) and `chicken_chase.gd` (speeds, ranges, `CHICKEN_JUKE_CHANCE`, obstacle count).

- [ ] **Step 1:** Sideload (`scripts/sideload.sh`), jump to the chase via the debug menu.
- [ ] **Step 2:** Verify: cowboy auto-runs the farm lane; swipe steers; tap lunges; hens juke + whiff reads fairly; obstacles stumble (not kill); caught hens fly to the taffy and pop the counter; timer ends the run; results show `+N POSSE BREW`; Granny's reaction scales (full/partial/zero); Continue returns to the map.
- [ ] **Step 3:** Start the next level → confirm the **+N starting posse** is applied once then cleared. Confirm the **24h gate** (pop-up gone + badge countdown after a run; available again after cooldown — test by editing the saved `chicken_chase_last_unix` or the device clock).
- [ ] **Step 4:** Verify Granny's **random inappropriate cackle** fires on the pop-up + results (flipbook reads cleanly, VO bursts land at slightly-wrong moments, not too frequent). Tune `MIN_GAP`/`MAX_GAP` if needed. Then tune the chase so a focused player can sweep 8 but a casual run still nets a few (spec §2 fairness). Update `[[project_chicken_minigame_boosters]]` with tuned values.
- [ ] **Step 5: Commit** the tuning.

---

## Self-Review (against the spec)

**Spec coverage:** §1 concept → whole plan. §2 loop (auto-runner, popcorn hens, obstacles+stumble, lunge+juke, fly-to-taffy collection, haul score) → Tasks 3 (rules) + 4 (scene). §3 proportional reward → Task 1 (`posse_bonus_for`) + Task 4 (`chicken_chase_award`). §4 24h gate (spend-on-begin) → Task 1 + Task 4 `_ready` spend. §5 pop-up + don't-burn safeguard + badge → Task 5. §6 paper-cutout Candy-Granny + chatty VO + the random inappropriate cackle (animation + VO) → Tasks 7, 8, 8b. §7 reuse (breathing-prop cutouts, obstacle system, taffy cutout, modal) → Task 4. §8 persistence (`chicken_chase_last_unix`, `pending_posse_bonus`, consume at level start) → Tasks 1, 2. §9 YAGNI → honored (no scores/leaderboards/multi-brew/permanent building). §10 build TODOs → Tasks 7–9. ✓

**Placeholder scan:** removed the deliberately-awkward assert in Task 1's test (corrected `test_seconds_until_chase_decreases_with_time` shown). The `posse_join` SFX reuse + texture placeholder are explicitly flagged as swap-in points, not vague TODOs. No "TBD"/"handle edge cases".

**Type consistency:** `ChickenChaseRun.{DURATION,FLOCK,STUMBLE_LOCKOUT}`, `.caught`, `.time_left`, `is_over()`, `can_lunge()`, `try_catch()/register_catch()`, `stumble()`, `tick()` — identical across Task 3 tests and the Task 4 scene. `GameState.posse_bonus_for(caught)`, `chicken_chase_available()`, `seconds_until_chase()`, `chicken_chase_spend()`, `chicken_chase_award(caught)`, `claim_posse_bonus()`, fields `chicken_chase_last_unix`/`pending_posse_bonus` — identical across Task 1 tests, Task 2 (level start), Task 4 (scene), Task 5 (pop-up). VO slugs (`granny_chase_*`, `granny_win_{full,partial,zero}_0`, `granny_intro/chatter/cooldown`) — consistent across Task 4/5 callers and Task 7 banks. ✓
