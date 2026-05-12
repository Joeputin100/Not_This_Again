extends GutTest

const BonusScene = preload("res://scenes/bonus.tscn")
const BonusScript = preload("res://scripts/bonus.gd")

var bonus: Node2D

func before_each():
	bonus = BonusScene.instantiate()
	add_child_autofree(bonus)
	await get_tree().process_frame

# ---------- group membership ----------

func test_added_to_bonuses_group():
	assert_true(bonus.is_in_group("bonuses"),
		"bonus should add itself to 'bonuses' group on _ready")

# ---------- scrolling behavior ----------

func test_process_scrolls_down():
	bonus.position = Vector2(540, 200)
	var initial_y := bonus.position.y
	bonus._process(0.1)
	# SCROLL_SPEED=220 * 0.1 = 22px downward.
	assert_almost_eq(bonus.position.y, initial_y + 22.0, 0.01,
		"bonus should move down at SCROLL_SPEED * delta")

func test_process_does_not_move_x():
	bonus.position = Vector2(300, 200)
	bonus._process(0.1)
	assert_eq(bonus.position.x, 300.0,
		"bonus should only scroll on Y axis, not X")

func test_scroll_speed_matches_obstacles():
	# Bonus should scroll at the same speed as barrels/obstacles (220).
	# If these drift apart, bonuses won't visually track their parent
	# barrel's spawn point.
	assert_eq(BonusScript.SCROLL_SPEED, 220.0,
		"bonus scroll speed should match obstacle scroll speed")

func test_size_constant_is_vector2():
	# Used by level.gd's collision pass against COWBOY_SIZE.
	assert_typeof(BonusScript.SIZE, TYPE_VECTOR2)
	assert_gt(BonusScript.SIZE.x, 0.0)
	assert_gt(BonusScript.SIZE.y, 0.0)

# ---------- bonus_type plumbing ----------

func test_default_bonus_type_empty():
	# A fresh-instantiated bonus has no type until barrel sets it.
	assert_eq(bonus.bonus_type, "",
		"new bonus should start with empty bonus_type")

func test_letter_for_known_types():
	# letter_for() drives the icon. All three documented types should
	# return a non-? glyph.
	assert_eq(BonusScript.letter_for("fast_fire"), "F")
	assert_eq(BonusScript.letter_for("extra_dude"), "+D")
	assert_eq(BonusScript.letter_for("rifle"), "R")

func test_letter_for_unknown_type():
	assert_eq(BonusScript.letter_for("missing"), "?",
		"unknown bonus types should show ? so bugs are visible")
