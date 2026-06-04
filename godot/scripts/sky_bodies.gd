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
# Candy mountain range baked into the sky shader's horizon (iter 335).
const MOUNTAINS_TEX := preload("res://assets/sprites/props/candy_mountains.png")

# Iter 336: shared two-axis sky presets for gameplay + level-select.
#   TIME OF DAY (from the system clock) drives sun/moon + light-tinted sky.
#   WEATHER (per level / themed) drives the clouds.
# sun/moon heights are LOW so they read at the down-tilted in-game cameras.
# (SP1 keeps its own richer LIGHTING_PRESETS; these are for the world scenes.)
const SKY_TOD := {
	"daylight": {
		"sun_visible": true, "sun_height": 7.0, "sun_tex": "daylight",
		"sun_tint": Color(1, 1, 1, 1), "sun_corona_intensity": 1.1,
		"sun_corona_body": Color(1.0, 0.95, 0.30, 1), "sun_corona_ray": Color(1.0, 0.65, 0.15, 1),
		"moon_visible": false,
		"sky_top": Color(0.20, 0.42, 0.64, 1), "sky_bot": Color(0.58, 0.80, 1.0, 1),
	},
	"sunset": {
		"sun_visible": true, "sun_height": 5.0, "sun_tex": "sunset",
		"sun_tint": Color(1, 0.95, 0.85, 1), "sun_corona_intensity": 1.25,
		"sun_corona_body": Color(1.0, 0.70, 0.15, 1), "sun_corona_ray": Color(1.0, 0.35, 0.10, 1),
		"moon_visible": false,
		"sky_top": Color(0.45, 0.28, 0.42, 1), "sky_bot": Color(1.0, 0.58, 0.30, 1),
	},
	"moonlight": {
		"sun_visible": false, "moon_visible": true, "moon_height": 7.0,
		"moon_tint": Color(0.88, 0.92, 1.05, 1), "moon_corona_color": Color(0.74, 0.84, 1.0, 1),
		"moon_corona_strength": 0.85,
		"sky_top": Color(0.03, 0.05, 0.13, 1), "sky_bot": Color(0.10, 0.14, 0.30, 1),
	},
}
const SKY_WEATHER := {
	"fair":     {"cloud_tint": Color(1.10, 1.10, 0.95, 1), "cloud_cover": 0.45, "cloud_speed": 0.006},
	"overcast": {"cloud_tint": Color(0.92, 0.92, 0.94, 1), "cloud_cover": 0.66, "cloud_speed": 0.010},
	"stormy":   {"cloud_tint": Color(0.40, 0.42, 0.48, 1), "cloud_cover": 0.94, "cloud_speed": 0.020},
	# Per-weather looks (iter417). Cloud SPEED rises with the weather's energy:
	# rain scuds gently, snow drifts slowest, dust blows fast, wind whips fastest.
	"rain":       {"cloud_tint": Color(0.78, 0.80, 0.86, 1), "cloud_cover": 0.78, "cloud_speed": 0.013},
	"snow":       {"cloud_tint": Color(0.90, 0.93, 0.98, 1), "cloud_cover": 0.62, "cloud_speed": 0.008},
	"dust_storm": {"cloud_tint": Color(0.82, 0.66, 0.45, 1), "cloud_cover": 0.80, "cloud_speed": 0.022},
	"wind_storm": {"cloud_tint": Color(0.55, 0.52, 0.50, 1), "cloud_cover": 0.88, "cloud_speed": 0.034},
}

# System clock → time-of-day key. Local hour buckets.
static func tod_from_clock() -> String:
	var h: int = Time.get_datetime_dict_from_system().get("hour", 12)
	if h >= 6 and h < 17:
		return "daylight"
	elif h >= 17 and h < 20:
		return "sunset"
	return "moonlight"

# Merge a time-of-day base with a weather overlay into one apply_preset dict.
static func make_sky_preset(tod: String, weather: String) -> Dictionary:
	var base: Dictionary = SKY_TOD.get(tod, SKY_TOD["daylight"])
	var p: Dictionary = base.duplicate(true)
	var w: Dictionary = SKY_WEATHER.get(weather, SKY_WEATHER["fair"])
	for k in w:
		p[k] = w[k]
	return p

