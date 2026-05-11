extends GutTest

const BarricadeScene = preload("res://scenes/barricade.tscn")
const BarricadeScript = preload("res://scripts/barricade.gd")

var b: Node2D

func before_each():
	b = BarricadeScene.instantiate()
	add_child_autofree(b)
	await get_tree().process_frame

func test_added_to_barricades_group():
	assert_true(b.is_in_group("barricades"))

func test_take_bullet_hit_returns_true_consumed():
	# Bullets are absorbed (consumed) but barricade is unaffected.
	assert_true(b.take_bullet_hit())

func test_take_bullet_hit_many_times_no_state_change():
	# Barricade is immortal — 100 hits should not change anything.
	for i in 100:
		b.take_bullet_hit()
	# No HP to check (barricade has none); just verify no crash + still in tree.
	assert_true(is_instance_valid(b))
	assert_true(b.is_in_group("barricades"))

func test_cowboy_damage_is_higher_than_other_obstacles():
	const TumbleweedScript = preload("res://scripts/tumbleweed.gd")
	const CactusScript = preload("res://scripts/cactus.gd")
	const BarrelScript = preload("res://scripts/barrel.gd")
	assert_gt(b.get_cowboy_damage(), TumbleweedScript.COWBOY_DAMAGE,
		"barricade hurts more than tumbleweed")
	assert_gt(b.get_cowboy_damage(), CactusScript.COWBOY_DAMAGE,
		"barricade hurts more than cactus")
	# Barrels deal damage equal to their remaining HP, not a constant;
	# fence damage of 10 is the highest among the new obstacles.
	assert_gte(b.get_cowboy_damage(), 8)

func test_does_not_have_take_damage_method():
	# Barricade is intentionally NOT destructible — it has no take_damage.
	assert_false(b.has_method("take_damage"),
		"barricade must NOT expose take_damage — it's immortal by design")
