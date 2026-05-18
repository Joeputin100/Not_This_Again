# Prop PNG drop folder

Place NB2-generated PNGs here. Filenames must match the slugs in
`PROP_TEX_REGISTRY` (in level_3d.gd):

- `cactus_saguaro.png` — tall saguaro, 1.4w × 2.8h world units
- `cactus_barrel.png` — squat barrel cactus, 1.2w × 1.4h
- `cactus_prickly.png` — prickly pear pads, 1.3w × 1.6h
- `tumbleweed.png` — for future tumbleweed obstacle conversion, 1.4 × 1.4
- `rock_small.png` — pebble, 0.8w × 0.6h
- `rock_large.png` — boulder, 1.4w × 1.1h
- `fence_post.png` — wood post (one post; pairs spawn together), 0.4w × 1.1h
- `scrub.png` — sagebrush, 1.0w × 0.6h
- `building_saloon.png` — false-front saloon, 4.5w × 5.5h
- `building_general_store.png` — same dimensions
- `building_bank.png` — same dimensions
- `building_jail.png` — 4.5w × 5.0h
- `building_stables.png` — wider, lower: 5.0w × 4.5h

All assets:

- **Transparent background** (alpha-cutout, no white fringe)
- **Bottom-rooted**: prop should sit on its bottom edge, since the
  spawn helper anchors the bottom of the plane at world y=0
- **Single layer**: no shadows below — the scene's lighting handles that
- **Paper-cutout style**: bold flat shapes, gouache or watercolor texture,
  subtle off-white paper edges suggesting layered cardboard
- **Resolution**: 256×384 is fine (matches the 0.6-aspect bottom-rooted
  plane mesh). Higher is OK but won't be visible at mobile billboard scale.

NB2 prompt template:
```
Wild West [prop name] in flat paper cutout illustration style, hand-painted
gouache texture, simple bold shapes, subtle off-white paper layer edges,
single bottom-rooted composition, transparent background, mobile game asset,
warm desert palette
```

For style consistency across the batch: generate ONE reference prop, then
use NB2's image-to-image to "generate [other prop] in this exact style".

When a PNG is missing, the breathing system spawns a magenta-checker
placeholder so it's obvious what's not yet authored.
