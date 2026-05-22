# SP1 Sprite-Sheet Animation System — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a sprite-sheet flipbook animation system — an offline atlas-build tool, a flipbook shader, single-character and MultiMesh-crowd runtimes — and a debug preview scene that demonstrates every character animating with zero video decoders.

**Architecture:** Each animation clip becomes one texture-atlas PNG (frames laid out in a grid). A shared `flipbook.gdshader` plays an atlas by computing the current frame from elapsed time and offsetting the UVs to that grid cell. Single characters (Pete, Humbug) use one `MeshInstance3D` quad; crowds use a pool of `MultiMeshInstance3D` — one per clip — with per-instance phase. The SP1 preview scene shows every character at once and doubles as the on-device benchmark harness.

**Tech Stack:** Godot 4.6.1 / GDScript; Godot spatial shaders; Python 3 + ffmpeg + Pillow (atlas tool); Veo via `tools/veo_render.sh` for new source clips.

**This is Plan 1 of 2 for SP1.** Plan 1 builds the system + preview scene (spec deliverables 1–5). Plan 2 — integration into `level_3d` — is written only after the preview scene is signed off on the A26.

**Spec:** `docs/superpowers/specs/2026-05-21-sp1-sprite-sheet-animation-design.md`

---

## File Structure

| File | Responsibility |
|---|---|
| `tools/build_atlas.py` | Offline: one clip (`.ogv` or frame dir) → one keyed atlas PNG + `<name>.atlas.json` (grid cols/rows, frame count, fps). |
| `tools/render_sp1_clips.sh` | Offline: drives `veo_render.sh` for the cyclic re-renders and the new pusher/chicken clips. |
| `godot/shaders/flipbook.gdshader` | Spatial shader: plays an atlas as a billboarded flipbook with alpha-scissor. |
| `godot/scripts/flipbook_player.gd` | Single-character node (Pete, Humbug): holds a flipbook quad, swaps clip atlas + resets start time. |
| `godot/scripts/flipbook_crowd.gd` | Crowd manager: per-clip `MultiMeshInstance3D` pool; each instance lives in its current clip's mesh. |
| `godot/scenes/sprite_anim_preview.tscn` + `godot/scripts/sprite_anim_preview.gd` | SP1 preview scene + the live frame-time / draw-call / texture-memory readout. |
| `godot/scripts/debug_menu.gd`, `godot/scenes/debug_menu.tscn` | Modified: add a "Rendering Rebuild" tier with an SP1 button. |
| `godot/assets/sprites/atlases/` | Output: the generated atlas PNGs + `.atlas.json` sidecars. |
| `godot/test/test_flipbook.gd` | GUT tests for the frame-index math and the crowd manager's clip routing. |

---

## Task 1: Atlas-build tool

**Files:**
- Create: `tools/build_atlas.py`
- Test: `godot/test/` not applicable — Python tool; verified by Step 4 below.

- [ ] **Step 1: Write the tool**

