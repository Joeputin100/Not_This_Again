# Candy Sun and Moon Sky Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a lollipop sun and half-bitten cookie moon as candy-Western sky bodies, positioned opposite the lighting preset's shadow direction, with subtle faces, tap-to-bounce interaction, candy "boop" sound, infinite-distance parallax, and a camera-tilt slider so the sky is visible in the SP1 viewer.

**Architecture:** Three procedural spatial shaders (sun_lollipop, sun_stick, moon_cookie) on flat QuadMeshes; one `Sky` Node3D controller that positions bodies per-preset, runs parallax in `_process`, and handles tap-bounce + SFX; scene additions to `sp1_crowd_viewer.tscn`. Sky is a Viewport3D sibling of Camera3D so rotation isolation is automatic — only its position tracks the camera (at 0.85× rate). Verification is visual via the `sp1-screenshot` skill plus on-device sideload.

**Tech Stack:** Godot 4.6.1 spatial shaders (GLES-compatible), GDScript, Godot Tween, AudioStreamPlayer3D, Area3D for input picking, ElevenLabs SFX API for audio generation.

**Reference docs:**
- Spec: `docs/superpowers/specs/2026-05-27-candy-sun-and-moon-sky-design.md`
- Screenshot skill: `.claude/skills/sp1-screenshot/SKILL.md`
- Existing flipbook pattern to mirror: `godot/shaders/flipbook.gdshader`, `godot/scripts/flipbook_crowd.gd`

---

## Verification approach

Game-project caveat: shaders and scene composition can't be unit-tested in the traditional sense — they're visual. Each task that produces a visual change includes a **Screenshot verify** step that uses the local `sp1-screenshot` skill to render the SP1 viewer and inspect the result with Claude vision. Final sideload-to-device confirmation is the last task.

