extends Node3D
class_name SkyBodies

const SKY_DISTANCE := 50.0
const PARALLAX_FACTOR := 0.15
const SUN_TEXTURES := {
	"daylight": preload("res://assets/sprites/sky/sun_daylight.png"),
	"sunset":   preload("res://assets/sprites/sky/sun_sunset.png"),
	"overcast": preload("res://assets/sprites/sky/sun_overcast.png"),
}
const MOON_TEX_NORMAL := preload("res://assets/sprites/sky/moon_normal.png")
const MOON_TEX_WINK := preload("res://assets/sprites/sky/moon_wink.png")

@onready var sun_disc: Node3D = $SunDisc
@onready var sun_stick: Node3D = $SunStick
@onready var moon_disc: Node3D = $MoonDisc

var _camera: Camera3D = null

func bind_camera(camera: Camera3D) -> void:
	_camera = camera

func apply_preset(preset: Dictionary, shadow_offset: Vector3) -> void:
	var raw_angle: float = 0.0
	if absf(shadow_offset.x) + absf(shadow_offset.z) > 0.0001:
		raw_angle = atan2(-shadow_offset.x, -shadow_offset.z)
	var lat_angle: float = clampf(raw_angle, -PI / 36.0, PI / 36.0)
	var horiz := Vector2(sin(lat_angle), -cos(lat_angle)) * SKY_DISTANCE

	var sun_visible: bool = preset.get("sun_visible", true)
	sun_disc.visible = sun_visible
	sun_stick.visible = sun_visible
	if sun_visible:
		var sun_h: float = preset["sun_height"]
		sun_disc.position = Vector3(horiz.x, sun_h, horiz.y)
		# Stick runs from the disc bottom DOWN past the horizon line. At
		# SKY_DISTANCE (50m) the terrain plane has ended, so y=0 there is the
		# visible horizon; extending the stick well below 0 makes it plunge
		# convincingly toward/behind the horizon instead of stopping mid-air.
		var stick_bottom := -40.0
		var stick_height: float = sun_h - stick_bottom
		var stick_mesh: QuadMesh = sun_stick.get_node("StickMesh").mesh
		stick_mesh.size = Vector2(0.6, stick_height)
		sun_stick.position = Vector3(horiz.x, (sun_h + stick_bottom) * 0.5, horiz.y)
		_push_sun_uniforms(preset)

	var moon_visible: bool = preset.get("moon_visible", false)
	moon_disc.visible = moon_visible
	if moon_visible:
		var moon_h: float = preset["moon_height"]
		moon_disc.position = Vector3(horiz.x, moon_h, horiz.y)
		_push_moon_uniforms(preset)

func _push_sun_uniforms(preset: Dictionary) -> void:
	var mat: ShaderMaterial = sun_disc.get_node("DiscMesh").material_override
	if mat:
		var tex_key: String = preset.get("sun_tex", "daylight")
		if SUN_TEXTURES.has(tex_key):
			mat.set_shader_parameter("albedo_tex", SUN_TEXTURES[tex_key])
		if preset.has("sun_tint"):
			mat.set_shader_parameter("tint", preset["sun_tint"])
	# Animated star corona behind the disc.
	var corona: ShaderMaterial = sun_disc.get_node("Corona").material_override
	if corona:
		corona.set_shader_parameter("burst", 0.0)
		if preset.has("sun_corona_intensity"):
			corona.set_shader_parameter("intensity", preset["sun_corona_intensity"])
		if preset.has("sun_corona_body"):
			corona.set_shader_parameter("body_color", preset["sun_corona_body"])
		if preset.has("sun_corona_ray"):
			corona.set_shader_parameter("ray_color", preset["sun_corona_ray"])

func _push_moon_uniforms(preset: Dictionary) -> void:
	var mat: ShaderMaterial = moon_disc.get_node("DiscMesh").material_override
	if mat == null:
		return
	mat.set_shader_parameter("albedo_tex", MOON_TEX_NORMAL)
	mat.set_shader_parameter("wink_tex", MOON_TEX_WINK)
	if preset.has("moon_tint"):
		mat.set_shader_parameter("tint", preset["moon_tint"])
	if preset.has("moon_corona_color"):
		mat.set_shader_parameter("corona_color", preset["moon_corona_color"])
	if preset.has("moon_corona_strength"):
		mat.set_shader_parameter("corona_strength", preset["moon_corona_strength"])

func _process(_dt: float) -> void:
	if _camera == null:
		return
	global_position = _camera.global_position * (1.0 - PARALLAX_FACTOR)
	if sun_disc.visible:
		sun_disc.look_at(_camera.global_position, Vector3.UP, true)
	if moon_disc.visible:
		moon_disc.look_at(_camera.global_position, Vector3.UP, true)
	if sun_stick.visible:
		var to_cam := _camera.global_position - sun_stick.global_position
		sun_stick.rotation.y = atan2(to_cam.x, to_cam.z)

