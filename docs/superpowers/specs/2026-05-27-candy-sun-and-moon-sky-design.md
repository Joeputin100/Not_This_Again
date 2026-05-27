# Candy-Western Sun and Moon Sky — Design

**Date:** 2026-05-27
**Status:** Approved by user 2026-05-27 (pending spec review)
**Author:** Brainstormed inline with user

## Why

The current SP1 scene's sky is a flat coloured rectangle (`Environment.background_color`). The four lighting presets (daylight, sunset, moonlight, overcast) change its hue, but there is no visible *light source*. Now that blob-shadows are positioned in the world (commit `21beed8`), it is visually wrong for shadows to point toward the viewer without a sun or moon visible in the sky opposite them.

This spec adds a pair of in-world candy-themed sky bodies — a **lollipop sun** and a **half-bitten cookie moon** — placed in the direction the light is coming from, with appropriate procedural shaders that work on the Mobile renderer (GLES-compatible).

## Goals

- Show a visible light source in the sky that matches the shadow direction for each lighting preset, so the scene reads as physically coherent.
- Keep the candy-Western tone of [[project_candy_theme]] — the bodies are *candy*, not photoreal celestial objects.
- All work on the Mobile renderer (no Forward+, no shadow-map dependencies).
- Subtle living motion (gentle rotation, sugar-shimmer, breathing glow) to avoid stiff painted-shape look.
- Shaders are procedural (no texture assets) so they ship inside the APK at near-zero cost.

## Non-Goals

- A full day/night cycle (the sun moving across the sky over real time). Position is driven by the lighting *preset*, not a clock.
- Reactive-to-gameplay variations (sun spinning faster during action, etc.).
- Real shadow-casting from the sun. Blob-shadows handle that.
- Replacing the existing `Environment.background_color` — the sky bodies sit IN FRONT of that flat colour, not instead of it.

## Visual Specification

### Sun — lollipop

- A circular **candy disc**, ~25% of the visible sky height.
- Disc texture (procedural in shader): caramel-and-butterscotch swirl pinwheel — 6 alternating wedges of two amber tones. The whole pattern rotates ~5°/sec.
- A glossy "sugar shimmer" highlight: a single bright streak that drifts across the disc surface (independent of the swirl rotation, slower phase ~3.5 sec/cycle).
- A glass-caramel **stick** runs from the bottom of the disc down to where it meets the ground at the horizon — a thin tall quad with a vertical colour gradient (warm amber base, glass-clear top) plus one moving vertical highlight column to suggest hard-candy refraction.
- Position: at the horizon in the **direction opposite** the lighting preset's `shadow_offset.xz`. Disc height in the sky depends on preset (daylight = high overhead-ish, sunset = low/grazing the horizon, moonlight = off-screen below horizon).
- Palette:
  - daylight: bright butterscotch (`#F5C66B` + `#E6A33A`)
  - sunset: orange-red toffee (`#F26A2E` + `#B83E1B`)
  - overcast: pale dusty caramel (`#E8C99C` + `#B89A6F`), low energy
  - moonlight: not rendered

### Moon — half-bitten cookie

