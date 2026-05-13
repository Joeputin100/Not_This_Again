class_name LevelDef
extends Resource

# Iter 54: per-level definition resource. Each level has its own .tres
# file declaring its difficulty, terrain, and seed. The level scene reads
# the .tres at _ready instead of relying on @export defaults — this means
# the same level.tscn can serve as level 1, 2, 3... by swapping resource.
#
# Currently level_select passes the level number via GameState.current_level;
# level.gd loads "res://resources/levels/level_{n}.tres" in _ready.

# Difficulty band: 1=Easy(Peppermint), 2=Medium(Fireball),
# 3=Hard(Jellybean), 4=Extreme(Liquorice).
@export var difficulty: int = 1

# Terrain slug: "frontier" / "mine" / "farm" / "mountain".
# Drives the Gold Rush dispatch + future per-terrain visual flavor
# (saloon vs mineshaft vs barn vs mountain pass backdrop).
@export var terrain: String = "frontier"

# Display name (e.g. "FRONTIER STANDOFF"). Used in level intro overlay.
@export var display_name: String = "LEVEL 1"

# Future: seed for procgen segment composition (Phase 2 work).
@export var seed: int = 0

# Future: weather override. Empty = inherit project default.
@export var weather_type: String = ""