```python
#!/usr/bin/env python3
"""Build one sprite-sheet atlas from a video clip or a folder of frames.

Usage:
  build_atlas.py --clip path/to/clip.ogv --out godot/assets/sprites/atlases/cowboy_idle_a
  build_atlas.py --frames path/to/frames_dir --fps 24 --out .../name

Produces <out>.png (the grid atlas, RGBA, chroma-keyed transparent) and
<out>.atlas.json ({cols, rows, frame_count, fps}).
"""
import argparse, json, math, subprocess, sys, tempfile
from pathlib import Path
from PIL import Image

GREEN = (0, 177, 64)        # Veo chroma-green; tune if a clip differs
KEY_TOLERANCE = 70          # per-channel distance treated as background

def extract_frames(clip: Path, dst: Path) -> float:
    """ffmpeg-extract every frame. Returns the clip's fps."""
    probe = subprocess.run(
        ["ffprobe", "-v", "error", "-select_streams", "v:0",
         "-show_entries", "stream=r_frame_rate", "-of", "csv=p=0", str(clip)],
        capture_output=True, text=True, check=True).stdout.strip()
    num, den = (int(x) for x in probe.split("/"))
    fps = num / den
    subprocess.run(["ffmpeg", "-y", "-i", str(clip),
                    str(dst / "f_%04d.png")], capture_output=True, check=True)
    return fps

def key_frame(img: Image.Image) -> Image.Image:
    """Chroma-key Veo green to transparent."""
    img = img.convert("RGBA")
    px = img.load()
    for y in range(img.height):
        for x in range(img.width):
            r, g, b, a = px[x, y]
            if (abs(r - GREEN[0]) + abs(g - GREEN[1]) + abs(b - GREEN[2])
                    < KEY_TOLERANCE * 3):
                px[x, y] = (r, g, b, 0)
    return img

def build(frames: list[Path], fps: float, out: Path) -> None:
    imgs = [key_frame(Image.open(f)) for f in sorted(frames)]
    n = len(imgs)
    cols = math.ceil(math.sqrt(n))
    rows = math.ceil(n / cols)
    fw, fh = imgs[0].size
    sheet = Image.new("RGBA", (cols * fw, rows * fh), (0, 0, 0, 0))
    for i, im in enumerate(imgs):
        sheet.paste(im, ((i % cols) * fw, (i // cols) * fh))
    out.with_suffix(".png").parent.mkdir(parents=True, exist_ok=True)
    sheet.save(out.with_suffix(".png"))
    out.with_suffix(".atlas.json").write_text(json.dumps(
        {"cols": cols, "rows": rows, "frame_count": n, "fps": fps}, indent=2))
    print(f"wrote {out}.png  {cols}x{rows} grid, {n} frames @ {fps:.1f}fps")

def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--clip"); ap.add_argument("--frames")
    ap.add_argument("--fps", type=float, default=24.0)
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    out = Path(a.out)
    if a.clip:
        with tempfile.TemporaryDirectory() as td:
            fps = extract_frames(Path(a.clip), Path(td))
            build(sorted(Path(td).glob("f_*.png")), fps, out)
    elif a.frames:
        build(sorted(Path(a.frames).glob("*.png")), a.fps, out)
    else:
        sys.exit("need --clip or --frames")

if __name__ == "__main__":
    main()
```

- [ ] **Step 2: Run it on one existing clip to verify it fails cleanly without Pillow, then install Pillow**

Run: `python3 tools/build_atlas.py --clip godot/assets/videos/cowboy/idle_a.ogv --out /tmp/atlastest/idle_a`
Expected first run: `ModuleNotFoundError: No module named 'PIL'` → then `pip install Pillow` (or use the roguelike venv which has it).

- [ ] **Step 3: Run it for real on `idle_a.ogv`**

Run: `python3 tools/build_atlas.py --clip godot/assets/videos/cowboy/idle_a.ogv --out /tmp/atlastest/idle_a`
Expected: prints `wrote /tmp/atlastest/idle_a.png  10x10 grid, 96 frames @ 24.0fps`; `/tmp/atlastest/idle_a.png` and `idle_a.atlas.json` exist.

- [ ] **Step 4: Verify the atlas visually**

Open `/tmp/atlastest/idle_a.png` — confirm a grid of cowboy frames with transparent (not green) backgrounds. If green fringing remains, raise `KEY_TOLERANCE`; if the cowboy is eaten, lower it.

- [ ] **Step 5: Commit**

```bash
git add tools/build_atlas.py
git commit -m "sp1: atlas-build tool (clip -> keyed grid PNG + metadata)"
```

---

## Task 2: Re-render the cyclic clips as short loops

**Files:**
- Create: `tools/render_sp1_clips.sh`
- Modify: none (output goes to `godot/assets/videos/<character>/`)

Cyclic clips wrap-pop every 4 s unless rendered as loops. Re-render them short and seamless.

- [ ] **Step 1: Add the cyclic-clip render block to `render_sp1_clips.sh`**

```bash
#!/usr/bin/env bash
# SP1 source-clip renders. Run section-by-section; review each clip.
set -euo pipefail
COWBOY=godot/assets/videos/cowboy

# Cyclic clips -> short --loop renders (~1.3s seamless single cycle).
for clip in run_shoot_fwd run_shoot_left run_shoot_right strafe_left strafe_right stand_shoot; do
  tools/veo_render.sh --loop --duration 1.3 \
    --image "$COWBOY/${clip}_startframe.png" \
    --prompt "cowboy ${clip//_/ }, one smooth seamless cycle, cartoon" \
    --out-name "$clip" --out-dir "$COWBOY"
done
```

- [ ] **Step 2: Extract a clean start frame per cyclic clip**

