# Win / Retry Flow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the bare win/fail overlays with a Candy-Crush-style end-of-level flow — bounce-in modals, a candy star-rating, heart-cookie lives with dancing/lonely personality, and a celebratory return to the level-select map.

**Architecture:** New self-contained UI widgets (`StarRating`, `HeartCookieRow`) and modal scenes (`WinModal`, `FailModal`) that take data and emit signals; `level_3d` owns all transitions and persistence; `GameState`/`LevelDef` hold data + persistence; `level_select` plays the map celebration. Pure logic (star math, persistence, heart accounting, widget slot-state) is GUT-tested; motion is verified by `sp1-screenshot` stills and on device.

**Tech Stack:** Godot 4.6.1, GDScript, GUT (`addons/gut/gut_cmdln.gd`), ElevenLabs SFX pipeline, NB-Pro-rendered art (already staged at `docs/superpowers/assets/winflow_2026-06-04/`).

---

## Conventions

- **Run GUT (all tests):**
  ```bash
  cd godot && xvfb-run -a "$HOME/.local/bin/godot" --headless --path . \
    -s res://addons/gut/gut_cmdln.gd -gconfig=res://.gutconfig.json -gexit 2>&1 | tail -25
  ```
  Expected on success: `All tests passed!` and `Exiting with code 0`. (The `RID allocations ... leaked at exit` lines are pre-existing harness noise, not failures.)
- **Run one test file:** add `-gtest=res://test/<file>.gd` to the command above.
- **Screenshot a scene:** `.claude/skills/sp1-screenshot/capture.sh res://scenes/<scene>.tscn /tmp/<name>.png` then Read the PNG.
- **GDScript edits:** the Edit tool's tab-matching is unreliable on this codebase's tabs; prefer a small Python `str.replace` script for multi-line GDScript edits (assert the match count == 1).
- Commit after every task with the message shown in its final step.

---

## File Structure

**Create:**
- `tools/winflow_assets.py` — one-shot: green-key + autocrop the staged art into `godot/assets/sprites/ui/winflow/`.
- `godot/assets/sprites/ui/winflow/*.png` (+ `.import`) — `star_pepper, star_gold, star_gummy, star_sugar, dish_oval, heart_full, heart_empty, cutout_taffy`.
- `godot/scripts/star_rating.gd` + `godot/scenes/ui/star_rating.tscn` — the candy star-rating widget.
- `godot/scripts/heart_cookie_row.gd` + `godot/scenes/ui/heart_cookie_row.tscn` — replaces `HeartRow`.
- `godot/scripts/win_modal.gd` + `godot/scenes/ui/win_modal.tscn`.
- `godot/scripts/fail_modal.gd` + `godot/scenes/ui/fail_modal.tscn`.
- `godot/test/test_star_rules.gd`, `godot/test/test_game_state_progress.gd`, `godot/test/test_star_rating_widget.gd`, `godot/test/test_heart_cookie_row.gd`.

**Modify:**
- `godot/scripts/level_def.gd` — add `star_thresholds` + `outlaw_quota`.
- `godot/resources/levels/level_1..4.tres` — set thresholds.
- `godot/scripts/game_state.gd` — persist `current_level`; add `level_best`, `record_level_result`, `stars_for`, `just_won_level`.
- `godot/scripts/level_3d.gd` — snapshot level bounty; use modals; move heart-spend; wire signals; outlaw-quota countdown + boss-on-zero; taffy outlaw number.
- `godot/scenes/level_3d.tscn` — add taffy cutout + HeartCookieRow top-left; remove WinOverlay/FailOverlay children's reliance (modals instanced at runtime).
- `godot/scripts/level_select.gd` + `godot/scenes/*level_select*.tscn` — celebration + per-orb stars.
- `tools/gen_creature_sfx.py` — add `heart_regen_cheer`.

---

## Phase 0 — Assets

### Task 1: Green-key + autocrop the staged art into game sprites

**Files:**
- Create: `tools/winflow_assets.py`
- Create (output): `godot/assets/sprites/ui/winflow/{star_pepper,star_gold,star_gummy,star_sugar,dish_oval,heart_full,heart_empty,cutout_taffy}.png`

- [ ] **Step 1: Write the pipeline script**

```python
# tools/winflow_assets.py — one-shot. Green-keys + autocrops the staged
# NB-Pro winflow renders into clean transparent game sprites.
#   python3 tools/winflow_assets.py
import numpy as np
from PIL import Image, ImageFilter
from pathlib import Path

SRC = Path("docs/superpowers/assets/winflow_2026-06-04")
DST = Path("godot/assets/sprites/ui/winflow"); DST.mkdir(parents=True, exist_ok=True)
# staged filename -> output sprite name
MAP = {
    "g_pepper": "star_pepper", "g_hard": "star_gold", "g_gummy": "star_gummy",
    "g_sugar": "star_sugar", "td_oval": "dish_oval",
    "heart_full": "heart_full", "heart_empty": "heart_empty",
    "cutout_taffy": "cutout_taffy",
}

def greenkey(src, low=12, high=46):
    a = np.array(Image.open(src).convert("RGBA")).astype(np.float32)
    R, G, B = a[:, :, 0], a[:, :, 1], a[:, :, 2]
    g = G - np.maximum(R, B)
    alpha = np.clip((high - g) / (high - low), 0, 1) * 255.0
    G2 = G - np.maximum(0, G - np.maximum(R, B)) * 0.9   # despill
    out = a.copy(); out[:, :, 1] = G2; out[:, :, 3] = alpha
    out = np.clip(out, 0, 255).astype(np.uint8)
    al = Image.fromarray(out[:, :, 3]).filter(ImageFilter.GaussianBlur(0.6))
    out[:, :, 3] = np.array(al)
    im = Image.fromarray(out); bb = im.getbbox()
    return im.crop(bb) if bb else im

for stem, name in MAP.items():
    src = SRC / f"{stem}.png"
    if not src.exists():
        raise SystemExit(f"missing staged asset: {src}")
    greenkey(src).save(DST / f"{name}.png")
    print("wrote", DST / f"{name}.png")
```

- [ ] **Step 2: Run it**

Run: `cd /home/projects/Not_This_Again && python3 tools/winflow_assets.py`
Expected: 8 `wrote .../winflow/<name>.png` lines, no error.

- [ ] **Step 3: Materialise Godot `.import` sidecars**

Run:
```bash
cd /home/projects/Not_This_Again/godot && xvfb-run -a "$HOME/.local/bin/godot" --headless --path . --import 2>&1 | tail -3
```
Expected: import completes; `godot/assets/sprites/ui/winflow/*.png.import` now exist (`ls godot/assets/sprites/ui/winflow/*.import` shows 8).

- [ ] **Step 4: Eyeball one over a dark background**

```bash
cd /home/projects/Not_This_Again && python3 - <<'PY'
from PIL import Image
fg=Image.open("godot/assets/sprites/ui/winflow/star_pepper.png").convert("RGBA")
bg=Image.new("RGBA",fg.size,(26,18,38,255))
Image.alpha_composite(bg,fg).convert("RGB").save("/tmp/winflow_check.png")
PY
```
Then Read `/tmp/winflow_check.png` — confirm clean edges, no green fringe, no holes.

- [ ] **Step 5: Commit**

```bash
cd /home/projects/Not_This_Again
git add tools/winflow_assets.py godot/assets/sprites/ui/winflow/
git commit -m "winflow: green-key staged art into ui/winflow sprites"
```

### Task 2: Add the heart-regen cheer SFX

**Files:**
- Modify: `tools/gen_creature_sfx.py` (the `SFX` dict)
- Create (output): `godot/assets/sfx/creatures/heart_regen_cheer.mp3`

- [ ] **Step 1: Add the SFX entry**

