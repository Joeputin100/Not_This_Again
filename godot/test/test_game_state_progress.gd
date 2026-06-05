extends GutTest

const GameStateScript = preload("res://scripts/game_state.gd")
var state: Node

func before_each():
	state = autofree(GameStateScript.new())

func test_record_level_result_stores_best():
	state.record_level_result(1, 2, 1800)
	assert_eq(state.level_best.get(1, {}).get("stars", 0), 2)
	assert_eq(state.level_best.get(1, {}).get("bounty", 0), 1800)

func test_record_level_result_keeps_max():
	state.record_level_result(1, 2, 1800)
	state.record_level_result(1, 1, 600)   # worse run must not lower the best
	assert_eq(state.level_best[1]["stars"], 2)
	assert_eq(state.level_best[1]["bounty"], 1800)

func test_record_level_result_improves():
	state.record_level_result(1, 1, 600)
	state.record_level_result(1, 3, 4000)
	assert_eq(state.level_best[1]["stars"], 3)
	assert_eq(state.level_best[1]["bounty"], 4000)

func test_just_won_level_defaults_zero():
	assert_eq(state.just_won_level, 0)

func test_persistence_round_trip():
	var tmp = "user://test_gamestate_progress.cfg"
	state.SAVE_PATH_OVERRIDE = tmp
	state.current_level = 3
	state.record_level_result(2, 3, 4200)
	state._save_to_disk()
	var s2 = autofree(GameStateScript.new())
	s2.SAVE_PATH_OVERRIDE = tmp
	s2._load_from_disk()
	assert_eq(s2.current_level, 3)
	assert_eq(s2.level_best.get(2, {}).get("stars", 0), 3)
