# Natural Terrain Environment Pass — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the `level_3d` gameplay terrain read as a believable 3D place — realistic varied ground (multi-octave hills, baked valley/ridge tint, a built-in detail layer) under atmospheric fog and (later) candy landmarks + parallax depth — themed per `LevelDef.terrain`.

**Architecture:** A new `terrain_themes.gd` (class_name `TerrainThemes`) holds the per-terrain look data AND the pure, unit-testable math (periodic hill height, valley/ridge tint). `level_3d` calls those statics from `_build_world_terrain` / `_hill_y` and applies the rest (ground material detail, `WorldEnvironment` fog) via `_apply_terrain_theme()`, keyed to the level's terrain string.

**Tech Stack:** Godot 4.6.1 GDScript; built-in `StandardMaterial3D` (detail layer + vertex colors), `WorldEnvironment` fog, `SurfaceTool`; GUT for pure-logic tests. NO custom spatial shaders (mobile renderer white-rects them).

**Verification reality:** GUT covers the pure statics in `terrain_themes.gd`. The terrain *look* is verified with `sp1-screenshot` stills of `res://scenes/level_3d.tscn` using a TEMPORARY force-PLAYING + busy-camera debug-preview hook (removed before each commit; pattern used in iter400–411). Fog depth, parallax motion, and on-device rendering are device checks (Firebase).

---

## File Structure

- `godot/scripts/terrain_themes.gd` (NEW) — `class_name TerrainThemes`. Static: `get_theme(name)`, `hill_height(d)`, `tint(hill_y, lo, hi)`; const `TERRAIN_THEMES` dict; const `HILL_PERIOD`.
- `godot/test/test_terrain_themes.gd` (NEW) — GUT tests for the three statics.
- `godot/scripts/level_3d.gd` (MODIFY) — `_hill_y` delegates to `TerrainThemes.hill_height`; `_build_world_terrain` bakes vertex tint + sets the detail layer; new `_apply_terrain_theme()`; `WorldEnvironment` setup.
- `godot/assets/textures/ground_detail.png` (NEW) — close-up gravel/crack detail tile (PIL-generated).

---

## Task 1: `TerrainThemes` data + lookup

**Files:**
- Create: `godot/scripts/terrain_themes.gd`
- Test: `godot/test/test_terrain_themes.gd`

- [ ] **Step 1: Write the failing test**

```gdscript
# godot/test/test_terrain_themes.gd
extends GutTest

const TerrainThemes = preload("res://scripts/terrain_themes.gd")

func test_frontier_theme_has_required_keys():
	var t: Dictionary = TerrainThemes.get_theme("frontier")
	for k in ["ground_albedo", "ground_detail", "tint_low", "tint_high", "fog_color", "fog_density"]:
		assert_true(t.has(k), "frontier theme missing key %s" % k)

func test_unknown_terrain_falls_back_to_frontier():
	assert_eq(TerrainThemes.get_theme("does_not_exist"), TerrainThemes.get_theme("frontier"))
```

- [ ] **Step 2: Run it, expect FAIL**

Run: `$HOME/.local/bin/godot --headless --path godot -s res://addons/gut/gut_cmdln.gd -gtest=res://test/test_terrain_themes.gd -gexit`
Expected: FAIL (preload of a nonexistent script / parse error).

- [ ] **Step 3: Implement `terrain_themes.gd`**

```gdscript
# godot/scripts/terrain_themes.gd
class_name TerrainThemes
extends RefCounted

# Per-terrain environment look. Keyed to LevelDef.terrain. "frontier" is the
# fully-authored baseline; the others start as copies and diverge later (phase 3).
const TERRAIN_THEMES: Dictionary = {
	"frontier": {
		"ground_albedo": "res://assets/textures/dirt_2k.png",
		"ground_detail": "res://assets/textures/ground_detail.png",
		"tint_low": Color(0.62, 0.50, 0.36),   # compacted valley
		"tint_high": Color(1.04, 0.98, 0.86),  # sun-bleached ridge (>1 brightens)
		"fog_color": Color(0.96, 0.78, 0.62),  # warm dusty horizon
		"fog_density": 0.018,
	},
}

static func get_theme(name: String) -> Dictionary:
	return TERRAIN_THEMES.get(name, TERRAIN_THEMES["frontier"])
```

