extends GutTest

# Tests for outlaw_bullet.gd — the projectile fired by outlaws,
# travelling DOWN toward the cowboy (inverse of posse bullets).

const OutlawBulletScene = preload("res://scenes/outlaw_bullet.tscn")
const OutlawBulletScript = preload("res://scripts/outlaw_bullet.gd")

var bullet: Node2D

func before_each():
	bullet = OutlawBulletScene.instantiate()
	add_child_autofree(bullet)
	await get_tree().process_frame

func test_added_to_outlaw_bullets_group():
	assert_true(bullet.is_in_group("outlaw_bullets"),
		"outlaw bullet should join 'outlaw_bullets' on _ready")

func test_moves_downward_in_process():
	# Direction is the key behavior — posse bullets move UP (negative y
	# delta), outlaw bullets move DOWN (positive y delta).
	var y_before: float = bullet.position.y
	bullet._process(0.1)
	assert_gt(bullet.position.y, y_before,
		"outlaw bullets should travel toward the cowboy (+y), got %.1f" % bullet.position.y)

func test_speed_matches_spec():
	# 700 px/sec — slow enough for the player to react to a falling
	# bullet, fast enough to feel threatening.
	assert_eq(OutlawBulletScript.SPEED, 700.0,
		"OutlawBullet.SPEED should remain 700 — UX tuning constant")

func test_despawns_below_playfield():
	bullet.position.y = OutlawBulletScript.DESPAWN_Y_BOTTOM - 1
	# Iter 31 renamed: bullets now also despawn off the top/sides because
	# the velocity vector can take them in any direction. The classic
	# 'past-the-bottom' path is verified here.
	bullet.velocity = Vector2(0, 1000)  # straight down, fast
	bullet._process(0.1)  # pushes y past DESPAWN_Y_BOTTOM
	await get_tree().process_frame
	assert_false(is_instance_valid(bullet),
		"outlaw bullet should queue_free once past DESPAWN_Y_BOTTOM")

func test_posse_damage_is_one():
	# Iter 31: bumped 2 → 1 so per-dude bullet collisions have clean
	# semantics — one bullet, one specific dude dies. Multi-dude posse
	# damage scales by Pete's dual-bullet rate, not by per-bullet weight.
	assert_eq(OutlawBulletScript.POSSE_DAMAGE, 1,
		"per-bullet posse damage should remain 1 (iter 31 per-dude semantics)")
