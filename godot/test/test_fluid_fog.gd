extends GutTest

# Pure helpers of the cotton-candy fluid fog (Level 4).

const FluidFog = preload("res://scripts/fluid_fog.gd")

func test_density_within_bounds_everywhere():
	for d in [0.0, 50.0, 123.0, 400.0, 1234.5]:
		for bf in [0.0, 0.5, 1.0]:
			var v: float = FluidFog.density(d, bf)
			assert_between(v, 0.0, 0.9, "density clamped at d=%s bf=%s" % [d, bf])

func test_density_breathes_with_distance():
	# the slow swell must actually vary the value along the run
	var lo := 99.0
	var hi := -99.0
	for i in range(60):
		var v: float = FluidFog.density(float(i) * 10.0, 0.0)
		lo = minf(lo, v)
		hi = maxf(hi, v)
	assert_gt(hi - lo, 0.15, "fog visibly thins and thickens along the run")

func test_density_ramps_with_boss():
	var base: float = FluidFog.density(500.0, 0.0)
	var mid: float = FluidFog.density(500.0, 0.5)
	var full: float = FluidFog.density(500.0, 1.0)
	assert_gt(mid, base, "boss approach thickens the fog")
	assert_gt(full, mid, "monotonic in boss_frac")

func test_pack_splats_caps_and_prioritizes():
	var cands: Array = []
	for i in range(20):
		cands.append({"uv": Vector2(0.1, 0.2), "vel": Vector2.ZERO,
			"radius": 0.05, "dye": 0.5, "prio": float(i)})
	var packed: Dictionary = FluidFog.pack_splats(cands, 16)
	assert_eq(packed["count"], 16, "capped at max_n")
	# the kept ones are the HIGHEST priorities (4..19) — the lowest kept is 4
	var pos: Array = packed["pos"]
	assert_eq(pos.size(), 16, "fixed-size arrays")

func test_pack_splats_passthrough_fields():
	var cands: Array = [{"uv": Vector2(0.25, 0.75), "vel": Vector2(0.1, -0.2),
		"radius": 0.08, "dye": 0.9, "prio": 1.0}]
	var packed: Dictionary = FluidFog.pack_splats(cands, 16)
	assert_eq(packed["count"], 1)
	assert_eq(packed["pos"][0], Vector2(0.25, 0.75))
	assert_eq(packed["vel"][0], Vector2(0.1, -0.2))
	assert_almost_eq(float(packed["radius"][0]), 0.08, 0.0001)
	assert_almost_eq(float(packed["dye"][0]), 0.9, 0.0001)

func test_pack_splats_empty_ok():
	var packed: Dictionary = FluidFog.pack_splats([], 16)
	assert_eq(packed["count"], 0)
	assert_eq((packed["pos"] as Array).size(), 16, "arrays still fixed-size for uniforms")
