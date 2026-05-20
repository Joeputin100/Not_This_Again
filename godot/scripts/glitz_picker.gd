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
var _preview_aura: CPUParticles3D = null  # iter 146 particle aura
# Iter 142: track buttons so we can restyle the selected ones.
var _bonus_btns: Dictionary = {}    # bonus_slug -> Button
var _preset_btns: Dictionary = {}   # preset_name -> Button

# Iter 143: explicit Color type + 1.0 alpha; iter 142's `const SELECTED_FG := Color(... 1)`
# (int alpha) was rejected as non-constant on Godot 4 release builds, causing the
# entire glitz_picker.gd to fail to parse — scene showed as a blank gray rectangle.
const SELECTED_FG: Color = Color(0.12, 0.08, 0.04, 1.0)
const UNSELECTED_FG: Color = Color(0.92, 0.85, 0.65, 1.0)
const SELECTED_MOD: Color = Color(1.20, 1.10, 0.85, 1.0)
const UNSELECTED_MOD: Color = Color(1.0, 1.0, 1.0, 1.0)

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
		_bonus_btns[bonus] = btn

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
		_preset_btns[preset_name] = btn

# Iter 142: paint the active bonus tab and preset button so user can see
# which one is currently chosen (user feedback: "make the activated
# buttons change color").
func _restyle_buttons() -> void:
	var active_preset: String = GlitzPrefs.get_preset_for_bonus(_current_bonus)
	for bonus in _bonus_btns.keys():
		var b: Button = _bonus_btns[bonus]
		var sel: bool = (bonus == _current_bonus)
		b.add_theme_color_override("font_color", SELECTED_FG if sel else UNSELECTED_FG)
		b.add_theme_color_override("font_color_hover", SELECTED_FG if sel else UNSELECTED_FG)
		b.modulate = SELECTED_MOD if sel else UNSELECTED_MOD
	for preset in _preset_btns.keys():
		var pb: Button = _preset_btns[preset]
		var sel: bool = (preset == active_preset)
		pb.add_theme_color_override("font_color", SELECTED_FG if sel else UNSELECTED_FG)
		pb.add_theme_color_override("font_color_hover", SELECTED_FG if sel else UNSELECTED_FG)
		pb.modulate = SELECTED_MOD if sel else UNSELECTED_MOD

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
	# Iter 148: mesh_height so the breathing shader anchors correctly on
	# this 1.8-tall preview plane (default 1.0 would mis-anchor the puppet
	# squash/lean). Glitz preview keeps the legacy sway profile (0).
	mat.set_shader_parameter("mesh_height", 1.8)
	mesh.material_override = mat
	mesh.position = Vector3(0, 0.9, 0)
	viewport.add_child(mesh)
	_preview_mesh = mesh
	# Iter 146: particle aura — radial sparkles around the silhouette.
	# Emits when halo_strength > 0 (via _apply_current_selection). User
	# feedback: "halo effect is too static. do a particle aura."
	var aura := CPUParticles3D.new()
	aura.amount = 60
	aura.lifetime = 1.4
	aura.one_shot = false
	aura.preprocess = 0.5  # pre-warm so aura isn't empty when picker opens
	aura.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE_SURFACE
	aura.emission_sphere_radius = 0.95
	aura.direction = Vector3(0, 0.4, 0)
	aura.spread = 180.0  # omnidirectional outward
	aura.initial_velocity_min = 0.05
	aura.initial_velocity_max = 0.45
	aura.gravity = Vector3(0, 0.3, 0)  # subtle upward drift
	aura.scale_amount_min = 0.05
	aura.scale_amount_max = 0.12
	aura.color = Color(1.0, 0.85, 0.40, 1.0)
	# Brightness curve: fade in then out
	aura.alpha_curve = _make_alpha_curve()
	# Small quad mesh for each particle
	var quad := QuadMesh.new()
	quad.size = Vector2(0.18, 0.18)
	aura.mesh = quad
	var aura_mat := StandardMaterial3D.new()
	aura_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	aura_mat.albedo_color = Color(1.0, 0.85, 0.40, 1.0)
	aura_mat.emission_enabled = true
	aura_mat.emission = Color(1.0, 0.92, 0.55, 1)
	aura_mat.emission_energy_multiplier = 2.5
	aura_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	aura_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	aura_mat.use_particle_trails = false
	quad.material = aura_mat
	aura.position = Vector3(0, 0.9, 0)
	aura.emitting = false  # gated on halo_strength
	viewport.add_child(aura)
	_preview_aura = aura

func _make_alpha_curve() -> Curve:
	var c := Curve.new()
	c.add_point(Vector2(0.00, 0.0))
	c.add_point(Vector2(0.20, 1.0))
	c.add_point(Vector2(0.70, 0.7))
	c.add_point(Vector2(1.00, 0.0))
	return c

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
	# Iter 142: highlight the active bonus tab + preset button
	_restyle_buttons()
	# Iter 146: gate the particle aura on halo_strength.
	if _preview_aura != null:
		var halo: float = float(GlitzPrefs.PRESETS.get(preset, {}).get("halo_strength", 0.0))
		_preview_aura.emitting = halo > 0.001
		_preview_aura.amount = clampi(int(40.0 + halo * 40.0), 20, 120)

func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/debug_menu.tscn")
