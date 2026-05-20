extends Node2D

# Candy Crush-style world map. A winding path of level nodes sits on the
# 3D terrain plane (terrain_3d_level_select.tscn) — the path itself is
# baked into the dirt texture, so it renders with the camera's
# perspective as part of the ground.
#
# Iter 158: the level nodes are "bound to the terrain". Perspective
# scaling shrinks + haze-fades distant (far-up) nodes, and a soft contact
# shadow under each node grounds it on the dirt. Drag-to-pan was removed
# (all eight nodes fit one screen). Level 2 — boss The Candy Rustler — is
# playable alongside level 1.
#
# Iter 159: Professor Humbug stands at the lower-left as the trailhead
# guide. Tapping him sparks a flourish + a TIP (speech bubble + voice) or,
# now and then, a THOUGHT (thought bubble + harp + voice). Monsieur
# Canard — the gold duck-head on his cane — has his own tap zone and
# quacks. (Flourishes are procedural tweens: a tip-bow, a thought-lean
# and a Canard-wiggle — the three "movements" for Humbug and Canard.
# Veo video flourishes would need the Veo pipeline + credentials, which
# aren't available in this build environment.)

const BuildInfo = preload("res://scripts/build_info.gd")
const GAME_THEME := preload("res://assets/theme.tres")
const HARP_SFX := preload("res://assets/sfx/harp_thought.wav")

@onready var level_1_button: Button = $LevelNode1
@onready var level_2_button: Button = $LevelNode2
@onready var back_button: Button = $UI/BackButton
@onready var humbug: TextureButton = $Humbug
@onready var canard_zone: Control = $Humbug/CanardZone

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

# Iter 159: Humbug / Canard interaction.
const HUMBUG_MENU_LINES: int = 6     # humbug_menu_0..5.mp3
const CANARD_QUACKS: int = 3         # canard_quack_0..2.mp3
const HUMBUG_THOUGHT_CHANCE: float = 0.32
const BUBBLE_POS := Vector2(130.0, 1000.0)
const BUBBLE_SIZE := Vector2(580.0, 260.0)

# Iter 160: easter eggs.
const HUMBUG_EGG_TAPS: int = 6         # accepted taps inside the window → jokes
const HUMBUG_EGG_WINDOW: float = 60.0
const CANARD_EGG_TAPS: int = 14        # taps → explosion + a fresh duck-head
const POOF_SFX := preload("res://assets/sfx/poof.wav")
const CANARD_HEAD_REGION := Rect2(241.0, 410.0, 100.0, 105.0)  # duck-head in the Humbug PNG (iter 163: tracked the CanardZone nudge)
var CANARD_QUACK_STREAMS: Array = [
	preload("res://assets/audio/characters/canard_quack_0.mp3"),
	preload("res://assets/audio/characters/canard_quack_1.mp3"),
	preload("res://assets/audio/characters/canard_quack_2.mp3"),
]

var _humbug_base_pos: Vector2
var _humbug_tapped_at: float = 0.0
var _humbug_flourish: Tween
var _humbug_bubble: Control = null
var _harp_player: AudioStreamPlayer
# Tap bookkeeping the iter-160 easter eggs build on.
var _humbug_tap_times: Array[float] = []
var _canard_tap_count: int = 0
# Iter 160 easter-egg state.
var _humbug_joke_idx: int = 0
var _canard_player: AudioStreamPlayer
var _canard_new_head: Sprite2D = null

func _ready() -> void:
	get_tree().set_quit_on_go_back(false)
	get_window().go_back_requested.connect(_on_back_requested)
	DebugLog.add("level_select _ready (build=%s)" % BuildInfo.SHA)
	level_1_button.pressed.connect(_on_level_1_pressed)
	level_2_button.pressed.connect(_on_level_2_pressed)
	back_button.pressed.connect(_on_back_pressed)
	_ground_level_nodes()
	_setup_humbug()
	_build_debug_overlay()

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