# Shaders for the procedural build path (gameplay / level-select). The SP1
# scene supplies these via its own .tscn sub-resources; here we build the same
# rig in code so the sky can be dropped into any SubViewport without
# duplicating ~15 scene nodes.
const _SH_SUN := preload("res://shaders/sun_lollipop.gdshader")
const _SH_CORONA := preload("res://shaders/sun_corona_star.gdshader")
const _SH_STICK := preload("res://shaders/sun_stick.gdshader")
const _SH_MOON := preload("res://shaders/moon_cookie.gdshader")
const _SH_CLOUDS := preload("res://shaders/sky_clouds.gdshader")

# Assigned in _ready: either found from scene children (SP1) or built in code.
var sun_disc: Node3D = null
var sun_stick: Node3D = null
var moon_disc: Node3D = null

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
		# Stick runs from the disc DOWN past the horizon line. At
		# SKY_DISTANCE (50m) the terrain plane has ended, so y=0 there is the
		# visible horizon; extending the stick well below 0 makes it plunge
		# convincingly toward/behind the horizon. center_offset hangs the quad
		# DOWN from the node origin so the node sits at the disc and the stick
		# can lean from that top anchor (see _process: rotation.z = 15°).
		var stick_bottom := -40.0
		var stick_height: float = sun_h - stick_bottom
		var stick_mesh: QuadMesh = sun_stick.get_node("StickMesh").mesh
		stick_mesh.size = Vector2(1.2, stick_height)
		stick_mesh.center_offset = Vector3(0.0, -stick_height * 0.5, 0.0)
		sun_stick.position = Vector3(horiz.x, sun_h, horiz.y)
		_push_sun_uniforms(preset)

	var moon_visible: bool = preset.get("moon_visible", false)
	moon_disc.visible = moon_visible
	if moon_visible:
		var moon_h: float = preset["moon_height"]
		moon_disc.position = Vector3(horiz.x, moon_h, horiz.y)
		_push_moon_uniforms(preset)

	_push_cloud_uniforms(preset)

# Iter 343: slight horizontal parallax of the baked horizon mountains, driven
# by the level-select path pan. Small factor — "slight but noticeable".
func set_mountain_pan(v: float) -> void:
	var we: Node = get_node_or_null("WorldEnvironment")
	if we == null:
		we = get_parent().get_node_or_null("WorldEnvironment")
	if we == null or we.environment == null or we.environment.sky == null:
		return
	var cm: ShaderMaterial = we.environment.sky.sky_material
	if cm != null:
		cm.set_shader_parameter("mtn_pan", v)

func _push_cloud_uniforms(preset: Dictionary) -> void:
	# Clouds are the WorldEnvironment sky shader — a sibling under Viewport3D
	# (SP1) or a child of this node (procedural build).
	var we: Node = get_node_or_null("WorldEnvironment")
	if we == null:
		we = get_parent().get_node_or_null("WorldEnvironment")
	if we == null or we.environment == null or we.environment.sky == null:
		return
	var cm: ShaderMaterial = we.environment.sky.sky_material
	if cm == null:
		return
	if preset.has("sky_top"):
		cm.set_shader_parameter("sky_color_top", preset["sky_top"])
	if preset.has("sky_bot"):
		cm.set_shader_parameter("sky_color_bot", preset["sky_bot"])
	if preset.has("cloud_tint"):
		cm.set_shader_parameter("cloud_color", preset["cloud_tint"])
	if preset.has("cloud_cover"):
		cm.set_shader_parameter("cloudcover", preset["cloud_cover"])
	if preset.has("cloud_speed"):
		cm.set_shader_parameter("cloud_speed", preset["cloud_speed"])
	# Candy mountains baked into the horizon (iter 335). Opt-in per preset so a
	# scene can leave them off; on by default for gameplay/level-select.
	if preset.get("mountains", true):
		cm.set_shader_parameter("mountains_tex", MOUNTAINS_TEX)
		cm.set_shader_parameter("mountains_on", true)
	else:
		cm.set_shader_parameter("mountains_on", false)

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
		# Billboard around Y to face the camera, plus a 15° lean so the stick
		# meets the horizon at 75° instead of straight up.
		var to_cam := _camera.global_position - sun_stick.global_position
		sun_stick.rotation = Vector3(0.0, atan2(to_cam.x, to_cam.z), deg_to_rad(15.0))

const VARIANTS := ["A", "B", "C"]
var _last_variant := {"sun": "", "moon": ""}

# Dedupe taps: both the Area3D physics-pick and the SP1 screen-space hit-test
# route to trigger_tap; this per-body cooldown stops one tap double-firing.
const _TAP_COOLDOWN := 0.25
var _last_tap_time := {"sun": -1.0, "moon": -1.0}

