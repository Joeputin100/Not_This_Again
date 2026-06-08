# Raisin Kidd — Level 5 Boss Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship Level 5 — a sun-baked badlands run with two Shaolin candy-monk outlaw types, ending in the "Raisin Kidd" deflect-and-counter timing boss (manga-FX flurry, blink warp, two phases, and a lose-screen finishing cinematic).

**Architecture:** The boss's combat *timing* lives in a new pure `RaisinKiddState` RefCounted (the `terrain_themes.gd` pattern) so it is unit-testable in GUT headless; `level_3d.gd` drives only rendering, contact, and audio from it. Enemies/boss render as chroma-key video billboards (the existing `_make_video_billboard` path). Manga speed-lines, onomatopoeia, the special-move title card, and the gumdrop countdown are an additive 2D-canvas overlay (`manga_fx.gd`, modeled on `frost_bolts.gd`) mounted under the `UI` node — mobile-safe, no custom 3D shaders.

**Tech Stack:** Godot 4.6.1, GDScript, GUT unit tests (`godot/test/`, run via `addons/gut/gut_cmdln.gd` + `.gutconfig.json`). LevelDef resources (`godot/resources/levels/`). Rye font at `res://assets/fonts/Rye-Regular.ttf`.

**Source spec:** `docs/superpowers/specs/2026-06-06-raisin-kidd-boss-design.md`. **Boss memory:** `[[project_raisin_kidd]]`.

**Asset prerequisite track (runs in parallel, see Tasks 9–10):** the boss idle/move + monk clips still need green-screen versions, and the EL voice `1a0nAYA3FcNQcMMfbddY` must be added to the account before VO generation. Code tasks 1–8 do NOT block on these — they wire against the studio-bg clips first and swap to keyed clips when ready.

**How to run the unit tests (used in every TDD task below):**
```bash
# From repo root. Imports the project once, then runs only the new test file.
/tmp/godot/Godot_v4.6.1-stable_linux.x86_64 --headless --import --path godot 2>&1 | tail -3
/tmp/godot/Godot_v4.6.1-stable_linux.x86_64 --headless --path godot \
  -s res://addons/gut/gut_cmdln.gd -gtest=res://test/<FILE>.gd -glog=2
```
If `/tmp/godot/...` is absent, the GUT workflow (`.github/workflows/test.yml`) shows the download step; or use whatever Godot 4.6.1 binary is on PATH. CI runs the full suite on every push.

---

## File Structure

**New files:**
- `godot/scripts/raisin_kidd_state.gd` — pure combat state machine (RefCounted). Holds HP, guard-break meter, mode, all timers; `tick()` emits discrete combat events. No scene refs.
- `godot/test/test_raisin_kidd_state.gd` — GUT tests for the state machine.
- `godot/scripts/manga_fx.gd` — additive 2D-canvas overlay (Node2D): focus lines, burst lines, onomatopoeia SFX text, special-move title card, gumdrop countdown, KA-BLOOM. Rye font.
- `godot/test/test_manga_fx.gd` — GUT tests for the overlay's public API (queue/clear, no-crash draw).
- `godot/resources/levels/level_5.tres` — LevelDef for Level 5.
- `godot/test/test_level_5_def.gd` — GUT test asserting the LevelDef loads with the expected fields.

**Modified files:**
- `godot/scripts/terrain_themes.gd` — add the `badlands` theme.
- `godot/test/test_terrain_themes.gd` — add `badlands` assertions.
- `godot/scripts/level_3d.gd` — monk outlaw kinds + badlands weighting + `_pick_outlaw_kind` branch; `_boss_kind` level-5 → `raisin`; `_spawn_raisin_kidd` + `_process_raisin_kidd`; build the MangaFx overlay; the Five-Point lose cinematic hook.

---

## Task 1: `badlands` terrain theme

**Files:**
- Modify: `godot/scripts/terrain_themes.gd:8-77` (the `TERRAIN_THEMES` dict)
- Test: `godot/test/test_terrain_themes.gd`

- [ ] **Step 1: Write the failing test**

Append to `godot/test/test_terrain_themes.gd`:
```gdscript
func test_badlands_theme_has_required_keys_and_scatter():
	var t: Dictionary = TerrainThemes.get_theme("badlands")
	# Must NOT fall back to frontier (i.e. it is actually defined).
	assert_ne(t, TerrainThemes.get_theme("frontier"), "badlands should be its own theme")
	for k in ["ground_albedo", "ground_normal", "ground_detail", "tint_low",
			"tint_high", "fog_color", "fog_density", "scatter"]:
		assert_true(t.has(k), "badlands theme missing key %s" % k)
	assert_gt((t["scatter"] as Array).size(), 0, "badlands needs scatter props")

func test_badlands_is_warm_toned():
	var t: Dictionary = TerrainThemes.get_theme("badlands")
	var hi: Color = t["tint_high"]
	assert_gt(hi.r, hi.b, "badlands ridge tint should be warm (red > blue)")
```

- [ ] **Step 2: Run test to verify it fails**

Run the test command above with `-gtest=res://test/test_terrain_themes.gd`.
Expected: FAIL — `test_badlands_theme_has_required_keys_and_scatter` fails the `assert_ne` (badlands currently falls back to frontier).

- [ ] **Step 3: Add the `badlands` theme**

In `godot/scripts/terrain_themes.gd`, inside `TERRAIN_THEMES`, add this entry after the `"mountain": { ... },` block (before the closing `}` of the dict). Texture paths follow the existing per-terrain naming (`ground_<name>.png` / `_n.png` / `trail_<name>.png`); those texture files are produced separately in the asset track — the theme references them by the standard path so the artist drops them in:
```gdscript
	"badlands": {
		"ground_albedo": "res://assets/textures/ground_badlands.png",
		"ground_normal": "res://assets/textures/ground_badlands_n.png",
		"ground_detail": "res://assets/textures/ground_detail.png",
		"ground_uv_tile": 24.0, "macro_strength": 2.6,
		"backdrop": "res://assets/sprites/props/backdrop_badlands.png",
		"tint_low": Color(0.46, 0.26, 0.18), "tint_high": Color(0.86, 0.52, 0.32),
		"fog_color": Color(0.96, 0.74, 0.52), "fog_density": 0.020,
		"trail": {"albedo": "res://assets/textures/trail_badlands.png", "half_width": 2.6},
		"boardwalk": null, "cliff": null,
		"scatter": [
			{"slug": "rock_large", "density": 0.5, "scale": [0.7, 1.4]},
			{"slug": "rock_small", "density": 0.6, "scale": [0.5, 1.0]},
			{"slug": "cactus_prickly", "density": 0.3, "scale": [0.8, 1.4]},
			{"slug": "scrub", "density": 0.4, "scale": [0.5, 0.9]},
		],
	},
```
Note: `get_theme` already returns `TERRAIN_THEMES.get(name, frontier)`, so no function change is needed — once the key exists it is served. Missing texture PNGs fall back gracefully at load time (Godot logs a load warning, renders the placeholder); the asset track fills them. The `scatter` slugs above all reuse existing prop sprites, so scatter works immediately.

- [ ] **Step 4: Run test to verify it passes**

Run the same command. Expected: PASS for both new tests; all pre-existing terrain tests still PASS.

- [ ] **Step 5: Commit**
```bash
git add godot/scripts/terrain_themes.gd godot/test/test_terrain_themes.gd
git commit -m "feat(terrain): add badlands theme for Level 5"
```

---

## Task 2: Level 5 LevelDef + boss dispatch

**Files:**
- Create: `godot/resources/levels/level_5.tres`
- Create: `godot/test/test_level_5_def.gd`
- Modify: `godot/scripts/level_3d.gd:3888-3892` (`_boss_kind`)

- [ ] **Step 1: Write the failing test**

