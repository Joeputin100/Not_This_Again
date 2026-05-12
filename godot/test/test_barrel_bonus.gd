extends GutTest

# Verifies barrels with bonus_type drop a Bonus on destruction, and
# barrels WITHOUT bonus_type don't pollute the level with bonuses.

const BarrelScene = preload("res://scenes/barrel.tscn")

var parent: Node2D
var barrel: Node2D

func before_each():
	# Need a parent node so the barrel's _spawn_bonus_drop() has somewhere
	# to add the bonus as a sibling. Using a fresh Node2D per test keeps
	# bonus counts isolated.
	parent = Node2D.new()
	add_child_autofree(parent)
	barrel = BarrelScene.instantiate()
	parent.add_child(barrel)
	await get_tree().process_frame

# ---------- bonus_type plumbing on the barrel ----------

func test_bonus_type_defaults_empty():
	assert_eq(barrel.bonus_type, "",
		"plain barrel should default to no bonus")

func test_bonus_type_can_be_set():
	barrel.bonus_type = "fast_fire"
	assert_eq(barrel.bonus_type, "fast_fire")

func test_bonus_indicator_added_when_bonus_type_set():
	# Fresh barrel with bonus_type — _ready should add a "BONUS X" label.
	# We can't check by name (anonymous Label), so count Label children
	# that aren't the built-in HpLabel.
	var bb := BarrelScene.instantiate()
	bb.bonus_type = "fast_fire"
	parent.add_child(bb)
	await get_tree().process_frame
	var extra_labels := 0
	for c in bb.get_children():
		if c is Label and c.name != "HpLabel":
			extra_labels += 1
	assert_gt(extra_labels, 0,
		"power-up barrel should add a BONUS indicator label")

func test_no_bonus_indicator_when_bonus_type_empty():
	# Plain barrel — no extra labels beyond HpLabel.
	var extra_labels := 0
	for c in barrel.get_children():
		if c is Label and c.name != "HpLabel":
			extra_labels += 1
	assert_eq(extra_labels, 0,
		"plain barrel should have no extra labels")

# ---------- bonus spawn on destruction ----------

func test_destroy_spawns_bonus_when_bonus_type_set():
	barrel.bonus_type = "fast_fire"
	barrel.position = Vector2(300, 500)
	# Destroy via overkill — take_damage returns true, _destroyed=true,
	# bonus spawns BEFORE the destroy animation starts.
	var before := get_tree().get_nodes_in_group("bonuses").size()
	barrel.take_damage(barrel.max_hp + 10)
	await get_tree().process_frame
	var after := get_tree().get_nodes_in_group("bonuses").size()
	assert_eq(after - before, 1,
		"destroying a power-up barrel should spawn exactly 1 bonus")

func test_destroyed_bonus_inherits_position():
	barrel.bonus_type = "rifle"
	barrel.position = Vector2(700, 250)
	barrel.take_damage(barrel.max_hp + 10)
	await get_tree().process_frame
	# Find the bonus in the parent (it's a sibling of the barrel).
	var found: Node2D = null
	for c in parent.get_children():
		if c.is_in_group("bonuses"):
			found = c
			break
	assert_not_null(found, "bonus should be parented to barrel's parent")
	if found:
		# Bonus may have ticked one frame of _process by now — allow some
		# slack on Y but X should be exact.
		assert_eq(found.position.x, 700.0,
			"bonus x should match barrel x")
		assert_almost_eq(found.position.y, 250.0, 30.0,
			"bonus y should start at barrel y (allowing one scroll tick)")

func test_destroyed_bonus_inherits_type():
	barrel.bonus_type = "rifle"
	barrel.take_damage(barrel.max_hp + 10)
	await get_tree().process_frame
	var found: Node2D = null
	for c in parent.get_children():
		if c.is_in_group("bonuses"):
			found = c
			break
	assert_not_null(found)
	if found:
		assert_eq(found.bonus_type, "rifle",
			"spawned bonus should carry barrel's bonus_type")

# ---------- no bonus spawn for plain barrels ----------

func test_destroy_plain_barrel_spawns_no_bonus():
	# Default bonus_type="" — destroying this barrel should add ZERO
	# bonuses to the parent / "bonuses" group.
	assert_eq(barrel.bonus_type, "",
		"precondition: barrel has no bonus_type")
	var before := get_tree().get_nodes_in_group("bonuses").size()
	barrel.take_damage(barrel.max_hp + 10)
	await get_tree().process_frame
	var after := get_tree().get_nodes_in_group("bonuses").size()
	assert_eq(after, before,
		"destroying a plain barrel should NOT spawn a bonus")

# ---------- partial-damage path doesn't pre-spawn ----------

func test_partial_damage_does_not_spawn_bonus():
	barrel.bonus_type = "fast_fire"
	# Hit it once — still alive, no destruction, no spawn.
	var before := get_tree().get_nodes_in_group("bonuses").size()
	barrel.take_damage(1)
	await get_tree().process_frame
	var after := get_tree().get_nodes_in_group("bonuses").size()
	assert_eq(after, before,
		"non-fatal hit should NOT spawn a bonus")
