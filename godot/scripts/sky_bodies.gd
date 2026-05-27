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
