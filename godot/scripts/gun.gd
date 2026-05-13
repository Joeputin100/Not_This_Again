class_name Gun
extends Resource

# A gun model — data only. Per-shooter runtime state lives in GunState.
# Designed so future variants (rifle, shotgun, gatling, bow) are just new
# .tres files with different exported values.
#
# Defaults below describe the starting Jelly Bean Six-Shooter (iter 45):
#   short range, ~5.5 shots/sec, 6-jelly-bean cylinder, 1 sec reload.
# All other weapons (Liquorice Whip, Jawbreaker Grenades, etc.) ship
# as their own .gd builders or future .tres resources in the same
# format — see memory/project_weapons_catalog.md for the catalog.

@export var display_name: String = "Jelly Bean Six-Shooter"

# Max distance (in pixels) a bullet from this gun travels before it
# despawns. 600 = "short range" on a 1920-tall playfield: bullets die
# roughly a third of the way up. Tactical implication: far obstacles
# can't be shot from the bottom; the cowboy has to wait for them to
# scroll down.
@export var range_px: float = 600.0

# Seconds between successive shots inside the same clip. 0.18 ≈ 5.5
# shots/sec, which matches the pre-iter-21 hardcoded fire_interval so
# the starter feel is preserved.
@export var fire_interval: float = 0.18

# Damage per shot. Threaded through take_bullet_hit on every
# destructible. Six-shooter is caliber 1 (the baseline).
@export var caliber: int = 1

# Shots per clip before a reload is required.
@export var clip_size: int = 6

# Seconds to refill the clip once it hits empty.
@export var reload_time: float = 1.0

# Iter 56+: per-weapon special behaviors. All default to no-effect values
# so the existing Jelly Bean Six-Shooter behavior is unchanged. New
# weapons override these via the WeaponFactory in scripts/weapons.gd.

# Number of enemies a single bullet passes through before despawning.
# 0 (default) = bullet dies on first hit. Liquorice Whip uses 2-3 for
# the multi-target whip arc.
@export var pierce_count: int = 0

# Radius (px) of splash damage when the bullet hits. 0 = no AOE.
# Jawbreaker Grenades use ~120. Bubblegum Bazooka uses ~80.
@export var aoe_radius: float = 0.0

# Seconds an enemy is frozen on hit. 0 = no freeze.
# Caramel Catapult uses 3.0; Laughing Horse's whinny uses 2.0.
@export var freeze_duration_s: float = 0.0

# Seconds an enemy is slowed (50% speed) on hit. 0 = no slow.
# Fudgicle Frostbite Pistol uses 4.0.
@export var slow_duration_s: float = 0.0

# How many bullets are spawned per fire trigger. 1 = single shot.
# Sour Patch Scattergun uses 5; Marzipan Mariachi triples to 3.
@export var bullets_per_shot: int = 1

# Spread angle (radians) for multi-bullet weapons. 0 = perfectly aligned.
@export var spread_radians: float = 0.0