For the small amount of pure-logic code (`sky_bodies.gd`'s preset math, parallax formula, bounce tween parameters), inline sanity checks via debug-prints rather than a full GUT/godot-test setup — this project has no existing test harness and adding one is out of scope.

---

## File Structure

**New files:**
- `godot/shaders/sun_lollipop.gdshader` — sun disc (swirl + shimmer + face + blink + spin_boost)
- `godot/shaders/sun_stick.gdshader` — vertical caramel-glass stick
- `godot/shaders/moon_cookie.gdshader` — moon disc (cookie + bite + face + breath + blink + wink_override)
- `godot/scripts/sky_bodies.gd` — Sky node controller (preset, parallax, look_at, variant-aware bounce, SFX routing)
- `godot/assets/sfx/sky_taps/sun_a_chime.ogg`, `sun_b_stick.ogg`, `sun_c_sparkle.ogg`
- `godot/assets/sfx/sky_taps/moon_a_squish.ogg`, `moon_b_crunch.ogg`, `moon_c_tink.ogg`
- `scripts/gen_candy_tap_sfx.py` — variant-aware ElevenLabs SFX generator (offline tool, not shipped to APK)

**Modified files:**
- `godot/scenes/sp1_crowd_viewer.tscn` — add Sky node + 3 bodies + Area3D + AudioStreamPlayer3D; add "Camera tilt" slider to UI
- `godot/scripts/sp1_crowd_viewer.gd` — expand `LIGHTING_PRESETS` with sun/moon keys; call `Sky.apply_preset()`; add camera-tilt slider handler; replace `look_at(origin)` with explicit pitch

---

### Task 1: Generate the six candy tap sounds (variant-aware)

**Files:**
- Create: `scripts/gen_candy_tap_sfx.py`
- Create: 6 files under `godot/assets/sfx/sky_taps/`

- [ ] **Step 1: Write the variant-aware SFX generator script**

```python
#!/usr/bin/env python3
"""Generate one of six candy-tap SFX variants via the ElevenLabs SFX API.

Usage:
  python3 scripts/gen_candy_tap_sfx.py --variant sun_a_chime
  python3 scripts/gen_candy_tap_sfx.py --all   # generate all 6 in one run

Re-run only if the prompt or output settings change — the .ogg files
are committed to the repo, not regenerated each build. Requires
ELEVENLABS_API_KEY in env (or pulled from gcloud secret
`elevenlabs-api-key` per reference_elevenlabs_vo memory).
"""
import argparse
import os
import subprocess
import sys
import time
from pathlib import Path

VARIANTS = {
    "sun_a_chime": {
        "prompt": ("Short bright hard candy chime, ~300ms, single clean "
                   "high-pitched ting like tapping a glass-clear lollipop, "
                   "gentle decay"),
        "duration": 0.4,
    },
    "sun_b_stick": {
        "prompt": ("Short woody tap on caramel candy stick, ~300ms, lower "
                   "pitched with a soft thunk attack, like flicking a "
                   "sucker stick"),
        "duration": 0.4,
    },
    "sun_c_sparkle": {
        "prompt": ("Tiny crystalline butterscotch sparkle, ~250ms, very "
                   "short bright shimmery ting with quick decay, sugar-"
                   "glass crystal feel"),
        "duration": 0.3,
    },
    "moon_a_squish": {
        "prompt": ("Soft padded marshmallow squish, ~350ms, low gentle "
                   "thud with subtle airy puff, like pressing into a "
                   "marshmallow"),
        "duration": 0.4,
    },
    "moon_b_crunch": {
        "prompt": ("Short dry cookie crunch, ~300ms, single crisp brittle "
                   "crack, like biting into a white chocolate cookie"),
        "duration": 0.4,
    },
    "moon_c_tink": {
        "prompt": ("Gentle white chocolate tink, ~350ms, mellow bell-like "
                   "tone slightly damped, smooth and creamy"),
        "duration": 0.4,
    },
}
OUT_DIR = Path("godot/assets/sfx/sky_taps")
PROMPT_INFLUENCE = 0.5  # 0=more variable, 1=stick close to prompt


def fetch_api_key() -> str:
    key = os.environ.get("ELEVENLABS_API_KEY")
    if key:
        return key
    proc = subprocess.run(
        ["gcloud", "secrets", "versions", "access", "latest",
         "--secret=elevenlabs-api-key", "--format=get(payload.data)"],
        capture_output=True, text=True, check=True,
    )
    import base64
    return base64.b64decode(
        proc.stdout.strip().replace("_", "/").replace("-", "+")
    ).decode()


def generate(variant_name: str, api_key: str) -> None:
    import requests
    spec = VARIANTS[variant_name]
    out_path = OUT_DIR / f"{variant_name}.ogg"
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    r = requests.post(
        "https://api.elevenlabs.io/v1/sound-generation",
        headers={"xi-api-key": api_key, "Content-Type": "application/json"},
        json={
            "text": spec["prompt"],
            "duration_seconds": spec["duration"],
            "prompt_influence": PROMPT_INFLUENCE,
            "output_format": "mp3_22050_32",
        },
        timeout=60,
    )
    r.raise_for_status()
    mp3_path = out_path.with_suffix(".mp3")
    mp3_path.write_bytes(r.content)
    subprocess.run(
        ["ffmpeg", "-y", "-i", str(mp3_path),
         "-c:a", "libvorbis", "-q:a", "3", str(out_path)],
        check=True, capture_output=True,
    )
    mp3_path.unlink()
    print(f"wrote {out_path} ({out_path.stat().st_size} bytes)")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--variant", choices=list(VARIANTS.keys()))
    ap.add_argument("--all", action="store_true")
    args = ap.parse_args()
    if not args.all and not args.variant:
        sys.exit("specify --variant <name> or --all")
    api_key = fetch_api_key()
    names = list(VARIANTS.keys()) if args.all else [args.variant]
    for n in names:
        generate(n, api_key)
        time.sleep(1.0)  # gentle rate-limit between API calls


if __name__ == "__main__":
    main()
```

- [ ] **Step 2: Run the generator for all six variants**

```bash
cd /home/projects/Not_This_Again
python3 scripts/gen_candy_tap_sfx.py --all
```

Expected output: 6 lines `wrote godot/assets/sfx/sky_taps/<name>.ogg (~5000-15000 bytes)`.

If any one variant returns a poor sound (ElevenLabs is stochastic), re-run just that one:
```bash
python3 scripts/gen_candy_tap_sfx.py --variant moon_b_crunch
```

Quick audition each: `ffplay -autoexit godot/assets/sfx/sky_taps/sun_a_chime.ogg` (Ctrl-C between plays).

- [ ] **Step 3: Commit**

```bash
git add scripts/gen_candy_tap_sfx.py godot/assets/sfx/sky_taps/
git commit -m "sfx: generate 6 candy-tap variants (3 per body) via ElevenLabs"
```

---

### Task 2: Write the sun lollipop shader

**Files:**
- Create: `godot/shaders/sun_lollipop.gdshader`

- [ ] **Step 1: Write the shader**

```glsl
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_opaque;

// Pinwheel swirl
uniform vec3 swirl_color_a : source_color = vec3(0.96, 0.78, 0.42);  // butterscotch light
uniform vec3 swirl_color_b : source_color = vec3(0.90, 0.64, 0.23);  // butterscotch deep
uniform float rotation_speed : hint_range(0.0, 1.0) = 0.087;          // ~5°/sec in rad/s
uniform float spin_boost : hint_range(1.0, 8.0) = 1.0;                // tap variant B tweens this temporarily
uniform int swirl_wedges : hint_range(2, 12) = 6;

// Sugar shimmer
uniform float shimmer_speed : hint_range(0.0, 1.0) = 0.286;           // 1/3.5 sec
uniform float shimmer_strength : hint_range(0.0, 1.0) = 0.4;

// Face (counter-rotated against swirl so it stays upright)
uniform vec3 face_color : source_color = vec3(0.30, 0.18, 0.06);      // toffee-brown
uniform vec2 face_eye_left_uv = vec2(0.40, 0.43);                     // relative to disc center
uniform vec2 face_eye_right_uv = vec2(0.60, 0.43);
uniform float face_eye_radius : hint_range(0.0, 0.1) = 0.035;
uniform float face_smile_y : hint_range(0.3, 0.7) = 0.60;             // smile baseline (UV space)
uniform float face_smile_width : hint_range(0.0, 0.5) = 0.18;
uniform float face_smile_thickness : hint_range(0.001, 0.05) = 0.012;
uniform float face_smile_curve : hint_range(0.0, 1.0) = 0.40;
uniform float blink_period_sec : hint_range(1.0, 30.0) = 6.0;
uniform float blink_duration_sec : hint_range(0.05, 0.5) = 0.12;

const float PI = 3.14159265359;
const float DISC_RADIUS = 0.48;

void fragment() {
    vec2 uv = UV - vec2(0.5);
    float r = length(uv);
    if (r > DISC_RADIUS) {
        discard;
    }

    // --- Swirl ---
    float ang = atan(uv.y, uv.x) + TIME * rotation_speed * spin_boost;
    float wedge_f = ang * float(swirl_wedges) / PI;
    float wedge = step(0.5, fract(wedge_f * 0.5));
    vec3 col = mix(swirl_color_a, swirl_color_b, wedge);

    // --- Shimmer streak (drifts independently of swirl) ---
    float shimmer_pos = sin(TIME * shimmer_speed * 2.0 * PI) * 0.35;
    float shimmer = exp(-pow((uv.x - shimmer_pos) * 4.0, 2.0));
    col += vec3(1.0, 0.95, 0.85) * shimmer * shimmer_strength * smoothstep(DISC_RADIUS, 0.0, r);

    // --- Face (counter-rotated to stay upright) ---
    // Build face_uv that ignores the swirl rotation
    vec2 face_uv = UV;
    // Blink: collapse eye y-scale for blink_duration of each blink_period
    float blink_phase = mod(TIME, blink_period_sec) / blink_duration_sec;
    float blink = smoothstep(0.0, 1.0, abs(blink_phase - 0.5) * 2.0);
    blink = clamp(blink, 0.05, 1.0);  // never fully zero (anti-aliasing)
    // Eye left
    vec2 d_left = (face_uv - face_eye_left_uv) / vec2(1.0, blink);
    float eye_left = smoothstep(face_eye_radius * 1.05, face_eye_radius * 0.95, length(d_left));
    // Eye right
    vec2 d_right = (face_uv - face_eye_right_uv) / vec2(1.0, blink);
    float eye_right = smoothstep(face_eye_radius * 1.05, face_eye_radius * 0.95, length(d_right));
    // Smile: parabola y = face_smile_y - curve * 4 * (x - 0.5)^2
    float smile_x = face_uv.x - 0.5;
    float smile_y_target = face_smile_y - face_smile_curve * 4.0 * smile_x * smile_x;
    float smile_dist = abs(face_uv.y - smile_y_target);
    float smile = smoothstep(face_smile_thickness, face_smile_thickness * 0.4, smile_dist);
    // Smile mask: only within +/- face_smile_width of x=0.5
    smile *= smoothstep(face_smile_width, face_smile_width * 0.7, abs(smile_x));
    float face_mask = clamp(eye_left + eye_right + smile, 0.0, 1.0);
    col = mix(col, face_color, face_mask);

    ALBEDO = col;
    ALPHA = smoothstep(DISC_RADIUS, DISC_RADIUS - 0.005, r);
}
```

- [ ] **Step 2: Create a one-off preview scene to verify the shader visually**

Create `godot/scenes/_shader_preview_sun.tscn` (temporary — to be deleted in Task 11):

A scene with: Camera3D at `(0, 0, 5)` looking at origin, MeshInstance3D with a `QuadMesh(2, 2)` and a `ShaderMaterial` using `sun_lollipop.gdshader`, plus a black ColorRect background. Set the project main scene to this temporarily.

- [ ] **Step 3: Screenshot verify**

```bash
.claude/skills/sp1-screenshot/capture.sh godot/scenes/_shader_preview_sun.tscn /tmp/sun_preview.png
```

Read `/tmp/sun_preview.png`. Expected appearance: round caramel pinwheel disc with two small dark eyes and a smile, sugar shimmer visible as a soft highlight. If the swirl looks blocky/striped instead of pinwheel-shaped, recheck the `atan`/`fract` math.

- [ ] **Step 4: Commit**

```bash
git add godot/shaders/sun_lollipop.gdshader godot/scenes/_shader_preview_sun.tscn
git commit -m "sky: sun_lollipop.gdshader — swirl + face + shimmer"
```

---

### Task 3: Write the sun stick shader

**Files:**
- Create: `godot/shaders/sun_stick.gdshader`

- [ ] **Step 1: Write the shader**

```glsl
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_opaque;

uniform vec3 stick_color_base : source_color = vec3(0.78, 0.56, 0.28);  // warm amber
uniform vec3 stick_color_tip : source_color = vec3(0.96, 0.86, 0.65);   // glass-clear (matches sun rim)
uniform float highlight_speed : hint_range(0.0, 1.0) = 0.25;            // 1/4 sec drift
uniform float highlight_strength : hint_range(0.0, 1.0) = 0.5;

void fragment() {
    // UV.y goes from 0 at top to 1 at bottom for a default QuadMesh.
    // We want the BASE (warm amber) at the bottom (y=1) and the TIP at top (y=0).
    vec3 col = mix(stick_color_tip, stick_color_base, UV.y);

    // Single drifting highlight column
    float center = 0.5 + sin(TIME * highlight_speed * 2.0 * 3.14159) * 0.08;
    float dist = abs(UV.x - center);
    float highlight = smoothstep(0.07, 0.0, dist) * highlight_strength;
    col += vec3(1.0, 0.95, 0.85) * highlight * (1.0 - UV.y * 0.5);  // fade toward base

    ALBEDO = col;
    ALPHA = 1.0;
}
```

- [ ] **Step 2: Commit** (visual verification deferred to Task 8 where the stick appears under the sun in-context)

```bash
git add godot/shaders/sun_stick.gdshader
git commit -m "sky: sun_stick.gdshader — vertical gradient + drifting highlight"
```

---

### Task 4: Write the moon cookie shader

**Files:**
- Create: `godot/shaders/moon_cookie.gdshader`

- [ ] **Step 1: Write the shader**

```glsl
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_opaque;

uniform vec3 cookie_color_cream : source_color = vec3(0.96, 0.90, 0.78);
uniform vec3 cookie_color_speckle : source_color = vec3(0.62, 0.48, 0.30);
uniform vec3 glow_amber : source_color = vec3(0.88, 0.69, 0.44);
uniform float bite_depth : hint_range(0.0, 1.0) = 0.4;     // 0=no bite, 1=nearly half
uniform vec2 bite_dir = vec2(0.7, 0.7);                    // direction of bite from center
uniform float breath_speed : hint_range(0.0, 1.0) = 0.333; // 1/3 sec cycle
uniform float speckle_density : hint_range(0.0, 50.0) = 12.0;
uniform float speckle_strength : hint_range(0.0, 1.0) = 0.2;

// Face (sleepy — half-closed eyes)
uniform vec3 face_color : source_color = vec3(0.62, 0.48, 0.30);
uniform vec2 face_eye_left_uv = vec2(0.38, 0.50);
uniform vec2 face_eye_right_uv = vec2(0.56, 0.50);          // offset away from bite_dir side
uniform float face_eye_half_height : hint_range(0.001, 0.04) = 0.008;
uniform float face_eye_half_width : hint_range(0.0, 0.1) = 0.04;
uniform float face_smile_y : hint_range(0.3, 0.7) = 0.62;
uniform float face_smile_width : hint_range(0.0, 0.5) = 0.12;
uniform float face_smile_thickness : hint_range(0.001, 0.05) = 0.010;
uniform float blink_period_sec : hint_range(1.0, 30.0) = 8.0;
uniform float blink_duration_sec : hint_range(0.05, 0.5) = 0.15;
uniform float wink_override : hint_range(0.0, 1.0) = 0.0;   // tap variant B tweens this 0→1→0 (left eye only)

const float DISC_RADIUS = 0.48;

float hash21(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

void fragment() {
    vec2 uv = UV - vec2(0.5);
    float r = length(uv);
    if (r > DISC_RADIUS) {
        discard;
    }

    // --- Bite arc ---
    // Bite center sits outside the disc edge; depth controls overlap.
    vec2 bn = normalize(bite_dir);
    vec2 bite_center = bn * (DISC_RADIUS + DISC_RADIUS * (1.0 - bite_depth));
    if (length(uv - bite_center) < DISC_RADIUS) {
        discard;
    }

    // --- Speckle base ---
    float n = hash21(floor(UV * speckle_density));
    vec3 base = mix(cookie_color_cream, cookie_color_speckle, n * speckle_strength);

    // --- Breath glow ---
    float breath = 0.15 + 0.075 * sin(TIME * breath_speed * 2.0 * 3.14159);
    vec3 col = mix(base, glow_amber, breath);

    // --- Face (sleepy half-closed eyes + small mouth) ---
    float blink_phase = mod(TIME, blink_period_sec) / blink_duration_sec;
    float blink = clamp(abs(blink_phase - 0.5) * 2.0, 0.1, 1.0);

    // Eye left — flat horizontal ellipse; wink_override forces this eye closed during tap variant B
    float left_open = mix(blink, 0.05, wink_override);
    vec2 d_left = (UV - face_eye_left_uv) / vec2(face_eye_half_width, face_eye_half_height * left_open);
    float eye_left = smoothstep(1.05, 0.95, length(d_left));
    // Eye right
    vec2 d_right = (UV - face_eye_right_uv) / vec2(face_eye_half_width, face_eye_half_height * blink);
    float eye_right = smoothstep(1.05, 0.95, length(d_right));
    // Mellow smile (almost straight, slight curve)
    float smile_x = UV.x - 0.5;
    float smile_y_target = face_smile_y - 0.15 * 4.0 * smile_x * smile_x;
    float smile_dist = abs(UV.y - smile_y_target);
    float smile = smoothstep(face_smile_thickness, face_smile_thickness * 0.4, smile_dist);
    smile *= smoothstep(face_smile_width, face_smile_width * 0.7, abs(smile_x));

    float face_mask = clamp(eye_left + eye_right + smile, 0.0, 1.0);
    col = mix(col, face_color, face_mask);

    ALBEDO = col;
    ALPHA = smoothstep(DISC_RADIUS, DISC_RADIUS - 0.005, r);
}
```

- [ ] **Step 2: Quick visual sanity check**

Reuse the preview scene from Task 2 by swapping the material's shader to `moon_cookie.gdshader`. Screenshot:

```bash
# Edit godot/scenes/_shader_preview_sun.tscn to swap shaders (manual)
.claude/skills/sp1-screenshot/capture.sh godot/scenes/_shader_preview_sun.tscn /tmp/moon_preview.png
```

Expected: cream-coloured cookie disc with subtle darker speckles, a bite missing from the upper-right (default `bite_dir = (0.7, 0.7)`), two half-closed eyes and a small mouth on the opposite side from the bite. If the bite arc looks like a clean half-circle removed (too aggressive), bite_depth may be too high; if no bite is visible, bite_depth may be too low.

Revert the preview scene back to the sun shader before committing.

- [ ] **Step 3: Commit**

```bash
git add godot/shaders/moon_cookie.gdshader
git commit -m "sky: moon_cookie.gdshader — speckle + bite arc + sleepy face + breath"
```

---

### Task 5: Sky controller — preset application (no interaction, no parallax yet)

**Files:**
- Create: `godot/scripts/sky_bodies.gd`

- [ ] **Step 1: Write the minimal controller**

```gdscript
extends Node3D
class_name SkyBodies

# Distance from camera at which sky bodies sit. Far enough that crowd
# (max radius 5m) never intersects, near enough that the bodies fit in
# the Mobile renderer's default far clip plane.
const SKY_DISTANCE := 50.0
# Parallax: 0.0 = bodies painted onto camera (no parallax at all),
# 1.0 = bodies fully in world (no infinite-distance illusion). 0.15 is
# a subtle "yes the camera moved" cue without losing the always-there
# stability.
const PARALLAX_FACTOR := 0.15

@onready var sun_disc: Node3D = $SunDisc
@onready var sun_stick: Node3D = $SunStick
@onready var moon_disc: Node3D = $MoonDisc

var _camera: Camera3D = null

func bind_camera(camera: Camera3D) -> void:
    _camera = camera

func apply_preset(preset: Dictionary, shadow_offset: Vector3) -> void:
    # Direction the light is coming FROM (opposite the shadow vector).
    var horiz := Vector2(-shadow_offset.x, -shadow_offset.z)
    if horiz.length_squared() < 0.0001:
        horiz = Vector2(0, -1)  # overcast: place body "behind camera" by default
    horiz = horiz.normalized() * SKY_DISTANCE
    # --- Sun ---
    var sun_visible: bool = preset.get("sun_visible", true)
    sun_disc.visible = sun_visible
    sun_stick.visible = sun_visible
    if sun_visible:
        var sun_h: float = preset["sun_height"]
        sun_disc.position = Vector3(horiz.x, sun_h, horiz.y)
        # Stick: vertical quad whose top meets disc bottom, bottom at y=0.
        # Quad mesh is 0.6 wide × stick_height tall, centered on origin,
        # so position the stick at (horiz.x, sun_h * 0.5, horiz.y) with
        # mesh y_size = sun_h.
        var stick_mesh: QuadMesh = sun_stick.get_node("StickMesh").mesh
        stick_mesh.size = Vector2(0.6, sun_h)
        sun_stick.position = Vector3(horiz.x, sun_h * 0.5, horiz.y)
        _push_sun_uniforms(preset)
    # --- Moon ---
    var moon_visible: bool = preset.get("moon_visible", false)
    moon_disc.visible = moon_visible
    if moon_visible:
        var moon_h: float = preset["moon_height"]
        moon_disc.position = Vector3(horiz.x, moon_h, horiz.y)
        _push_moon_uniforms(preset)

func _push_sun_uniforms(preset: Dictionary) -> void:
    var mat: ShaderMaterial = sun_disc.get_node("DiscMesh").material_override
    if mat == null:
        return
    if preset.has("sun_swirl_a"):
        mat.set_shader_parameter("swirl_color_a", preset["sun_swirl_a"])
    if preset.has("sun_swirl_b"):
        mat.set_shader_parameter("swirl_color_b", preset["sun_swirl_b"])

func _push_moon_uniforms(preset: Dictionary) -> void:
    var mat: ShaderMaterial = moon_disc.get_node("DiscMesh").material_override
    if mat == null:
        return
    if preset.has("moon_bite_depth"):
        mat.set_shader_parameter("bite_depth", preset["moon_bite_depth"])

func _process(_dt: float) -> void:
    if _camera == null:
        return
    # Parallax: sky lags camera by PARALLAX_FACTOR.
    global_position = _camera.global_position * (1.0 - PARALLAX_FACTOR)
    # Re-face each visible disc at the camera.
    if sun_disc.visible:
        sun_disc.look_at(_camera.global_position, Vector3.UP, true)
    if moon_disc.visible:
        moon_disc.look_at(_camera.global_position, Vector3.UP, true)
    if sun_stick.visible:
        # Stick only rotates around world Y to face camera.
        var to_cam := _camera.global_position - sun_stick.global_position
        sun_stick.rotation.y = atan2(to_cam.x, to_cam.z)
```

- [ ] **Step 2: Commit**

```bash
git add godot/scripts/sky_bodies.gd
git commit -m "sky: sky_bodies.gd — preset application + parallax + look_at"
```

---

### Task 6: Add Sky node + bodies to SP1 viewer scene

**Files:**
- Modify: `godot/scenes/sp1_crowd_viewer.tscn`

- [ ] **Step 1: Add Sky node hierarchy to the scene**

Open `godot/scenes/sp1_crowd_viewer.tscn` in Godot editor (or hand-edit the .tscn). Under `ViewportContainer/Viewport3D`, add:

```
Sky                         (Node3D, script: sky_bodies.gd)
├── SunDisc                 (Node3D)
│   ├── DiscMesh            (MeshInstance3D, QuadMesh size 12×12, ShaderMaterial→sun_lollipop.gdshader)
│   ├── TapArea             (Area3D + CollisionShape3D with SphereShape3D radius 6.0)
│   └── TapSfx              (Node, container)
│       ├── A               (AudioStreamPlayer3D, stream=sun_a_chime.ogg, volume_db=-8)
│       ├── B               (AudioStreamPlayer3D, stream=sun_b_stick.ogg, volume_db=-8)
│       └── C               (AudioStreamPlayer3D, stream=sun_c_sparkle.ogg, volume_db=-8)
├── SunStick                (Node3D)
│   └── StickMesh           (MeshInstance3D, QuadMesh size 0.6×1 placeholder, ShaderMaterial→sun_stick.gdshader)
└── MoonDisc                (Node3D)
    ├── DiscMesh            (MeshInstance3D, QuadMesh size 9×9, ShaderMaterial→moon_cookie.gdshader)
    ├── TapArea             (Area3D + CollisionShape3D with SphereShape3D radius 4.5)
    └── TapSfx              (Node, container)
        ├── A               (AudioStreamPlayer3D, stream=moon_a_squish.ogg, volume_db=-8)
        ├── B               (AudioStreamPlayer3D, stream=moon_b_crunch.ogg, volume_db=-8)
        └── C               (AudioStreamPlayer3D, stream=moon_c_tink.ogg, volume_db=-8)
```

Set each MeshInstance3D's `cast_shadow = SHADOW_CASTING_SETTING_OFF` (the sky doesn't cast shadows).