# ---------------------------------------------------------------------------
# Iter 159: Professor Humbug + Monsieur Canard
# ---------------------------------------------------------------------------

func _setup_humbug() -> void:
	humbug.pivot_offset = humbug.size * 0.5  # flourishes scale/rotate in place
	_humbug_base_pos = humbug.position
	humbug.pressed.connect(_on_humbug_pressed)
	canard_zone.mouse_filter = Control.MOUSE_FILTER_STOP
	canard_zone.gui_input.connect(_on_canard_tap)
	_harp_player = AudioStreamPlayer.new()
	_harp_player.stream = HARP_SFX
	_harp_player.bus = "Master"
	_harp_player.volume_db = -4.0
	add_child(_harp_player)
	_canard_player = AudioStreamPlayer.new()
	_canard_player.bus = "Master"
	add_child(_canard_player)

# Tap Humbug → a flourish + mostly a tip (speech bubble), now and then a
# thought (thought bubble + harp). Voice reuses his six menu lines.
func _on_humbug_pressed() -> void:
	if not _humbug_tap_accepted():
		return
	# Iter 160: pestered HUMBUG_EGG_TAPS times inside the window → he
	# cracks and snips a (cycling) joke line instead of offering a tip.
	if _humbug_tap_times.size() >= HUMBUG_EGG_TAPS:
		_humbug_joke()
		return
	if randf() < HUMBUG_THOUGHT_CHANCE:
		_humbug_thought_flourish()
		_show_humbug_bubble(Text.random("humbug.thoughts"), true)
		if _harp_player != null:
			_harp_player.play()
	else:
		_humbug_tip_flourish()
		_show_humbug_bubble(Text.random("humbug.tips"), false)
	if get_node_or_null("/root/AudioBus") and AudioBus.has_method("play_character_line"):
		AudioBus.play_character_line("humbug_menu_%d" % (randi() % HUMBUG_MENU_LINES))

# Debounce (1s) + don't let him talk over himself. Records the accepted
# tap time — the iter-160 "still touching me?" easter egg reads this.
func _humbug_tap_accepted() -> bool:
	var now: float = Time.get_unix_time_from_system()
	if now - _humbug_tapped_at < 1.0:
		return false
	if get_node_or_null("/root/AudioBus") and AudioBus.has_method("any_character_line_playing"):
		if AudioBus.any_character_line_playing():
			return false
	_humbug_tapped_at = now
	_humbug_tap_times.append(now)
	var cutoff: float = now - HUMBUG_EGG_WINDOW
	while not _humbug_tap_times.is_empty() and _humbug_tap_times[0] < cutoff:
		_humbug_tap_times.remove_at(0)
	return true

# Tap Canard (the duck-head cane handle) → a quack + a quick wiggle.
# accept_event() keeps the tap from also firing Humbug's tip.
func _on_canard_tap(event: InputEvent) -> void:
	var is_press: bool = false
	if event is InputEventScreenTouch:
		is_press = (event as InputEventScreenTouch).pressed
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		is_press = mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed
	if not is_press:
		return
	canard_zone.accept_event()
	_canard_tap_count += 1
	# Iter 160: the CANARD_EGG_TAPS-th tap is the last straw — Canard
	# bursts, then a fresh duck-head springs from the cane.
	if _canard_tap_count >= CANARD_EGG_TAPS:
		_canard_tap_count = 0
		_canard_explode()
		return
	# Increasingly annoyed: quacks climb in pitch + volume and the wiggle
	# sharpens the more he is pestered.
	var heat: float = float(_canard_tap_count) / float(CANARD_EGG_TAPS)
	_canard_wiggle(1.0 + heat * 1.7)
	if _canard_player != null:
		_canard_player.stream = CANARD_QUACK_STREAMS[randi() % CANARD_QUACK_STREAMS.size()]
		_canard_player.pitch_scale = 1.0 + heat * 0.6
		_canard_player.volume_db = -3.0 + heat * 4.0
		_canard_player.play()