const VARIANTS := ["A", "B", "C"]
var _last_variant := {"sun": "", "moon": ""}

func _ready() -> void:
	var pairs := [["sun", sun_disc], ["moon", moon_disc]]
	for pair in pairs:
		var body_key: String = pair[0]
		var body: Node3D = pair[1]
		var area: Area3D = body.get_node_or_null("TapArea")
		if area:
			area.input_event.connect(_on_body_tapped.bind(body_key, body))

func _pick_variant(body_key: String) -> String:
	var pool := VARIANTS.filter(func(v): return v != _last_variant[body_key])
	var chosen: String = pool[randi() % pool.size()]
	_last_variant[body_key] = chosen
	return chosen

func _on_body_tapped(_camera: Node, event: InputEvent, _pos: Vector3,
					_normal: Vector3, _shape_idx: int,
					body_key: String, body: Node3D) -> void:
	var is_touch: bool = event is InputEventScreenTouch and event.pressed
	var is_click: bool = event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT
	if not (is_touch or is_click):
		return
	var variant := _pick_variant(body_key)
	var sfx_player: AudioStreamPlayer3D = body.get_node_or_null("TapSfx/%s" % variant)
	if sfx_player:
		sfx_player.play()
	if body_key == "sun":
		match variant:
			"A": _anim_scale_pulse(body)
			"B": _anim_sun_corona_burst(body)
			"C": _anim_z_wobble(body, 0.26, 0.6)
	else:
		match variant:
			"A": _anim_scale_pulse(body)
			"B": _anim_moon_wink(body)
			"C": _anim_z_wobble(body, 0.14, 0.5)

func _kill_prev_tween(body: Node3D) -> void:
	if body.has_meta("bounce_tween"):
		var prev: Tween = body.get_meta("bounce_tween")
		if prev and prev.is_valid():
			prev.kill()

func _anim_scale_pulse(body: Node3D) -> void:
	_kill_prev_tween(body)
	body.scale = Vector3.ONE
	var t := create_tween()
	t.set_trans(Tween.TRANS_BACK)
	t.tween_property(body, "scale", Vector3.ONE * 1.15, 0.08).set_ease(Tween.EASE_OUT)
	t.tween_property(body, "scale", Vector3.ONE * 0.97, 0.14).set_ease(Tween.EASE_IN_OUT)
	t.tween_property(body, "scale", Vector3.ONE, 0.08).set_ease(Tween.EASE_OUT)
	body.set_meta("bounce_tween", t)

func _anim_sun_corona_burst(body: Node3D) -> void:
	_kill_prev_tween(body)
	var mat: ShaderMaterial = body.get_node("Corona").material_override
	if mat == null:
		return
	mat.set_shader_parameter("burst", 0.0)
	var t := create_tween()
	t.tween_method(func(v): mat.set_shader_parameter("burst", v), 0.0, 1.5, 0.10)\
	 .set_ease(Tween.EASE_OUT)
	t.tween_method(func(v): mat.set_shader_parameter("burst", v), 1.5, 0.0, 0.40)\
	 .set_ease(Tween.EASE_IN)
	body.set_meta("bounce_tween", t)

func _anim_moon_wink(body: Node3D) -> void:
	_kill_prev_tween(body)
	var mat: ShaderMaterial = body.get_node("DiscMesh").material_override
	if mat == null:
		return
	mat.set_shader_parameter("wink_progress", 0.0)
	var t := create_tween()
	t.tween_method(func(v): mat.set_shader_parameter("wink_progress", v), 0.0, 1.0, 0.08)\
	 .set_ease(Tween.EASE_OUT)
	t.tween_interval(0.15)
	t.tween_method(func(v): mat.set_shader_parameter("wink_progress", v), 1.0, 0.0, 0.12)\
	 .set_ease(Tween.EASE_IN)
	body.set_meta("bounce_tween", t)

func _anim_z_wobble(body: Node3D, peak_rad: float, total_sec: float) -> void:
	_kill_prev_tween(body)
	body.rotation.z = 0.0
	var t := create_tween()
	t.tween_property(body, "rotation:z", peak_rad, total_sec * 0.25).set_ease(Tween.EASE_OUT)
	t.tween_property(body, "rotation:z", -peak_rad, total_sec * 0.30).set_ease(Tween.EASE_IN_OUT)
	t.tween_property(body, "rotation:z", peak_rad * 0.4, total_sec * 0.22).set_ease(Tween.EASE_IN_OUT)
	t.tween_property(body, "rotation:z", 0.0, total_sec * 0.23).set_ease(Tween.EASE_IN)
	body.set_meta("bounce_tween", t)