Set each MeshInstance3D material's `render_priority = -20` so the sky sorts behind everything else.

Camera3D: enable input picking — set `Camera3D.cull_mask` to include layer 1 (default) and ensure the Area3D nodes are on layer 1.

- [ ] **Step 2: Commit**

```bash
git add godot/scenes/sp1_crowd_viewer.tscn
git commit -m "sky: scene tree — Sky/SunDisc/SunStick/MoonDisc + TapArea + TapSfx"
```

---

### Task 7: Wire lighting presets to Sky + bind camera

**Files:**
- Modify: `godot/scripts/sp1_crowd_viewer.gd`

- [ ] **Step 1: Expand LIGHTING_PRESETS with sky-body keys**

In `LIGHTING_PRESETS`, add new keys to each preset. Replace the existing dict with:

```gdscript
const LIGHTING_PRESETS := {
    "daylight": {
        "light_color":   Color(1.00, 0.96, 0.82, 1),
        "light_energy":  1.2,
        "ambient_color": Color(0.78, 0.82, 0.92, 1),
        "ambient_energy": 0.3,
        "bg_color":      Color(0.42, 0.62, 0.85, 1),
        "shadow_offset": Vector3(0.05, 0.0, 0.10),
        "shadow_color":  Color(0.00, 0.00, 0.02, 0.75),
        "shadow_scale":  1.0,
        "sun_visible":   true,
        "sun_height":    18.0,
        "sun_swirl_a":   Color(0.96, 0.78, 0.42, 1),
        "sun_swirl_b":   Color(0.90, 0.64, 0.23, 1),
        "moon_visible":  false,
    },
    "sunset": {
        "light_color":   Color(1.00, 0.55, 0.30, 1),
        "light_energy":  1.5,
        "ambient_color": Color(0.92, 0.55, 0.45, 1),
        "ambient_energy": 0.4,
        "bg_color":      Color(0.92, 0.55, 0.30, 1),
        "shadow_offset": Vector3(0.60, 0.0, 1.50),
        "shadow_color":  Color(0.18, 0.05, 0.02, 0.55),
        "shadow_scale":  1.3,
        "sun_visible":   true,
        "sun_height":    7.0,
        "sun_swirl_a":   Color(0.95, 0.42, 0.18, 1),
        "sun_swirl_b":   Color(0.72, 0.24, 0.10, 1),
        "moon_visible":  false,
    },
    "moonlight": {
        "light_color":   Color(0.60, 0.72, 1.00, 1),
        "light_energy":  0.55,
        "ambient_color": Color(0.18, 0.24, 0.48, 1),
        "ambient_energy": 0.20,
        "bg_color":      Color(0.06, 0.09, 0.22, 1),
        "shadow_offset": Vector3(0.04, 0.0, 0.08),
        "shadow_color":  Color(0.02, 0.04, 0.10, 0.35),
        "shadow_scale":  0.85,
        "sun_visible":   false,
        "moon_visible":  true,
        "moon_height":   16.0,
        "moon_bite_depth": 0.4,
    },
    "overcast": {
        "light_color":   Color(0.92, 0.94, 0.95, 1),
        "light_energy":  0.6,
        "ambient_color": Color(0.86, 0.88, 0.92, 1),
        "ambient_energy": 0.7,
        "bg_color":      Color(0.78, 0.80, 0.82, 1),
        "shadow_offset": Vector3(0.0, 0.0, 0.0),
        "shadow_color":  Color(0.06, 0.06, 0.08, 0.40),
        "shadow_scale":  0.80,
        "sun_visible":   true,
        "sun_height":    14.0,
        "sun_swirl_a":   Color(0.91, 0.79, 0.61, 1),
        "sun_swirl_b":   Color(0.72, 0.60, 0.43, 1),
        "moon_visible":  false,
    },
}
```

