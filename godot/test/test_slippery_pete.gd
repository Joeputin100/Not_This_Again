extends GutTest

# Tests for slippery_pete.gd — Level 1 boss. Verifies the boss-tier
# stat overrides, dual-bullet firing, "outlaws" + "bosses" group
# membership (so existing level.gd collision passes pick him up
# without changes), and the more dramatic destroy animation timing.

const PeteScene = preload("res://scenes/slippery_pete.tscn")
const PeteScript = preload("res://scripts/slippery_pete.gd")
const OutlawScript = preload("res://scripts/outlaw.gd")

var pete: Node2D

func before_each():
	pete = PeteScene.instantiate()
	add_child_autofree(pete)
	await get_tree().process_frame

# ---------- groups ----------

func test_added_to_outlaws_group():
	# Joins 'outlaws' so the existing bullet/outlaw + outlaw/cowboy
	# collision passes catch Pete without level.gd changes.
	assert_true(pete.is_in_group("outlaws"),
		"Pete should join 'outlaws' for existing collision-pass reuse")

func test_added_to_bosses_group():
	# Also joins 'bosses' so future logic (level-end detection, dedicated
	# boss-death VFX) can target boss-only entities.
	assert_true(pete.is_in_group("bosses"),
		"Pete should join 'bosses' for boss-only queries")

# ---------- boss-tier stats vs vagrant ----------

func test_max_hp_higher_than_vagrant():
	assert_gt(PeteScript.MAX_HP, OutlawScript.MAX_HP,
		"boss HP (%d) should exceed vagrant HP (%d)" % [PeteScript.MAX_HP, OutlawScript.MAX_HP])

func test_cowboy_damage_higher_than_vagrant():
	assert_gt(PeteScript.COWBOY_DAMAGE, OutlawScript.COWBOY_DAMAGE,
		"boss contact damage (%d) should exceed vagrant (%d)" % [PeteScript.COWBOY_DAMAGE, OutlawScript.COWBOY_DAMAGE])

func test_fire_interval_faster_than_vagrant():
	assert_lt(PeteScript.FIRE_INTERVAL, OutlawScript.FIRE_INTERVAL,
		"boss fires more often (%.2fs vs %.2fs)" % [PeteScript.FIRE_INTERVAL, OutlawScript.FIRE_INTERVAL])

func test_scroll_speed_slower_than_vagrant():
	# Pete moves deliberately — gives the player time to engage during
	# the boss approach instead of racing into contact.
	assert_lt(PeteScript.SCROLL_SPEED, OutlawScript.SCROLL_SPEED,
		"boss scrolls slower than vagrant (%.0f vs %.0f)" % [PeteScript.SCROLL_SPEED, OutlawScript.SCROLL_SPEED])

func test_size_larger_than_vagrant():
	assert_gt(pete.SIZE.x, OutlawScript.SIZE.x, "boss hitbox is wider")
	assert_gt(pete.SIZE.y, OutlawScript.SIZE.y, "boss hitbox is taller")

# ---------- HP + caliber ----------

func test_starts_at_max_hp():
	assert_eq(pete.hp, PeteScript.MAX_HP)

func test_take_bullet_hit_decrements_hp():
	var before: int = pete.hp
	pete.take_bullet_hit()
	assert_eq(pete.hp, before - 1)

func test_take_bullet_hit_caliber_aware():
	var before: int = pete.hp
	pete.take_bullet_hit(3)
	assert_eq(pete.hp, before - 3, "rifle round (caliber 3) reduces HP by 3")

func test_max_hp_hits_destroy_pete():
	for i in PeteScript.MAX_HP:
		pete.take_bullet_hit()
	assert_lte(pete.hp, 0)
	assert_true(pete._destroyed)

func test_destroyed_signal_fires_with_x():
	pete.position = Vector2(540, 500)
	watch_signals(pete)
	for i in PeteScript.MAX_HP:
		pete.take_bullet_hit()
	assert_signal_emitted_with_parameters(pete, "destroyed", [540.0])

# ---------- dual fire ----------

func test_fires_two_bullets_per_tick():
	# Place Pete on-screen and tick exactly one fire interval. Should
	# spawn TWO outlaw_bullets (one per visible pistol).
	pete.position.y = PeteScript.ON_SCREEN_Y + 100.0
	var before_count: int = get_tree().get_nodes_in_group("outlaw_bullets").size()
	pete._process(PeteScript.FIRE_INTERVAL + 0.05)
	await get_tree().process_frame
	var after_count: int = get_tree().get_nodes_in_group("outlaw_bullets").size()
	assert_eq(after_count - before_count, 2,
		"Pete should fire 2 bullets per FIRE_INTERVAL (one per pistol), got %d" % (after_count - before_count))

func test_dual_bullets_have_horizontal_spread():
	# Verify the two bullets spawn at opposite horizontal offsets so
	# the player has to dodge a wider pattern than a single vagrant.
	pete.position = Vector2(540, PeteScript.ON_SCREEN_Y + 100.0)
	var before_count: int = get_tree().get_nodes_in_group("outlaw_bullets").size()
	pete._process(PeteScript.FIRE_INTERVAL + 0.05)
	await get_tree().process_frame
	var bullets: Array = get_tree().get_nodes_in_group("outlaw_bullets")
	# Last two spawned should be Pete's. Compare their X positions.
	if bullets.size() >= before_count + 2:
		var b1: Node2D = bullets[bullets.size() - 2]
		var b2: Node2D = bullets[bullets.size() - 1]
		assert_ne(b1.position.x, b2.position.x,
			"Pete's two bullets should spawn at different x positions")
		assert_eq(absf(b1.position.x - b2.position.x), 2.0 * PeteScript.LEFT_GUN_X_OFFSET,
			"horizontal spread should be 2 × LEFT_GUN_X_OFFSET")

# ---------- movement ----------

func test_no_fire_above_on_screen_threshold():
	pete.position.y = PeteScript.ON_SCREEN_Y - 300.0
	var before_count: int = get_tree().get_nodes_in_group("outlaw_bullets").size()
	pete._process(PeteScript.FIRE_INTERVAL * 1.5)
	await get_tree().process_frame
	var after_count: int = get_tree().get_nodes_in_group("outlaw_bullets").size()
	assert_eq(after_count - before_count, 0,
		"Pete shouldn't fire while still above the on-screen threshold")