In `tools/gen_creature_sfx.py`, add inside the `SFX` dict:
```python
    "heart_regen_cheer": (
        "a short warm celebratory cheer with a tiny sparkle chime, like a heart "
        "refilling in a candy mobile game, upbeat and brief",
        1.0,
    ),
```

- [ ] **Step 2: Generate it**

Run: `cd /home/projects/Not_This_Again && /home/projects/roguelike/.venv-eleven/bin/python tools/gen_creature_sfx.py 2>&1 | tail -5`
Expected: a line indicating `heart_regen_cheer` was generated (others skipped as existing). Verify `ls -la godot/assets/sfx/creatures/heart_regen_cheer.mp3` shows a non-empty file.

- [ ] **Step 3: Commit**

```bash
cd /home/projects/Not_This_Again
git add tools/gen_creature_sfx.py godot/assets/sfx/creatures/heart_regen_cheer.mp3
git commit -m "winflow: add heart_regen_cheer SFX"
```

---

## Phase 1 — Data + persistence (pure logic, GUT)

### Task 3: LevelDef.star_thresholds

**Files:**
- Modify: `godot/scripts/level_def.gd`
- Modify: `godot/resources/levels/level_1.tres` … `level_4.tres`

- [ ] **Step 1: Add the field**

In `godot/scripts/level_def.gd`, after the `weather_type` export, add:
```gdscript
# Win/retry flow: ascending bounty cutoffs for 1/2/3 stars. t1 should be
# reachable simply by finishing (a win always grants >= 1 star). Tuned per level.
@export var star_thresholds: Array[int] = [0, 1500, 3500]
```

Also add the outlaw quota (the level objective + boss trigger, §6a):
```gdscript
# Win/retry flow: number of outlaws to clear before the boss appears. The
# top-left taffy badge counts this down; reaching 0 triggers the boss. 0 = use
# the legacy distance/timer boss trigger instead.
@export var outlaw_quota: int = 60
```

- [ ] **Step 2: Set per-level thresholds**

In each `godot/resources/levels/level_N.tres`, in the `[resource]` block, add a line (tuned by difficulty):
- `level_1.tres`: `star_thresholds = Array[int]([0, 1200, 3000])`
- `level_2.tres`: `star_thresholds = Array[int]([0, 1800, 4200])`
- `level_3.tres`: `star_thresholds = Array[int]([0, 2400, 5500])`
- `level_4.tres`: `star_thresholds = Array[int]([0, 3000, 7000])`

Also add an `outlaw_quota` line per level (scaling with difficulty):
- `level_1.tres`: `outlaw_quota = 40`
- `level_2.tres`: `outlaw_quota = 60`
- `level_3.tres`: `outlaw_quota = 85`
- `level_4.tres`: `outlaw_quota = 120`

- [ ] **Step 3: Verify it loads**

Run the full GUT suite (Conventions). Expected: still `All tests passed!` (no parse error from the new export / .tres lines).

- [ ] **Step 4: Commit**

```bash
cd /home/projects/Not_This_Again
git add godot/scripts/level_def.gd godot/resources/levels/level_*.tres
git commit -m "winflow: LevelDef.star_thresholds + outlaw_quota + per-level values"
```

### Task 4: Star computation helper (GUT)

**Files:**
- Modify: `godot/scripts/game_state.gd`
- Test: `godot/test/test_star_rules.gd`

- [ ] **Step 1: Write the failing test**

```gdscript
# godot/test/test_star_rules.gd
extends GutTest

const GameStateScript = preload("res://scripts/game_state.gd")

func test_below_first_threshold_is_one_star_on_win():
	# A win always grants >= 1 star even if bounty is under t1.
	assert_eq(GameStateScript.stars_for(0, [0, 1500, 3500]), 1)

func test_meets_second_threshold():
	assert_eq(GameStateScript.stars_for(1500, [0, 1500, 3500]), 2)

func test_meets_third_threshold():
	assert_eq(GameStateScript.stars_for(9999, [0, 1500, 3500]), 3)

func test_between_thresholds():
	assert_eq(GameStateScript.stars_for(2000, [0, 1500, 3500]), 2)

func test_caps_at_three():
	assert_eq(GameStateScript.stars_for(99999, [0, 10, 20, 30, 40]), 3)
```

- [ ] **Step 2: Run it — expect FAIL**

Run with `-gtest=res://test/test_star_rules.gd`. Expected: failures (`stars_for` not found).

- [ ] **Step 3: Implement `stars_for`**

In `godot/scripts/game_state.gd`, add (static, near the bottom):
```gdscript
# Win/retry flow: stars (1..3) earned for a run's bounty against ascending
# thresholds. A win always grants >= 1 star; result is clamped to 3.
static func stars_for(run_bounty: int, thresholds: Array) -> int:
	var n: int = 1
	for t in thresholds:
		if run_bounty >= int(t):
			n = maxi(n, 1 + thresholds.find(t))
	return clampi(n, 1, 3)
```
*(Note: `thresholds.find(t)` returns the index; for ascending `[0,1500,3500]`, meeting index 2 → 3 stars. Equal values are fine because `find` returns the first index and `maxi` keeps the largest met.)*

- [ ] **Step 4: Run it — expect PASS**

Run with `-gtest=res://test/test_star_rules.gd`. Expected: 5/5 pass.

- [ ] **Step 5: Commit**

```bash
cd /home/projects/Not_This_Again
git add godot/scripts/game_state.gd godot/test/test_star_rules.gd
git commit -m "winflow: GameState.stars_for + tests"
```

### Task 5: Persist current_level + level_best + just_won_level

**Files:**
- Modify: `godot/scripts/game_state.gd`
- Test: `godot/test/test_game_state_progress.gd`

- [ ] **Step 1: Write the failing test**

```gdscript
# godot/test/test_game_state_progress.gd
extends GutTest

const GameStateScript = preload("res://scripts/game_state.gd")
var state: Node

func before_each():
	state = autofree(GameStateScript.new())

func test_record_level_result_stores_best():
	state.record_level_result(1, 2, 1800)
	assert_eq(state.level_best.get(1, {}).get("stars", 0), 2)
	assert_eq(state.level_best.get(1, {}).get("bounty", 0), 1800)

func test_record_level_result_keeps_max():
	state.record_level_result(1, 2, 1800)
	state.record_level_result(1, 1, 600)   # worse run must not lower the best
	assert_eq(state.level_best[1]["stars"], 2)
	assert_eq(state.level_best[1]["bounty"], 1800)

func test_record_level_result_improves():
	state.record_level_result(1, 1, 600)
	state.record_level_result(1, 3, 4000)
	assert_eq(state.level_best[1]["stars"], 3)
	assert_eq(state.level_best[1]["bounty"], 4000)

func test_just_won_level_defaults_zero():
	assert_eq(state.just_won_level, 0)
```

- [ ] **Step 2: Run it — expect FAIL**

Run with `-gtest=res://test/test_game_state_progress.gd`. Expected: failures (`record_level_result`, `level_best`, `just_won_level` missing).

- [ ] **Step 3: Implement the state + merge**

In `godot/scripts/game_state.gd`:

Add member vars near the other vars:
```gdscript
# Win/retry flow: per-level best result {level:int -> {stars:int, bounty:int}}.
# Persisted. Drives the map orbs' star display.
var level_best: Dictionary = {}
# Transient (NOT persisted) handoff: set to the level number just won so
# level_select plays the celebration walk on its next _ready, then cleared.
var just_won_level: int = 0
```

Add the merge method:
```gdscript
# Win/retry flow: record a level result, keeping the best stars and bounty.
func record_level_result(level: int, stars: int, run_bounty: int) -> void:
	var prev: Dictionary = level_best.get(level, {"stars": 0, "bounty": 0})
	level_best[level] = {
		"stars": maxi(int(prev["stars"]), stars),
		"bounty": maxi(int(prev["bounty"]), run_bounty),
	}
	_save_to_disk()
```