- A circular **white-chocolate cookie disc**, ~20% of sky height.
- Disc texture (procedural): warm cream base with small darker speckles (hashed noise, baked at TIME=0 so speckles don't shimmer). Tint is white-chocolate cream (`#F4E6C7`).
- A **bite arc** carved out of one side: a circular discard mask whose center sits outside the disc edge — the arc that survives looks like a bite mark. Bite depth is a configurable shader uniform `bite_depth` (0.0 = no bite / full circle, 1.0 = nearly half-eaten).
- Faint **sub-surface breath**: the disc body mixes 15% with a warm amber (`#E0B070`) on a ~3 sec sine cycle, giving the appearance of being faintly lit from inside.
- Position: also opposite the lighting preset's `shadow_offset.xz` direction (the moon is the light source for the moonlight preset). High in the sky for moonlight, off-screen for daylight/sunset/overcast.
- No stick.

## Architecture

### Scene tree

A new `Sky` Node3D is added under `ViewportContainer/Viewport3D`, beside `KeyLight` and `WorldEnvironment`:

```
Viewport3D
├── Camera3D
├── KeyLight
├── FillLight
├── WorldEnvironment
├── Sky                         (NEW — Node3D)
│   ├── SunDisc                 (MeshInstance3D, QuadMesh, sun_lollipop.gdshader)
│   ├── SunStick                (MeshInstance3D, QuadMesh, sun_stick.gdshader)
│   └── MoonDisc                (MeshInstance3D, QuadMesh, moon_cookie.gdshader)
├── Grass + GrassShadows + crowd
```

Each body is a flat `QuadMesh` with y-axis billboard behavior already proven in the flipbook shader — for sky bodies the billboard is even simpler because they never move XY-relative to the camera within a preset.

### Shaders

All three shaders are spatial shaders with:

```
render_mode unshaded, blend_mix, cull_disabled, depth_draw_opaque;
```

`render_priority = -20` so they sort behind everything else (grass shadows at -5, crowd at +10).

**`shaders/sun_lollipop.gdshader`** — single textured-less disc.
- Inputs (uniforms): `swirl_color_a`, `swirl_color_b`, `rotation_speed = 5°/sec`, `shimmer_speed = 1.0/3.5sec`.
- Fragment:
  - Compute polar coords from UV centered at (0.5, 0.5). Reject pixels outside a radius of 0.48 (slight inner-disc to keep the silhouette clean).
  - `angle = atan(uv.y - 0.5, uv.x - 0.5) + TIME * rotation_speed`
  - `wedge = step(0.5, fract(angle * 3.0 / PI))` → alternating swirl
  - `base = mix(swirl_color_a, swirl_color_b, wedge)`
  - Shimmer: a single moving Gaussian highlight along an axis that drifts on the disc — `shimmer = exp(-pow((local_axis - TIME * shimmer_speed) * 4.0, 2.0))`
  - Output `base + shimmer * 0.4`.
- ~15 LOC fragment.

**`shaders/sun_stick.gdshader`** — vertical thin quad.
- Inputs: `stick_color_base` (warm amber), `stick_color_tip` (clear / disc colour for blend), `highlight_drift_speed = 1.0/4sec`.
- Fragment:
  - Vertical gradient from base at v=1 to tip at v=0
  - One moving highlight column: `highlight = smoothstep(0.42, 0.5, abs(uv.x - 0.5 - sin(TIME * speed) * 0.08))` (a 16%-wide bright stripe drifting horizontally)
  - Output `mix(base, tip, uv.y) + highlight * 0.5`.
- ~10 LOC.

**`shaders/moon_cookie.gdshader`** — single disc.
- Inputs: `cookie_color_cream`, `cookie_color_speckle`, `glow_amber`, `bite_depth = 0.4`, `bite_dir = vec2(0.7, 0.7)` (normalized), `breath_speed = 1.0/3sec`.
- Fragment:
  - Reject pixels outside disc radius 0.48.
  - Bite mask: compute `bite_center = vec2(0.5, 0.5) + bite_dir * (0.48 + 0.48 * (1.0 - bite_depth))`. If `distance(uv, bite_center) < 0.5`, discard.
  - Speckle: 3-octave hash noise, frozen at TIME=0 — sampled per-fragment but the hash takes only UV, so it's stable across frames.
  - `base = mix(cream, speckle_color, hash_noise * 0.2)`
  - Breath: `final = mix(base, glow_amber, 0.15 + 0.075 * sin(TIME * 2.0 * PI / 3.0))`
- ~25 LOC.

### GDScript

A new autoload-style helper isn't needed — the sky just gets a thin manager:

**`godot/scripts/sky_bodies.gd`** (extends Node3D, attached to the `Sky` node):
- Holds references to its three children.
- Method `apply_preset(preset: Dictionary, shadow_offset: Vector3, camera: Camera3D)`:
  - Compute `light_xz = -shadow_offset.xz.normalized() * SKY_DISTANCE` (default `SKY_DISTANCE = 50.0`).
  - For sun: position SunDisc at `(light_xz.x, sun_height_for_preset, light_xz.y)`. Position SunStick from the disc's bottom down to ground level at the same XZ.
  - For moon: position MoonDisc at `(light_xz.x, moon_height_for_preset, light_xz.y)`.
  - Set visibility per preset (`SunDisc.visible = preset != moonlight`, `MoonDisc.visible = preset == moonlight`).
  - Push preset's `swirl_color_a/b` (sun) or `bite_depth` + `glow_amber` (moon) into the materials.
- Method `_process(dt)`: nothing — animation lives entirely in shader TIME. The script just orients the quads to face the camera once at apply_preset (y-axis billboard so they always face camera).

**Wiring into `sp1_crowd_viewer.gd._apply_lighting_preset()`:**
- After the existing key_light/world_env updates, call `$ViewportContainer/Viewport3D/Sky.apply_preset(p, p["shadow_offset"], camera_3d)`.
- Each `LIGHTING_PRESETS` entry gains a few keys: `sun_visible`, `sun_height`, `sun_swirl_a`, `sun_swirl_b`, `moon_visible`, `moon_height`, `moon_bite_depth`. (For overcast: sun visible but dim, moon hidden.)

### Position math (sun stick to horizon)

The sun stick is a vertical quad (`QuadMesh` with `size = Vector2(stick_width, stick_height)`). It hangs *down* from the disc to the ground:

- `disc_pos = Vector3(light_xz.x, sun_height, light_xz.z)`
- `stick_height = sun_height - disc_radius`  (so the top of the stick meets the bottom of the disc, the bottom touches ground y=0)
- `stick_center_y = stick_height / 2`
- `stick_center = Vector3(light_xz.x, stick_center_y, light_xz.z)`
- Stick quad faces the camera via y-axis billboard; the quad is `stick_width` wide and `stick_height` tall (so quad spans y=0..stick_height in local space, sits at y=stick_center_y in world space).

### Distance and parallax

`SKY_DISTANCE = 50.0` puts the sky bodies far enough that:
- They don't intersect or interact with the crowd (max crowd spawn radius is 5m).
- They still respond to camera FOV correctly (perspective makes them shrink slightly as the camera moves, providing subtle "look at the horizon" parallax).

For now the sky bodies are fixed in world space — they DO NOT follow the camera. If we later want them to feel infinitely far away (skybox-style) we can re-parent them to the Camera3D, but for the SP1 viewer's small d-pad-driven motion (camera doesn't move, only crowd) this isn't necessary.

