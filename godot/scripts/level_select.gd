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
# Iter 63: terrain reference for drag-to-pan.
@onready var terrain: Node2D = $Terrain3D

# Iter 63: perspective scaling for level tiles + difficulty labels so
# they sit "on" the terrain instead of floating above. Same horizon
# parameters as level.gd's _apply_perspective_scaling, but applied to
# specific named nodes since level_select tiles aren't in scrolling
# groups.
const TILE_PERSP_HORIZON_Y: float = 250.0
const TILE_PERSP_HORIZON_SCALE: float = 0.45
const TILE_PERSP_FOREGROUND_Y: float = 1750.0
const PERSP_TILE_NAMES: Array[String] = [
	"LevelNode1", "DiffLabel1", "Glyph1Hat",
	"LevelNode2Locked", "DiffLabel2", "Glyph2Pickaxe",
	"LevelNode3Locked", "DiffLabel3", "Glyph3Boot",
	"LevelNode4Locked", "DiffLabel4", "Glyph4Wagon",
	"LevelNode5Locked", "LevelNode6Locked",
	"LevelNode7Locked", "LevelNode8Locked",
	"Cowboy",
]

func _ready() -> void:
	get_tree().set_quit_on_go_back(false)
	get_window().go_back_requested.connect(_on_back_requested)
	DebugLog.add("level_select _ready (build=%s)" % BuildInfo.SHA)
	level_1_button.pressed.connect(_on_level_1_pressed)
	back_button.pressed.connect(_on_back_pressed)
	# Iter 63: tile perspective scaling — disabled in iter 64 in favor
	# of full 3D refactor. Tiles will be migrated to 3D billboards
	# inside the terrain SubViewport in a future iter.
	# _apply_tile_perspective()

# Iter 63: drag-to-pan. Track the previous touch y; on drag, nudge the
# terrain's UV offset by the y-delta scaled to a sensible factor.
var _drag_last_y: float = -1.0
const DRAG_SENSITIVITY: float = 0.0005  # texture UV units per screen pixel

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			_drag_last_y = t.position.y
		else:
			_drag_last_y = -1.0
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if _drag_last_y >= 0.0 and terrain and terrain.has_method("nudge_uv"):
			var dy: float = d.position.y - _drag_last_y
			terrain.nudge_uv(-dy * DRAG_SENSITIVITY)
			_drag_last_y = d.position.y
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_drag_last_y = mb.position.y if mb.pressed else -1.0
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if (mm.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0 and _drag_last_y >= 0.0:
			if terrain and terrain.has_method("nudge_uv"):
				var dy: float = mm.position.y - _drag_last_y
				terrain.nudge_uv(-dy * DRAG_SENSITIVITY)
				_drag_last_y = mm.position.y

# Iter 63: scale each named tile by its position.y so far-up tiles
# appear smaller (perspective). Stores base_scale via meta so repeat
# calls don't compound the scaling.
func _apply_tile_perspective() -> void:
	var span: float = TILE_PERSP_FOREGROUND_Y - TILE_PERSP_HORIZON_Y
	for n in PERSP_TILE_NAMES:
		var node: Node = get_node_or_null(n)
		if node == null:
			continue
		# Find a y position to use — Control nodes use offset_top, Node2D
		# uses position.y. Buttons/Labels are Controls.
		var y: float = 0.0
		if node is Control:
			y = float(node.offset_top)
		elif "position" in node:
			y = node.position.y
		else:
			continue
		var t: float = clampf((y - TILE_PERSP_HORIZON_Y) / span, 0.0, 1.0)
		var s: float = lerpf(TILE_PERSP_HORIZON_SCALE, 1.0, t)
		if not node.has_meta("base_scale"):
			node.set_meta("base_scale", node.scale if "scale" in node else Vector2.ONE)
		if "scale" in node:
			node.scale = node.get_meta("base_scale") * s

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
