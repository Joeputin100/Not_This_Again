# Realistic Ground Terrain — Design

**Date:** 2026-06-05
**Status:** Approved direction (Approach A) — pending spec review
**Goal:** Replace the gameplay ground's obviously-tiled flat dirt ("looks like it's from 1990") with realistic, varied natural ground — a believable *surface* plus a worn central **trail**, dressed **shoulders**, a wooden **boardwalk** (frontier), and **scatter** (grass/brush/rock/cactus/tumbleweed) — **authored distinctly per level** via the existing `TerrainTheme` system. All four terrains (frontier / mine / farm / mountain) get their own look in this build.

This realizes §1b (surface variation) and §2a (landmark/scatter) of the 2026-06-04 natural-terrain spec, which shipped the *shape* (rolling hills + fog + valley/ridge tint) but never landed the *surface*.

---

## Constraints (hard)

- **Android mobile renderer white-rects custom spatial (3D) shaders.** Use ONLY built-in `StandardMaterial3D` (incl. its detail-layer + vertex-color paths), `MultiMesh`, baked vertex data, and decals. The one proven on-device exception is `grass_field.gdshader` (SP1) — may be used for sparse grass but is not required.
- Gameplay renders in `Terrain3D/SubViewport` (1080×1920), camera fov KEEP_WIDTH, dynamic pitch CALM(−25°)↔BUSY(−55°), two `DirectionalLight3D`s.
- The static world wraps every `PATH_PATTERN_LEN` (140) — anything baked into geometry/vertex color must stay **periodic in z** over 140 so the wrap is seamless (`TerrainThemes.hill_height`/`mottle` already are; `FastNoiseLite` would NOT be).
- Performance is tight at large posse (`CROWD_RENDER_CAP=1500`). Scatter/landmarks must be `MultiMesh` (or pooled), bounded + distance-culled, and must **not rebuild per frame**.

## Architecture

Extend the existing `TerrainThemes` (`godot/scripts/terrain_themes.gd`) so one theme dictionary drives every ground piece, and `level_3d` reads `_level_def.terrain` once to build them. New per-theme keys (added alongside the current `ground_albedo`/`ground_detail`/tints/fog):

```
ground_albedo, ground_normal, ground_detail, ground_detail_normal   # surface
ground_uv_tile          # base tiling (units/repeat) — larger = less obvious repeat
macro_strength          # how strong the baked vertex macro-variation is
trail_albedo, trail_normal, trail_half_width   # worn central trail (null = no trail)
boardwalk: { side: "right"|"left"|null, albedo, width }   # plank walk (frontier only)
scatter: [ { slug, density, side: "shoulder"|"both", scale_range, y_align } ]  # MultiMesh sets
```

`level_3d._apply_terrain_theme(theme)` (exists) gains: build trail mesh, build boardwalk, build scatter MultiMeshes. `_build_world_terrain` keeps the hill mesh but swaps the material per theme + boosts the baked macro-variation. Everything parents under `_world_root` so it scrolls/wraps with the world.

## Components

### 1. Realistic surface (the core fix)
- **Per-terrain albedo + normal**, organic (embedded pebbles/cracks/sand for frontier; gravel/ore for mine; soil/grass-fleck for farm; snow-over-rock for mountain), tiled at `ground_uv_tile` **larger** than today's 13 so the repeat recedes.
- **Strong baked per-vertex macro-variation:** boost `TerrainThemes.mottle` amplitude (controlled by `macro_strength`) so large light/dark earth blotches break the tile grid — the single biggest "not one flat tile" win, free at runtime (baked once via `SurfaceTool.set_color` + `vertex_color_use_as_albedo`).
- **Detail layer:** `detail_enabled` + `detail_albedo`/`detail_normal` at higher tiling via `detail_uv_layer=UV2` for close-up grit. Built-in, mobile-safe.
- **Kill the center seam:** offset/adjust base UVs so there's no hard line down the middle of the path.

### 2. Worn trail + shoulders
- A central **trail ribbon mesh** (its own `StandardMaterial3D`, `trail_albedo`+`trail_normal`, slightly darker/sunken, wheel-rutted), laid over the earth down the posse's lane, width `trail_half_width`, riding the hills (reuses the level-select `_build_trail_mesh` technique). `null` trail → terrains with no distinct path (e.g. open mountain) just show ground.
- The ground beyond `trail_half_width` is the **shoulder** — the placement zone for scatter + boardwalk.

### 3. Wooden boardwalk (frontier)
- A plank-walk **strip mesh** along the **right shoulder** (between the buildings and the trail), `boardwalk.albedo` wood-plank texture, width `boardwalk.width`, riding the hills. Frontier only (`boardwalk.side="right"`); other themes set `side=null`.

### 4. Scatter (MultiMesh, shoulder-placed, distance-culled)
- Each theme's `scatter` list spawns a `MultiMesh` per slug (billboard `QuadMesh` for sprites; existing prop art). Instances placed on the shoulder(s) by `density`, at deterministic positions seeded from `(slug, cell)` so the wrap is seamless, scrolling with `_world_root`. Bounded instance count + distance-cull beyond the fog line; never rebuilt per frame. **Non-colliding decor** — distinct from the gameplay hazard cactus/bull/coop, which keep their roles.