For each clip, pull frame 0 of the current `.ogv` as the loop anchor:
Run: `for c in run_shoot_fwd run_shoot_left run_shoot_right strafe_left strafe_right stand_shoot; do ffmpeg -y -i godot/assets/videos/cowboy/$c.ogv -vframes 1 godot/assets/videos/cowboy/${c}_startframe.png; done`

- [ ] **Step 3: Render the cyclic clips**

Run: the cyclic block of `tools/render_sp1_clips.sh`.
Expected: 6 new `.ogv` files (~1.3 s each) in `godot/assets/videos/cowboy/`.

- [ ] **Step 4: User review**

Send the 6 clips to the user. Each must loop with no visible pop. Re-roll any that swim or hitch.

- [ ] **Step 5: Commit**

```bash
git add tools/render_sp1_clips.sh godot/assets/videos/cowboy/
git commit -m "sp1: re-render cyclic cowboy clips as short seamless loops"
```

---

## Task 3: Render the pusher clips

**Files:**
- Modify: `tools/render_sp1_clips.sh`
- Create: `godot/assets/videos/pusher/` (8 clips)

- [ ] **Step 1: Generate a forward-facing pusher start frame**

The existing `pusher_left/right/melee.png` cover three of four poses; run-forward has none. Generate one with NB2 (`gemini-3.1-flash-image-preview`): a pusher mid-run toward the viewer, on flat chroma-green, ~50% frame height. Save `godot/assets/sprites/props/pusher_forward.png`.

- [ ] **Step 2: Add the pusher render block to `render_sp1_clips.sh`**

```bash
PUSH=godot/assets/videos/pusher
mkdir -p "$PUSH"
PROPS=godot/assets/sprites/props
declare -A PUSHER=(
  [push_left_a]="$PROPS/pusher_left.png|pusher shoving left, shoulder down, strained"
  [push_left_b]="$PROPS/pusher_left.png|pusher shoving left, low crouch heave"
  [push_left_c]="$PROPS/pusher_left.png|pusher shoving left, staggering effort"
  [push_right_a]="$PROPS/pusher_right.png|pusher shoving right, shoulder down, strained"
  [push_right_b]="$PROPS/pusher_right.png|pusher shoving right, low crouch heave"
  [push_right_c]="$PROPS/pusher_right.png|pusher shoving right, staggering effort"
  [run_forward]="$PROPS/pusher_forward.png|pusher running forward at the viewer"
  [melee]="$PROPS/pusher_melee.png|pusher swinging a melee blow"
)
for name in "${!PUSHER[@]}"; do
  IFS='|' read -r img prompt <<< "${PUSHER[$name]}"
  tools/veo_render.sh --loop --duration 1.3 --image "$img" \
    --prompt "$prompt, cartoon, seamless cycle" \
    --out-name "$name" --out-dir "$PUSH"
done
```

- [ ] **Step 3: Render + review**

Run the pusher block. Send the 8 clips to the user; re-roll rejects.

- [ ] **Step 4: Commit**

```bash
git add tools/render_sp1_clips.sh godot/assets/sprites/props/pusher_forward.png godot/assets/videos/pusher/
git commit -m "sp1: render 8 pusher animation clips"
```

---

## Task 4: Render the chicken clips + loose feathers

**Files:**
- Modify: `tools/render_sp1_clips.sh`
- Create: `godot/assets/videos/chicken/` (9 clips), `godot/assets/sprites/fx/feather_*.png`

- [ ] **Step 1: Generate 3 breed start frames**

NB2-generate one chroma-green start frame per breed, panicked pose: `chicken_rir.png` (Rhode Island Red), `chicken_leghorn.png` (white Leghorn), `chicken_silkie.png` (speckled Silkie). Save under `godot/assets/sprites/props/`.

- [ ] **Step 2: Add the chicken render block to `render_sp1_clips.sh`**

```bash
CHICK=godot/assets/videos/chicken
mkdir -p "$CHICK"
for breed in rir leghorn silkie; do
  for anim in "flap:frantic wing-flapping in place, bug-eyed panic" \
              "scramble:panicked blind scramble-run" \
              "tumble:tumbling head-over-heels, legs flailing, crowing"; do
    IFS=':' read -r a desc <<< "$anim"
    tools/veo_render.sh --loop --duration 1.2 \
      --image "godot/assets/sprites/props/chicken_${breed}.png" \
      --prompt "$desc, cartoon chicken, seamless cycle" \
      --out-name "${breed}_${a}" --out-dir "$CHICK"
  done
done
```

