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

## Decisions locked (2026-05-27)

- **Frenzy = augment, not replace.** Gun keeps firing normally; candy sky-rain is added on top for the duration, plus the visual flourish. **Add a camera shake that runs for the whole frenzy** (not just on activation).
- **Rustler is a melee boss** — no candy projectile needed for him.

## Full projectile list (player + hero + enemy)

Player/posse (weapons.gd): Jelly Bean Six-Shooter (default), Liquorice Whip, Cotton Candy Rifle, Gumdrop Gatling, Fudgicle Frostbite Pistol, Jawbreaker Grenades, Screaming Red-Hot TNT.
Hero-locked: Marshmallow Cannon (Sheriff), Stun Whinny (Laughing Horse — freeze, no/again-musical projectile).
Enemy: outlaw_bullet (wants a distinct "bad/sour" candy so incoming danger reads clearly). Rustler: melee, none.

NOTE: bullets are currently drawn as solid-color rounded shapes; `bullet.gd` randomizes each shot's color from 6 flat CANDY_COLORS. The 4 `bullet_*.png` in props/ are **unused legacy**. Reskin = swap the flat shape for a `Sprite2D` with a candy texture, chosen per-weapon via a new `bullet_candy` field on the Gun resource.

## Candy sprite inventory

HAVE (6, baked from fizzer "Unlimited Confectionery"): red/green/blue/amber gummies, white-choc swirl, striped sweet. → cover the jelly-bean weapons (default + frenzy) + liquorice-ish.

HAVE (7th, baked from Nrx "Cotton candy Pac-Man"): `candy_cotton.png` — fluffy pastel pink→blue volumetric floss → Cotton Candy Rifle. DONE.
HAVE (8th, baked from bradjamesgrant "fractal pyramid"): `candy_bomb.png` — round glowing magenta/cyan crystalline orb → candidate for Jawbreaker Grenades or Screaming TNT (bomb/explosive). DONE.

STILL WANT (distinct materials — user is raiding Shadertoy; do NOT gummy-fy everything):
- Marshmallow (soft matte subsurface white) → Marshmallow Cannon
- Jawbreaker / hard candy (glossy concentric layers) → Jawbreaker Grenades
- Icy / frosted → Fudgicle Frostbite
- Red-hot / emissive molten → Screaming TNT
- Sour / "bad" candy (acid tone) → outlaw bullets
- Gumdrop (sugar-crystal dome) → Gumdrop Gatling
- Cookie, Cupcake → extra candy/dessert variety (see found shaders)

## Found Shadertoy shaders to bake (re-grab complete source at bake time)

- **fizzer "Unlimited Confectionery"** — DONE (gummy + chocolate → 6 sprites). Had a clean separable `gummy()` material; easy extract.
- **dr2 "Cookies" (2019)** — hex-tiled raymarched cookie field w/ arm-swirl SDF. Heavy (2.9 fps). NOT a separable material; bake by porting a SINGLE-object raymarch (fix hex cell, fixed cam, strip mutable globals → inout/struct, render one cookie to PNG offline). Source partially captured in chat.
- **dr2 "Cupcakes" (2019)** — same structure (cupcake SDF w/ frosting swirl). Heavy (1.6 fps). Same single-object bake approach. Chat paste was missing tail helpers (PrCylAnDf, HsvToRgb) — re-grab full source.

- **Nrx "Cotton candy Pac-Man" (MlfGR4)** — DONE (`candy_cotton.png`). Volumetric fbm cloud; no mutable globals, only iChannel0 noise-texture (swapped for procedural). Tier 1.5: self-contained volumetric march → sphere.

Bake-to-PNG alpha methods (which to use):
- **Hard-surface candy** (gummy/choc sphere, crisp silhouette) → circular alpha mask in post.
- **Soft/volumetric candy** (cotton candy, marshmallow, anything with fuzzy/translucent edges) → render over white + over black, recover true alpha with `scripts/diff_matte.py`. The capture framebuffer is opaque, so per-pixel shader alpha is otherwise lost.

Extraction difficulty tiers:
1. **Easy** — shader has a separable material fn on a primitive (fizzer gummy). Drop on a sphere, bake.
2. **Hard** — full scene raymarcher where the candy IS the geometry (dr2 cookies/cupcakes). Port a single-object raymarch offline; mutable-global refactor required.
3. **Fallback** — for materials hard to extract OR that we can't find good shaders for (cotton candy, marshmallow), **generate via Imagen** in the established candy style and chroma-key (cheaper than a heavy port).

## Recommended

Execute in a fresh session (this one is very long). Order: (1) enumerate + confirm final candy map, (2) bake all candy sprites (shader-extract where tier-1, single-object port where tier-2, Imagen where tier-3), (3) add `bullet_candy` to Gun + reskin bullet.gd, (4) build the sky-rain spawner + frenzy camera-shake.
