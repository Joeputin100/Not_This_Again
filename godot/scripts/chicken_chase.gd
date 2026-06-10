extends Node3D

# Granny's Chicken Chase minigame. Self-contained 3D auto-runner built entirely
# in code: the cowboy runs a candy-farm lane; swipe to steer, tap to lunge-grab
# popcorn hens; caught hens fly to the wrapped-taffy counter. Rules live in the
# pure ChickenChaseRun; this does rendering, input, and Soda-Crush juice.

const ChickenChaseRun := preload("res://scripts/chicken_chase_run.gd")
const _BREATHING_SHADER := preload("res://shaders/breathing_prop.gdshader")
const _RYE := preload("res://assets/fonts/Rye-Regular.ttf")
const _HEN_TEX := "res://assets/sprites/props/chicken_popcorn.png"
const _HEN_FALLBACK := "res://assets/sprites/props/chicken_static.png"
const _OBSTACLE_TEX := "res://assets/sprites/props/barrel.png"

const RUN_SPEED: float = 8.0
const STEER_SPEED: float = 16.0
const LANE_HALF_W: float = 4.0
const LUNGE_RANGE_Z: float = 3.0
const LUNGE_RANGE_X: float = 1.6
const CHICKEN_JUKE_CHANCE: float = 0.45
const JUKE_DODGE_T: float = 0.9       # seconds a juked hen darts away + is uncatchable
const OBSTACLE_HIT_RADIUS: float = 1.1

var _run: ChickenChaseRun = null
var _cowboy: Node3D = null
var _flock: Node3D = null
var _obstacles: Node3D = null
var _taffy_panel: Control = null
var _taffy_label: Label = null
var _timer_label: Label = null
var _results: Control = null
var _results_headline: Label = null

const CHASE_MUSIC := preload("res://assets/audio/music/gladiators_tack_piano.ogg")

func _ready() -> void:
	# tack-piano "Entry of the Gladiators" — circus chaos for the chicken chase
	# (clean-room transcription, tools/gen_gladiators_tackpiano.py)
	if get_node_or_null("/root/MusicPlayer") != null and MusicPlayer.has_method("play"):
		MusicPlayer.play(CHASE_MUSIC)
	_run = ChickenChaseRun.new()
	if get_node_or_null("/root/GameState"):
		GameState.chicken_chase_spend()
	_build_world()
	_build_ui()
	_spawn_flock()
	_spawn_obstacles()
	if get_node_or_null("/root/AudioBus") and AudioBus.has_method("play_character_line"):
		AudioBus.play_character_line("granny_chase_%d" % (randi() % 2))
	_refresh_hud()

func _build_world() -> void:
	var cam := Camera3D.new()
	cam.position = Vector3(0, 7, 8)
	cam.rotation_degrees = Vector3(-35, 0, 0)
	add_child(cam)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55, -30, 0)
	add_child(light)
	# simple ground plane (farm-ish dirt) — the chase is short
	var ground := MeshInstance3D.new()
	var gp := PlaneMesh.new()
	gp.size = Vector2(40, 120)
	ground.mesh = gp
	ground.position = Vector3(0, 0, -40)
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.62, 0.5, 0.3)
	ground.material_override = gm
	add_child(ground)
	_cowboy = _make_cutout(_try_tex("res://assets/sprites/props/hero_taffy_kid.png", _HEN_FALLBACK), 1.4, 1.8)
	_cowboy.position = Vector3(0, 0.9, 0)
	add_child(_cowboy)
	_flock = Node3D.new(); add_child(_flock)
	_obstacles = Node3D.new(); add_child(_obstacles)

