extends GutTest

const CactusScene = preload("res://scenes/cactus.tscn")
const CactusScript = preload("res://scripts/cactus.gd")

var cactus: Node2D

func before_each():
	cactus = CactusScene.instantiate()
	add_child_autofree(cactus)
	await get_tree().process_frame

func test_starts_at_max_hp():
	assert_eq(cactus.hp, CactusScript.MAX_HP)

func test_added_to_cacti_group():
	assert_true(cactus.is_in_group("cacti"))

func test_take_bullet_hit_reduces_hp():
	var before: int = cactus.hp
	cactus.take_bullet_hit()
	assert_eq(cactus.hp, before - 1)

func test_take_bullet_hit_does_NOT_push_back():
	# Unlike tumbleweed, cactus does NOT recoil from bullets.
	var before_y: float = cactus.position.y
	cactus.take_bullet_hit()
	assert_eq(cactus.position.y, before_y,
		"cactus position should be unchanged by bullet hit")

func test_36_hits_destroys():
	for i in CactusScript.MAX_HP:
		cactus.take_bullet_hit()
	assert_true(cactus._destroyed)

func test_cowboy_damage_higher_than_tumbleweed():
	# Cactus spikes hurt more than tumbleweed's soft impact.
	const TumbleweedScript = preload("res://scripts/tumbleweed.gd")
	assert_gt(cactus.get_cowboy_damage(), TumbleweedScript.COWBOY_DAMAGE)

func test_hp_label_updates():
	cactus.take_bullet_hit()
	var label: Label = cactus.get_node("HpLabel")
	assert_eq(label.text, str(CactusScript.MAX_HP - 1))