func _ready() -> void:
	# SP1 supplies the bodies as scene children; gameplay / level-select add a
	# bare SkyBodies node, so build the rig in code when it's missing.
	if has_node("SunDisc"):
		sun_disc = $SunDisc
		sun_stick = $SunStick
		moon_disc = $MoonDisc
	else:
		_build_procedural()
	var pairs := [["sun", sun_disc], ["moon", moon_disc]]
	for pair in pairs:
		var body_key: String = pair[0]
		var body: Node3D = pair[1]
		var area: Area3D = body.get_node_or_null("TapArea")
		if area:
			area.input_event.connect(_on_body_tapped.bind(body_key, body))

# Build the full sun/moon rig + a cloud WorldEnvironment in code (gameplay /
# level-select). Mirrors the SP1 .tscn: sun disc (lollipop) + corona (star) +
# stick, moon (cookie), and a sky-shader cloud environment. No tap areas — the
# sky isn't tapped during play.
func _build_procedural() -> void:
	sun_disc = Node3D.new()
	sun_disc.name = "SunDisc"
	add_child(sun_disc)
	sun_disc.add_child(_make_disc("Corona", 30.0, _SH_CORONA, -25))
	sun_disc.add_child(_make_disc("DiscMesh", 12.0, _SH_SUN, -20))

	sun_stick = Node3D.new()
	sun_stick.name = "SunStick"
	add_child(sun_stick)
	var stick := MeshInstance3D.new()
	stick.name = "StickMesh"
	var sq := QuadMesh.new()
	sq.size = Vector2(0.6, 1.0)
	stick.mesh = sq
	stick.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var stick_mat := ShaderMaterial.new()
	stick_mat.shader = _SH_STICK
	stick_mat.render_priority = -23
	stick.material_override = stick_mat
	sun_stick.add_child(stick)

	moon_disc = Node3D.new()
	moon_disc.name = "MoonDisc"
	add_child(moon_disc)
	moon_disc.add_child(_make_disc("DiscMesh", 9.0, _SH_MOON, -20))
	moon_disc.visible = false

	# Cloud sky environment (child of self → applies to this viewport's world).
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.02
	noise.fractal_octaves = 6
	var ntex := NoiseTexture2D.new()
	ntex.width = 1024
	ntex.height = 1024
	ntex.seamless = true
	ntex.generate_mipmaps = true
	ntex.noise = noise
	var cloud_mat := ShaderMaterial.new()
	cloud_mat.shader = _SH_CLOUDS
	cloud_mat.set_shader_parameter("noise_tex", ntex)
	var sky := Sky.new()
	sky.sky_material = cloud_mat
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	add_child(we)

# One billboarded disc quad with a shader material. Used for sun disc, corona,
# and moon.
func _make_disc(disc_name: String, size: float, shader: Shader, priority: int) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = disc_name
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	mi.mesh = q
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.render_priority = priority
	mi.material_override = mat
	return mi

func _pick_variant(body_key: String) -> String:
	var pool := VARIANTS.filter(func(v): return v != _last_variant[body_key])
	var chosen: String = pool[randi() % pool.size()]
	_last_variant[body_key] = chosen
	return chosen

func _on_body_tapped(_camera: Node, event: InputEvent, _pos: Vector3,
					_normal: Vector3, _shape_idx: int,
					body_key: String, _body: Node3D) -> void:
	var is_touch: bool = event is InputEventScreenTouch and event.pressed
	var is_click: bool = event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT
	if not (is_touch or is_click):
		return
	trigger_tap(body_key)

# Public: play a random no-repeat tap reaction (sound + animation) for the
# given body ("sun"/"moon"). Called both by the Area3D physics-pick path and
# by the SP1 viewer's screen-space hit test (more reliable on touch).
func trigger_tap(body_key: String) -> void:
	var now: float = float(Time.get_ticks_msec()) / 1000.0
	if now - float(_last_tap_time[body_key]) < _TAP_COOLDOWN:
		return
	_last_tap_time[body_key] = now
	var body: Node3D = sun_disc if body_key == "sun" else moon_disc
	var variant := _pick_variant(body_key)
	# Scene's TapSfx players are AudioStreamPlayer (non-positional). The old
	# AudioStreamPlayer3D annotation was a TYPE MISMATCH that threw at runtime
	# and aborted this function before any sound OR animation — the real reason
	# taps did nothing across every prior attempt (iter 331 fix).
	var sfx_player: AudioStreamPlayer = body.get_node_or_null("TapSfx/%s" % variant)
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