- [ ] **Step 2: Bind the camera to the Sky in _ready, call apply_preset in _apply_lighting_preset**

Add after the existing camera setup in `_ready()`:

```gdscript
    var sky := $ViewportContainer/Viewport3D/Sky
    if sky and camera_3d:
        sky.bind_camera(camera_3d)
```

In `_apply_lighting_preset()`, after the existing key_light/world_env/crowd-shadow setup, add:

```gdscript
    var sky := $ViewportContainer/Viewport3D/Sky
    if sky and sky.has_method("apply_preset"):
        sky.apply_preset(p, p["shadow_offset"])
```

- [ ] **Step 3: Screenshot verify all 4 presets**

The screenshot pipeline runs the scene headlessly — it cannot click UI buttons. For each preset, temporarily hardcode the preset name at the bottom of `_ready()`:

```gdscript
    # TEMP: hardcode preset for verification (remove before commit)
    _apply_lighting_preset("daylight")  # change per pass: sunset, moonlight, overcast
```

For each of the four presets, change the literal, capture a screenshot, then proceed to the next:

```bash
for preset in daylight sunset moonlight overcast; do
  # 1. Edit sp1_crowd_viewer.gd: change the hardcoded literal to "$preset"
  # 2. Capture
  .claude/skills/sp1-screenshot/capture.sh godot/scenes/sp1_crowd_viewer.tscn /tmp/sky_${preset}.png
done
```

