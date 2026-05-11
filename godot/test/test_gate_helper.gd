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

# ---------- apply_effect: ADDITIVE ----------

func test_additive_left_door_adds():
	# 5 posse + 10 → 15
	assert_eq(GateHelper.apply_effect(5, GateHelper.SIDE_LEFT, 10, 2, GateHelper.TYPE_ADDITIVE), 15)

func test_additive_right_door_adds():
	# 5 posse + 2 → 7
	assert_eq(GateHelper.apply_effect(5, GateHelper.SIDE_RIGHT, 10, 2, GateHelper.TYPE_ADDITIVE), 7)

func test_additive_negative_value_subtracts():
	# 5 posse + (-3) → 2
	assert_eq(GateHelper.apply_effect(5, GateHelper.SIDE_LEFT, -3, 10, GateHelper.TYPE_ADDITIVE), 2)

func test_additive_overflow_negative_clamped_to_one():
	# 5 posse + (-99) → -94 → clamped to 1
	assert_eq(GateHelper.apply_effect(5, GateHelper.SIDE_LEFT, -99, 10, GateHelper.TYPE_ADDITIVE), 1)

func test_additive_starting_from_one():
	assert_eq(GateHelper.apply_effect(1, GateHelper.SIDE_LEFT, 4, 2, GateHelper.TYPE_ADDITIVE), 5)

# ---------- apply_effect: MULTIPLICATIVE ----------

func test_multiplicative_left_door_multiplies():
	# 5 posse * 2 → 10
	assert_eq(GateHelper.apply_effect(5, GateHelper.SIDE_LEFT, 2, 3, GateHelper.TYPE_MULTIPLICATIVE), 10)

func test_multiplicative_right_door_multiplies():
	# 5 posse * 3 → 15
	assert_eq(GateHelper.apply_effect(5, GateHelper.SIDE_RIGHT, 2, 3, GateHelper.TYPE_MULTIPLICATIVE), 15)

func test_multiplicative_zero_clamped_to_one():
	# 5 posse * 0 → 0 → clamped to 1
	assert_eq(GateHelper.apply_effect(5, GateHelper.SIDE_LEFT, 0, 3, GateHelper.TYPE_MULTIPLICATIVE), 1)

func test_multiplicative_large_value():
	assert_eq(GateHelper.apply_effect(50, GateHelper.SIDE_RIGHT, 1, 10, GateHelper.TYPE_MULTIPLICATIVE), 500)

func test_multiplicative_one_leaves_unchanged():
	assert_eq(GateHelper.apply_effect(7, GateHelper.SIDE_LEFT, 1, 2, GateHelper.TYPE_MULTIPLICATIVE), 7)

# ---------- gate_is_growing: ADDITIVE ----------

func test_additive_both_positive_growing():
	assert_true(GateHelper.gate_is_growing(5, 3, GateHelper.TYPE_ADDITIVE))

func test_additive_one_negative_shrinking():
	assert_false(GateHelper.gate_is_growing(-3, 10, GateHelper.TYPE_ADDITIVE))

func test_additive_other_negative_shrinking():
	assert_false(GateHelper.gate_is_growing(5, -2, GateHelper.TYPE_ADDITIVE))

func test_additive_both_zero_growing():
	# Zero is neutral; treat as not-shrinking → growing (blue).
	assert_true(GateHelper.gate_is_growing(0, 0, GateHelper.TYPE_ADDITIVE))

func test_additive_negative_to_zero_crosses_threshold():
	# Just barely flipped past zero.
	assert_true(GateHelper.gate_is_growing(0, 10, GateHelper.TYPE_ADDITIVE))
	assert_false(GateHelper.gate_is_growing(-1, 10, GateHelper.TYPE_ADDITIVE))

# ---------- gate_is_growing: MULTIPLICATIVE ----------

func test_multiplicative_both_greater_than_one_growing():
	assert_true(GateHelper.gate_is_growing(2, 3, GateHelper.TYPE_MULTIPLICATIVE))

func test_multiplicative_zero_shrinking():
	assert_false(GateHelper.gate_is_growing(0, 3, GateHelper.TYPE_MULTIPLICATIVE))

func test_multiplicative_one_is_neutral_growing():
	# ×1 = no change; treat as not-shrinking → growing (blue).
	assert_true(GateHelper.gate_is_growing(1, 2, GateHelper.TYPE_MULTIPLICATIVE))

func test_multiplicative_both_one_growing():
	assert_true(GateHelper.gate_is_growing(1, 1, GateHelper.TYPE_MULTIPLICATIVE))
