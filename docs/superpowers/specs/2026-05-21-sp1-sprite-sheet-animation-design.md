# SP1 — Sprite-Sheet Character Animation

**Date:** 2026-05-21
**Status:** Design approved; ready for implementation planning.
**Part 1 of 3** of the rendering rebuild — SP1 (animation) · SP2 (camera-through-world) · SP3 (segment procgen).

## 1. Problem

On the target device (Samsung Galaxy A26 5G) the 3D level runs choppily. The cause is **live video decoding**: every animated character — the cowboy and each posse follower, the outlaws, the prospectors, the boss — is a video clip played through a `VideoStreamPlayer`, and each one is a Theora decoder. Around 17 decoders run at once. Video decoding is CPU-heavy, and it is worst on budget phones, which have fewer and weaker CPU cores.

Nothing else in the scene is expensive — the props, gates and effects are static textures with cheap shaders. The video billboards are the one part that does not belong in a shipping mobile game.

## 2. Goal

Replace every video-billboard character with **sprite-sheet flipbook animation**: each animation is a grid of frames baked into one image, played by changing which frame is shown. No decoders, no per-frame video work — just a static texture and a UV offset.

SP1 retires the video-billboard system entirely. After SP1 there is one animation path, not two.

### Performance targets
- **Samsung Galaxy A26 5G:** 30 fps hard floor in the heaviest scene. Frame rate is uncapped — it runs free toward the 120 Hz panel; 30 is the floor, not the target.
- **Android 7 / API 24 (minSdk):** "playable" — runs correctly, no crashes, acceptable feel; frame rate may sit below 30.
- **No dropped animation frames.** Sprite sheets capture the full source frame rate; smoothness is preserved.

## 3. The cast

Every animated character in the 3D level, by rendering type.

**Crowds** (many on screen at once — drawn batched, one draw per clip):
- Cowboy posse (leader + followers)
- Vagrant outlaws (~14 alive at once)
- Prospectors (a few at once)
- Pushers (10–100, in the pushed-wagon mechanic)
- Chickens (a coop-burst flock)

**Singletons** (one on screen — a single sprite):
- Slippery Pete (level-1 boss)
- Professor Humbug (level-select guide)

**Out of scope:**
- The Rustler (level-2 boss) — a hinged cutout-puppet rig, a different animation type; untouched by SP1.
- Captive heroes — deferred.

## 4. Source clips & the atlas pipeline

### 4.1 Existing video characters
Cowboy (12 clips), Pete (9), vagrant (8), prospector (6), Humbug (3) — 38 existing `.ogv` clips, 720×1280, 24 fps, 4 s each.
- **Cyclic clips** (run, strafe, stand-shoot): re-rendered as short `--loop` Veo clips so they loop seamlessly (one clean cycle, every frame kept, no 4-second pop).
- **One-shot performances** (idle, celebrate): kept full-length.

### 4.2 New characters (no existing video — filmed fresh via Veo)
- **Pushers** — 8 clips: push-left ×3, push-right ×3, run-forward ×1, melee ×1. Push-left/right get 3 variations because the shoving mob is the most crowded view. The existing `pusher_left/right/melee.png` seed the Veo start frames; a forward-facing start frame is created for run-forward.
- **Chickens** — 3 breeds (Rhode Island Red, White Leghorn, speckled Silkie) × 3 chaotic animations (frantic flap-in-place, panicked scramble, crowing tumble) = 9 clips, each mirrored left/right for 18 on-screen variations. Plus a loose-feather particle effect for the coop-burst.

### 4.3 The pipeline
One offline tool, run per clip: `.ogv` → extract frames (ffmpeg) → chroma-key each to transparency → assemble into a grid (one atlas PNG) → import into Godot with VRAM compression.

Atlas resolution is **locked during preview-scene benchmarking** (section 6) against measured A26 texture memory and frame time. Memory levers — modest per-frame resolution, on-demand per-character loading, VRAM compression — none of which drops a frame.

## 5. The flipbook runtime

### 5.1 The shader
One shared `flipbook.gdshader` (a 3D shader on a flat quad). Inputs: the atlas texture, its grid size, frame count, fps, a start time, and a per-instance phase offset. It billboards the quad to face the camera, computes the current frame from elapsed time, samples that frame's grid cell, and alpha-scissors the edges (crisp cutout, no transparency-sorting cost).

### 5.2 Singletons (Pete, Humbug)
A single `MeshInstance3D` quad with the flipbook material. A small controller swaps the atlas and resets the start time when the animation state changes.

### 5.3 Crowds (cowboy posse, outlaws, prospectors, pushers, chickens)
Per character, a pool of `MultiMeshInstance3D` — one per animation clip. Each instance lives in the MultiMesh of whatever clip it is currently playing; per-instance custom data carries its start time, phase offset, and (for chickens) a left/right flip flag. The whole posse, running in step, sits in one MultiMesh; mixed-state crowds spread across a few. Draw calls equal the number of (character, clip) pairs on screen — a handful, versus ~17 decoders today.

### 5.4 Deleted
The runtime green-screen (chroma-key) shader and the video-billboard machinery are removed — atlases are pre-keyed.

## 6. The SP1 preview scene

A standalone debug scene, `sprite_anim_preview.tscn`, launched from a new debug-menu tier (a grouped set of SP1/SP2/SP3 buttons, per the directive to build each sub-project as an independently inspectable debug option).

It shows every character animating at once — the singletons, sample crowds, and the chicken coop-burst spectacle (a coop bursts, the flock erupts, feathers fly) — with a live on-screen readout of frame time, draw-call count, and texture memory.

This scene is **both** the validation gate (the user signs it off on the A26 before integration) **and** the benchmark harness where atlas resolution is locked.

## 7. Integration into the game

The final SP1 step, gated on the user's sign-off of the preview scene.
- Each character's video billboard is replaced with its sprite-sheet form.
- Pushers are added as a crowd to the existing pushed-wagon mechanic.
- Chickens are built and demonstrated in the preview scene; wiring them to destructible coops in real levels is SP2's job (coops do not exist in the 3D level yet).
- The video-billboard system is deleted: the chroma-key shader, the video players, the shared and follower viewport pools.

This step changes only *how things are drawn* — gates, bosses and hit-detection are untouched. SP1 cannot break a level; it can only change the frame rate.

## 8. Testing

- **Preview scene:** live frame time, draw-call count and texture memory on the A26 — where atlas resolution is locked.
- **Headline metric:** A26 frame rate before vs after, in the same heavy scene — the video build against the sprite-sheet build.
- **Firebase Test Lab:** the integrated build run across a spread of older/slower devices, to confirm the Android-7 "playable" floor.
- **Smoke test:** the existing automated smoke test confirms the game still boots and runs after integration.

## 9. Deliverable order

1. The atlas-build tool.
2. New Veo renders (pusher and chicken clips) and the cyclic-clip re-renders.
3. Atlases for all clips.
4. The flipbook shader.
5. The SP1 preview scene — the validation gate.
6. Integration into the level, deleting the video system.

## 10. Out of scope (later sub-projects)

- **SP2** — camera-through-world rebuild, recycled gameplay segments, re-integrating the Rustler boss, destructible chicken coops.
- **SP3** — the segment-template procedural-generation system.
