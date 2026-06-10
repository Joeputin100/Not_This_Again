extends Node

# Cotton-candy fluid fog (Level 4 mountain pass) — a real 2D fluid sim
# (advect / divergence / one-Jacobi-per-frame pressure / dye) rendered as a
# wispy pink ground-fog band the posse wades through. Adapted from the
# roguelike webgl_effects_demo Navier-Stokes solver; all passes are
# canvas_item shaders in low-res SubViewports (the mobile-proven class —
# spatial shaders white-rect on the Android renderer, canvas shaders don't).
# Spec: docs/superpowers/specs/2026-06-10-cotton-candy-fluid-fog-design.md
#
# VISUAL ONLY — no gameplay effect. Mountain terrain only, debug-gated;
# device pass is the perf go/no-go (4 RTT passes + display per frame).

const SIM_W := 192
const SIM_H := 108
const MAX_SPLATS := 16
const VEL_DISSIPATION := 0.992
const DYE_DISSIPATION := 0.985

const SH_VEL := preload("res://assets/shaders/fluid_velocity.gdshader")
const SH_DIV := preload("res://assets/shaders/fluid_divergence.gdshader")
const SH_PRS := preload("res://assets/shaders/fluid_pressure.gdshader")
const SH_DYE := preload("res://assets/shaders/fluid_dye.gdshader")
const SH_DISPLAY := preload("res://assets/shaders/fluid_fog_display.gdshader")

# ---- pure helpers (GUT-tested headless) ------------------------------------

# Fog thickness along the run: a breathing base + boss-approach ramp.
# 0.35 base, ±0.2 slow swell (period ~565 world units), +0.35·boss_frac,
# clamped to [0, 0.9] (never a wall — wispy by spec).
static func density(distance: float, boss_frac: float) -> float:
	# base 0.45 (owner look-dev report: 0.54 reads right at mid-swell)
	var v: float = 0.45 + 0.2 * sin(distance / 90.0) + 0.35 * clampf(boss_frac, 0.0, 1.0)
	return clampf(v, 0.0, 0.9)

# Pack splat candidates into fixed-size uniform arrays. Highest `prio` wins
# when over the cap. Returns {count, pos[], vel[], radius[], dye[]} with
# arrays always MAX-sized (shader uniform arrays are fixed length).
static func pack_splats(cands: Array, max_n: int) -> Dictionary:
	var sorted_c := cands.duplicate()
	sorted_c.sort_custom(func(a, b): return float(a["prio"]) > float(b["prio"]))
	var n: int = mini(sorted_c.size(), max_n)
	var pos: Array = []
	var vel: Array = []
	var radius: Array = []
	var dye: Array = []
	var flavor: Array = []
	for i in range(max_n):
		if i < n:
			pos.append(sorted_c[i]["uv"])
			vel.append(sorted_c[i]["vel"])
			radius.append(float(sorted_c[i]["radius"]))
			dye.append(float(sorted_c[i]["dye"]))
			flavor.append(float(sorted_c[i].get("flavor", 0.0)))
		else:
			pos.append(Vector2.ZERO)
			vel.append(Vector2.ZERO)
			radius.append(0.0)
			dye.append(0.0)
			flavor.append(0.0)
	return {"count": n, "pos": pos, "vel": vel, "radius": radius, "dye": dye, "flavor": flavor}

# ---- runtime ----------------------------------------------------------------

var enabled: bool = false:
	set(v):
		if v == enabled:
			return
		enabled = v
		if v:
			_build()
		else:
			_teardown()

var fog_density: float = 0.5   # pushed to the display shader each frame

var _vel: Array = []     # [SubViewport, SubViewport] ping-pong
var _prs: Array = []
var _dye: Array = []
var _div: SubViewport = null
var _flip: bool = false  # which side of each pair wrote last frame
var _display: ColorRect = null
var _splat_buf: Array = []

# Materials per writer viewport (uniforms pushed each frame).
var _mat_vel: Array = []
var _mat_prs: Array = []
var _mat_dye: Array = []
var _mat_div: ShaderMaterial = null
var _mat_display: ShaderMaterial = null

func add_splat_candidate(uv: Vector2, vel: Vector2, radius: float, dye_amt: float, prio: float, flavor: float = 0.0) -> void:
	_splat_buf.append({"uv": uv, "vel": vel, "radius": radius, "dye": dye_amt,
		"prio": prio, "flavor": flavor})

func _make_pass(shader: Shader) -> Array:
	var sv := SubViewport.new()
	sv.size = Vector2i(SIM_W, SIM_H)
	sv.disable_3d = true
	sv.transparent_bg = false
	sv.render_target_update_mode = SubViewport.UPDATE_DISABLED
	var rect := ColorRect.new()
	rect.size = Vector2(SIM_W, SIM_H)
	var mat := ShaderMaterial.new()
	mat.shader = shader
	rect.material = mat
	sv.add_child(rect)
	add_child(sv)
	return [sv, mat]

