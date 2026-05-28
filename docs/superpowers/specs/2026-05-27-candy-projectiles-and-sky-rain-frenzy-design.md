# Candy Projectiles + Sky-Rain Frenzy — Design

**Date:** 2026-05-27
**Status:** Brainstorm captured; pending implementation (recommended fresh session)

## Why

The candy projectiles (jellybean, frenzy, frostbite, rifle bullets) lack polish. We baked 6 high-quality candy sprites from fizzer's Shadertoy "Unlimited Confectionery" gummy/chocolate materials (`godot/assets/sprites/candy/candy_{red,green,blue,amber,choc_swirl,choc_stripe}.png`, via `godot/shaders/candy_sprite.gdshader`). This spec covers (1) reskinning the existing projectiles with those candies and (2) reworking "Jelly Bean Frenzy" from a triple-stream burst into candies raining from the sky that damage outlaws on contact.

## Part 1 — Projectile reskin

Existing bullet sprites (`godot/assets/sprites/props/`): `bullet_jellybean.png`, `bullet_frenzy.png`, `bullet_frostbite.png`, `bullet_rifle.png`.

Proposed mapping (confirm with user):
- `bullet_jellybean` → random of the 4 gummy candies (red/green/blue/amber)
- `bullet_frenzy` → same gummy set (frenzy fires candy)
- `bullet_frostbite` → blue gummy (cold) — or a new "ice candy" tint variant
- `bullet_rifle` → striped sweet (`choc_stripe`) or amber

Open question: are there more candy projectiles (the 15-weapon catalog in `project_weapons_catalog`)? Enumerate all bullet/projectile sprites before mapping. Some may want new candy variants (e.g. a candy-cane for a specific weapon).

The candy sprite is a static PNG; bullets are 2D sprites in `bullet.gd`. Reskin = swap the texture the bullet scene/script uses, optionally random-pick a color per shot.

## Part 2 — Sky-rain frenzy rework

Current ("Jelly Bean Frenzy", level.gd): `_frenzy_active` makes `_spawn_bullet()` emit a 3-bullet ±15° fan for `FRENZY_DURATION` (5s). Driven by the `jelly_frenzy` bonus pickup (bonus.gd).

New behavior (user-requested "full rework to sky-rain projectiles"):
- During frenzy, candies RAIN from the top of the screen across the play width (not fired from the gun).
- Each falling candy is a projectile that DAMAGES outlaws on contact, then bursts into a candy-shatter puff (so it's a useful bonus, not just visual).
- Candies that reach the bottom without hitting despawn.
- Keep the 5s duration + camera shake on activation.

Design decisions to confirm:
- Does the gun KEEP firing normally during frenzy, with sky-rain on top? Or does frenzy REPLACE gun fire with the rain? (User said "full rework" — leaning toward: gun keeps normal single-shot, sky-rain is the added frenzy damage source.)
- Rain density (candies/sec), fall speed, damage per candy (vs normal bullet).
- Random candy color/type per drop.

### Implementation sketch

- New `scripts/candy_rain.gd` + `scenes/candy_rain.tscn`: a spawner (Node2D/Timer) that emits falling candy sprites across the top during frenzy. Each candy is an Area2D (or reuses a lightweight bullet) that checks outlaw overlap, deals damage, and spawns a shatter particle on hit.
- Hook into level.gd `_frenzy_active`: start/stop the spawner with the frenzy timer.
- Candy-shatter puff: small CPUParticles2D burst (sugar crystals) on contact — could tint to the candy's color.
- Reuse the existing outlaw damage path (whatever `bullet.gd` calls on outlaw hit).

### Files

New:
- `scenes/candy_rain.tscn`, `scripts/candy_rain.gd`
- `scenes/candy_shatter.tscn` (CPUParticles2D burst) — or reuse an existing hit FX
- possibly more `candy_*.png` variants for specific weapons

Modified:
- `scripts/level.gd` — frenzy now drives the rain spawner instead of (or alongside) the bullet fan
- `scripts/bullet.gd` + bullet scenes — swap textures to candy sprites
- `scripts/bonus.gd` — unchanged trigger, new effect

## Performance

All candy art is pre-baked PNG sprites (zero runtime shader cost). The sky-rain is ordinary 2D sprite/particle gameplay — no raymarching. Safe on mobile.

## Done so far (2026-05-27)

- `candy_sprite.gdshader` (gummy + chocolate materials, `LIGHT`→`LDIR` fix)
- 6 baked sprites in `godot/assets/sprites/candy/`
- Shader is bake-only (offline); not shipped as a runtime shader.

## Recommended

Execute in a fresh session (this one is very long). Start by enumerating ALL projectile sprites + confirming the rain-vs-gunfire question, then build the spawner + reskin.