Read each screenshot. Expected:
- **daylight**: sun visible upper-screen with butterscotch swirl, face, stick down to horizon
- **sunset**: sun lower with orange-red swirl, longer stick
- **moonlight**: cookie moon visible, sun gone
- **overcast**: pale low-energy sun, no moon

Note: at this point the camera still looks down at origin, so the sun/moon may be partially clipped at the top of the frame — that's fine, Task 8 adds the tilt slider.

After verification, remove the temporary `_apply_lighting_preset("...")` line from `_ready()`.

- [ ] **Step 4: Commit**

```bash
git add godot/scripts/sp1_crowd_viewer.gd
git commit -m "sky: wire LIGHTING_PRESETS to Sky.apply_preset + bind camera"
```

---

### Task 8: Camera tilt slider

**Files:**
- Modify: `godot/scenes/sp1_crowd_viewer.tscn`
- Modify: `godot/scripts/sp1_crowd_viewer.gd`

- [ ] **Step 1: Add the slider to the UI panel**

In `godot/scenes/sp1_crowd_viewer.tscn`, add a new Label + HSlider to the VBox `UI/Panel/VBox`, between `SizeSlider` and `DPad`:

```
TiltLabel    (Label, text="Camera tilt: -20°")
TiltSlider   (HSlider, min_value=-60.0, max_value=20.0, value=-20.0, step=1.0)
```

