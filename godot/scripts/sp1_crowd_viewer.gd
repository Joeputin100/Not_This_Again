extends Node2D

# SP1 debug crowd viewer. Node2D + SubViewport because the project's main
# window uses canvas_items stretch mode — pure-Node3D scenes don't activate
# their cameras under it (same reason terrain_3d uses the SubViewport
# pattern). 3D content lives inside ViewportContainer/Viewport3D; the UI
# (slider, d-pad, perf readout) sits in a CanvasLayer above.

const FlipbookCrowd = preload("res://scripts/flipbook_crowd.gd")

# Every clip belonging to each character — drives the OptionButton and
# the FlipbookCrowd.configure() call.
const CHARACTERS := {
	"cowboy": [
		"cowboy_idle_a", "cowboy_idle_b", "cowboy_idle_c",
		"cowboy_celebrate_a", "cowboy_celebrate_b", "cowboy_celebrate_c",
		"cowboy_run_shoot_fwd", "cowboy_run_shoot_left",
		"cowboy_run_shoot_right", "cowboy_strafe_left",
		"cowboy_strafe_right", "cowboy_stand_shoot",
	],
	"pete": [
		"pete_celebrate", "pete_complains", "pete_death",
		"pete_hit_by_gunfire", "pete_shoots_at_player", "pete_shouts",
		"pete_steps_forward", "pete_strafe_right_to_left",
		"pete_taps_foot_idle",
	],
	"vagrant": [
		"vagrant_death", "vagrant_drunk_walk", "vagrant_idle_wobble",
		"vagrant_shoot_down", "vagrant_shoot_left", "vagrant_shoot_right",
		"vagrant_strafe_left", "vagrant_strafe_right",
	],
	"prospector": [
		"prospector_death", "prospector_idle_drinking",
		"prospector_reacts_to_gunshot", "prospector_steps_forward",
		"prospector_strafe_left", "prospector_strafe_right",
	],
	"pusher": [
		"pusher_melee", "pusher_run_forward",
		"pusher_push_left_a", "pusher_push_left_b", "pusher_push_left_c",
		"pusher_push_right_a", "pusher_push_right_b", "pusher_push_right_c",
	],
	"chicken": [
		"chicken_rir_flap", "chicken_rir_scramble", "chicken_rir_tumble",
		"chicken_leghorn_flap", "chicken_leghorn_scramble",
		"chicken_leghorn_tumble", "chicken_silkie_flap",
		"chicken_silkie_scramble", "chicken_silkie_tumble",
	],
	"humbug": ["humbug_tip", "humbug_thought", "humbug_canard"],
}

# Per-character directional walk clips. When the d-pad is pressed, ALL
# members switch to the matching direction's clip so the crowd visibly
# walks in that direction — without this, the translation alone is hard
# to read against a uniform grass plane. "idle" means d-pad released
# (members get their original spawn clip back for variety).
const DIRECTIONS := {
	"cowboy": {
		"fwd":   "cowboy_run_shoot_fwd",
		"left":  "cowboy_strafe_left",
		"right": "cowboy_strafe_right",
		"back":  "cowboy_run_shoot_fwd",
	},
	"pete": {
		"fwd":   "pete_steps_forward",
		"left":  "pete_strafe_right_to_left",
		"right": "pete_strafe_right_to_left",
		"back":  "pete_steps_forward",
	},
	"vagrant": {
		"fwd":   "vagrant_drunk_walk",
		"left":  "vagrant_strafe_left",
		"right": "vagrant_strafe_right",
		"back":  "vagrant_drunk_walk",
	},
	"prospector": {
		"fwd":   "prospector_steps_forward",
		"left":  "prospector_strafe_left",
		"right": "prospector_strafe_right",
		"back":  "prospector_steps_forward",
	},
	"pusher": {
		"fwd":   "pusher_run_forward",
		"left":  "pusher_push_left_a",
		"right": "pusher_push_right_a",
		"back":  "pusher_run_forward",
	},
	"chicken": {
		# Chickens are in-place panickers; "directional walk" doesn't really
		# apply. d-pad press just intensifies the panic (scramble) but keeps
		# whatever breed each member was spawned with — _apply_direction_to_crowd
		# treats missing direction keys as "stay on initial clip", and idle
		# returns to spawn-variety. This entry is kept empty intentionally so
		# the d-pad doesn't cause breeds to swap on the crowd.
	},
	"humbug": {
		"fwd":   "humbug_tip",
		"left":  "humbug_thought",
		"right": "humbug_canard",
		"back":  "humbug_tip",
	},
}

