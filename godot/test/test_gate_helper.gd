extends GutTest

const GateHelper = preload("res://scripts/gate_helper.gd")

# ---------- which_side ----------

func test_clearly_left_returns_left():
	assert_eq(GateHelper.which_side(200.0, 540.0), GateHelper.SIDE_LEFT)

func test_clearly_right_returns_right():
	assert_eq(GateHelper.which_side(800.0, 540.0), GateHelper.SIDE_RIGHT)

func test_just_below_divider_is_left():
	assert_eq(GateHelper.which_side(539.99, 540.0), GateHelper.SIDE_LEFT)

func test_exact_divider_treated_as_right():
	# Ties go right (documented behavior).
	assert_eq(GateHelper.which_side(540.0, 540.0), GateHelper.SIDE_RIGHT)

func test_just_above_divider_is_right():
	assert_eq(GateHelper.which_side(540.01, 540.0), GateHelper.SIDE_RIGHT)

# ---------- apply_effect ----------

func test_left_door_adds():
	# 5 posse, +10 gate → 15
	assert_eq(GateHelper.apply_effect(5, GateHelper.SIDE_LEFT, 10, 2), 15)

func test_right_door_multiplies():
	# 5 posse, ×2 gate → 10
	assert_eq(GateHelper.apply_effect(5, GateHelper.SIDE_RIGHT, 10, 2), 10)

func test_negative_addition_clamped_to_one():
	# 5 posse, -10 gate → -5 → clamped to 1
	assert_eq(GateHelper.apply_effect(5, GateHelper.SIDE_LEFT, -10, 2), 1)

func test_zero_multiplier_clamped_to_one():
	# 5 posse, ×0 gate → 0 → clamped to 1
	assert_eq(GateHelper.apply_effect(5, GateHelper.SIDE_RIGHT, 10, 0), 1)

func test_large_multiplier():
	# Sanity: big numbers work
	assert_eq(GateHelper.apply_effect(50, GateHelper.SIDE_RIGHT, 0, 10), 500)

func test_addition_starting_from_one():
	assert_eq(GateHelper.apply_effect(1, GateHelper.SIDE_LEFT, 4, 2), 5)
