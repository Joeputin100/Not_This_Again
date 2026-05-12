extends GutTest

# Integration tests that actually instantiate level.tscn and exercise its
# lifecycle. Previously the GUT suite only tested pure-logic classes;
# nothing ever ran the level scene's _ready/_process/_input pipeline.
# That left a class of bugs invisible until physical sideload.
#
# These tests:
#   1. Load level.tscn into the tree
#   2. Wait for _ready to complete
#   3. Send fake input events
#   4. Manually tick _process()
#   5. Verify cowboy.position responds
#
# If these PASS in CI but the game still fails on Android, the bug is
# Android-specific (Android-only input routing, autoload-on-device, etc.).
# If they FAIL in CI, the bug is in our level.gd / level.tscn / common code.

const LevelScene = preload("res://scenes/level.tscn")

var level: Node = null

func before_each():
	# Each test gets a fresh level instance via autofree so they don't share state.
	level = LevelScene.instantiate()
	add_child_autofree(level)
	# Process one frame so @onready vars resolve and _ready completes.
	await get_tree().process_frame
	await get_tree().process_frame

# ---------- _ready completion ----------

func test_ready_completes_and_writes_debug_label():
	# debug_label.text starts as "DBG" in the .tscn. If _ready() reaches
	# its end, it overwrites with "READY OK (process not yet ticked)".
	# If it threw before that line, the label still says "DBG".
	var dbg: Label = level.get_node("UI/DebugInfo")
	# Wait a couple more frames in case some setup is deferred.
	await get_tree().process_frame
	await get_tree().process_frame
	assert_ne(dbg.text, "DBG",
		"_ready() did NOT reach the end — it threw or returned early. Current label text: %s" % dbg.text)

func test_cowboy_node_exists_and_resolved():
	# Tests that the @onready var resolution found the cowboy.
	# If it didn't, _ready would have thrown at the first line.
	assert_not_null(level.cowboy, "cowboy @onready var resolved to null")
	if level.cowboy:
		assert_eq(level.cowboy.position.y, 1500.0, "cowboy initial y position from tscn")

func test_target_x_initialized_in_ready():
	# After _ready, target_x should equal cowboy.position.x (which is 540).
	assert_eq(level.target_x, 540.0, "target_x not initialized to cowboy.position.x")

# ---------- _process() ----------

func test_process_runs_and_updates_debug_label():
	# Manually call _process() with a sample delta. Should increment counter
	# and update the debug label.
	# IMPORTANT: Godot's own process loop ticks _process during the await
	# get_tree().process_frame calls in before_each, so we count from a
	# captured baseline instead of asserting exact equality from zero.
	var dbg: Label = level.get_node("UI/DebugInfo")
	var baseline_count: int = level._process_run_count
	level._process(0.016)
	level._process(0.016)
	level._process(0.016)
	assert_true("proc:" in dbg.text,
		"_process did not update label to 'proc:N ...' format. Got: %s" % dbg.text)
	assert_eq(level._process_run_count, baseline_count + 3,
		"_process_run_count should be baseline (%d) + 3 after 3 direct calls" % baseline_count)

# ---------- _input() ----------

func test_screen_drag_event_updates_target_x():
	# Direct call to _input(event). If this works, the event routing is fine
	# in headless mode and any Android bug is in real-event dispatch.
	var drag := InputEventScreenDrag.new()
	drag.position = Vector2(200.0, 1500.0)
	level._input(drag)
	# clamp_x clamps to [MARGIN_X, VIEWPORT_WIDTH - MARGIN_X] = [80, 1000].
	# 200 stays at 200.
	assert_eq(level.target_x, 200.0, "target_x should equal drag.position.x after drag event")
	assert_eq(level._input_event_count, 1, "input event count should be 1")
	assert_eq(level._last_input_type, "DRAG", "last input type should be DRAG")

func test_mouse_motion_event_updates_target_x():
	# Touch events on Android get emulated as mouse events too. Verify we
	# handle that path.
	var mm := InputEventMouseMotion.new()
	mm.position = Vector2(800.0, 1500.0)
	mm.button_mask = MOUSE_BUTTON_MASK_LEFT
	level._input(mm)
	assert_eq(level.target_x, 800.0, "target_x should equal mouse.position.x")
	assert_eq(level._last_input_type, "MOUSE_MOTION")

func test_mouse_motion_without_button_pressed_ignored():
	# Hovering shouldn't move the cowboy.
	var mm := InputEventMouseMotion.new()
	mm.position = Vector2(300.0, 1500.0)
	mm.button_mask = 0
	level._input(mm)
	assert_eq(level._input_event_count, 0, "hovering should not count as input")
	assert_eq(level.target_x, 540.0, "target_x should remain at initial 540")

# ---------- end-to-end: input → process → cowboy moves ----------

func test_drag_event_then_processing_moves_cowboy_toward_target():
	var cowboy: Node2D = level.get_node("Cowboy")
	var initial_x: float = cowboy.position.x
	assert_eq(initial_x, 540.0, "cowboy starts centered")

	# Drag to the left.
	var drag := InputEventScreenDrag.new()
	drag.position = Vector2(200.0, 1500.0)
	level._input(drag)
	assert_eq(level.target_x, 200.0, "target_x set to drag position")

	# Tick _process for 0.5 seconds total. With FOLLOW_SPEED=12, the
	# cowboy should lerp most of the way toward target_x=200.
	for i in 30:
		level._process(0.016)

	assert_lt(cowboy.position.x, initial_x,
		"cowboy did not move leftward (initial %.0f, now %.0f, target %.0f)" % [
			initial_x, cowboy.position.x, level.target_x
		])
	assert_lt(cowboy.position.x, 350.0,
		"cowboy didn't get most of the way to target=200 in 0.5s. position=%.0f" % cowboy.position.x)