const MOVE_SPEED := 4.0
const SPAWN_RADIUS := 5.0
const GRASS_HALF := 25.0    # crowd clamp bound — keeps members on the visible grass

# Per-character world-y offset to put feet at ground level. Each character's
# figure occupies a different vertical fraction of its 9:16 cell — the value
# below is that fraction (which is also the position.y needed because the
# figure is vertically centred in the cell and the quad is 2.0 tall, so
# feet land at world y = position.y - height_ratio = 0 when position.y =
# height_ratio). Numbers from the figure-bbox scan in `tools/build_atlas.py`
# notes.
const CHARACTER_FOOT_Y := {
	"cowboy":     0.52,
	"pete":       0.57,
	"vagrant":    0.57,
	"prospector": 0.57,
	"pusher":     0.75,
	"chicken":    0.43,
	"humbug":     0.93,
}

# Lighting presets — drive KeyLight + WorldEnvironment to fake different
# times of day. Each preset's shadow direction is the same (the light
# transform is fixed; we vary colour/energy + ambient/background). For
# proper "low sun = long shadows" we'd vary the light's pitch too, which
# would be a future iteration.
const LIGHTING_PRESETS := {
	"daylight": {
		"light_color":   Color(1.00, 0.96, 0.82, 1),
		"light_energy":  1.2,
		"ambient_color": Color(0.78, 0.82, 0.92, 1),
		"ambient_energy": 0.3,
		"bg_color":      Color(0.42, 0.62, 0.85, 1),
		"shadow_offset": Vector3(0.05, 0.0, 0.10),
		"shadow_color":  Color(0.00, 0.00, 0.02, 0.75),
		"shadow_scale":  1.0,
		"sun_visible":   true,
		"sun_height":    18.0,
		"sun_swirl_a":   Color(0.96, 0.78, 0.42, 1),
		"sun_swirl_b":   Color(0.90, 0.64, 0.23, 1),
		"moon_visible":  false,
	},
	"sunset": {
		"light_color":   Color(1.00, 0.55, 0.30, 1),
		"light_energy":  1.5,
		"ambient_color": Color(0.92, 0.55, 0.45, 1),
		"ambient_energy": 0.4,
		"bg_color":      Color(0.92, 0.55, 0.30, 1),
		"shadow_offset": Vector3(0.60, 0.0, 1.50),
		"shadow_color":  Color(0.18, 0.05, 0.02, 0.55),
		"shadow_scale":  1.3,
		"sun_visible":   true,
		"sun_height":    7.0,
		"sun_swirl_a":   Color(0.95, 0.42, 0.18, 1),
		"sun_swirl_b":   Color(0.72, 0.24, 0.10, 1),
		"moon_visible":  false,
	},
	"moonlight": {
		"light_color":   Color(0.60, 0.72, 1.00, 1),
		"light_energy":  0.55,
		"ambient_color": Color(0.18, 0.24, 0.48, 1),
		"ambient_energy": 0.20,
		"bg_color":      Color(0.06, 0.09, 0.22, 1),
		"shadow_offset": Vector3(0.04, 0.0, 0.08),
		"shadow_color":  Color(0.02, 0.04, 0.10, 0.35),
		"shadow_scale":  0.85,
		"sun_visible":   false,
		"moon_visible":  true,
		"moon_height":   16.0,
		"moon_bite_depth": 0.4,
	},
	"overcast": {
		"light_color":   Color(0.92, 0.94, 0.95, 1),
		"light_energy":  0.6,
		"ambient_color": Color(0.86, 0.88, 0.92, 1),
		"ambient_energy": 0.7,
		"bg_color":      Color(0.78, 0.80, 0.82, 1),
		"shadow_offset": Vector3(0.0, 0.0, 0.0),
		"shadow_color":  Color(0.06, 0.06, 0.08, 0.40),
		"shadow_scale":  0.80,
		"sun_visible":   true,
		"sun_height":    14.0,
		"sun_swirl_a":   Color(0.91, 0.79, 0.61, 1),
		"sun_swirl_b":   Color(0.72, 0.60, 0.43, 1),
		"moon_visible":  false,
	},
}

