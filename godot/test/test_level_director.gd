extends GutTest

# SP2 slice 2 — LevelDirector pacing: cruise easing, intensity damping, and the
# three approach-zone exits (clear / timer / event) + the CLEAR safety timeout.

const LevelDirector = preload("res://scripts/level_director.gd")

func _settle(d, enemies: int, secs: float) -> void:
	var steps := int(secs * 60.0)
	for i in steps:
		d.update(1.0 / 60.0, enemies)

func test_cruise_eases_to_target_when_quiet():
	var d = LevelDirector.new()
	d.set_cruise(1.5)
	_settle(d, 0, 2.0)
	assert_almost_eq(d.speed_factor(), 1.5, 0.05, "no enemies -> eases up to cruise 1.5")

func test_intensity_damps_speed():
	var d = LevelDirector.new()
	d.set_cruise(1.0)
	_settle(d, 8, 2.0)
	assert_lt(d.speed_factor(), 0.5, "8 enemies -> slowed well below cruise")
	assert_gt(d.speed_factor(), 0.30, "but not below the slow floor")

func test_approach_zone_clear_exit():
	var d = LevelDirector.new()
	d.set_cruise(1.0)
	d.enter_zone(LevelDirector.ApproachExit.CLEAR, 30.0)
	_settle(d, 5, 1.0)
	assert_true(d.world_held(), "zone holds while enemies remain")
	assert_lt(d.speed_factor(), 0.1, "factor eased to ~0 during the hold")
	_settle(d, 0, 0.2)
	assert_false(d.world_held(), "zone resolves once cleared")

func test_approach_zone_timer_exit():
	var d = LevelDirector.new()
	d.enter_zone(LevelDirector.ApproachExit.TIMER, 1.0)
	_settle(d, 9, 0.5)
	assert_true(d.world_held(), "held before the timer")
	_settle(d, 9, 0.7)
	assert_false(d.world_held(), "timer expired -> resumes even with enemies present")

func test_approach_zone_event_exit():
	var d = LevelDirector.new()
	d.enter_zone(LevelDirector.ApproachExit.EVENT, 30.0)
	_settle(d, 9, 0.3)
	assert_true(d.world_held())
	d.notify_event()
	d.update(1.0 / 60.0, 9)
	assert_false(d.world_held(), "event flag resolves the zone")

func test_clear_safety_timeout():
	var d = LevelDirector.new()
	d.enter_zone(LevelDirector.ApproachExit.CLEAR, 1.0)
	_settle(d, 5, 1.2)
	assert_false(d.world_held(), "safety timeout force-resumes a stuck CLEAR zone")
