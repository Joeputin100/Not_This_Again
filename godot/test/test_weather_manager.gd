extends GutTest

# Iter 22d — WeatherManager integration tests. Each weather type, when
# applied to a fresh level instance, should mutate the documented level
# fields. We use level.tscn (not a hand-rolled stub) so the test catches
# regressions in onready/_ready wiring too.

const LevelScene = preload("res://scenes/level.tscn")
const WeatherScript = preload("res://scripts/weather.gd")

var level: Node = null

func before_each():
	# Each test gets a fresh level. before_each is async so we can await
	# process_frame to let @onready vars resolve.
	level = LevelScene.instantiate()
	# We override weather_type BEFORE add_child so level._ready picks it
	# up. Some tests will override to a specific type; the default
	# weather_type is DUST_STORM (in level.gd) so just dropping in
	# does that.
	add_child_autofree(level)
	await get_tree().process_frame
	await get_tree().process_frame

# ---------- WeatherManager wired up ----------

func test_weather_manager_node_exists():
	var wm: Node2D = level.get_node("WeatherManager")
	assert_not_null(wm, "WeatherManager Node2D missing from level.tscn")

func test_weather_manager_onready_resolved():
	assert_not_null(level.weather_manager,
		"level.weather_manager @onready did not resolve")

# ---------- DUST_STORM ----------

func test_dust_storm_reduces_gun_range():
	# Default weather_type on level.gd is DUST_STORM, so before_each
	# already triggered application. _gun.range_px should be the base
	# 600 × 0.7 = 420.
	assert_almost_eq(level._gun.range_px, 420.0, 0.5,
		"DUST_STORM should drop bullet range to 70% of 600 = 420")

func test_dust_storm_sets_steering_speed_mult():
	assert_almost_eq(level.steering_speed_mult, 0.7, 0.001,
		"DUST_STORM should set steering_speed_mult to 0.7")

func test_dust_storm_leaves_bullet_state_default():
	# DUST_STORM shouldn't touch bullet velocity or drift.
	assert_eq(level.bullet_velocity_mult, 1.0)
	assert_eq(level.bullet_lateral_drift, 0.0)
	assert_eq(level.cowboy_wind_drift_x, 0.0)

# ---------- RAIN ----------

func _build_level_with(type_id: String) -> Node:
	# Builds a level whose weather_type is set BEFORE _ready runs, so the
	# WeatherManager.apply_weather call inside _ready picks up the right
	# value. We can't reuse the before_each level here because that one
	# has already had DUST_STORM applied.
	var lv: Node = LevelScene.instantiate()
	lv.weather_type = type_id
	add_child_autofree(lv)
	await get_tree().process_frame
	await get_tree().process_frame
	return lv

func test_rain_sets_bullet_velocity_mult():
	var rainy: Node = await _build_level_with("RAIN")
	assert_almost_eq(rainy.bullet_velocity_mult, 0.8, 0.001,
		"RAIN should set bullet_velocity_mult to 0.8")

func test_rain_leaves_range_and_steering_untouched():
	var rainy: Node = await _build_level_with("RAIN")
	# Range stays at the gun default (600) — no multiplier in rain.
	assert_almost_eq(rainy._gun.range_px, 600.0, 0.5)
	assert_eq(rainy.steering_speed_mult, 1.0)

func test_rain_no_drift():
	var rainy: Node = await _build_level_with("RAIN")
	assert_eq(rainy.bullet_lateral_drift, 0.0)
	assert_eq(rainy.cowboy_wind_drift_x, 0.0)

# ---------- WIND_STORM ----------

func test_wind_storm_sets_bullet_lateral_drift():
	var windy: Node = await _build_level_with("WIND_STORM")
	assert_eq(windy.bullet_lateral_drift, 40.0,
		"WIND_STORM should set bullet_lateral_drift to 40 px/sec")

func test_wind_storm_sets_cowboy_wind_drift_x():
	var windy: Node = await _build_level_with("WIND_STORM")
	assert_eq(windy.cowboy_wind_drift_x, 25.0,
		"WIND_STORM should set cowboy_wind_drift_x to 25 px/sec")

func test_wind_storm_leaves_steering_and_velocity_untouched():
	var windy: Node = await _build_level_with("WIND_STORM")
	assert_eq(windy.steering_speed_mult, 1.0)
	assert_eq(windy.bullet_velocity_mult, 1.0)
	assert_almost_eq(windy._gun.range_px, 600.0, 0.5)

# ---------- Unknown weather type ----------

func test_unknown_weather_type_is_noop():
	var lv: Node = LevelScene.instantiate()
	lv.weather_type = "BLIZZARD"
	add_child_autofree(lv)
	await get_tree().process_frame
	await get_tree().process_frame
	# All weather state stays at defaults; gun range unchanged.
	assert_eq(lv.steering_speed_mult, 1.0)
	assert_eq(lv.bullet_velocity_mult, 1.0)
	assert_eq(lv.bullet_lateral_drift, 0.0)
	assert_eq(lv.cowboy_wind_drift_x, 0.0)
	assert_almost_eq(lv._gun.range_px, 600.0, 0.5)

# ---------- Wind drift moves cowboy target_x ----------

func test_wind_drift_pushes_target_x_over_time():
	# This is the gameplay-integration assertion for WIND_STORM. With
	# cowboy_wind_drift_x=25 and no player input, target_x should drift
	# right by ~12.5px after 0.5s.
	var windy: Node = await _build_level_with("WIND_STORM")
	var start_target: float = windy.target_x
	# Tick _process for 0.5s of simulated time.
	for i in 30:
		windy._process(0.016)
	# At 25 px/sec for ~0.48s of accumulated ticks → ~12px drift.
	# Use a generous tolerance because rounding accumulates.
	assert_gt(windy.target_x, start_target + 8.0,
		"wind drift should push target_x rightward (start=%.1f end=%.1f)" % [start_target, windy.target_x])
