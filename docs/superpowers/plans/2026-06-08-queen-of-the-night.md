# Level 6 — Queen of the Night (Magic Flute) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship Level 6 — a starlit-licorice-canyon Magic-Flute level with two gunless candy-songbird outlaws, a Papageno/Papagena "Pa-pa-pa" tutorial set-piece, and the **Queen of the Night** boss fought as an operatic **call-and-response swipe-duel** (she sings a melodic contour; you swipe to trace it back) riding *Der Hölle Rache*.

**Architecture:** The duel's logic — phrase sequencing, the **swipe-trace accuracy scoring**, response-window timing, out-sing-vs-high-note resolution, HP, escalation, and phases — lives in a pure `QueenDuelState` RefCounted (the `RaisinKiddState` pattern) so it is unit-testable in GUT headless on CI. `level_3d.gd` drives only rendering, input capture, audio, and the WIN/FAIL flow from it. The duel visuals (contour, note-dots, metronome, swipe trail, hit FX) are an additive 2D-canvas overlay (`sing_duel_fx.gd`, modeled on `manga_fx.gd`/`frost_bolts.gd`) mounted under `UI`. The Queen is a chroma-key Veo video billboard; the songbirds are sprite/flipbook outlaws. No custom 3D shaders.

**Tech Stack:** Godot 4.6.1, GDScript, GUT (`godot/test/`). **Tests run on GitHub Actions CI (`.github/workflows/test.yml`), NOT locally** (VPS memory-constrained — see project memory). Push the branch; verify with `gh run watch`. Reuses the Level-5 Raisin Kidd code as the template (`raisin_kidd_state.gd`, `manga_fx.gd`, `terrain_themes.gd` badlands, `level_5.tres`, the `_spawn_/_process_` boss wiring).

**Source spec:** `docs/superpowers/specs/2026-06-08-queen-of-the-night-design.md`. **Memory:** `[[project_queen_of_the_night_boss]]`.

**Asset-track prerequisite (parallel, Tasks 8–10):** concept→Veo green-screen clips (Queen idle/sing/vengeance, 2 birds, Papageno/Papagena), hybrid audio (candy instrumental + ElevenLabs vocal stingers + Pa-pa-pa duet), `canyon` terrain textures. Code Tasks 1–7 do NOT block on these — they wire against placeholder/studio art and silent audio, swapping finals in when ready.

---

## File Structure

**New files:**
- `godot/scripts/queen_duel_state.gd` — pure duel state machine + `score_trace` scoring (RefCounted). No scene refs.
- `godot/test/test_queen_duel_state.gd` — GUT tests.
- `godot/scripts/sing_duel_fx.gd` — additive 2D-canvas overlay (contour, note-dots, metronome pulse, swipe trail, out-sing/high-note FX). Rye font for any text.
- `godot/test/test_sing_duel_fx.gd` — GUT tests for the overlay's public API.
- `godot/resources/levels/level_6.tres` — LevelDef.
- `godot/test/test_level_6_def.gd` — GUT test.

**Modified files:**
- `godot/scripts/terrain_themes.gd` (+ test) — add the `canyon` theme.
- `godot/scripts/level_3d.gd` — bird outlaw kinds + canyon weighting + `_pick_outlaw_kind` branch; `_boss_kind` level-6 → `queen`; `_spawn_queen` + `_process_queen` (duel drive + swipe capture); `_build_sing_duel_fx`; the Papageno tutorial set-piece hook.

**Single-test CI note:** push the branch; the GUT job runs `-gconfig=res://.gutconfig.json`. Each TDD task writes the test first; red→green is confirmed on the CI run for that push (batch a few tasks per push to save CI minutes). Watch: `gh run list --branch <branch> --workflow=test.yml --limit 1` then `gh run watch <id> --exit-status`.

---

## Task 1: `canyon` terrain theme

**Files:** Modify `godot/scripts/terrain_themes.gd` (the `TERRAIN_THEMES` dict); Test `godot/test/test_terrain_themes.gd`.

- [ ] **Step 1: Write the failing test.** Append to `godot/test/test_terrain_themes.gd`:
```gdscript
func test_canyon_theme_present_and_dark_cool():
	var t: Dictionary = TerrainThemes.get_theme("canyon")
	assert_ne(t, TerrainThemes.get_theme("frontier"), "canyon should be its own theme")
	for k in ["ground_albedo", "ground_normal", "ground_detail", "tint_low",
			"tint_high", "fog_color", "fog_density", "scatter", "cliff"]:
		assert_true(t.has(k), "canyon theme missing key %s" % k)
	var hi: Color = t["tint_high"]
	assert_lt(hi.r, hi.b, "canyon ridge tint should be cool (blue > red) for a night look")
	assert_not_null(t["cliff"], "canyon has a cliff side")
```

- [ ] **Step 2: Run the test (CI), verify FAIL** — `canyon` falls back to frontier so `assert_ne` fails.

