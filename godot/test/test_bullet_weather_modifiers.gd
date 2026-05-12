extends GutTest

# Iter 22d — bullet weather modifiers (velocity_mult, lateral_drift).
# Confirms the bullet honors per-spawn modifiers set by level._spawn_bullet
# from level.bullet_velocity_mult and level.bullet_lateral_drift.

const BulletScene = preload("res://scenes/bullet.tscn")

# ---------- velocity_mult ----------

func test_default_velocity_mult_is_one():
	var bullet: Node2D = BulletScene.instantiate()
	add_child_autofree(bullet)
	assert_eq(bullet.velocity_mult, 1.0,
		"default velocity_mult is no-effect 1.0")

func test_half_velocity_mult_halves_y_movement():
	var slow: Node2D = BulletScene.instantiate()
	slow.position = Vector2(540, 1500)
	slow.velocity_mult = 0.5
	add_child_autofree(slow)
	var slow_start_y: float = slow.position.y
	# Direct _process call so we don't depend on a frame timing.
	slow._process(0.1)
	var slow_moved: float = slow_start_y - slow.position.y

	var fast: Node2D = BulletScene.instantiate()
	fast.position = Vector2(540, 1500)
	fast.velocity_mult = 1.0
	add_child_autofree(fast)
	var fast_start_y: float = fast.position.y
	fast._process(0.1)
	var fast_moved: float = fast_start_y - fast.position.y

	# Slow bullet should travel roughly half as far in the same delta.
	assert_almost_eq(slow_moved, fast_moved * 0.5, 1.0,
		"velocity_mult=0.5 should halve y-distance per tick (slow=%.1f fast=%.1f)" % [slow_moved, fast_moved])

func test_zero_velocity_mult_stops_y_movement():
	var bullet: Node2D = BulletScene.instantiate()
	bullet.position = Vector2(540, 1500)
	bullet.velocity_mult = 0.0
	add_child_autofree(bullet)
	var start_y: float = bullet.position.y
	bullet._process(0.1)
	assert_eq(bullet.position.y, start_y,
		"velocity_mult=0.0 means bullet is frozen on y")

# ---------- lateral_drift ----------

func test_default_lateral_drift_is_zero():
	var bullet: Node2D = BulletScene.instantiate()
	add_child_autofree(bullet)
	assert_eq(bullet.lateral_drift, 0.0,
		"default lateral_drift is no-effect 0.0")

func test_no_drift_keeps_x_constant():
	var bullet: Node2D = BulletScene.instantiate()
	bullet.position = Vector2(540, 1500)
	bullet.lateral_drift = 0.0
	add_child_autofree(bullet)
	bullet._process(0.1)
	assert_eq(bullet.position.x, 540.0,
		"with lateral_drift=0, x should not change")

func test_positive_drift_moves_x_rightward():
	var bullet: Node2D = BulletScene.instantiate()
	bullet.position = Vector2(540, 1500)
	bullet.lateral_drift = 40.0
	add_child_autofree(bullet)
	var start_x: float = bullet.position.x
	# 0.1s at 40 px/sec → ~4px right.
	bullet._process(0.1)
	assert_almost_eq(bullet.position.x, start_x + 4.0, 0.5,
		"lateral_drift=40 should move bullet ~4px in 0.1s")

func test_negative_drift_moves_x_leftward():
	var bullet: Node2D = BulletScene.instantiate()
	bullet.position = Vector2(540, 1500)
	bullet.lateral_drift = -40.0
	add_child_autofree(bullet)
	var start_x: float = bullet.position.x
	bullet._process(0.1)
	assert_almost_eq(bullet.position.x, start_x - 4.0, 0.5,
		"lateral_drift=-40 should move bullet ~4px LEFT in 0.1s")

func test_drift_accumulates_over_frames():
	var bullet: Node2D = BulletScene.instantiate()
	bullet.position = Vector2(540, 1500)
	bullet.lateral_drift = 40.0
	add_child_autofree(bullet)
	var start_x: float = bullet.position.x
	# 10 frames of 0.05s → 0.5s total → 20px drift.
	for i in 10:
		bullet._process(0.05)
	assert_almost_eq(bullet.position.x, start_x + 20.0, 1.0,
		"drift accumulates linearly: 40 px/s × 0.5s = 20px")

# ---------- combined ----------

func test_velocity_and_drift_combine_independently():
	# Slow bullet that also drifts: y movement halved, x drift unaffected.
	var bullet: Node2D = BulletScene.instantiate()
	bullet.position = Vector2(540, 1500)
	bullet.velocity_mult = 0.5
	bullet.lateral_drift = 40.0
	add_child_autofree(bullet)
	var start_x: float = bullet.position.x
	var start_y: float = bullet.position.y
	bullet._process(0.1)
	# x drift independent of velocity_mult.
	assert_almost_eq(bullet.position.x, start_x + 4.0, 0.5,
		"lateral drift unaffected by velocity_mult")
	# y movement halved.
	var moved_y: float = start_y - bullet.position.y
	assert_lt(moved_y, 100.0,
		"y movement at velocity_mult=0.5 is much less than 150 (full speed in 0.1s)")
