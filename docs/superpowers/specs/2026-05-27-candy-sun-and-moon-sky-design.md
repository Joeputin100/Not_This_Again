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
- Both bodies have **subtle faces** (eyes + small mouth) — Candy Crush level-selector vibe.
- Both bodies are **tappable**: tap → scale-bounce animation + soft candy "boop" sound.
- Sky bodies feel **infinitely far away** with parallax — follow the camera at a fractional rate so they shift slightly as the camera turns, but never drift off-screen as the camera moves through the world.
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
- A **subtle face** rendered on top of the swirl — two small dark-brown dot eyes (~3% disc radius each) and a tiny upward-curving toffee-brown smile. The face is **counter-rotated** so it stays upright while the swirl spins underneath. Eyes blink every ~6 seconds (eye texture is a vertically scaled dot — height collapses for 0.12 sec then returns).
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
- A **subtle sleepy face** opposite the bite — two half-closed (horizontal-line) eyes and a small mellow smile (slightly downturned at the ends, "drowsy" rather than "frowning"). Same brown as the cookie speckle so it reads as baked-in. Face stays UPRIGHT (no counter-rotation needed — the moon doesn't rotate). Eyes do a slow blink every ~8 seconds.
- Position: also opposite the lighting preset's `shadow_offset.xz` direction (the moon is the light source for the moonlight preset). High in the sky for moonlight, off-screen for daylight/sunset/overcast.
- No stick.

### Tap interaction (both bodies)

- A tap (or mouse click) on either body triggers a **bounce animation**: the disc scales rapidly from 1.0 → 1.15× over 80 ms, then springs back to 1.0× over 220 ms via `ease-out-back` (overshoots 0.97× momentarily). Total duration ~300 ms. This matches the Candy Crush level-selector feel — a satisfying "you touched candy" tactile reaction.
- A simultaneous **tap sound** plays: a soft candy "boop" (short pitched chime with a wrapper-crinkle attack). Same sound for sun and moon, pitched up a semitone for the moon to differentiate. Source: generated via the ElevenLabs SFX pipeline (`reference_elevenlabs_vo` — paid tier active 2026-05-21), saved as `godot/assets/sfx/candy_tap.ogg`.
- Tap detection: each body has an invisible Area3D child with a CollisionShape3D sized to match the disc's visible bounds. Touch input is routed via Godot's standard `_input_event` signal on the Area3D (the Camera3D physics pick mode is enabled). Multi-touch friendly — taps don't queue, each one independently retriggers the bounce from start.
- The bounce animation does NOT interrupt the swirl rotation, shimmer, or breath cycles — those continue in the shader independently. Bounce is a pure Node3D scale animation in GDScript.

## Architecture

### Scene tree

A new `Sky` Node3D is added as a sibling of Camera3D under Viewport3D (NOT parented to Camera3D — that would inherit camera rotation, which we don't want). Sky's world position is updated each frame to track the camera at a fractional rate (parallax). Bodies keep their local positions within Sky constant per preset.

```
Viewport3D
├── Camera3D                    (existing — pitch now driven by Camera-tilt slider)
├── Sky                         (NEW — Node3D, position tracks camera at 0.85x)
│   ├── SunDisc                 (MeshInstance3D + Area3D + AudioStreamPlayer3D)
│   │   ├── DiscMesh            (MeshInstance3D, QuadMesh, sun_lollipop.gdshader)
│   │   ├── TapArea             (Area3D + CollisionShape3D, disc-sized)
│   │   └── TapSfx              (AudioStreamPlayer3D, candy_tap.ogg)
│   ├── SunStick                (MeshInstance3D, QuadMesh, sun_stick.gdshader)
│   └── MoonDisc                (MeshInstance3D + Area3D + AudioStreamPlayer3D)
│       ├── DiscMesh            (... moon_cookie.gdshader)
│       ├── TapArea
│       └── TapSfx              (candy_tap.ogg, pitch +1 semitone)
├── KeyLight
├── FillLight
├── WorldEnvironment
├── Grass + GrassShadows + crowd
```

Each body is a flat `QuadMesh` with full `look_at(camera)` orientation (not Y-axis-only) so the disc face always points at the camera even when the camera tilts up to look at high overhead sun.

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

**`godot/scripts/sky_bodies.gd`** (extends Node3D, attached to the `Sky` node):

- Holds references to its three children (SunDisc, SunStick, MoonDisc) and the parent camera.
- Method `apply_preset(preset: Dictionary, shadow_offset: Vector3, camera: Camera3D)`:
  - Compute `light_xz = -shadow_offset.xz.normalized() * SKY_DISTANCE` (default `SKY_DISTANCE = 50.0`).
  - For sun: set SunDisc.position to `Vector3(light_xz.x, sun_height_for_preset, light_xz.y)` (local position within Sky node).
  - Position SunStick from the disc's bottom down to ground level at the same XZ.
  - For moon: set MoonDisc.position similarly.
  - Set visibility per preset (`SunDisc.visible = preset != moonlight`, `MoonDisc.visible = preset == moonlight`).
  - Push preset's `swirl_color_a/b` (sun) or `bite_depth` + `glow_amber` (moon) into the materials.
- Method `_process(dt)`:
  - Update parallax: `global_position = camera.global_position * (1.0 - PARALLAX_FACTOR)` (Sky is a Viewport3D sibling of Camera, so this directly sets its world position).
  - Re-orient each visible disc to face the camera: `disc.look_at(camera.global_position, Vector3.UP, true)`. Per-frame is fine — three look_at calls is negligible.
- Method `_bounce(body: Node3D)`:
  - Tween-driven scale animation: `body.scale = Vector3.ONE` → `Vector3.ONE * 1.15` (80 ms, ease out) → `Vector3.ONE * 0.97` (140 ms, ease in-out-back) → `Vector3.ONE` (80 ms, ease out). Uses one chained `Tween`.
- Signal handler: each TapArea's `input_event` signal connects to a local method that checks for `InputEventScreenTouch` (pressed) or `InputEventMouseButton` (pressed) and calls `_bounce(parent_body)` + plays the parent's `TapSfx`.

**Wiring into `sp1_crowd_viewer.gd._apply_lighting_preset()`:**
- After the existing key_light/world_env updates, call `$ViewportContainer/Viewport3D/Sky.apply_preset(p, p["shadow_offset"], camera_3d)`.
- Each `LIGHTING_PRESETS` entry gains a few keys: `sun_visible`, `sun_height`, `sun_swirl_a`, `sun_swirl_b`, `moon_visible`, `moon_height`, `moon_bite_depth`.

### Position math (sun stick to horizon)

The sun stick is a vertical quad (`QuadMesh` with `size = Vector2(stick_width, stick_height)`). It hangs *down* from the disc to the ground:

- `disc_pos = Vector3(light_xz.x, sun_height, light_xz.z)`
- `stick_height = sun_height - disc_radius`  (so the top of the stick meets the bottom of the disc, the bottom touches ground y=0)
- `stick_center_y = stick_height / 2`
- `stick_center = Vector3(light_xz.x, stick_center_y, light_xz.z)`
- Stick quad faces the camera via y-axis billboard; the quad is `stick_width` wide and `stick_height` tall (so quad spans y=0..stick_height in local space, sits at y=stick_center_y in world space).

### Distance and parallax

Each frame, `sky_bodies.gd._process()` sets the Sky node's world position to track the camera at a fractional rate:

```gdscript
const PARALLAX_FACTOR := 0.15  # 0 = painted-on, 1 = full-world (no parallax illusion)
global_position = camera.global_position * (1.0 - PARALLAX_FACTOR)
```

Net effect: as the camera moves forward 1 m, the Sky moves forward 0.85 m, so the sky bodies LAG the camera by 0.15 m. From the camera's screen-space POV, the sky bodies drift slightly OPPOSITE to camera motion — exactly the "distant objects move less" parallax cue.

- The Sky node DOES NOT inherit camera rotation (it's a sibling, not a child, of Camera3D). When the camera angle slider tilts up, the sky bodies stay anchored at their world positions, so tilting reveals more sky and brings the bodies into view.
- For the SP1 viewer where the camera position is currently fixed, this means PARALLAX only matters once the level scene gives the camera a chase-cam or similar moving rig. In the SP1 viewer itself the parallax math runs but has no visible effect — that's fine, it's a "free" feature for later.

Local offset of each body within Sky (defines screen direction):

- SunDisc: `Vector3(-sun_x_dir * SKY_DISTANCE, sun_height_for_preset, -sun_z_dir * SKY_DISTANCE)` where `(sun_x_dir, sun_z_dir) = normalize(-shadow_offset.xz)`.
- MoonDisc: same formula with moon heights.
- SunStick: between disc-bottom and horizon line at the same XZ direction.

`SKY_DISTANCE = 50.0` chosen so the bodies appear large enough at the specified quad sizes (12×12 for sun) without intersecting the camera's near plane.

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

### Camera angle slider

The current SP1 viewer points the camera roughly at the ground (look_at origin from a position above-and-back), so the field of view is mostly terrain — no sky is visible. To see the sun/moon, the camera needs to tilt up.

Add a **Camera angle slider** to the UI panel, between "Crowd size" and "Character size":

- Label: `"Camera tilt"`
- Range: `-60.0` (looking nearly straight down) to `+20.0` (tilted up into sky), default `-20.0` (current behavior — mostly ground, slim sky strip visible at top).
- Slider value = camera pitch in degrees relative to horizontal.
- Implementation: `sp1_crowd_viewer.gd` keeps the camera's XZ position fixed and rotates the camera node around its local X axis to set pitch. The look_at(origin) call is removed in favor of explicit pitch.

When tilted up (+20°), most of the visible frame becomes sky and the sun/moon are prominent. When tilted down (-60°), they're effectively off-screen above. The user can tune to taste per screenshot/recording.

### Audio

A single tap sound `godot/assets/sfx/candy_tap.ogg`:

- Generated via the ElevenLabs SFX API (see [[reference_elevenlabs_vo]] — paid tier active 2026-05-21).
- Prompt: "Short soft candy boop sound, ~300ms, like tapping a hard candy through cellophane wrapper, gentle high-pitched chime with a subtle crinkle attack."
- 22050 Hz mono, ogg-vorbis, ~10KB.
- Both bodies share the same file; the moon's `TapSfx` sets `pitch_scale = 1.06` (one semitone up) so sun and moon are distinguishable.
- Volume: -8 dB (subtle; the player should feel rewarded but not jarred).
- Generated once, committed to repo. The script `scripts/gen_candy_tap_sfx.py` (new) handles regeneration if the prompt changes.

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

Local screenshot-via-vision pipeline (the `sp1-screenshot` skill) for each preset, with camera tilt set to ~+10° so sky is prominent:

1. **Daylight**: sun visible upper-area, butterscotch swirl, gentle rotation visible in 2-second screenshot diff, face visible (eyes + smile readable). Stick clearly visible going down to horizon.
2. **Sunset**: sun low on horizon, orange-red, long stick to ground. Face still upright (counter-rotated against the swirl).
3. **Moonlight**: cookie moon visible, sun hidden, bite arc clearly readable, sleepy face opposite the bite.
4. **Overcast**: pale low-energy sun visible, no moon, no shimmer.
5. **Camera tilt slider sweep**: tilt from -60° to +20° — sky bodies stay anchored in world position, becoming visible as the camera tilts up.
6. **D-pad movement (parallax)**: hold a direction for 2 seconds — sky bodies should drift slightly opposite to the crowd's motion (parallax factor 0.15), but stay roughly centered in their preset direction.
7. **Tap interaction**: tap each visible body — bounce animation (max scale ~1.15) visible in screenshot, tap sound audible.
8. **Eye blink**: 10-second screenshot diff captures at least one blink cycle on each body.

Pass criteria:
- In every preset, the visible body's screen position matches the direction OPPOSITE to where shadows fall on the crowd.
- Faces remain upright (sun face counter-rotates, moon face doesn't rotate).
- Tap → bounce + sound on each tap, no missed taps under multi-finger input.
- Parallax is perceptible but subtle (sky bodies move ~15% of camera distance).

## File List

New files:
- `godot/shaders/sun_lollipop.gdshader` — disc + swirl + shimmer + face
- `godot/shaders/sun_stick.gdshader` — vertical caramel-glass stick
- `godot/shaders/moon_cookie.gdshader` — disc + speckle + bite + face + breath
- `godot/scripts/sky_bodies.gd` — Sky node controller (preset, parallax, look_at, bounce)
- `godot/assets/sfx/candy_tap.ogg` — generated tap sound
- `scripts/gen_candy_tap_sfx.py` — ElevenLabs SFX generator (offline tool)

Modified files:
- `godot/scenes/sp1_crowd_viewer.tscn` — add Sky node + bodies + Area3D + AudioStreamPlayer3D; add "Camera tilt" slider
- `godot/scripts/sp1_crowd_viewer.gd` — expand `LIGHTING_PRESETS`; call `Sky.apply_preset()`; add camera tilt slider handler; remove `look_at(origin)` in favor of explicit pitch

## Open Questions

None remaining — all decisions captured above. Future work (full day/night cycle, gameplay-reactive sky) explicitly deferred per Non-Goals.

## Pending follow-ups (NOT in this spec)

These came up during brainstorming and are tracked separately:

- **Pusher atlas size normalization** — Veo rendered pusher clips at inconsistent figure sizes, so blob-shadows match large pushers only. Fix is in `tools/build_atlas.py`: detect figure bbox per clip (union across frames) and scale each clip so the figure occupies a fixed cell fraction (~70%). Persist the computed scale into each `.atlas.json` so Godot can also use it for the `CHARACTER_FOOT_Y` calculation (replacing the hand-measured dict in `sp1_crowd_viewer.gd`).
