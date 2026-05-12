extends GutTest

# Verifies the posse_dude scene loads its AnimatedSprite2D with the
# three expected animations (idle, run_shoot, die) and that default
# autoplay is run_shoot — the gameplay-active state.

const PosseDudeScene = preload("res://scenes/posse_dude.tscn")
const PosseDudeFrames = preload("res://assets/posse_dude_frames.tres")

var dude: Node2D

func before_each():
	dude = PosseDudeScene.instantiate()
	add_child_autofree(dude)
	await get_tree().process_frame

func test_has_animated_sprite_child():
	var sprite: AnimatedSprite2D = dude.get_node_or_null("Sprite") as AnimatedSprite2D
	assert_not_null(sprite, "posse_dude should have an AnimatedSprite2D named 'Sprite'")

func test_sprite_uses_posse_dude_frames():
	var sprite: AnimatedSprite2D = dude.get_node("Sprite") as AnimatedSprite2D
	assert_not_null(sprite.sprite_frames,
		"AnimatedSprite2D needs a SpriteFrames resource")

func test_frames_has_idle_animation():
	var sprite: AnimatedSprite2D = dude.get_node("Sprite") as AnimatedSprite2D
	assert_true(sprite.sprite_frames.has_animation("idle"),
		"SpriteFrames missing 'idle' animation")

func test_frames_has_run_shoot_animation():
	var sprite: AnimatedSprite2D = dude.get_node("Sprite") as AnimatedSprite2D
	assert_true(sprite.sprite_frames.has_animation("run_shoot"),
		"SpriteFrames missing 'run_shoot' animation")

func test_frames_has_die_animation():
	var sprite: AnimatedSprite2D = dude.get_node("Sprite") as AnimatedSprite2D
	assert_true(sprite.sprite_frames.has_animation("die"),
		"SpriteFrames missing 'die' animation")

func test_idle_animation_loops():
	var sprite: AnimatedSprite2D = dude.get_node("Sprite") as AnimatedSprite2D
	assert_true(sprite.sprite_frames.get_animation_loop("idle"),
		"idle should loop indefinitely")

func test_run_shoot_animation_loops():
	var sprite: AnimatedSprite2D = dude.get_node("Sprite") as AnimatedSprite2D
	assert_true(sprite.sprite_frames.get_animation_loop("run_shoot"),
		"run_shoot should loop indefinitely (player can play forever)")

func test_die_animation_does_not_loop():
	var sprite: AnimatedSprite2D = dude.get_node("Sprite") as AnimatedSprite2D
	assert_false(sprite.sprite_frames.get_animation_loop("die"),
		"die should play once and stop on the final 'dead' frame")

func test_idle_has_six_frames():
	var sprite: AnimatedSprite2D = dude.get_node("Sprite") as AnimatedSprite2D
	assert_eq(sprite.sprite_frames.get_frame_count("idle"), 6,
		"idle animation should have 6 frames (matches source spritesheet)")

func test_run_shoot_has_eight_frames():
	var sprite: AnimatedSprite2D = dude.get_node("Sprite") as AnimatedSprite2D
	assert_eq(sprite.sprite_frames.get_frame_count("run_shoot"), 8,
		"run_shoot animation should have 8 frames")

func test_die_has_three_frames():
	var sprite: AnimatedSprite2D = dude.get_node("Sprite") as AnimatedSprite2D
	assert_eq(sprite.sprite_frames.get_frame_count("die"), 3,
		"die animation should have 3 frames (hit → stumble → dead)")

func test_default_animation_is_run_shoot():
	var sprite: AnimatedSprite2D = dude.get_node("Sprite") as AnimatedSprite2D
	# autoplay or animation property — either way, the displayed
	# animation in-game should be run_shoot, not idle (cowboys auto-fire
	# from frame 0 of every level).
	assert_eq(sprite.animation, &"run_shoot",
		"default animation should be run_shoot for active gameplay")
