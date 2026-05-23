#!/usr/bin/env bash
# SP1 source-clip renders. Run section-by-section; review each clip.
set -euo pipefail
COWBOY=godot/assets/videos/cowboy

# Cyclic clips -> 4s --loop renders. Veo's minimum image-to-video
# duration is 4s; the --loop flag pins the last frame to the start
# image, so the 4s clip plays as a seamless cycle when repeated.
for clip in run_shoot_fwd run_shoot_left run_shoot_right strafe_left strafe_right stand_shoot; do
  tools/veo_render.sh --loop --duration 4 \
    --image "$COWBOY/${clip}_startframe.png" \
    --prompt "cowboy ${clip//_/ }, one smooth seamless cycle, cartoon" \
    --out-name "$clip" --out-dir "$COWBOY"
done

# ----- Pusher clips (Task 3) -----
# 3 leftward push variations + run_forward + melee. Rightward pushes
# are ffmpeg-flipped post-render, not separate Veo renders (per the
# project's source-flip pattern for symmetric pairs).
PUSHER=godot/assets/videos/pusher
mkdir -p "$PUSHER"
PROPS=godot/assets/sprites/props

tools/veo_render.sh --loop --duration 4 --image "$PROPS/pusher_left.png"    --prompt "A cartoon pusher shoving leftward, shoulder down with a strained heave. One smooth seamless looping cycle." --out-name push_left_a --out-dir "$PUSHER"
tools/veo_render.sh --loop --duration 4 --image "$PROPS/pusher_left.png"    --prompt "A cartoon pusher shoving leftward in a low crouch, both hands pushing hard. One smooth seamless looping cycle." --out-name push_left_b --out-dir "$PUSHER"
tools/veo_render.sh --loop --duration 4 --image "$PROPS/pusher_left.png"    --prompt "A cartoon pusher shoving leftward with a staggering effort, feet slipping. One smooth seamless looping cycle." --out-name push_left_c --out-dir "$PUSHER"
tools/veo_render.sh --loop --duration 4 --image "$PROPS/pusher_forward.png" --prompt "A cartoon pusher running forward toward the viewer. One smooth seamless looping cycle." --out-name run_forward --out-dir "$PUSHER"
tools/veo_render.sh --loop --duration 4 --image "$PROPS/pusher_melee.png"   --prompt "A cartoon pusher swinging a forward melee blow. One smooth seamless looping cycle." --out-name melee       --out-dir "$PUSHER"
