extends Control

# "Help an old gal round up her hens?" pop-up + persistent cooldown badge for
# Granny's Chicken Chase, built in code. Shown on the level-select map when the
# chase is available. The daily attempt is only spent when the run BEGINS (in
# chicken_chase.gd), so dismissing here never burns the day.

signal play_pressed

const _RYE := preload("res://assets/fonts/Rye-Regular.ttf")
const _GRANNY_TEX := "res://assets/sprites/props/granny_cutout.png"
const GrannyCackler := preload("res://scripts/granny_cackler.gd")

var _prompt: Control = null
var _badge: Control = null
var _badge_label: Label = null
var _granny_img: TextureRect = null

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_prompt()
	_build_badge()
	_refresh()

func _build_prompt() -> void:
	_prompt = Control.new()
	_prompt.set_anchors_preset(Control.PRESET_CENTER)
	add_child(_prompt)
	var bg := ColorRect.new()
	bg.color = Color(0.2, 0.1, 0.18, 0.92)
	bg.size = Vector2(560, 360)
	bg.position = Vector2(-280, -180)
	_prompt.add_child(bg)
	_granny_img = TextureRect.new()
	_granny_img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_granny_img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_granny_img.size = Vector2(180, 240)
	_granny_img.position = Vector2(-260, -150)
	if ResourceLoader.exists(_GRANNY_TEX):
		_granny_img.texture = load(_GRANNY_TEX)
	_prompt.add_child(_granny_img)
	var msg := Label.new()
	msg.add_theme_font_override("font", _RYE)
	msg.add_theme_font_size_override("font_size", 36)
	msg.add_theme_color_override("font_color", Color(1, 0.95, 0.85))
	msg.text = "Help an old gal\nround up her hens,\nsugar?"
	msg.size = Vector2(300, 200)
	msg.position = Vector2(-60, -150)
	msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_prompt.add_child(msg)
	var play := _make_button("CHASE!", Vector2(-60, 70))
	play.pressed.connect(func(): emit_signal("play_pressed"))
	_prompt.add_child(play)
	var not_now := _make_button("Not now", Vector2(120, 70))
	not_now.pressed.connect(func(): _prompt.visible = false)
	_prompt.add_child(not_now)
	# iter620 (#87): the cackle moved INTO the chicken minigame (chicken_chase.gd).
	# It used to run here on the level-select map and could be heard cackling even
	# after the prompt was dismissed — owner asked for cackle to be minigame-only.

func _build_badge() -> void:
	_badge = Control.new()
	_badge.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_badge.position = Vector2(24, 24)
	add_child(_badge)
	var bg := ColorRect.new()
	bg.color = Color(0.85, 0.45, 0.55, 0.85)
	bg.size = Vector2(150, 60)
	_badge.add_child(bg)
	var btn := Button.new()
	btn.flat = true
	btn.size = Vector2(150, 60)
	btn.pressed.connect(func():
		if get_node_or_null("/root/GameState") == null or GameState.chicken_chase_available():
			_prompt.visible = true)
	_badge.add_child(btn)
	_badge_label = Label.new()
	_badge_label.add_theme_font_override("font", _RYE)
	_badge_label.add_theme_font_size_override("font_size", 28)
	_badge_label.size = Vector2(150, 60)
	_badge_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_badge_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_badge_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_badge.add_child(_badge_label)

func _make_button(text: String, pos: Vector2) -> Button:
	var b := Button.new()
	b.text = text
	b.position = pos
	b.size = Vector2(140, 70)
	b.add_theme_font_override("font", _RYE)
	b.add_theme_font_size_override("font_size", 34)
	return b

func _refresh() -> void:
	var available: bool = get_node_or_null("/root/GameState") == null or GameState.chicken_chase_available()
	_prompt.visible = available
	if available:
		_badge_label.text = "🐔 Ready!"
	else:
		var s: int = GameState.seconds_until_chase()
		_badge_label.text = "🐔 %02d:%02d" % [s / 3600, (s % 3600) / 60]

func _process(_dt: float) -> void:
	# cheap refresh of the cooldown label while the prompt is dismissed
	if _prompt != null and not _prompt.visible:
		_refresh_badge_only()

func _refresh_badge_only() -> void:
	if get_node_or_null("/root/GameState") == null or GameState.chicken_chase_available():
		_badge_label.text = "🐔 Ready!"
	else:
		var s: int = GameState.seconds_until_chase()
		_badge_label.text = "🐔 %02d:%02d" % [s / 3600, (s % 3600) / 60]