- [ ] **Step 4: Run it, expect PASS**

Run: `$HOME/.local/bin/godot --headless --path godot -s res://addons/gut/gut_cmdln.gd -gtest=res://test/test_terrain_themes.gd -gexit`
Expected: 2 passing.

- [ ] **Step 5: Commit**

```bash
git add godot/scripts/terrain_themes.gd godot/test/test_terrain_themes.gd
git commit -m "terrain themes: TerrainThemes.get_theme + frontier baseline"
```

---

## Task 2: Periodic multi-octave hills

**Files:**
- Modify: `godot/scripts/terrain_themes.gd` (add `HILL_PERIOD` + `hill_height`)
- Modify: `godot/scripts/level_3d.gd` (`_hill_y` delegates)
- Test: `godot/test/test_terrain_themes.gd`

- [ ] **Step 1: Write the failing test** (append)

```gdscript
func test_hill_height_is_periodic():
	# Must wrap seamlessly with the static world (period == HILL_PERIOD).
	for d in [0.0, 13.0, 47.5, 99.9]:
		assert_almost_eq(TerrainThemes.hill_height(d),
			TerrainThemes.hill_height(d + TerrainThemes.HILL_PERIOD), 0.0001)

func test_hill_height_amplitude_bounded():
	var hi := -1000.0
	var lo := 1000.0
	for i in range(280):
		var v: float = TerrainThemes.hill_height(float(i) * 0.5)
		hi = maxf(hi, v); lo = minf(lo, v)
	assert_true(hi - lo > 0.5, "hills should actually undulate")
	assert_true(hi - lo < 6.0, "hills should not spike (got range %.2f)" % (hi - lo))
```

- [ ] **Step 2: Run it, expect FAIL** (`hill_height` not defined)

Run: `$HOME/.local/bin/godot --headless --path godot -s res://addons/gut/gut_cmdln.gd -gtest=res://test/test_terrain_themes.gd -gexit`

- [ ] **Step 3: Implement** — add to `terrain_themes.gd`:

```gdscript
# Hill profile = sum of sine octaves whose periods all divide HILL_PERIOD, so it
# stays periodic (the static world wraps at level_3d.PATH_PATTERN_LEN == 140).
const HILL_PERIOD: float = 140.0

static func hill_height(d: float) -> float:
	return (1.10 * sin(d * TAU / 140.0)
		+ 0.55 * sin(d * TAU / 70.0)
		+ 0.30 * sin(d * TAU / 35.0)
		+ 0.16 * sin(d * TAU / 28.0))
```

- [ ] **Step 4: Run it, expect PASS** (4 tests now).

- [ ] **Step 5: Wire `level_3d._hill_y`** — replace the body of `func _hill_y(d: float) -> float:` (currently `return HILL_AMP1 * sin(...) + HILL_AMP2 * sin(...)`) with:

```gdscript
func _hill_y(d: float) -> float:
	return TerrainThemes.hill_height(d)
```

