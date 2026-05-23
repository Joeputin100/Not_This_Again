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

# ----- Chicken clips (Task 4) -----
# 3 breeds x 3 chaotic animations = 9 source clips.
# NOT source-flipped: the runtime flipbook shader's per-instance flip
# flag doubles visible variety to 18 at draw time.
CHICK=godot/assets/videos/chicken
mkdir -p "$CHICK"

for breed in rir leghorn silkie; do
  tools/veo_render.sh --loop --duration 4 --image "$PROPS/chicken_${breed}.png" \
    --prompt "A cartoon $breed chicken, panicked, flapping its wings frantically in place, bug-eyed terror. One smooth seamless looping cycle." \
    --out-name ${breed}_flap --out-dir "$CHICK"
  # Silkies are so fluffy that "flap in place" and "scramble" read the same on
  # screen, so the silkie scramble gets a beak-open crow to differentiate it
  # from silkie flap. The other breeds' silhouettes already differ enough.
  if [ "$breed" = "silkie" ]; then
    scramble_prompt="A cartoon silkie chicken scrambling in panic, beak wide open mid-crow, running blindly in a tight loop, terrified. One smooth seamless looping cycle."
  else
    scramble_prompt="A cartoon $breed chicken scrambling in panic, running blindly in a tight loop, terrified. One smooth seamless looping cycle."
  fi
  tools/veo_render.sh --loop --duration 4 --image "$PROPS/chicken_${breed}.png" \
    --prompt "$scramble_prompt" \
    --out-name ${breed}_scramble --out-dir "$CHICK"
  tools/veo_render.sh --loop --duration 4 --image "$PROPS/chicken_${breed}.png" \
    --prompt "A cartoon $breed chicken tumbling head-over-heels, legs flailing, beak open mid-crow. One smooth seamless looping cycle." \
    --out-name ${breed}_tumble --out-dir "$CHICK"
done

# ----- Build atlases for every SP1 clip (Task 5 / Task 10) -----
# Runs build_atlas.py on every .ogv under each character dir. Missing dirs
# (characters not yet rendered) are skipped via the -e guard. Output is
# atlas PNG + .atlas.json sidecar keyed by ${dir}_${clipname}.
#
# --scale 0.25 is the locked atlas resolution per Task 10. Source frames
# are 720×1280 (Veo 9:16); a quarter-scale frame is 180×320, which is
# still over-sampled for the device render where each character occupies
# roughly 100–200 px of screen height. Dropped the APK from ~1.3 GB
# (source-res atlases) to ~350 MB (locked-res atlases).
ATLAS=godot/assets/sprites/atlases
mkdir -p "$ATLAS"
for dir in cowboy pete vagrant prospector humbug pusher chicken; do
  for clip in godot/assets/videos/$dir/*.ogv; do
    [ -e "$clip" ] || continue
    base=$(basename "$clip" .ogv)
    python3 tools/build_atlas.py --clip "$clip" --scale 0.25 --out "$ATLAS/${dir}_${base}"
  done
done
