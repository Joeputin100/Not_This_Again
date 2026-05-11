extends GutTest

const ChickenScene = preload("res://scenes/chicken.tscn")
const ChickenScript = preload("res://scripts/chicken.gd")

var chicken: Node2D

func before_each():
	chicken = ChickenScene.instantiate()
	add_child_autofree(chicken)
	# NOT awaiting process_frame — chicken's _ready does randi_range
	# for HP, and we want to inspect that pristine state before any
	# _process movement / lifespan ticks.

func test_added_to_chickens_group():
	assert_true(chicken.is_in_group("chickens"))

func test_starts_with_hp_between_1_and_3():
	assert_gte(chicken.hp, 1, "chicken HP >= 1")
	assert_lte(chicken.hp, 3, "chicken HP <= 3")

func test_zero_cowboy_damage():
	# Vision blocker only — chickens don't damage the cowboy on contact.
	assert_eq(chicken.get_cowboy_damage(), 0,
		"chickens should NOT damage posse")

func test_take_bullet_hit_decrements_hp():
	chicken.hp = 3
	chicken.take_bullet_hit()
	assert_eq(chicken.hp, 2)

func test_take_bullet_hit_returns_true_consumed():
	assert_true(chicken.take_bullet_hit())

func test_one_hp_chicken_dies_on_one_shot():
	chicken.hp = 1
	chicken.take_bullet_hit()
	assert_lte(chicken.hp, 0)
