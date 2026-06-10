extends GutTest

func test_level_4_def_mountain_snow_jawbreaker():
	var def = load("res://resources/levels/level_4.tres")
	assert_not_null(def, "level_4.tres should load")
	assert_eq(def.terrain, "mountain", "Level 4 terrain is mountain")
	assert_eq(def.weather_type, "SNOW", "Level 4 weather is snow")
	assert_eq(def.difficulty, 4)
	var boss_kind := ""
	for ev in def.events:
		if ev.kind == 5:
			boss_kind = str(ev.params.get("boss", ""))
	assert_eq(boss_kind, "jawbreaker", "Level 4 boss event spawns the Jawbreaker")
