extends GutTest

const BulletScene = preload("res://scenes/bullet.tscn")
const BulletScript = preload("res://scripts/bullet.gd")

# Bullet range is set BEFORE add_child. _ready captures spawn_y; then
# _process moves the bullet up and despawns at max_range OR at the
# off-screen threshold — whichever comes first.

func test_bullet_with_zero_range_falls_back_to_offscreen():
	var bullet: Node2D = BulletScene.instantiate()
	bullet.position = Vector2(540, 1500)
	# max_range default is 0 (no limit) → bullet only despawns off-screen.
	add_child_autofree(bullet)
	await get_tree().process_frame
	# After one frame at 60fps, bullet has moved up ~25px. Nowhere near
	# DESPAWN_Y. Should still be alive.
	assert_true(is_instance_valid(bullet),
		"zero-range bullet survives after one frame near spawn")

func test_bullet_with_range_despawns_after_traveling_range():
	var bullet: Node2D = BulletScene.instantiate()
	bullet.position = Vector2(540, 1500)
	# Use a tiny range so a few process ticks blow past it.
	bullet.max_range = 30.0
	add_child_autofree(bullet)
	# Burn enough simulated time to travel >30px. Bullet speed is 1500
	# px/sec, so 0.05s → 75px. Use real frame advances so _process
	# actually runs.
	for i in 6:
		await get_tree().process_frame
	# Bullet should be freed by now.
	assert_false(is_instance_valid(bullet),
		"30px range bullet despawned after traveling past 30px")

func test_bullet_default_damage_one():
	var bullet: Node2D = BulletScene.instantiate()
	add_child_autofree(bullet)
	assert_eq(bullet.damage, 1,
		"default bullet damage matches six-shooter caliber 1")

func test_bullet_custom_damage_sticks():
	var bullet: Node2D = BulletScene.instantiate()
	bullet.damage = 5
	add_child_autofree(bullet)
	assert_eq(bullet.damage, 5,
		"damage set before add_child survives _ready")