# Milling drift — applied to every crowd MultiMesh's flipbook material at
# spawn time. mill_amp=0 disables (stationary crowd); 0.3 is a soft
# "shifting weight" idle.
const CROWD_MILL_AMP := 0.30
const CROWD_MILL_FREQ := 0.35

# Grass field: MultiMesh of billboarded grass-tuft sprites, expanded to a
# full field per the roguelike webgl demo. Tufts share one draw call via
# MultiMesh; per-instance time offset (custom-data .r) breaks up the
# unison sway.
const GRASS_FIELD_SHADER := preload("res://shaders/grass_field.gdshader")
const GRASS_TUFT_TEX_PATH := "res://assets/sprites/props/grass_tuft.png"
const GRASS_TUFT_COUNT := 800
const GRASS_TUFT_HEIGHT := 0.7
const GRASS_TUFT_WIDTH := 1.28   # 1408x768 sprite, anchored at ~9:5 aspect

var _crowd: Node3D = null
var _character := "cowboy"
var _target_count := 20
var _ids: Array[int] = []
var _member_initial_clip := {}   # id -> the variety clip the member spawned with
var _direction := "idle"
var _move := Vector3.ZERO

@onready var viewport_3d: SubViewport = $ViewportContainer/Viewport3D
@onready var camera_3d: Camera3D = $ViewportContainer/Viewport3D/Camera3D
@onready var key_light: DirectionalLight3D = $ViewportContainer/Viewport3D/KeyLight
@onready var world_env: WorldEnvironment = $ViewportContainer/Viewport3D/WorldEnvironment
@onready var slider: HSlider = $UI/Panel/VBox/CountSlider
@onready var count_label: Label = $UI/Panel/VBox/CountLabel
@onready var char_select: OptionButton = $UI/Panel/VBox/CharSelect
@onready var light_select: OptionButton = $UI/Panel/VBox/LightSelect
@onready var size_slider: HSlider = $UI/Panel/VBox/SizeSlider
@onready var size_label: Label = $UI/Panel/VBox/SizeLabel
@onready var tilt_slider: HSlider = $UI/Panel/VBox/TiltSlider
@onready var tilt_label: Label = $UI/Panel/VBox/TiltLabel
@onready var perf: Label = $UI/Perf
@onready var back_button: Button = $UI/BackButton
@onready var dpad_up: Button = $UI/Panel/VBox/DPad/Up
@onready var dpad_down: Button = $UI/Panel/VBox/DPad/Down
@onready var dpad_left: Button = $UI/Panel/VBox/DPad/Left
@onready var dpad_right: Button = $UI/Panel/VBox/DPad/Right

