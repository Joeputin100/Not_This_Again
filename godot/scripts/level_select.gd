extends Node2D

# Candy Crush-style world map. A winding path of level nodes sits on the
# 3D terrain plane (terrain_3d_level_select.tscn) — the path itself is
# baked into the dirt texture, so it renders with the camera's
# perspective as part of the ground.
#
# Iter 158: the level nodes are "bound to the terrain". Perspective
# scaling shrinks + haze-fades far-up (distant) nodes, and a soft contact
# shadow under each node grounds it on the dirt — so the nodes read as
# part of the receding 3D path instead of flat 2D stickers floating over
# it. Drag-to-pan was removed: all eight nodes already fit one screen,
# and panning the baked-in path texture (while the buttons stayed put)
# was exactly what made the nodes look detached. Level 2 — the level
# whose boss is The Candy Rustler (see level_3d._boss_kind) — is now
# playable alongside level 1.

const BuildInfo = preload("res://scripts/build_info.gd")

@onready var level_1_button: Button = $LevelNode1
@onready var level_2_button: Button = $LevelNode2
@onready var back_button: Button = $UI/BackButton

# Perspective scaling for the path tiles. Nodes near TILE_PERSP_HORIZON_Y
# (far up the screen = distant) shrink toward HORIZON_SCALE; nodes near
# FOREGROUND_Y (near the camera) stay full size.
const TILE_PERSP_HORIZON_Y: float = 250.0
const TILE_PERSP_HORIZON_SCALE: float = 0.45
const TILE_PERSP_FOREGROUND_Y: float = 1750.0
const PERSP_TILE_NAMES: Array[String] = [
	"LevelNode1", "DiffLabel1", "Glyph1Hat",
	"LevelNode2", "DiffLabel2", "Glyph2Pickaxe",
	"LevelNode3Locked", "DiffLabel3", "Glyph3Boot",
	"LevelNode4Locked", "DiffLabel4", "Glyph4Wagon",
	"LevelNode5Locked", "LevelNode6Locked",
	"LevelNode7Locked", "LevelNode8Locked",
	"Cowboy",
]
# The tappable level-node buttons — these get a contact shadow.
const LEVEL_NODE_NAMES: Array[String] = [
	"LevelNode1", "LevelNode2",
	"LevelNode3Locked", "LevelNode4Locked",
	"LevelNode5Locked", "LevelNode6Locked",
	"LevelNode7Locked", "LevelNode8Locked",
]

func _ready() -> void:
	get_tree().set_quit_on_go_back(false)
	get_window().go_back_requested.connect(_on_back_requested)
	DebugLog.add("level_select _ready (build=%s)" % BuildInfo.SHA)
	level_1_button.pressed.connect(_on_level_1_pressed)
	level_2_button.pressed.connect(_on_level_2_pressed)
	back_button.pressed.connect(_on_back_pressed)
	_ground_level_nodes()

# Iter 158: bind the path tiles to the terrain — perspective scale + a
# haze fade with distance, plus a contact shadow per level node.
func _ground_level_nodes() -> void:
	var span: float = TILE_PERSP_FOREGROUND_Y - TILE_PERSP_HORIZON_Y
	for n in PERSP_TILE_NAMES:
		var node: Node = get_node_or_null(NodePath(n))
		if node == null:
			continue
		var y: float = 0.0
		if node is Control:
			var c := node as Control
			c.pivot_offset = c.size * 0.5  # scale about the centre, in place
			y = c.offset_top
		elif node is Node2D:
			y = (node as Node2D).position.y
		else:
			continue
		var t: float = clampf((y - TILE_PERSP_HORIZON_Y) / span, 0.0, 1.0)
		var s: float = lerpf(TILE_PERSP_HORIZON_SCALE, 1.0, t)
		# scale/modulate via get/set so one loop covers Control + Node2D.
		if not node.has_meta("base_scale"):
			node.set_meta("base_scale", node.get("scale"))
		node.set("scale", (node.get_meta("base_scale") as Vector2) * s)
		var mod: Color = node.get("modulate")
		mod.a = lerpf(0.80, 1.0, t)  # distant nodes sit back in the dust
		node.set("modulate", mod)
	for node_name in LEVEL_NODE_NAMES:
		var btn: Control = get_node_or_null(NodePath(node_name)) as Control
		if btn == null or btn.has_node("ContactShadow"):
			continue
		var shadow := _make_contact_shadow(btn.size)
		btn.add_child(shadow)
		btn.move_child(shadow, 0)  # behind the candy disc + its decorations

# A soft dark ellipse pooled at a node's base — sells "planted on dirt"
# rather than "pasted on top". show_behind_parent draws it under the disc.
func _make_contact_shadow(node_size: Vector2) -> Polygon2D:
	var shadow := Polygon2D.new()
	shadow.name = "ContactShadow"
	var w: float = node_size.x * 0.96
	var h: float = node_size.x * 0.28
	var pts := PackedVector2Array()
	var seg: int = 22
	for i in seg:
		var a: float = TAU * float(i) / float(seg)
		pts.append(Vector2(cos(a) * w * 0.5, sin(a) * h * 0.5))
	shadow.polygon = pts
	shadow.color = Color(0.0, 0.0, 0.0, 0.30)
	shadow.show_behind_parent = true
	shadow.position = Vector2(node_size.x * 0.5, node_size.y * 0.97)
	return shadow

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
	_start_level(level_1_button, 1)

func _on_level_2_pressed() -> void:
	_start_level(level_2_button, 2)

# Shared level-start flow: lock the button, set the level (this drives
# the boss dispatch in level_3d — level 2 spawns The Candy Rustler), play
# a brief Candy-Crush squish, then enter the 3D level. The squish tweens
# around the node's CURRENT (perspective-scaled) scale so it doesn't snap
# back to full size.
func _start_level(btn: Button, level_num: int) -> void:
	DebugLog.add("LEVEL %d selected from level_select" % level_num)
	AudioBus.play_tap()
	GameState.current_level = level_num
	btn.disabled = true
	var cur: Vector2 = btn.scale
	var tween := create_tween()
	tween.tween_property(btn, "scale", cur * 0.92, 0.06)
	tween.tween_property(btn, "scale", cur, 0.18) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await tween.finished
	get_tree().change_scene_to_file("res://scenes/level_3d.tscn")

func _to_main_menu() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