### 5. Per-terrain theming — all four authored

| Level | Terrain | Surface | Trail | Boardwalk | Scatter set |
|---|---|---|---|---|---|
| 1 FRONTIER STANDOFF | frontier | dry sun-baked earth: pebbles, cracks, sand drifts | worn wheel-rut dirt trail | **right shoulder** | grass tufts, dry brush (scrub), rocks, cactus, tumbleweed |
| 2 MINE SHAFT MAYHEM | mine | dusty gravel + ore-flecked rock, darker | rocky cart-track (wood ties) | none | boulders/ore rocks, support timbers, gravel piles, scrub |
| 3 FARM ROAD FRACAS | farm | living soil: grass-fleck dirt, greener | packed-dirt farm road | none | grass tufts (dense), weeds/crops, fence posts, hay/rocks |
| 4 MOUNTAIN PASS PERIL | mountain | snow-over-rock: white drifts on grey stone, icy patches | snow-packed path (faint) | none | snow drifts, pine trees, boulders, frosted rocks |

**Mountain has a cliff edge on the LEFT of the trail.** Instead of a normal left shoulder, the ground ends in a precipice that drops away to a snowy gorge / cloud haze — the pass runs along a ledge. Right shoulder stays normal (snowy ground + scatter). Implemented as a `cliff: { side: "left", drop_face, void_fill }` theme key: the terrain mesh's left half drops to a cliff face below trail level (extend `_terr_vertex`/the surface build to lower the left-of-trail vertices into a steep face), with a haze/void fill beyond. No left-shoulder scatter on mountain. (The Jawbreaker boss — slow-advancing — duels at the end of this ledge.) **Mountain puddles render as frozen ice** (frosted pale-cyan, mostly opaque, matte) instead of reflective blue water — a `puddle_style: "ice"` theme key consumed by `_make_puddle`.

Frontier is authored to the owner's detailed brief; the other three are authored to the table above (owner refines during spec review). Each falls back to frontier gracefully if a key is missing.

## Data flow

```
LevelDef.terrain ──► TerrainThemes.get_theme(name)
        │
level_3d._apply_terrain_theme(theme)
        ├─ ground StandardMaterial3D: albedo+normal+detail+vertex_color (macro_strength)
        ├─ _build_trail_mesh(trail_albedo, trail_half_width)          (if trail)
        ├─ _build_boardwalk(side, albedo, width)                       (if boardwalk)
        └─ _build_scatter(scatter[])  → MultiMesh per slug, culled
_build_world_terrain ──► hill mesh + boosted baked per-vertex macro-variation
```

## Files

- `godot/scripts/terrain_themes.gd` — new per-theme keys; author frontier/mine/farm/mountain; `macro_strength` into `mottle`.
- `godot/scripts/level_3d.gd` — `_apply_terrain_theme` (trail/boardwalk/scatter build), `_build_world_terrain` (per-theme material + boosted macro), new `_build_trail_mesh`/`_build_boardwalk`/`_build_scatter` (+ distance-cull in `_update_world_root`).
- `godot/resources/levels/level_1.tres` — set `terrain = "frontier"` explicitly.
- `godot/assets/textures/` + `godot/assets/sprites/props/` — new: per-terrain ground albedo+normal (frontier/mine/farm/mountain), trail albedo+normal (frontier/mine/farm), boardwalk planks, grass-tuft sprite, pine/snow-drift sprites; **reuse** existing rock/cactus/scrub/tumbleweed/fence art. Generated via NB-Pro / PIL (seamless-tileable) pipelines.
- `godot/test/test_terrain_themes.gd` — extend for the new pure theme math (macro_strength clamp, scatter placement determinism).

## Verification

- **GUT (pure logic):** `TerrainThemes` math — `mottle`/`macro_strength` stays in a sane clamp + periodic over 140; deterministic scatter-placement helper (same cell → same instances). Keep these as small static helpers.
- **sp1-screenshot:** capture `level_3d.tscn` per terrain (force the level's terrain via a temporary debug hook, removed before commit) — judge the real surface, trail, boardwalk, scatter for each of the four. This is the primary look gate (static-harness: motion/parallax/cull are device checks).
- **Device (Firebase):** all four terrains at real frame rate — surface read, trail, boardwalk, scatter density + culling, and big-posse FPS hold.

## Performance

- Scatter is `MultiMesh` (one draw per slug), instance counts bounded per theme, distance-culled to the fog line, positions baked once (no per-frame rebuild). Re-profile at high posse; if FPS dips, reduce densities / cull distance per theme (data-only change).

## Phasing (build order)

1. **Surface core** — per-theme material (albedo+normal+detail) + boosted baked macro-variation + seam fix, on frontier. Biggest immediate jump.
2. **Trail + shoulders + boardwalk** — frontier trail ribbon + right-shoulder boardwalk.
3. **Scatter system** — MultiMesh scatter + distance-cull, frontier set.
4. **Author the other three terrains** — mine / farm / mountain surfaces, trails, scatter sets (reuse the phase 1–3 machinery; data + art only).

## Out of scope

- The SP3 level editor. Data-driving the path/holes/puddles (stay as-is). Parallax backdrop layers + landmark mesas (natural-terrain spec §2b — separate follow-up). Colliding/hazard behavior for scatter (decor only).
