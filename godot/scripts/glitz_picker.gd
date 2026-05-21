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

@onready var bonus_tabs: HFlowContainer = $VBox/BonusTabs
@onready var preset_grid: GridContainer = $VBox/PresetGrid
@onready var status_label: Label = $VBox/StatusLabel
@onready var back_button: Button = $VBox/BackButton
@onready var viewport: SubViewport = $VBox/PreviewBox/Viewport
@onready var speed_slider: HSlider = $VBox/SpeedRow/SpeedSlider
@onready var speed_value_label: Label = $VBox/SpeedRow/SpeedValueLabel

var _current_bonus: String = "rifle"
var _preview_mesh: MeshInstance3D = null
var _preview_halo: MeshInstance3D = null
var _preview_aura: MeshInstance3D = null  # iter 171: electric-aura ImmediateMesh
var _aura_t: float = 0.0
# Iter 175: alternate "sunburst" aura + the toggle between the two styles.
var _preview_sunburst: MeshInstance3D = null
var _aura_is_electric: bool = true
var _aura_btn: Button = null
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
	_build_aura_toggle()
	_apply_current_selection()

func _build_bonus_tabs() -> void:
	for bonus in GlitzPrefs.BONUS_TYPES:
		var btn := Button.new()
		btn.text = bonus.to_upper()
		btn.custom_minimum_size = Vector2(150, 60)  # iter 175: smaller — 14 bonus tabs now
		btn.add_theme_font_size_override("font_size", 22)
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
	# Iter 171: electric aura — 12 spinning, curving, glowing arcs + a
	# pulsing centre orb, additively blended. A faithful port of the
	# roguelike WebGL demo's 12-petal Canvas-2D "ELECTRIC AURA", rebuilt
	# every frame into an ImmediateMesh by _rebuild_electric_aura.
	# (iter 167's filled 12-petal star — the "sunburst" — is kept as
	# _make_sunburst_mesh on request, as a separate aura style.)
	var aura := MeshInstance3D.new()
	aura.mesh = ImmediateMesh.new()
	var aura_mat := StandardMaterial3D.new()
	aura_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	aura_mat.vertex_color_use_as_albedo = true
	aura_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	aura_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	aura_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	aura.material_override = aura_mat
	aura.position = Vector3(0, 0.9, -0.05)  # just behind the bonus billboard
	aura.visible = false  # gated on halo_strength
	viewport.add_child(aura)
	_preview_aura = aura
	# Iter 175: the alternate sunburst aura (iter-167 filled 12-petal
	# star), shown when the AURA toggle is set to SUNBURST.
	var burst := MeshInstance3D.new()
	burst.mesh = _make_sunburst_mesh()
	var burst_mat := StandardMaterial3D.new()
	burst_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	burst_mat.vertex_color_use_as_albedo = true
	burst_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	burst_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	burst_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	burst.material_override = burst_mat
	burst.position = Vector3(0, 0.9, -0.05)
	burst.scale = Vector3(1.4, 1.4, 1.0)
	burst.visible = false
	viewport.add_child(burst)
	_preview_sunburst = burst

# Iter 167/171: the "sunburst" — a flat filled 12-petal star mesh (triangle
# fan, bright opaque centre → transparent petal tips). Kept on request as
# a separate aura style; not currently wired (the iter-171 electric aura
# is the active one). r = base + amp*cos(12*theta) → 12 petals.
func _make_sunburst_mesh() -> ArrayMesh:
	var verts := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var seg: int = 96
	verts.append(Vector3.ZERO)
	colors.append(Color(1.0, 0.92, 0.58, 1.0))
	for i in range(seg + 1):
		var th: float = TAU * float(i) / float(seg)
		var r: float = 0.70 + 0.32 * cos(12.0 * th)
		verts.append(Vector3(cos(th) * r, sin(th) * r, 0.0))
		colors.append(Color(1.0, 0.74, 0.30, 0.0))
	for i in range(seg):
		indices.append(0)
		indices.append(1 + i)
		indices.append(2 + i)
	var arr: Array = []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_COLOR] = colors
	arr[Mesh.ARRAY_INDEX] = indices
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return am

# Iter 171: electric aura — a faithful port of the roguelike WebGL demo's
# 12-petal Canvas-2D "ELECTRIC AURA". Each arc sweeps out and back
# (r = sin(s*PI)*pulse), curves with a per-arc whip, and the whole ring
# spins; drawn as bright-core ribbons on the additive material. Rebuilt
# every frame into the ImmediateMesh.
const AURA_PETALS: int = 12
const AURA_SEGS: int = 16
const AURA_RADIUS: float = 2.5    # scales the ~0..0.36 petal reach to world units
const AURA_HALF_WIDTH: float = 0.05