- [ ] **Step 3: Render + review the 9 chicken clips**

Run the chicken block. Send to the user; re-roll rejects.

- [ ] **Step 4: Generate the loose-feather sprites**

NB2-generate 3 small single feathers (different shapes/tints) on transparent background: `godot/assets/sprites/fx/feather_0.png`..`feather_2.png`. These feed a `GPUParticles3D` burst in the preview scene (Task 9).

- [ ] **Step 5: Commit**

```bash
git add tools/render_sp1_clips.sh godot/assets/sprites/props/chicken_*.png godot/assets/videos/chicken/ godot/assets/sprites/fx/
git commit -m "sp1: render 9 chicken clips (3 breeds x 3) + loose-feather sprites"
```

---

## Task 5: Generate atlases for every clip

**Files:**
- Modify: `tools/render_sp1_clips.sh` (append a batch-atlas section)
- Create: `godot/assets/sprites/atlases/*` (atlas PNGs + `.atlas.json`)

- [ ] **Step 1: Append the batch-atlas loop**

```bash
# --- Build atlases for every SP1 clip ---
ATLAS=godot/assets/sprites/atlases
for dir in cowboy pete vagrant prospector humbug pusher chicken; do
  for clip in godot/assets/videos/$dir/*.ogv; do
    [ -e "$clip" ] || continue
    base=$(basename "$clip" .ogv)
    python3 tools/build_atlas.py --clip "$clip" --out "$ATLAS/${dir}_${base}"
  done
done
```

- [ ] **Step 2: Run it**

Run: the batch-atlas section.
Expected: an atlas PNG + `.atlas.json` per clip under `godot/assets/sprites/atlases/`.

- [ ] **Step 3: Spot-check 3 atlases** — open `cowboy_idle_a.png`, `pusher_melee.png`, `chicken_silkie_flap.png`; confirm clean grids, transparent backgrounds.

- [ ] **Step 4: Commit**

```bash
git add tools/render_sp1_clips.sh godot/assets/sprites/atlases/
git commit -m "sp1: generate sprite-sheet atlases for all character clips"
```

---

## Task 6: The flipbook shader

**Files:**
- Create: `godot/shaders/flipbook.gdshader`

- [ ] **Step 1: Write the shader**

```glsl
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;

uniform sampler2D atlas : source_color, filter_nearest;
uniform int cols = 10;
uniform int rows = 10;
uniform int frame_count = 96;
uniform float fps = 24.0;
uniform float start_time = 0.0;   // used when use_instance == 0 (singletons)
uniform float phase = 0.0;
uniform int use_instance = 0;     // 1 = read start/phase/flip from INSTANCE_CUSTOM (crowds)
uniform float alpha_clip = 0.5;

varying float v_start;
varying float v_phase;
varying float v_flip;

void vertex() {
    // Per-instance animation data (crowds) or material uniforms (singletons).
    v_start = use_instance == 1 ? INSTANCE_CUSTOM.r : start_time;
    v_phase = use_instance == 1 ? INSTANCE_CUSTOM.g : phase;
    v_flip  = use_instance == 1 ? INSTANCE_CUSTOM.b : 0.0;
    // Y-axis billboard: face the camera, stay upright.
    mat4 mv = VIEW_MATRIX * MODEL_MATRIX;
    mv[0] = vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0);
    mv[1] = vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0);
    mv[2] = vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0);
    POSITION = PROJECTION_MATRIX * mv * vec4(VERTEX, 1.0);
}

void fragment() {
    float t = TIME - v_start + v_phase * float(frame_count) / fps;
    int frame = int(floor(t * fps)) % frame_count;
    if (frame < 0) { frame += frame_count; }
    vec2 cell = vec2(float(frame % cols), float(frame / cols));
    vec2 fuv = UV;
    if (v_flip > 0.5) { fuv.x = 1.0 - fuv.x; }   // mirrored variations (chickens)
    vec2 uv = (fuv + cell) / vec2(float(cols), float(rows));
    vec4 c = texture(atlas, uv);
    if (c.a < alpha_clip) { discard; }
    ALBEDO = c.rgb;
    ALPHA = 1.0;
}
```