- [ ] **Step 2: Replace the camera look_at with explicit pitch**

In `sp1_crowd_viewer.gd`:

Remove the existing line `camera_3d.look_at(Vector3.ZERO, Vector3.UP)`.

Add:

```gdscript
@onready var tilt_slider: HSlider = $UI/Panel/VBox/TiltSlider
@onready var tilt_label: Label = $UI/Panel/VBox/TiltLabel
```

In `_ready()` (after the slider connects block):

```gdscript
    if tilt_slider:
        tilt_slider.value_changed.connect(_on_tilt_changed)
        _on_tilt_changed(tilt_slider.value)
```

New method:

```gdscript
func _on_tilt_changed(degrees: float) -> void:
    if camera_3d == null:
        return
    # Tilt: positive rotates the camera UP (look toward sky). The camera
    # keeps its XZ position; we rotate around its local X axis.
    var pitch_rad := deg_to_rad(degrees)
    # Start from the camera's home transform looking horizontally at +Z
    # forward, then apply pitch. The viewport's camera sits above-and-back
    # of origin so the X/Y/Z home values come from the .tscn.
    camera_3d.rotation.x = pitch_rad
    if tilt_label:
        tilt_label.text = "Camera tilt: %d°" % int(degrees)
```

- [ ] **Step 3: Screenshot verify**

