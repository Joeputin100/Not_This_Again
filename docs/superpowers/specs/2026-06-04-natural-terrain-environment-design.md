# Natural Terrain Environment Pass — Design

**Goal:** Turn the gameplay terrain from bare brown hilly dirt into a believable 3D place — a realistic, varied ground *surface* (direction B) dressed with candy-themed *landmarks and layered atmospheric depth* (direction C), swappable per level terrain-type.

**Scope:** Visual environment of `level_3d` gameplay only. Does NOT cover the level-editor (SP3) or data-driving the path/holes/puddles (those stay as-is). It DOES key the look to the existing `LevelDef.terrain` field.

## Constraints (hard)

- The Android mobile renderer **white-rects custom spatial (3D) shaders** — confirmed repeatedly this project. Therefore the ground/landmarks/fog use ONLY built-in `StandardMaterial3D` (including its built-in detail + vertex-color paths), `MultiMesh`, and `WorldEnvironment`. The one proven exception is `grass_field.gdshader` (renders on-device in SP1); it MAY be used for sparse grass scatter but is not required.
- Gameplay renders inside `Terrain3D/SubViewport` (1080×1920), camera fov 50 KEEP_WIDTH, dynamic pitch CALM(−25°)↔BUSY(−55°), two `DirectionalLight3D`s, **no `WorldEnvironment` currently**.
- Current terrain: `level_3d._build_world_terrain()` builds one curved+hilly `ArrayMesh` (SurfaceTool) using the flat-ground 2K PBR dirt material (albedo+normal+rough); `_hill_y(d)` = two sine waves; `_terr_vertex`, `_hole_drop`, `_make_puddle`, `_update_world_root` already exist. The whole world lives under `_world_root` which is translated to fake the posse advancing.
- Performance headroom is tight at large posse (`CROWD_RENDER_CAP=1500`). New scatter/landmarks must be MultiMesh or pooled + distance-culled, and must not rebuild per frame.

## Components

### 1. Realistic ground surface (B)

**1a. Multi-octave hills.** Replace `_hill_y(d)`'s two sine waves with a fixed sum of ~4-5 sine octaves whose periods all divide `PATH_PATTERN_LEN` (e.g. 140, 70, 35, 28, 20) with decreasing amplitudes. This stays analytic and PERIODIC over the pattern length, so the wrapping static world (`_world_root.z = fposmod(distance, PATH_PATTERN_LEN)`) still tiles seamlessly, which `FastNoiseLite` would NOT (it isn't periodic). Amplitudes tuned for natural rolling hills, not spikes. The per-vertex result drives geometry + lighting normals (the mesh is subdivided enough for `generate_normals()` to pick up the bumps). Optionally add a component varying with the lateral grid `gx` so hills roll across the width too, kept periodic in the bake.

**1b. Surface variation (no custom shader).**
- **Detail layer:** on the ground `StandardMaterial3D`, set `detail_enabled` with `detail_albedo` (close-up gravel/cracks tile) + `detail_normal`, `detail_blend_mode = MIX`, a `detail_mask`, and `detail_uv_layer = UV1` at a higher tiling than the base — adds near-ground detail the base 2K tile lacks. Built-in, mobile-safe.
- **Per-vertex color tint:** `_build_world_terrain` writes a `Color` per vertex (via `SurfaceTool.set_color`) and the material sets `vertex_color_use_as_albedo = true` so it multiplies the albedo: darker in compacted valleys (low `_hill_y`), sun-bleached on ridges (high `_hill_y`), plus low-frequency noise mottling. This is the main "real earth, not one flat tile" win and costs nothing at runtime (baked once).

### 2. Candy landmarks & layered depth (C)

**2a. Landmark props.** Off-path decor scattered on the shoulders + mid-distance: candy rock mesas/buttes, boulder stacks, cactus clusters. Implemented like the existing scrolling props (billboard `Sprite3D` or simple `QuadMesh`/`MeshInstance3D` with `StandardMaterial3D`), parented under `_world_root` so they scroll with the static world, placed by the theme's density/positions, **non-colliding** (decor only — distinct from the gameplay obstacle bull/coop/cactus which keep their hazard roles). New art reuses/extends `assets/sprites/props/` (rock_large/small, cactus_*, candy_stripe) plus new mesa/butte sprites as needed.

