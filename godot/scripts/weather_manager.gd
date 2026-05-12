extends Node2D

# WeatherManager — instantiates the appropriate weather visual scene and
# mutates level state to apply gameplay effects. Single-shot: called once
# from level._ready after the gun is initialized.
#
# Why a Node2D (not just a static module): the visual particles need a
# parent in the scene tree, and Node2D gives free positioning + z_index
# control so weather effects render above gameplay nodes but below the
# UI canvas layer. (CanvasLayer-rooted UI always draws above Node2D,
# regardless of z_index, so we don't need a layer trick for that.)
#
# z_index is set on the spawned visual itself in the scene file; this
# manager just adds the child and walks away.

const WeatherScript = preload("res://scripts/weather.gd")

# Tracks the visual instance for debugging / test introspection. Tests
# may peek at this to confirm a particle scene was actually added.
var current_weather_type: String = ""
var current_visual: Node = null

# Apply weather to a level. Mutates `level` in place:
#   level._gun.range_px *= range_mult
#   level.steering_speed_mult = steering_mult
#   level.bullet_velocity_mult = bullet_velocity_mult
#   level.bullet_lateral_drift = bullet_drift
#   level.cowboy_wind_drift_x = cowboy_drift_x
# Then instantiates the weather visual scene as a child of self.
#
# Unknown type IDs are a no-op (no visual, no mutation) — defensive
# against typos in @export weather_type. We log via DebugLog so the
# COPY-button output catches the misconfig.
func apply_weather(type_id: String, level: Node) -> void:
	if not WeatherScript.is_valid(type_id):
		DebugLog.add("WeatherManager: unknown weather type %s — skipping" % type_id)
		return
	var params: Dictionary = WeatherScript.params_for(type_id)
	current_weather_type = type_id

	# Mutate level. Use .get() with null-check so a partially-initialized
	# level (e.g. test stubs without the gun) doesn't crash here.
	# Matches the defensive pattern used in level._resolve_obstacle_cowboy_
	# collisions (`obstacle.get("_destroyed") == true`).
	if level.get("_gun") != null:
		var gun: Resource = level._gun
		gun.range_px = gun.range_px * float(params["range_mult"])
	# Set state vars unconditionally — level.gd declares all four with
	# identity defaults, so this never fails for the real level. If a
	# test caller passes a Node without these vars, set_indexed would
	# error; in practice we always pass a level instance.
	level.steering_speed_mult = float(params["steering_mult"])
	level.bullet_velocity_mult = float(params["bullet_velocity_mult"])
	level.bullet_lateral_drift = float(params["bullet_drift"])
	level.cowboy_wind_drift_x = float(params["cowboy_drift_x"])

	# Spawn visual. Load via load() (not preload) since the path is
	# data-driven and a missing scene shouldn't crash the whole script.
	var scene_path: String = String(params["scene_path"])
	var packed: PackedScene = load(scene_path) as PackedScene
	if packed != null:
		current_visual = packed.instantiate()
		add_child(current_visual)
	else:
		DebugLog.add("WeatherManager: failed to load %s for %s" % [scene_path, type_id])

	DebugLog.add("WeatherManager applied %s" % type_id)
