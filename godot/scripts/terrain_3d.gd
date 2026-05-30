extends Node2D

# Pseudo-3D ground plane for the level playfield. A SubViewport renders
# a tilted-perspective dirt plane in 3D space; the Sprite2D in this
# scene displays that render at the playfield's pixel size (1080×1920
# scaled from the 540×960 SubViewport).
#
# The 3D plane is static — instead of moving the geometry, we scroll
# the UV offset over time. Perspective foreshortening makes the near
# ground appear to scroll fast and the far ground appear to scroll
# slow without any extra math — the same uniform UV-velocity reads as
# proper depth motion because the plane is tilted.
#
# Sits BEHIND all 2D gameplay nodes in level.tscn — gates, obstacles,
# bullets, cowboy and posse all overlay on top of the rendered terrain.

# Iter 153/165: scroll_speed (UV-V units/sec) is synced by level_3d from
# OBSTACLE_SPEED so the ground texture scrolls at the SAME apparent rate
# as the world-space props sliding over it. The conversion is
# OBSTACLE_SPEED / 15 — the plane is 60 deep with uv1_scale.y = 4, so
# 1 UV-V = 60/4 = 15 world units. This default is a placeholder;
# level_3d overwrites it on _ready.
var scroll_speed: float = 0.1667

# Iter 63: gate the auto-scroll so the level-select variant of the
# terrain can stay static (panned by finger drag instead). Default true
# preserves gameplay behavior; level_select sets this to false on its
# Terrain3D instance.
@export var auto_scroll: bool = true

# Iter 339: the level-select terrain can be gently HILLY. Gameplay keeps it
# flat (hilly = false) so props sit on y = 0. When hilly, _ready rebuilds the
# Ground as a displaced mesh and height_at() becomes the single source of
# truth for the surface height — so the level-select script can sit the level
# orbs ON the hills instead of floating above a flat plane.
@export var hilly: bool = false
@export var hill_amp: float = 1.2

# Iter 339: the level-select map can carpet its hills in dense animated GRASS
# tufts (a MultiMesh driven by grass_field.gdshader — "our grass animation")
# and tint the ground green. Gameplay leaves grassy = false. grass_count is
# "much denser than the SP1 crowd preview" per the user.
@export var grassy: bool = false
@export var grass_count: int = 700
const _GRASS_TUFT: Texture2D = preload("res://assets/sprites/props/wheat_tuft.png")
const _GRASS_SHADER: Shader = preload("res://shaders/grass_field.gdshader")
var _half_z: float = 30.0  # half the plane depth; set when the hilly mesh is built

@onready var sub_viewport: SubViewport = $SubViewport
@onready var ground: MeshInstance3D = $SubViewport/Ground
@onready var sprite_2d: Sprite2D = $Sprite

var _material: StandardMaterial3D
var _uv_offset: float = 0.0
# Iter 40c: set false during boss fights so the world stops moving
# while the duel resolves. The cowboy is stationary, the boss is in
# STAY mode — the dirt scroll was the only motion telegraphing
# "running forward", which contradicted the showdown framing.
var _scroll_active: bool = true

func _ready() -> void:
	if sprite_2d:
		sprite_2d.texture = sub_viewport.get_texture()
	if ground:
		_material = ground.material_override as StandardMaterial3D
		if hilly:
			_build_hilly_mesh()
		if grassy:
			_make_grassy()

# Iter 40c: level.gd flips this off when the boss-engaged signal fires.
# Kept as a generic boolean (rather than a one-way latch) so it could
# also be flipped back on for win cinematics or special level events.
func set_scroll_active(active: bool) -> void:
	_scroll_active = active

# Iter 63: external nudge for drag-pan scenes (level_select). Negative
# delta scrolls "backward" so dragging UP makes the world come toward you.
func nudge_uv(delta_y: float) -> void:
	_uv_offset += delta_y
	while _uv_offset > 1.0:
		_uv_offset -= 1.0
	while _uv_offset < 0.0:
		_uv_offset += 1.0
	if _material:
		_material.uv1_offset = Vector3(0.0, _uv_offset, 0.0)

func _process(delta: float) -> void:
	if not _scroll_active or not auto_scroll:
		return
	# Iter 67: NEGATED — previous direction made the cowboy appear to
	# run backwards (dirt scrolled away from him toward the camera).
	# Subtracting moves the texture in the opposite UV direction so the
	# dirt now appears to move FROM the horizon TOWARD the camera —
	# matches the perception of "running forward into the scene."
	# Using fposmod for robust wrap-around in both directions.
	_uv_offset = fposmod(_uv_offset - scroll_speed * WorldSpeed.mult * delta, 1.0)
	if _material:
		_material.uv1_offset = Vector3(0.0, _uv_offset, 0.0)