func _ready() -> void:
	DebugLog.add("sp1_crowd_viewer: _ready start")
	get_tree().set_quit_on_go_back(false)
	if get_window():
		get_window().go_back_requested.connect(_on_back_pressed)
	if viewport_3d == null:
		DebugLog.add("sp1_crowd_viewer: FATAL viewport_3d missing — abort")
		return
	DebugLog.add("sp1_crowd_viewer: viewport %s" % str(viewport_3d.size))
	if camera_3d == null:
		DebugLog.add("sp1_crowd_viewer: WARN camera_3d null")
	var sky := $ViewportContainer/Viewport3D/Sky
	if sky and camera_3d:
		sky.bind_camera(camera_3d)
	if back_button:
		back_button.pressed.connect(_on_back_pressed)
	if char_select == null or slider == null:
		DebugLog.add("sp1_crowd_viewer: WARN UI missing — char_select=%s slider=%s" % [
			char_select, slider])
	else:
		_populate_character_options()
		_populate_lighting_options()
		slider.value_changed.connect(_on_slider_changed)
		char_select.item_selected.connect(_on_character_selected)
		if light_select:
			light_select.item_selected.connect(_on_lighting_selected)
			_apply_lighting_preset("daylight")
		if size_slider:
			size_slider.value_changed.connect(_on_size_changed)
		if tilt_slider:
			tilt_slider.value_changed.connect(_on_tilt_changed)
			_on_tilt_changed(tilt_slider.value)
	# d-pad inputs are polled in _process (see _update_direction) so we
	# can handle the case where the user releases one button while another
	# is still held — signal-only connects don't track multi-button state.
	_spawn_grass_field()
	DebugLog.add("sp1_crowd_viewer: building crowd for %s" % _character)
	_build_crowd(_character)
	DebugLog.add("sp1_crowd_viewer: crowd built, adding %d members" % _target_count)
	_set_count(_target_count)
	if count_label:
		_update_count_label()
	DebugLog.add("sp1_crowd_viewer: _ready done")

func _populate_character_options() -> void:
	char_select.clear()
	for c in CHARACTERS.keys():
		char_select.add_item(c)
	char_select.selected = 0

func _populate_lighting_options() -> void:
	if light_select == null:
		return
	light_select.clear()
	for k in LIGHTING_PRESETS.keys():
		light_select.add_item(k)
	light_select.selected = 0  # daylight

func _on_lighting_selected(idx: int) -> void:
	var keys: Array = LIGHTING_PRESETS.keys()
	_apply_lighting_preset(keys[idx])

func _apply_lighting_preset(name: String) -> void:
	var p: Dictionary = LIGHTING_PRESETS.get(name, {})
	if p.is_empty():
		return
	if key_light:
		key_light.light_color = p["light_color"]
		key_light.light_energy = p["light_energy"]
	if world_env and world_env.environment:
		var env: Environment = world_env.environment
		env.ambient_light_color = p["ambient_color"]
		env.ambient_light_energy = p["ambient_energy"]
		env.background_color = p["bg_color"]
	# Drive blob shadows: offset + colour + scale change per preset so the
	# "sun angle" reads visually (long warm shadows at sunset, faint cool
	# in moonlight, tiny ambient-style in overcast). FlipbookCrowd handles
	# the MultiMesh update.
	if _crowd and _crowd.has_method("set_shadow_params"):
		_crowd.set_shadow_params(p["shadow_offset"], p["shadow_color"], p["shadow_scale"])
	# Keep the OptionButton's visible label in sync if this was invoked from
	# code (not the dropdown signal).
	if light_select:
		var i := 0
		for k in LIGHTING_PRESETS.keys():
			if k == name:
				light_select.selected = i
				break
			i += 1
	var sky := $ViewportContainer/Viewport3D/Sky
	if sky and sky.has_method("apply_preset"):
		sky.apply_preset(p, p["shadow_offset"])
	DebugLog.add("sp1_crowd_viewer: lighting preset = %s" % name)

func _on_character_selected(idx: int) -> void:
	var keys: Array = CHARACTERS.keys()
	var name: String = keys[idx]
	if name == _character:
		return
	_character = name
	_direction = "idle"
	_move = Vector3.ZERO
	_build_crowd(_character)
	_set_count(_target_count)

func _on_slider_changed(val: float) -> void:
	_target_count = int(val)
	_update_count_label()
	_set_count(_target_count)

func _on_tilt_changed(degrees: float) -> void:
	if camera_3d == null:
		return
	var pitch_rad := deg_to_rad(degrees)
	camera_3d.rotation.x = pitch_rad
	if tilt_label:
		tilt_label.text = "Camera tilt: %d°" % int(degrees)

func _on_size_changed(val: float) -> void:
	# Scaling the whole crowd Node3D is the cheapest way to upsize every
	# member's quad uniformly — also scales the blob-shadows because they
	# live under the same parent. Slider range 0.5..5.0; 1.0 = the spawn
	# size set in flipbook_crowd.gd.
	if _crowd:
		_crowd.scale = Vector3(val, val, val)
	if size_label:
		size_label.text = "Character size: %.1f×" % val

