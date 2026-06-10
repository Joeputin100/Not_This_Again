extends GutTest

const GameStateScript = preload("res://scripts/game_state.gd")

func test_sing_hint_defaults_false():
	var state = autofree(GameStateScript.new())
	assert_false(state.sing_hint_shown)

func test_sing_hint_persists():
	var tmp = "user://test_sing_mode_gamestate.cfg"
	var state = autofree(GameStateScript.new())
	state.SAVE_PATH_OVERRIDE = tmp
	state.sing_hint_shown = true
	state._save_to_disk()
	var s2 = autofree(GameStateScript.new())
	s2.SAVE_PATH_OVERRIDE = tmp
	s2._load_from_disk()
	assert_true(s2.sing_hint_shown, "hint flag round-trips")