# Three procedural flourishes. Each resets Humbug to rest first so rapid
# taps can't compound the transform.
func _reset_humbug_transform() -> void:
	if _humbug_flourish != null:
		_humbug_flourish.kill()
	humbug.position = _humbug_base_pos
	humbug.scale = Vector2.ONE
	humbug.rotation = 0.0

func _humbug_tip_flourish() -> void:
	_reset_humbug_transform()
	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(humbug, "scale", Vector2(1.06, 0.90), 0.12) \
		.set_trans(Tween.TRANS_QUAD)
	t.tween_property(humbug, "position", _humbug_base_pos + Vector2(0, 14), 0.12) \
		.set_trans(Tween.TRANS_QUAD)
	t.chain().tween_property(humbug, "scale", Vector2.ONE, 0.32) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(humbug, "position", _humbug_base_pos, 0.32) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_humbug_flourish = t

func _humbug_thought_flourish() -> void:
	_reset_humbug_transform()
	var t := create_tween()
	t.tween_property(humbug, "rotation", -0.055, 0.5) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t.tween_interval(0.45)
	t.tween_property(humbug, "rotation", 0.0, 0.7) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_humbug_flourish = t

func _canard_wiggle(intensity: float = 1.0) -> void:
	_reset_humbug_transform()
	var a: float = 0.05 * intensity
	var t := create_tween()
	t.tween_property(humbug, "rotation", a, 0.09).set_trans(Tween.TRANS_SINE)
	t.tween_property(humbug, "rotation", -a * 0.82, 0.12).set_trans(Tween.TRANS_SINE)
	t.tween_property(humbug, "rotation", 0.0, 0.13) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_humbug_flourish = t

# Pop a speech/thought bubble above Humbug; auto-dismiss after a beat.
func _show_humbug_bubble(text: String, is_thought: bool) -> void:
	if _humbug_bubble != null and is_instance_valid(_humbug_bubble):
		_humbug_bubble.queue_free()
	var bubble := _build_bubble(text, is_thought)
	add_child(bubble)
	_humbug_bubble = bubble
	bubble.pivot_offset = BUBBLE_SIZE * 0.5
	bubble.scale = Vector2.ZERO
	var t := create_tween()
	t.tween_property(bubble, "scale", Vector2.ONE, 0.30) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_interval(3.6)
	t.tween_property(bubble, "modulate:a", 0.0, 0.45)
	t.tween_callback(bubble.queue_free)

func _build_bubble(text: String, is_thought: bool) -> Control:
	var root := Control.new()
	root.theme = GAME_THEME
	root.position = BUBBLE_POS
	root.size = BUBBLE_SIZE
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if is_thought:
		_add_thought_dots(root)
	else:
		_add_speech_tail(root)
	var panel := Panel.new()
	panel.size = BUBBLE_SIZE
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.90, 0.93, 0.99, 1) if is_thought else Color(0.98, 0.95, 0.86, 1)
	sb.border_color = Color(0.45, 0.50, 0.62, 1) if is_thought else Color(0.42, 0.26, 0.13, 1)
	sb.set_border_width_all(7)
	sb.set_corner_radius_all(46)
	sb.shadow_color = Color(0.0, 0.0, 0.0, 0.28)
	sb.shadow_size = 10
	sb.shadow_offset = Vector2(0, 6)
	panel.add_theme_stylebox_override("panel", sb)
	root.add_child(panel)
	var label := Label.new()
	label.text = text
	label.position = Vector2(38, 28)
	label.size = BUBBLE_SIZE - Vector2(76, 56)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", 33)
	label.add_theme_color_override("font_color", Color(0.22, 0.13, 0.05, 1))
	root.add_child(label)
	return root

# Speech bubble: a filled triangle tail pointing down-left at Humbug.
func _add_speech_tail(root: Control) -> void:
	var tail := Polygon2D.new()
	tail.color = Color(0.98, 0.95, 0.86, 1)
	tail.polygon = PackedVector2Array([
		Vector2(55, BUBBLE_SIZE.y - 8),
		Vector2(160, BUBBLE_SIZE.y - 8),
		Vector2(5, BUBBLE_SIZE.y + 100),
	])
	root.add_child(tail)

