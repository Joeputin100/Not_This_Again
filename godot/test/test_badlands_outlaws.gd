extends GutTest

# Drives only the pure weighting helper by faking a badlands LevelDef.
const Level3D = preload("res://scripts/level_3d.gd")

func test_badlands_weights_only_emit_monks():
	# The badlands roster must contain exactly the two monk kinds.
	var kinds := {}
	for entry in Level3D.BADLANDS_OUTLAW_WEIGHTS:
		kinds[entry[0]] = true
	assert_true(kinds.has("fireball_monk"), "badlands roster has fireball_monk")
	assert_true(kinds.has("star_monk"), "badlands roster has star_monk")
	assert_eq(kinds.size(), 2, "badlands roster is exactly the two monks")

func test_monk_kinds_have_stats_and_videos():
	for k in ["fireball_monk", "star_monk"]:
		assert_true(Level3D.OUTLAW_KINDS.has(k), "OUTLAW_KINDS missing %s" % k)
		assert_true(Level3D.MONK_OUTLAW_VIDEOS.has(k), "MONK_OUTLAW_VIDEOS missing %s" % k)
		assert_gt(int(Level3D.OUTLAW_KINDS[k]["hp"]), 0, "%s needs hp" % k)
