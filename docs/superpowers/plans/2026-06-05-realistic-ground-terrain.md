# Realistic Ground Terrain — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the obviously-tiled flat-dirt gameplay ground with realistic, varied natural ground — a richer baked surface plus a worn central trail, a right-shoulder boardwalk (frontier), MultiMesh scatter, and a mountain cliff ledge — authored per-terrain (frontier/mine/farm/mountain) via `TerrainThemes`.

**Architecture:** One `TerrainThemes` dictionary drives every ground piece. `level_3d._apply_terrain_theme()` reads `_level_def.terrain` and builds: the ground material (per-terrain albedo+normal+detail + strong baked per-vertex macro-variation), a central trail ribbon mesh, a boardwalk strip, MultiMesh scatter, and (mountain) a left cliff. All parent under `_world_root`, which already wraps every `PATH_PATTERN_LEN` (140) — so all baked data stays **periodic in z over 140**. Pure theme math (`mottle` strength, cliff drop, deterministic scatter placement) lives in `terrain_themes.gd` and is GUT-tested; everything geometric is screenshot/device-verified.

**Tech Stack:** Godot 4.6.1 GDScript; `StandardMaterial3D` (albedo/normal/detail/vertex-color), `MultiMesh`, `SurfaceTool` — **no custom spatial shaders** (Android white-rects them). Art via NB Pro (`tools/nb_pro_render.py`) + PIL seamless-tiling.

**Branch:** `terrain` (already checked out).

---

## Key constants & helpers (already in `godot/scripts/level_3d.gd` — do NOT redefine)

- `TERR_HALF_W = 16.0`, `TERR_DX = 2.0`, `TERR_DZ = 2.0`, `TERR_Z_BEHIND = 12.0`, `TERR_Z_AHEAD = -200.0` — terrain mesh grid.
- `PATH_PATTERN_LEN = 140.0`, `PATH_AMP = 8.0`, `COWBOY_X_BOUND = 3.0` — path/world wrap.
- `_terr_vertex(gx, lz) -> Vector3` (line ~6429): `Vector3(gx + _path_lateral(d), _hill_y(d) - _hole_drop(d, gx), lz)` where `d = -lz`. The trail/boardwalk/scatter all use this so they ride the same curved+hilly surface.
- `_path_lateral(d)`, `_hill_y(d)`, `_hole_drop(d, gx)` — periodic over 140.
- `_build_world_terrain()` (~6451) — builds the hill mesh; the per-vertex tint/mottle bake lives here (`tile = 13.0` UV).
- `_apply_terrain_theme()` (~6437) — currently only builds the fog `WorldEnvironment`. We extend it to build the new pieces.
- `_update_world_root()` (~6621) — translates `_world_root` each frame (the scroll).
- `_make_puddle(d, gx, radius)` (~6596) — reference for a flat decal mesh laid on the terrain.