# Thought bubble: three shrinking puffs trailing down-left at Humbug.
func _add_thought_dots(root: Control) -> void:
	var fill := Color(0.90, 0.93, 0.99, 1)
	var specs := [
		[Vector2(95, BUBBLE_SIZE.y + 12), 24.0],
		[Vector2(55, BUBBLE_SIZE.y + 58), 16.0],
		[Vector2(22, BUBBLE_SIZE.y + 96), 10.0],
	]
	for spec in specs:
		var dot := Polygon2D.new()
		dot.color = fill
		dot.polygon = _circle_points(spec[1])
		dot.position = spec[0]
		root.add_child(dot)

func _circle_points(r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 16:
		var a: float = TAU * float(i) / 16.0
		pts.append(Vector2(cos(a) * r, sin(a) * r))
	return pts

# --- Iter 160: easter eggs -------------------------------------------------

# Humbug, pestered past HUMBUG_EGG_TAPS in the window, drops the tips and
# snips a joke. The three lines cycle (annoyed → giggling → dismissive).
func _humbug_joke() -> void:
	_humbug_annoyed_flourish()
	_show_humbug_bubble(Text.lookup("humbug.easter_jokes.%d" % _humbug_joke_idx), false)
	_humbug_joke_idx = (_humbug_joke_idx + 1) % 3
	if get_node_or_null("/root/AudioBus") and AudioBus.has_method("play_character_line"):
		AudioBus.play_character_line("humbug_menu_%d" % (randi() % HUMBUG_MENU_LINES))

# A brisk "no-no-no" head-shake — the pestered/annoyed flourish.
func _humbug_annoyed_flourish() -> void:
	_reset_humbug_transform()
	var t := create_tween()
	for _i in 3:
		t.tween_property(humbug, "rotation", 0.085, 0.07).set_trans(Tween.TRANS_SINE)
		t.tween_property(humbug, "rotation", -0.085, 0.07).set_trans(Tween.TRANS_SINE)
	t.tween_property(humbug, "rotation", 0.0, 0.10) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_humbug_flourish = t

# The CANARD_EGG_TAPS-th tap: a poof, a candy-shrapnel burst, and a fresh
# duck-head that springs out of the licorice cane a beat later.
func _canard_explode() -> void:
	var origin: Vector2 = _humbug_base_pos + canard_zone.position + canard_zone.size * 0.5
	if _canard_player != null:
		_canard_player.stream = POOF_SFX
		_canard_player.pitch_scale = 1.0
		_canard_player.volume_db = 0.0
		_canard_player.play()
	_humbug_annoyed_flourish()
	_spawn_explosion_fx(origin)
	get_tree().create_timer(0.45).timeout.connect(_spawn_new_canard_head.bind(origin))

func _spawn_explosion_fx(origin: Vector2) -> void:
	var flash := Polygon2D.new()
	flash.color = Color(1.0, 0.95, 0.70, 0.92)
	flash.polygon = _circle_points(40.0)
	flash.position = origin
	add_child(flash)
	var ft := create_tween()
	ft.set_parallel(true)
	ft.tween_property(flash, "scale", Vector2(3.4, 3.4), 0.35) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	ft.tween_property(flash, "modulate:a", 0.0, 0.35)
	ft.chain().tween_callback(flash.queue_free)
	var burst := CPUParticles2D.new()
	burst.position = origin
	burst.emitting = false
	burst.one_shot = true
	burst.explosiveness = 1.0
	burst.amount = 26
	burst.lifetime = 0.7
	burst.direction = Vector2(0, -1)
	burst.spread = 180.0
	burst.initial_velocity_min = 220.0
	burst.initial_velocity_max = 520.0
	burst.gravity = Vector2(0, 900)
	burst.scale_amount_min = 5.0
	burst.scale_amount_max = 11.0
	burst.color = Color(1.0, 0.82, 0.25, 1)
	add_child(burst)
	burst.emitting = true
	get_tree().create_timer(1.7).timeout.connect(burst.queue_free)

# A fresh Monsieur Canard springs from the cane, bounces onto the
# cane-top (covering the burst original), and quacks his debut.
func _spawn_new_canard_head(origin: Vector2) -> void:
	if _canard_new_head != null and is_instance_valid(_canard_new_head):
		_canard_new_head.queue_free()
	var head := Sprite2D.new()
	var at := AtlasTexture.new()
	at.atlas = humbug.texture_normal
	at.region = CANARD_HEAD_REGION
	head.texture = at
	head.position = origin
	head.scale = Vector2.ZERO
	add_child(head)
	_canard_new_head = head
	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(head, "scale", Vector2(0.95, 0.95), 0.30) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(head, "position", origin + Vector2(0, -56), 0.30) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.chain()
	t.tween_property(head, "position", origin, 0.24) \
		.set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(head, "scale", Vector2(0.85, 0.85), 0.24)
	get_tree().create_timer(0.34).timeout.connect(func() -> void:
		if _canard_player != null:
			_canard_player.stream = CANARD_QUACK_STREAMS[0]
			_canard_player.pitch_scale = 1.06
			_canard_player.volume_db = -2.0
			_canard_player.play())

# ---------------------------------------------------------------------------

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

# ---------------------------------------------------------------------------
# Iter 161: debug-build-only tap-area + coordinate-grid overlay.
# ---------------------------------------------------------------------------

# Build the overlay (debug builds only — release never shows it). Captures
# each tap area's resting on-screen quad and hands them to the overlay,
# which draws a 100px grid + outlined polygons + (x,y) readouts.
func _build_debug_overlay() -> void:
	if not OS.has_feature("debug"):
		return
	var overlay = preload("res://scripts/debug_tap_overlay.gd").new()
	var t: Array = []
	t.append({"name": "Humbug", "color": Color(1.0, 0.30, 0.55),
		"quad": _control_screen_quad(humbug)})
	t.append({"name": "CanardZone", "color": Color(0.25, 0.85, 1.0),
		"quad": _control_screen_quad(canard_zone)})
	t.append({"name": "BackButton", "color": Color(1.0, 0.70, 0.20),
		"quad": _control_screen_quad(back_button)})
	# The speech/thought bubble's resting rect (it only exists on tap).
	t.append({"name": "HumbugBubble", "color": Color(0.80, 0.55, 1.0),
		"quad": PackedVector2Array([
			BUBBLE_POS,
			BUBBLE_POS + Vector2(BUBBLE_SIZE.x, 0.0),
			BUBBLE_POS + BUBBLE_SIZE,
			BUBBLE_POS + Vector2(0.0, BUBBLE_SIZE.y),
		])})
	for nm in LEVEL_NODE_NAMES:
		var node: Control = get_node_or_null(NodePath(nm)) as Control
		if node != null:
			t.append({"name": nm, "color": Color(0.45, 1.0, 0.45),
				"quad": _control_screen_quad(node)})
	overlay.targets = t
	var layer := CanvasLayer.new()
	layer.layer = 128  # above the UI layer — grid sits on top of everything
	layer.add_child(overlay)
	add_child(layer)
	DebugLog.add("level_select: debug tap+grid overlay built (%d targets)" % t.size())

# A control's true on-screen quad — the four corners of its local rect run
# through the global transform, so scale / rotation / pivot are honored
# (get_global_rect() would miss the perspective scaling on level nodes).
func _control_screen_quad(c: Control) -> PackedVector2Array:
	var xf: Transform2D = c.get_global_transform()
	var s: Vector2 = c.size
	return PackedVector2Array([
		xf * Vector2(0.0, 0.0),
		xf * Vector2(s.x, 0.0),
		xf * Vector2(s.x, s.y),
		xf * Vector2(0.0, s.y),
	])
