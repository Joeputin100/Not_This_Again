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

# Win/retry flow: ascending bounty cutoffs for 1/2/3 stars. t1 should be
# reachable simply by finishing (a win always grants >= 1 star). Tuned per level.
@export var star_thresholds: Array[int] = [0, 1500, 3500]

# Win/retry flow: number of outlaws to clear before the boss appears. The
# top-left taffy badge counts this down; reaching 0 triggers the boss. 0 = use
# the legacy distance/timer boss trigger instead.
@export var outlaw_quota: int = 60

# SP2 Level Toolkit: the level as data. `events` is a distance-indexed timeline
# (LevelPlayer fires each as the scrolled distance crosses it); `goal` is the
# win condition. See docs/superpowers/specs/2026-05-31-sp2-level-toolkit-design.md.
enum Goal { REACH_END, DEFEAT_BOSS, SURVIVE }

@export var goal: int = Goal.DEFEAT_BOSS
@export var goal_param: float = 0.0   # REACH_END: end-distance · SURVIVE: seconds
@export var length: float = 0.0       # total path distance (world units)
@export var start_posse: int = 5      # posse size the level begins with
@export var events: Array[LevelEvent] = []

# Soda-Crush level-start modal: a short human goal string derived from the
# win condition + outlaw quota + boss. `level_num` picks the boss (level 2 is
# The Candy Rustler, every other DEFEAT_BOSS level is Slippery Pete) — matching
# level_3d's _boss_kind() mapping.
static func goal_text(def: LevelDef, level_num: int = 1) -> String:
	if def == null:
		return "Reach the end of the trail!"
	match def.goal:
		Goal.DEFEAT_BOSS:
			var boss_name: String = "The Candy Rustler" if level_num == 2 else "Slippery Pete"
			return "Clear %d outlaws, then defeat %s!" % [def.outlaw_quota, boss_name]
		Goal.SURVIVE:
			return "Survive %d seconds!" % int(def.goal_param)
		_:
			return "Reach the end of the trail!"

