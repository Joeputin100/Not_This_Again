extends GutTest

const TerrainThemes = preload("res://scripts/terrain_themes.gd")

func test_frontier_theme_has_required_keys():
	var t: Dictionary = TerrainThemes.get_theme("frontier")
	for k in ["ground_albedo", "ground_detail", "tint_low", "tint_high", "fog_color", "fog_density"]:
		assert_true(t.has(k), "frontier theme missing key %s" % k)

func test_unknown_terrain_falls_back_to_frontier():
	assert_eq(TerrainThemes.get_theme("does_not_exist"), TerrainThemes.get_theme("frontier"))

func test_hill_height_is_periodic():
	for d in [0.0, 13.0, 47.5, 99.9]:
		assert_almost_eq(TerrainThemes.hill_height(d),
			TerrainThemes.hill_height(d + TerrainThemes.HILL_PERIOD), 0.0001)

func test_hill_height_amplitude_bounded():
	var hi := -1000.0
	var lo := 1000.0
	for i in range(280):
		var v: float = TerrainThemes.hill_height(float(i) * 0.5)
		hi = maxf(hi, v); lo = minf(lo, v)
	assert_true(hi - lo > 0.5, "hills should actually undulate")
	assert_true(hi - lo < 6.0, "hills should not spike (got range %.2f)" % (hi - lo))

func test_tint_valley_darker_than_ridge():
	var lo := Color(0.5, 0.4, 0.3)
	var hi := Color(1.0, 0.95, 0.85)
	var valley := TerrainThemes.tint(-2.0, lo, hi, 2.0)
	var ridge := TerrainThemes.tint(2.0, lo, hi, 2.0)
	assert_true(valley.v < ridge.v, "valley should be darker than ridge")

func test_mottle_periodic_in_lz_and_bounded():
	for gx in [-8.0, 0.0, 5.0]:
		for lz in [-3.0, -50.0]:
			assert_almost_eq(TerrainThemes.mottle(gx, lz),
				TerrainThemes.mottle(gx, lz - TerrainThemes.HILL_PERIOD), 0.0001)
	for i in range(200):
		var m: float = TerrainThemes.mottle(float(i) * 0.3, float(-i) * 0.7)
		assert_between(m, 0.78, 1.22)


func test_mottle_strength_scales_and_clamps():
	var a := TerrainThemes.mottle(3.0, 10.0, 1.0)
	var b := TerrainThemes.mottle(3.0, 10.0, 3.0)
	assert_true(a >= 0.78 and a <= 1.16, "legacy clamp holds")
	assert_true(b >= 0.55 and b <= 1.45, "strong clamp holds")
	assert_ne(a, b, "strength changes the value")

func test_mottle_periodic_in_z_over_140():
	assert_almost_eq(TerrainThemes.mottle(2.0, 5.0, 2.0), TerrainThemes.mottle(2.0, 5.0 + 140.0, 2.0), 0.0001)

func test_cliff_drop_left_only_beyond_trail():
	assert_eq(TerrainThemes.cliff_drop(0.0, 2.5, "left", 30.0), 0.0)
	assert_eq(TerrainThemes.cliff_drop(5.0, 2.5, "left", 30.0), 0.0)
	var near := TerrainThemes.cliff_drop(-3.0, 2.5, "left", 30.0)
	var far := TerrainThemes.cliff_drop(-10.0, 2.5, "left", 30.0)
	assert_true(near > 0.0 and far > near, "drops and deepens leftward")
	assert_true(far <= 30.0, "capped at depth")
	assert_eq(TerrainThemes.cliff_drop(-10.0, 2.5, "", 30.0), 0.0, "no side = no cliff")

func test_scatter_positions_deterministic_and_in_bounds():
	var a := TerrainThemes.scatter_positions(7, 3, 5, -10.0, -4.0, 1.5, 6.0)
	var b := TerrainThemes.scatter_positions(7, 3, 5, -10.0, -4.0, 1.5, 6.0)
	assert_eq(a, b, "same seed/cell -> identical placement")
	assert_eq(a.size(), 5)
	for p in a:
		assert_true(p.y >= -10.0 and p.y <= -4.0, "z in band")
		assert_true(abs(p.x) >= 1.5 and abs(p.x) <= 6.0, "x in shoulder band")

func test_badlands_theme_has_required_keys_and_scatter():
	var t: Dictionary = TerrainThemes.get_theme("badlands")
	# Must NOT fall back to frontier (i.e. it is actually defined).
	assert_ne(t, TerrainThemes.get_theme("frontier"), "badlands should be its own theme")
	for k in ["ground_albedo", "ground_normal", "ground_detail", "tint_low",
			"tint_high", "fog_color", "fog_density", "scatter"]:
		assert_true(t.has(k), "badlands theme missing key %s" % k)
	assert_gt((t["scatter"] as Array).size(), 0, "badlands needs scatter props")

func test_badlands_is_warm_toned():
	var t: Dictionary = TerrainThemes.get_theme("badlands")
	var hi: Color = t["tint_high"]
	assert_gt(hi.r, hi.b, "badlands ridge tint should be warm (red > blue)")

func test_canyon_theme_present_and_dark_cool():
	var t: Dictionary = TerrainThemes.get_theme("canyon")
	assert_ne(t, TerrainThemes.get_theme("frontier"), "canyon should be its own theme")
	for k in ["ground_albedo", "ground_normal", "ground_detail", "tint_low",
			"tint_high", "fog_color", "fog_density", "scatter", "cliff"]:
		assert_true(t.has(k), "canyon theme missing key %s" % k)
	var hi: Color = t["tint_high"]
	assert_lt(hi.r, hi.b, "canyon ridge tint should be cool (blue > red) for a night look")
	assert_not_null(t["cliff"], "canyon has a cliff side")
