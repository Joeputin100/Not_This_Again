extends GutTest

const TumbleweedScene = preload("res://scenes/tumbleweed.tscn")
const TumbleweedScript = preload("res://scripts/tumbleweed.gd")

var tw: Node2D

func before_each():
	tw = TumbleweedScene.instantiate()
	add_child_autofree(tw)
	await get_tree().process_frame

func test_starts_at_max_hp():
	assert_eq(tw.hp, TumbleweedScript.MAX_HP, "tumbleweed starts at MAX_HP=36")

func test_added_to_tumbleweeds_group():
	assert_true(tw.is_in_group("tumbleweeds"))

func test_take_bullet_hit_reduces_hp_by_one():
	var before := tw.hp
	tw.take_bullet_hit()
	assert_eq(tw.hp, before - 1)

func test_take_bullet_hit_pushes_back():
	var before_y := tw.position.y
	tw.take_bullet_hit()
	assert_eq(tw.position.y, before_y - TumbleweedScript.PUSHBACK_PER_HIT,
		"y should decrease (move up) by PUSHBACK_PER_HIT")

func test_36_hits_destroys():
	for i in TumbleweedScript.MAX_HP:
		tw.take_bullet_hit()
	assert_true(tw._destroyed, "36 hits should destroy")
	assert_eq(tw.hp, 0)

func test_hits_after_destroyed_return_false():
	for i in TumbleweedScript.MAX_HP:
		tw.take_bullet_hit()
	assert_false(tw.take_bullet_hit(), "no more consumption after destroyed")

func test_hp_label_updates():
	tw.take_bullet_hit()
	var label: Label = tw.get_node("HpLabel")
	assert_eq(label.text, str(TumbleweedScript.MAX_HP - 1))

func test_destroyed_signal_fires_with_x():
	tw.position = Vector2(400, 0)
	watch_signals(tw)
	for i in TumbleweedScript.MAX_HP:
		tw.take_bullet_hit()
	assert_signal_emitted_with_parameters(tw, "destroyed", [400.0])

func test_cowboy_damage_value():
	assert_eq(tw.get_cowboy_damage(), TumbleweedScript.COWBOY_DAMAGE)
