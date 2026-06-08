extends GutTest

const ChickenChaseRun = preload("res://scripts/chicken_chase_run.gd")

func _run() -> ChickenChaseRun:
	return ChickenChaseRun.new()

func test_starts_unfinished_zero_caught_full_timer():
	var r = _run()
	assert_eq(r.caught, 0)
	assert_false(r.is_over())
	assert_almost_eq(r.time_left, ChickenChaseRun.DURATION, 0.001)

func test_register_catch_increments_and_caps_at_flock():
	var r = _run()
	for i in range(ChickenChaseRun.FLOCK + 3):
		r.register_catch()
	assert_eq(r.caught, ChickenChaseRun.FLOCK, "caught caps at the flock size")

func test_can_lunge_unless_stumbling():
	var r = _run()
	assert_true(r.can_lunge(), "can lunge at start")
	r.stumble()
	assert_false(r.can_lunge(), "cannot lunge while stumbling")

func test_stumble_recovers_after_lockout():
	var r = _run()
	r.stumble()
	r.tick(ChickenChaseRun.STUMBLE_LOCKOUT + 0.05)
	assert_true(r.can_lunge(), "lunge restored after the stumble lockout elapses")

func test_catch_blocked_while_stumbling():
	var r = _run()
	r.stumble()
	var ok: bool = r.try_catch()
	assert_false(ok, "try_catch returns false mid-stumble")
	assert_eq(r.caught, 0, "no catch credited mid-stumble")

func test_try_catch_credits_when_clear():
	var r = _run()
	assert_true(r.try_catch())
	assert_eq(r.caught, 1)

func test_timer_ends_the_run():
	var r = _run()
	r.tick(ChickenChaseRun.DURATION + 0.1)
	assert_true(r.is_over(), "run ends when the timer expires")
	assert_almost_eq(r.time_left, 0.0, 0.001)

func test_run_ends_early_when_flock_complete():
	var r = _run()
	for i in range(ChickenChaseRun.FLOCK):
		r.try_catch()
	assert_true(r.is_over(), "catching the whole flock ends the run early")

func test_tick_after_over_is_noop():
	var r = _run()
	r.tick(ChickenChaseRun.DURATION + 1.0)
	var t: float = r.time_left
	r.tick(5.0)
	assert_eq(r.time_left, t, "ticking after over does nothing")