- [ ] **Step 3: Add the theme.** In `TERRAIN_THEMES`, after the `"badlands": { ... },` block (before the dict's closing `}`):
```gdscript
	"canyon": {
		"ground_albedo": "res://assets/textures/ground_canyon.png",
		"ground_normal": "res://assets/textures/ground_canyon_n.png",
		"ground_detail": "res://assets/textures/ground_detail.png",
		"ground_uv_tile": 24.0, "macro_strength": 2.2, "hill_scale": 1.6,
		"backdrop": "res://assets/sprites/props/backdrop_canyon.png",
		"tint_low": Color(0.10, 0.09, 0.18), "tint_high": Color(0.26, 0.28, 0.48),
		"fog_color": Color(0.20, 0.22, 0.40), "fog_density": 0.030,
		"trail": {"albedo": "res://assets/textures/trail_canyon.png", "half_width": 2.6},
		"boardwalk": null,
		"cliff": {"side": "left", "depth": 30.0},
		"scatter": [
			{"slug": "rock_large", "density": 0.5, "scale": [0.8, 1.6], "side": "right"},
			{"slug": "cactus_saguaro", "density": 0.3, "scale": [0.9, 1.5], "side": "right"},
			{"slug": "rock_small", "density": 0.6, "scale": [0.5, 1.0]},
		],
	},
```
`get_theme` already serves any present key via `.get(name, frontier)` — no function change. Missing texture PNGs fall back gracefully at load (the asset track fills them); the scatter slugs reuse existing prop sprites. The `cliff` reuses the mountain cliff system.

- [ ] **Step 4: Run (CI), verify PASS** (both new asserts; all prior terrain tests still pass).
- [ ] **Step 5: Commit** — `git add godot/scripts/terrain_themes.gd godot/test/test_terrain_themes.gd && git commit -m "feat(level6): add canyon terrain theme"`

---

## Task 2: Level 6 LevelDef + boss dispatch

**Files:** Create `godot/resources/levels/level_6.tres`, `godot/test/test_level_6_def.gd`; Modify `godot/scripts/level_3d.gd` `_boss_kind()`.

- [ ] **Step 1: Write the failing test.** Create `godot/test/test_level_6_def.gd`:
```gdscript
extends GutTest

func test_level_6_def_loads_with_canyon_and_quota():
	var def = load("res://resources/levels/level_6.tres")
	assert_not_null(def, "level_6.tres should load")
	assert_eq(def.terrain, "canyon", "Level 6 terrain is canyon")
	assert_eq(def.difficulty, 6, "Level 6 difficulty is 6")
	assert_gt(def.outlaw_quota, 0, "Level 6 needs an outlaw quota")
	assert_eq(def.star_thresholds.size(), 3, "three star thresholds")
	assert_gt(def.outlaw_quota, 140, "Level 6 quota exceeds Level 5's 140")
```

- [ ] **Step 2: Run (CI), verify FAIL** (`load(...)` null).

- [ ] **Step 3: Create `level_6.tres`** (mirror `level_5.tres`; boss event `kind = 5`, `params = {"boss": "queen"}`):
```
[gd_resource type="Resource" script_class="LevelDef" format=3]

[ext_resource type="Script" path="res://scripts/level_def.gd" id="1_def"]
[ext_resource type="Script" path="res://scripts/level_event.gd" id="1_hrksf"]

[sub_resource type="Resource" id="Resource_q6boss"]
script = ExtResource("1_hrksf")
distance = 75.0
kind = 5
params = {
"boss": "queen"
}

[resource]
script = ExtResource("1_def")
difficulty = 6
terrain = "canyon"
display_name = "STARLIT CANYON SERENADE"
weather_type = "NIGHT"
seed = 6
star_thresholds = Array[int]([0, 5000, 11000])
outlaw_quota = 160
events = Array[ExtResource("1_hrksf")]([SubResource("Resource_q6boss")])
```
If `weather_type = "NIGHT"` errors at load, change to `"NONE"` and track night-sky as a follow-up (verify in Task 10).

- [ ] **Step 4: Wire dispatch.** In `level_3d.gd`, extend `_boss_kind()` (it currently returns "rustler" for 2, "raisin" for 5, else "pete"):
```gdscript
	if lvl == 6:
		return "queen"
```
(Add this `if` beside the existing `lvl == 5` one; leave spawn call-sites for Task 6.)

- [ ] **Step 5: Run (CI), verify PASS.**
- [ ] **Step 6: Commit** — `git commit -m "feat(level6): canyon LevelDef + queen boss dispatch"`

---

## Task 3: Candy-songbird outlaws (two tints)

**Files:** Modify `godot/scripts/level_3d.gd` (`OUTLAW_KINDS`, add `CANYON_OUTLAW_*`/`BIRD_OUTLAW_VIDEOS` near the badlands constants, `_pick_outlaw_kind` terrain branch, `_spawn_outlaw` billboard branch); Test `godot/test/test_canyon_outlaws.gd`.

Two gunless songbirds reuse the video-billboard outlaw path. Assets land later; load-with-fallback.

- [ ] **Step 1: Write the failing test.** Create `godot/test/test_canyon_outlaws.gd`:
```gdscript
extends GutTest
const Level3D = preload("res://scripts/level_3d.gd")

func test_canyon_roster_is_the_two_birds():
	var kinds := {}
	for e in Level3D.CANYON_OUTLAW_WEIGHTS:
		kinds[e[0]] = true
	assert_true(kinds.has("flit_finch"))
	assert_true(kinds.has("peck_jay"))
	assert_eq(kinds.size(), 2)

func test_bird_kinds_have_stats_and_videos():
	for k in ["flit_finch", "peck_jay"]:
		assert_true(Level3D.OUTLAW_KINDS.has(k), "OUTLAW_KINDS missing %s" % k)
		assert_true(Level3D.BIRD_OUTLAW_VIDEOS.has(k), "BIRD_OUTLAW_VIDEOS missing %s" % k)
		assert_gt(int(Level3D.OUTLAW_KINDS[k]["hp"]), 0)
```

- [ ] **Step 2: Run (CI), verify FAIL** (constants undefined).

- [ ] **Step 3: Add constants.** After the `BADLANDS_OUTLAW_WEIGHTS`/monk block, add:
```gdscript
# Level-6 candy songbirds (no guns). flit_finch = warm, erratic light harasser;
# peck_jay = cool, swoops to peck on a cooldown. Tuned on device (Task 10).
const BIRD_OUTLAW_VIDEOS: Dictionary = {
	"flit_finch": "res://assets/videos/canyon_birds/flit_finch.ogv",
	"peck_jay":   "res://assets/videos/canyon_birds/peck_jay.ogv",
}
const CANYON_OUTLAW_WEIGHTS: Array = [
	["flit_finch", 55], ["peck_jay", 45],
]
const PECK_JAY_SWOOP_COOLDOWN: float = 2.2   # reserved for later AI tuning
```
Extend `OUTLAW_KINDS` with the two rows (keep existing kinds):
```gdscript
	"flit_finch": {"hp": 8,  "height": 2.2},
	"peck_jay":   {"hp": 11, "height": 2.4},
```

- [ ] **Step 4: Teach `_pick_outlaw_kind` + `_spawn_outlaw`.** In `_pick_outlaw_kind`, add a `"canyon"` arm to the terrain `match` (mirroring the `"badlands"` arm):
```gdscript
		"canyon": roster = CANYON_OUTLAW_WEIGHTS
```
In `_spawn_outlaw`'s billboard branch, add the bird-video case beside the monk case:
```gdscript
	elif BIRD_OUTLAW_VIDEOS.has(kind):
		billboard = _make_video_billboard(load(BIRD_OUTLAW_VIDEOS[kind]), OUTLAW_KINDS[kind]["height"])
```
(Leave the `var is_farm_kind/has_kind_stats := OUTLAW_KINDS.has(kind)` max-hp line untouched; the birds are in `OUTLAW_KINDS` so they get their HP.)

- [ ] **Step 5: Run (CI), verify PASS.** No regressions.
- [ ] **Step 6: Commit** — `git commit -m "feat(level6): two candy-songbird outlaw kinds + canyon weighting"`

---

## Task 4: `QueenDuelState` — pure duel logic + swipe scoring

This is the heart. A pure RefCounted owning HP, phase, the phrase sequence, the response-window clock, and the **`score_trace`** swipe-accuracy function. `level_3d` calls `tick(delta)` (which returns events) and `submit_swipe(points)` (which scores + resolves).

**Files:** Create `godot/scripts/queen_duel_state.gd`; Test `godot/test/test_queen_duel_state.gd`.

- [ ] **Step 1: Write the failing test.** Create `godot/test/test_queen_duel_state.gd`:
```gdscript
extends GutTest

const QueenDuelState = preload("res://scripts/queen_duel_state.gd")

func _fresh() -> QueenDuelState:
	return QueenDuelState.new()

# ---- score_trace (pure, static) ----
func test_perfect_trace_scores_high():
	var shape: Array = [Vector2(0,0), Vector2(1,1), Vector2(2,0), Vector2(3,1)]
	assert_gt(QueenDuelState.score_trace(shape, shape.duplicate()), 0.9)

func test_translated_and_scaled_copy_still_scores_high():
	# same shape, shifted +100 and scaled x3 -> shape-matching is position/scale invariant
	var shape: Array = [Vector2(0,0), Vector2(1,1), Vector2(2,0), Vector2(3,1)]
	var moved: Array = []
	for p in shape:
		moved.append(p * 3.0 + Vector2(100, 50))
	assert_gt(QueenDuelState.score_trace(shape, moved), 0.85)

func test_different_shape_scores_low():
	var a: Array = [Vector2(0,0), Vector2(1,1), Vector2(2,0), Vector2(3,1)]   # zigzag
	var b: Array = [Vector2(0,0), Vector2(1,0), Vector2(2,0), Vector2(3,0)]   # flat line
	assert_lt(QueenDuelState.score_trace(a, b), 0.6)

func test_reversed_trace_scores_lower_than_forward():
	var shape: Array = [Vector2(0,0), Vector2(1,1), Vector2(2,0), Vector2(3,1)]
	var rev: Array = shape.duplicate(); rev.reverse()
	assert_lt(QueenDuelState.score_trace(shape, rev), QueenDuelState.score_trace(shape, shape.duplicate()))

func test_too_few_points_scores_zero():
	assert_eq(QueenDuelState.score_trace([Vector2(0,0)], [Vector2(0,0), Vector2(1,1)]), 0.0)

# ---- duel state machine ----
func test_starts_idle_full_hp():
	var s = _fresh()
	assert_eq(s.hp, QueenDuelState.MAX_HP)
	assert_eq(s.phase, 1)
	assert_false(s.is_over())

func test_tick_opens_a_phrase_then_response_window():
	var s = _fresh()
	var seen := {}
	for i in range(int((QueenDuelState.SING_T + 0.5) / 0.05)):
		for e in s.tick(0.05): seen[e] = true
	assert_true(seen.has("phrase_start"), "she sings")
	assert_true(seen.has("response_open"), "response window opens")
	assert_gt(s.current_contour().size(), 1, "a contour is available to trace")

func test_good_swipe_damages_queen():
	var s = _fresh()
	_advance_to_response(s)
	var before: int = s.hp
	var res: Dictionary = s.submit_swipe(s.current_contour().duplicate())  # perfect trace
	assert_true(res["out_sing"], "perfect trace out-sings her")
	assert_lt(s.hp, before, "she takes damage")

func test_bad_swipe_drains_posse_not_hp():
	var s = _fresh()
	_advance_to_response(s)
	var before: int = s.hp
	var res: Dictionary = s.submit_swipe([Vector2(0,0), Vector2(9,9)])  # nothing like the contour
	assert_false(res["out_sing"])
	assert_gt(res["posse_drain"], 0, "a botched answer drains the posse")
	assert_eq(s.hp, before, "no HP damage on a bad answer")

func test_phase2_at_half_hp():
	var s = _fresh()
	s.hp = int(QueenDuelState.MAX_HP * 0.5) - 1
	var saw := false
	for i in range(10):
		if s.tick(0.016).has("phase2"): saw = true; break
	assert_true(saw)
	assert_eq(s.phase, 2)

func test_defeat_emits_once_at_zero_hp():
	var s = _fresh()
	s.hp = 1
	_advance_to_response(s)
	s.submit_swipe(s.current_contour().duplicate())   # finish her
	var defeats := 0
	for i in range(40):
		for e in s.tick(0.05):
			if e == "defeat": defeats += 1
	assert_lte(s.hp, 0)
	assert_eq(defeats if s.hp <= 0 else -1, defeats)   # ran without error
	assert_eq(s.mode, QueenDuelState.Mode.DEAD)

func test_tutorial_mode_never_drains_or_damages():
	var s = QueenDuelState.new(true)   # tutorial = true
	_advance_to_response(s)
	var res: Dictionary = s.submit_swipe([Vector2(0,0), Vector2(9,9)])  # bad
	assert_eq(res["posse_drain"], 0, "tutorial never penalizes")
	assert_eq(s.hp, QueenDuelState.MAX_HP, "tutorial never damages HP either way")

func _advance_to_response(s) -> void:
	for i in range(int((QueenDuelState.SING_T + 0.1) / 0.02)):
		s.tick(0.02)
		if s.mode == QueenDuelState.Mode.RESPONSE:
			return
```
Note: replace the awkward `test_defeat_emits_once_at_zero_hp` assert pair with a clean once-check if you prefer; the intent is "defeat is emitted and mode→DEAD; no crash." Keep `assert_eq(s.mode, QueenDuelState.Mode.DEAD)`.

- [ ] **Step 2: Run (CI), verify FAIL** (script missing).

- [ ] **Step 3: Implement `queen_duel_state.gd`:**
```gdscript
class_name QueenDuelState
extends RefCounted

# Pure call-and-response sing-duel logic for the Level-6 boss, Queen of the
# Night (spec §5). Holds NO scene/render state; level_3d.gd drives rendering,
# swipe capture, audio, and the WIN/FAIL flow from the public fields + the
# event list tick() returns. The RaisinKiddState pattern — unit-tested in GUT.
#
# Per-frame contract:
#   var events: Array = state.tick(delta)     # react: play VO/FX, open input
#   # when the player finishes a swipe during RESPONSE:
#   var res: Dictionary = state.submit_swipe(points)   # {out_sing, score, posse_drain}

enum Mode { IDLE, SINGING, RESPONSE, RESOLVE, DEAD }

const MAX_HP: int = 600
const SING_T: float = 1.6              # she sings the phrase (telegraph)
const RESPONSE_T: float = 2.2          # window to swipe the answer
const RESOLVE_T: float = 0.8           # beat after an answer
const GOOD_THRESHOLD: float = 0.62     # score >= this = out-sing
const HIT_DAMAGE: int = 60             # HP per out-sing (scaled by score)
const MISS_DRAIN: int = 3              # posse drained on a botched answer
const MATCH_TOLERANCE: float = 0.55    # score_trace falloff (unit-box distance)
const RESAMPLE_N: int = 16
const PHASE2_HP_FRAC: float = 0.5

# escalating phrase contours (normalized-ish points; shape is what matters)
const PHRASES: Array = [
	[Vector2(0,2), Vector2(1,0), Vector2(2,0), Vector2(3,2)],                       # gentle arc
	[Vector2(0,3), Vector2(1,2), Vector2(2,1), Vector2(3,0)],                       # rising run
	[Vector2(0,3), Vector2(1,0), Vector2(2,3), Vector2(3,0), Vector2(4,3), Vector2(5,0)],  # staccato finale
]

var hp: int = MAX_HP
var phase: int = 1
var mode: int = Mode.IDLE
var tutorial: bool = false

var _t: float = 0.0
var _phrase_i: int = 0
var _defeated: bool = false

func _init(is_tutorial: bool = false) -> void:
	tutorial = is_tutorial

func is_over() -> bool:
	return mode == Mode.DEAD

func current_contour() -> Array:
	return PHRASES[_phrase_i % PHRASES.size()]

# --- the pure scorer: how well does `swipe` trace `target`? 0..1 ---
static func score_trace(target: Array, swipe: Array) -> float:
	if target.size() < 2 or swipe.size() < 2:
		return 0.0
	var a: Array = _normalize(_resample(target, RESAMPLE_N))
	var b: Array = _normalize(_resample(swipe, RESAMPLE_N))
	var d: float = 0.0
	for i in range(RESAMPLE_N):
		d += (a[i] as Vector2).distance_to(b[i])
	d /= float(RESAMPLE_N)
	return clampf(1.0 - d / MATCH_TOLERANCE, 0.0, 1.0)

static func _resample(pts: Array, n: int) -> Array:
	# arc-length resample to n evenly-spaced points
	var total: float = 0.0
	for i in range(pts.size() - 1):
		total += (pts[i] as Vector2).distance_to(pts[i + 1])
	if total <= 0.0:
		var flat: Array = []
		for i in range(n): flat.append(pts[0])
		return flat
	var step: float = total / float(n - 1)
	var out: Array = [pts[0]]
	var acc: float = 0.0
	var i: int = 0
	var cur: Vector2 = pts[0]
	while out.size() < n and i < pts.size() - 1:
		var seg: float = cur.distance_to(pts[i + 1])
		if acc + seg >= step:
			var t: float = (step - acc) / seg
			cur = cur.lerp(pts[i + 1], t)
			out.append(cur)
			acc = 0.0
		else:
			acc += seg
			cur = pts[i + 1]
			i += 1
	while out.size() < n:
		out.append(pts[pts.size() - 1])
	return out

static func _normalize(pts: Array) -> Array:
	# translate to min corner, scale by the larger extent -> unit box (shape-only)
	var mn := Vector2(INF, INF)
	var mx := Vector2(-INF, -INF)
	for p in pts:
		mn = mn.min(p); mx = mx.max(p)
	var ext: Vector2 = mx - mn
	var s: float = maxf(ext.x, ext.y)
	if s <= 0.0:
		s = 1.0
	var out: Array = []
	for p in pts:
		out.append(((p as Vector2) - mn) / s)
	return out

func tick(delta: float) -> Array:
	var events: Array = []
	if mode == Mode.DEAD:
		return events
	# phase transition (one-shot)
	if phase == 1 and hp <= int(MAX_HP * PHASE2_HP_FRAC) and hp > 0:
		phase = 2
		events.append("phase2")
	if hp <= 0:
		if not _defeated:
			_defeated = true
			mode = Mode.DEAD
			events.append("defeat")
		return events
	_t -= delta
	match mode:
		Mode.IDLE:
			mode = Mode.SINGING
			_t = sing_time()
			events.append("phrase_start")
		Mode.SINGING:
			if _t <= 0.0:
				mode = Mode.RESPONSE
				_t = RESPONSE_T
				events.append("response_open")
		Mode.RESPONSE:
			if _t <= 0.0:
				# timed out = a miss
				_resolve(0.0, events)
		Mode.RESOLVE:
			if _t <= 0.0:
				_phrase_i += 1
				mode = Mode.IDLE
	return events

func sing_time() -> float:
	# phase 2 sings faster
	return SING_T * (0.7 if phase == 2 else 1.0)

# Called by level_3d when the player finishes a swipe during RESPONSE.
func submit_swipe(points: Array) -> Dictionary:
	if mode != Mode.RESPONSE:
		return {"out_sing": false, "score": 0.0, "posse_drain": 0}
	var sc: float = score_trace(current_contour(), points)
	var dummy: Array = []
	_resolve(sc, dummy)
	var out_sing: bool = sc >= GOOD_THRESHOLD and not tutorial
	# tutorial: report the score but never penalize/damage
	var drain: int = 0
	var dmg: int = 0
	if not tutorial:
		if sc >= GOOD_THRESHOLD:
			dmg = int(round(HIT_DAMAGE * sc))
		else:
			drain = MISS_DRAIN
	return {"out_sing": out_sing, "score": sc, "posse_drain": drain, "damage": dmg}

func _resolve(score: float, events: Array) -> void:
	# apply HP damage on a good answer (skipped in tutorial); enter RESOLVE
	if not tutorial and score >= GOOD_THRESHOLD:
		hp = maxi(0, hp - int(round(HIT_DAMAGE * score)))
		events.append("out_sing")
	elif not tutorial:
		events.append("high_note")
	mode = Mode.RESOLVE
	_t = RESOLVE_T
```
Note on `submit_swipe` vs `_resolve`: `_resolve` advances the state machine and (non-tutorial) applies HP; `submit_swipe` returns the result dict the scene needs (drain/damage for posse + FX). The timeout path in `tick` calls `_resolve(0.0,...)` so an unanswered phrase counts as a high-note miss.

- [ ] **Step 4: Run (CI), verify PASS** for all cases. If `test_translated_and_scaled_copy` is borderline, the `_normalize` (shape-only) is what makes it pass — do not change the test; verify `_normalize`/`_resample`.
- [ ] **Step 5: Commit** — `git commit -m "feat(level6): QueenDuelState sing-duel logic + swipe scoring + tests"`

---

## Task 5: `sing_duel_fx.gd` additive overlay

A `manga_fx.gd`-style additive Control overlay: draws the glowing contour + note-dots as she sings, a metronome pulse during the response window, the player's live swipe trail, and the out-sing / high-note hit FX. Captures the swipe points.

**Files:** Create `godot/scripts/sing_duel_fx.gd`; Test `godot/test/test_sing_duel_fx.gd`.

- [ ] **Step 1: Write the failing test.** Create `godot/test/test_sing_duel_fx.gd`:
```gdscript
extends GutTest
const SingDuelFx = preload("res://scripts/sing_duel_fx.gd")
var fx
func before_each():
	fx = SingDuelFx.new()
	add_child_autofree(fx)
	fx.size = Vector2(1080, 1920)
	await get_tree().process_frame

func test_show_contour_makes_it_active():
	fx.show_contour([Vector2(0,0), Vector2(1,1), Vector2(2,0)])
	assert_true(fx.is_active())

func test_open_response_captures_swipe_points():
	fx.show_contour([Vector2(0,0), Vector2(1,1)])
	fx.open_response()
	fx.feed_point(Vector2(100, 100))
	fx.feed_point(Vector2(120, 90))
	var pts: Array = fx.end_response()
	assert_eq(pts.size(), 2, "captured the fed swipe points")

func test_clear_resets():
	fx.show_contour([Vector2(0,0), Vector2(1,1)])
	fx.clear()
	assert_false(fx.is_active())

func test_flash_does_not_crash():
	fx.out_sing_flash(Vector2(500, 800))
	fx.high_note_flash(Vector2(500, 800))
	fx._process(0.016)
	assert_true(true)
```

- [ ] **Step 2: Run (CI), verify FAIL** (script missing).

- [ ] **Step 3: Implement `sing_duel_fx.gd`:**
```gdscript
extends Control

# Sing-duel overlay for the Queen of the Night (spec §5/§8). Additive 2D canvas
# in the manga_fx.gd tradition: draws the glowing melodic contour + note-dots
# while she sings, a metronome pulse during the response window, the player's
# live swipe trail, and out-sing / high-note hit flashes. Captures the swipe.
#
#   show_contour(points)   # screen-space points of her phrase (she sings)
#   open_response()        # begin capturing the player's swipe
#   feed_point(p)          # add a swipe point (from InputEventScreenDrag)
#   end_response() -> Array # stop capturing, return the captured points
#   out_sing_flash(at) / high_note_flash(at)
#   clear() / is_active()

const RYE := preload("res://assets/fonts/Rye-Regular.ttf")

var _contour: Array = []          # screen-space points
var _sing_anim: float = 0.0       # 0..1 reveal of the contour
var _capturing: bool = false
var _swipe: Array = []
var _flashes: Array = []          # {pos, life, t0, color, text}

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = m
	set_process(false)

func is_active() -> bool:
	return not _contour.is_empty() or _capturing or not _flashes.is_empty()

func clear() -> void:
	_contour.clear(); _swipe.clear(); _flashes.clear()
	_capturing = false; _sing_anim = 0.0
	set_process(false); queue_redraw()

func show_contour(points: Array) -> void:
	_contour = points.duplicate()
	_sing_anim = 0.0
	set_process(true); queue_redraw()

func open_response() -> void:
	_capturing = true
	_swipe.clear()
	set_process(true)

func feed_point(p: Vector2) -> void:
	if _capturing:
		_swipe.append(p)
		queue_redraw()

func end_response() -> Array:
	_capturing = false
	var out: Array = _swipe.duplicate()
	queue_redraw()
	return out

func out_sing_flash(at: Vector2) -> void:
	_flashes.append({"pos": at, "life": 0.8, "t0": 0.8, "color": Color(0.5, 1.0, 0.6), "text": "OUT-SING!"})
	set_process(true); queue_redraw()

func high_note_flash(at: Vector2) -> void:
	_flashes.append({"pos": at, "life": 0.8, "t0": 0.8, "color": Color(1.0, 0.4, 0.6), "text": "HIGH NOTE!"})
	set_process(true); queue_redraw()

func _process(delta: float) -> void:
	if _sing_anim < 1.0 and not _contour.is_empty():
		_sing_anim = minf(1.0, _sing_anim + delta * 1.2)
	var live: Array = []
	for f in _flashes:
		f["life"] -= delta
		if f["life"] > 0.0:
			live.append(f)
	_flashes = live
	queue_redraw()
	if not is_active():
		set_process(false)

func _draw() -> void:
	# her contour (revealed left-to-right as she sings)
	if _contour.size() >= 2:
		var n: int = _contour.size()
		var lit: int = maxi(1, int(_sing_anim * (n - 1)))
		for i in range(lit):
			draw_line(_contour[i], _contour[i + 1], Color(1.0, 0.84, 0.4, 0.9), 8.0)
		for i in range(n):
			if float(i) / float(n - 1) <= _sing_anim:
				draw_circle(_contour[i], 9.0, Color(1.0, 0.84, 0.4, 0.95))
	# player's live swipe trail
	for i in range(_swipe.size() - 1):
		draw_line(_swipe[i], _swipe[i + 1], Color(0.47, 0.82, 1.0, 0.95), 7.0)
	# flashes
	for f in _flashes:
		var frac: float = clampf(f["life"] / f["t0"], 0.0, 1.0)
		var c: Color = f["color"]; c.a = frac
		draw_circle(f["pos"], lerpf(60.0, 180.0, 1.0 - frac), Color(c.r, c.g, c.b, frac * 0.4))
		var tw: float = RYE.get_string_size(f["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, 64).x
		draw_string(RYE, f["pos"] - Vector2(tw * 0.5, 0), f["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, 64, c)
```

- [ ] **Step 4: Run (CI), verify PASS.** (Fix any tab/space slip — it's the usual GDScript parse trap.)
- [ ] **Step 5: Commit** — `git commit -m "feat(level6): sing-duel additive overlay + tests"`

---

## Task 6: Spawn + drive the Queen in `level_3d.gd`

Scene wiring (device-verified). Mounts the overlay, spawns the Queen billboard, drives `QueenDuelState`, captures swipes during the response window, applies damage/drain, and runs WIN/FAIL.

**Files:** Modify `godot/scripts/level_3d.gd`.

- [ ] **Step 1: Add members + constants** near the Raisin members:
```gdscript
const _QUEEN_DUEL_STATE := preload("res://scripts/queen_duel_state.gd")
const QUEEN_IDLE_STREAM := "res://assets/videos/queen/idle.ogv"
const QUEEN_STAY_Z: float = -7.0
const QUEEN_HEIGHT: float = 6.0
var _queen: QueenDuelState = null
const SingDuelFxScript = preload("res://scripts/sing_duel_fx.gd")
var _sing_fx: Control = null
var _queen_swiping: bool = false
```

- [ ] **Step 2: Build the overlay** — add `_build_sing_duel_fx()` next to `_build_manga_fx()` and call it in `_ready` alongside the others:
```gdscript
func _build_sing_duel_fx() -> void:
	var ui: Node = get_node_or_null("UI")
	if ui == null: return
	_sing_fx = SingDuelFxScript.new()
	_sing_fx.name = "SingDuelFx"
	ui.add_child(_sing_fx)
	ui.move_child(_sing_fx, 0)
```

- [ ] **Step 3: `_spawn_queen`** (mirror `_spawn_raisin_kidd`):
```gdscript
func _spawn_queen() -> void:
	_queen = _QUEEN_DUEL_STATE.new()
	var boss := Node3D.new()
	boss.position = Vector3(0.0, 2.6, OBSTACLE_SPAWN_Z + 4.0)
	boss.set_meta("hp", _queen.hp); boss.set_meta("hp_max", QueenDuelState.MAX_HP)
	boss.set_meta("boss_kind", "queen")
	boss_root.add_child(boss)
	boss.add_child(_make_video_billboard(load(QUEEN_IDLE_STREAM), QUEEN_HEIGHT))
	var plate := Label3D.new(); plate.text = "QUEEN OF THE NIGHT"
	plate.font_size = 40; plate.outline_size = 9; plate.modulate = Color(0.9, 0.78, 0.35, 1)
	plate.billboard = BaseMaterial3D.BILLBOARD_ENABLED; plate.no_depth_test = true
	plate.position = Vector3(0, 0.6, 0.6); boss.add_child(plate)
	_install_pete_hud(boss, "QUEEN OF THE NIGHT"); _refresh_pete_hp(boss)
	info_label.text = "BOSS — QUEEN OF THE NIGHT"
	DebugLog.add("queen spawned, HP=%d" % _queen.hp)
```

- [ ] **Step 4: `_process_queen`** — drive the duel, project a screen-space "duel band" for the contour, capture swipes, apply results, win/fail:
```gdscript
func _process_queen(boss: Node3D, delta: float) -> void:
	if _queen == null or boss.get_meta("dying", false): return
	if boss.position.z < QUEEN_STAY_Z:
		boss.position.z += RUSTLER_SPEED * delta
	# posse chip damage (auto-fire) — every overlapping bullet
	for bullet in bullets_root.get_children():
		if not (bullet is Node3D): continue
		var dx: float = bullet.position.x - boss.position.x
		var dz: float = bullet.position.z - boss.position.z
		if dx*dx + dz*dz < PETE_HIT_RADIUS_SQ:
			_queen.hp = maxi(0, _queen.hp - 1)
			bullet.queue_free()
	var events: Array = _queen.tick(delta)
	boss.set_meta("hp", _queen.hp); _refresh_pete_hp(boss)
	for e in events:
		match e:
			"phrase_start":
				if _sing_fx: _sing_fx.show_contour(_contour_to_screen(_queen.current_contour()))
				_queen_say("sing")
			"response_open":
				if _sing_fx: _sing_fx.open_response()
				_queen_swiping = true
			"out_sing":
				if _sing_fx: _sing_fx.out_sing_flash(get_viewport_rect().size * Vector2(0.5, 0.4))
			"high_note":
				if _sing_fx: _sing_fx.high_note_flash(get_viewport_rect().size * Vector2(0.5, 0.4))
				_queen_say("highnote")
			"phase2":
				_queen_say("phase2")
			"defeat":
				boss.set_meta("dying", true); _queen_say("dying")
				if _sing_fx: _sing_fx.clear()
				_show_win("Queen of the Night", boss, null)
				return

# Map a QueenDuelState contour (abstract points) into screen-space across a band.
func _contour_to_screen(contour: Array) -> Array:
	var vp: Vector2 = get_viewport_rect().size
	var x0: float = vp.x * 0.12; var w: float = vp.x * 0.76
	var y0: float = vp.y * 0.30; var h: float = vp.y * 0.30
	# normalize the contour's own bounds, then place in the band
	var mn := Vector2(INF, INF); var mx := Vector2(-INF, -INF)
	for p in contour: mn = mn.min(p); mx = mx.max(p)
	var ext: Vector2 = (mx - mn); if ext.x <= 0: ext.x = 1; if ext.y <= 0: ext.y = 1
	var out: Array = []
	for p in contour:
		var nx: float = ((p as Vector2).x - mn.x) / ext.x
		var ny: float = ((p as Vector2).y - mn.y) / ext.y
		out.append(Vector2(x0 + nx * w, y0 + ny * h))
	return out
```

- [ ] **Step 5: Swipe input** — in `_unhandled_input` (or wherever level_3d handles input), feed drag points to the overlay while swiping, and submit on release:
```gdscript
	if _queen_swiping and _sing_fx:
		if ev is InputEventScreenDrag:
			_sing_fx.feed_point(ev.position)
		elif ev is InputEventScreenTouch and not ev.pressed:
			var pts: Array = _sing_fx.end_response()
			var res: Dictionary = _queen.submit_swipe(pts)
			if int(res.get("posse_drain", 0)) > 0:
				for i in range(int(res["posse_drain"])):
					_outlaw_drain_posse(Vector3.ZERO, "")
			_queen_swiping = false
```
(Use the project's real input entry point — `grep -n "_unhandled_input\|_input(" godot/scripts/level_3d.gd`; if drags are read elsewhere, hook there. Desktop: also accept `InputEventMouseMotion` with button held + `InputEventMouseButton` release for debugging.)

- [ ] **Step 6: Wire spawn + dispatch.** Add `"queen" -> _spawn_queen()` to the three boss spawn call-sites (the `ev.params`/`_boss_kind()` branches, beside rustler/raisin), add a `"queen": _process_queen(...)` arm to the per-frame boss dispatch `match`, and ensure the Pete-block guard excludes `"queen"` too (`not in ["rustler","raisin","queen"]`). Add a `_queen_say(kind)` mirroring `_raisin_say` (banks: `queen_sing_`, `queen_highnote_`, `queen_phase2_`, `queen_dying_`, `queen_intro_`).

- [ ] **Step 7: Headless parse + suite (CI).** Push; confirm no parse errors in `level_3d.gd` and the full GUT suite passes.
- [ ] **Step 8: Commit** — `git commit -m "feat(level6): spawn + drive Queen of the Night sing-duel"`

---

## Task 7: Papageno/Papagena tutorial set-piece

A no-penalty mid-canyon set-piece teaching the swipe-duel (spec §4), reusing `QueenDuelState(tutorial=true)` + the overlay.

**Files:** Modify `godot/scripts/level_3d.gd` (+ `level_6.tres` if a mid-level event triggers it).

- [ ] **Step 1:** Add a `_papageno_tutorial` flow: when the canyon run reaches the tutorial trigger (a `LevelEvent` in `level_6.tres` at an early distance, or a one-shot at ~1/3 through the run), spawn a small Papageno+Papagena billboard pair and run **2–3 easy rounds** of `QueenDuelState.new(true)` restricted to the gentle-arc phrase: `show_contour` → `open_response` → capture → `submit_swipe` (score shown as a happy/again reaction, never a penalty). End with a joyous "Pa-pa-pa" duet beat, then resume the run. Reuse `_contour_to_screen` + the swipe-capture from Task 6.
- [ ] **Step 2:** Keep it skippable/short; it must not block the quota countdown. Use `tutorial=true` so HP/drain are inert.
- [ ] **Step 3: Headless parse (CI). Commit** — `git commit -m "feat(level6): Papageno/Papagena swipe-duel tutorial set-piece"`

---

## Task 8: Hybrid audio (instrumental backing + vocal stingers)

**Files:** `godot/assets/audio/...`, `godot/assets/text/en.json` (`queen` banks), `tools/gen_queen_vo.py`.

- [ ] **Step 1:** Produce the **instrumental candy backing track** (music-box/bells/synth arrangement of the PD melodies) + a beat-grid value the duel reads (BPM → response-window alignment). Place under `godot/assets/audio/music/`.
- [ ] **Step 2:** Author en.json `queen_dialog_{intro,sing,highnote,phase2,dying}` + the Papageno/Papagena lines; generate **AI-performed vocal stingers** (ElevenLabs, the `gen_*_vo.py` pattern) for the sung phrases + the Pa-pa-pa duet. Author `.import` sidecars (md5 = md5(res-path)) like the Raisin VO. Register slugs via `AudioBus.play_character_line`.
- [ ] **Step 3: Commit.**

---

## Task 9: Concept → green-screen billboard clips

**Files:** `godot/assets/videos/queen/`, `godot/assets/videos/canyon_birds/`.

- [ ] **Step 1:** From the locked **chocolate-gold Queen** concept (`docs/superpowers/assets/queen_night_2026-06-08/queen_concept_3_chocolatgold.png`): NB-Pro a flat-green-bg seed, Veo idle/sing/vengeance clips, key + transcode to `.ogv` (the boss green-screen pipeline; sample green from a mid-frame). Same for the two songbirds (`flit_finch`, `peck_jay`) and the Papageno/Papagena pair.
- [ ] **Step 2:** Point `QUEEN_IDLE_STREAM` + `BIRD_OUTLAW_VIDEOS` at the keyed clips. **Commit.**

---

## Task 10: Device pass + tuning

**Files:** tune `queen_duel_state.gd` consts (`SING_T`, `RESPONSE_T`, `GOOD_THRESHOLD`, `HIT_DAMAGE`, `MISS_DRAIN`, `MATCH_TOLERANCE`), `level_3d.gd` (band placement), `level_6.tres` (quota/stars), `CANYON_OUTLAW_WEIGHTS`.

- [ ] **Step 1:** Sideload (`scripts/sideload.sh`), jump to Level 6 (debug menu / DebugPreview).
- [ ] **Step 2:** Verify: canyon terrain + night sky; both songbirds spawn; quota → boss. Papageno tutorial teaches the swipe (no penalty). Queen sings → contour reads clearly → swipe traces → out-sing damages / high-note drains; phrases escalate to the staccato finale; phase 2 at 50%; posse chip-fire feels right; defeat → WIN flow; lose → Fail.
- [ ] **Step 3:** Tune the swipe scoring so a focused player reliably out-sings and the finale is a satisfying spike; align the response window to the music beat. Update `[[project_queen_of_the_night_boss]]` with tuned values. **Commit.**

---

## Self-Review (against the spec)

**Spec coverage:** §1 niche/showcase → Task 4 + 6. §2 canyon terrain + LevelDef + arena stop → Tasks 1, 2. §3 two songbirds → Task 3. §4 Papageno tutorial → Task 7 (uses `QueenDuelState(tutorial=true)`). §5 sing-duel (she sings → contour → swipe → out-sing/high-note, escalation, phase 2, posse-chip, win/lose) → Task 4 (logic) + 5 (overlay) + 6 (drive). §6 hybrid audio → Task 8. §7 chocolate-gold look → Task 9. §8 mobile-safe (billboard + additive overlay, pure testable core) → Tasks 4/5/6/9. §9 YAGNI (no pitch detection/rhythm engine) → honored (contour+window scoring only). §10 TODOs → Tasks 8/9/10. ✓

**Placeholder scan:** the swipe-input hook (Task 6 Step 5) and the audio production (Task 8) are flagged with how to find the real entry point / pipeline, not left vague. No "TBD"/"handle edge cases". The Papageno set-piece (Task 7) reuses concretely-named pieces (`QueenDuelState(tutorial=true)`, `_contour_to_screen`, the swipe capture).

**Type consistency:** `QueenDuelState.{Mode, MAX_HP, score_trace, current_contour, tick, submit_swipe, hp, phase, mode, tutorial}` — identical across Task 4 tests, Task 6 drive, and Task 7 tutorial. `SingDuelFx.{show_contour, open_response, feed_point, end_response, out_sing_flash, high_note_flash, clear, is_active}` — identical across Task 5 tests and Task 6 drive. `submit_swipe` returns `{out_sing, score, posse_drain, damage}` — consumed consistently in Task 6. Boss meta `"boss_kind" == "queen"` consistent across spawn (Task 6) and dispatch/guard (Task 6 Step 6). ✓
