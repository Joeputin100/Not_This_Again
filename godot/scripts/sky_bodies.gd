extends Node3D
class_name SkyBodies

const SKY_DISTANCE := 50.0
const PARALLAX_FACTOR := 0.15

@onready var sun_disc: Node3D = $SunDisc
@onready var sun_stick: Node3D = $SunStick
@onready var moon_disc: Node3D = $MoonDisc

var _camera: Camera3D = null

func bind_camera(camera: Camera3D) -> void:
	_camera = camera

func apply_preset(preset: Dictionary, shadow_offset: Vector3) -> void:
	var horiz := Vector2(-shadow_offset.x, -shadow_offset.z)
	if horiz.length_squared() < 0.0001:
		horiz = Vector2(0, -1)
	horiz = horiz.normalized() * SKY_DISTANCE
	var sun_visible: bool = preset.get("sun_visible", true)
	sun_disc.visible = sun_visible
	sun_stick.visible = sun_visible
	if sun_visible:
		var sun_h: float = preset["sun_height"]
		sun_disc.position = Vector3(horiz.x, sun_h, horiz.y)
		var stick_mesh: QuadMesh = sun_stick.get_node("StickMesh").mesh
		stick_mesh.size = Vector2(0.6, sun_h)
		sun_stick.position = Vector3(horiz.x, sun_h * 0.5, horiz.y)
		_push_sun_uniforms(preset)
	var moon_visible: bool = preset.get("moon_visible", false)
	moon_disc.visible = moon_visible
	if moon_visible:
		var moon_h: float = preset["moon_height"]
		moon_disc.position = Vector3(horiz.x, moon_h, horiz.y)
		_push_moon_uniforms(preset)

func _push_sun_uniforms(preset: Dictionary) -> void:
	var mat: ShaderMaterial = sun_disc.get_node("DiscMesh").material_override
	if mat == null:
		return
	if preset.has("sun_swirl_a"):
		mat.set_shader_parameter("swirl_color_a", preset["sun_swirl_a"])
	if preset.has("sun_swirl_b"):
		mat.set_shader_parameter("swirl_color_b", preset["sun_swirl_b"])

func _push_moon_uniforms(preset: Dictionary) -> void:
	var mat: ShaderMaterial = moon_disc.get_node("DiscMesh").material_override
	if mat == null:
		return
	if preset.has("moon_bite_depth"):
		mat.set_shader_parameter("bite_depth", preset["moon_bite_depth"])

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
	var is_touch := event is InputEventScreenTouch and event.pressed
	var is_click := event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT
	if not (is_touch or is_click):
		return
	var variant := _pick_variant(body_key)
	var sfx_player: AudioStreamPlayer3D = body.get_node_or_null("TapSfx/%s" % variant)
	if sfx_player:
		sfx_player.play()
	if body_key == "sun":
		match variant:
			"A": _anim_scale_pulse(body)
			"B": _anim_sun_spin(body)
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

func _anim_sun_spin(body: Node3D) -> void:
	_kill_prev_tween(body)
	var mat: ShaderMaterial = body.get_node("DiscMesh").material_override
	if mat == null:
		return
	mat.set_shader_parameter("spin_boost", 1.0)
	var t := create_tween()
	t.tween_method(func(v): mat.set_shader_parameter("spin_boost", v), 1.0, 4.0, 0.12)\
	 .set_ease(Tween.EASE_OUT)
	t.tween_method(func(v): mat.set_shader_parameter("spin_boost", v), 4.0, 1.0, 0.28)\
	 .set_ease(Tween.EASE_IN)
	body.set_meta("bounce_tween", t)

func _anim_moon_wink(body: Node3D) -> void:
	_kill_prev_tween(body)
	var mat: ShaderMaterial = body.get_node("DiscMesh").material_override
	if mat == null:
		return
	mat.set_shader_parameter("wink_override", 0.0)
	var t := create_tween()
	t.tween_method(func(v): mat.set_shader_parameter("wink_override", v), 0.0, 1.0, 0.10)\
	 .set_ease(Tween.EASE_OUT)
	t.tween_method(func(v): mat.set_shader_parameter("wink_override", v), 1.0, 0.0, 0.15)\
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