func _update_count_label() -> void:
	count_label.text = "Crowd size: %d" % _target_count

func _spawn_grass_field() -> void:
	# Build a MultiMesh of GRASS_TUFT_COUNT billboarded tufts spread across
	# the visible grass plane. Each instance picks a random XZ position,
	# Y-translates so the quad's bottom sits at ground level, gets a small
	# scale variation, and carries a random sway phase in custom_data.r.
	var tex: Texture2D = load(GRASS_TUFT_TEX_PATH)
	if tex == null:
		DebugLog.add("sp1_crowd_viewer: WARN grass_tuft.png missing — skipping field")
		return
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "GrassField"
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	var quad := QuadMesh.new()
	quad.size = Vector2(GRASS_TUFT_WIDTH, GRASS_TUFT_HEIGHT)
	mm.mesh = quad
	var mat := ShaderMaterial.new()
	mat.shader = GRASS_FIELD_SHADER
	mat.set_shader_parameter("albedo_tex", tex)
	mat.set_shader_parameter("mesh_height", GRASS_TUFT_HEIGHT)
	mat.set_shader_parameter("alpha_cutoff", 0.30)
	mat.set_shader_parameter("sway_amp", 0.13)
	mat.set_shader_parameter("sway_freq", 1.5)
	mat.set_shader_parameter("bob_amp", 0.020)
	mat.set_shader_parameter("bob_freq", 2.2)
	# Default render_priority (0) — crowd's flipbook material is +10 so the
	# alpha-blend sort always puts crowd members above grass tufts.
	mmi.material_override = mat
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	viewport_3d.add_child(mmi)
	mm.instance_count = GRASS_TUFT_COUNT
	# Parallel MultiMesh of small blob-shadows under each tuft. Re-uses the
	# crowd_shadow.gdshader; instance positions match the tuft XZ positions.
	var sh_mmi := MultiMeshInstance3D.new()
	sh_mmi.name = "GrassShadows"
	var sh_mm := MultiMesh.new()
	sh_mm.transform_format = MultiMesh.TRANSFORM_3D
	var sh_plane := PlaneMesh.new()
	sh_plane.size = Vector2(0.65, 0.45)  # smaller blob per tuft
	sh_mm.mesh = sh_plane
	sh_mmi.multimesh = sh_mm
	var sh_mat := ShaderMaterial.new()
	sh_mat.shader = preload("res://shaders/crowd_shadow.gdshader")
	sh_mat.set_shader_parameter("shadow_color", Color(0.0, 0.0, 0.02, 0.55))
	sh_mat.set_shader_parameter("softness", 0.55)
	sh_mat.render_priority = -5   # under everything else (behind crowd's +10)
	sh_mmi.material_override = sh_mat
	sh_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	viewport_3d.add_child(sh_mmi)
	sh_mm.instance_count = GRASS_TUFT_COUNT

	for i in GRASS_TUFT_COUNT:
		var pos := Vector3(
			randf_range(-GRASS_HALF, GRASS_HALF), GRASS_TUFT_HEIGHT * 0.5,
			randf_range(-GRASS_HALF, GRASS_HALF))
		var s: float = randf_range(0.75, 1.35)
		var xform := Transform3D(Basis().scaled(Vector3(s, s, s)), pos)
		mm.set_instance_transform(i, xform)
		# r = sway phase 0..1 (shader maps to 0..2π).
		mm.set_instance_custom_data(i, Color(randf(), 0.0, 0.0, 0.0))
		# Matching shadow: same XZ, scaled to the tuft size, slightly offset
		# to suggest sun direction (consistent with the crowd's default).
		var sh_pos := Vector3(pos.x + 0.05, 0.01, pos.z + 0.10)
		var sh_xform := Transform3D(Basis().scaled(Vector3(s, 1.0, s)), sh_pos)
		sh_mm.set_instance_transform(i, sh_xform)
	DebugLog.add("sp1_crowd_viewer: spawned %d grass tufts (+ shadows)" % GRASS_TUFT_COUNT)