(Leave `HILL_AMP1`/`HILL_AMP2` consts; they're now unused but harmless — remove only if no other reference.)

- [ ] **Step 6: Verify the game still parses + GUT green**

Run: `$HOME/.local/bin/godot --headless --path godot -s res://addons/gut/gut_cmdln.gd -gconfig=res://.gutconfig.json -gexit`
Expected: 430 passing / 1 failing (the pre-existing weather test).

- [ ] **Step 7: Commit**

```bash
git add godot/scripts/terrain_themes.gd godot/test/test_terrain_themes.gd godot/scripts/level_3d.gd
git commit -m "terrain: periodic multi-octave hills (seamless wrap preserved)"
```

---

## Task 3: Baked valley/ridge vertex tint

**Files:**
- Modify: `godot/scripts/terrain_themes.gd` (add `tint`)
- Modify: `godot/scripts/level_3d.gd` (`_build_world_terrain`)
- Test: `godot/test/test_terrain_themes.gd`

- [ ] **Step 1: Write the failing test** (append)

```gdscript
func test_tint_valley_darker_than_ridge():
	var lo := Color(0.5, 0.4, 0.3)
	var hi := Color(1.0, 0.95, 0.85)
	var valley := TerrainThemes.tint(-2.0, lo, hi, 2.0)   # low hill_y
	var ridge := TerrainThemes.tint(2.0, lo, hi, 2.0)     # high hill_y
	assert_true(valley.v < ridge.v, "valley should be darker than ridge")
```

- [ ] **Step 2: Run it, expect FAIL** (`tint` not defined).

- [ ] **Step 3: Implement** — add to `terrain_themes.gd`:

```gdscript
# Map a vertex's hill height (-amp..amp) to a valley→ridge albedo multiplier color.
static func tint(hill_y: float, lo: Color, hi: Color, amp: float) -> Color:
	var t: float = clampf((hill_y + amp) / (2.0 * amp), 0.0, 1.0)
	return lo.lerp(hi, t)
```

- [ ] **Step 4: Run it, expect PASS** (5 tests).

- [ ] **Step 5: Bake into `_build_world_terrain`** — in `level_3d.gd`, the terrain build loop currently does `st.set_uv(...); st.add_vertex(pXX)` for each of the 6 verts per cell. Before each `add_vertex`, set the vertex color from the theme tint. Add near the top of `_build_world_terrain` (after `var st := SurfaceTool.new()`):

```gdscript
	var _theme: Dictionary = TerrainThemes.get_theme(
		_level_def.terrain if _level_def != null else "frontier")
	var _tlo: Color = _theme["tint_low"]
	var _thi: Color = _theme["tint_high"]
	var _tamp: float = HILL_AMP1 + HILL_AMP2 + 0.46   # ≈ max |hill_height|
```

Then for EACH of the six `st.set_uv(...) ; st.add_vertex(pNN)` pairs, insert a `set_color` using that vertex's baked height. Each `pNN` is a `Vector3` whose `.y` is `_hill_y(d) - hole`; use its `.y` directly:

```gdscript
			st.set_color(TerrainThemes.tint(p00.y, _tlo, _thi, _tamp)); st.set_uv(Vector2(u0, v0)); st.add_vertex(p00)
			st.set_color(TerrainThemes.tint(p10.y, _tlo, _thi, _tamp)); st.set_uv(Vector2(u1, v0)); st.add_vertex(p10)
			st.set_color(TerrainThemes.tint(p11.y, _tlo, _thi, _tamp)); st.set_uv(Vector2(u1, v1)); st.add_vertex(p11)
			st.set_color(TerrainThemes.tint(p00.y, _tlo, _thi, _tamp)); st.set_uv(Vector2(u0, v0)); st.add_vertex(p00)
			st.set_color(TerrainThemes.tint(p11.y, _tlo, _thi, _tamp)); st.set_uv(Vector2(u1, v1)); st.add_vertex(p11)
			st.set_color(TerrainThemes.tint(p01.y, _tlo, _thi, _tamp)); st.set_uv(Vector2(u0, v1)); st.add_vertex(p01)
```

And on the ground material (the duplicated flat-ground material in `_build_world_terrain`), enable vertex color:

```gdscript
		(mat as StandardMaterial3D).vertex_color_use_as_albedo = true
```

(If the grabbed material isn't a `StandardMaterial3D`, the existing fallback `sm` branch should also set `sm.vertex_color_use_as_albedo = true`.)

- [ ] **Step 6: Visual verify** — add a TEMP `call_deferred("_DEBUG_terrain_preview")` in `_ready` (force `_level_state = PLAYING`, `_countdown_remaining = -10`, `_render_countdown()`, set `camera.rotation_degrees.x = CAM_PITCH_BUSY`, `camera.position = CAM_POS_BUSY`, `_level_distance = 30.0`, then `_apply_path_curve()`); capture and inspect:

Run: `.claude/skills/sp1-screenshot/capture.sh res://scenes/level_3d.tscn /tmp/terr3.png` then Read `/tmp/terr3.png`.
Expected: ground shows darker valleys / lighter ridges (no longer one flat brown). Remove the TEMP hook.

- [ ] **Step 7: Commit**

```bash
git add godot/scripts/terrain_themes.gd godot/test/test_terrain_themes.gd godot/scripts/level_3d.gd
git commit -m "terrain: baked valley/ridge vertex tint on the ground mesh"
```

---

## Task 4: Ground detail layer

**Files:**
- Create: `godot/assets/textures/ground_detail.png`
- Modify: `godot/scripts/level_3d.gd` (`_build_world_terrain` material)

- [ ] **Step 1: Generate the detail tile** — a seamless-ish grey gravel/crack tile (PIL):

```bash
python3 - <<'PY'
from PIL import Image, ImageFilter, ImageDraw
import random
random.seed(11)
S=512
img=Image.new("RGB",(S,S),(128,128,128))
px=img.load()
for y in range(S):
    for x in range(S):
        n=random.randint(-26,26)
        px[x,y]=(128+n,128+n,128+n)
img=img.filter(ImageFilter.GaussianBlur(0.6))
d=ImageDraw.Draw(img)
for _ in range(40):  # a few darker cracks/pebbles
    x,y=random.randint(0,S),random.randint(0,S)
    d.line([(x,y),(x+random.randint(-40,40),y+random.randint(-40,40))],fill=(96,96,96),width=1)
img.save("godot/assets/textures/ground_detail.png")
print("wrote ground_detail.png")
PY
```

- [ ] **Step 2: Wire the detail layer** — in `_build_world_terrain`, after the material is resolved (the `mat`/`sm` block), add (guarded to `StandardMaterial3D`):

```gdscript
	if mat is StandardMaterial3D and ResourceLoader.exists(_theme["ground_detail"]):
		var sm3 := mat as StandardMaterial3D
		sm3.detail_enabled = true
		sm3.detail_blend_mode = BaseMaterial3D.BLEND_MODE_MIX
		sm3.detail_albedo = load(_theme["ground_detail"])
		sm3.detail_uv_layer = BaseMaterial3D.DETAIL_UV_1
		sm3.uv2_scale = Vector3(6, 6, 1)   # detail tiles finer than the base
```

(`_theme` is the dict resolved in Task 3 step 5; this task assumes Task 3 landed.)

- [ ] **Step 3: Import + visual verify**

Run: `$HOME/.local/bin/godot --headless --path godot --import` then capture `/tmp/terr4.png` via the TEMP preview hook (as Task 3 step 6) and Read it.
Expected: near-ground gravel/crack detail over the base dirt. Remove the TEMP hook.

- [ ] **Step 4: Commit**

```bash
git add godot/assets/textures/ground_detail.png godot/assets/textures/ground_detail.png.import godot/scripts/level_3d.gd
git commit -m "terrain: ground detail layer (built-in detail_albedo) for close-up variation"
```

---

## Task 5: WorldEnvironment fog

**Files:**
- Modify: `godot/scripts/level_3d.gd` (add env + `_apply_terrain_theme`)

- [ ] **Step 1: Add `_apply_terrain_theme` + fog** — new function in `level_3d.gd`:

```gdscript
# iter4xx: apply the per-terrain environment look (fog; ground tex/tint are baked
# at build time in _build_world_terrain). Called from _ready after the terrain exists.
func _apply_terrain_theme() -> void:
	var theme: Dictionary = TerrainThemes.get_theme(
		_level_def.terrain if _level_def != null else "frontier")
	var env := Environment.new()
	env.background_mode = Environment.BG_CANVAS  # keep the existing sky/canvas behind
	env.fog_enabled = true
	env.fog_light_color = theme["fog_color"]
	env.fog_density = theme["fog_density"]
	var we := WorldEnvironment.new()
	we.name = "TerrainEnv"
	we.environment = env
	subviewport.add_child(we)
```

- [ ] **Step 2: Call it in `_ready`** — right after `_build_world_terrain()`:

```gdscript
	_build_world_terrain()
	_apply_terrain_theme()   # fog + per-terrain look
```

- [ ] **Step 3: Visual verify** — capture `/tmp/terr5.png` via the TEMP preview hook (set `_level_distance = 30`) and Read it.
Expected: far hills fade into a warm haze; the terrain's far edge is hidden by fog. If fog swallows the whole scene, halve `fog_density` in the frontier theme. Remove the TEMP hook.

- [ ] **Step 4: GUT green + commit**

```bash
$HOME/.local/bin/godot --headless --path godot -s res://addons/gut/gut_cmdln.gd -gconfig=res://.gutconfig.json -gexit   # 430/1
git add godot/scripts/level_3d.gd
git commit -m "terrain: WorldEnvironment distance fog from the terrain theme"
```

---

## Task 6: Phase-1 integration check

**Files:** none (verification + cleanup)

- [ ] **Step 1:** Confirm no stray TEMP `_DEBUG_terrain_preview` / `call_deferred("_DEBUG` remains:

Run: `grep -n "_DEBUG_terrain_preview\|call_deferred(\"_DEBUG" godot/scripts/level_3d.gd` → expect no matches.

- [ ] **Step 2:** Full GUT run green (430 pass / 1 pre-existing fail).
- [ ] **Step 3:** One more `/tmp/terr_final.png` capture (TEMP hook, then remove) confirming hills + tint + detail + fog read together as a natural surface.
- [ ] **Step 4:** Deploy for the on-device fog/motion check (push → CI → `scripts/sideload.sh` → `scripts/firebase_distribute.sh`, per the project loop).

---

## Phase 2 — Landmarks & layered depth (OUTLINE)

- **Landmark spawner:** a periodic spawner (like `_spawn_chicken_coop`) that places NON-colliding decor — candy rock mesas/buttes, boulder stacks, cactus clusters — off-path (|x| beyond `COWBOY_X_BOUND`) under `_world_root`, slugs + density from `theme["landmark_set"]`. Reuse `_obstacle_prop` for art; mark `is_decor` so the bullet/collision loops skip them. Distance-cull on despawn.
- **Parallax backdrop:** 2–3 wide billboard/curved-plane layers at far −z between gameplay and the candy mountains; each shifts x by a fraction of `_path_lateral(_level_distance)` (parallax). Built once, repositioned per frame (cheap). Silhouette textures from `theme["backdrop_layers"]`.
- New theme keys: `landmark_set`, `backdrop_layers`, `scatter_density`. New art via NB-Pro/PIL.
- Verify: stills (decor placement) + device (parallax motion).

## Phase 3 — Per-terrain theme sets (OUTLINE)

- Author `mine` / `farm` / `mountain` entries in `TERRAIN_THEMES` (ground tex, tint palette, fog color, landmark set, backdrops) — diverging from the frontier copy.
- Generate per-terrain ground + landmark + backdrop art.
- Author `.tres` levels (or just set `terrain` on existing ones) to exercise each; capture one still per terrain.
- The `_apply_terrain_theme` + `_build_world_terrain` paths already read by name, so this is data + art only.

---

## Self-Review

- **Spec coverage:** multi-octave hills (T2), detail layer (T4), vertex tint (T3), landmarks (P2), parallax (P2), fog (T5), per-terrain theme indirection (T1 + read in T3/T5/T6; full sets P3), mobile-safe built-ins only (all tasks), verification reality (each task's visual step + T6 device). ✔
- **Placeholder scan:** every code step shows real code; tints/densities are concrete starting values with a tuning note. ✔
- **Type consistency:** `get_theme`/`hill_height`/`tint`/`HILL_PERIOD` names + the theme dict keys (`tint_low/high`, `fog_color/density`, `ground_albedo/detail`, `landmark_set`, `backdrop_layers`) are used identically across tasks. ✔
