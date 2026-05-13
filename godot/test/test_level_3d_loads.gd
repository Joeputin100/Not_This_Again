extends GutTest

# Iter 91: scene-load smoke test for level_3d.tscn. User reports the
# scene freezes the app on a brown screen after navigating to it from
# the debug menu. Since GUT runs in headless Godot, we can verify the
# scene at least LOADS + instantiates without hanging, which catches:
#
#   - Missing resource references (load_steps mismatch)
#   - Parse errors in level_3d.gd
#   - Infinite loops or crashes in _ready
#   - Missing @onready var paths
#
# If _ready hangs, this test will hang the runner — CI's GUT step has
# a job-level timeout-minutes:30 in android-debug.yml, so a hang shows
# up as a job timeout failure.
#
# A working scene passes this in <100ms.

const Level3DScene = preload("res://scenes/level_3d.tscn")

func test_scene_loads():
	# Verify the .tscn file parses + binds resources.
	assert_not_null(Level3DScene, "level_3d.tscn should load as PackedScene")

func test_scene_instantiates():
	var inst: Node = Level3DScene.instantiate()
	assert_not_null(inst, "instantiate() should produce a Node")
	# Verify the root has the expected name + script.
	assert_eq(inst.name, "Level3D")
	# Critical subtree paths used by level_3d.gd's @onready vars.
	assert_not_null(inst.get_node_or_null("Terrain3D/SubViewport"),
		"SubViewport must exist for cowboy + obstacles + bullets")
	assert_not_null(inst.get_node_or_null("Terrain3D/Sprite"),
		"Sprite2D must exist for SubViewport→screen rendering")
	assert_not_null(inst.get_node_or_null("Terrain3D/SubViewport/Cowboy3D"),
		"Cowboy3D Sprite3D must exist")
	assert_not_null(inst.get_node_or_null("Terrain3D/SubViewport/Obstacles"),
		"Obstacles container must exist")
	assert_not_null(inst.get_node_or_null("Terrain3D/SubViewport/Bullets"),
		"Bullets container must exist")
	assert_not_null(inst.get_node_or_null("Terrain3D/SubViewport/Gates"),
		"Gates container must exist (iter 75)")
	assert_not_null(inst.get_node_or_null("Terrain3D/SubViewport/Outlaws"),
		"Outlaws container must exist (iter 76)")
	assert_not_null(inst.get_node_or_null("Terrain3D/SubViewport/OutlawBullets"),
		"OutlawBullets container must exist (iter 76)")
	assert_not_null(inst.get_node_or_null("Terrain3D/SubViewport/Boss"),
		"Boss container must exist (iter 77)")
	assert_not_null(inst.get_node_or_null("Terrain3D/SubViewport/Popups"),
		"Popups container must exist (iter 80)")
	assert_not_null(inst.get_node_or_null("Terrain3D/SubViewport/Bonuses"),
		"Bonuses container must exist (iter 88)")
	# UI subtree
	assert_not_null(inst.get_node_or_null("UI/BackButton"))
	assert_not_null(inst.get_node_or_null("UI/InfoLabel"))
	assert_not_null(inst.get_node_or_null("UI/HeartsLabel"))
	assert_not_null(inst.get_node_or_null("UI/PosseLabel"))
	assert_not_null(inst.get_node_or_null("UI/HitsLabel"))
	assert_not_null(inst.get_node_or_null("UI/WinOverlay"))
	assert_not_null(inst.get_node_or_null("UI/FailOverlay"))
	inst.queue_free()

func test_scene_enters_tree():
	# This actually runs _ready, which is where the suspected freeze
	# happens. If _ready loops infinitely, GUT will hang here.
	var inst: Node = Level3DScene.instantiate()
	add_child_autofree(inst)
	await get_tree().process_frame
	# If we reach here without hanging, _ready completed.
	assert_not_null(inst.get_node_or_null("Terrain3D/SubViewport/Cowboy3D"))
