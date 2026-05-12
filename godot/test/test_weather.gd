extends GutTest

# Iter 22d — Weather data class. Verifies the three TYPE constants exist
# and that params_for() returns the documented modifier values for each.
# These tests pin the design contract: if a future iter rebalances weather
# stats, this test fails and forces an intentional update.

const WeatherScript = preload("res://scripts/weather.gd")

# ---------- TYPE constants ----------

func test_type_dust_storm_exists():
	assert_eq(WeatherScript.TYPE_DUST_STORM, "DUST_STORM",
		"DUST_STORM type id stable across iters")

func test_type_rain_exists():
	assert_eq(WeatherScript.TYPE_RAIN, "RAIN")

func test_type_wind_storm_exists():
	assert_eq(WeatherScript.TYPE_WIND_STORM, "WIND_STORM")

func test_all_types_returns_three():
	var types: Array[String] = WeatherScript.all_types()
	assert_eq(types.size(), 3, "exactly three weather types in iter 22d")
	assert_true(types.has("DUST_STORM"))
	assert_true(types.has("RAIN"))
	assert_true(types.has("WIND_STORM"))

# ---------- is_valid ----------

func test_is_valid_accepts_known_types():
	assert_true(WeatherScript.is_valid("DUST_STORM"))
	assert_true(WeatherScript.is_valid("RAIN"))
	assert_true(WeatherScript.is_valid("WIND_STORM"))

func test_is_valid_rejects_unknown():
	assert_false(WeatherScript.is_valid("THUNDERSTORM"))
	assert_false(WeatherScript.is_valid(""))
	assert_false(WeatherScript.is_valid("dust_storm"),
		"case-sensitive — lowercase id is invalid")

# ---------- DUST_STORM params ----------

func test_dust_storm_range_mult_reduces_30_percent():
	var p: Dictionary = WeatherScript.params_for("DUST_STORM")
	assert_almost_eq(float(p["range_mult"]), 0.7, 0.001,
		"dust storm cuts bullet range to 70%")

func test_dust_storm_steering_mult_reduces_30_percent():
	var p: Dictionary = WeatherScript.params_for("DUST_STORM")
	assert_almost_eq(float(p["steering_mult"]), 0.7, 0.001)

func test_dust_storm_no_bullet_modifiers():
	var p: Dictionary = WeatherScript.params_for("DUST_STORM")
	assert_eq(float(p["bullet_velocity_mult"]), 1.0)
	assert_eq(float(p["bullet_drift"]), 0.0)
	assert_eq(float(p["cowboy_drift_x"]), 0.0)

# ---------- RAIN params ----------

func test_rain_bullet_velocity_reduces_20_percent():
	var p: Dictionary = WeatherScript.params_for("RAIN")
	assert_almost_eq(float(p["bullet_velocity_mult"]), 0.8, 0.001,
		"rain slows bullets to 80% velocity")

func test_rain_leaves_steering_and_range_untouched():
	var p: Dictionary = WeatherScript.params_for("RAIN")
	assert_eq(float(p["range_mult"]), 1.0)
	assert_eq(float(p["steering_mult"]), 1.0)

func test_rain_no_drift():
	var p: Dictionary = WeatherScript.params_for("RAIN")
	assert_eq(float(p["bullet_drift"]), 0.0)
	assert_eq(float(p["cowboy_drift_x"]), 0.0)

# ---------- WIND_STORM params ----------

func test_wind_storm_bullet_drift_nonzero():
	var p: Dictionary = WeatherScript.params_for("WIND_STORM")
	# Spec calls for ~40 px/sec. Pin it.
	assert_eq(float(p["bullet_drift"]), 40.0)

func test_wind_storm_cowboy_drift_nonzero():
	var p: Dictionary = WeatherScript.params_for("WIND_STORM")
	assert_eq(float(p["cowboy_drift_x"]), 25.0)

func test_wind_storm_leaves_velocity_and_range():
	var p: Dictionary = WeatherScript.params_for("WIND_STORM")
	assert_eq(float(p["range_mult"]), 1.0)
	assert_eq(float(p["bullet_velocity_mult"]), 1.0)
	assert_eq(float(p["steering_mult"]), 1.0)

# ---------- params_for unknown type ----------

func test_params_for_unknown_returns_empty():
	var p: Dictionary = WeatherScript.params_for("NOPE")
	assert_eq(p.size(), 0, "unknown weather type → empty dict, defensive")

# ---------- scene path sanity ----------

func test_each_weather_has_scene_path():
	for type_id in WeatherScript.all_types():
		var p: Dictionary = WeatherScript.params_for(type_id)
		assert_true(p.has("scene_path"), "%s missing scene_path" % type_id)
		var path: String = String(p["scene_path"])
		assert_true(path.begins_with("res://scenes/weather/"),
			"%s scene_path should live under scenes/weather/, got %s" % [type_id, path])
