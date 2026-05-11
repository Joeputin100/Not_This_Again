extends Node2D

# Phase 1 level: 3 math gates scroll toward the cowboy. Posse count
# updates per gate. When all gates have fired, the WinOverlay slides in
# with the final bounty, an AGAIN button replays the level. Back gesture
# returns to menu mid-run or post-win.

const MovementBounds = preload("res://scripts/movement_bounds.gd")
const GateHelper = preload("res://scripts/gate_helper.gd")
const LevelProgressScript = preload("res://scripts/level_progress.gd")
const ScreenShakeScript = preload("res://scripts/screen_shake.gd")
const CombosCounterScript = preload("res://scripts/combos_counter.gd")

const FOLLOW_SPEED: float = 12.0
const STARTING_POSSE: int = 5

@onready var cowboy: Node2D = $Cowboy
@onready var camera: Camera2D = $Camera
@onready var posse_label: Label = $UI/PosseCount
@onready var debug_label: Label = $UI/DebugInfo
@onready var win_overlay: CanvasLayer = $WinOverlay
@onready var win_panel: Control = $WinOverlay/WinPanel
@onready var win_subtitle: Label = $WinOverlay/WinPanel/WinSubtitle
@onready var again_button: Button = $WinOverlay/WinPanel/PlayAgainButton
@onready var menu_button: Button = $WinOverlay/WinPanel/MenuButton

var target_x: float
var _input_event_count: int = 0
var _process_run_count: int = 0
var _last_input_type: String = "(none yet)"
var _last_event_class: String = "(none)"

# Run-local state. Resets each level.
var posse_count: int = STARTING_POSSE:
	set(value):
		posse_count = maxi(1, value)
		_refresh_posse_label()

var progress: RefCounted
var shake: RefCounted
var combos: RefCounted

func _ready() -> void:
	print("[LEVEL] _ready start")
	target_x = cowboy.position.x
	progress = LevelProgressScript.new()
	shake = ScreenShakeScript.new()
	combos = CombosCounterScript.new()

	# Discover all gates by group instead of hand-listing — adding a 4th
	# gate to the scene tree later won't require code changes here.
	var gates := _gather_gates()
	progress.reset(gates.size())
	for gate in gates:
		gate.triggered.connect(_on_gate_triggered.bind(gate))

	again_button.pressed.connect(_on_again_pressed)
	menu_button.pressed.connect(_on_menu_pressed)
	# Pivot for the win panel scale-in animation
	win_panel.pivot_offset = Vector2(440, 280)
	_refresh_posse_label()
	# Diagnostic: mark that _ready completed end-to-end.
	if debug_label:
		debug_label.text = "READY OK (process not yet ticked)"
	else:
		print("[LEVEL] WARNING: debug_label is null at end of _ready")
	print("[LEVEL] _ready end. cowboy=", cowboy, " camera=", camera, " debug_label=", debug_label)

func _gather_gates() -> Array[Node]:
	var gates: Array[Node] = []
	for child in get_children():
		if child.has_signal("triggered") and child.has_method("_format_left"):
			gates.append(child)
	return gates

func _process(delta: float) -> void:
	_process_run_count += 1
	cowboy.position.x = lerpf(cowboy.position.x, target_x, FOLLOW_SPEED * delta)
	# Drive screen shake. CanvasLayer-rooted UI is unaffected; only
	# world-space nodes (background, lane guides, gates, cowboy) shake.
	camera.offset = shake.tick(delta)
	# Diagnostic — fallback to get_node in case @onready ref is stale.
	# This SHOULD always update if _process is firing.
	var dbg := debug_label if debug_label != null else get_node_or_null("UI/DebugInfo") as Label
	if dbg:
		dbg.text = "proc:%d input:%d type:%s class:%s\ntarget_x:%.0f cowboy_x:%.0f" % [
			_process_run_count, _input_event_count, _last_input_type, _last_event_class,
			target_x, cowboy.position.x,
		]

