extends Control

# Iter 148: prop-sway profile picker.
# Shows 5 hero cutouts in a row in a live 3D preview, each running a
# different sway profile (1-5) from breathing_prop.gdshader. Buttons
# below pick the global default, saved via the SwayPrefs autoload.

const BREATHING_SHADER := preload("res://shaders/breathing_prop.gdshader")
const PREVIEW_TEX_PATH := "res://assets/sprites/props/hero_marshmallow_sheriff.png"

# Profiles shown in the picker (1-5; profile 0 = legacy is not offered).
const PICKER_PROFILES: Array[int] = [1, 2, 3, 4, 5]
const PROP_HEIGHT: float = 1.8
const PROP_SPACING: float = 1.5

@onready var viewport: SubViewport = $VBox/PreviewBox/Viewport
@onready var profile_buttons: HBoxContainer = $VBox/ProfileButtons
@onready var status_label: Label = $VBox/StatusLabel
@onready var back_button: Button = $VBox/BackButton

var _btns: Dictionary = {}  # profile_int -> Button

const SELECTED_FG: Color = Color(0.12, 0.08, 0.04, 1.0)
const UNSELECTED_FG: Color = Color(0.92, 0.85, 0.65, 1.0)
const SELECTED_MOD: Color = Color(1.20, 1.10, 0.85, 1.0)
const UNSELECTED_MOD: Color = Color(1.0, 1.0, 1.0, 1.0)

func _ready() -> void:
	get_tree().set_quit_on_go_back(false)
	if get_window():
		get_window().go_back_requested.connect(_on_back_pressed)
	back_button.pressed.connect(_on_back_pressed)
	_spawn_preview_props()
	_build_buttons()
	_restyle()

# One billboard per profile, in a row, each running its sway profile so
# the user can compare all five motions side-by-side, live.
func _spawn_preview_props() -> void:
	var tex: Texture2D = null
	if ResourceLoader.exists(PREVIEW_TEX_PATH):
		tex = load(PREVIEW_TEX_PATH)
	# Iter 154: size the plane to the TEXTURE's aspect ratio. The fixed
	# 0.62:1 plane squashed the 1.83:1 hero PNG → distorted/wrong-aspect
	# cutouts (user feedback). Plane aspect = texture aspect = no stretch.
	var tex_aspect: float = 0.62
	if tex != null and tex.get_height() > 0:
		tex_aspect = float(tex.get_width()) / float(tex.get_height())
	var n: int = PICKER_PROFILES.size()
	var x0: float = -PROP_SPACING * float(n - 1) * 0.5
	for i in range(n):
		var profile: int = PICKER_PROFILES[i]
		var mesh := MeshInstance3D.new()
		var plane := PlaneMesh.new()
		plane.size = Vector2(PROP_HEIGHT * tex_aspect, PROP_HEIGHT)
		plane.subdivide_width = 5
		plane.subdivide_depth = 7
		plane.orientation = 2  # FACE_Z
		mesh.mesh = plane
		var mat := ShaderMaterial.new()
		mat.shader = BREATHING_SHADER
		if tex != null:
			mat.set_shader_parameter("albedo_tex", tex)
		mat.set_shader_parameter("modulate", Color(1, 1, 1, 1))
		mat.set_shader_parameter("sway_profile", profile)
		mat.set_shader_parameter("sway_intensity", 1.0)
		mat.set_shader_parameter("mesh_height", PROP_HEIGHT)
		# Stagger time_offset so the five aren't phase-locked.
		mat.set_shader_parameter("time_offset", float(i) * 1.1)
		mesh.material_override = mat
		# Position: row along X, base sitting on y=0 (mesh centered → y = h/2).
		mesh.position = Vector3(x0 + PROP_SPACING * float(i), PROP_HEIGHT * 0.5, 0)
		viewport.add_child(mesh)
		# Name plate under each.
		var label := Label3D.new()
		label.text = SwayPrefs.PROFILE_NAMES[profile]
		label.font_size = 56
		label.outline_size = 8
		label.modulate = Color(1.0, 0.92, 0.55, 1)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.position = Vector3(x0 + PROP_SPACING * float(i), -0.35, 0)
		label.pixel_size = 0.0028
		viewport.add_child(label)

func _build_buttons() -> void:
	for profile in PICKER_PROFILES:
		var btn := Button.new()
		btn.text = SwayPrefs.PROFILE_NAMES[profile]
		btn.custom_minimum_size = Vector2(0, 120)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.add_theme_font_size_override("font_size", 24)
		btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		btn.pressed.connect(_on_profile_pressed.bind(profile))
		profile_buttons.add_child(btn)
		_btns[profile] = btn

func _on_profile_pressed(profile: int) -> void:
	SwayPrefs.set_profile(profile)
	if get_node_or_null("/root/AudioBus"):
		AudioBus.play_tap()
	_restyle()

func _restyle() -> void:
	var active: int = SwayPrefs.get_profile()
	for profile in _btns.keys():
		var b: Button = _btns[profile]
		var sel: bool = (profile == active)
		b.add_theme_color_override("font_color", SELECTED_FG if sel else UNSELECTED_FG)
		b.add_theme_color_override("font_color_hover", SELECTED_FG if sel else UNSELECTED_FG)
		b.modulate = SELECTED_MOD if sel else UNSELECTED_MOD
	var active_name: String = SwayPrefs.PROFILE_NAMES[active] if active < SwayPrefs.PROFILE_NAMES.size() else "?"
	status_label.text = "current default: %s    (saved)" % active_name

func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/debug_menu.tscn")
