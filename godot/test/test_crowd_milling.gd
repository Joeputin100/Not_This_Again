extends GutTest

# Idle-milling drift math (FlipbookCrowd.mill_step) — pure + deterministic.

const FlipbookCrowd = preload("res://scripts/flipbook_crowd.gd")

func _rng(seed_v: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_v
	return r

func test_stays_in_bounds_over_long_run():
	var rng := _rng(42)
	var pos := Vector2(0, 2.0)
	var vel := Vector2.ZERO
	var t := 0.0
	for i in range(4000):   # ~66s of simulated drift
		var r: Dictionary = FlipbookCrowd.mill_step(pos, vel, t, 0.016, 3.0, 5.0, rng)
		pos = r["pos"]; vel = r["vel"]; t = r["t"]
		assert_between(pos.x, -3.0, 3.0)
		assert_between(pos.y, 0.3, 5.0)

func test_paused_member_eventually_walks():
	var rng := _rng(7)
	var pos := Vector2.ZERO
	var vel := Vector2.ZERO
	var t := 0.5
	var walked := false
	for i in range(400):
		var r: Dictionary = FlipbookCrowd.mill_step(pos, vel, t, 0.05, 4.0, 6.0, rng)
		pos = r["pos"]; vel = r["vel"]; t = r["t"]
		if vel != Vector2.ZERO:
			walked = true
			break
	assert_true(walked, "a paused member picks a wander direction after its timer")

func test_walking_member_eventually_pauses():
	var rng := _rng(9)
	var vel := Vector2(FlipbookCrowd.MILL_SPEED, 0)
	var pos := Vector2.ZERO
	var t := 1.0
	var paused := false
	for i in range(400):
		var r: Dictionary = FlipbookCrowd.mill_step(pos, vel, t, 0.05, 4.0, 6.0, rng)
		pos = r["pos"]; vel = r["vel"]; t = r["t"]
		if vel == Vector2.ZERO:
			paused = true
			break
	assert_true(paused, "a walking member stops to stand around")

func test_drift_speed_is_gentle():
	var rng := _rng(3)
	var r: Dictionary = FlipbookCrowd.mill_step(Vector2.ZERO, Vector2.ZERO, 0.0, 0.016, 4.0, 6.0, rng)
	var v: Vector2 = r["vel"]
	assert_almost_eq(v.length(), FlipbookCrowd.MILL_SPEED, 0.001, "wander speed = MILL_SPEED")
