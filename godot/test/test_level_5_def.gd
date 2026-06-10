extends GutTest

func test_level_5_def_loads_with_vineyard_and_quota():
	var def = load("res://resources/levels/level_5.tres")
	assert_not_null(def, "level_5.tres should load")
	assert_eq(def.terrain, "vineyard", "Level 5 terrain is vineyard")
	assert_eq(def.difficulty, 5, "Level 5 difficulty is 5")
	assert_gt(def.outlaw_quota, 0, "Level 5 needs an outlaw quota")
	assert_eq(def.star_thresholds.size(), 3, "three star thresholds")
	# One step harder than Level 4 (quota 120).
	assert_gt(def.outlaw_quota, 120, "Level 5 quota should exceed Level 4's 120")
