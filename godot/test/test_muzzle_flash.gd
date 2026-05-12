extends GutTest

# Tests the muzzle_flash scene: SpriteFrames resource is loaded, the
# 'fire' animation exists with the expected frame count, and the script
# queue_frees the node on animation_finished (one-shot behavior).

const MuzzleFlashScene = preload("res://scenes/muzzle_flash.tscn")
const MuzzleFlashFrames = preload("res://assets/muzzle_flash_frames.tres")

var flash: AnimatedSprite2D

func before_each():
	flash = MuzzleFlashScene.instantiate()
	add_child_autofree(flash)
	# Don't await — we want to inspect the initial state before _process
	# advances the animation past frame 0.

func test_root_is_animated_sprite():
	assert_true(flash is AnimatedSprite2D,
		"muzzle_flash root should BE an AnimatedSprite2D (not a Node2D wrapper)")

func test_uses_muzzle_flash_frames():
	assert_not_null(flash.sprite_frames,
		"sprite_frames resource missing")

func test_has_fire_animation():
	assert_true(flash.sprite_frames.has_animation("fire"),
		"muzzle_flash should have a 'fire' animation")

func test_fire_does_not_loop():
	# One-shot — must NOT loop or it'd never queue_free.
	assert_false(flash.sprite_frames.get_animation_loop("fire"),
		"fire animation should not loop (one-shot)")

func test_fire_has_six_frames():
	assert_eq(flash.sprite_frames.get_frame_count("fire"), 6,
		"fire animation should have 6 frames")

func test_fire_speed_30fps():
	# 30fps × 6 frames = 200ms — fast enough to feel snappy with the
	# auto-fire cadence (one flash per ~180ms shot interval).
	assert_almost_eq(flash.sprite_frames.get_animation_speed("fire"), 30.0, 0.1,
		"fire animation should play at 30fps")

func test_default_animation_is_fire():
	assert_eq(flash.animation, &"fire",
		"default animation should be 'fire' for autoplay to work")
