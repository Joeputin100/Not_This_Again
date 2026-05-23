extends Node3D

# Crowd of one character. One MultiMeshInstance3D per clip; each member
# lives in the mesh of its current clip. Per-instance custom data (a
# Color) carries: r=start_time, g=phase, b=flip(0/1).

const ATLAS_DIR := "res://assets/sprites/atlases/"
const FLIPBOOK_SHADER := preload("res://shaders/flipbook.gdshader")

var _meshes := {}          # clip_name -> MultiMeshInstance3D
var _member_clip := {}     # member_id -> clip_name
var _member_xform := {}    # member_id -> Transform3D
var _next_id := 0

func configure(_character: String, clips: Array) -> void:
	for clip in clips:
		var mmi := MultiMeshInstance3D.new()
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		var q := QuadMesh.new()
		# 9:16 to match the SP1 source-clip aspect (Veo 720x1280) so
		# crowd members render upright with correct proportions rather
		# than squashed onto a square quad.
		q.size = Vector2(1.125, 2.0)
		mm.mesh = q
		mmi.multimesh = mm
		var meta: Dictionary = JSON.parse_string(
			FileAccess.get_file_as_string(ATLAS_DIR + clip + ".atlas.json"))
		var mat := ShaderMaterial.new()
		mat.shader = FLIPBOOK_SHADER
		mat.set_shader_parameter("atlas", load(ATLAS_DIR + clip + ".png"))
		mat.set_shader_parameter("cols", int(meta["cols"]))
		mat.set_shader_parameter("rows", int(meta["rows"]))
		mat.set_shader_parameter("frame_count", int(meta["frame_count"]))
		mat.set_shader_parameter("fps", float(meta["fps"]))
		mat.set_shader_parameter("use_instance", 1)   # read start/phase/flip per instance
		mmi.material_override = mat
		add_child(mmi)
		_meshes[clip] = mmi

func add_member(clip: String, xform := Transform3D.IDENTITY) -> int:
	var id := _next_id
	_next_id += 1
	_member_clip[id] = clip
	_member_xform[id] = xform
	_rebuild(clip)
	return id

func remove_member(id: int) -> void:
	if not _member_clip.has(id):
		return
	var clip: String = _member_clip[id]
	_member_clip.erase(id)
	_member_xform.erase(id)
	_rebuild(clip)

func set_member_clip(id: int, clip: String) -> void:
	var old: String = _member_clip[id]
	if old == clip:
		return
	_member_clip[id] = clip
	_rebuild(old)
	_rebuild(clip)

func clip_of(id: int) -> String:
	return _member_clip[id]

func member_count() -> int:
	return _member_clip.size()

func member_ids() -> Array:
	return _member_clip.keys()

func mesh_instance_count(clip: String) -> int:
	return _meshes[clip].multimesh.instance_count

func _rebuild(clip: String) -> void:
	var ids := []
	for id in _member_clip:
		if _member_clip[id] == clip:
			ids.append(id)
	var mm: MultiMesh = _meshes[clip].multimesh
	mm.instance_count = ids.size()
	for i in ids.size():
		var id: int = ids[i]
		mm.set_instance_transform(i, _member_xform[id])
		# r=start_time (now), g=random phase, b=random flip
		mm.set_instance_custom_data(i, Color(
			float(Time.get_ticks_msec()) / 1000.0, randf(),
			1.0 if randf() < 0.5 else 0.0, 0.0))
