extends GutTest

# Level-4 mountain outlaw cast: the three rejected Jawbreaker silhouettes
# (spec §11.2). Mirrors test_canyon_outlaws.gd — pure data checks; the
# behaviors run on device.

const LevelScript = preload("res://scripts/level_3d.gd")

func test_three_mountain_kinds_registered():
	for kind in ["stacked_totem", "yeti_brute", "snowball_roller"]:
		assert_true(LevelScript.OUTLAW_KINDS.has(kind), "%s in OUTLAW_KINDS" % kind)
		assert_gt(LevelScript.OUTLAW_KINDS[kind]["hp"], 0)
		assert_gt(LevelScript.OUTLAW_KINDS[kind]["height"], 0.0)
		assert_true(LevelScript.MOUNTAIN_OUTLAW_VIDEOS.has(kind), "%s has a video" % kind)

func test_mountain_weights_cover_all_kinds_and_sum_100():
	var total := 0
	var kinds := {}
	for entry in LevelScript.MOUNTAIN_OUTLAW_WEIGHTS:
		total += entry[1]
		kinds[entry[0]] = true
	assert_eq(total, 100, "weights sum to 100")
	assert_eq(kinds.size(), 3, "all three kinds weighted")

func test_video_paths_point_at_mountain_outlaws_dir():
	for kind in LevelScript.MOUNTAIN_OUTLAW_VIDEOS:
		var path: String = LevelScript.MOUNTAIN_OUTLAW_VIDEOS[kind]
		assert_true(path.begins_with("res://assets/videos/mountain_outlaws/"),
			"%s path in mountain_outlaws/" % kind)
		assert_true(path.ends_with(".ogv"))
