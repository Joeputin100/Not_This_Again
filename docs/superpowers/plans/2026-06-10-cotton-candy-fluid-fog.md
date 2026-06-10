# Cotton-Candy Fluid Fog (Level 4) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Real fluid-sim pink ground fog on Level 4 — wispy band, whole run with breathing density, perturbed by posse/outlaws/bullets/boss blast. Visual-only, debug-gated, device go/no-go.

**Architecture:** 4 low-res (192×108) canvas-shader sim passes + 1 display pass, ping-pong SubViewports, one Jacobi/frame (temporal amortization). `fluid_fog.gd` Node owns viewports + splat packing; pure helpers GUT-tested. Spec: `docs/superpowers/specs/2026-06-10-cotton-candy-fluid-fog-design.md`.

**Tech Stack:** Godot 4.6 canvas_item shaders (the chromakey-proven class), GUT on GitHub Actions only.

---

## Task 1: Pure helpers + tests — `fluid_fog.gd` statics
Create `godot/scripts/fluid_fog.gd` (Node; statics first), `godot/test/test_fluid_fog.gd`.
- `static density(distance: float) -> float` — 0.35 + 0.2·sin(distance/90) + boss ramp (param `boss_frac` 0..1 adds up to +0.35), clamped 0..0.9.
- `static pack_splats(cands: Array, max_n: int) -> Array` — cands `{uv: Vector2, vel: Vector2, radius: float, dye: float, prio: float}`; sort by prio desc, cap, return fixed-size arrays for uniforms.
- Tests: density bounds/ramp monotonic in boss_frac; packing caps at max_n keeping highest prio; uv passthrough.

## Task 2: The five shaders
Create `godot/assets/shaders/fluid_{velocity,divergence,pressure,dye}.gdshader` + `fluid_fog_display.gdshader`. Velocity stored 0.5-centered (`v=(rg-0.5)*VEL_SCALE`). Splat uniform arrays (16× vec2 pos, vec2 vel, float radius, float dye). Display: dye × smooth band mask (top fade at BAND_TOP_UV) × `density` uniform; palette mix(pale-rose, magenta, dye); alpha cap 0.55.

## Task 3: `fluid_fog.gd` runtime — viewports + frame loop
8 SubViewports (vel×2, prs×2, div, dye×2 — div single; display is a ColorRect on the UI layer). Per `_process`: swap roles, set `UPDATE_ONCE` in pass order, push uniforms (dt clamped, splat arrays, texel size). `enabled` setter tears down/builds. `add_splat_candidate()` buffer cleared per frame.

## Task 4: level_3d wiring + debug
Mountain-terrain-only instantiation; per frame feed: cowboy (prio 5), visible outlaws (prio 3), ≤6 bullets (prio 4, small radius, dye 0 — force only = tunnels), world-scroll ambient drift, Jawbreaker blast → one radius-30 splat (prio 10). Density from `_level_distance` + boss_frac. Debug menu "L4 FOG TEST" (`pending_fog_test`: level 4 jump with fog forced on). 

## Task 5: Browser look-dev page
`docs/superpowers/assets/fluid_fog_2026-06-10/fog_lookdev.html` — the demo solver + our band mask, pink palette, density slider, fake runner/outlaws/bullets. Serve via companion for owner tuning; bake tuned constants back into the display shader.

## Task 6: CI green + memory close-out.

**Device pass (owner):** FPS go/no-go, density/palette judgment, splat strengths.

## Self-review
Spec §3 passes→Tasks 2/3; splat cast+density→Tasks 1/4; §5 debug gate→Task 4; §6 look-dev→Task 5, GUT→Task 1. Types: `pack_splats` output consumed by Task 3 uniform push; `density(distance, boss_frac)` signature consistent Task 1/4. No placeholders. ✓
