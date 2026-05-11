extends GutTest

const CoopScene = preload("res://scenes/chicken_coop.tscn")
const CoopScript = preload("res://scripts/chicken_coop.gd")

var coop: Node2D

func before_each():
	coop = CoopScene.instantiate()
	add_child_autofree(coop)
	await get_tree().process_frame

func test_starts_at_max_hp():
	assert_eq(coop.hp, CoopScript.MAX_HP)

func test_added_to_chicken_coops_group():
	assert_true(coop.is_in_group("chicken_coops"))

func test_take_bullet_hit_decrements_hp():
	var before := coop.hp
	coop.take_bullet_hit()
	assert_eq(coop.hp, before - 1)

func test_zero_cowboy_damage():
	# Coop itself doesn't damage; chickens are the consequence.
	assert_eq(coop.get_cowboy_damage(), 0)

func test_max_hp_hits_destroys():
	for i in CoopScript.MAX_HP:
		coop.take_bullet_hit()
	assert_true(coop._destroyed)

func test_destruction_emits_destroyed_signal():
	coop.position = Vector2(360, 100)
	watch_signals(coop)
	for i in CoopScript.MAX_HP:
		coop.take_bullet_hit()
	assert_signal_emitted_with_parameters(coop, "destroyed", [360.0])

func test_destruction_releases_chickens():
	# When the coop dies, it should add CHICKEN_COUNT_MIN..MAX chickens
	# to its parent. Count them by group membership.
	var before_count := get_tree().get_nodes_in_group("chickens").size()
	for i in CoopScript.MAX_HP:
		coop.take_bullet_hit()
	# Process a frame so any deferred adds settle.
	await get_tree().process_frame
	var after_count := get_tree().get_nodes_in_group("chickens").size()
	var added := after_count - before_count
	assert_gte(added, CoopScript.CHICKEN_COUNT_MIN,
		"should spawn at least CHICKEN_COUNT_MIN chickens (got %d)" % added)
	assert_lte(added, CoopScript.CHICKEN_COUNT_MAX,
		"should spawn at most CHICKEN_COUNT_MAX chickens (got %d)" % added)

func test_hits_after_destroyed_return_false():
	for i in CoopScript.MAX_HP:
		coop.take_bullet_hit()
	assert_false(coop.take_bullet_hit(),
		"destroyed coop shouldn't consume further bullets")
