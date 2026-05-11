extends GutTest

const BarrelScene = preload("res://scenes/barrel.tscn")

var barrel: Node2D

func before_each():
	barrel = BarrelScene.instantiate()
	add_child_autofree(barrel)
	await get_tree().process_frame

# ---------- initial state ----------

func test_starts_at_max_hp():
	assert_eq(barrel.hp, barrel.max_hp)

func test_added_to_barrels_group():
	assert_true(barrel.is_in_group("barrels"),
		"barrel should add itself to 'barrels' group on _ready")

func test_hp_label_shows_max_hp():
	var label: Label = barrel.get_node("HpLabel")
	assert_eq(label.text, str(barrel.max_hp))

# ---------- take_damage ----------

func test_take_damage_reduces_hp():
	var before := barrel.hp
	barrel.take_damage(1)
	assert_eq(barrel.hp, before - 1)

func test_take_damage_returns_false_when_not_destroyed():
	var was_destroyed := barrel.take_damage(1)
	assert_false(was_destroyed)
	assert_false(barrel._destroyed)

func test_take_damage_returns_true_on_final_hit():
	for i in barrel.max_hp - 1:
		barrel.take_damage(1)
	# One more should destroy it.
	var was_destroyed := barrel.take_damage(1)
	assert_true(was_destroyed)
	assert_true(barrel._destroyed)

func test_take_damage_after_destroyed_returns_false():
	for i in barrel.max_hp:
		barrel.take_damage(1)
	# Already destroyed; further hits should be ignored.
	var was_destroyed := barrel.take_damage(1)
	assert_false(was_destroyed)

func test_hp_label_updates_with_damage():
	var label: Label = barrel.get_node("HpLabel")
	barrel.take_damage(1)
	assert_eq(label.text, str(barrel.max_hp - 1))

func test_destroyed_signal_fires_with_position_x():
	barrel.position = Vector2(300, 500)
	watch_signals(barrel)
	for i in barrel.max_hp:
		barrel.take_damage(1)
	assert_signal_emitted_with_parameters(barrel, "destroyed", [300.0])

# ---------- variable damage amounts ----------

func test_take_damage_n_at_once():
	var before := barrel.hp
	barrel.take_damage(3)
	assert_eq(barrel.hp, before - 3)

func test_overkill_destroys():
	var was_destroyed := barrel.take_damage(barrel.max_hp + 5)
	assert_true(was_destroyed)
