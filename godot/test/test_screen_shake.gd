extends GutTest

const ScreenShakeScript = preload("res://scripts/screen_shake.gd")

var shake: RefCounted

func before_each():
	shake = ScreenShakeScript.new()

# ---------- defaults ----------

func test_starts_with_zero_trauma():
	assert_eq(shake.trauma, 0.0)

# ---------- add_trauma ----------

func test_add_trauma_accumulates():
	shake.add_trauma(0.3)
	shake.add_trauma(0.2)
	assert_almost_eq(shake.trauma, 0.5, 0.001)

func test_add_trauma_clamps_to_one():
	shake.add_trauma(0.6)
	shake.add_trauma(0.8)
	assert_eq(shake.trauma, 1.0)

func test_add_trauma_below_zero_clamped():
	# Negative input is nonsensical but should be safely handled.
	shake.add_trauma(-1.0)
	assert_eq(shake.trauma, 0.0)

# ---------- tick / decay ----------

func test_zero_trauma_gives_zero_offset():
	assert_eq(shake.tick(0.016), Vector2.ZERO)

func test_trauma_decays_over_time():
	shake.add_trauma(0.5)
	shake.tick(0.1)
	assert_true(shake.trauma < 0.5)

func test_trauma_decays_at_expected_rate():
	# Default decay = 1.6/sec. From 0.5, 0.25s should bring it to ~0.1.
	shake.add_trauma(0.5)
	shake.tick(0.25)
	assert_almost_eq(shake.trauma, 0.5 - 1.6 * 0.25, 0.001)

func test_trauma_decays_to_floor_of_zero():
	shake.add_trauma(0.2)
	shake.tick(10.0)  # way past
	assert_eq(shake.trauma, 0.0)

# ---------- offset bounds ----------

func test_offset_magnitude_bounded_by_max_offset_at_full_trauma():
	shake.max_offset = 50.0
	shake.add_trauma(1.0)
	# Each axis ∈ [-50, 50]. Magnitude ≤ 50*sqrt(2). Sample many to
	# verify even the worst-case stays bounded.
	for i in 200:
		var offset := shake.tick(0.0) as Vector2
		assert_true(absf(offset.x) <= 50.0, "x out of range: %f" % offset.x)
		assert_true(absf(offset.y) <= 50.0, "y out of range: %f" % offset.y)

func test_offset_scales_with_trauma_squared():
	# At trauma=0.5, offset magnitude per axis should not exceed 0.25*max
	# (because 0.5² = 0.25).
	shake.max_offset = 100.0
	shake.add_trauma(0.5)
	for i in 200:
		var offset := shake.tick(0.0) as Vector2
		assert_true(absf(offset.x) <= 25.0, "x out of range: %f" % offset.x)
		assert_true(absf(offset.y) <= 25.0, "y out of range: %f" % offset.y)

# ---------- reset ----------

func test_reset_clears_trauma():
	shake.add_trauma(0.7)
	shake.reset()
	assert_eq(shake.trauma, 0.0)