func _build_ui() -> void:
	var ui := CanvasLayer.new()
	ui.name = "UI"
	add_child(ui)
	# wrapped-taffy counter (top-center)
	_taffy_panel = Control.new()
	_taffy_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_taffy_panel.position = Vector2(0, 40)
	ui.add_child(_taffy_panel)
	var taffy_bg := ColorRect.new()
	taffy_bg.color = Color(0.85, 0.45, 0.55, 0.85)
	taffy_bg.size = Vector2(160, 90)
	taffy_bg.position = Vector2(-80, 0)
	_taffy_panel.add_child(taffy_bg)
	_taffy_label = _make_label(64)
	_taffy_label.size = Vector2(160, 90)
	_taffy_label.position = Vector2(-80, 0)
	_taffy_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_taffy_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_taffy_panel.add_child(_taffy_label)
	# timer (top-right)
	_timer_label = _make_label(48)
	_timer_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_timer_label.position = Vector2(-120, 40)
	_timer_label.size = Vector2(100, 60)
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ui.add_child(_timer_label)
	# results panel (hidden until run ends)
	_results = Control.new()
	_results.set_anchors_preset(Control.PRESET_FULL_RECT)
	_results.visible = false
	ui.add_child(_results)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_results.add_child(dim)
	_results_headline = _make_label(72)
	_results_headline.set_anchors_preset(Control.PRESET_CENTER)
	_results_headline.position = Vector2(-300, -120)
	_results_headline.size = Vector2(600, 120)
	_results_headline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_results.add_child(_results_headline)
	var cont := Button.new()
	cont.text = "MAP"
	cont.set_anchors_preset(Control.PRESET_CENTER)
	cont.position = Vector2(-90, 60)
	cont.size = Vector2(180, 80)
	cont.add_theme_font_override("font", _RYE)
	cont.add_theme_font_size_override("font_size", 44)
	cont.pressed.connect(_on_continue_pressed)
	_results.add_child(cont)

func _make_label(sz: int) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", _RYE)
	l.add_theme_font_size_override("font_size", sz)
	l.add_theme_color_override("font_color", Color(1, 1, 1))
	return l

func _process(delta: float) -> void:
	if _run == null or _run.is_over():
		return
	_run.tick(delta)
	_cowboy.position.z -= RUN_SPEED * delta
	_advance_flock(delta)
	_check_obstacle_contact()
	_refresh_hud()
	if _run.is_over():
		_end_run()

func _unhandled_input(ev: InputEvent) -> void:
	if _run == null or _run.is_over():
		return
	if ev is InputEventScreenDrag:
		_cowboy.position.x = clampf(_cowboy.position.x + ev.relative.x * 0.012, -LANE_HALF_W, LANE_HALF_W)
	elif (ev is InputEventScreenTouch and ev.pressed) or (ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT):
		_attempt_lunge()

func _attempt_lunge() -> void:
	if not _run.can_lunge():
		return
	var target := _nearest_catchable_hen()
	if target == null:
		return
	if randf() < CHICKEN_JUKE_CHANCE and not target.get_meta("juking", false):
		target.set_meta("juking", true)
		target.set_meta("juke_t", JUKE_DODGE_T)
		return
	if _run.try_catch():
		_fly_hen_to_taffy(target)

func _nearest_catchable_hen() -> Node3D:
	var best: Node3D = null
	var best_d := 1e9
	for h in _flock.get_children():
		if not (h is Node3D) or h.get_meta("caught", false):
			continue
		var dz: float = _cowboy.position.z - h.position.z
		var dx: float = absf(h.position.x - _cowboy.position.x)
		if dz >= 0.0 and dz <= LUNGE_RANGE_Z and dx <= LUNGE_RANGE_X and dz < best_d:
			best_d = dz; best = h
	return best

func _fly_hen_to_taffy(hen: Node3D) -> void:
	hen.set_meta("caught", true)
	var tw := create_tween()
	tw.tween_property(hen, "position", hen.position + Vector3(0, 3.0, 3.0), 0.18)
	tw.parallel().tween_property(hen, "scale", hen.scale * 0.3, 0.3)
	tw.tween_callback(func():
		hen.visible = false
		if get_node_or_null("/root/AudioBus") and AudioBus.has_method("play_sfx"):
			AudioBus.play_sfx("deputize_join")
		_pop_taffy())

