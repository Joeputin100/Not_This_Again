class_name Weather
extends RefCounted

# Weather — pure data describing the three iter-22d weather types.
#
# Each weather has a VISUAL component (a CPUParticles2D scene living
# under WeatherManager) and a GAMEPLAY component (a set of modifiers
# applied to level._gun.range_px, level.steering_speed_mult,
# level.bullet_velocity_mult, level.bullet_lateral_drift, and
# level.cowboy_wind_drift_x).
#
# Per-level activation: one weather chosen at level start, persists the
# whole level. Future iters may seed/randomize; iter 22d uses a simple
# @export var on level.gd for tuning.
#
# Why RefCounted (not Resource): no .tres files needed for tests, and
# params are static lookups, not designer-tweakable assets. If weather
# stats ever need designer-side balancing, this can swap to a Resource
# subtree without changing callers.

# String IDs used by WeatherManager.apply_weather() and level's
# @export var weather_type. String (not enum) so the scene-editor
# export shows a readable value and so a typo'd type errors visibly
# rather than silently picking the wrong one.
const TYPE_DUST_STORM: String = "DUST_STORM"
const TYPE_RAIN: String = "RAIN"
const TYPE_WIND_STORM: String = "WIND_STORM"

# Centralized param table. Each entry contains every knob WeatherManager
# may need. Anything that's "no effect" stays at the identity value:
# multipliers at 1.0, drifts at 0.0. This means adding a new weather
# only requires adding its row and its scene; the manager loop doesn't
# branch per-type.
#
# Fields:
#   scene_path:           CPUParticles2D scene to instantiate above gameplay
#   range_mult:           multiplied into level._gun.range_px
#   steering_mult:        multiplied into the cowboy follow lerp speed
#   bullet_velocity_mult: multiplied into bullet SPEED at spawn
#   bullet_drift:         lateral px/sec added to bullet x each frame
#   cowboy_drift_x:       lateral px/sec added to cowboy target_x each frame
const _PARAMS: Dictionary = {
	"DUST_STORM": {
		"scene_path": "res://scenes/weather/dust_storm.tscn",
		"range_mult": 0.7,        # bullet range -30%
		"steering_mult": 0.7,     # steering -30%
		"bullet_velocity_mult": 1.0,
		"bullet_drift": 0.0,
		"cowboy_drift_x": 0.0,
	},
	"RAIN": {
		"scene_path": "res://scenes/weather/rain.tscn",
		"range_mult": 1.0,
		"steering_mult": 1.0,
		"bullet_velocity_mult": 0.8,  # bullet velocity -20%
		"bullet_drift": 0.0,
		"cowboy_drift_x": 0.0,
	},
	"WIND_STORM": {
		"scene_path": "res://scenes/weather/wind_storm.tscn",
		"range_mult": 1.0,
		"steering_mult": 1.0,
		"bullet_velocity_mult": 1.0,
		"bullet_drift": 40.0,         # bullets curve right ~40px/sec
		"cowboy_drift_x": 25.0,       # cowboy drifts right ~25px/sec
	},
}

# Returns the params dict for a given type, or an empty dict if unknown.
# Static so callers (tests, WeatherManager) don't need to instantiate
# Weather. Tests rely on this signature to assert constants exist.
static func params_for(type_id: String) -> Dictionary:
	if not _PARAMS.has(type_id):
		return {}
	return _PARAMS[type_id]

# All known type IDs. Used by tests and could be used by a future
# random-pick utility.
static func all_types() -> Array[String]:
	var out: Array[String] = []
	for k in _PARAMS.keys():
		out.append(k as String)
	return out

# True if type_id matches a registered weather.
static func is_valid(type_id: String) -> bool:
	return _PARAMS.has(type_id)