- [ ] **Step 2: Smoke-test in a scratch scene**

Create a temp 3D scene: a `MeshInstance3D` with a `QuadMesh` and a `ShaderMaterial` using `flipbook.gdshader`, atlas params set for `cowboy_idle_a`. Run it. Expected: the cowboy animates, faces the camera, clean transparent edges.

- [ ] **Step 3: Commit**

```bash
git add godot/shaders/flipbook.gdshader
git commit -m "sp1: flipbook shader (billboarded atlas playback, alpha-scissor)"
```

---

## Task 7: The single-character flipbook player

**Files:**
- Create: `godot/scripts/flipbook_player.gd`
- Test: `godot/test/test_flipbook.gd`

- [ ] **Step 1: Write the failing test**

```gdscript
extends GutTest
const FlipbookPlayer = preload("res://scripts/flipbook_player.gd")

func test_set_clip_updates_material_params():
    var p = FlipbookPlayer.new()
    add_child_autofree(p)
    p.set_clip("cowboy_idle_a")
    var mat: ShaderMaterial = p.get_active_material(0)
    assert_eq(mat.get_shader_parameter("cols"), 10, "cols from atlas json")
    assert_eq(mat.get_shader_parameter("frame_count"), 96)
```

- [ ] **Step 2: Run it — verify it fails**

Run: `godot --headless --path godot -s addons/gut/gut_cmdln.gd -gtest=res://test/test_flipbook.gd`
Expected: FAIL — `flipbook_player.gd` does not exist.

- [ ] **Step 3: Write `flipbook_player.gd`**

```gdscript
extends MeshInstance3D
# Single-character flipbook (Pete, Humbug). One quad, one flipbook material;
# set_clip() swaps the atlas + resets the animation clock.

const ATLAS_DIR := "res://assets/sprites/atlases/"
const FLIPBOOK_SHADER := preload("res://shaders/flipbook.gdshader")

var _clip := ""

func _ready() -> void:
    if mesh == null:
        var q := QuadMesh.new()
        q.size = Vector2(2.0, 2.0)
        mesh = q
    if get_active_material(0) == null:
        var m := ShaderMaterial.new()
        m.shader = FLIPBOOK_SHADER
        set_surface_override_material(0, m)

func set_clip(clip_name: String) -> void:
    if clip_name == _clip:
        return
    _clip = clip_name
    var meta: Dictionary = JSON.parse_string(
        FileAccess.get_file_as_string(ATLAS_DIR + clip_name + ".atlas.json"))
    var mat: ShaderMaterial = get_active_material(0)
    mat.set_shader_parameter("atlas", load(ATLAS_DIR + clip_name + ".png"))
    mat.set_shader_parameter("cols", int(meta["cols"]))
    mat.set_shader_parameter("rows", int(meta["rows"]))
    mat.set_shader_parameter("frame_count", int(meta["frame_count"]))
    mat.set_shader_parameter("fps", float(meta["fps"]))
    mat.set_shader_parameter("start_time", float(Time.get_ticks_msec()) / 1000.0)
    mat.set_shader_parameter("phase", 0.0)
```

- [ ] **Step 4: Run the test — verify it passes**

Run: the GUT command from Step 2. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add godot/scripts/flipbook_player.gd godot/test/test_flipbook.gd
git commit -m "sp1: single-character flipbook player + test"
```

---

## Task 8: The MultiMesh crowd manager

**Files:**
- Create: `godot/scripts/flipbook_crowd.gd`
- Test: `godot/test/test_flipbook.gd` (append)

- [ ] **Step 1: Write the failing test**

```gdscript
func test_crowd_routes_instance_to_its_clip_mesh():
    var crowd = preload("res://scripts/flipbook_crowd.gd").new()
    add_child_autofree(crowd)
    crowd.configure("cowboy", ["cowboy_idle_a", "cowboy_run_shoot_fwd"])
    var id = crowd.add_member("cowboy_idle_a")
    assert_eq(crowd.clip_of(id), "cowboy_idle_a")
    crowd.set_member_clip(id, "cowboy_run_shoot_fwd")
    assert_eq(crowd.clip_of(id), "cowboy_run_shoot_fwd")
    assert_eq(crowd.mesh_instance_count("cowboy_idle_a"), 0)
    assert_eq(crowd.mesh_instance_count("cowboy_run_shoot_fwd"), 1)
