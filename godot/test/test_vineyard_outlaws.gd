extends GutTest

# Drives only the pure weighting helper by faking a vineyard LevelDef.
const Level3D = preload("res://scripts/level_3d.gd")

func test_vineyard_weights_only_emit_monks():
	# The vineyard roster must contain exactly the two monk kinds.
	var kinds := {}
	for entry in Level3D.VINEYARD_OUTLAW_WEIGHTS:
		kinds[entry[0]] = true
	assert_true(kinds.has("fireball_monk"), "vineyard roster has fireball_monk")
	assert_true(kinds.has("star_monk"), "vineyard roster has star_monk")
	assert_eq(kinds.size(), 2, "vineyard roster is exactly the two monks")

func test_monk_kinds_have_stats_and_videos():
	for k in ["fireball_monk", "star_monk"]:
		assert_true(Level3D.OUTLAW_KINDS.has(k), "OUTLAW_KINDS missing %s" % k)
		assert_true(Level3D.MONK_OUTLAW_VIDEOS.has(k), "MONK_OUTLAW_VIDEOS missing %s" % k)
		assert_gt(int(Level3D.OUTLAW_KINDS[k]["hp"]), 0, "%s needs hp" % k)
