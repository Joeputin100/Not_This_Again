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
		assert_between(m, 0.78, 1.16)