```

- [ ] **Step 2: Run it — verify it fails**

Run: the GUT command from Task 7 Step 2. Expected: FAIL — `flipbook_crowd.gd` missing.

- [ ] **Step 3: Write `flipbook_crowd.gd`**

```gdscript
extends Node3D
# Crowd of one character. One MultiMeshInstance3D per clip; each member
# lives in the mesh of its current clip. Per-instance custom data (a
# Color) carries: r=start_time, g=phase, b=flip(0/1).

const ATLAS_DIR := "res://assets/sprites/atlases/"
const FLIPBOOK_SHADER := preload("res://shaders/flipbook.gdshader")

var _meshes := {}          # clip_name -> MultiMeshInstance3D
var _member_clip := {}     # member_id -> clip_name
var _member_xform := {}    # member_id -> Transform3D
var _next_id := 0

func configure(_character: String, clips: Array) -> void:
    for clip in clips:
        var mmi := MultiMeshInstance3D.new()
        var mm := MultiMesh.new()
        mm.transform_format = MultiMesh.TRANSFORM_3D
        mm.use_custom_data = true
        var q := QuadMesh.new()
        q.size = Vector2(2.0, 2.0)
        mm.mesh = q
        mmi.multimesh = mm
        var meta: Dictionary = JSON.parse_string(
            FileAccess.get_file_as_string(ATLAS_DIR + clip + ".atlas.json"))
        var mat := ShaderMaterial.new()
        mat.shader = FLIPBOOK_SHADER
        mat.set_shader_parameter("atlas", load(ATLAS_DIR + clip + ".png"))
        mat.set_shader_parameter("cols", int(meta["cols"]))
        mat.set_shader_parameter("rows", int(meta["rows"]))
        mat.set_shader_parameter("frame_count", int(meta["frame_count"]))
        mat.set_shader_parameter("fps", float(meta["fps"]))
        mat.set_shader_parameter("use_instance", 1)   # read start/phase/flip per instance
        mmi.material_override = mat
        add_child(mmi)
        _meshes[clip] = mmi

func add_member(clip: String, xform := Transform3D.IDENTITY) -> int:
    var id := _next_id
    _next_id += 1
    _member_clip[id] = clip
    _member_xform[id] = xform
    _rebuild(clip)
    return id

func set_member_clip(id: int, clip: String) -> void:
    var old: String = _member_clip[id]
    if old == clip:
        return
    _member_clip[id] = clip
    _rebuild(old)
    _rebuild(clip)

func clip_of(id: int) -> String:
    return _member_clip[id]

func mesh_instance_count(clip: String) -> int:
    return _meshes[clip].multimesh.instance_count

func _rebuild(clip: String) -> void:
    var ids := []
    for id in _member_clip:
        if _member_clip[id] == clip:
            ids.append(id)
    var mm: MultiMesh = _meshes[clip].multimesh
    mm.instance_count = ids.size()
    for i in ids.size():
        var id: int = ids[i]
        mm.set_instance_transform(i, _member_xform[id])
        # r=start_time (now), g=random phase, b=random flip
        mm.set_instance_custom_data(i, Color(
            float(Time.get_ticks_msec()) / 1000.0, randf(),
            1.0 if randf() < 0.5 else 0.0, 0.0))
```

- [ ] **Step 4: Run the test — verify it passes**

Run: the GUT command. Expected: PASS (both Task 7 and Task 8 tests).

- [ ] **Step 5: Commit**

```bash
git add godot/scripts/flipbook_crowd.gd godot/test/test_flipbook.gd
git commit -m "sp1: MultiMesh crowd manager (per-clip mesh routing) + test"
```

---

## Task 9: The SP1 preview scene + debug-menu tier

**Files:**
- Create: `godot/scenes/sprite_anim_preview.tscn`, `godot/scripts/sprite_anim_preview.gd`
- Modify: `godot/scripts/debug_menu.gd`, `godot/scenes/debug_menu.tscn`

- [ ] **Step 1: Build the preview scene**

`sprite_anim_preview.tscn`: a `Node3D` root + `Camera3D` (match the level camera: y=7, z=3, pitch −55°, fov 50) + a `CanvasLayer` with a `Label` for the readout. Script `sprite_anim_preview.gd`:

```gdscript
extends Node3D
# SP1 preview: every character animating at once + a live perf readout.
const FlipbookPlayer = preload("res://scripts/flipbook_player.gd")
const FlipbookCrowd = preload("res://scripts/flipbook_crowd.gd")

