extends GutTest

const GameStateScript = preload("res://scripts/game_state.gd")

func test_below_first_threshold_is_one_star_on_win():
	# A win always grants >= 1 star even if bounty is under t1.
	assert_eq(GameStateScript.stars_for(0, [0, 1500, 3500]), 1)

func test_meets_second_threshold():
	assert_eq(GameStateScript.stars_for(1500, [0, 1500, 3500]), 2)

func test_meets_third_threshold():
	assert_eq(GameStateScript.stars_for(9999, [0, 1500, 3500]), 3)

func test_between_thresholds():
	assert_eq(GameStateScript.stars_for(2000, [0, 1500, 3500]), 2)

func test_caps_at_three():
	assert_eq(GameStateScript.stars_for(99999, [0, 10, 20, 30, 40]), 3)
