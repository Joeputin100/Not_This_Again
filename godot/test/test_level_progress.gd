extends GutTest

const LevelProgressScript = preload("res://scripts/level_progress.gd")

var p: RefCounted

func before_each():
	p = LevelProgressScript.new()

# ---------- default state ----------

func test_starts_with_zero_total():
	assert_eq(p.gates_total, 0)

func test_starts_with_zero_passed():
	assert_eq(p.gates_passed, 0)

func test_not_complete_at_default():
	assert_false(p.is_complete())

func test_progress_zero_when_no_gates():
	assert_eq(p.progress_fraction(), 0.0)

# ---------- reset ----------

func test_reset_sets_total():
	p.reset(3)
	assert_eq(p.gates_total, 3)

func test_reset_clears_passed():
	p.gates_passed = 5
	p.reset(3)
	assert_eq(p.gates_passed, 0)

func test_reset_clamps_negative_total_to_zero():
	p.reset(-1)
	assert_eq(p.gates_total, 0)

# ---------- record_pass ----------

func test_record_pass_increments():
	p.reset(3)
	p.record_pass()
	assert_eq(p.gates_passed, 1)

func test_three_passes_accumulate():
	p.reset(3)
	p.record_pass()
	p.record_pass()
	p.record_pass()
	assert_eq(p.gates_passed, 3)

# ---------- is_complete ----------

func test_not_complete_with_zero_passed_of_three():
	p.reset(3)
	assert_false(p.is_complete())

func test_not_complete_with_two_passed_of_three():
	p.reset(3)
	p.record_pass()
	p.record_pass()
	assert_false(p.is_complete())

func test_complete_when_passed_equals_total():
	p.reset(3)
	p.record_pass()
	p.record_pass()
	p.record_pass()
	assert_true(p.is_complete())

func test_complete_stays_true_on_over_record():
	# Defensive: if a buggy caller records more than total, still complete.
	p.reset(3)
	p.record_pass()
	p.record_pass()
	p.record_pass()
	p.record_pass()
	assert_true(p.is_complete())

# ---------- gates_remaining ----------

func test_remaining_full_at_start():
	p.reset(3)
	assert_eq(p.gates_remaining(), 3)

func test_remaining_decrements():
	p.reset(3)
	p.record_pass()
	assert_eq(p.gates_remaining(), 2)

func test_remaining_zero_when_complete():
	p.reset(2)
	p.record_pass()
	p.record_pass()
	assert_eq(p.gates_remaining(), 0)

func test_remaining_clamped_to_zero_on_over_record():
	p.reset(2)
	p.record_pass()
	p.record_pass()
	p.record_pass()
	assert_eq(p.gates_remaining(), 0)

# ---------- progress_fraction ----------

func test_progress_zero_at_start():
	p.reset(4)
	assert_eq(p.progress_fraction(), 0.0)

func test_progress_half():
	p.reset(4)
	p.record_pass()
	p.record_pass()
	assert_almost_eq(p.progress_fraction(), 0.5, 0.001)

func test_progress_full():
	p.reset(4)
	for i in 4:
		p.record_pass()
	assert_almost_eq(p.progress_fraction(), 1.0, 0.001)

func test_progress_clamped_above_one():
	p.reset(2)
	for i in 5:
		p.record_pass()
	assert_eq(p.progress_fraction(), 1.0)