**2b. Parallax backdrop layers.** 2–3 receding silhouette layers (buttes/mesas) rendered as wide billboards/curved planes between the gameplay terrain and the existing candy-mountain backdrop. Each layer scrolls horizontally at a fraction of the world's lateral motion (`_path_lateral`-derived) for parallax, giving real depth. Layers are static meshes positioned far in −z; they shift x slightly with the path so the world feels like it curves through a landscape.

**2c. Atmospheric fog.** Add a `WorldEnvironment` to the gameplay SubViewport with built-in **distance fog** (`Environment.fog_enabled`, `fog_light_color` = the theme's horizon tint, density/start tuned so far hills + landmarks fade into haze before the mesh's far edge). This adds depth and hides the terrain mesh's far cutoff. Mobile-safe.

### 3. Per-terrain theming

A `TerrainTheme` definition keyed to `LevelDef.terrain` (existing values: `"frontier"`, plus `mine`/`farm`/`mountain`). Implemented as a `const Dictionary` in a small `terrain_themes.gd` (or a `.tres` resource if it needs editing later — start with a script dictionary for simplicity), each entry bundling:

- `ground_albedo`, `ground_detail` texture paths
- `vertex_tint_low` / `vertex_tint_high` colors (valley/ridge)
- `fog_color`, `fog_density`
- `landmark_set`: list of prop slugs + spawn weights/density
- `backdrop_layers`: ordered list of silhouette textures + parallax factors
- `scatter_density`: ground-cover amount (kept low for the photoreal B look)

`level_3d._ready` reads `_level_def.terrain` → looks up the theme → applies ground material params, fog, landmark spawn config, backdrop layers. **Frontier** is fully authored first; the other three are stub entries (fall back to frontier) populated as data later.

## Data flow

```
LevelDef.terrain ("frontier")
        │
        ▼
TERRAIN_THEMES["frontier"]  ── ground tex/tint, fog, landmark set, backdrops
        │
level_3d._ready ─► _apply_terrain_theme(theme)
        ├─ ground StandardMaterial3D: albedo+detail+vertex_color
        ├─ WorldEnvironment fog color/density
        ├─ landmark spawner config (density/slugs)
        └─ backdrop layer nodes under _world_root / far -z
_build_world_terrain ─► multi-octave _hill_y + baked per-vertex tint
```

## Files

- `godot/scripts/level_3d.gd` — `_hill_y` (multi-octave), `_build_world_terrain` (vertex tint + detail material), new `_apply_terrain_theme`, landmark spawner, backdrop builder, `WorldEnvironment` setup.
- `godot/scripts/terrain_themes.gd` (new) — the `TERRAIN_THEMES` dictionary.
- `godot/assets/sprites/props/` and/or `assets/textures/` — new mesa/butte/backdrop art + a ground detail tile (generate via the existing NB-Pro / PIL pipelines).

## Phasing

1. **Surface (B core):** `WorldEnvironment` fog + multi-octave hills + ground detail layer + baked per-vertex tint. Biggest immediate jump; one terrain (frontier).
2. **Landmarks & depth (C):** landmark prop spawner + parallax backdrop layers.
3. **Per-terrain themes:** the `TerrainTheme` structure wired in phase 1's apply path; phases 1–2 read `frontier`; phase 3 authors `mine`/`farm`/`mountain` sets.

(The `TerrainTheme` indirection is introduced in phase 1 even though only `frontier` is filled, so phases 2–3 slot in without rework.)

## Testing / verification

- `sp1-screenshot` captures of `level_3d.tscn` after each phase for the surface/fog/landmark look (static-harness caveat: gameplay motion/parallax can't be seen headless — those are device checks). Use the busy-camera + force-PLAYING debug-preview pattern (temporary, removed before commit) to frame the terrain for stills.
- On-device (Firebase) for fog depth at the real frame rate, parallax motion, and per-terrain swaps.
- GUT stays green (428/429; the 1 pre-existing weather failure is unrelated).
- Performance watch: landmark/backdrop counts bounded + distance-culled; no per-frame mesh rebuilds; re-profile at high posse.

## Risks

- **Mobile shader white-rect:** mitigated by built-ins only; if the detail layer or vertex-color path misbehaves on-device, fall back to baked variation in the albedo texture.
- **Fog vs the candy sky:** fog color must blend to the existing sky/mountain backdrop, not gray it out; tune per theme.
- **Photoreal-vs-candy tension (dir B):** keep the *ground* earthy/realistic but the *landmarks/sky* candy — the contrast is intentional; watch that the ground doesn't read as a different game from the candy elements.
