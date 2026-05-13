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