Same hardcode-and-capture pattern as Task 7. For each tilt value, set:

```gdscript
    # TEMP: hardcode tilt for verification (remove before commit)
    tilt_slider.value = 10.0   # vary: -50.0, -20.0, 10.0
```

…then capture:

```bash
for tilt in m50 m20 p10; do
  # edit slider value: m50 → -50.0, m20 → -20.0, p10 → +10.0
  .claude/skills/sp1-screenshot/capture.sh godot/scenes/sp1_crowd_viewer.tscn /tmp/tilt_${tilt}.png
done
```

Expected:
- -50°: mostly ground, sky barely visible at top
- -20°: balanced (default)
- +10°: lots of sky visible, sun/moon prominent

Remove the temporary hardcode line after verification.

- [ ] **Step 4: Commit**

```bash
git add godot/scenes/sp1_crowd_viewer.tscn godot/scripts/sp1_crowd_viewer.gd
git commit -m "sp1: camera tilt slider (-60° to +20°), removes look_at"
```

---

### Task 9: Tap detection + variant-aware bounce + SFX

**Files:**
- Modify: `godot/scripts/sky_bodies.gd`

- [ ] **Step 1: Add tap handlers and variant-aware bounce to sky_bodies.gd**

Append to `sky_bodies.gd`:

```gdscript
const VARIANTS := ["A", "B", "C"]
var _last_variant := {"sun": "", "moon": ""}

func _ready() -> void:
    # Wire each body's TapArea to the tap handler.
    var pairs := [["sun", sun_disc], ["moon", moon_disc]]
    for pair in pairs:
        var body_key: String = pair[0]
        var body: Node3D = pair[1]
        var area: Area3D = body.get_node_or_null("TapArea")
        if area:
            area.input_event.connect(_on_body_tapped.bind(body_key, body))

func _pick_variant(body_key: String) -> String:
    # Random no-repeat: pick uniformly from variants except the previous one.
    var pool := VARIANTS.filter(func(v): return v != _last_variant[body_key])
    var chosen: String = pool[randi() % pool.size()]
    _last_variant[body_key] = chosen
    return chosen

func _on_body_tapped(_camera: Node, event: InputEvent, _pos: Vector3,
                    _normal: Vector3, _shape_idx: int,
                    body_key: String, body: Node3D) -> void:
    var is_touch := event is InputEventScreenTouch and event.pressed
    var is_click := event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT
    if not (is_touch or is_click):
        return
    var variant := _pick_variant(body_key)
    # Play matching sound
    var sfx_player: AudioStreamPlayer3D = body.get_node_or_null("TapSfx/%s" % variant)
    if sfx_player:
        sfx_player.play()
    # Run matching animation
    if body_key == "sun":
        match variant:
            "A": _anim_scale_pulse(body)
            "B": _anim_sun_spin(body)
            "C": _anim_z_wobble(body, 0.26, 0.6)
    else:
        match variant:
            "A": _anim_scale_pulse(body)
            "B": _anim_moon_wink(body)
            "C": _anim_z_wobble(body, 0.14, 0.5)

func _kill_prev_tween(body: Node3D) -> void:
    if body.has_meta("bounce_tween"):
        var prev: Tween = body.get_meta("bounce_tween")
        if prev and prev.is_valid():
            prev.kill()

# Variant A — scale-pulse. Used by both bodies.
func _anim_scale_pulse(body: Node3D) -> void:
    _kill_prev_tween(body)
    body.scale = Vector3.ONE
    var t := create_tween()
    t.set_trans(Tween.TRANS_BACK)
    t.tween_property(body, "scale", Vector3.ONE * 1.15, 0.08).set_ease(Tween.EASE_OUT)
    t.tween_property(body, "scale", Vector3.ONE * 0.97, 0.14).set_ease(Tween.EASE_IN_OUT)
    t.tween_property(body, "scale", Vector3.ONE, 0.08).set_ease(Tween.EASE_OUT)
    body.set_meta("bounce_tween", t)

# Sun variant B — spin-flourish via shader spin_boost uniform.
func _anim_sun_spin(body: Node3D) -> void:
    _kill_prev_tween(body)
    var mat: ShaderMaterial = body.get_node("DiscMesh").material_override
    if mat == null:
        return
    mat.set_shader_parameter("spin_boost", 1.0)
    var t := create_tween()
    t.tween_method(func(v): mat.set_shader_parameter("spin_boost", v), 1.0, 4.0, 0.12)\
     .set_ease(Tween.EASE_OUT)
    t.tween_method(func(v): mat.set_shader_parameter("spin_boost", v), 4.0, 1.0, 0.28)\
     .set_ease(Tween.EASE_IN)
    body.set_meta("bounce_tween", t)

# Moon variant B — wink via shader wink_override uniform (left eye only).
func _anim_moon_wink(body: Node3D) -> void:
    _kill_prev_tween(body)
    var mat: ShaderMaterial = body.get_node("DiscMesh").material_override
    if mat == null:
        return
    mat.set_shader_parameter("wink_override", 0.0)
    var t := create_tween()
    t.tween_method(func(v): mat.set_shader_parameter("wink_override", v), 0.0, 1.0, 0.10)\
     .set_ease(Tween.EASE_OUT)
    t.tween_method(func(v): mat.set_shader_parameter("wink_override", v), 1.0, 0.0, 0.15)\
     .set_ease(Tween.EASE_IN)
    body.set_meta("bounce_tween", t)

# Variant C — Z-axis wobble (sun: ±15°, moon: ±8°).
func _anim_z_wobble(body: Node3D, peak_rad: float, total_sec: float) -> void:
    _kill_prev_tween(body)
    body.rotation.z = 0.0
    var t := create_tween()
    t.tween_property(body, "rotation:z", peak_rad, total_sec * 0.25).set_ease(Tween.EASE_OUT)
    t.tween_property(body, "rotation:z", -peak_rad, total_sec * 0.30).set_ease(Tween.EASE_IN_OUT)
    t.tween_property(body, "rotation:z", peak_rad * 0.4, total_sec * 0.22).set_ease(Tween.EASE_IN_OUT)
    t.tween_property(body, "rotation:z", 0.0, total_sec * 0.23).set_ease(Tween.EASE_IN)
    body.set_meta("bounce_tween", t)
```