@onready var readout: Label = $UI/Readout

func _ready() -> void:
    _spawn_singleton("pete_idle", Vector3(-6, 0, 0))
    _spawn_singleton("humbug_idle", Vector3(-4.5, 0, 0))
    _spawn_crowd("cowboy", ["cowboy_idle_a", "cowboy_run_shoot_fwd"], 12, Vector3(-2.5, 0, 0))
    _spawn_crowd("vagrant", ["vagrant_idle", "vagrant_shoot"], 14, Vector3(0, 0, 0))
    _spawn_crowd("prospector", ["prospector_idle_drinking"], 4, Vector3(2.5, 0, 0))
    _spawn_crowd("pusher", ["pusher_push_left_a", "pusher_push_right_a"], 20, Vector3(4.5, 0, 0))
    _spawn_crowd("chicken", ["chicken_rir_flap", "chicken_leghorn_scramble",
        "chicken_silkie_tumble"], 30, Vector3(7, 0, 0))

func _spawn_singleton(clip: String, pos: Vector3) -> void:
    var p = FlipbookPlayer.new()
    p.position = pos
    add_child(p)
    p.set_clip(clip)

func _spawn_crowd(character: String, clips: Array, count: int, origin: Vector3) -> void:
    var c = FlipbookCrowd.new()
    c.position = origin
    add_child(c)
    c.configure(character, clips)
    for i in count:
        var x := Transform3D(Basis(), Vector3(randf_range(-1.5, 1.5), 0,
            randf_range(-1.5, 1.5)))
        c.add_member(clips[i % clips.size()], x)

func _process(_dt: float) -> void:
    readout.text = "FPS %d  draw calls %d  VRAM %.0f MB" % [
        Engine.get_frames_per_second(),
        RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
        RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED) / 1048576.0]
```

- [ ] **Step 2: Add the debug-menu tier**

In `debug_menu.gd` / `debug_menu.tscn`, add a labelled group "Rendering Rebuild" with three buttons (SP1 active, SP2/SP3 disabled placeholders). The SP1 button: `get_tree().change_scene_to_file("res://scenes/sprite_anim_preview.tscn")`. Follow the existing `candy_rustler_rig_preview` launch pattern.

- [ ] **Step 3: Run the preview locally (headless smoke)**

Run: `godot --headless --path godot res://scenes/sprite_anim_preview.tscn` for ~3 s. Expected: no errors; scene instantiates and `_process` runs.

- [ ] **Step 4: Commit**

```bash
git add godot/scenes/sprite_anim_preview.tscn godot/scripts/sprite_anim_preview.gd godot/scripts/debug_menu.gd godot/scenes/debug_menu.tscn
git commit -m "sp1: preview scene + debug-menu Rendering-Rebuild tier"
```

---

## Task 10: Benchmark on the A26 and lock atlas resolution

**Files:** none (tuning task)

- [ ] **Step 1: Build + sideload** — push, let CI build, deliver the APK; user opens debug menu → Rendering Rebuild → SP1.

- [ ] **Step 2: Read the on-screen readout** on the A26 — FPS, draw calls, VRAM.

- [ ] **Step 3: Tune** — if VRAM is too high or FPS below 30, lower per-frame atlas resolution: re-run `build_atlas.py` with a downscale factor (add a `--scale` arg if needed), regenerate, re-measure. Lock the resolution that holds 30 fps with VRAM headroom.

- [ ] **Step 4: User sign-off** — user confirms the preview looks right and performs on the A26. This sign-off unblocks **Plan 2 (integration)**.

- [ ] **Step 5: Commit** the final atlas resolution / any `build_atlas.py` tuning.

```bash
git add tools/build_atlas.py godot/assets/sprites/atlases/
git commit -m "sp1: lock atlas resolution against A26 benchmark"
```

---

## Out of scope (Plan 2)

Integration into `level_3d` — replacing the video billboards, wiring `phase`/`start_time` from `INSTANCE_CUSTOM` if not done in Task 9, deleting `chromakey.gdshader` and the video-viewport pools. Written after the Task 10 sign-off.