- [ ] **Step 4: Run it — expect PASS**

Run with `-gtest=res://test/test_game_state_progress.gd`. Expected: 4/4 pass.

- [ ] **Step 5: Persist current_level + level_best (round-trip test)**

Add to `test_game_state_progress.gd`:
```gdscript
func test_persistence_round_trip(tmp = "user://test_gamestate_progress.cfg"):
	state.SAVE_PATH_OVERRIDE = tmp
	state.current_level = 3
	state.record_level_result(2, 3, 4200)
	state._save_to_disk()
	var s2 = autofree(GameStateScript.new())
	s2.SAVE_PATH_OVERRIDE = tmp
	s2._load_from_disk()
	assert_eq(s2.current_level, 3)
	assert_eq(s2.level_best.get(2, {}).get("stars", 0), 3)
```

- [ ] **Step 6: Run it — expect FAIL, then implement persistence**

Run the file; expect the round-trip test fails. Then in `game_state.gd`:

Add an overridable save path (so tests don't clobber the real save), near `SAVE_PATH`:
```gdscript
# Tests set this to a temp path; empty = use SAVE_PATH.
var SAVE_PATH_OVERRIDE: String = ""

func _save_path() -> String:
	return SAVE_PATH_OVERRIDE if SAVE_PATH_OVERRIDE != "" else SAVE_PATH
```

In `_save_to_disk()`, change the guard + path and add the new fields. Replace the body with:
```gdscript
func _save_to_disk() -> void:
	if not is_inside_tree() and SAVE_PATH_OVERRIDE == "":
		return
	var cfg := ConfigFile.new()
	cfg.set_value("hearts", "current", hearts)
	cfg.set_value("hearts", "last_spend_unix", _last_spend_unix)
	cfg.set_value("meta", "bounty", bounty)
	cfg.set_value("meta", "current_level", current_level)
	cfg.set_value("meta", "level_best", level_best)
	var _err: int = cfg.save(_save_path())
```

In `_load_from_disk()`, change the existence check + load to `_save_path()` and read the new fields. Replace the body with:
```gdscript
func _load_from_disk() -> void:
	if not FileAccess.file_exists(_save_path()):
		return
	var cfg := ConfigFile.new()
	if cfg.load(_save_path()) != OK:
		return
	hearts = clampi(int(cfg.get_value("hearts", "current", MAX_HEARTS)), 0, MAX_HEARTS)
	_last_spend_unix = int(cfg.get_value("hearts", "last_spend_unix", 0))
	bounty = int(cfg.get_value("meta", "bounty", 0))
	current_level = maxi(1, int(cfg.get_value("meta", "current_level", 1)))
	level_best = cfg.get_value("meta", "level_best", {})
	apply_regen()
```

- [ ] **Step 7: Run it — expect PASS**

Run the file. Expected: all pass (5/5). Then run the FULL suite — expect `All tests passed!` (no regression in `test_game_state.gd`).

- [ ] **Step 8: Commit**

```bash
cd /home/projects/Not_This_Again
git add godot/scripts/game_state.gd godot/test/test_game_state_progress.gd
git commit -m "winflow: persist current_level + level_best, just_won_level handoff"
```

---

## Phase 2 — StarRating widget

### Task 6: StarRating slot logic (GUT) + scene

**Files:**
- Create: `godot/scripts/star_rating.gd`, `godot/scenes/ui/star_rating.tscn`
- Test: `godot/test/test_star_rating_widget.gd`

- [ ] **Step 1: Write the failing test (pure logic only)**

```gdscript
# godot/test/test_star_rating_widget.gd
extends GutTest

const StarRating = preload("res://scripts/star_rating.gd")

func test_candy_path_by_difficulty():
	assert_string_ends_with(StarRating.candy_tex_path(1), "star_pepper.png")
	assert_string_ends_with(StarRating.candy_tex_path(2), "star_gold.png")
	assert_string_ends_with(StarRating.candy_tex_path(3), "star_gummy.png")
	assert_string_ends_with(StarRating.candy_tex_path(4), "star_sugar.png")

func test_candy_path_clamps_unknown_difficulty():
	assert_string_ends_with(StarRating.candy_tex_path(99), "star_pepper.png")

func test_slot_count_is_three():
	assert_eq(StarRating.SLOT_FRACS.size(), 3)
```

- [ ] **Step 2: Run it — expect FAIL**

Run with `-gtest=res://test/test_star_rating_widget.gd`. Expected: fail (script missing).

- [ ] **Step 3: Implement the widget script**

```gdscript
# godot/scripts/star_rating.gd
class_name StarRating
extends Control

# Candy star-rating: 1..3 difficulty-matched candies seated in a top-down
# oval boat dish. set_rating(difficulty, earned) fills `earned` slots with the
# breathing candy; the rest show a faint ghost. Pure layout data is static so
# it is unit-testable without instancing the scene.

const DIR := "res://assets/sprites/ui/winflow/"
const CANDY_BY_DIFFICULTY := {1: "star_pepper", 2: "star_gold", 3: "star_gummy", 4: "star_sugar"}
# Slot centres as (x,y) fraction of the dish box; index 0 used for 1-star,
# 0+2 for 2-star, all three for 3-star. Centre slot is slightly larger.
const SLOT_FRACS := [Vector2(0.50, 0.50), Vector2(0.28, 0.50), Vector2(0.72, 0.50)]
const SLOT_SIZE := [1.0, 0.92, 0.92]   # centre bigger

static func candy_tex_path(difficulty: int) -> String:
	var name: String = CANDY_BY_DIFFICULTY.get(difficulty, "star_pepper")
	return DIR + name + ".png"

# Which slot indices are used for a given star count (so they stay centred).
static func slots_for(stars: int) -> Array:
	match clampi(stars, 0, 3):
		1: return [0]
		2: return [1, 2]
		3: return [0, 1, 2]
		_: return []

@onready var _dish: TextureRect = $Dish

var _difficulty: int = 1
var _earned: int = 0
var _candies: Array = []   # holds spawned candy/ghost nodes

func set_rating(difficulty: int, earned: int, animate: bool = false) -> void:
	_difficulty = difficulty
	_earned = clampi(earned, 0, 3)
	_rebuild(animate)

func _rebuild(animate: bool) -> void:
	for c in _candies:
		if is_instance_valid(c): c.queue_free()
	_candies.clear()
	if _dish == null: return
	var box: Vector2 = size
	var tex := load(candy_tex_path(_difficulty)) as Texture2D
	var lit: Array = slots_for(_earned)
	for i in range(3):
		var frac: Vector2 = SLOT_FRACS[i]
		var sz: float = box.x * 0.30 * SLOT_SIZE[i]
		var node := TextureRect.new()
		node.texture = tex
		node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		node.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		node.custom_minimum_size = Vector2(sz, sz)
		node.size = Vector2(sz, sz)
		node.position = Vector2(frac.x * box.x - sz * 0.5, frac.y * box.y - sz * 0.5)
		node.pivot_offset = Vector2(sz * 0.5, sz * 0.5)
		if lit.has(i):
			_breathe(node, float(lit.find(i)) * 0.25)
			if animate: _pop_in(node, float(lit.find(i)) * 0.18)
		else:
			node.modulate = Color(1, 1, 1, 0.28)   # ghost slot
		add_child(node)
		_candies.append(node)

func _breathe(node: Control, delay: float) -> void:
	var t := node.create_tween().set_loops()
	t.tween_interval(delay)
	t.tween_property(node, "scale", Vector2(1.06, 1.06), 0.95).set_trans(Tween.TRANS_SINE)
	t.tween_property(node, "scale", Vector2.ONE, 0.95).set_trans(Tween.TRANS_SINE)

func _pop_in(node: Control, delay: float) -> void:
	node.scale = Vector2(0.2, 0.2)
	var t := node.create_tween()
	t.tween_interval(delay)
	t.tween_property(node, "scale", Vector2.ONE, 0.4) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if has_node("/root/AudioBus"):
		t.tween_callback(get_node("/root/AudioBus").play_sfx.bind("bonus_pickup"))
```

- [ ] **Step 4: Create the scene**

Create `godot/scenes/ui/star_rating.tscn`:
```
[gd_scene load_steps=3 format=3]

[ext_resource type="Script" path="res://scripts/star_rating.gd" id="1"]
[ext_resource type="Texture2D" path="res://assets/sprites/ui/winflow/dish_oval.png" id="2"]

[node name="StarRating" type="Control"]
custom_minimum_size = Vector2(220, 150)
script = ExtResource("1")

[node name="Dish" type="TextureRect" parent="."]
anchors_preset = 15
texture = ExtResource("2")
expand_mode = 1
stretch_mode = 5
```

- [ ] **Step 5: Run the test — expect PASS**

Run with `-gtest=res://test/test_star_rating_widget.gd`. Expected: 3/3 pass.

- [ ] **Step 6: Screenshot-verify the widget renders**

Create a throwaway scene `/tmp/sr_preview.tscn`? Instead, temporarily set `level_3d` aside — simplest: add a tiny harness scene. Run:
```bash
cd /home/projects/Not_This_Again && cat > godot/scenes/ui/_sr_preview.tscn <<'EOF'
[gd_scene load_steps=2 format=3]
[ext_resource type="PackedScene" path="res://scenes/ui/star_rating.tscn" id="1"]
[node name="Root" type="ColorRect"]
offset_right=1080
offset_bottom=1920
color=Color(0.1,0.07,0.15,1)
[node name="SR" parent="." instance=ExtResource("1")]
offset_left=400
offset_top=800
script=null
EOF
```
Then a temporary `_ready` is not available in a pure scene; instead screenshot via the harness which calls nothing — so for this preview, hardcode 2 stars by adding a tiny autoload-free preview script. **Simpler:** screenshot is optional here; the GUT test covers slot logic. Verify visually later inside the WinModal (Task 9). Delete the preview scene:
```bash
rm -f godot/scenes/ui/_sr_preview.tscn
```

- [ ] **Step 7: Commit**

```bash
cd /home/projects/Not_This_Again
git add godot/scripts/star_rating.gd godot/scenes/ui/star_rating.tscn godot/test/test_star_rating_widget.gd
git commit -m "winflow: StarRating widget + slot-logic tests"
```

---

## Phase 3 — HeartCookieRow

### Task 7: HeartCookieRow (GUT state) replacing HeartRow

**Files:**
- Create: `godot/scripts/heart_cookie_row.gd`, `godot/scenes/ui/heart_cookie_row.tscn`
- Test: `godot/test/test_heart_cookie_row.gd`

- [ ] **Step 1: Write the failing test (pure state)**

```gdscript
# godot/test/test_heart_cookie_row.gd
extends GutTest

const HeartCookieRow = preload("res://scripts/heart_cookie_row.gd")

var row

func before_each():
	row = autofree(HeartCookieRow.new())

func test_set_hearts_records_state():
	row.set_hearts(3, 5)
	assert_eq(row._current, 3)
	assert_eq(row._max, 5)

func test_detects_regen_increase():
	row.set_hearts(2, 5)
	assert_true(row._is_regen(3), "current going up = regen")
	assert_false(row._is_regen(1), "going down is not regen")

func test_lonely_only_at_one():
	assert_true(row._is_lonely(1))
	assert_false(row._is_lonely(2))
	assert_false(row._is_lonely(0))
```

- [ ] **Step 2: Run it — expect FAIL**

Run with `-gtest=res://test/test_heart_cookie_row.gd`. Expected: fail (script missing).

- [ ] **Step 3: Implement HeartCookieRow**

```gdscript
# godot/scripts/heart_cookie_row.gd
class_name HeartCookieRow
extends Control

# Sprite-based lives row (replaces the vector-drawn HeartRow). Full = frosted
# heart cookie, empty = plain dough cookie. 2+ full hearts dance together;
# the last lone heart looks lonely; a regenerated slot pops in with a cheer.
# set_hearts(current, maximum) matches HeartRow's contract.

const DIR := "res://assets/sprites/ui/winflow/"
const FULL := preload("res://assets/sprites/ui/winflow/heart_full.png")
const EMPTY := preload("res://assets/sprites/ui/winflow/heart_empty.png")

var _current: int = 5
var _max: int = 5
var _slots: Array = []   # TextureRect per slot

static func _is_lonely_count(c: int) -> bool:
	return c == 1

func _is_lonely(c: int) -> bool:
	return HeartCookieRow._is_lonely_count(c)

func _is_regen(new_current: int) -> bool:
	return new_current > _current

func set_hearts(current: int, maximum: int) -> void:
	var regen := _is_regen(current)
	var regen_slot := _current   # the slot that just filled (0-based index)
	_current = clampi(current, 0, maxi(maximum, 1))
	_max = maxi(maximum, 1)
	_rebuild()
	if regen and regen_slot < _slots.size():
		_play_regen(regen_slot)

func _rebuild() -> void:
	for s in _slots:
		if is_instance_valid(s): s.queue_free()
	_slots.clear()
	var slot_w: float = size.x / float(_max)
	for i in range(_max):
		var node := TextureRect.new()
		node.texture = FULL if i < _current else EMPTY
		node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		node.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		var sz: float = minf(slot_w * 0.9, size.y)
		node.custom_minimum_size = Vector2(sz, sz)
		node.size = Vector2(sz, sz)
		node.position = Vector2(slot_w * (float(i) + 0.5) - sz * 0.5, (size.y - sz) * 0.5)
		node.pivot_offset = Vector2(sz * 0.5, sz)   # pivot at the bottom-centre
		add_child(node)
		_slots.append(node)
		if i < _current:
			if _is_lonely(_current): _animate_lonely(node)
			else: _animate_dance(node, float(i) * 0.28)

func _animate_dance(node: Control, delay: float) -> void:
	var t := node.create_tween().set_loops()
	t.tween_interval(delay)
	# gentle ~2.2s sway: hop + tilt with squash-stretch on the landing
	t.tween_property(node, "rotation_degrees", 8.0, 1.1).set_trans(Tween.TRANS_SINE)
	t.parallel().tween_property(node, "position:y", node.position.y - 6.0, 0.55)
	t.parallel().tween_property(node, "position:y", node.position.y, 0.55).set_delay(0.55)
	t.tween_property(node, "rotation_degrees", -8.0, 1.1).set_trans(Tween.TRANS_SINE)

func _animate_lonely(node: Control) -> void:
	node.modulate = Color(0.92, 0.92, 0.92, 1.0)
	var t := node.create_tween().set_loops()
	t.tween_property(node, "rotation_degrees", -3.0, 1.6).set_trans(Tween.TRANS_SINE)
	t.tween_property(node, "rotation_degrees", -7.0, 1.6).set_trans(Tween.TRANS_SINE)

func _play_regen(slot: int) -> void:
	if slot >= _slots.size(): return
	var node: Control = _slots[slot]
	node.scale = Vector2(0.2, 0.2)
	var t := node.create_tween()
	t.tween_property(node, "scale", Vector2(1.15, 1.15), 0.35) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(node, "scale", Vector2.ONE, 0.15)
	if has_node("/root/AudioBus"):
		get_node("/root/AudioBus").play_sfx("heart_regen_cheer")
```

- [ ] **Step 4: Create the scene**

Create `godot/scenes/ui/heart_cookie_row.tscn`:
```
[gd_scene load_steps=2 format=3]
[ext_resource type="Script" path="res://scripts/heart_cookie_row.gd" id="1"]
[node name="HeartCookieRow" type="Control"]
custom_minimum_size = Vector2(260, 52)
script = ExtResource("1")
```

- [ ] **Step 5: Run the test — expect PASS**

Run with `-gtest=res://test/test_heart_cookie_row.gd`. Expected: 3/3 pass. Then full suite — `All tests passed!`.

- [ ] **Step 6: Commit**

```bash
cd /home/projects/Not_This_Again
git add godot/scripts/heart_cookie_row.gd godot/scenes/ui/heart_cookie_row.tscn godot/test/test_heart_cookie_row.gd
git commit -m "winflow: HeartCookieRow (cookies, dance/lonely/regen) + state tests"
```

---

## Phase 4 — Modals + level_3d wiring

### Task 8: WinModal scene + script

**Files:**
- Create: `godot/scripts/win_modal.gd`, `godot/scenes/ui/win_modal.tscn`

- [ ] **Step 1: Implement the script**

```gdscript
# godot/scripts/win_modal.gd
class_name WinModal
extends Control

# Bounce-in win panel: star rating reveal + bounty count-up + hearts, with
# CONTINUE / REPLAY / MAP buttons. Emits signals; the level owns transitions.

signal continue_pressed
signal replay_pressed
signal map_pressed

@onready var _panel: Control = $Panel
@onready var _stars: StarRating = $Panel/StarRating
@onready var _score: Label = $Panel/Score
@onready var _next: Label = $Panel/NextLabel
@onready var _hearts: HeartCookieRow = $Panel/HeartCookieRow

# difficulty: LevelDef.difficulty; run_bounty: this level's bounty; stars: 1..3;
# next_needed: bounty for the next star (0 = already maxed); hearts/max: lives.
func show_win(difficulty: int, run_bounty: int, stars: int, next_needed: int,
		hearts: int, hearts_max: int) -> void:
	visible = true
	_hearts.set_hearts(hearts, hearts_max)
	_next.text = "" if next_needed <= 0 else "%d more for the next star" % next_needed
	_stars.set_rating(difficulty, stars, true)
	_bounce_in()
	_count_up(run_bounty)

func _bounce_in() -> void:
	_panel.scale = Vector2(0.2, 0.2)
	_panel.pivot_offset = _panel.size * 0.5
	var t := _panel.create_tween()
	t.tween_property(_panel, "scale", Vector2.ONE, 0.6) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _count_up(target: int) -> void:
	_score.text = "0"
	var t := create_tween()
	t.tween_method(func(v): _score.text = "%d" % int(v), 0.0, float(target), 1.0)

func _on_continue() -> void: emit_signal("continue_pressed")
func _on_replay() -> void: emit_signal("replay_pressed")
func _on_map() -> void: emit_signal("map_pressed")
```

- [ ] **Step 2: Create the scene**

Create `godot/scenes/ui/win_modal.tscn` — a full-screen `Control` with a dim `ColorRect` scrim, a `Panel` holding `Label` "LEVEL COMPLETE!", an instance of `star_rating.tscn` (named `StarRating`), `Score` Label, `NextLabel`, an instance of `heart_cookie_row.tscn` (named `HeartCookieRow`), and three `Button`s (Continue/Replay/Map) whose `pressed` signals connect to `_on_continue`/`_on_replay`/`_on_map`. (Build in the editor or hand-author the `.tscn`; ensure node names match the `@onready` paths above.)

- [ ] **Step 3: Verify it parses**

Run the full GUT suite. Expected: `All tests passed!` (no parse error). `class_name WinModal` registering is enough; no dedicated unit test (logic is signal plumbing — covered by the level integration screenshot in Task 10).

- [ ] **Step 4: Commit**

```bash
cd /home/projects/Not_This_Again
git add godot/scripts/win_modal.gd godot/scenes/ui/win_modal.tscn
git commit -m "winflow: WinModal scene + script"
```

### Task 9: FailModal scene + script

**Files:**
- Create: `godot/scripts/fail_modal.gd`, `godot/scenes/ui/fail_modal.tscn`

- [ ] **Step 1: Implement the script**

```gdscript
# godot/scripts/fail_modal.gd
class_name FailModal
extends Control

# Bounce-in fail panel. RETRY costs 1 heart on press (chomp the rightmost
# cookie, then emit). If hearts == 0, RETRY is disabled with a regen note.

signal retry_pressed
signal map_pressed

@onready var _panel: Control = $Panel
@onready var _score: Label = $Panel/Score
@onready var _hearts: HeartCookieRow = $Panel/HeartCookieRow
@onready var _retry: Button = $Panel/RetryButton
@onready var _cost: Label = $Panel/CostLabel

func show_fail(run_bounty: int, hearts: int, hearts_max: int, regen_text: String) -> void:
	visible = true
	_score.text = "%d" % run_bounty
	_hearts.set_hearts(hearts, hearts_max)
	if hearts <= 0:
		_retry.disabled = true
		_cost.text = "Out of lives — %s" % regen_text
	else:
		_retry.disabled = false
		_cost.text = "costs 1 ♥  ·  %d left" % hearts
	_bounce_in()

func _bounce_in() -> void:
	_panel.scale = Vector2(0.2, 0.2)
	_panel.pivot_offset = _panel.size * 0.5
	_panel.create_tween().tween_property(_panel, "scale", Vector2.ONE, 0.6) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _on_retry() -> void:
	emit_signal("retry_pressed")   # level spends the heart + reloads

func _on_map() -> void:
	emit_signal("map_pressed")
```

- [ ] **Step 2: Create the scene**

Create `godot/scenes/ui/fail_modal.tscn` — full-screen `Control` + scrim + `Panel` with "POSSE SCATTERED!" Label, `Score` Label, `HeartCookieRow` instance, `RetryButton`, `CostLabel`, `MapButton`. Connect `RetryButton.pressed`→`_on_retry`, `MapButton.pressed`→`_on_map`. Node names must match the `@onready` paths.

- [ ] **Step 3: Verify it parses**

Run the full GUT suite. Expected: `All tests passed!`.

- [ ] **Step 4: Commit**

```bash
cd /home/projects/Not_This_Again
git add godot/scripts/fail_modal.gd godot/scenes/ui/fail_modal.tscn
git commit -m "winflow: FailModal scene + script"
```

### Task 10: Wire modals into level_3d (transitions, persistence, heart accounting)

**Files:**
- Modify: `godot/scripts/level_3d.gd`

- [ ] **Step 1: Snapshot per-level bounty at start**

Add a member var near the other `_level_*` vars:
```gdscript
var _bounty_at_start: int = 0   # GameState.bounty when this level began (for run-bounty)
```
In `_ready()`, right after the `_level_def` load block, add:
```gdscript
	if get_node_or_null("/root/GameState"):
		_bounty_at_start = GameState.bounty
```
Add a helper near `_add_bounty`:
```gdscript
func _run_bounty() -> int:
	if get_node_or_null("/root/GameState") == null:
		return 0
	return maxi(0, GameState.bounty - _bounty_at_start)
```

- [ ] **Step 2: Preload modal scenes**

Near the top consts of `level_3d.gd`:
```gdscript
const WIN_MODAL_SCENE := preload("res://scenes/ui/win_modal.tscn")
const FAIL_MODAL_SCENE := preload("res://scenes/ui/fail_modal.tscn")
var _end_modal: Control = null
```

- [ ] **Step 3: Replace the WinOverlay reveal with WinModal**

In `_show_win(...)`, replace the block:
```gdscript
	if win_label:
		win_label.text = "BOUNTY!\nposse %d · hits %d" % [_posse_count_3d, _hits]
	if win_overlay:
		win_overlay.visible = true
	AudioBus.play_gate_pass()
```
with:
```gdscript
	AudioBus.play_gate_pass()
	_present_win_modal()
```
And add the method:
```gdscript
func _present_win_modal() -> void:
	var diff: int = _level_def.difficulty if _level_def != null else 1
	var thr: Array = _level_def.star_thresholds if _level_def != null else [0, 1500, 3500]
	var rb: int = _run_bounty()
	var stars: int = GameState.stars_for(rb, thr)
	var next_needed: int = 0
	for t in thr:
		if rb < int(t):
			next_needed = int(t) - rb
			break
	var lvl: int = GameState.current_level if get_node_or_null("/root/GameState") else 1
	if get_node_or_null("/root/GameState"):
		GameState.record_level_result(lvl, stars, rb)
		GameState.current_level = lvl + 1
		GameState.just_won_level = lvl
	var hearts: int = GameState.hearts if get_node_or_null("/root/GameState") else 5
	var hmax: int = GameState.MAX_HEARTS if get_node_or_null("/root/GameState") else 5
	_end_modal = WIN_MODAL_SCENE.instantiate()
	get_node("UI").add_child(_end_modal)
	_end_modal.show_win(diff, rb, stars, next_needed, hearts, hmax)
	_end_modal.continue_pressed.connect(_goto_map.bind(true))
	_end_modal.replay_pressed.connect(_retry_level)
	_end_modal.map_pressed.connect(_goto_map.bind(false))
```

- [ ] **Step 4: Replace FailOverlay + move heart-spend out of _show_fail**

In `_show_fail()`, delete the heart-spend block:
```gdscript
	if get_node_or_null("/root/GameState"):
		GameState.spend_heart()
```
and replace the overlay reveal:
```gdscript
	info_label.text = "DEAD  ·  posse 0  ·  hits %d" % _hits
	if fail_label:
		fail_label.text = "DEAD\n%d hits" % _hits
	if fail_overlay:
		fail_overlay.visible = true
```
with:
```gdscript
	info_label.text = "DEAD  ·  posse 0  ·  hits %d" % _hits
	_present_fail_modal()
```
And add:
```gdscript
func _present_fail_modal() -> void:
	var hearts: int = GameState.hearts if get_node_or_null("/root/GameState") else 5
	var hmax: int = GameState.MAX_HEARTS if get_node_or_null("/root/GameState") else 5
	var regen_text: String = ""
	if get_node_or_null("/root/GameState") and GameState.has_method("regen_text"):
		regen_text = GameState.regen_text()
	_end_modal = FAIL_MODAL_SCENE.instantiate()
	get_node("UI").add_child(_end_modal)
	_end_modal.show_fail(_run_bounty(), hearts, hmax, regen_text)
	_end_modal.retry_pressed.connect(_retry_level)
	_end_modal.map_pressed.connect(_goto_map.bind(false))
```

- [ ] **Step 5: Implement the transition handlers (retry spends the heart)**

Add to `level_3d.gd`:
```gdscript
func _goto_map(_celebrate: bool) -> void:
	# just_won_level was set on win; level_select reads it to celebrate.
	get_tree().change_scene_to_file("res://scenes/level_select.tscn")

func _retry_level() -> void:
	# Retry costs a heart, charged HERE (not on death). If broke, do nothing
	# (the FailModal disables the button at 0 hearts).
	if get_node_or_null("/root/GameState"):
		if GameState.hearts <= 0:
			return
		GameState.spend_heart()
	if get_node_or_null("/root/DebugPreview") and DebugPreview.has_method("clear"):
		DebugPreview.clear()
	get_tree().reload_current_scene()
```
*(`level_select.tscn` path: confirm the actual scene path with `ls godot/scenes | grep level_select` before wiring; adjust if it differs.)*

- [ ] **Step 6: Add `GameState.regen_text()` (used by FailModal)**

In `game_state.gd`:
```gdscript
# Human-readable time until the next heart regenerates ("full in 24:31").
func regen_text() -> String:
	if hearts >= MAX_HEARTS or _last_spend_unix == 0:
		return "full"
	var elapsed: int = int(Time.get_unix_time_from_system()) - _last_spend_unix
	var remain: int = int(REGEN_INTERVAL_S) - (elapsed % int(REGEN_INTERVAL_S))
	return "full in %d:%02d" % [remain / 60, remain % 60]
```

- [ ] **Step 7: Verify parse + screenshot the modals**

Run the full GUT suite — expect `All tests passed!`. Then screenshot-verify the win modal using the temporary force-state debug hook pattern (sp1-screenshot does not tick `_process`): add a temporary block in `level_3d._ready()` guarded by a `_DEBUG_WIN_PREVIEW` const that calls `_present_win_modal()` deferred, screenshot `res://scenes/level_3d.tscn`, Read the PNG to confirm layout (dish, breathing candies, score, hearts, buttons), then REMOVE the temporary block. Repeat for fail.

- [ ] **Step 8: Commit**

```bash
cd /home/projects/Not_This_Again
git add godot/scripts/level_3d.gd godot/scripts/game_state.gd
git commit -m "winflow: wire Win/Fail modals into level_3d (retry spends heart, persist progress)"
```

---

## Phase 4b — Outlaw quota (objective + boss trigger)

### Task 10b: Outlaw quota tracking + boss-on-zero (level_3d)

**Files:**
- Modify: `godot/scripts/level_3d.gd`

Spec §6a: the per-level `outlaw_quota` becomes the objective; reaching 0 remaining triggers the boss, replacing the distance/timer trigger when `outlaw_quota > 0`.

- [ ] **Step 1: Add the counters + getter**

Near the other `_level_*` vars in `level_3d.gd`:
```gdscript
var _outlaws_remaining: int = 0   # ticks down as outlaws leave the field; 0 -> boss
var _outlaws_spawned: int = 0     # stop spawning once this reaches the quota
```
In `_ready()`, after `_level_def` is loaded:
```gdscript
	if _level_def != null and _level_def.outlaw_quota > 0:
		_outlaws_remaining = _level_def.outlaw_quota
```
Add a getter the HUD reads:
```gdscript
func outlaws_remaining() -> int:
	return _outlaws_remaining
```

- [ ] **Step 2: Gate outlaw spawning to the quota**

Find the outlaw spawner (`grep -n "func _spawn_outlaw\|outlaw spawn #\|_outlaw_spawn_timer" godot/scripts/level_3d.gd`). At the top of the spawn function (or where the timer decides to spawn), add the cap:
```gdscript
	if _level_def != null and _level_def.outlaw_quota > 0 and _outlaws_spawned >= _level_def.outlaw_quota:
		return   # quota fully emitted — no more outlaws
```
Immediately after a real outlaw node is created, `_outlaws_spawned += 1`.

- [ ] **Step 3: Decrement remaining when an outlaw leaves the field**

Add a single chokepoint so both defeat and escape decrement exactly once:
```gdscript
func _outlaw_left_field() -> void:
	if _level_def == null or _level_def.outlaw_quota <= 0:
		return
	_outlaws_remaining = maxi(0, _outlaws_remaining - 1)
	_set_outlaws_label(_outlaws_remaining)   # updates the taffy number + bump (Task 11)
	if _outlaws_remaining == 0:
		_trigger_quota_boss()
```
Call `_outlaw_left_field()` from BOTH the outlaw-defeated path (where an outlaw is killed/removed) and the outlaw-despawn-past path (where an un-defeated outlaw is `queue_free()`d for leaving the screen). Use a per-outlaw `set_meta("counted", true)` guard so an outlaw that is both killed and then freed only decrements once:
```gdscript
	if not outlaw.get_meta("counted", false):
		outlaw.set_meta("counted", true)
		_outlaw_left_field()
```

- [ ] **Step 4: Trigger the boss at zero; gate the legacy triggers**

Add:
```gdscript
func _trigger_quota_boss() -> void:
	if _pete_spawned or _test_range_mode:
		return
	_pete_spawned = true
	if _boss_kind() == "rustler":
		_spawn_candy_rustler()
	else:
		_spawn_pete()
	for _g in gates_root.get_children():
		_g.queue_free()
	_level_state = LevelState.BOSS
	DebugLog.add("quota cleared -> boss (kind=%s)" % _boss_kind())
```
Gate the existing triggers so they do not double-fire when a quota is in use. In the data-event `BOSS` handler (Task: spawns boss from data) and the `PETE_SPAWN_DELAY` timer block, add to each guard:
```gdscript
	# Skip the legacy timing trigger when this level is quota-driven.
	var _quota_driven: bool = _level_def != null and _level_def.outlaw_quota > 0
```
and add `and not _quota_driven` to both `if` conditions (the distance data-BOSS fire and the `PETE_SPAWN_DELAY` fire). The data event may still set which boss via `_boss_kind()`; only the *timing* is quota-driven.

- [ ] **Step 5: Verify (device-dependent)**

Run full GUT — `All tests passed!` (parse + no regression). The countdown→boss is motion/gameplay; verify on the Task 15 device pass that the number ticks down per kill and the boss appears at 0. For a quick local sanity check, add a temporary `DebugLog` line in `_outlaw_left_field()` printing `_outlaws_remaining`, sideload, watch the log, then remove it.

- [ ] **Step 6: Commit**

```bash
cd /home/projects/Not_This_Again
git add godot/scripts/level_3d.gd
git commit -m "winflow: outlaw quota countdown drives the boss trigger"
```

---

## Phase 5 — In-level hearts cutout

### Task 11: Move hearts to the top-left taffy cutout; remove Quake-bar hearts

**Files:**
- Modify: `godot/scenes/level_3d.tscn`, `godot/scripts/level_3d.gd`

- [ ] **Step 1: Find the current Quake-bar / HeartsLabel hearts**

Run: `grep -n "hearts_label\|HeartsLabel\|HeartRow\|_build_quake_bar\|hearts" godot/scripts/level_3d.gd | head`. Identify where hearts are drawn on the Quake bar and where `$UI/HeartsLabel` is updated.

- [ ] **Step 2: Add the taffy cutout + HeartCookieRow to the HUD**

In `godot/scenes/level_3d.tscn`, under the `UI` CanvasLayer, add a top-left `TextureRect` named `HeartsCutout` (texture = `res://assets/sprites/ui/winflow/cutout_taffy.png`, anchored top-left, e.g. position ~ (12, 12), size ~ (300, 150)), and inside it an instance of `heart_cookie_row.tscn` named `HeartCookieRow` positioned over the taffy's flat centre panel.

Also add, inside `HeartsCutout`, a `Label` named `OutlawNumber` for the large outlaws-remaining count — big bold candy font, centred in the upper part of the taffy panel; the `HeartCookieRow` becomes a smaller row beneath it. Both must sit within the flat centre panel (next step).

**Fit the hearts to the taffy's centre panel (not its bounding box).** The taffy sprite's twist-ended ends are decorative; the cookies must sit only within the flat caramel panel in the middle, or they spill onto the wrapper. Measure the panel's inner rect once (a quick Python pass over `cutout_taffy.png`: the panel is the large smooth caramel region — find its bounding box the way the dish-lip trace sampled colour), then inset `HeartCookieRow`'s position+size to that rect (expect roughly the central ~62% width × ~46% height; confirm by measuring). Verify in the Step 5 screenshot that all cookies land inside the panel with margin.

- [ ] **Step 3: Repoint the hearts update to the new row**

In `level_3d.gd`, change the `@onready var hearts_label: HeartRow = $UI/HeartsLabel` to:
```gdscript
@onready var hearts_label: HeartCookieRow = $UI/HeartsCutout/HeartCookieRow
```
Find every `hearts_label.set_hearts(...)` call — they keep working unchanged (same `set_hearts(current, max)` contract). Ensure hearts are refreshed on `_ready` and whenever they change (connect to `GameState.hearts_changed` if not already).

Add the outlaw-number wiring:
```gdscript
@onready var _hud_outlaws: Label = $UI/HeartsCutout/OutlawNumber

# Set the taffy's outlaws-remaining number with a small bump on change.
func _set_outlaws_label(n: int) -> void:
	if _hud_outlaws == null:
		return
	_hud_outlaws.text = str(n)
	_hud_outlaws.pivot_offset = _hud_outlaws.size * 0.5
	var t := _hud_outlaws.create_tween()
	t.tween_property(_hud_outlaws, "scale", Vector2(1.25, 1.25), 0.08)
	t.tween_property(_hud_outlaws, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_BACK)
```
In `_ready()` (after `_outlaws_remaining` is initialised in Task 10b), seed the label without the bump:
```gdscript
	if _hud_outlaws != null:
		_hud_outlaws.text = str(_outlaws_remaining)
```

- [ ] **Step 4: Remove the Quake-bar hearts**

In `_build_quake_bar` (and anywhere the Quake bar drew/added hearts), remove the heart drawing/label so lives appear ONLY in the top-left cutout. Leave the rest of the Quake bar intact.

- [ ] **Step 5: Verify + screenshot**

Run the full GUT suite — `All tests passed!`. Then `sp1-screenshot` `res://scenes/level_3d.tscn` and Read the PNG: confirm the taffy cutout with heart cookies sits top-left and the Quake bar no longer shows hearts.

- [ ] **Step 6: Commit**

```bash
cd /home/projects/Not_This_Again
git add godot/scenes/level_3d.tscn godot/scripts/level_3d.gd
git commit -m "winflow: in-level hearts move to top-left taffy cutout, off the Quake bar"
```

---

## Phase 6 — Map celebration + per-orb stars

### Task 12: Celebration walk on returning from a win

**Files:**
- Modify: `godot/scripts/level_select.gd`

- [ ] **Step 1: Read the existing focus/walk + orb code**

Run: `grep -n "_focus_level\|_cowboy_s\|_set_cowboy_s\|_set_focus_s\|ORB_START_S\|ORB_GAP_S\|_build_orb_visuals\|_place_cowboy\|func _ready" godot/scripts/level_select.gd`. Confirm `_focus_level = current_level - 1`, the orb glow on the focus orb, and `_set_cowboy_s`.

- [ ] **Step 2: Add the celebration in `_ready`**

In `level_select.gd._ready()`, after the existing `_focus_on(_focus_level)` call, add:
```gdscript
	_maybe_celebrate_win()
```
And implement:
```gdscript
# Win/retry flow: if we just won a level, start the cowboy on the completed
# orb, light the newly-unlocked orb with gold dust, and walk him to it.
func _maybe_celebrate_win() -> void:
	if get_node_or_null("/root/GameState") == null: return
	var won: int = GameState.just_won_level
	GameState.just_won_level = 0
	if won <= 0: return
	var from_idx: int = clampi(won - 1, 0, ORB_COUNT - 1)        # completed orb
	var to_idx: int = clampi(won, 0, ORB_COUNT - 1)              # newly unlocked
	if to_idx == from_idx: return
	_walking = true
	_set_cowboy_s(ORB_START_S + float(from_idx) * ORB_GAP_S)
	_focus_on(from_idx)
	_gold_dust_on_orb(to_idx)
	var target_s: float = ORB_START_S + float(to_idx) * ORB_GAP_S
	var dur: float = clampf(absf(target_s - _cowboy_s) / 12.0, 0.5, 2.0)
	var walk := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	walk.tween_method(_set_cowboy_s, _cowboy_s, target_s, dur)
	await walk.finished
	_walking = false
```

- [ ] **Step 3: Implement the gold-dust burst**

Add (reusing the orb breathe/glow already present — set whatever flag/scale the existing code uses to mark an orb "active"; here we add a particle burst):
```gdscript
func _gold_dust_on_orb(idx: int) -> void:
	if idx >= _orb_local_centers.size(): return
	var p := CPUParticles2D.new()
	p.position = _orb_screen_center(idx)   # use existing orb->screen helper; adjust name
	p.amount = 40
	p.lifetime = 1.2
	p.one_shot = true
	p.explosiveness = 0.85
	p.emitting = true
	p.color = Color(1.0, 0.85, 0.35, 1.0)
	p.initial_velocity_min = 80.0
	p.initial_velocity_max = 220.0
	p.scale_amount_min = 2.0
	p.scale_amount_max = 5.0
	add_child(p)
	if get_node_or_null("/root/AudioBus"):
		AudioBus.play_sfx("bonus_pickup")
	get_tree().create_timer(1.5).timeout.connect(p.queue_free)
```
*(Confirm the actual orb→screen-position helper name when reading the file in Step 1; replace `_orb_screen_center` with the real one. If none exists, project `_orb_local_centers[idx]` the same way the orb sprites are placed.)*

- [ ] **Step 4: Verify + screenshot mid-celebration**

Run full GUT — `All tests passed!`. Then screenshot the map with a temporary `_DEBUG_CELEBRATE` hook that sets `GameState.just_won_level = 1` before `_ready` (or call `_gold_dust_on_orb(1)` directly), capture `res://scenes/level_select.tscn`, Read the PNG to confirm the gold dust + lit orb. Remove the temporary hook.

- [ ] **Step 5: Commit**

```bash
cd /home/projects/Not_This_Again
git add godot/scripts/level_select.gd
git commit -m "winflow: level_select celebration walk + gold-dust orb on win return"
```

### Task 13: Per-orb best-star display

**Files:**
- Modify: `godot/scripts/level_select.gd`

- [ ] **Step 1: Add a StarRating under each completed orb**

In `level_select.gd`, where orbs are built (`_build_orb_visuals`), for each level `lvl` that has a `GameState.level_best` entry, instance `res://scenes/ui/star_rating.tscn`, call `set_rating(difficulty_for(lvl), GameState.level_best[lvl]["stars"], false)`, size it small (~80×54), and position it just below the orb's screen centre. Levels without a `level_best` entry get no stars.
```gdscript
func _attach_orb_stars(lvl: int, orb_center: Vector2) -> void:
	if get_node_or_null("/root/GameState") == null: return
	if not GameState.level_best.has(lvl): return
	var sr := preload("res://scenes/ui/star_rating.tscn").instantiate()
	add_child(sr)
	sr.custom_minimum_size = Vector2(84, 56)
	sr.size = Vector2(84, 56)
	sr.position = orb_center + Vector2(-42, 26)
	sr.set_rating(_orb_difficulty(lvl), int(GameState.level_best[lvl].get("stars", 0)), false)

func _orb_difficulty(lvl: int) -> int:
	# Levels 1..4 map difficulty 1..4; beyond that, cycle.
	return ((lvl - 1) % 4) + 1
```
Call `_attach_orb_stars(lvl, <orb screen centre>)` from the orb-building loop using the same centre the orb sprite uses.

- [ ] **Step 2: Verify + screenshot**

Run full GUT — `All tests passed!`. Screenshot the map with a temporary hook that seeds `GameState.level_best = {1: {"stars": 2, "bounty": 1800}}` before `_ready`; confirm the 2-star boat under level 1's orb. Remove the hook.

- [ ] **Step 3: Commit**

```bash
cd /home/projects/Not_This_Again
git add godot/scripts/level_select.gd
git commit -m "winflow: per-orb best-star display on the map"
```

---

## Phase 7 — Retire the old HeartRow + device pass

### Task 14: Swap main-menu splash to HeartCookieRow; retire HeartRow

**Files:**
- Modify: `godot/scenes/main_menu.tscn` (and any other scene using `HeartRow`), `godot/scripts/main_menu.gd` if needed

- [ ] **Step 1: Find HeartRow usages**

Run: `grep -rln "HeartRow\|heart_row" godot/scenes godot/scripts`. For each scene that uses the old `HeartRow` (notably the main-menu splash), swap the node to an instance of `heart_cookie_row.tscn` (same `set_hearts` calls keep working).

- [ ] **Step 2: Update the references**

In `main_menu.gd` (and others), change any `: HeartRow` typed `@onready` to `: HeartCookieRow` and ensure the node path points at the new instance. Leave `set_hearts(current, max)` calls unchanged.

- [ ] **Step 3: Verify + screenshot**

Run full GUT — `All tests passed!`. `sp1-screenshot` `res://scenes/main_menu.tscn`; confirm heart cookies show on the splash.

- [ ] **Step 4: Delete the obsolete HeartRow (only if no remaining references)**

Run `grep -rln "HeartRow\|heart_row" godot` again; if nothing references it, `git rm godot/scripts/heart_row.gd godot/scripts/heart_row.gd.uid`. If anything still references it, leave it and note why.

- [ ] **Step 5: Commit**

```bash
cd /home/projects/Not_This_Again
git add -A
git commit -m "winflow: swap splash to HeartCookieRow, retire HeartRow"
```

### Task 15: Device pass (sideload + verify motion)

**Files:** none (verification only)

- [ ] **Step 1: Build + distribute**

Commit any pending work, push, then build + distribute the same way other iters do:
```bash
cd /home/projects/Not_This_Again
git push origin main
scripts/sideload.sh <iterN> && scripts/firebase_distribute.sh /tmp/nta_sideload/nta_iter<N>.apk "winflow: win/fail modals, candy stars, heart cookies, map celebration"
```

- [ ] **Step 2: Verify on device (manual)**

Confirm: win modal bounce-in + star reveal + bounty count-up; fail modal; RETRY spends a heart (cookie chomp) and reloads; lives show in the top-left taffy cutout, dancing at 2+ and lonely at 1; a regenerated heart pops + cheers; CONTINUE returns to the map where the next orb gold-dusts/lights and the cowboy walks to it; completed orbs show their star count; progress survives an app restart.

---

## Self-Review

**Spec coverage:**
- §2 StarRating → Tasks 1, 6, (used in 8, 13). ✓
- §3 HeartCookieRow + dancing/lonely/regen + placement → Tasks 7, 11, 14. ✓
- §4 Win modal (bounce-in, reveal, count-up, persistence, current_level++) → Tasks 8, 10. ✓
- §5 Fail modal (retry-costs-heart-on-press, spend moved out of `_show_fail`, 0-hearts disable) → Tasks 9, 10. ✓
- §6 Data + persistence (star_thresholds, current_level, level_best, just_won_level) → Tasks 3, 4, 5. ✓
- §6a Outlaw quota + boss trigger + taffy number → Tasks 3, 10b, 11. ✓
- §7 Map celebration + per-orb stars → Tasks 12, 13. ✓
- §8 Assets (green-key pipeline, regen cheer SFX) → Tasks 1, 2. ✓
- §9 Verification (GUT/screenshot/device) → present in each task + Task 15. ✓

**Placeholder scan:** Two tasks (8, 9 scene authoring; 11/12/13 scene-node placement) describe `.tscn` construction in prose rather than full file dumps, because the exact node layout depends on reading the current `level_3d.tscn`/`level_select.tscn` — each names the required node names + textures + signal connections precisely. The `_orb_screen_center`/`level_select.tscn` path notes flag the one-line lookups to confirm while reading those files. No "TBD/handle edge cases" placeholders.

**Type consistency:** `set_hearts(current, maximum)` (HeartRow→HeartCookieRow) preserved everywhere. `set_rating(difficulty, earned, animate)` consistent across StarRating callers (Tasks 6/8/13). `stars_for(run_bounty, thresholds)` consistent (Tasks 4/10). `record_level_result(level, stars, run_bounty)` consistent (Tasks 5/10). `just_won_level` set in Task 10, read+cleared in Task 12. Modal signal names (`continue_pressed/replay_pressed/map_pressed/retry_pressed/map_pressed`) consistent between Tasks 8/9 and the connects in Task 10.
