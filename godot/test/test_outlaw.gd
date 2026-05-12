extends GutTest

# Tests for outlaw.gd — the black-hat antagonist that scrolls DOWN at
# the cowboy, fires bullets at FIRE_INTERVAL while on-screen, takes
# MAX_HP shots to destroy (caliber-aware), and deals heavy contact
# damage if it reaches the posse alive.

const OutlawScene = preload("res://scenes/outlaw.tscn")
const OutlawScript = preload("res://scripts/outlaw.gd")

var outlaw: Node2D

func before_each():
	outlaw = OutlawScene.instantiate()
	add_child_autofree(outlaw)
	await get_tree().process_frame

# ---------- group + initial state ----------

func test_added_to_outlaws_group():
	assert_true(outlaw.is_in_group("outlaws"),
		"outlaw should join 'outlaws' on _ready")

func test_starts_at_max_hp():
	assert_eq(outlaw.hp, OutlawScript.MAX_HP)

func test_hp_label_shows_max_hp():
	var label: Label = outlaw.get_node("HpLabel")
	assert_eq(label.text, str(OutlawScript.MAX_HP))

# ---------- contact damage ----------

func test_cowboy_damage_15():
	assert_eq(outlaw.get_cowboy_damage(), OutlawScript.COWBOY_DAMAGE)
	assert_eq(outlaw.get_cowboy_damage(), 15,
		"contact damage tuned to 15 — costly but survivable")

func test_cowboy_damage_higher_than_barrels():
	# Outlaw contact should hurt more than a single barrel-cowboy hit.
	# barrel.gd uses an @export var max_hp (not a const), so instantiate
	# a barrel and read its value rather than indexing a non-existent
	# BarrelScript.MAX_HP constant (the iter 29 version of this test
	# was a silent parse error; iter 32 surfaces it after the suite
	# starts running all 390 tests instead of the 296 that fit through
	# the earlier := inference quirk).
	const BarrelScene = preload("res://scenes/barrel.tscn")
	var b: Node2D = BarrelScene.instantiate()
	add_child_autofree(b)
	assert_gt(outlaw.get_cowboy_damage(), b.max_hp,
		"outlaw contact (%d) should outweigh barrel max_hp (%d)" % [
			outlaw.get_cowboy_damage(), b.max_hp,
		])

# ---------- take_bullet_hit ----------

func test_take_bullet_hit_decrements_hp():
	var before: int = outlaw.hp
	outlaw.take_bullet_hit()
	assert_eq(outlaw.hp, before - 1)

func test_take_bullet_hit_returns_true_consumed():
	assert_true(outlaw.take_bullet_hit(),
		"posse bullet is consumed by the outlaw on hit")

func test_take_bullet_hit_caliber_aware():
	var before: int = outlaw.hp
	outlaw.take_bullet_hit(3)
	assert_eq(outlaw.hp, before - 3,
		"rifle round (caliber 3) reduces HP by 3 in one hit")

func test_max_hp_hits_destroy():
	for i in OutlawScript.MAX_HP:
		outlaw.take_bullet_hit()
	assert_lte(outlaw.hp, 0)
	assert_true(outlaw._destroyed)

func test_destroyed_signal_fires_with_x():
	outlaw.position = Vector2(420, 100)
	watch_signals(outlaw)
	for i in OutlawScript.MAX_HP:
		outlaw.take_bullet_hit()
	assert_signal_emitted_with_parameters(outlaw, "destroyed", [420.0])

func test_hits_after_destroyed_return_false():
	for i in OutlawScript.MAX_HP:
		outlaw.take_bullet_hit()
	assert_false(outlaw.take_bullet_hit(),
		"destroyed outlaw shouldn't consume more posse bullets")

# ---------- movement ----------

func test_scrolls_downward_when_alive():
	var y_before: float = outlaw.position.y
	outlaw._process(0.1)
	assert_gt(outlaw.position.y, y_before,
		"outlaw should move toward cowboy (+y) while alive")

func test_no_scroll_after_destroyed():
	for i in OutlawScript.MAX_HP:
		outlaw.take_bullet_hit()
	# Move position to clear the destroy-tween's modulate animation
	# from interfering with our position check.
	var y_before: float = outlaw.position.y
	outlaw._process(0.5)
	assert_eq(outlaw.position.y, y_before,
		"destroyed outlaw should stop scrolling")

# ---------- firing cadence ----------

func test_does_not_fire_above_on_screen_threshold():
	# Outlaws far above the playfield (negative y) shouldn't pre-fire —
	# the player can't see them, can't dodge unfairly. Use a far-off-
	# screen position so the simulated _process tick (which moves the
	# outlaw by SCROLL_SPEED × delta) doesn't cross ON_SCREEN_Y during
	# the test window.
	outlaw.position.y = OutlawScript.ON_SCREEN_Y - 2000.0
	var before_count: int = get_tree().get_nodes_in_group("outlaw_bullets").size()
	outlaw._process(OutlawScript.FIRE_INTERVAL * 1.5)
	await get_tree().process_frame
	var after_count: int = get_tree().get_nodes_in_group("outlaw_bullets").size()
	assert_eq(after_count - before_count, 0,
		"outlaw above ON_SCREEN_Y shouldn't fire (%d bullets spawned)" % (after_count - before_count))

func test_fires_when_on_screen():
	outlaw.position.y = OutlawScript.ON_SCREEN_Y + 100.0
	var before_count: int = get_tree().get_nodes_in_group("outlaw_bullets").size()
	# Tick exactly one fire interval.
	outlaw._process(OutlawScript.FIRE_INTERVAL + 0.05)
	await get_tree().process_frame
	var after_count: int = get_tree().get_nodes_in_group("outlaw_bullets").size()
	assert_gte(after_count - before_count, 1,
		"outlaw on-screen should fire at least one bullet per FIRE_INTERVAL tick")