func _rebuild_electric_aura(t: float) -> void:
	var im: ImmediateMesh = _preview_aura.mesh as ImmediateMesh
	if im == null:
		return
	im.clear_surfaces()
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in AURA_PETALS:
		_emit_aura_petal(im, i, t)
	_emit_aura_orb(im, t)
	im.surface_end()

func _emit_aura_petal(im: ImmediateMesh, i: int, t: float) -> void:
	var angle_base: float = (float(i) / float(AURA_PETALS)) * TAU + t * 0.7
	var pulse: float = 0.28 + 0.08 * sin(t * 2.1 + float(i) * 1.3)
	var whip: float = sin(t * 0.6 + float(i) * 0.5)
	var hue: float = fmod(0.55 + 0.05 * sin(t * 0.5 + float(i)), 1.0)
	var core: Color = Color.from_hsv(hue, 0.45, 1.0, 0.9)
	var edge: Color = Color(core.r, core.g, core.b, 0.0)
	var pts: Array[Vector3] = []
	for k in AURA_SEGS + 1:
		var s: float = float(k) / float(AURA_SEGS)
		var r: float = sin(s * PI) * pulse * AURA_RADIUS
		var ang: float = angle_base + s * PI * 0.9 * whip
		pts.append(Vector3(cos(ang) * r, sin(ang) * r, 0.0))
	for k in AURA_SEGS:
		var p0: Vector3 = pts[k]
		var p1: Vector3 = pts[k + 1]
		var d: Vector3 = p1 - p0
		if d.length() < 0.0001:
			continue
		d = d.normalized()
		var perp: Vector3 = Vector3(-d.y, d.x, 0.0) * AURA_HALF_WIDTH
		# bright core line, transparent ribbon edges → additive glow
		_aura_tri(im, p0 + perp, edge, p0, core, p1, core)
		_aura_tri(im, p0 + perp, edge, p1, core, p1 + perp, edge)
		_aura_tri(im, p0, core, p0 - perp, edge, p1 - perp, edge)
		_aura_tri(im, p0, core, p1 - perp, edge, p1, core)

func _emit_aura_orb(im: ImmediateMesh, t: float) -> void:
	var pr: float = (0.16 + 0.05 * sin(t * 3.5)) * AURA_RADIUS
	var core: Color = Color(0.82, 0.90, 1.0, 0.95)
	var edge: Color = Color(0.30, 0.50, 1.0, 0.0)
	var rim: int = 22
	for k in rim:
		var a0: float = TAU * float(k) / float(rim)
		var a1: float = TAU * float(k + 1) / float(rim)
		_aura_tri(im, Vector3.ZERO, core,
			Vector3(cos(a0) * pr, sin(a0) * pr, 0.0), edge,
			Vector3(cos(a1) * pr, sin(a1) * pr, 0.0), edge)

func _aura_tri(im: ImmediateMesh, a: Vector3, ca: Color,
		b: Vector3, cb: Color, c: Vector3, cc: Color) -> void:
	im.surface_set_color(ca)
	im.surface_add_vertex(a)
	im.surface_set_color(cb)
	im.surface_add_vertex(b)
	im.surface_set_color(cc)
	im.surface_add_vertex(c)

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
	# Iter 167/175: show the active aura style when the preset has a halo.
	if _preview_aura != null:
		var halo: float = float(GlitzPrefs.PRESETS.get(preset, {}).get("halo_strength", 0.0))
		var show_aura: bool = halo > 0.001
		_preview_aura.visible = show_aura and _aura_is_electric
		if _preview_sunburst != null:
			_preview_sunburst.visible = show_aura and not _aura_is_electric

func _process(delta: float) -> void:
	# Iter 171: rebuild the electric aura's geometry each frame so the
	# 12 arcs spin, curve and pulse.
	if _preview_aura != null and _preview_aura.visible:
		_aura_t += delta
		_rebuild_electric_aura(_aura_t)
	# Iter 175: the sunburst aura just slowly rotates.
	if _preview_sunburst != null and _preview_sunburst.visible:
		_preview_sunburst.rotation.z += delta * 0.5

# Iter 175: AURA toggle in the speed row — switches the preview aura
# between the electric arcs and the iter-167 sunburst star.
func _build_aura_toggle() -> void:
	_aura_btn = Button.new()
	_aura_btn.custom_minimum_size = Vector2(250, 0)
	_aura_btn.add_theme_font_size_override("font_size", 24)
	_aura_btn.pressed.connect(_on_aura_toggle)
	$VBox/SpeedRow.add_child(_aura_btn)
	_refresh_aura_btn()

func _on_aura_toggle() -> void:
	_aura_is_electric = not _aura_is_electric
	if get_node_or_null("/root/AudioBus"):
		AudioBus.play_tap()
	_refresh_aura_btn()
	_apply_current_selection()

func _refresh_aura_btn() -> void:
	if _aura_btn != null:
		_aura_btn.text = "AURA: ELECTRIC" if _aura_is_electric else "AURA: SUNBURST"

func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/debug_menu.tscn")
