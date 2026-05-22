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