# Iter 339: gentle rolling height field for the level-select map. Deterministic
# (no noise asset) so the mesh build and orb placement agree EXACTLY. Takes
# plane-LOCAL coords (centred at origin), returns the world-Y displacement.
func height_at(lx: float, lz: float) -> float:
	if not hilly:
		return 0.0
	return hill_amp * (
		0.6 * sin(lx * 0.17 + 0.6)
		+ 0.5 * sin(lz * 0.12 - 0.3)
		+ 0.4 * sin((lx + lz) * 0.08 + 1.1)
	)

# Rebuild the flat PlaneMesh as a displaced grid so the dirt + baked path
# texture drapes over gentle hills. Keeps the same 0..1 UV mapping as the
# PlaneMesh so the painted road lands exactly where it did before; only the
# Y is pushed by height_at(). Winding is chosen so normals face +Y (up).
func _build_hilly_mesh() -> void:
	var sx: float = 40.0
	var sz: float = 60.0
	var pm := ground.mesh as PlaneMesh
	if pm != null:
		sx = pm.size.x
		sz = pm.size.y
	var cols: int = 48
	var rows: int = maxi(48, int(sz))  # ~1 row/unit so hills stay smooth on a long plane
	_half_z = sz * 0.5
	# Precompute the grid (position + uv + analytic up-normal). No lambda — a
	# bare method call inside a GDScript lambda is unreliable. Normals come
	# from a finite-difference of height_at so lighting is correct, and the
	# material is set double-sided so visibility never depends on winding.
	var pos: Array = []
	var uvc: Array = []
	var nrm: Array = []
	var e: float = 0.5
	for j in range(rows + 1):
		var prow: Array = []
		var urow: Array = []
		var nrow: Array = []
		for i in range(cols + 1):
			var u: float = float(i) / float(cols)
			var v: float = float(j) / float(rows)
			var x: float = -sx * 0.5 + sx * u
			var z: float = -sz * 0.5 + sz * v
			prow.append(Vector3(x, height_at(x, z), z))
			urow.append(Vector2(u, v))
			nrow.append(Vector3(
				height_at(x - e, z) - height_at(x + e, z),
				2.0 * e,
				height_at(x, z - e) - height_at(x, z + e)).normalized())
		pos.append(prow)
		uvc.append(urow)
		nrm.append(nrow)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in range(rows):
		for i in range(cols):
			for cell in [[i, j], [i, j + 1], [i + 1, j + 1], [i, j], [i + 1, j + 1], [i + 1, j]]:
				var ci: int = cell[0]
				var cj: int = cell[1]
				st.set_uv(uvc[cj][ci])
				st.set_normal(nrm[cj][ci])
				st.add_vertex(pos[cj][ci])
	st.generate_tangents()
	ground.mesh = st.commit()
	if _material:
		_material.cull_mode = BaseMaterial3D.CULL_DISABLED

# Iter 339: green the ground (grass is built later by build_grass, once the
# level_select script knows where the path is so it can weed the corridor).
func _make_grassy() -> void:
	if _material:
		_material.albedo_texture = null               # drop the dirt/road art
		_material.albedo_color = Color(0.70, 0.56, 0.30)  # wheat / golden-brown

# A MultiMesh of billboarded grass-tuft quads scattered over the hills (swayed
# by grass_field.gdshader, one draw call). `avoid` is plane-local (x,z) points
# along the path; tufts within `radius` of any are skipped so grass doesn't
# grow up through the trail.
func build_grass(avoid: PackedVector2Array, radius: float,
		props: PackedVector2Array = PackedVector2Array(), prop_radius: float = 0.0) -> void:
	if not grassy:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 1337
	var r2: float = radius * radius
	var pr2: float = prop_radius * prop_radius
	var xforms: Array[Transform3D] = []
	var phases := PackedFloat32Array()
	var tries: int = 0
	while xforms.size() < grass_count and tries < grass_count * 6:
		tries += 1
		var gx: float = rng.randf_range(-18.0, 18.0)
		var gz: float = rng.randf_range(-_half_z + 4.0, 8.0)
		var blocked: bool = false
		for p in avoid:
			if Vector2(gx, gz).distance_squared_to(p) < r2:
				blocked = true
				break
		if not blocked and pr2 > 0.0:
			for q in props:
				if Vector2(gx, gz).distance_squared_to(q) < pr2:
					blocked = true
					break
		if blocked:
			continue
		var s: float = rng.randf_range(0.6, 1.3)
		xforms.append(Transform3D(Basis().scaled(Vector3.ONE * s),
			Vector3(gx, height_at(gx, gz) + 0.35 * s, gz)))
		phases.append(rng.randf())
	var quad := QuadMesh.new()
	quad.size = Vector2(0.9, 0.7)
	var mat := ShaderMaterial.new()
	mat.shader = _GRASS_SHADER
	mat.set_shader_parameter("albedo_tex", _GRASS_TUFT)
	mat.set_shader_parameter("sway_amp", 0.12)
	mat.set_shader_parameter("mesh_height", 0.7)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = quad
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		mm.set_instance_custom_data(i, Color(phases[i], 0.0, 0.0, 0.0))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "GrassField"
	mmi.multimesh = mm
	mmi.material_override = mat
	ground.add_child(mmi)