### Concrete sizes and heights

Quad sizes (at SKY_DISTANCE = 50.0, picked so each body occupies the stated fraction of vertical sky at FOV 50°):

| Body      | Quad size (W × H, world units) |
|-----------|--------------------------------|
| SunDisc   | 12 × 12                        |
| SunStick  | 0.6 × (sun_height)             |
| MoonDisc  | 9 × 9                          |

Sun height (Y of the disc center) per preset:

| Preset    | sun_height | sun_visible |
|-----------|------------|-------------|
| daylight  | 18         | true        |
| sunset    | 7          | true        |
| overcast  | 14         | true (dim)  |
| moonlight | —          | false       |

Moon height per preset:

| Preset    | moon_height | moon_visible |
|-----------|-------------|--------------|
| moonlight | 16          | true         |
| others    | —           | false        |

### Disc orientation (face the camera, not the world)

Each disc quad orients so its face normal points at the camera, not just its world-Y axis. With sun_height = 18 and camera near eye-level (~y=8), a Y-axis-only billboard would show the disc edge-on. Instead, on each `apply_preset()` call:

```gdscript
sun_disc.look_at(camera.global_position, Vector3.UP, true)
moon_disc.look_at(camera.global_position, Vector3.UP, true)
```

(`use_model_front = true` so the quad's +Z face — its visible side — points at the camera.) The stick keeps its world-vertical orientation but still rotates around Y to face the camera so its highlight stripe lines up with the disc.

Since the camera is fixed in the SP1 viewer, this `look_at` call only happens at preset switch (cheap).

## Data Flow

```
user picks lighting preset
   ↓
LightSelect.item_selected
   ↓
_apply_lighting_preset(name)
   ↓
   ├── set KeyLight (existing)
   ├── set WorldEnvironment (existing)
   ├── set FlipbookCrowd shadow params (existing)
   └── Sky.apply_preset(preset, shadow_offset, camera)   ← NEW
         ↓
         ├── Compute light_xz from -shadow_offset.normalized
         ├── Position SunDisc, SunStick, MoonDisc
         ├── Toggle visibility per preset
         └── Push palette uniforms into materials
   ↓
shader TIME drives subsequent animation (no GDScript per-frame work)
```

## Error Handling

- If `shadow_offset.xz` is zero (overcast preset), default to `Vector3(0, sun_height, -1)` so the sun is "directly behind the camera" — visible, neutral position.
- All shader uniforms have safe defaults so a freshly created `Sky` node renders something sensible even before any preset is applied.

## Testing

Local screenshot-via-vision pipeline (the `sp1-screenshot` skill) for each preset:

1. **Daylight**: sun visible upper-area, butterscotch swirl, gentle rotation visible in 2-second screenshot diff.
2. **Sunset**: sun low on horizon, orange-red, long stick to ground.
3. **Moonlight**: cookie moon visible, sun hidden, bite arc clearly readable.
4. **Overcast**: pale low-energy sun visible, no moon, no shimmer.
5. **D-pad movement**: confirm sun/moon do NOT shift screen position when crowd moves (they're at world distance 50, crowd moves a few meters — should be near-static in frame).

Pass criterion: in every preset, the position of the visible body matches the direction OPPOSITE to where the shadows fall on the crowd.

## File List

New files:
- `godot/shaders/sun_lollipop.gdshader`
- `godot/shaders/sun_stick.gdshader`
- `godot/shaders/moon_cookie.gdshader`
- `godot/scripts/sky_bodies.gd`

Modified files:
- `godot/scenes/sp1_crowd_viewer.tscn` — add Sky node + 3 child MeshInstance3Ds + materials
- `godot/scripts/sp1_crowd_viewer.gd` — expand `LIGHTING_PRESETS` with new keys; call `Sky.apply_preset()` from `_apply_lighting_preset()`

## Open Questions

None remaining — all decisions captured above. Future work (full day/night cycle, gameplay-reactive sky) explicitly deferred per Non-Goals.
