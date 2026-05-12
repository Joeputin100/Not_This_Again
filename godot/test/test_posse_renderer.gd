extends GutTest

# Tests for posse_renderer.gd — instantiates the renderer, drives
# posse_count through grow/shrink/stable transitions, and verifies the
# child-dude count tracks the formation size (posse_count - 1).
#
# Uses active_follower_count() rather than raw get_child_count() so
# we don't have to wait out the tween-out duration when dudes leave
# (departing dudes stay in the scene tree until queue_free fires).

const PosseRendererScript = preload("res://scripts/posse_renderer.gd")

var renderer: Node2D

func before_each():
	renderer = PosseRendererScript.new()
	add_child_autofree(renderer)
	# Wait one frame so _ready resolves and the default posse_count=1 is
	# stable. The first user-driven assignment will fire the setter.
	await get_tree().process_frame

# ---------- initial state ----------

func test_starts_with_zero_followers():
	# Default posse_count is 1 → 0 followers.
	assert_eq(renderer.active_follower_count(), 0,
		"default posse_count=1 should produce 0 followers")

# ---------- grow ----------

func test_set_posse_count_5_spawns_four_followers():
	renderer.posse_count = 5
	await get_tree().process_frame
	assert_eq(renderer.active_follower_count(), 4,
		"posse_count=5 → 4 active followers")

func test_set_posse_count_10_spawns_nine_followers():
	renderer.posse_count = 10
	await get_tree().process_frame
	assert_eq(renderer.active_follower_count(), 9,
		"posse_count=10 → 9 active followers")

func test_grow_from_5_to_10_adds_five_more():
	renderer.posse_count = 5
	await get_tree().process_frame
	assert_eq(renderer.active_follower_count(), 4)
	renderer.posse_count = 10
	await get_tree().process_frame
	assert_eq(renderer.active_follower_count(), 9,
		"after grow 5→10, should have 9 active followers")

# ---------- shrink ----------

func test_shrink_from_10_to_3_drops_to_two_followers():
	renderer.posse_count = 10
	await get_tree().process_frame
	assert_eq(renderer.active_follower_count(), 9)
	renderer.posse_count = 3
	await get_tree().process_frame
	# posse_count=3 → 2 active. Leaving dudes are still in the scene tree
	# (tweening out), but active_follower_count excludes them.
	assert_eq(renderer.active_follower_count(), 2,
		"after shrink 10→3, should have 2 active followers")

# ---------- clamps to >=1 ----------

func test_posse_count_zero_clamps_to_one():
	renderer.posse_count = 0
	await get_tree().process_frame
	# Clamped to 1 → 0 followers.
	assert_eq(renderer.posse_count, 1,
		"posse_count=0 should clamp to 1")
	assert_eq(renderer.active_follower_count(), 0)

func test_posse_count_negative_clamps_to_one():
	renderer.posse_count = -5
	await get_tree().process_frame
	assert_eq(renderer.posse_count, 1,
		"negative posse_count should clamp to 1")

# ---------- leader anchor ----------

func test_set_leader_position_updates_renderer_position():
	renderer.set_leader_position(Vector2(300, 800))
	assert_eq(renderer.position, Vector2(300, 800),
		"set_leader_position should set renderer.position directly")

# ---------- dudes are positioned behind the leader ----------

func test_followers_y_offset_positive():
	# After grow, every active dude's base_pos should have y > 0 (behind
	# leader). The dude's actual position may be jittered, but base_pos is
	# the cached formation slot.
	renderer.posse_count = 10
	await get_tree().process_frame
	for dude in renderer.get_children():
		if dude.has_meta("base_pos"):
			var base_pos: Vector2 = dude.get_meta("base_pos")
			assert_gt(base_pos.y, 0.0,
				"dude base_pos.y should be > 0 (behind leader)")

# ---------- jitter applied each frame ----------

func test_jitter_moves_dude_off_base_position():
	# After several frames, dudes' actual position should drift from their
	# base_pos due to sinusoidal jitter. (At least one dude should differ;
	# all dudes might briefly cross their base every cycle, so we check the
	# whole crowd.)
	renderer.posse_count = 10
	await get_tree().process_frame
	# Force several _process ticks (skip waiting for real frames — GUT's
	# get_tree().process_frame ticks engine _process automatically).
	for i in 10:
		renderer._process(0.05)
	var any_jittered: bool = false
	for dude in renderer.get_children():
		if not dude.has_meta("base_pos"):
			continue
		var base_pos: Vector2 = dude.get_meta("base_pos")
		if dude.position.distance_to(base_pos) > 0.5:
			any_jittered = true
			break
	assert_true(any_jittered,
		"after 10 process ticks, at least one dude should be jittered off base")