func _pop_taffy() -> void:
	if _taffy_panel == null:
		return
	var tw := create_tween()
	_taffy_panel.scale = Vector2(1.25, 1.25)
	tw.tween_property(_taffy_panel, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _spawn_flock() -> void:
	var tex := _try_tex(_HEN_TEX, _HEN_FALLBACK)
	for i in range(ChickenChaseRun.FLOCK):
		var hen := _make_cutout(tex, 1.0, 1.0)
		hen.position = Vector3(randf_range(-LANE_HALF_W, LANE_HALF_W), 0.6, _cowboy.position.z - 8.0 - i * 3.0)
		hen.set_meta("caught", false)
		hen.set_meta("phase", randf() * TAU)
		_flock.add_child(hen)

func _advance_flock(delta: float) -> void:
	for h in _flock.get_children():
		if not (h is Node3D) or h.get_meta("caught", false):
			continue
		var ph: float = float(h.get_meta("phase", 0.0)) + delta
		h.set_meta("phase", ph)
		h.position.x += sin(ph * 3.0) * 0.6 * delta
		if h.get_meta("juking", false):
			var away: float = signf(h.position.x - _cowboy.position.x)
			if away == 0.0:
				away = 1.0
			h.position.x = clampf(h.position.x + away * 4.0 * delta, -LANE_HALF_W, LANE_HALF_W)
			var jt: float = float(h.get_meta("juke_t", 0.0)) - delta
			if jt <= 0.0:
				h.set_meta("juking", false)   # dodge over — catchable again
			else:
				h.set_meta("juke_t", jt)

func _spawn_obstacles() -> void:
	var tex := _try_tex(_OBSTACLE_TEX, _HEN_FALLBACK)
	for i in range(4):
		var ob := _make_cutout(tex, 1.2, 1.4)
		ob.position = Vector3(randf_range(-LANE_HALF_W, LANE_HALF_W), 0.7, _cowboy.position.z - 12.0 - i * 6.0)
		ob.set_meta("spent", false)
		_obstacles.add_child(ob)

func _check_obstacle_contact() -> void:
	if not _run.can_lunge():
		return
	for ob in _obstacles.get_children():
		if not (ob is Node3D) or ob.get_meta("spent", false):
			continue
		var dz: float = absf(ob.position.z - _cowboy.position.z)
		var dx: float = absf(ob.position.x - _cowboy.position.x)
		if dz < OBSTACLE_HIT_RADIUS and dx < OBSTACLE_HIT_RADIUS:
			ob.set_meta("spent", true)
			_run.stumble()
			var tw := create_tween()
			tw.tween_property(_cowboy, "rotation:z", 0.3, 0.08)
			tw.tween_property(_cowboy, "rotation:z", 0.0, 0.2)

func _refresh_hud() -> void:
	if _taffy_label:
		_taffy_label.text = "%d/%d" % [_run.caught, ChickenChaseRun.FLOCK]
	if _timer_label:
		_timer_label.text = "%0.0f" % ceil(_run.time_left)

func _end_run() -> void:
	if get_node_or_null("/root/GameState"):
		GameState.chicken_chase_award(_run.caught)
	var line := "granny_win_zero_0"
	if _run.caught >= ChickenChaseRun.FLOCK:
		line = "granny_win_full_0"
	elif _run.caught > 0:
		line = "granny_win_partial_0"
	if get_node_or_null("/root/AudioBus") and AudioBus.has_method("play_character_line"):
		AudioBus.play_character_line(line)
	var bonus := 0
	if get_node_or_null("/root/GameState"):
		bonus = GameState.posse_bonus_for(_run.caught)
	if _results_headline:
		_results_headline.text = "+%d POSSE BREW" % bonus
	if _results:
		_results.visible = true

func _on_continue_pressed() -> void:
	# hand the music back to the selector's shared track
	if get_node_or_null("/root/MusicPlayer") != null and MusicPlayer.has_method("play_splash"):
		MusicPlayer.play_splash()
	get_tree().change_scene_to_file("res://scenes/level_select.tscn")

# ── cutout helper (mirrors level_3d's breathing-prop approach) ──
func _make_cutout(tex: Texture2D, w: float, h: float) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(w, h)
	plane.subdivide_width = 5
	plane.subdivide_depth = 7
	plane.orientation = 2
	mesh.mesh = plane
	var mat := ShaderMaterial.new()
	mat.shader = _BREATHING_SHADER
	mat.set_shader_parameter("albedo_tex", tex)
	mat.set_shader_parameter("modulate", Color(1, 1, 1, 1))
	mat.set_shader_parameter("sway_amp", 0.06)
	mat.set_shader_parameter("sway_freq", 2.0)
	mat.set_shader_parameter("bob_amp", 0.03)
	mat.set_shader_parameter("bob_freq", 3.0)
	mat.set_shader_parameter("time_offset", randf() * 6.28)
	mat.set_shader_parameter("mesh_height", h)
	mesh.material_override = mat
	return mesh

func _try_tex(path: String, fallback: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	return load(fallback) as Texture2D
