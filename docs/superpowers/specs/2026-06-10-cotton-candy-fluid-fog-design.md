# Level-4 Cotton-Candy Fluid Fog — Design Spec

**Date:** 2026-06-10
**Status:** Owner decisions locked (placement/coverage/density). Build behind a debug toggle; final go/no-go on device (multi-pass RTT perf is unproven on the phone).
**Related:** task #78, `/home/projects/roguelike/webgl_effects_demo.html` (the fluid-orbs/portal Navier-Stokes reference), [[project_jawbreaker_boss]], [[feedback_perf_keep_polish]].

## 1. Concept

A **living pink cotton-candy ground fog** over the Level-4 mountain pass: a real 2D fluid simulation (the demo's solver) rendered as a screen-space band the posse wades through. Outlaws carve wakes, bullets punch tunnels, the posse pushes a bow-wave — the fog *reacts* to everything moving through it.

## 2. Owner decisions (locked 2026-06-10)

| Decision | Choice |
|---|---|
| Placement | **Ground-fog band** — lower portion of the screen where the posse runs |
| Coverage | **Whole run, varying density** — thin on open stretches, thick toward the boss; the level's signature |
| Thickness | **Wispy-translucent** — entities always readable through it; a reactive surface, never an obstruction |

## 3. Architecture (mobile-safe path)

All passes are **canvas_item shaders in SubViewports** (the proven class — chromakey/flipbook; spatial shaders white-rect on the mobile renderer). Sim at low res (**192×108**, RGBA8; velocity 0.5-centered signed encode).

**Temporal amortization:** one Jacobi pressure iteration **per frame** (converges over frames) instead of N per frame — fog is forgiving of slight compressibility, and it keeps the budget at **4 sim passes + 1 display** per frame:

1. `fluid_velocity.gdshader` — advect velocity + inject splat forces + subtract last frame's pressure gradient
2. `fluid_divergence.gdshader` — divergence of velocity
3. `fluid_pressure.gdshader` — ONE Jacobi step (reads previous pressure + divergence)
4. `fluid_dye.gdshader` — advect dye (the pink) + dye splats, mild dissipation
5. `fluid_fog_display.gdshader` — full-screen ColorRect under the HUD: dye × band-gradient mask × global density; pink palette (pale rose lit tops → deeper magenta in the thick)

Ping-pong = two SubViewports per field with roles swapped each frame (`UPDATE_ONCE` toggling); pass order = tree order.

**Splats:** up to **16/frame** packed into shader uniform arrays. Sources: cowboy (bow wave), on-screen outlaws, a sample of live bullets (strongest force, thin radius = tunnels), the Jawbreaker's blast (one huge radial splat). Screen-projection via `camera.unproject_position`, mapped into band UV. Velocity from per-entity frame delta + the world scroll (so the fog streams past even when entities idle).

**Density curve:** `density(distance)` = base 0.35 + slow sine swell ±0.2 + ramp to 0.9 in the boss approach/fight. Pure function, GUT-tested.

## 4. Gameplay neutrality

Visual only — no hit, speed, or AI changes. Wispy alpha cap (≤ ~0.55) keeps everything readable.

## 5. Scope guards

- **Mountain terrain only**, behind `FluidFog.enabled`; insta-kill switch if device FPS objects (the effect degrades to nothing — no fallback art in v1).
- Debug menu: **"L4 FOG TEST"** jump-in.
- Out (YAGNI): vorticity confinement, multi-band fog, other levels, fog-in-boss-arena-only variants, obstacles masking (entities are splats, not boundaries).

## 6. Verification

- GUT (CI): density curve; splat packing (cap at 16, nearest-to-camera priority, correct UV mapping math via a pure projector helper).
- Look-dev: a browser replica page (the demo's solver + our band mask/palette/splat cast) for owner tuning *before* the device pass.
- Device pass: the real go/no-go — FPS with 4 RTT passes + display on the phone GPU.
