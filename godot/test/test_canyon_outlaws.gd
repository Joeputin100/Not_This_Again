extends GutTest
const Level3D = preload("res://scripts/level_3d.gd")

func test_canyon_roster_is_the_two_birds():
	var kinds := {}
	for e in Level3D.CANYON_OUTLAW_WEIGHTS:
		kinds[e[0]] = true
	assert_true(kinds.has("flit_finch"))
	assert_true(kinds.has("peck_jay"))
	assert_eq(kinds.size(), 2)

func test_bird_kinds_have_stats_and_videos():
	for k in ["flit_finch", "peck_jay"]:
		assert_true(Level3D.OUTLAW_KINDS.has(k), "OUTLAW_KINDS missing %s" % k)
		assert_true(Level3D.BIRD_OUTLAW_VIDEOS.has(k), "BIRD_OUTLAW_VIDEOS missing %s" % k)
		assert_gt(int(Level3D.OUTLAW_KINDS[k]["hp"]), 0)
