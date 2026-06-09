extends GutTest

func test_level_6_def_loads_with_canyon_and_quota():
	var def = load("res://resources/levels/level_6.tres")
	assert_not_null(def, "level_6.tres should load")
	assert_eq(def.terrain, "canyon", "Level 6 terrain is canyon")
	assert_eq(def.difficulty, 6, "Level 6 difficulty is 6")
	assert_gt(def.outlaw_quota, 0, "Level 6 needs an outlaw quota")
	assert_eq(def.star_thresholds.size(), 3, "three star thresholds")
	assert_gt(def.outlaw_quota, 140, "Level 6 quota exceeds Level 5's 140")
