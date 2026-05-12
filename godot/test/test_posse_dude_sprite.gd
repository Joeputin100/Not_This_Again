extends GutTest

# Verifies the posse_dude scene (iter 28+) wraps a Cowboy3D node — the
# 3D Mixamo character rendered via SubViewport. Replaces the iter 23
# version that checked for an AnimatedSprite2D + posse_dude_frames.tres,
# both of which are now obsolete on the active rendering path.

const PosseDudeScene = preload("res://scenes/posse_dude.tscn")

var dude: Node2D

func before_each():
	dude = PosseDudeScene.instantiate()
	add_child_autofree(dude)
	await get_tree().process_frame

func test_has_cowboy3d_child():
	var c3d: Node2D = dude.get_node_or_null("Cowboy3D") as Node2D
	assert_not_null(c3d, "posse_dude should wrap a Cowboy3D node")

func test_cowboy3d_has_play_anim_method():
	var c3d: Node2D = dude.get_node("Cowboy3D") as Node2D
	assert_true(c3d.has_method("play_anim"),
		"Cowboy3D should expose play_anim(name) so PosseRenderer.set_animation works")

func test_cowboy3d_has_subviewport():
	var c3d: Node2D = dude.get_node("Cowboy3D") as Node2D
	var sv: SubViewport = c3d.get_node_or_null("SubViewport") as SubViewport
	assert_not_null(sv, "Cowboy3D should own a SubViewport for 3D rendering")

func test_cowboy3d_has_sprite_2d():
	var c3d: Node2D = dude.get_node("Cowboy3D") as Node2D
	var sprite: Sprite2D = c3d.get_node_or_null("Sprite") as Sprite2D
	assert_not_null(sprite, "Cowboy3D should own a Sprite2D backed by the SubViewport texture")