**Reference patterns to READ before implementing (follow these, don't reinvent):**
- `godot/scripts/terrain_3d.gd:179` `build_grass()` — the **MultiMesh of billboarded quads scattered on a hilly surface** pattern (TRANSFORM_3D, per-instance transforms). Model `_build_scatter` on it.
- `godot/scripts/level_select.gd:1112` `_build_trail_mesh()` — the **trail-ribbon-along-a-path** mesh pattern. Model `_build_trail_mesh` (gameplay) on it.

---

## File structure

- `godot/scripts/terrain_themes.gd` — extend `TERRAIN_THEMES` with new keys; author frontier/mine/farm/mountain; add `macro_strength` param to `mottle`; add pure `cliff_drop` + `scatter_positions` helpers.
- `godot/scripts/level_3d.gd` — `_build_world_terrain` (per-theme material + boosted macro + detail UV2 + seam fix + cliff vertex hook); new `_build_trail_mesh`, `_build_boardwalk`, `_build_scatter`, `_build_cliff_void`; `_apply_terrain_theme` wiring.
- `godot/resources/levels/level_1.tres` — add `terrain = "frontier"`.
- `godot/test/test_terrain_themes.gd` — extend for the new pure math.
- `tools/terrain_textures.py` (new) — generate seamless per-terrain ground albedo + derived normal.
- `godot/assets/textures/` + `godot/assets/sprites/props/` — new ground/trail/boardwalk textures + grass-tuft/pine/snow-drift sprites.

---

## Phase 0 — Art generation

### Task 1: Seamless per-terrain ground albedo + normal

**Files:** Create `tools/terrain_textures.py`; output to `godot/assets/textures/ground_<terrain>.png` + `ground_<terrain>_n.png` for terrain in {frontier, mine, farm, mountain}.

- [ ] **Step 1: Write `tools/terrain_textures.py`.** It (a) calls NB Pro for a top-down natural-ground albedo per terrain, (b) makes it seamlessly tileable via the offset-and-feather trick, (c) derives a normal map from luminance. Use the existing NB Pro CLI (READ `tools/nb_pro_render.py` header for exact flags) and PIL.

```python
#!/usr/bin/env python3
"""Generate seamless tileable ground albedo + derived normal per terrain theme."""
import subprocess, sys, pathlib, numpy as np
from PIL import Image, ImageFilter
OUT = pathlib.Path("godot/assets/textures")
PROMPTS = {
  "frontier": "top-down seamless tileable photo of dry sun-baked desert dirt ground, scattered small pebbles, fine cracks, patches of pale sand, natural earthy browns, even overhead light, no shadows no objects",
  "mine":     "top-down seamless tileable photo of dusty grey mine gravel and crushed ore rock, coal flecks, compacted dirt, even overhead light, no shadows",
  "farm":     "top-down seamless tileable photo of rich brown farm soil with sparse short grass flecks and tiny weeds, moist earthy tones, even overhead light, no shadows",
  "mountain": "top-down seamless tileable photo of snow over grey mountain rock, packed snow drifts, exposed frosted stone, icy patches, even overhead light, no shadows",
}
def make_seamless(img):  # offset by half, feather the cross seams
    a = np.asarray(img.convert("RGB")).astype(np.float32); h,w,_ = a.shape
    off = np.roll(np.roll(a, h//2, 0), w//2, 1)
    bx = np.ones((h,w,1), np.float32)
    fade = np.linspace(0,1,w//8).reshape(1,-1,1)
    bx[:, :w//8] = fade; bx[:, w-w//8:] = fade[:, ::-1]
    by = np.ones((h,w,1), np.float32)
    fy = np.linspace(0,1,h//8).reshape(-1,1,1)
    by[:h//8] = fy; by[h-h//8:] = fy[::-1]
    m = np.minimum(bx, by)
    out = a*m + off*(1-m)
    return Image.fromarray(out.astype(np.uint8))
def normal_from(img, strength=2.0):
    g = np.asarray(img.convert("L")).astype(np.float32)/255.0
    gx = np.gradient(g, axis=1)*strength; gy = np.gradient(g, axis=0)*strength
    n = np.dstack([-gx, -gy, np.ones_like(g)])
    n /= np.linalg.norm(n, axis=2, keepdims=True)
    return Image.fromarray(((n*0.5+0.5)*255).astype(np.uint8))
def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for terr, prompt in PROMPTS.items():
        raw = f"/tmp/ground_{terr}_raw.png"
        subprocess.run([sys.executable, "tools/nb_pro_render.py", prompt,
                        "--aspect", "1:1", "--out", raw], check=True)
        base = Image.open(raw).resize((1024,1024))
        seam = make_seamless(base)
        seam.save(OUT / f"ground_{terr}.png")
        normal_from(seam).save(OUT / f"ground_{terr}_n.png")
        print("wrote", terr)
if __name__ == "__main__": main()
```

- [ ] **Step 2: Run it.** `python3 tools/terrain_textures.py`. Expected: 8 PNGs in `godot/assets/textures/`. If NB Pro flags differ, adjust the subprocess call to match `nb_pro_render.py`'s real CLI. If NB Pro fails, retry once with a shorter prompt; if still failing, REPORT the exact error (do not fake the textures).
- [ ] **Step 3: Eyeball each albedo** by Reading the PNGs — confirm natural, varied, no hard objects, reads as the right terrain. Regenerate any that look like obvious tiles or cartoon art.
- [ ] **Step 4: Import + commit.** Run the Godot importer so `.import` sidecars exist: `cd godot && ~/.local/bin/godot --headless --path . --import 2>&1 | tail -3`. Then:
```bash
git add tools/terrain_textures.py godot/assets/textures/ground_*.png godot/assets/textures/ground_*_n.png godot/assets/textures/ground_*.import godot/assets/textures/ground_*_n.png.import
git commit -m "terrain: seamless per-terrain ground albedo + derived normal (frontier/mine/farm/mountain)"
```

### Task 2: Trail, boardwalk, and detail textures

**Files:** Output `godot/assets/textures/trail_<frontier|mine|farm>.png`, `boardwalk_planks.png`, and confirm `ground_detail.png` (exists) usability.

- [ ] **Step 1: Generate via NB Pro** (one call each, READ `nb_pro_render.py` for flags):
  - `trail_frontier` — "top-down seamless worn dirt wagon trail, two faint wheel ruts, packed earth, pebbles, even light, no objects"
  - `trail_mine` — "top-down seamless rocky mine cart track, wooden ties across gravel, even light"
  - `trail_farm` — "top-down seamless packed-dirt farm road, faint tire ruts, even light"
  - `boardwalk_planks` — "top-down seamless weathered grey wooden boardwalk planks running vertically, gaps between boards, even light, no objects"
  Save each to `godot/assets/textures/<name>.png` (1:1 aspect), then run them through the same `make_seamless` from Task 1 (import `make_seamless` or re-run that function on the files).
- [ ] **Step 2: Eyeball** each by Reading the PNGs; regenerate if not tileable/natural.
- [ ] **Step 3: Import + commit.**
```bash
cd godot && ~/.local/bin/godot --headless --path . --import 2>&1 | tail -2
git add godot/assets/textures/trail_*.png godot/assets/textures/boardwalk_planks.png godot/assets/textures/trail_*.import godot/assets/textures/boardwalk_planks.png.import
git commit -m "terrain: trail (frontier/mine/farm) + boardwalk plank textures"
```

### Task 3: Scatter sprites (new) — grass tuft, pine, snow drift

**Files:** `godot/assets/sprites/props/grass_tuft.png`, `pine_tree.png`, `snow_drift.png` (+ `.import`). Reuse existing `rock_large/small`, `cactus_*`, `scrub`, `tumbleweed`, `fence_post`.

- [ ] **Step 1: Generate via NB Pro with green-key matte** (these are billboard sprites — they need alpha). Model on the existing prop-sprite pipeline (READ `tools/kimmy_assets.py` or `scripts/diff_matte.py` for the matte step). Prompts: grass tuft = "a single tuft of dry prairie grass, side view, on a pure green screen"; pine = "a snow-dusted pine tree, side view, pure green screen"; snow drift = "a low mound of snow, side view, pure green screen". Matte → transparent PNG.
- [ ] **Step 2: Eyeball** each (clean alpha, reads at small size).
- [ ] **Step 3: Import + commit.**
```bash
cd godot && ~/.local/bin/godot --headless --path . --import 2>&1 | tail -2
git add godot/assets/sprites/props/grass_tuft.png godot/assets/sprites/props/pine_tree.png godot/assets/sprites/props/snow_drift.png godot/assets/sprites/props/grass_tuft.png.import godot/assets/sprites/props/pine_tree.png.import godot/assets/sprites/props/snow_drift.png.import
git commit -m "terrain: scatter sprites — grass tuft, pine, snow drift"
```

---

## Phase 1 — Theme data + pure math (GUT-tested)

### Task 4: Extend `TerrainThemes` — keys, all 4 themes, macro_strength, cliff, scatter math

**Files:** Modify `godot/scripts/terrain_themes.gd`; Test `godot/test/test_terrain_themes.gd`.

- [ ] **Step 1: Write failing tests.** Append to `godot/test/test_terrain_themes.gd`:

```gdscript
func test_mottle_strength_scales_and_clamps():
	# strength 1.0 == legacy behavior; higher strength widens variation but stays clamped.
	var a := TerrainThemes.mottle(3.0, 10.0, 1.0)
	var b := TerrainThemes.mottle(3.0, 10.0, 3.0)
	assert_true(a >= 0.78 and a <= 1.16, "legacy clamp holds")
	assert_true(b >= 0.55 and b <= 1.45, "strong clamp holds")
	assert_ne(a, b, "strength changes the value")

func test_mottle_periodic_in_z_over_140():
	# must repeat every PATH_PATTERN_LEN so the wrapping world is seamless.
	assert_almost_eq(TerrainThemes.mottle(2.0, 5.0, 2.0), TerrainThemes.mottle(2.0, 5.0 + 140.0, 2.0), 0.0001)

func test_cliff_drop_left_only_beyond_trail():
	# No drop on/right of the trail; steep drop left of it; deeper as you go further left.
	assert_eq(TerrainThemes.cliff_drop(0.0, 2.5, "left", 30.0), 0.0)
	assert_eq(TerrainThemes.cliff_drop(5.0, 2.5, "left", 30.0), 0.0)
	var near := TerrainThemes.cliff_drop(-3.0, 2.5, "left", 30.0)
	var far := TerrainThemes.cliff_drop(-10.0, 2.5, "left", 30.0)
	assert_true(near > 0.0 and far > near, "drops and deepens leftward")
	assert_true(far <= 30.0, "capped at depth")
	assert_eq(TerrainThemes.cliff_drop(-10.0, 2.5, "", 30.0), 0.0, "no side = no cliff")

func test_scatter_positions_deterministic_and_in_bounds():
	var a := TerrainThemes.scatter_positions(7, 3, 5, -10.0, -4.0, 1.5, 6.0)
	var b := TerrainThemes.scatter_positions(7, 3, 5, -10.0, -4.0, 1.5, 6.0)
	assert_eq(a, b, "same seed/cell -> identical placement")
	assert_eq(a.size(), 5)
	for p in a:
		assert_true(p.y >= -10.0 and p.y <= -4.0, "z in band")
		assert_true(abs(p.x) >= 1.5 and abs(p.x) <= 6.0, "x in shoulder band")
```

- [ ] **Step 2: Run, verify fail.** `cd godot && ~/.local/bin/godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://test -gprefix=test_terrain_themes -gexit 2>&1 | tail -15` — expect failures (functions/signatures missing).

- [ ] **Step 3: Implement in `terrain_themes.gd`.** (a) Add the `strength` param to `mottle`; (b) add `cliff_drop` + `scatter_positions`; (c) replace `TERRAIN_THEMES` with all four authored themes + the new keys.

```gdscript
# Low-frequency albedo MULTIPLIER that varies across the surface to break the tile
# repeat. Periodic in lz over HILL_PERIOD. `strength` scales the variation (themes
# pass ~2-3 for a strong "not one flat tile" look; default 1.0 = legacy).
static func mottle(gx: float, lz: float, strength: float = 1.0) -> float:
	var w: float = lz * TAU / HILL_PERIOD
	var m: float = (sin(gx * 0.43 + w * 3.0)
		+ 0.6 * sin(gx * 0.91 - w * 5.0)
		+ 0.4 * sin(gx * 0.19 + w * 8.0))
	return clampf(1.0 + 0.11 * strength * m, 1.0 - 0.22 * strength, 1.0 + 0.22 * strength)

# Extra downward offset for a cliff edge. `side`=="left" drops vertices whose world
# x is left of -trail_half; deepens with distance past the edge, capped at `depth`.
static func cliff_drop(gx_world: float, trail_half: float, side: String, depth: float) -> float:
	if side == "left" and gx_world < -trail_half:
		return minf((-trail_half - gx_world) * 6.0, depth)
	if side == "right" and gx_world > trail_half:
		return minf((gx_world - trail_half) * 6.0, depth)
	return 0.0

# Deterministic scatter placement for one z-cell: `count` (x,z) points, z in
# [z0,z1], |x| in [x_lo,x_hi] (shoulder band), seeded by (slug_seed, cell) so the
# wrapping world is stable frame-to-frame. Returns Array[Vector2] (x=world x, y=z).
static func scatter_positions(slug_seed: int, cell: int, count: int,
		z0: float, z1: float, x_lo: float, x_hi: float) -> Array:
	var out: Array = []
	var rng := RandomNumberGenerator.new()
	for i in range(count):
		rng.seed = hash([slug_seed, cell, i])
		var z: float = lerpf(z0, z1, rng.randf())
		var x: float = lerpf(x_lo, x_hi, rng.randf())
		if rng.randf() < 0.5:
			x = -x
		out.append(Vector2(x, z))
	return out
```

Then replace the `TERRAIN_THEMES` dict (keep `frontier`'s existing tint/fog values, add the new keys; author the other three):

```gdscript
const TERRAIN_THEMES: Dictionary = {
	"frontier": {
		"ground_albedo": "res://assets/textures/ground_frontier.png",
		"ground_normal": "res://assets/textures/ground_frontier_n.png",
		"ground_detail": "res://assets/textures/ground_detail.png",
		"ground_uv_tile": 26.0, "macro_strength": 2.4,
		"tint_low": Color(0.50, 0.40, 0.28), "tint_high": Color(0.86, 0.74, 0.56),
		"fog_color": Color(0.96, 0.78, 0.62), "fog_density": 0.018,
		"trail": {"albedo": "res://assets/textures/trail_frontier.png", "half_width": 2.6},
		"boardwalk": {"side": "right", "albedo": "res://assets/textures/boardwalk_planks.png", "width": 2.2},
		"cliff": null,
		"scatter": [
			{"slug": "grass_tuft", "density": 0.9, "scale": [0.5, 1.0]},
			{"slug": "scrub", "density": 0.5, "scale": [0.6, 1.1]},
			{"slug": "rock_small", "density": 0.4, "scale": [0.5, 1.0]},
			{"slug": "cactus_prickly", "density": 0.25, "scale": [0.8, 1.3]},
			{"slug": "tumbleweed", "density": 0.2, "scale": [0.6, 1.0]},
		],
	},
	"mine": {
		"ground_albedo": "res://assets/textures/ground_mine.png",
		"ground_normal": "res://assets/textures/ground_mine_n.png",
		"ground_detail": "res://assets/textures/ground_detail.png",
		"ground_uv_tile": 24.0, "macro_strength": 2.2,
		"tint_low": Color(0.34, 0.31, 0.30), "tint_high": Color(0.62, 0.58, 0.54),
		"fog_color": Color(0.72, 0.66, 0.58), "fog_density": 0.024,
		"trail": {"albedo": "res://assets/textures/trail_mine.png", "half_width": 2.6},
		"boardwalk": null, "cliff": null,
		"scatter": [
			{"slug": "rock_large", "density": 0.6, "scale": [0.7, 1.4]},
			{"slug": "rock_small", "density": 0.7, "scale": [0.5, 1.0]},
			{"slug": "scrub", "density": 0.3, "scale": [0.5, 0.9]},
		],
	},
	"farm": {
		"ground_albedo": "res://assets/textures/ground_farm.png",
		"ground_normal": "res://assets/textures/ground_farm_n.png",
		"ground_detail": "res://assets/textures/ground_detail.png",
		"ground_uv_tile": 22.0, "macro_strength": 2.0,
		"tint_low": Color(0.34, 0.36, 0.22), "tint_high": Color(0.62, 0.62, 0.40),
		"fog_color": Color(0.80, 0.84, 0.70), "fog_density": 0.016,
		"trail": {"albedo": "res://assets/textures/trail_farm.png", "half_width": 2.6},
		"boardwalk": null, "cliff": null,
		"scatter": [
			{"slug": "grass_tuft", "density": 1.6, "scale": [0.6, 1.2]},
			{"slug": "fence_post", "density": 0.3, "scale": [0.9, 1.1]},
			{"slug": "rock_small", "density": 0.3, "scale": [0.4, 0.8]},
		],
	},
	"mountain": {
		"ground_albedo": "res://assets/textures/ground_mountain.png",
		"ground_normal": "res://assets/textures/ground_mountain_n.png",
		"ground_detail": "res://assets/textures/ground_detail.png",
		"ground_uv_tile": 24.0, "macro_strength": 1.8,
		"tint_low": Color(0.62, 0.66, 0.72), "tint_high": Color(0.92, 0.95, 1.0),
		"fog_color": Color(0.86, 0.90, 0.96), "fog_density": 0.030,
		"trail": {"albedo": "res://assets/textures/ground_mountain.png", "half_width": 2.6},
		"boardwalk": null, "puddle_style": "ice",
		"cliff": {"side": "left", "depth": 30.0},
		"scatter": [
			{"slug": "snow_drift", "density": 0.8, "scale": [0.7, 1.4], "side": "right"},
			{"slug": "pine_tree", "density": 0.5, "scale": [1.0, 2.0], "side": "right"},
			{"slug": "rock_large", "density": 0.4, "scale": [0.6, 1.2], "side": "right"},
		],
	},
}
```

- [ ] **Step 4: Run the full suite, verify green.** `cd godot && ~/.local/bin/godot --headless --path . -s addons/gut/gut_cmdln.gd -gconfig=res://.gutconfig.json -gexit 2>&1 | grep -E "Passing Tests|tests passed|Failing"` — expect `All tests passed!`.
- [ ] **Step 5: Commit.**
```bash
git add godot/scripts/terrain_themes.gd godot/test/test_terrain_themes.gd
git commit -m "terrain: TerrainThemes — 4 authored themes + macro_strength + cliff_drop + scatter_positions (+tests)"
```

---

## Phase 2 — Surface

### Task 5: Per-theme ground material + boosted macro + detail UV2 + seam fix + cliff vertices

**Files:** Modify `godot/scripts/level_3d.gd` `_build_world_terrain` (~6451) and `_terr_vertex` (~6429).

- [ ] **Step 1: Add cliff state + hook it into `_terr_vertex`.** Near the other terrain members add `var _terr_cliff_side: String = ""` and `var _terr_cliff_depth: float = 0.0`. Change `_terr_vertex`:

```gdscript
func _terr_vertex(gx: float, lz: float) -> Vector3:
	var d: float = -lz
	var wx: float = gx + _path_lateral(d)
	var y: float = _hill_y(d) - _hole_drop(d, gx)
	if _terr_cliff_side != "":
		# trail_half (2.6) is the cliff lip; world-x relative to the lane centre.
		y -= TerrainThemes.cliff_drop(wx - _path_lateral(d), 2.6, _terr_cliff_side, _terr_cliff_depth)
	return Vector3(wx, y, lz)
```
(`wx - _path_lateral(d)` == `gx`, i.e. lane-relative x — the cliff lip tracks the curving lane.)

- [ ] **Step 2: In `_build_world_terrain`,** set the cliff members from the theme BEFORE the vertex loop, drive `tile`/macro from the theme, and replace the material block to use the theme's albedo+normal+detail. Read the theme once (it already does), then:

```gdscript
	var _cliff: Variant = _theme.get("cliff", null)
	_terr_cliff_side = String(_cliff["side"]) if _cliff != null else ""
	_terr_cliff_depth = float(_cliff["depth"]) if _cliff != null else 0.0
	var tile: float = float(_theme.get("ground_uv_tile", 13.0))
	var _macro: float = float(_theme.get("macro_strength", 1.0))
```
Change the `_vcol` mottle call to pass strength: `var m: float = TerrainThemes.mottle(gx, lz, _macro)`. In the per-vertex loop also write a **second UV set (UV2)** at higher tiling for the detail layer — for each `st.set_uv(...)` add a matching `st.set_uv2(Vector2(u * 4.0, v * 4.0))` (4× detail tiling). Fix the **center seam** by offsetting U so the lane centre isn't on a tile boundary: compute `u` as `(gx + TERR_HALF_W) / tile + 0.37` (constant offset). Then replace the material construction:

```gdscript
	var sm := StandardMaterial3D.new()
	sm.albedo_texture = load(_theme["ground_albedo"])
	if _theme.has("ground_normal"):
		sm.normal_enabled = true
		sm.normal_texture = load(_theme["ground_normal"])
	sm.roughness = 1.0
	sm.cull_mode = BaseMaterial3D.CULL_DISABLED
	sm.vertex_color_use_as_albedo = true
	sm.uv1_scale = Vector3(1, 1, 1)
	if _theme.has("ground_detail"):
		sm.detail_enabled = true
		sm.detail_albedo = load(_theme["ground_detail"])
		sm.detail_blend_mode = BaseMaterial3D.BLEND_MODE_MIX
		sm.detail_uv_layer = BaseMaterial3D.DETAIL_UV_2
	mi.material_override = sm
```
(Delete the old "reuse the flat ground's authored material" block — we now drive the material from the theme.)

- [ ] **Step 3: Verify it parses + tests stay green.** `cd godot && ~/.local/bin/godot --headless --path . -s addons/gut/gut_cmdln.gd -gconfig=res://.gutconfig.json -gexit 2>&1 | grep -E "Passing Tests|All tests"` → `All tests passed!`.
- [ ] **Step 4: Screenshot frontier.** `.claude/skills/sp1-screenshot/capture.sh res://scenes/level_3d.tscn /tmp/terr_surface.png` then Read it — confirm the ground reads richer/varied with no obvious 13-unit banding or center seam. (Frontier is the default scene level.)
- [ ] **Step 5: Commit.**
```bash
git add godot/scripts/level_3d.gd
git commit -m "terrain: per-theme ground material (albedo+normal+detail UV2) + boosted macro + seam fix + cliff vertices"
```

---

## Phase 3 — Trail, boardwalk, cliff void

### Task 6: Central worn-trail ribbon mesh

**Files:** Modify `godot/scripts/level_3d.gd` — new `_build_trail_mesh()`. READ `level_select.gd:1112 _build_trail_mesh` first for the ribbon pattern.

- [ ] **Step 1: Implement** (called from `_apply_terrain_theme` in Task 10):

```gdscript
# A worn central trail ribbon laid over the earth down the posse's lane. Rides the
# hills via _terr_vertex, raised a hair to avoid z-fighting. Skips themes with no trail.
func _build_trail_mesh() -> void:
	if _world_root == null or _level_def == null:
		return
	var theme: Dictionary = TerrainThemes.get_theme(_level_def.terrain)
	var trail: Variant = theme.get("trail", null)
	if trail == null:
		return
	var half: float = float(trail["half_width"])
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rows: int = int((TERR_Z_BEHIND - TERR_Z_AHEAD) / TERR_DZ)
	for r in range(rows):
		var lz0: float = TERR_Z_BEHIND - float(r) * TERR_DZ
		var lz1: float = lz0 - TERR_DZ
		var v0: float = -lz0 / 6.0
		var v1: float = -lz1 / 6.0
		var pL0 := _terr_vertex(-half, lz0) + Vector3(0, 0.02, 0)
		var pR0 := _terr_vertex(half, lz0) + Vector3(0, 0.02, 0)
		var pL1 := _terr_vertex(-half, lz1) + Vector3(0, 0.02, 0)
		var pR1 := _terr_vertex(half, lz1) + Vector3(0, 0.02, 0)
		st.set_uv(Vector2(0, v0)); st.add_vertex(pL0)
		st.set_uv(Vector2(1, v0)); st.add_vertex(pR0)
		st.set_uv(Vector2(1, v1)); st.add_vertex(pR1)
		st.set_uv(Vector2(0, v0)); st.add_vertex(pL0)
		st.set_uv(Vector2(1, v1)); st.add_vertex(pR1)
		st.set_uv(Vector2(0, v1)); st.add_vertex(pL1)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = "Trail"
	mi.mesh = st.commit()
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(trail["albedo"])
	m.roughness = 1.0
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	_world_root.add_child(mi)
```

- [ ] **Step 2: Temporarily call it** at the end of `_build_world_terrain` (`call_deferred("_build_trail_mesh")`) just for this task's screenshot; **remove** before commit (real wiring is Task 10). Screenshot + Read `/tmp/terr_trail.png` — confirm a distinct worn trail down the centre following the curve.
- [ ] **Step 3: Remove the temp call, verify GUT green, commit.**
```bash
git add godot/scripts/level_3d.gd
git commit -m "terrain: central worn-trail ribbon mesh (_build_trail_mesh)"
```

### Task 7: Boardwalk strip (frontier, right shoulder)

**Files:** Modify `godot/scripts/level_3d.gd` — new `_build_boardwalk()`.

- [ ] **Step 1: Implement** (same ribbon technique, offset onto the right shoulder):

```gdscript
# A wooden plank walk along one shoulder (frontier: right). Rides the hills.
func _build_boardwalk() -> void:
	if _world_root == null or _level_def == null:
		return
	var theme: Dictionary = TerrainThemes.get_theme(_level_def.terrain)
	var bw: Variant = theme.get("boardwalk", null)
	if bw == null:
		return
	var trail: Variant = theme.get("trail", null)
	var lip: float = float(trail["half_width"]) if trail != null else 2.6
	var x0: float = lip + 0.6
	var x1: float = x0 + float(bw["width"])
	if String(bw["side"]) == "left":
		var t := x0; x0 = -x1; x1 = -t
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rows: int = int((TERR_Z_BEHIND - TERR_Z_AHEAD) / TERR_DZ)
	for r in range(rows):
		var lz0: float = TERR_Z_BEHIND - float(r) * TERR_DZ
		var lz1: float = lz0 - TERR_DZ
		var v0: float = -lz0 / 3.0
		var v1: float = -lz1 / 3.0
		var pL0 := _terr_vertex(x0, lz0) + Vector3(0, 0.06, 0)
		var pR0 := _terr_vertex(x1, lz0) + Vector3(0, 0.06, 0)
		var pL1 := _terr_vertex(x0, lz1) + Vector3(0, 0.06, 0)
		var pR1 := _terr_vertex(x1, lz1) + Vector3(0, 0.06, 0)
		st.set_uv(Vector2(0, v0)); st.add_vertex(pL0)
		st.set_uv(Vector2(1, v0)); st.add_vertex(pR0)
		st.set_uv(Vector2(1, v1)); st.add_vertex(pR1)
		st.set_uv(Vector2(0, v0)); st.add_vertex(pL0)
		st.set_uv(Vector2(1, v1)); st.add_vertex(pR1)
		st.set_uv(Vector2(0, v1)); st.add_vertex(pL1)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = "Boardwalk"
	mi.mesh = st.commit()
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(bw["albedo"])
	m.roughness = 1.0
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	_world_root.add_child(mi)
```

- [ ] **Step 2: Temp-call + screenshot** (as Task 6 Step 2), confirm a plank walk on the RIGHT shoulder; remove temp call.
- [ ] **Step 3: GUT green, commit.**
```bash
git add godot/scripts/level_3d.gd
git commit -m "terrain: wooden boardwalk strip on the right shoulder (frontier)"
```

### Task 8: MultiMesh scatter

**Files:** Modify `godot/scripts/level_3d.gd` — new `_build_scatter()`. READ `terrain_3d.gd:179 build_grass` for the MultiMesh pattern.

- [ ] **Step 1: Implement.** One `MultiMeshInstance3D` per scatter slug; instances placed on the shoulder band via `TerrainThemes.scatter_positions` per z-cell across the mesh depth, sitting on the surface via `_terr_vertex`, billboarded quads. Bounded by density; fog hides the far ones (no per-frame cull needed — the mesh is static under `_world_root`).

```gdscript
const _SHOULDER_X_LO: float = 3.4   # just past the trail lip
const _SHOULDER_X_HI: float = 13.0  # out to the fog/terrain edge
func _build_scatter() -> void:
	if _world_root == null or _level_def == null:
		return
	var theme: Dictionary = TerrainThemes.get_theme(_level_def.terrain)
	var sets: Array = theme.get("scatter", [])
	var z_lo: float = TERR_Z_AHEAD + 2.0
	var z_hi: float = TERR_Z_BEHIND - 2.0
	var cell_dz: float = 6.0
	var cells: int = int((z_hi - z_lo) / cell_dz)
	for s in sets:
		var slug: String = String(s["slug"])
		var tex_path: String = "res://assets/sprites/props/%s.png" % slug
		if not ResourceLoader.exists(tex_path):
			continue
		var tex: Texture2D = load(tex_path)
		var side: String = String(s.get("side", "both"))
		var sc: Array = s.get("scale", [0.6, 1.0])
		var dens: float = float(s["density"])
		var xforms: Array = []
		for c in range(cells):
			var z0: float = z_lo + float(c) * cell_dz
			var z1: float = z0 + cell_dz
			var n: int = int(round(dens * 2.0))
			for p in TerrainThemes.scatter_positions(hash(slug), c, n, -z1, -z0, _SHOULDER_X_LO, _SHOULDER_X_HI):
				var px: float = p.x
				if side == "right" and px < 0.0: px = -px
				if side == "left" and px > 0.0: px = -px
				var lz: float = p.y
				var pos: Vector3 = _terr_vertex(px, lz)
				var rng := RandomNumberGenerator.new(); rng.seed = hash([slug, c, px])
				var scl: float = lerpf(sc[0], sc[1], rng.randf())
				var b := Basis.IDENTITY.scaled(Vector3(scl, scl, scl))
				xforms.append(Transform3D(b, pos + Vector3(0, scl * 0.5, 0)))
		if xforms.is_empty():
			continue
		var quad := QuadMesh.new(); quad.size = Vector2(1.0, 1.0)
		var m := StandardMaterial3D.new()
		m.albedo_texture = tex
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		m.alpha_scissor_threshold = 0.5
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		m.billboard_keep_scale = true
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		quad.material = m
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = quad
		mm.instance_count = xforms.size()
		for i in range(xforms.size()):
			mm.set_instance_transform(i, xforms[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Scatter_%s" % slug
		mmi.multimesh = mm
		_world_root.add_child(mmi)
```

- [ ] **Step 2: Temp-call + screenshot,** confirm scatter on the shoulders (grass/scrub/rocks/cactus/tumbleweed on frontier), not on the trail; remove temp call.
- [ ] **Step 3: GUT green, commit.**
```bash
git add godot/scripts/level_3d.gd
git commit -m "terrain: MultiMesh scatter on the shoulders (deterministic, fog-bounded)"
```

### Task 9: Mountain cliff void-fill

**Files:** Modify `godot/scripts/level_3d.gd` — new `_build_cliff_void()`.

- [ ] **Step 1: Implement** a dark/haze vertical fill below the cliff lip so the drop reads as a precipice into a gorge, not a hole:

```gdscript
# A receding haze/void plane below the cliff lip so the left drop reads as a gorge.
func _build_cliff_void() -> void:
	if _world_root == null or _level_def == null:
		return
	var theme: Dictionary = TerrainThemes.get_theme(_level_def.terrain)
	var cliff: Variant = theme.get("cliff", null)
	if cliff == null:
		return
	var depth: float = float(cliff["depth"])
	var lip: float = -2.6 if String(cliff["side"]) == "left" else 2.6
	var pm := PlaneMesh.new()
	pm.size = Vector2(depth, abs(TERR_Z_AHEAD - TERR_Z_BEHIND))
	var mi := MeshInstance3D.new()
	mi.name = "CliffVoid"
	mi.mesh = pm
	# Lay it as a steep face just outside the lip, dropping to -depth.
	mi.rotation_degrees = Vector3(0, 0, -80 if String(cliff["side"]) == "left" else 80)
	mi.position = Vector3(lip - (depth * 0.5) * (1 if String(cliff["side"]) == "left" else -1),
		-depth * 0.5, (TERR_Z_AHEAD + TERR_Z_BEHIND) * 0.5)
	var m := StandardMaterial3D.new()
	m.albedo_color = theme.get("fog_color", Color(0.86, 0.90, 0.96))
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	_world_root.add_child(mi)
```
*(Confirm orientation against a mountain screenshot in Task 10; nudge the rotation/position so the face reads as a cliff into haze.)*

- [ ] **Step 2: GUT green, commit.**
```bash
git add godot/scripts/level_3d.gd
git commit -m "terrain: mountain cliff void-fill (gorge haze below the left lip)"
```

### Task 9b: Frozen-ice puddles on the mountain

**Files:** Modify `godot/scripts/level_3d.gd` `_make_puddle` (~6596).

Mountain puddles must read as **frozen ice**, not reflective blue water. Make `_make_puddle` theme-aware: when the level's theme has `puddle_style == "ice"`, render a frosted pale-cyan/white, mostly-opaque, matte-frosty disc instead of the shiny blue water.

- [ ] **Step 1: Implement.** After the existing `mat` setup in `_make_puddle`, before `mi.material_override = mat`, add:
```gdscript
	var _pt: Dictionary = TerrainThemes.get_theme(_level_def.terrain if _level_def != null else "frontier")
	if String(_pt.get("puddle_style", "water")) == "ice":
		# Frozen: frosty pale ice, mostly opaque, matte (not the shiny blue water look).
		mat.albedo_color = Color(0.82, 0.92, 0.98, 0.95)
		mat.metallic = 0.15
		mat.roughness = 0.55
```
- [ ] **Step 2: Verify + screenshot.** GUT green; then confirm via the mountain screenshot in Task 10 (force terrain=mountain) that puddles read as pale frosted ice, not blue water.
- [ ] **Step 3: Commit.**
```bash
git add godot/scripts/level_3d.gd
git commit -m "terrain: frozen-ice puddles on mountain (puddle_style=ice)"
```

---

## Phase 4 — Wire + author + verify

### Task 10: Wire `_apply_terrain_theme` + level_1 terrain + per-terrain screenshots

**Files:** Modify `godot/scripts/level_3d.gd` `_apply_terrain_theme`, `godot/resources/levels/level_1.tres`.

- [ ] **Step 1: Wire the builders.** At the END of `_apply_terrain_theme()` (after the fog `WorldEnvironment`), add:
```gdscript
	_build_trail_mesh()
	_build_boardwalk()
	_build_cliff_void()
	_build_scatter()
```
(Note: `_apply_terrain_theme` runs in `_ready` AFTER `_build_world_terrain`, so `_world_root` exists. Confirm that order in `_ready` — `_build_world_terrain()` then `_apply_terrain_theme()`; if reversed, swap so the world root is built first.)

- [ ] **Step 2: Set level_1 terrain.** In `godot/resources/levels/level_1.tres`, in the `[resource]` block add `terrain = "frontier"` (so it's explicit, not defaulted).

- [ ] **Step 3: Screenshot all four terrains.** Add a TEMPORARY debug hook in `_ready` (remove before commit) that forces the terrain so the static harness can frame each:
```gdscript
	if _level_def != null:
		_level_def.terrain = "mountain"   # _DBG_TERR temp — cycle frontier/mine/farm/mountain
```
For each of the four, set the value, run `.claude/skills/sp1-screenshot/capture.sh res://scenes/level_3d.tscn /tmp/terr_<name>.png`, and Read it. Confirm: richer non-tiling surface, the trail, frontier's right boardwalk, scatter on shoulders, and the mountain left cliff + gorge haze. Tune theme values (uv_tile, macro_strength, densities, cliff rotation) as needed. **Remove the temp hook.**

- [ ] **Step 4: Full GUT green.** `All tests passed!`.
- [ ] **Step 5: Commit.**
```bash
git add godot/scripts/level_3d.gd godot/resources/levels/level_1.tres
git commit -m "terrain: wire trail/boardwalk/scatter/cliff into _apply_terrain_theme; level_1 terrain=frontier"
```

### Task 11: Sideload + device verification

**Files:** none (verification only).

- [ ] **Step 1: Build + distribute.**
```bash
git push origin terrain
scripts/sideload.sh <iterN> && scripts/firebase_distribute.sh /tmp/nta_sideload/nta_iter<N>.apk "terrain: realistic per-level ground (surface+trail+boardwalk+scatter+mountain cliff)"
```
- [ ] **Step 2: Device check (manual).** Play each level: ground reads natural (no obvious tiling), the worn trail, frontier's right boardwalk, shoulder scatter, the mountain left cliff/gorge; and **big-posse frame rate holds** (the scatter is bounded MultiMesh). Note any per-terrain tuning for a fast-follow.

---

## Self-Review

**Spec coverage:** §1 surface → Tasks 1,5. §2 trail/shoulders → Task 6. §3 boardwalk → Task 7. §4 scatter → Tasks 3,8. §5 per-terrain theming → Task 4 (+10 wiring). Mountain cliff → Tasks 4 (math), 5 (vertices), 9 (void). Verification → Tasks 4 (GUT), 5–10 (screenshots), 11 (device). All covered.

**Type consistency:** `mottle(gx,lz,strength)`, `cliff_drop(gx_world,trail_half,side,depth)`, `scatter_positions(slug_seed,cell,count,z0,z1,x_lo,x_hi)` match between Task 4 (def+tests) and callers (Tasks 5,8). Theme keys (`ground_albedo/normal/detail`, `ground_uv_tile`, `macro_strength`, `trail.{albedo,half_width}`, `boardwalk.{side,albedo,width}`, `cliff.{side,depth}`, `scatter[].{slug,density,scale,side}`) consistent between Task 4 and the `_build_*` consumers. `_build_trail_mesh`/`_build_boardwalk`/`_build_scatter`/`_build_cliff_void` defined Tasks 6–9, wired Task 10.

**Trail half_width:** `2.6` is hard-coded in `_terr_vertex`'s cliff call (Task 5) and read from the theme elsewhere — kept equal across themes (2.6); if a theme changes it, update the `_terr_vertex` literal too (noted in Task 5).
