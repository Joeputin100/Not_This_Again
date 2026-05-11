extends GutTest

const BulletScene = preload("res://scenes/bullet.tscn")

var bullet: Node2D

func before_each():
	bullet = BulletScene.instantiate()
	add_child_autofree(bullet)
	await get_tree().process_frame

func test_added_to_bullets_group():
	assert_true(bullet.is_in_group("bullets"),
		"bullet should add itself to 'bullets' group on _ready")

func test_moves_upward_per_process_tick():
	bullet.position = Vector2(540, 1500)
	var initial_y := bullet.position.y
	bullet._process(0.1)
	# After 0.1s at SPEED=1500, bullet should have moved up ~150px.
	assert_lt(bullet.position.y, initial_y - 100,
		"bullet should move upward at least 100px in 0.1s")

func test_x_unaffected_by_process():
	bullet.position = Vector2(300, 1500)
	bullet._process(0.1)
	assert_eq(bullet.position.x, 300.0,
		"bullet should only move on Y axis, not X")

func test_speed_constant_value():
	# Reasonable sanity check on the constant.
	assert_gt(bullet.SPEED, 100.0, "SPEED should be substantial")
	assert_lt(bullet.SPEED, 10000.0, "SPEED should be sane")

func test_bullet_size_for_collision_math():
	# bullet.SIZE is used by Collision2D — make sure it stays a Vector2.
	assert_typeof(bullet.SIZE, TYPE_VECTOR2)
	assert_gt(bullet.SIZE.x, 0)
	assert_gt(bullet.SIZE.y, 0)
