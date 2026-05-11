extends GutTest

const CombosCounterScript = preload("res://scripts/combos_counter.gd")

var c: RefCounted

func before_each():
	c = CombosCounterScript.new()

# ---------- stateful counter ----------

func test_starts_at_zero():
	assert_eq(c.current, 0)

func test_step_increments_and_returns_new_value():
	assert_eq(c.step(), 1)
	assert_eq(c.current, 1)
	assert_eq(c.step(), 2)
	assert_eq(c.current, 2)

func test_reset_to_zero():
	c.step()
	c.step()
	c.reset()
	assert_eq(c.current, 0)

# ---------- label_for ----------

func test_label_empty_for_single():
	assert_eq(CombosCounterScript.label_for(1), "")

func test_label_double_at_two():
	assert_eq(CombosCounterScript.label_for(2), "DOUBLE!")

func test_label_mega_at_three():
	assert_eq(CombosCounterScript.label_for(3), "MEGA!")

func test_label_mega_at_four_and_above():
	assert_eq(CombosCounterScript.label_for(4), "MEGA!")
	assert_eq(CombosCounterScript.label_for(10), "MEGA!")

# ---------- particle_multiplier ----------

func test_particle_mult_single_is_one():
	assert_almost_eq(CombosCounterScript.particle_multiplier(1), 1.0, 0.001)

func test_particle_mult_combo_two():
	assert_almost_eq(CombosCounterScript.particle_multiplier(2), 1.5, 0.001)

func test_particle_mult_combo_three():
	assert_almost_eq(CombosCounterScript.particle_multiplier(3), 2.0, 0.001)

func test_particle_mult_caps_at_three():
	# Beyond combo 3 the multiplier shouldn't keep growing forever.
	assert_almost_eq(CombosCounterScript.particle_multiplier(5), 2.0, 0.001)
	assert_almost_eq(CombosCounterScript.particle_multiplier(100), 2.0, 0.001)

# ---------- trauma_for ----------

func test_trauma_single_is_base():
	assert_almost_eq(CombosCounterScript.trauma_for(1), 0.40, 0.001)

func test_trauma_combo_two_steps_up():
	assert_almost_eq(CombosCounterScript.trauma_for(2), 0.55, 0.001)

func test_trauma_combo_three_steps_up():
	assert_almost_eq(CombosCounterScript.trauma_for(3), 0.70, 0.001)

func test_trauma_combo_four_continues_to_step():
	assert_almost_eq(CombosCounterScript.trauma_for(4), 0.85, 0.001)

func test_trauma_caps_at_combo_four():
	assert_almost_eq(CombosCounterScript.trauma_for(5), 0.85, 0.001)
	assert_almost_eq(CombosCounterScript.trauma_for(99), 0.85, 0.001)
