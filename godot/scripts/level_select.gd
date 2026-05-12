extends Node2D

# Candy Crush-style world map. The player sees a winding path of level
# nodes on top of the 3D terrain plane (instance of terrain_3d.tscn).
# Tapping the active level node starts that level; locked nodes do
# nothing yet (no save-data progression in v1, so visually they're just
# foreshadowing future content).
#
# Iter 40: first cut. Just one playable node (Level 1) + 7 visible-but-
# locked placeholders along the path. Cowboy sprite sits next to Level 1
# as the "you are here" marker. Back button returns to main menu.
#
# Future iters will: animate the cowboy walking along the path between
# levels, populate the locked nodes as the player progresses through the
# procgen library, place 3D set-dressing along the path (saloons, water
# tower, etc.), and add a "current biome" header that changes color as
# the path moves through plains → ranch → mining town → ghost town →
# canyon → train tracks.

const BuildInfo = preload("res://scripts/build_info.gd")

@onready var level_1_button: Button = $LevelNode1
@onready var back_button: Button = $UI/BackButton

func _ready() -> void:
	# Back gesture from level select → main menu (NOT quit app, that only
	# happens from the main menu itself per the platform/predictive-back
	# convention established in iter 26).
	get_tree().set_quit_on_go_back(false)
	get_window().go_back_requested.connect(_on_back_requested)
	DebugLog.add("level_select _ready (build=%s)" % BuildInfo.SHA)
	level_1_button.pressed.connect(_on_level_1_pressed)
	back_button.pressed.connect(_on_back_pressed)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		DebugLog.add("level_select NOTIFICATION_WM_GO_BACK_REQUEST → main menu")
		_to_main_menu()
	elif what == NOTIFICATION_WM_CLOSE_REQUEST:
		_to_main_menu()

func _on_back_requested() -> void:
	DebugLog.add("level_select go_back_requested SIGNAL → main menu")
	_to_main_menu()

func _on_back_pressed() -> void:
	AudioBus.play_tap()
	_to_main_menu()

func _on_level_1_pressed() -> void:
	DebugLog.add("LEVEL 1 selected from level_select")
	AudioBus.play_tap()
	level_1_button.disabled = true
	# Brief Candy-Crush press feedback (squish-and-restore) before scene change.
	var tween := create_tween()
	tween.tween_property(level_1_button, "scale", Vector2(0.92, 0.92), 0.06)
	tween.tween_property(level_1_button, "scale", Vector2(1.0, 1.0), 0.18) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await tween.finished
	get_tree().change_scene_to_file("res://scenes/level.tscn")

func _to_main_menu() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
