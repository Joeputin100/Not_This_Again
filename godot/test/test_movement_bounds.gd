extends GutTest

const Mb = preload("res://scripts/movement_bounds.gd")

# ---------- clamp_x ----------

func test_clamps_negative_to_left_margin():
	assert_eq(Mb.clamp_x(-50.0), Mb.MARGIN_X)

func test_clamps_zero_to_left_margin():
	assert_eq(Mb.clamp_x(0.0), Mb.MARGIN_X)

func test_clamps_overshoot_to_right_margin():
	assert_eq(Mb.clamp_x(2000.0), Mb.VIEWPORT_WIDTH - Mb.MARGIN_X)

func test_passes_through_center():
	assert_eq(Mb.clamp_x(540.0), 540.0)

func test_passes_through_left_quarter():
	assert_eq(Mb.clamp_x(270.0), 270.0)

func test_passes_through_right_quarter():
	assert_eq(Mb.clamp_x(810.0), 810.0)

func test_clamps_at_exact_left_margin():
	assert_eq(Mb.clamp_x(Mb.MARGIN_X), Mb.MARGIN_X)

func test_clamps_at_exact_right_margin():
	var right_margin := Mb.VIEWPORT_WIDTH - Mb.MARGIN_X
	assert_eq(Mb.clamp_x(right_margin), right_margin)

# ---------- normalize_x ----------

func test_normalize_at_left_margin_is_zero():
	assert_eq(Mb.normalize_x(Mb.MARGIN_X), 0.0)

func test_normalize_at_right_margin_is_one():
	assert_almost_eq(Mb.normalize_x(Mb.VIEWPORT_WIDTH - Mb.MARGIN_X), 1.0, 0.001)

func test_normalize_center_is_half():
	assert_almost_eq(Mb.normalize_x(Mb.VIEWPORT_WIDTH / 2.0), 0.5, 0.001)

func test_normalize_clamps_below_zero():
	assert_eq(Mb.normalize_x(-100.0), 0.0)

func test_normalize_clamps_above_one():
	assert_eq(Mb.normalize_x(2000.0), 1.0)
