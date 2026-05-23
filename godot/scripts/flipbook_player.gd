extends MeshInstance3D

# Single-character flipbook (Pete, Humbug). One quad, one flipbook material;
# set_clip() swaps the atlas + resets the animation clock. For crowd renders
# (cowboy, chicken, etc.) use FlipbookCrowd's MultiMesh path instead.

const ATLAS_DIR := "res://assets/sprites/atlases/"
const FLIPBOOK_SHADER := preload("res://shaders/flipbook.gdshader")

var _clip := ""

func _ready() -> void:
	if mesh == null:
		var q := QuadMesh.new()
		# 9:16 to match the SP1 source-clip aspect (Veo 720x1280).
		# 2 m tall character; width follows the 9:16 ratio.
		q.size = Vector2(1.125, 2.0)
		mesh = q
	if get_active_material(0) == null:
		var m := ShaderMaterial.new()
		m.shader = FLIPBOOK_SHADER
		set_surface_override_material(0, m)

func set_clip(clip_name: String) -> void:
	if clip_name == _clip:
		return
	_clip = clip_name
	# _ready() may not have run yet if set_clip is called pre-tree-entry;
	# make sure the mesh + material exist before we touch them.
	if mesh == null:
		var q := QuadMesh.new()
		# 9:16 to match the SP1 source-clip aspect (Veo 720x1280).
		# 2 m tall character; width follows the 9:16 ratio.
		q.size = Vector2(1.125, 2.0)
		mesh = q
	if get_active_material(0) == null:
		var m := ShaderMaterial.new()
		m.shader = FLIPBOOK_SHADER
		set_surface_override_material(0, m)
	var meta: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string(ATLAS_DIR + clip_name + ".atlas.json"))
	var mat: ShaderMaterial = get_active_material(0)
	mat.set_shader_parameter("atlas", load(ATLAS_DIR + clip_name + ".png"))
	mat.set_shader_parameter("cols", int(meta["cols"]))
	mat.set_shader_parameter("rows", int(meta["rows"]))
	mat.set_shader_parameter("frame_count", int(meta["frame_count"]))
	mat.set_shader_parameter("fps", float(meta["fps"]))
	mat.set_shader_parameter("start_time", float(Time.get_ticks_msec()) / 1000.0)
	mat.set_shader_parameter("phase", 0.0)
	mat.set_shader_parameter("use_instance", 0)

func get_clip() -> String:
	return _clip