Create `godot/test/test_level_5_def.gd`:
```gdscript
extends GutTest

func test_level_5_def_loads_with_badlands_and_quota():
	var def = load("res://resources/levels/level_5.tres")
	assert_not_null(def, "level_5.tres should load")
	assert_eq(def.terrain, "badlands", "Level 5 terrain is badlands")
	assert_eq(def.difficulty, 5, "Level 5 difficulty is 5")
	assert_gt(def.outlaw_quota, 0, "Level 5 needs an outlaw quota")
	assert_eq(def.star_thresholds.size(), 3, "three star thresholds")
	# One step harder than Level 4 (quota 120).
	assert_gt(def.outlaw_quota, 120, "Level 5 quota should exceed Level 4's 120")
```

- [ ] **Step 2: Run test to verify it fails**

Run with `-gtest=res://test/test_level_5_def.gd`.
Expected: FAIL — `load(...)` returns null (`level_5.tres` does not exist yet); `assert_not_null` fails.

- [ ] **Step 3: Create `level_5.tres`**

Create `godot/resources/levels/level_5.tres` (mirrors `level_4.tres`; boss event `kind = 5` with `params = {"boss": "raisin"}`; the `distance` matches Level 4's boss-trigger distance):
```
[gd_resource type="Resource" script_class="LevelDef" format=3]

[ext_resource type="Script" path="res://scripts/level_def.gd" id="1_def"]
[ext_resource type="Script" path="res://scripts/level_event.gd" id="1_hrksf"]

[sub_resource type="Resource" id="Resource_r5boss"]
script = ExtResource("1_hrksf")
distance = 75.0
kind = 5
params = {
"boss": "raisin"
}

[resource]
script = ExtResource("1_def")
difficulty = 5
terrain = "badlands"
display_name = "BADLANDS VINEYARD VENGEANCE"
weather_type = "HEAT"
seed = 5
star_thresholds = Array[int]([0, 4000, 9000])
outlaw_quota = 140
events = Array[ExtResource("1_hrksf")]([SubResource("Resource_r5boss")])
```
Note on `weather_type = "HEAT"`: if the weather system rejects an unknown type it falls back to clear (verify in Task 10 on device). If `"HEAT"` errors at load, change it to `"NONE"` for now and track heat-shimmer as a follow-up — do not block the level on it.

- [ ] **Step 4: Wire boss dispatch**

In `godot/scripts/level_3d.gd`, change `_boss_kind` (currently lines 3888-3892) to recognize Level 5:
```gdscript
func _boss_kind() -> String:
	var lvl: int = 1
	if get_node_or_null("/root/GameState") != null:
		lvl = GameState.current_level
	if lvl == 2:
		return "rustler"
	if lvl == 5:
		return "raisin"
	return "pete"
```
Leave the two existing spawn call-sites (lines ~3616 and ~5348) as-is for now; Task 6 extends them to handle `"raisin"`.

- [ ] **Step 5: Run test to verify it passes**

Run with `-gtest=res://test/test_level_5_def.gd`. Expected: PASS.

- [ ] **Step 6: Commit**
```bash
git add godot/resources/levels/level_5.tres godot/test/test_level_5_def.gd godot/scripts/level_3d.gd
git commit -m "feat(level5): add badlands LevelDef + raisin boss dispatch"
```

---

## Task 3: Shaolin candy-monk outlaws (two tints)

**Files:**
- Modify: `godot/scripts/level_3d.gd` — `FARM_OUTLAW_VIDEOS` (~373), `OUTLAW_KINDS` (~380), add `BADLANDS_OUTLAW_*` constants nearby, and `_pick_outlaw_kind` (~5375).
- Test: `godot/test/test_raisin_kidd_state.gd` is for the boss; add a small outlaw-weighting test here.

The two monks reuse the existing video-billboard outlaw path. Both are ranged (no guns) and drain via `_outlaw_drain_posse`. Assets already on disk: `godot/assets/videos/candy_monk/hadouken.ogv` (orange / Fireball) and `candy_star_blue.ogv` (blue / Star).

- [ ] **Step 1: Write the failing test**

Create `godot/test/test_badlands_outlaws.gd`:
```gdscript
extends GutTest

# Drives only the pure weighting helper by faking a badlands LevelDef.
const Level3D = preload("res://scripts/level_3d.gd")

func test_badlands_weights_only_emit_monks():
	# The badlands roster must contain exactly the two monk kinds.
	var kinds := {}
	for entry in Level3D.BADLANDS_OUTLAW_WEIGHTS:
		kinds[entry[0]] = true
	assert_true(kinds.has("fireball_monk"), "badlands roster has fireball_monk")
	assert_true(kinds.has("star_monk"), "badlands roster has star_monk")
	assert_eq(kinds.size(), 2, "badlands roster is exactly the two monks")

func test_monk_kinds_have_stats_and_videos():
	for k in ["fireball_monk", "star_monk"]:
		assert_true(Level3D.OUTLAW_KINDS.has(k), "OUTLAW_KINDS missing %s" % k)
		assert_true(Level3D.MONK_OUTLAW_VIDEOS.has(k), "MONK_OUTLAW_VIDEOS missing %s" % k)
		assert_gt(int(Level3D.OUTLAW_KINDS[k]["hp"]), 0, "%s needs hp" % k)
```

- [ ] **Step 2: Run test to verify it fails**

Run with `-gtest=res://test/test_badlands_outlaws.gd`.
Expected: FAIL — `BADLANDS_OUTLAW_WEIGHTS` / `MONK_OUTLAW_VIDEOS` are undefined (parse error or missing-constant failure).

- [ ] **Step 3: Add the monk constants**

In `godot/scripts/level_3d.gd`, immediately after the `FARM_OUTLAW_WEIGHTS` block (~line 389) add:
```gdscript
# Level-5 Shaolin candy-monks (no guns). Same video-billboard path as the
# farm kinds. fireball_monk = orange, slow/heavy telegraphed lob; star_monk =
# blue, fast/light multi-shot harasser. Tuned on device (Task 10).
const MONK_OUTLAW_VIDEOS: Dictionary = {
	"fireball_monk": "res://assets/videos/candy_monk/hadouken.ogv",
	"star_monk":     "res://assets/videos/candy_monk/candy_star_blue.ogv",
}
const BADLANDS_OUTLAW_WEIGHTS: Array = [
	["fireball_monk", 45], ["star_monk", 55],
]
const FIREBALL_MONK_HOLD_Z: float = 7.0     # heavy lobber holds at range
const STAR_MONK_HOLD_Z: float = 5.0         # harasser closes a bit more
```
Then extend `OUTLAW_KINDS` (~line 380) to add the two monk stat rows:
```gdscript
const OUTLAW_KINDS: Dictionary = {
	"candy_corn":    {"hp": 10, "height": 2.5},
	"gummi_bear":    {"hp": 8,  "height": 2.3},
	"fried_dough":   {"hp": 16, "height": 2.8},
	"triffid":       {"hp": 14, "height": 3.0},
	"fireball_monk": {"hp": 18, "height": 2.7},
	"star_monk":     {"hp": 9,  "height": 2.5},
}
```

- [ ] **Step 4: Teach `_pick_outlaw_kind` + `_spawn_outlaw` about badlands**

In `_pick_outlaw_kind` (~5375), generalize the roster selection so badlands draws from the monk weights:
```gdscript
func _pick_outlaw_kind() -> String:
	if _level_def == null:
		return "vagrant"
	var roster: Array
	match _level_def.terrain:
		"farm": roster = FARM_OUTLAW_WEIGHTS
		"badlands": roster = BADLANDS_OUTLAW_WEIGHTS
		_: return "vagrant"
	var total: int = 0
	for entry in roster:
		total += entry[1]
	var roll: int = _rng.randi_range(0, total - 1)
	for entry in roster:
		roll -= entry[1]
		if roll < 0:
			return entry[0]
	return roster[0][0]
```
In `_spawn_outlaw` (~5388), the billboard branch keys off `OUTLAW_KINDS.has(kind)` (farm kinds) and loads from `FARM_OUTLAW_VIDEOS`. Extend it to also load monk videos. Replace the `is_farm_kind` billboard block (~5422-5427):
```gdscript
	var billboard: Node3D
	if FARM_OUTLAW_VIDEOS.has(kind):
		billboard = _make_video_billboard(load(FARM_OUTLAW_VIDEOS[kind]), OUTLAW_KINDS[kind]["height"])
	elif MONK_OUTLAW_VIDEOS.has(kind):
		billboard = _make_video_billboard(load(MONK_OUTLAW_VIDEOS[kind]), OUTLAW_KINDS[kind]["height"])
	else:
		billboard = _make_video_billboard(VAGRANT_IDLE_STREAM, 2.5)
```
Note: `is_farm_kind` is also used a few lines up to pick `max_hp` (`OUTLAW_KINDS.has(kind)`) — the monks are in `OUTLAW_KINDS`, so `var is_farm_kind: bool = OUTLAW_KINDS.has(kind)` already gives them their HP. Leave that line; only the billboard branch changes.

- [ ] **Step 5: Run test to verify it passes**

Run with `-gtest=res://test/test_badlands_outlaws.gd`. Expected: PASS. Also re-run `test_terrain_themes.gd` and the full suite locally if quick — no regressions.

- [ ] **Step 6: Commit**
```bash
git add godot/scripts/level_3d.gd godot/test/test_badlands_outlaws.gd
git commit -m "feat(level5): two candy-monk outlaw kinds + badlands weighting"
```

---

## Task 4: `RaisinKiddState` combat state machine (pure, unit-tested)

This is the heart of the boss. A pure RefCounted that owns HP, the guard-break meter, the mode, and every timer. `level_3d` calls `register_fire(n)` each frame with the count of bullets that hit the boss this frame, then `tick(delta)` to advance; `tick` returns the list of discrete events that occurred so the scene can react (move the boss, play VO, fire FX, drain posse, run the win flow).

**Files:**
- Create: `godot/scripts/raisin_kidd_state.gd`
- Test: `godot/test/test_raisin_kidd_state.gd`

- [ ] **Step 1: Write the failing test**

Create `godot/test/test_raisin_kidd_state.gd`:
```gdscript
extends GutTest

const RaisinKiddState = preload("res://scripts/raisin_kidd_state.gd")

func _fresh() -> RaisinKiddState:
	return RaisinKiddState.new()

func test_starts_guarding_and_invulnerable():
	var s = _fresh()
	assert_eq(s.mode, RaisinKiddState.Mode.GUARD)
	assert_false(s.is_vulnerable(), "guarding boss is invulnerable")
	assert_eq(s.hp, RaisinKiddState.MAX_HP)

func test_fire_while_guarding_fills_meter_but_deals_no_damage():
	var s = _fresh()
	s.register_fire(10)
	s.tick(0.016)
	assert_eq(s.hp, RaisinKiddState.MAX_HP, "no damage while guarding")
	assert_gt(s.meter, 0.0, "fire fills the guard-break meter")

func test_meter_decays_when_not_hit():
	var s = _fresh()
	s.register_fire(10)
	s.tick(0.016)
	var peak: float = s.meter
	# No fire for a while.
	for i in range(120):
		s.tick(0.05)
	assert_lt(s.meter, peak, "meter decays without sustained fire")

func test_sustained_fire_shatters_guard_and_opens_window():
	var s = _fresh()
	var saw_shatter := false
	# Pour fire in until the meter trips.
	for i in range(400):
		s.register_fire(20)
		var events: Array = s.tick(0.05)
		if events.has("guard_shatter"):
			saw_shatter = true
			break
	assert_true(saw_shatter, "sustained fire should shatter the guard")
	assert_eq(s.mode, RaisinKiddState.Mode.BROKEN)
	assert_true(s.is_vulnerable(), "broken guard is a damage window")

func test_broken_window_closes_and_reforms():
	var s = _fresh()
	for i in range(400):
		s.register_fire(20)
		if s.tick(0.05).has("guard_shatter"):
			break
	# Let the open window elapse.
	var saw_reform := false
	for i in range(int(RaisinKiddState.GUARD_BREAK_OPEN_T / 0.05) + 5):
		if s.tick(0.05).has("guard_reform"):
			saw_reform = true
			break
	assert_true(saw_reform, "guard reforms after the open window")
	assert_eq(s.mode, RaisinKiddState.Mode.GUARD)
	assert_almost_eq(s.meter, 0.0, 0.001, "meter resets on reform")

func test_damage_only_lands_during_a_window():
	var s = _fresh()
	# Force a broken window.
	for i in range(400):
		s.register_fire(20)
		if s.tick(0.05).has("guard_shatter"):
			break
	var before: int = s.hp
	s.register_fire(5)
	s.tick(0.016)
	assert_lt(s.hp, before, "fire during a window deals damage")

func test_grapes_of_wrath_cycles_windup_flurry_recovery():
	var s = _fresh()
	var seen := {}
	for i in range(int((RaisinKiddState.GOW_INTERVAL_P1 + RaisinKiddState.GOW_WINDUP + RaisinKiddState.GOW_RECOVERY_T + 1.0) / 0.05)):
		for e in s.tick(0.05):
			seen[e] = true
	assert_true(seen.has("gow_windup"), "telegraph fires")
	assert_true(seen.has("gow_flurry"), "flurry fires")
	assert_true(seen.has("gow_recovery_open"), "recovery window opens after flurry")

func test_recovery_is_a_vulnerable_window():
	var s = _fresh()
	var hit_recovery := false
	for i in range(2000):
		var events: Array = s.tick(0.05)
		if events.has("gow_recovery_open"):
			hit_recovery = true
			assert_true(s.is_vulnerable(), "recovery is a damage window")
			break
	assert_true(hit_recovery)

func test_warp_fires_on_cadence():
	var s = _fresh()
	var warps := 0
	for i in range(int((RaisinKiddState.WARP_INTERVAL_P1 * 2.5) / 0.05)):
		if s.tick(0.05).has("warp"):
			warps += 1
	assert_gte(warps, 2, "warp should fire ~every WARP_INTERVAL seconds")

func test_phase2_triggers_at_half_hp_and_speeds_up():
	var s = _fresh()
	# Drop HP straight to just above half, then below.
	s.hp = int(RaisinKiddState.MAX_HP * RaisinKiddState.PHASE2_HP_FRAC) + 1
	assert_eq(s.phase, 1)
	s.hp = int(RaisinKiddState.MAX_HP * RaisinKiddState.PHASE2_HP_FRAC) - 1
	var saw_phase2 := false
	for i in range(10):
		if s.tick(0.016).has("phase2"):
			saw_phase2 = true
			break
	assert_true(saw_phase2, "phase 2 triggers below half HP")
	assert_eq(s.phase, 2)
	assert_lt(s.gow_interval(), RaisinKiddState.GOW_INTERVAL_P1, "GoW faster in phase 2")
	assert_lt(s.warp_interval(), RaisinKiddState.WARP_INTERVAL_P1, "warp faster in phase 2")

func test_defeat_emitted_once_at_zero_hp():
	var s = _fresh()
	for i in range(400):
		s.register_fire(20)
		if s.tick(0.05).has("guard_shatter"):
			break
	# Hammer the open window to zero.
	var defeats := 0
	for i in range(2000):
		s.register_fire(50)
		for e in s.tick(0.05):
			if e == "defeat":
				defeats += 1
		if s.hp <= 0 and defeats >= 1:
			# keep ticking a bit to ensure it doesn't re-emit
			for j in range(20):
				for e2 in s.tick(0.05):
					if e2 == "defeat":
						defeats += 1
			break
	assert_eq(defeats, 1, "defeat emits exactly once")
	assert_eq(s.mode, RaisinKiddState.Mode.DEAD)
```

- [ ] **Step 2: Run test to verify it fails**

Run with `-gtest=res://test/test_raisin_kidd_state.gd`.
Expected: FAIL — `preload` of a non-existent script errors / all tests fail.

- [ ] **Step 3: Implement `raisin_kidd_state.gd`**

Create `godot/scripts/raisin_kidd_state.gd`:
```gdscript
class_name RaisinKiddState
extends RefCounted

# Pure combat state machine for the Level-5 boss "Raisin Kidd" — the
# "Untouchable" deflect-and-counter timing fight (spec §3). Holds NO scene
# or render state; level_3d.gd drives rendering, contact, audio, and the
# WIN flow from the public fields + the event list tick() returns. This is
# the TerrainThemes pattern: pure logic here, unit-tested in GUT headless.
#
# Per-frame contract from level_3d:
#   state.register_fire(n)            # n = posse bullets overlapping the boss this frame
#   var events: Array = state.tick(delta)
#   # react to events (move boss, play VO/FX, drain posse, run win flow)
#
# All durations in seconds; meter is an abstract 0..THRESHOLD scale.

enum Mode { GUARD, WINDUP, FLURRY, RECOVERY, BROKEN, DEAD }

# --- tunables (device-tuned in Task 10) ---
const MAX_HP: int = 600
const GUARD_BREAK_FILL_PER_HIT: float = 1.4   # meter units per overlapping bullet
const GUARD_BREAK_THRESHOLD: float = 100.0
const GUARD_BREAK_DECAY: float = 22.0          # meter units/sec lost when not hit this frame
const GUARD_BREAK_OPEN_T: float = 3.0          # vulnerable seconds after a shatter
const DAMAGE_PER_HIT: int = 1                  # HP lost per overlapping bullet during a window
const GOW_INTERVAL_P1: float = 6.0
const GOW_INTERVAL_P2: float = 4.0
const GOW_WINDUP: float = 1.0                  # telegraph before the flurry
const GOW_FLURRY_T: float = 0.6                # the flurry itself
const GOW_RECOVERY_T: float = 1.5              # guaranteed smaller window after the flurry
const WARP_INTERVAL_P1: float = 10.0
const WARP_INTERVAL_P2: float = 7.0
const PHASE2_HP_FRAC: float = 0.5

var hp: int = MAX_HP
var meter: float = 0.0
var mode: int = Mode.GUARD
var phase: int = 1

var _fire_this_frame: int = 0
var _open_t: float = 0.0          # remaining time in a BROKEN/RECOVERY window
var _gow_t: float = GOW_INTERVAL_P1   # countdown to next Grapes of Wrath
var _gow_phase_t: float = 0.0     # countdown within WINDUP/FLURRY/RECOVERY
var _warp_t: float = WARP_INTERVAL_P1
var _defeated_emitted: bool = false

func gow_interval() -> float:
	return GOW_INTERVAL_P2 if phase == 2 else GOW_INTERVAL_P1

func warp_interval() -> float:
	return WARP_INTERVAL_P2 if phase == 2 else WARP_INTERVAL_P1

func is_vulnerable() -> bool:
	return mode == Mode.BROKEN or mode == Mode.RECOVERY

# level_3d calls this each frame with the number of posse bullets overlapping
# the boss; tick() consumes it.
func register_fire(n: int) -> void:
	_fire_this_frame += n

func tick(delta: float) -> Array:
	var events: Array = []
	if mode == Mode.DEAD:
		_fire_this_frame = 0
		return events

	var fired: int = _fire_this_frame
	_fire_this_frame = 0

	# --- apply fire: damage if a window is open, else fill/decay the meter ---
	if is_vulnerable():
		if fired > 0:
			hp = maxi(0, hp - fired * DAMAGE_PER_HIT)
	elif mode == Mode.GUARD or mode == Mode.WINDUP or mode == Mode.FLURRY:
		if fired > 0:
			meter += fired * GUARD_BREAK_FILL_PER_HIT
		else:
			meter = maxf(0.0, meter - GUARD_BREAK_DECAY * delta)

	# --- phase transition (checked every frame; one-shot) ---
	if phase == 1 and hp <= int(MAX_HP * PHASE2_HP_FRAC) and hp > 0:
		phase = 2
		events.append("phase2")
		# tighten the live clocks so the speed-up is felt immediately
		_gow_t = minf(_gow_t, gow_interval())
		_warp_t = minf(_warp_t, warp_interval())

	# --- death ---
	if hp <= 0:
		if not _defeated_emitted:
			_defeated_emitted = true
			mode = Mode.DEAD
			events.append("defeat")
		return events

	# --- guard-break shatter (only while guarding-ish, not mid-flurry windows) ---
	if (mode == Mode.GUARD or mode == Mode.WINDUP or mode == Mode.FLURRY) \
			and meter >= GUARD_BREAK_THRESHOLD:
		mode = Mode.BROKEN
		_open_t = GUARD_BREAK_OPEN_T
		meter = 0.0
		events.append("guard_shatter")
		return events

	# --- window countdowns ---
	if mode == Mode.BROKEN:
		_open_t -= delta
		if _open_t <= 0.0:
			mode = Mode.GUARD
			meter = 0.0
			events.append("guard_reform")
		# warp + GoW clocks pause during a broken window (he's stunned)
		return events

	if mode == Mode.RECOVERY:
		_open_t -= delta
		if _open_t <= 0.0:
			mode = Mode.GUARD
			events.append("gow_recovery_end")
		return events

	# --- Grapes of Wrath cycle (only progresses while GUARD-ing) ---
	if mode == Mode.GUARD:
		_warp_t -= delta
		if _warp_t <= 0.0:
			_warp_t = warp_interval()
			events.append("warp")
		_gow_t -= delta
		if _gow_t <= 0.0:
			mode = Mode.WINDUP
			_gow_phase_t = GOW_WINDUP
			events.append("gow_windup")
		return events

	if mode == Mode.WINDUP:
		_gow_phase_t -= delta
		if _gow_phase_t <= 0.0:
			mode = Mode.FLURRY
			_gow_phase_t = GOW_FLURRY_T
			events.append("gow_flurry")
		return events

	if mode == Mode.FLURRY:
		_gow_phase_t -= delta
		if _gow_phase_t <= 0.0:
			mode = Mode.RECOVERY
			_open_t = GOW_RECOVERY_T
			_gow_t = gow_interval()    # reset cadence for the next flurry
			events.append("gow_recovery_open")
		return events

	return events
```

- [ ] **Step 4: Run test to verify it passes**

Run with `-gtest=res://test/test_raisin_kidd_state.gd`. Expected: PASS for all cases. If `test_sustained_fire_shatters_guard` is flaky, the loop pours 20 bullets × `GUARD_BREAK_FILL_PER_HIT` per 0.05 s — comfortably trips `THRESHOLD` before decay; do not weaken assertions, fix the tunables if a test reveals a logic gap.

- [ ] **Step 5: Commit**
```bash
git add godot/scripts/raisin_kidd_state.gd godot/test/test_raisin_kidd_state.gd
git commit -m "feat(level5): RaisinKiddState combat state machine + tests"
```

---

## Task 5: `manga_fx.gd` additive overlay

A `frost_bolts.gd`-style additive 2D-canvas overlay. Public API the boss code calls; all drawing self-contained. Rye font for lettering (spec §7). No custom shaders.

**Files:**
- Create: `godot/scripts/manga_fx.gd`
- Test: `godot/test/test_manga_fx.gd`

- [ ] **Step 1: Write the failing test**

Create `godot/test/test_manga_fx.gd`:
```gdscript
extends GutTest

const MangaFx = preload("res://scripts/manga_fx.gd")

var fx

func before_each():
	fx = MangaFx.new()
	add_child_autofree(fx)
	fx.size = Vector2(1080, 1920)   # pretend full-screen
	await get_tree().process_frame

func test_starts_idle():
	assert_false(fx.is_active(), "no effects queued -> idle")

func test_burst_activates_then_expires():
	fx.burst(Vector2(540, 900), "DOON!")
	assert_true(fx.is_active(), "burst makes it active")
	# Run longer than the effect lifetime.
	for i in range(120):
		fx._process(0.05)
	assert_false(fx.is_active(), "burst expires")

func test_focus_lines_and_title_card_dont_crash_draw():
	fx.focus_lines(Vector2(540, 900))
	fx.title_card("FIVE-POINT RAISIN\nEXPLODING GUMDROP!")
	fx._process(0.016)
	fx.queue_redraw()     # _draw runs next frame; just assert no error reaching here
	assert_true(fx.is_active())

func test_gumdrop_countdown_runs_five_to_one():
	fx.gumdrop_countdown(Vector2(540, 1100))
	assert_true(fx.is_active())
	var huge := 0.0
	while fx.is_active() and huge < 60.0:
		fx._process(0.1)
		huge += 0.1
	assert_lt(huge, 60.0, "countdown terminates")

func test_clear_stops_everything():
	fx.focus_lines(Vector2(1, 1))
	fx.burst(Vector2(2, 2), "ZUSH!")
	fx.clear()
	assert_false(fx.is_active(), "clear() empties all effects")
```

- [ ] **Step 2: Run test to verify it fails**

Run with `-gtest=res://test/test_manga_fx.gd`.
Expected: FAIL — `manga_fx.gd` does not exist.

- [ ] **Step 3: Implement `manga_fx.gd`**

Create `godot/scripts/manga_fx.gd`:
```gdscript
extends Control

# Manga / fighting-anime FX overlay for the Raisin Kidd boss (spec §7). An
# additive 2D canvas in the frost_bolts.gd tradition — focus lines (集中線),
# burst lines, written-out onomatopoeia SFX, a special-move title card, and
# the Five-Point gumdrop countdown + KA-BLOOM. Mobile-safe: pure Control
# _draw + a Rye font, no custom shaders. Mounted under UI by level_3d.
#
# Public API (all screen-space positions):
#   focus_lines(center)              # converging speed-lines telegraph
#   burst(center, text)              # radial burst-lines + onomatopoeia pop
#   title_card(text)                 # slam-in special-move name card
#   gumdrop_countdown(center)        # 5->1 gumdrop pips, then KA-BLOOM
#   clear()                          # wipe everything
#   is_active()                      # any live effect?

const RYE := preload("res://assets/fonts/Rye-Regular.ttf")

const FOCUS_LIFE := 1.0
const BURST_LIFE := 0.7
const TITLE_LIFE := 1.6
const PIP_STEP := 0.45          # seconds per gumdrop pip
const BLOOM_LIFE := 0.9

var _focus: Array = []          # {center, life, t0}
var _bursts: Array = []         # {center, text, life, t0}
var _titles: Array = []         # {text, life, t0}
var _counts: Array = []         # {center, n, step_t, life, blooming, bloom_life}
var _rng := RandomNumberGenerator.new()
var _font: Font

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = m
	_font = RYE
	set_process(false)

func is_active() -> bool:
	return not (_focus.is_empty() and _bursts.is_empty() \
		and _titles.is_empty() and _counts.is_empty())

func clear() -> void:
	_focus.clear(); _bursts.clear(); _titles.clear(); _counts.clear()
	set_process(false)
	queue_redraw()

func _wake() -> void:
	set_process(true)
	queue_redraw()

func focus_lines(center: Vector2) -> void:
	_focus.append({"center": center, "life": FOCUS_LIFE, "t0": FOCUS_LIFE})
	_wake()

func burst(center: Vector2, text: String = "") -> void:
	_bursts.append({"center": center, "text": text, "life": BURST_LIFE, "t0": BURST_LIFE})
	_wake()

func title_card(text: String) -> void:
	_titles.append({"text": text, "life": TITLE_LIFE, "t0": TITLE_LIFE})
	_wake()

func gumdrop_countdown(center: Vector2) -> void:
	_counts.append({"center": center, "n": 5, "step_t": PIP_STEP,
		"life": PIP_STEP * 5.0, "blooming": false, "bloom_life": BLOOM_LIFE})
	_wake()

func _process(delta: float) -> void:
	_focus = _age(_focus, delta)
	_bursts = _age(_bursts, delta)
	_titles = _age(_titles, delta)
	for c in _counts:
		if c["blooming"]:
			c["bloom_life"] -= delta
		else:
			c["step_t"] -= delta
			c["life"] -= delta
			if c["step_t"] <= 0.0:
				c["step_t"] = PIP_STEP
				c["n"] = maxi(0, int(c["n"]) - 1)
			if int(c["n"]) <= 0 and c["life"] <= 0.0:
				c["blooming"] = true
	var live_counts: Array = []
	for c in _counts:
		if not c["blooming"] or c["bloom_life"] > 0.0:
			live_counts.append(c)
	_counts = live_counts
	queue_redraw()
	if not is_active():
		set_process(false)

func _age(arr: Array, delta: float) -> Array:
	var out: Array = []
	for e in arr:
		e["life"] -= delta
		if e["life"] > 0.0:
			out.append(e)
	return out

func _draw() -> void:
	for f in _focus:
		_draw_focus(f)
	for b in _bursts:
		_draw_burst(b)
	for c in _counts:
		_draw_count(c)
	for t in _titles:
		_draw_title(t)

func _draw_focus(f: Dictionary) -> void:
	var c: Vector2 = f["center"]
	var frac: float = clampf(f["life"] / f["t0"], 0.0, 1.0)
	var a: float = frac * 0.85
	var R: float = maxf(size.x, size.y)
	var n := 64
	for i in range(n):
		var ang: float = TAU * float(i) / float(n) + sin(float(i) * 12.9) * 0.02
		var inner: float = lerpf(R * 0.55, R * 0.20, 1.0 - frac)  # lines retract as they "hit"
		var p_in: Vector2 = c + Vector2(cos(ang), sin(ang)) * inner
		var p_out: Vector2 = c + Vector2(cos(ang), sin(ang)) * R
		var w: float = 2.0 + 6.0 * abs(sin(float(i) * 7.3))
		draw_line(p_out, p_in, Color(1, 1, 1, a * 0.6), w)

func _draw_burst(b: Dictionary) -> void:
	var c: Vector2 = b["center"]
	var frac: float = clampf(b["life"] / b["t0"], 0.0, 1.0)
	var grow: float = 1.0 - frac
	var R: float = lerpf(40.0, 520.0, grow)
	var n := 40
	for i in range(n):
		var ang: float = TAU * float(i) / float(n)
		var jag: float = 0.78 + 0.22 * abs(sin(float(i) * 5.1))
		var p_in: Vector2 = c + Vector2(cos(ang), sin(ang)) * (R * 0.45)
		var p_out: Vector2 = c + Vector2(cos(ang), sin(ang)) * (R * jag)
		draw_line(p_in, p_out, Color(1, 0.95, 0.5, frac * 0.9), 3.0 + 5.0 * jag)
	if String(b["text"]) != "":
		_draw_sfx_text(String(b["text"]), c + Vector2(0, -20), lerpf(54, 96, grow), frac)

func _draw_count(c: Dictionary) -> void:
	var center: Vector2 = c["center"]
	if c["blooming"]:
		var bf: float = clampf(c["bloom_life"] / BLOOM_LIFE, 0.0, 1.0)
		# KA-BLOOM! white flash + gumdrop shower text
		var R: float = lerpf(60.0, 600.0, 1.0 - bf)
		draw_circle(center, R * 0.5, Color(1, 1, 1, bf * 0.5))
		_draw_sfx_text("KA-BLOOM!", center, lerpf(72, 130, 1.0 - bf), bf)
		return
	# Five gumdrop pips in a row that wink out 5->1.
	var lit: int = int(c["n"])
	for i in range(5):
		var px: Vector2 = center + Vector2((i - 2) * 70.0, 0.0)
		var on: bool = i < lit
		var col := Color(0.9, 0.4, 0.9, 0.95) if on else Color(0.4, 0.2, 0.4, 0.4)
		_draw_gumdrop(px, 26.0, col)

func _draw_gumdrop(p: Vector2, r: float, col: Color) -> void:
	# rounded teardrop: a circle with a soft peak
	draw_circle(p + Vector2(0, r * 0.25), r, col)
	var pts := PackedVector2Array([
		p + Vector2(-r * 0.7, r * 0.1), p + Vector2(0, -r), p + Vector2(r * 0.7, r * 0.1)])
	draw_colored_polygon(pts, col)

func _draw_title(t: Dictionary) -> void:
	var frac: float = clampf(t["life"] / t["t0"], 0.0, 1.0)
	# slam-in: large at start, settles; fade out at the tail
	var age: float = 1.0 - frac
	var scale_in: float = clampf(age / 0.18, 0.0, 1.0)         # first 18% slams in
	var fade: float = clampf(frac / 0.25, 0.0, 1.0)            # last 25% fades
	var fs: float = lerpf(160.0, 96.0, scale_in)
    # speed-line backing behind the card
	_draw_focus({"center": size * 0.5, "life": 1.0, "t0": 1.0})
	var lines: PackedStringArray = String(t["text"]).split("\n")
	var y: float = size.y * 0.42
	for ln in lines:
		_draw_sfx_text(ln, Vector2(size.x * 0.5, y), fs, fade)
		y += fs * 1.05

func _draw_sfx_text(text: String, center: Vector2, font_size: float, alpha: float) -> void:
	# bold outlined manga lettering: dark outline pass + white edge + warm fill
	var fs := int(font_size)
	var tw: float = _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var pos: Vector2 = center - Vector2(tw * 0.5, 0)
	# outline (draw the string offset in 8 directions, dark)
	for ox in [-4, 0, 4]:
		for oy in [-4, 0, 4]:
			if ox == 0 and oy == 0:
				continue
			draw_string(_font, pos + Vector2(ox, oy), text, HORIZONTAL_ALIGNMENT_LEFT,
				-1, fs, Color(0.05, 0.0, 0.08, alpha))
	# white edge
	draw_string(_font, pos + Vector2(0, -2), text, HORIZONTAL_ALIGNMENT_LEFT,
		-1, fs, Color(1, 1, 1, alpha))
	# warm fill
	draw_string(_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT,
		-1, fs, Color(1.0, 0.78, 0.25, alpha))
```
Fix the one stray-indented comment line (`    # speed-line backing...`) to a tab before saving — GDScript is tab-indented; mixed tabs/spaces will fail to parse. Run `node --check` is N/A (this is GDScript); the import step + the test run is the parse check.

- [ ] **Step 4: Run test to verify it passes**

Run with `-gtest=res://test/test_manga_fx.gd`. Expected: PASS. If a parse error appears, it is almost certainly the tab/space mix on the comment line above — fix and re-run.

- [ ] **Step 5: Commit**
```bash
git add godot/scripts/manga_fx.gd godot/test/test_manga_fx.gd
git commit -m "feat(level5): manga FX additive overlay (focus/burst/title/countdown)"
```

---

## Task 6: Spawn + drive Raisin Kidd in `level_3d.gd`

Wire the boss into the scene: a chroma-key video billboard (guard idle clip), the HUD HP bar, the per-frame `RaisinKiddState` drive, deflect "tink" sparks while guarding, posse drain during the flurry, warp reposition, manga FX on the events, and the WIN flow on defeat. This task is largely untestable scene wiring — it is verified on device in Task 10.

**Files:**
- Modify: `godot/scripts/level_3d.gd` — add constants, `_build_manga_fx`, `_spawn_raisin_kidd`, `_process_raisin_kidd`; extend the boss spawn call-sites (~3616, ~5348) and the boss process dispatch (~6524).

- [ ] **Step 1: Add boss constants + the MangaFx member**

Near the Rustler constants (~line 447) add:
```gdscript
# Iter (level5): Raisin Kidd — the "Untouchable" deflect/counter boss. Combat
# timing lives in RaisinKiddState (unit-tested); this scene drives rendering,
# contact, FX, and the WIN/lose flow from its events.
const _RAISIN_KIDD_STATE := preload("res://scripts/raisin_kidd_state.gd")
const RAISIN_GUARD_STREAM := "res://assets/videos/raisin_kidd/guard_idle.ogv"
const RAISIN_GOW_STREAM := "res://assets/videos/raisin_kidd/grapes_of_wrath_green.ogv"
const RAISIN_STAY_Z: float = -7.0       # arena center, like the Rustler
const RAISIN_HEIGHT: float = 5.0
const RAISIN_WARP_X_MAX: float = 4.0    # lateral range he can reappear at
const RAISIN_FLURRY_DPS: float = 4.0    # posse drained/sec during a Grapes of Wrath flurry
var _raisin: RaisinKiddState = null
var _raisin_flurry_accum: float = 0.0
```
And near the frost-bolts member (~256) add:
```gdscript
const MangaFxScript = preload("res://scripts/manga_fx.gd")
var _manga_fx: Control = null
```

- [ ] **Step 2: Build the MangaFx overlay at startup**

Next to the `_build_frost_bolts()` / `_build_rainbow_bolts()` calls (~644-645) add `_build_manga_fx()`, and define it next to `_build_frost_bolts` (~7540):
```gdscript
func _build_manga_fx() -> void:
	var ui: Node = get_node_or_null("UI")
	if ui == null:
		return
	_manga_fx = MangaFxScript.new()
	_manga_fx.name = "MangaFx"
	ui.add_child(_manga_fx)
	ui.move_child(_manga_fx, 0)
```
Add the call after `_build_rainbow_bolts()`:
```gdscript
	_build_frost_bolts()     # iter404: FROSTBITE chain-lightning overlay
	_build_rainbow_bolts()   # kimmy: RAINBOW prism-chain overlay
	_build_manga_fx()        # level5: Raisin Kidd manga FX overlay
```

- [ ] **Step 3: Implement `_spawn_raisin_kidd`**

Add after `_spawn_candy_rustler` (after ~line 3959), modeled on it but using a video billboard (not the rig):
```gdscript
# Spawn the Level-5 boss, Raisin Kidd. Video-billboard actor (guard idle clip),
# HUD HP bar mirrored from RaisinKiddState. Per-frame logic is _process_raisin_kidd.
func _spawn_raisin_kidd() -> void:
	_raisin = _RAISIN_KIDD_STATE.new()
	var boss := Node3D.new()
	boss.position = Vector3(0.0, 2.25, OBSTACLE_SPAWN_Z + 4.0)
	boss.set_meta("hp", _raisin.hp)
	boss.set_meta("hp_max", RaisinKiddState.MAX_HP)
	boss.set_meta("boss_kind", "raisin")
	boss_root.add_child(boss)
	var bb: Node3D = _make_video_billboard(load(RAISIN_GUARD_STREAM), RAISIN_HEIGHT)
	boss.add_child(bb)
	if bb.get_child_count() > 0:
		boss.set_meta("sprite_3d", bb.get_child(0))
	var name_plate := Label3D.new()
	name_plate.text = "RAISIN KIDD"
	name_plate.font_size = 44
	name_plate.outline_size = 9
	name_plate.modulate = Color(0.85, 0.45, 0.85, 1)
	name_plate.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	name_plate.no_depth_test = true
	name_plate.position = Vector3(0, 0.6, 0.6)
	boss.add_child(name_plate)
	_install_pete_hud(boss, "RAISIN KIDD")
	_refresh_pete_hp(boss)
	info_label.text = "BOSS — RAISIN KIDD"
	DebugLog.add("raisin kidd spawned at z=%.1f, HP=%d" % [boss.position.z, _raisin.hp])
```

- [ ] **Step 4: Implement `_process_raisin_kidd`**

Add after `_spawn_raisin_kidd`. This counts overlapping bullets, drives the state, and reacts to events. World→screen projection for FX uses the active 3D camera (the same `unproject_position` the codebase uses for popups/aim — confirm the camera node name when wiring; if `get_viewport().get_camera_3d()` returns the gameplay camera, use it):
```gdscript
func _process_raisin_kidd(boss: Node3D, delta: float) -> void:
	if _raisin == null or boss.get_meta("dying", false):
		return
	# Approach the arena center first (terrain already stopped on engage).
	if boss.position.z < RAISIN_STAY_Z:
		boss.position.z += RUSTLER_SPEED * delta

	# Count overlapping posse bullets; consume them only when a window is open
	# (a hit during guard just pings off and fills the meter — keep the bullet
	# visually consumed either way so fire feels like it lands on him).
	var hits := 0
	for bullet in bullets_root.get_children():
		if not (bullet is Node3D):
			continue
		var dx: float = bullet.position.x - boss.position.x
		var dz: float = bullet.position.z - boss.position.z
		if dx * dx + dz * dz < PETE_HIT_RADIUS_SQ:
			hits += 1
			bullet.queue_free()
	if hits > 0:
		_raisin.register_fire(hits)
		# deflect "tink" sparks + popup only while guarding
		if not _raisin.is_vulnerable():
			_spawn_popup_3d(boss.position + Vector3(0, 1.6, 0), "TINK",
				Color(0.8, 0.85, 1.0, 1), 48)
		else:
			_spawn_popup_3d(boss.position + Vector3(0, 1.6, 0),
				"-%d" % hits, Color(0.85, 0.45, 0.85, 1), 64)

	var events: Array = _raisin.tick(delta)
	# mirror HP onto the HUD bar
	boss.set_meta("hp", _raisin.hp)
	_refresh_pete_hp(boss)

	var cam := get_viewport().get_camera_3d()
	var boss_screen: Vector2 = cam.unproject_position(boss.position + Vector3(0, 1.5, 0)) if cam else get_viewport_rect().size * 0.5

	for e in events:
		match e:
			"gow_windup":
				if _manga_fx: _manga_fx.focus_lines(boss_screen)
				_raisin_say("gow")
			"gow_flurry":
				if _manga_fx: _manga_fx.burst(boss_screen, "DOON!")
			"gow_recovery_open":
				pass   # vulnerability handled by is_vulnerable(); no FX needed
			"warp":
				# blinding-speed reposition to a new lane x
				boss.position.x = _rng.randf_range(-RAISIN_WARP_X_MAX, RAISIN_WARP_X_MAX)
				if _manga_fx: _manga_fx.burst(boss_screen, "")   # candy-dust puff
				_raisin_say("warp")
			"phase2":
				_raisin_say("phase2")
			"guard_shatter":
				if _manga_fx: _manga_fx.burst(boss_screen, "KRAK!")
			"defeat":
				boss.set_meta("dying", true)
				_raisin_say("dying")
				_show_win("Raisin Kidd", boss, null)
				return

	# Grapes of Wrath flurry drains the posse (special followers soak first).
	if _raisin.mode == RaisinKiddState.Mode.FLURRY:
		_raisin_flurry_accum += delta * RAISIN_FLURRY_DPS
		while _raisin_flurry_accum >= 1.0:
			_raisin_flurry_accum -= 1.0
			_outlaw_drain_posse(boss.position, "")
```
Add a thin `_raisin_say(kind)` that mirrors `_rustler_say`'s bank lookup (VO banks are generated in Task 8; stub it to no-op-if-missing so the fight runs before VO exists):
```gdscript
func _raisin_say(kind: String) -> void:
	var banks: Dictionary = {
		"intro": ["raisin_intro_", 2], "gow": ["raisin_gow_", 3],
		"warp": ["raisin_warp_", 3], "phase2": ["raisin_phase2_", 2],
		"hit": ["raisin_hit_", 4], "dying": ["raisin_dying_", 2],
	}
	if not banks.has(kind):
		return
	var audio := get_node_or_null("/root/AudioBus")
	if audio == null or not audio.has_method("play_character_line"):
		return
	var entry: Array = banks[kind]
	audio.play_character_line("%s%d" % [entry[0], randi() % int(entry[1])])
```

- [ ] **Step 5: Wire the spawn + process dispatch**

At the boss-event spawn site (~3616) extend the if/else:
```gdscript
				var bk := String(ev.params.get("boss", "pete"))
				if bk == "rustler":
					_spawn_candy_rustler()
				elif bk == "raisin":
					_spawn_raisin_kidd()
				else:
					_spawn_pete()
```
At the `_boss_kind()`-driven spawn site (~5348) and the quota-driven one (~6411) apply the same three-way branch. At the per-frame boss process dispatch (~6524), add a raisin branch beside the rustler one:
```gdscript
	if _pete_spawned and boss_root.get_child_count() > 0:
		var the_boss: Node3D = boss_root.get_child(0)
		if is_instance_valid(the_boss):
			match the_boss.get_meta("boss_kind", "pete"):
				"rustler": _process_rustler(the_boss, delta)
				"raisin": _process_raisin_kidd(the_boss, delta)
```
Note: the existing Pete block above this guard already runs for `boss_kind == "pete"`; verify the raisin boss is excluded from the Pete block the same way the rustler is (the Pete block's `is_instance_valid(...) and ... != "rustler"` guard at ~6424 must also exclude `"raisin"` — change it to `not in ["rustler", "raisin"]` or an equivalent check).

- [ ] **Step 6: Headless smoke (parse + boot)**

Run the importer; it must report no parse errors in `level_3d.gd`:
```bash
/tmp/godot/Godot_v4.6.1-stable_linux.x86_64 --headless --import --path godot 2>&1 | grep -iE "error|level_3d" | head
```
Expected: no `SCRIPT ERROR` / parse errors mentioning `level_3d.gd`. Then run the full GUT suite to confirm nothing regressed:
```bash
/tmp/godot/Godot_v4.6.1-stable_linux.x86_64 --headless --path godot -s res://addons/gut/gut_cmdln.gd -gconfig=res://.gutconfig.json 2>&1 | tail -20
```
Expected: all tests PASS.

- [ ] **Step 7: Commit**
```bash
git add godot/scripts/level_3d.gd
git commit -m "feat(level5): spawn + drive Raisin Kidd boss (deflect/counter, warp, GoW, manga FX)"
```

---

## Task 7: Five-Point Exploding Gumdrop lose cinematic

When the player loses *at this boss* (posse wiped / hearts exhausted while `boss_kind == "raisin"`), play the finisher cinematic before the Fail modal: title card → five-point strike burst → gumdrop countdown → KA-BLOOM → DEFEATED → Fail modal. This is a non-interactive flourish (spec §4).

**Files:**
- Modify: `godot/scripts/level_3d.gd` — the lose/fail path (find where `_show_fail`/FailModal is invoked).

- [ ] **Step 1: Find the lose path**

```bash
grep -n "_show_fail\|FailModal\|fail_modal\|hearts.*0\|_on_posse_wiped\|game_over\|_lose" godot/scripts/level_3d.gd | head -20
```
Identify the function that triggers the Fail modal when the posse/hearts hit zero. Call it `_trigger_fail()` below (use the real name found).

- [ ] **Step 2: Add the cinematic coroutine**

Add to `level_3d.gd`:
```gdscript
# Five-Point Raisin Exploding Gumdrop Technique — the lose cinematic, only when
# the player is defeated AT the Raisin Kidd boss (spec §4). Non-interactive.
func _play_raisin_finisher() -> void:
	if _manga_fx == null:
		return
	var center: Vector2 = get_viewport_rect().size * Vector2(0.5, 0.42)
	var strike: Vector2 = get_viewport_rect().size * Vector2(0.5, 0.6)
	_raisin_say("dying")   # reuse his cackle bank; a dedicated finisher line can swap in later
	_manga_fx.title_card("FIVE-POINT RAISIN\nEXPLODING GUMDROP!")
	await get_tree().create_timer(1.1).timeout
	for i in range(5):
		_manga_fx.burst(strike + Vector2((i - 2) * 30, (i - 2) * 12), "BAP!")
		await get_tree().create_timer(0.12).timeout
	_manga_fx.gumdrop_countdown(strike)
	await get_tree().create_timer(0.45 * 5.0 + 0.9).timeout
	# DEFEATED stamp via a final title card, then hand off to the Fail modal.
	_manga_fx.title_card("DEFEATED")
	await get_tree().create_timer(0.9).timeout
```

- [ ] **Step 3: Gate the fail path on the boss**

In the fail trigger found in Step 1, branch: if a raisin boss is live, play the finisher first, then show the modal. Example shape (adapt to the real function):
```gdscript
func _trigger_fail() -> void:
	var raisin_live := false
	if boss_root.get_child_count() > 0:
		var b: Node = boss_root.get_child(0)
		raisin_live = is_instance_valid(b) and b.get_meta("boss_kind", "") == "raisin"
	if raisin_live:
		await _play_raisin_finisher()
	# ... existing fail-modal code unchanged ...
```
If the existing fail function is not already `async`-friendly (no `await`), wrap the finisher in a guard so non-raisin fails are untouched, and ensure the function is allowed to `await` (GDScript funcs can `await` freely). Verify the modal still shows for a normal (non-raisin) loss.

- [ ] **Step 4: Headless parse check**
```bash
/tmp/godot/Godot_v4.6.1-stable_linux.x86_64 --headless --import --path godot 2>&1 | grep -iE "error|level_3d" | head
```
Expected: no parse errors. Full visual confirmation is the device pass (Task 10).

- [ ] **Step 5: Commit**
```bash
git add godot/scripts/level_3d.gd
git commit -m "feat(level5): Five-Point Exploding Gumdrop lose cinematic"
```

---

## Task 8: Raisin Kidd voice-over

**Files:**
- Use: the existing `tools/gen_*_vo.py` pattern + roguelike venv (see `[[reference_elevenlabs_vo]]`).
- Output: `godot/assets/audio/vo/raisin_*.ogg` (match the existing VO directory + AudioBus line-key convention).

- [ ] **Step 1: Add the EL voice to the account**

The voice `1a0nAYA3FcNQcMMfbddY` is a *library* voice — it must be added to our account before TTS works. If you have the EL API key (GSM), attempt the add-to-account endpoint; otherwise this is a one-line owner action ("Add to my voices" in the EL UI). Confirm with a 1-line TTS smoke before generating the full set.

- [ ] **Step 2: Write the line set**

Author lines per bank (keys must match `_raisin_say`): `raisin_intro_0..1`, `raisin_gow_0..2`, `raisin_warp_0..2`, `raisin_phase2_0..1`, `raisin_hit_0..3`, `raisin_dying_0..1`. Arrogant Pai-Mei cadence + sinister cackle; the GoW lines shout the move name; one dying line doubles as the finisher cackle. Keep them family-friendly (candy framing).

- [ ] **Step 3: Generate + place the audio**

Run the gen script (the `gen_humbug_vo.py`/`gen_*_vo.py` pattern, `apply_text_normalization="on"`, voice `1a0nAYA3FcNQcMMfbddY`), writing each line to the VO audio dir under the matching key. Register the keys in AudioBus the same way the rustler/pete lines are registered.

- [ ] **Step 4: Smoke**

Headless boot the level (or unit-check AudioBus has the keys) to confirm `play_character_line("raisin_intro_0")` resolves. No silent missing-key warnings.

- [ ] **Step 5: Commit**
```bash
git add godot/assets/audio/vo/raisin_*.ogg <audio_bus_or_manifest_changes>
git commit -m "feat(level5): Raisin Kidd voice-over line set"
```

---

## Task 9: Green-screen the remaining boss + monk clips

The two *attack* clips are already keyed (`grapes_of_wrath_green`, `five_point_strike_green`). The idle/move + monk clips are still studio-bg. Produce keyed versions so the billboards composite cleanly (spec §7).

**Files:**
- Regenerate: `godot/assets/videos/raisin_kidd/{guard_idle,leap}.ogv` and `godot/assets/videos/candy_monk/{hadouken,candy_star_blue}.ogv` as green-keyed (or add `_green` variants and point the constants at them).

- [ ] **Step 1: Re-seed on green**

For each clip: NB-Pro a flat-green-bg seed still from the existing pose render (`replace background with solid flat chroma-key green`), then `veo_render.sh --image <green_seed>` from it (Veo ignores a bare "green screen" prompt without a green seed — the documented quirk). Keep attacks RAI-safe (tai-chi/dance + candy-light orbs).

- [ ] **Step 2: Key + transcode**

`ffmpeg colorkey` sampling the green hex from a MID-frame (~1.8 s, not frame 0 — black fade-in), then transcode to `.ogv` for the billboards. **Preserve the Grapes-of-Wrath translucency** — do NOT tighten the key to remove the partial phasing on that move (owner-approved happy accident).

- [ ] **Step 3: Point the constants at the keyed clips**

If you produced `_green` variants, update `RAISIN_GUARD_STREAM` and `MONK_OUTLAW_VIDEOS` to the keyed paths. If you regenerated in place, no code change.

- [ ] **Step 4: Commit**
```bash
git add godot/assets/videos/raisin_kidd/ godot/assets/videos/candy_monk/ godot/scripts/level_3d.gd
git commit -m "feat(level5): green-screen boss idle/move + monk clips"
```

---

## Task 10: Device pass + tuning

**Files:**
- Tune: constants in `raisin_kidd_state.gd` and `level_3d.gd` (monk weights, flurry DPS, warp range), `level_5.tres` (quota, star thresholds).

- [ ] **Step 1: Sideload**

`scripts/sideload.sh` → universal APK. Jump to Level 5 via the debug menu / DebugPreview if available (mirror how Kimmy/other set-pieces are previewed).

- [ ] **Step 2: Verify the run**

Confirm: badlands terrain + warm fog render; heat weather (or graceful clear fallback); both monk tints spawn and lob/throw; quota counts down to the boss trigger.

- [ ] **Step 3: Verify the fight**

Confirm: Raisin reaches arena center; jellybean fire pings (TINK) + fills the guard-break meter; sustained fire shatters → ~3 s damage window; Grapes of Wrath telegraphs (focus lines + DOON!), drains the posse, and leaves a punishable recovery; warp repositions ~every 10 s (7 s in phase 2); phase 2 at 50% HP; defeat runs the WIN flow; **losing at the boss plays the Five-Point finisher → DEFEATED → Fail modal**. Verify the GoW translucency reads as intended (kept).

- [ ] **Step 4: Tune + record**

Adjust tunables to taste; update `[[project_raisin_kidd]]` memory with the device-tuned values and any fast-follow nits. Commit tuning.
```bash
git add godot/scripts/raisin_kidd_state.gd godot/scripts/level_3d.gd godot/resources/levels/level_5.tres
git commit -m "tune(level5): device-tuned Raisin Kidd fight + Level 5 pacing"
```

---

## Self-Review (against the spec)

**Spec coverage:**
- §1 concept / niche → boss as a distinct deflect-counter timing fight: Task 4 (state machine) + Task 6 (drive). ✓
- §2 appearance/animation (two poses) → guard idle billboard (Task 6); leap clip reserved for warp re-entry polish (Task 9 keys it; wiring the leap-on-warp swap is a fast-follow noted in Task 6's warp handler). **Gap flagged:** the plan uses the guard clip for the body and does not swap to the leap clip on warp/attack — acceptable v1, but call it out as a follow-up rather than silently dropping it. *(Added note here; no extra task — the warp handler is the hook point.)*
- §3 combat (deflect, guard-break meter, Grapes of Wrath windup/flurry/recovery, warp, phases, win) → Task 4 fully, Task 6 wires it. ✓
- §4 Five-Point lose finisher (title card → 5-strike → countdown → KA-BLOOM → DEFEATED) → Task 5 (FX) + Task 7 (cinematic). ✓
- §5 Level 5 badlands + LevelDef + arena stop → Task 1 + Task 2 (terrain stop reuses the existing boss-engage trigger). ✓ (heat-shimmer weather flagged as verify-or-defer in Task 2/10.)
- §6 two monk outlaws → Task 3. ✓
- §7 mobile-safe build (billboards + additive canvas + Rye) → Task 3/5/6, no custom 3D shaders. ✓
- §8 TODOs (green-screen clips, VO, tuning, keep translucency) → Tasks 8/9/10. ✓

**Placeholder scan:** no "TBD"/"add error handling"/"similar to Task N" — code is inline. Two intentional adapt-to-real-name spots (the fail-trigger function in Task 7, the gameplay camera accessor in Task 6) are explicitly flagged with how to find the real name, not left vague.

**Type consistency:** `RaisinKiddState.Mode.{GUARD,WINDUP,FLURRY,RECOVERY,BROKEN,DEAD}`, `register_fire(int)`, `tick(delta)->Array`, `is_vulnerable()`, `gow_interval()`, `warp_interval()`, fields `hp/meter/mode/phase` — used identically in tests (Task 4) and the driver (Task 6). MangaFx API `focus_lines/burst/title_card/gumdrop_countdown/clear/is_active` — identical in tests (Task 5) and driver (Tasks 6/7). Boss meta key `"boss_kind" == "raisin"` consistent across spawn (Task 6 Step 3), dispatch (Step 5), and fail gate (Task 7). ✓