func _input(event: InputEvent) -> void:
	# Track ALL inputs to verify _input is being called at all, not just
	# touch-flavored ones.
	_last_event_class = event.get_class()
	var new_x := -1.0
	if event is InputEventScreenDrag:
		new_x = (event as InputEventScreenDrag).position.x
		_last_input_type = "DRAG"
		_input_event_count += 1
	elif event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed:
		new_x = (event as InputEventScreenTouch).position.x
		_last_input_type = "TOUCH"
		_input_event_count += 1
	elif event is InputEventMouseMotion and ((event as InputEventMouseMotion).button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		new_x = (event as InputEventMouseMotion).position.x
		_last_input_type = "MOUSE_MOTION"
		_input_event_count += 1
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			new_x = mb.position.x
			_last_input_type = "MOUSE_BUTTON"
			_input_event_count += 1
	if new_x >= 0.0:
		target_x = MovementBounds.clamp_x(new_x)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
	elif what == NOTIFICATION_WM_CLOSE_REQUEST:
		get_tree().quit()

func _on_gate_triggered(gate_center_x: float, gate: Node) -> void:
	# Combo escalates per consecutive gate. Particle amount and screen
	# trauma both scale via CombosCounter's curves; over combo 3 we get
	# the "MEGA!" floating banner (Candy-Crush-style escalation).
	var combo := combos.step()

	# Boost gate's particle amount BEFORE its _play_pass_animation runs.
	# Signal emission is synchronous, so this lands before emitting=true.
	var mult := CombosCounterScript.particle_multiplier(combo)
	if gate.has_node("Sparkles"):
		var sparkles := gate.get_node("Sparkles") as CPUParticles2D
		sparkles.amount = int(28.0 * mult)

	var side := GateHelper.which_side(cowboy.position.x, gate_center_x)
	posse_count = GateHelper.apply_effect(posse_count, side, gate.left_value, gate.right_value)
	AudioBus.play_gate_pass()
	shake.add_trauma(CombosCounterScript.trauma_for(combo))
	_pulse_posse_label()

	var combo_label := CombosCounterScript.label_for(combo)
	if combo_label != "":
		_spawn_combo_banner(combo_label)

	progress.record_pass()
	if progress.is_complete():
		_show_win()

# Floating combo banner ("DOUBLE!" / "MEGA!") added to the UI canvas
# layer so screen shake doesn't jitter it. Scales in with a bounce,
# floats upward, fades out, queue_frees.
func _spawn_combo_banner(text: String) -> void:
	var ui := $UI as CanvasLayer
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE  # don't block touch input
	label.theme = preload("res://assets/theme.tres")
	label.add_theme_font_size_override("font_size", 156)
	label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.5, 1))
	label.add_theme_color_override("font_outline_color", Color(0.18, 0.1, 0.03, 1))
	label.add_theme_constant_override("outline_size", 14)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.size_flags_horizontal = Control.SIZE_FILL
	label.anchor_left = 0.0
	label.anchor_right = 1.0
	label.anchor_top = 0.5
	label.anchor_bottom = 0.5
	label.offset_left = 0.0
	label.offset_right = 0.0
	label.offset_top = -90.0
	label.offset_bottom = 90.0
	ui.add_child(label)
	label.pivot_offset = Vector2(540.0, 90.0)
	label.scale = Vector2(0.4, 0.4)
	label.modulate.a = 0.0

	var pop := create_tween().set_parallel(true)
	pop.tween_property(label, "scale", Vector2.ONE, 0.22) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	pop.tween_property(label, "modulate:a", 1.0, 0.12)
	pop.tween_property(label, "offset_top", -290.0, 0.9) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	pop.tween_property(label, "offset_bottom", -110.0, 0.9) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await get_tree().create_timer(0.55).timeout
	var fade := create_tween()
	fade.tween_property(label, "modulate:a", 0.0, 0.35)
	await fade.finished
	label.queue_free()

func _refresh_posse_label() -> void:
	if posse_label:
		posse_label.text = "POSSE: %d" % posse_count

func _pulse_posse_label() -> void:
	if not posse_label:
		return
	posse_label.pivot_offset = posse_label.size / 2.0
	var tween := create_tween()
	tween.tween_property(posse_label, "scale", Vector2(1.25, 1.25), 0.12) \
		.set_trans(Tween.TRANS_BACK) \
		.set_ease(Tween.EASE_OUT)
	tween.tween_property(posse_label, "scale", Vector2.ONE, 0.18) \
		.set_trans(Tween.TRANS_SINE) \
		.set_ease(Tween.EASE_IN_OUT)

# ---------- Win flow ----------

func _show_win() -> void:
	# Murderbot-flavored bounty copy. Phase 1+ may template this further.
	win_subtitle.text = "%d posse members made it.
whatever that's worth." % posse_count
	# Wait a beat so the player notices the last gate fire before the
	# overlay covers it.
	await get_tree().create_timer(0.55).timeout
	win_overlay.visible = true
	win_panel.scale = Vector2(0.55, 0.55)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(win_panel, "scale", Vector2.ONE, 0.32) \
		.set_trans(Tween.TRANS_BACK) \
		.set_ease(Tween.EASE_OUT)

func _on_again_pressed() -> void:
	AudioBus.play_tap()
	again_button.disabled = true
	menu_button.disabled = true
	var t := create_tween()
	t.tween_property(again_button, "scale", Vector2(0.92, 0.92), 0.06)
	t.tween_property(again_button, "scale", Vector2.ONE, 0.16) \
		.set_trans(Tween.TRANS_BACK) \
		.set_ease(Tween.EASE_OUT)
	await t.finished
	get_tree().reload_current_scene()

func _on_menu_pressed() -> void:
	AudioBus.play_tap()
	again_button.disabled = true
	menu_button.disabled = true
	var t := create_tween()
	t.tween_property(menu_button, "scale", Vector2(0.92, 0.92), 0.06)
	t.tween_property(menu_button, "scale", Vector2.ONE, 0.16) \
		.set_trans(Tween.TRANS_BACK) \
		.set_ease(Tween.EASE_OUT)
	await t.finished
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