func _build_crowd(character: String) -> void:
	if _crowd:
		_crowd.queue_free()
		_crowd = null
	_ids.clear()
	_member_initial_clip.clear()
	_crowd = FlipbookCrowd.new()
	_crowd.name = "Crowd"
	# Crowd must live inside the SubViewport so its MeshInstances see the
	# Camera3D + lights set up there. Adding to self (Node2D) would put
	# it in 2D space where the 3D shader never runs.
	viewport_3d.add_child(_crowd)
	_crowd.configure(character, CHARACTERS[character])
	# Enable shader-side milling on every clip's MultiMesh material so the
	# crowd jostles around its spawn positions when idle.
	for child in _crowd.get_children():
		if child is MultiMeshInstance3D and child.material_override is ShaderMaterial:
			var mat: ShaderMaterial = child.material_override
			mat.set_shader_parameter("mill_amp", CROWD_MILL_AMP)
			mat.set_shader_parameter("mill_freq", CROWD_MILL_FREQ)

func _set_count(n: int) -> void:
	var clips: Array = CHARACTERS[_character]
	while _ids.size() < n:
		var clip: String = clips[_ids.size() % clips.size()]
		var foot_y: float = CHARACTER_FOOT_Y.get(_character, 0.57)
		var x := Transform3D(Basis(), Vector3(
			randf_range(-SPAWN_RADIUS, SPAWN_RADIUS), foot_y,
			randf_range(-SPAWN_RADIUS, SPAWN_RADIUS)))
		var id: int = _crowd.add_member(clip, x)
		_ids.append(id)
		_member_initial_clip[id] = clip
	while _ids.size() > n:
		var id: int = _ids.pop_back()
		_member_initial_clip.erase(id)
		_crowd.remove_member(id)

func _update_direction() -> void:
	# Poll d-pad buttons. First button checked in priority order wins —
	# pressing two buttons at once picks the first listed.
	var new_dir := "idle"
	var move := Vector3.ZERO
	if dpad_up and dpad_up.button_pressed:
		new_dir = "fwd"
		move.z = -MOVE_SPEED
	elif dpad_down and dpad_down.button_pressed:
		new_dir = "back"
		move.z = MOVE_SPEED
	elif dpad_left and dpad_left.button_pressed:
		new_dir = "left"
		move.x = -MOVE_SPEED
	elif dpad_right and dpad_right.button_pressed:
		new_dir = "right"
		move.x = MOVE_SPEED
	_move = move
	if new_dir != _direction:
		_direction = new_dir
		_apply_direction_to_crowd()

func _apply_direction_to_crowd() -> void:
	# When a direction is held, ALL members switch to that direction's
	# walk clip. When released ("idle"), members go back to the variety
	# clip they spawned with — so you see the full animation set again.
	if _crowd == null:
		return
	var dir_map: Dictionary = DIRECTIONS.get(_character, {})
	for id in _ids:
		var clip: String
		if _direction == "idle":
			clip = _member_initial_clip.get(id, "")
		else:
			clip = dir_map.get(_direction, "")
		if clip != "":
			_crowd.set_member_clip(id, clip)

func _process(dt: float) -> void:
	_update_direction()
	if _crowd and _move.length_squared() > 0.0:
		var new_pos: Vector3 = _crowd.position + _move * dt
		# Clamp to grass bounds so the crowd doesn't walk into the void.
		new_pos.x = clampf(new_pos.x, -GRASS_HALF, GRASS_HALF)
		new_pos.z = clampf(new_pos.z, -GRASS_HALF, GRASS_HALF)
		_crowd.position = new_pos
	if perf:
		perf.text = "FPS %d  draws %d  VRAM %.0f MB  dir %s" % [
			Engine.get_frames_per_second(),
			RenderingServer.get_rendering_info(
				RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
			RenderingServer.get_rendering_info(
				RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED) / 1048576.0,
			_direction]

func _on_back_pressed() -> void:
	if get_node_or_null("/root/AudioBus"):
		AudioBus.play_tap()
	get_tree().change_scene_to_file("res://scenes/debug_menu.tscn")