func _build() -> void:
	_teardown()
	for i in range(2):
		var v := _make_pass(SH_VEL)
		_vel.append(v[0]); _mat_vel.append(v[1])
		var p := _make_pass(SH_PRS)
		_prs.append(p[0]); _mat_prs.append(p[1])
		var d := _make_pass(SH_DYE)
		_dye.append(d[0]); _mat_dye.append(d[1])
	var dv := _make_pass(SH_DIV)
	_div = dv[0]; _mat_div = dv[1]
	# full-screen display band under the HUD
	_display = ColorRect.new()
	_display.name = "FluidFogDisplay"
	_display.set_anchors_preset(Control.PRESET_FULL_RECT)
	_display.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat_display = ShaderMaterial.new()
	_mat_display.shader = SH_DISPLAY
	_display.material = _mat_display

func display_node() -> ColorRect:
	return _display

func _teardown() -> void:
	for arr in [_vel, _prs, _dye]:
		for sv in arr:
			if is_instance_valid(sv):
				sv.queue_free()
	if _div != null and is_instance_valid(_div):
		_div.queue_free()
	if _display != null and is_instance_valid(_display):
		_display.queue_free()
	_vel = []; _prs = []; _dye = []; _div = null; _display = null
	_mat_vel = []; _mat_prs = []; _mat_dye = []; _mat_div = null; _mat_display = null
	_splat_buf = []

func _process(delta: float) -> void:
	if not enabled or _vel.is_empty():
		_splat_buf = []
		return
	var dt: float = clampf(delta, 0.001, 0.033)
	var read_i: int = 0 if _flip else 1   # wrote last frame -> read this frame
	var write_i: int = 1 if _flip else 0
	_flip = not _flip
	var texel := Vector2(1.0 / SIM_W, 1.0 / SIM_H)
	var packed: Dictionary = pack_splats(_splat_buf, MAX_SPLATS)
	_splat_buf = []
	# 1. velocity: advect + splat forces + subtract last frame's pressure grad
	var mv: ShaderMaterial = _mat_vel[write_i]
	mv.set_shader_parameter("vel_tex", _vel[read_i].get_texture())
	mv.set_shader_parameter("pressure_tex", _prs[read_i].get_texture())
	mv.set_shader_parameter("dt", dt)
	mv.set_shader_parameter("dissipation", VEL_DISSIPATION)
	mv.set_shader_parameter("texel", texel)
	_push_splats(mv, packed)
	# 2. divergence of the NEW velocity
	_mat_div.set_shader_parameter("vel_tex", _vel[write_i].get_texture())
	_mat_div.set_shader_parameter("texel", texel)
	# 3. one Jacobi pressure step (temporal amortization)
	var mp: ShaderMaterial = _mat_prs[write_i]
	mp.set_shader_parameter("pressure_tex", _prs[read_i].get_texture())
	mp.set_shader_parameter("div_tex", _div.get_texture())
	mp.set_shader_parameter("texel", texel)
	# 4. dye: advect by the new velocity + dye splats
	var md: ShaderMaterial = _mat_dye[write_i]
	md.set_shader_parameter("dye_tex", _dye[read_i].get_texture())
	md.set_shader_parameter("vel_tex", _vel[write_i].get_texture())
	md.set_shader_parameter("dt", dt)
	md.set_shader_parameter("dissipation", DYE_DISSIPATION)
	md.set_shader_parameter("texel", texel)
	_push_splats(md, packed)
	# display
	if _mat_display != null:
		_mat_display.set_shader_parameter("dye_tex", _dye[write_i].get_texture())
		_mat_display.set_shader_parameter("density", fog_density)
	# render the writers this frame, in pass order (tree order already matches)
	for sv in [_vel[write_i], _div, _prs[write_i], _dye[write_i]]:
		(sv as SubViewport).render_target_update_mode = SubViewport.UPDATE_ONCE

func _push_splats(mat: ShaderMaterial, packed: Dictionary) -> void:
	mat.set_shader_parameter("n_splats", packed["count"])
	mat.set_shader_parameter("splat_pos", PackedVector2Array(packed["pos"]))
	mat.set_shader_parameter("splat_vel", PackedVector2Array(packed["vel"]))
	mat.set_shader_parameter("splat_radius", PackedFloat32Array(packed["radius"]))
	mat.set_shader_parameter("splat_dye", PackedFloat32Array(packed["dye"]))
	mat.set_shader_parameter("splat_flavor", PackedFloat32Array(packed["flavor"]))
