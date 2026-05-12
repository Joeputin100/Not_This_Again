#!/usr/bin/env python3
"""Generate Godot SpriteFrames .tres resources from the sliced sprite PNGs.

Output goes to godot/assets/. Two resources:
  - posse_dude_frames.tres: animations "idle", "run_shoot", "die"
  - muzzle_flash_frames.tres: animation "fire"

SpriteFrames .tres format (Godot 4.x):
  [gd_resource type="SpriteFrames" load_steps=N format=3 uid="..."]
  [ext_resource type="Texture2D" path="res://..." id="..."]
  ...
  [resource]
  animations = [{ "frames": [...], "loop": ..., "name": &"...", "speed": ... }, ...]
"""
import os

OUT_DIR = "/home/projects/Not_This_Again/godot/assets"


def gen_sprite_frames(out_filename: str, uid: str,
                      animations: list[dict]) -> None:
    """animations is a list of dicts:
        {"name": "idle", "loop": True, "speed": 6.0, "files": ["posse_idle_00", ...]}
    """
    # Collect all unique textures and assign IDs
    all_files: list[str] = []
    for anim in animations:
        for f in anim["files"]:
            if f not in all_files:
                all_files.append(f)

    lines: list[str] = []
    lines.append(f'[gd_resource type="SpriteFrames" load_steps={len(all_files) + 1} format=3 uid="uid://{uid}"]\n')
    lines.append("")

    # ext_resource block
    file_to_id: dict[str, str] = {}
    for idx, fname in enumerate(all_files, start=1):
        ext_id = f"{idx}_{fname.split('_')[-1]}"  # e.g. "1_00"
        # Ensure unique IDs — append the prefix if needed
        if ext_id in file_to_id.values():
            ext_id = f"{idx}_{fname}"  # full filename
        file_to_id[fname] = ext_id
        lines.append(f'[ext_resource type="Texture2D" path="res://assets/sprites/{fname}.png" id="{ext_id}"]')

    lines.append("")
    lines.append("[resource]")
    lines.append("animations = [")

    for ai, anim in enumerate(animations):
        lines.append("{")
        lines.append('"frames": [')
        for fi, fname in enumerate(anim["files"]):
            ext_id = file_to_id[fname]
            comma = "," if fi < len(anim["files"]) - 1 else ""
            lines.append(f'{{"duration": 1.0, "texture": ExtResource("{ext_id}")}}{comma}')
        lines.append("],")
        lines.append(f'"loop": {"true" if anim["loop"] else "false"},')
        lines.append(f'"name": &"{anim["name"]}",')
        lines.append(f'"speed": {anim["speed"]}')
        lines.append("}" + ("," if ai < len(animations) - 1 else ""))

    lines.append("]")

    with open(f"{OUT_DIR}/{out_filename}", "w") as f:
        f.write("\n".join(lines) + "\n")
    print(f"Wrote {OUT_DIR}/{out_filename}: {len(all_files)} textures, {len(animations)} animations")


if __name__ == "__main__":
    # Posse dude — idle (6 fr, looped, slow), run_shoot (8 fr, looped,
    # fast), die (3 fr, no loop, medium).
    gen_sprite_frames("posse_dude_frames.tres", "b22a_posse_frames", [
        {
            # Iter 25 bumped 6 → 10fps after sideload feedback that the
            # foot-tap looked choppy. At 10fps the 6-frame cycle completes
            # in 0.6s — quick enough to read as movement, slow enough that
            # individual poses don't blur together.
            "name": "idle",
            "loop": True,
            "speed": 10.0,
            "files": [f"posse_idle_{i:02d}" for i in range(6)],
        },
        {
            # Iter 25 bumped 12 → 20fps. Run cycle now completes in 0.4s
            # — sells "running hard" without the in-between-frames blur
            # that more art (or Skeleton2D rigging) would otherwise need.
            "name": "run_shoot",
            "loop": True,
            "speed": 20.0,
            "files": [f"posse_run_shoot_{i:02d}" for i in range(8)],
        },
        {
            "name": "die",
            "loop": False,
            "speed": 8.0,
            "files": [f"posse_die_{i:02d}" for i in range(3)],
        },
    ])

    # Muzzle flash — one-shot "fire" animation. 30fps so the whole flash
    # plays in ~200ms.
    gen_sprite_frames("muzzle_flash_frames.tres", "b22a_muzzle_flash", [
        {
            "name": "fire",
            "loop": False,
            "speed": 30.0,
            "files": [f"muzzle_flash_{i:02d}" for i in range(6)],
        },
    ])

    print("\nDone.")