- [ ] **Step 2: Sideload-only verification**

This step requires touch input; the headless screenshot pipeline can't simulate taps. After Task 11's APK build, manually verify on-device:
- Tap the sun under daylight/sunset/overcast — each tap plays one of three sounds and one of three animations (scale-pulse / spin-flourish / wobble)
- Tap the moon under moonlight — each tap plays one of three sounds and one of three animations (scale-pulse / wink / tilt)
- Rapid-tap the sun 6 times — the same variant should never repeat back-to-back; all three should appear at least once across the run
- Wink: confirm only the LEFT eye closes (not both, not the right)

- [ ] **Step 3: Commit**

```bash
git add godot/scripts/sky_bodies.gd
git commit -m "sky: tap → variant-aware bounce (3) + SFX (3) per body, no-repeat"
```

---

### Task 10: Local screenshot verification of all presets with tilt

**Files:** None (verification only)

- [ ] **Step 1: Screenshot each preset with tilt=+10°**

Hard-code `tilt_slider.value = 10.0` and lighting preset in `_ready()` for each pass, OR use the screenshot skill's interaction mode:

```bash
for preset in daylight sunset moonlight overcast; do
  # (modify _ready temporarily to pick this preset and tilt=+10)
  .claude/skills/sp1-screenshot/capture.sh godot/scenes/sp1_crowd_viewer.tscn /tmp/final_${preset}.png
done
```

- [ ] **Step 2: Read each screenshot with vision; record issues**

For each preset, verify:
- Sun or moon visible matching expected preset behavior
- Face on the visible body (eyes + mouth) is readable
- Sunset shadow direction (toward camera-right/+Z) is OPPOSITE to sun position (camera-left/-Z)
- Stick reaches the horizon line under daylight/sunset/overcast
- Body sorting: sun/moon behind grass and crowd

If any issue, return to the relevant task to fix.

- [ ] **Step 3: Restore _ready to its production state** (remove any hardcoded preset/tilt used for testing)

- [ ] **Step 4: Commit any fixes from this pass (none if all clean)**

---

### Task 11: Clean up preview scene + final sideload

**Files:**
- Delete: `godot/scenes/_shader_preview_sun.tscn`

- [ ] **Step 1: Delete the temporary preview scene from Task 2**

```bash
git rm godot/scenes/_shader_preview_sun.tscn
```

- [ ] **Step 2: Push + build APK**

```bash
git commit -m "sky: drop temporary shader-preview scene"
git push origin main
```

Wait for GitHub Actions Android Debug build to complete. Then bundle the APK to `/tmp`:

```bash
RUN_ID=$(gh run list --workflow android-debug.yml --limit 1 --json databaseId --jq '.[0].databaseId')
mkdir -p /tmp/sp1-build
wget -nv -O /tmp/bundletool.jar https://github.com/google/bundletool/releases/download/1.18.1/bundletool-all-1.18.1.jar
gh run download "$RUN_ID" --name app-debug-aab -D /tmp/sp1-build
AAB=$(find /tmp/sp1-build -name '*.aab' | head -1)
java -jar /tmp/bundletool.jar build-apks --bundle="$AAB" --output=/tmp/sp1-build/sp1.apks --mode=universal
unzip -o /tmp/sp1-build/sp1.apks universal.apk -d /tmp/sp1-build/
SHA=$(git rev-parse --short HEAD)
ITER=$(git log --oneline | wc -l)
mv /tmp/sp1-build/universal.apk "/tmp/not_this_again_iter${ITER}_${SHA}.apk"
rm -rf /tmp/sp1-build /tmp/bundletool.jar
ls -la /tmp/not_this_again_iter*.apk
```

- [ ] **Step 3: Sideload + on-device verification**

User sideloads to phone and confirms:
- All 4 presets show correct sky body
- Camera tilt slider sweeps reveal/hide the bodies
- Tap on sun/moon → bounce + sound
- Faces visible at expected scale (~25% sun, ~20% moon of vertical sky)
- No frame-rate regression (still ~60fps with 200 crowd members)

- [ ] **Step 4: Mark plan complete + update memory**

If sideload passes, the plan is complete. Update the project memory file `project_feature_deferred_crowd_milling.md` if any new deferred items emerged, and update `MEMORY.md` to note that the candy-sky feature is implemented.

---

## Pending Follow-ups (NOT in this plan)

- **Pusher atlas size normalization**: Separate spec — re-render pushers with figure-bbox-based normalization in `tools/build_atlas.py`. Tracked because shadows currently only match large pushers; this plan does not address that.
- **Full day/night cycle**: Sun/moon arc across the sky over real time. Explicitly deferred per spec Non-Goals.
- **Gameplay-reactive sky**: Sun spins faster during action, moon bite deepens with damage. Deferred.
