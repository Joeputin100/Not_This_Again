extends GutTest

# Verifies the posse_dude scene (iter 30+) renders the cowboy as a
# single static Sprite2D — pivoted back from the iter 28 3D Cowboy3D
# approach after user feedback that the 3D rendering was 'still far
# from polished.' Iter 30 swaps to the hand-drawn posse_idle_00.png
# pose. No animation; visual variety comes from PosseRenderer's per-
# dude jitter + spawn-tween.

const PosseDudeScene = preload("res://scenes/posse_dude.tscn")

var dude: Node2D

func before_each():
	dude = PosseDudeScene.instantiate()
	add_child_autofree(dude)
	await get_tree().process_frame

func test_has_sprite_2d_child():
	var sprite: Sprite2D = dude.get_node_or_null("Sprite") as Sprite2D
	assert_not_null(sprite, "posse_dude should have a static Sprite2D child")

func test_sprite_has_texture():
	var sprite: Sprite2D = dude.get_node("Sprite") as Sprite2D
	assert_not_null(sprite.texture,
		"Sprite2D texture should be loaded (posse_idle_00.png)")

func test_sprite_positioned_for_cowboy_height():
	var sprite: Sprite2D = dude.get_node("Sprite") as Sprite2D
	# y=-100 offset puts the texture center at the cowboy's chest height
	# relative to the dude's footprint, matching the iter 23+ layout.
	assert_eq(sprite.position.y, -100.0,
		"sprite y-offset should be -100 to land the cowboy at chest height")

func test_sprite_scale_matches_playfield_size():
	var sprite: Sprite2D = dude.get_node("Sprite") as Sprite2D
	# 0.4 scales the 341×447-ish source down to ~140×180 visible. Same
	# size as the iter 23/25 AnimatedSprite2D era so the existing posse
	# spacing constants (130/200) still keep dudes from overlapping.
	assert_eq(sprite.scale, Vector2(0.4, 0.4),
		"sprite scale should be 0.4 to match the original playfield size")
