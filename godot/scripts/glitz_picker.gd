extends Control

# Iter 132: glitz/spin preset picker.
# Three bonus tabs (rifle/frostbite/frenzy) × six glitz presets.
# Live 3D preview shows the currently-selected (bonus × preset) combo
# with all uniforms applied. Selection auto-saves to GlitzPrefs.
#
# Architecture:
#   - BonusTabs (HBox): 3 buttons for current bonus type
#   - PreviewBox (SubViewportContainer): live 3D render of bonus billboard
#       with shader uniforms swapped on selection change
#   - PresetGrid (GridContainer 3 cols × 2 rows): 6 preset thumbnails as
#       text buttons; tap → swap uniforms in the preview viewport
#   - StatusLabel: confirms current selection
#   - BackButton: returns to debug_menu.tscn
#
# Selection automatically saves via GlitzPrefs autoload — no separate
# "SAVE" button needed. User just taps until happy, then back.

const BREATHING_SHADER := preload("res://shaders/breathing_prop.gdshader")

@onready var bonus_tabs: HBoxContainer = $VBox/BonusTabs
@onready var preset_grid: GridContainer = $VBox/PresetGrid
@onready var status_label: Label = $VBox/StatusLabel
@onready var back_button: Button = $VBox/BackButton
@onready var viewport: SubViewport = $VBox/PreviewBox/Viewport
@onready var speed_slider: HSlider = $VBox/SpeedRow/SpeedSlider
@onready var speed_value_label: Label = $VBox/SpeedRow/SpeedValueLabel

var _current_bonus: String = "rifle"
var _preview_mesh: MeshInstance3D = null
var _preview_halo: MeshInstance3D = null

func _ready() -> void:
	get_tree().set_quit_on_go_back(false)
	if get_window():
		get_window().go_back_requested.connect(_on_back_pressed)
	back_button.pressed.connect(_on_back_pressed)
	speed_slider.value_changed.connect(_on_speed_slider_changed)
	_build_bonus_tabs()
	_build_preset_grid()
	_spawn_preview_mesh()
	_apply_current_selection()

func _build_bonus_tabs() -> void:
	for bonus in GlitzPrefs.BONUS_TYPES:
		var btn := Button.new()
		btn.text = bonus.to_upper()
		btn.custom_minimum_size = Vector2(220, 80)
		btn.add_theme_font_size_override("font_size", 36)
		btn.pressed.connect(_on_bonus_tab_pressed.bind(bonus))
		bonus_tabs.add_child(btn)

func _build_preset_grid() -> void:
	# Iter 137: 18 presets — keep buttons readable on a 3-col grid.
	# Per-row height shrinks (120 → 100), font_size shrinks (28 → 22)
	# so the longest preset name "PULSE+HALO+YSPIN" fits without ellipsis.
	for preset_name in GlitzPrefs.PRESET_ORDER:
		var btn := Button.new()
		btn.text = preset_name.replace("_", "+").to_upper()
		btn.custom_minimum_size = Vector2(0, 100)
		btn.add_theme_font_size_override("font_size", 22)
		btn.clip_text = false
		btn.autowrap_mode = TextServer.AUTOWRAP_OFF
		btn.pressed.connect(_on_preset_pressed.bind(preset_name))
		preset_grid.add_child(btn)

# Spawns the preview billboard mesh (uses bonus_crate_rifle texture
# as a placeholder for whichever bonus type is selected; texture swaps
# per tab). Plus a halo plane behind it for the halo_strength effect.
func _spawn_preview_mesh() -> void:
	# Main bonus billboard
	var mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(1.5, 1.8)
	plane.subdivide_width = 5
	plane.subdivide_depth = 7
	plane.orientation = 2  # FACE_Z
	mesh.mesh = plane
	var mat := ShaderMaterial.new()
	mat.shader = BREATHING_SHADER
	mat.set_shader_parameter("modulate", Color(1, 1, 1, 1))
	mat.set_shader_parameter("sway_amp", 0.04)
	mat.set_shader_parameter("sway_freq", 1.5)
	mat.set_shader_parameter("bob_amp", 0.02)
	mat.set_shader_parameter("bob_freq", 2.5)
	mat.set_shader_parameter("time_offset", 0.0)
	mesh.material_override = mat
	mesh.position = Vector3(0, 0.9, 0)
	viewport.add_child(mesh)
	_preview_mesh = mesh

func _on_bonus_tab_pressed(bonus: String) -> void:
	_current_bonus = bonus
	_apply_current_selection()

func _on_preset_pressed(preset: String) -> void:
	GlitzPrefs.set_preset_for_bonus(_current_bonus, preset)
	_apply_current_selection()

func _on_speed_slider_changed(value: float) -> void:
	GlitzPrefs.set_speed_mult_for_bonus(_current_bonus, value)
	speed_value_label.text = "%.2f×" % value
	_apply_current_selection()

# Loads the bonus's saved preset + applies its uniforms to the preview,
# also swaps the bonus texture to match the current tab.
func _apply_current_selection() -> void:
	var preset := GlitzPrefs.get_preset_for_bonus(_current_bonus)
	var speed_mult := GlitzPrefs.get_speed_mult_for_bonus(_current_bonus)
	# Sync slider to saved value WITHOUT re-firing its signal
	if abs(speed_slider.value - speed_mult) > 0.001:
		speed_slider.set_value_no_signal(speed_mult)
		speed_value_label.text = "%.2f×" % speed_mult
	var mat: ShaderMaterial = _preview_mesh.material_override
	if mat == null:
		return
	# Swap texture to current bonus
	var tex_path := "res://assets/sprites/props/bonus_crate_%s.png" % _current_bonus
	if ResourceLoader.exists(tex_path):
		mat.set_shader_parameter("albedo_tex", load(tex_path))
	# Apply preset (slider scales rotation_speed)
	GlitzPrefs.apply_preset_to_material(preset, mat, speed_mult)
	status_label.text = "BONUS: %s    PRESET: %s    SPEED: %.2f×    (saved)" % [
		_current_bonus.to_upper(), preset.replace("_", "+").to_upper(), speed_mult]

func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/debug_menu.tscn")
