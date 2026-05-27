extends Node3D

# Crowd of one character. One MultiMeshInstance3D per clip; each member
# lives in the mesh of its current clip. Per-instance custom data (a
# Color) carries: r=start_time, g=phase, b=flip(0/1).

const ATLAS_DIR := "res://assets/sprites/atlases/"
const FLIPBOOK_SHADER := preload("res://shaders/flipbook.gdshader")
const SHADOW_SHADER := preload("res://shaders/crowd_shadow.gdshader")

var _meshes := {}          # clip_name -> MultiMeshInstance3D
var _member_clip := {}     # member_id -> clip_name
var _member_xform := {}    # member_id -> Transform3D
var _next_id := 0

# Blob-shadow params — a single MultiMesh of dark ovals laid flat under
# each crowd member, offset in the light's anti-direction. Doesn't depend
# on the Mobile renderer's shadow-map support; works as plain alpha-blend
# geometry on any pipeline. set_shadow_params() drives appearance per
# lighting preset (sunset = long warm offset, daylight = short cool, etc).
const SHADOW_PLANE_SIZE := Vector2(1.4, 1.0)
var _shadow_mmi: MultiMeshInstance3D = null
var _shadow_offset := Vector3(0.25, 0.01, 0.45)
var _shadow_scale := 1.0
var _shadow_color := Color(0.0, 0.0, 0.05, 0.55)
var _shadow_enabled := true

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
		# Cast shadows so each member contributes a figure-shaped shadow via
		# the alpha-aware depth-pre-pass. Default is ON but being explicit
		# documents the dependency and survives any future refactor that
		# might set it to SHADOW_OFF (e.g., for a low-end-device option).
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(mmi)
		_meshes[clip] = mmi

func add_member(clip: String, xform := Transform3D.IDENTITY) -> int:
	var id := _next_id
	_next_id += 1
	_member_clip[id] = clip
	_member_xform[id] = xform
	_rebuild(clip)
	_rebuild_shadows()
	return id

func remove_member(id: int) -> void:
	if not _member_clip.has(id):
		return
	var clip: String = _member_clip[id]
	_member_clip.erase(id)
	_member_xform.erase(id)
	_rebuild(clip)
	_rebuild_shadows()

func set_member_clip(id: int, clip: String) -> void:
	var old: String = _member_clip[id]
	if old == clip:
		return
	_member_clip[id] = clip
	_rebuild(old)
	_rebuild(clip)
	# shadows don't move when clip changes — positions are unchanged.

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
		# r=start_time (now), g=random phase, b=random flip. start_time is
		# normalised to 0..1 so it survives any Mobile-renderer custom-data
		# precision quirk and the shader's milling code (which multiplies
		# by TAU) maps it across the full phase range.
		mm.set_instance_custom_data(i, Color(
			randf(), randf(),
			1.0 if randf() < 0.5 else 0.0, 0.0))

# ---- Blob shadows ---------------------------------------------------------

func set_shadow_params(offset: Vector3, color: Color, scale: float = 1.0) -> void:
	_shadow_offset = offset
	_shadow_color = color
	_shadow_scale = scale
	_ensure_shadow_mmi()
	var mat: ShaderMaterial = _shadow_mmi.material_override
	if mat:
		mat.set_shader_parameter("shadow_color", _shadow_color)
	_rebuild_shadows()

func set_shadow_enabled(enabled: bool) -> void:
	_shadow_enabled = enabled
	if _shadow_mmi:
		_shadow_mmi.visible = enabled

func _ensure_shadow_mmi() -> void:
	if _shadow_mmi != null:
		return
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "CrowdShadow"
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var plane := PlaneMesh.new()
	plane.size = SHADOW_PLANE_SIZE
	mm.mesh = plane
	mmi.multimesh = mm
	var mat := ShaderMaterial.new()
	mat.shader = SHADOW_SHADER
	mat.set_shader_parameter("shadow_color", _shadow_color)
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	_shadow_mmi = mmi

func _rebuild_shadows() -> void:
	if not _shadow_enabled:
		return
	_ensure_shadow_mmi()
	var ids: Array = _member_clip.keys()
	var mm: MultiMesh = _shadow_mmi.multimesh
	mm.instance_count = ids.size()
	var basis := Basis().scaled(Vector3(_shadow_scale, 1.0, _shadow_scale))
	for i in ids.size():
		var pos: Vector3 = _member_xform[ids[i]].origin
		# Shadow Y is tiny (above ground plane to win z-fight) but the
		# crowd_shadow shader's depth_test_disabled makes that moot — kept
		# small anyway for any future shader that does test depth.
		var shadow_pos := Vector3(
			pos.x + _shadow_offset.x,
			0.01,
			pos.z + _shadow_offset.z)
		mm.set_instance_transform(i, Transform3D(basis, shadow_pos))
