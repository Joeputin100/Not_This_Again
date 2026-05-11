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
const Collision2D = preload("res://scripts/collision_2d.gd")
const BulletScene = preload("res://scenes/bullet.tscn")
const BulletScript = preload("res://scripts/bullet.gd")
const BarrelScript = preload("res://scripts/barrel.gd")
const TumbleweedScript = preload("res://scripts/tumbleweed.gd")
const CactusScript = preload("res://scripts/cactus.gd")
const BarricadeScript = preload("res://scripts/barricade.gd")
const ChickenCoopScript = preload("res://scripts/chicken_coop.gd")
const ChickenScript = preload("res://scripts/chicken.gd")

const FOLLOW_SPEED: float = 12.0
const STARTING_POSSE: int = 5

# Bullets spawn this far above the cowboy each shot.
const BULLET_SPAWN_Y_OFFSET: float = -120.0

# Approximate cowboy hit box for barrel collision detection.
const COWBOY_SIZE: Vector2 = Vector2(120, 200)

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

# Auto-fire mechanic. Posse rate of fire = 1 / fire_interval per second.
# fire_interval will be mutated by power-up pickups (faster fire).
var fire_interval: float = 0.18
var _fire_timer: float = 0.0
var _bullets_fired: int = 0
var _barrels_destroyed: int = 0

# When false, _spawn_bullet() is a no-op. Set to false on win so we don't
# keep showering the (now-decorative) screen with bullets during the
# victory overlay.
var _shooting_active: bool = true

# Run-local state. Resets each level.
var posse_count: int = STARTING_POSSE:
	set(value):
		posse_count = maxi(1, value)
		_refresh_posse_label()

var progress: RefCounted
var shake: RefCounted
var combos: RefCounted

func _ready() -> void:
	DebugLog.add("level _ready start")
	# Belt-and-suspenders: also disable quit-on-go-back at runtime in case
	# the project.godot setting doesn't reach Android's Activity layer.
	get_tree().set_quit_on_go_back(false)
	# Third route: also connect to the Window's go_back_requested signal
	# directly. Godot emits this in parallel with NOTIFICATION_WM_GO_BACK_
	# REQUEST, so if one path is intercepted at the Java layer, the other
	# might still fire. Each handler logs to DebugLog so the user's COPY
	# button output reveals which (if either) actually ran.
	get_window().go_back_requested.connect(_on_back_requested_signal)
	DebugLog.add("level: quit_on_go_back=%s" % str(get_tree().is_quit_on_go_back()))
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
	DebugLog.add("level _ready end (gates=%d, cowboy=%s)" % [
		_gather_gates().size(),
		"ok" if cowboy != null else "NULL",
	])

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

	# Auto-fire bullets at fire_interval cadence.
	_fire_timer += delta
	while _fire_timer >= fire_interval:
		_fire_timer -= fire_interval
		_spawn_bullet()

	# Bullet ↔ obstacle / gate collision passes. O(bullets × obstacles)
	# per frame, trivial at this scale.
	_resolve_bullet_barrel_collisions()
	_resolve_bullet_gate_collisions()
	_resolve_bullet_obstacle_collisions("tumbleweeds", TumbleweedScript.SIZE)
	_resolve_bullet_obstacle_collisions("cacti", CactusScript.SIZE)
	_resolve_bullet_obstacle_collisions("barricades", BarricadeScript.SIZE)
	_resolve_bullet_obstacle_collisions("chicken_coops", ChickenCoopScript.SIZE)
	_resolve_bullet_obstacle_collisions("chickens", ChickenScript.SIZE)
	# Cowboy ↔ obstacle collision passes (posse damage).
	_resolve_barrel_cowboy_collisions()
	_resolve_obstacle_cowboy_collisions("tumbleweeds", TumbleweedScript.SIZE)
	_resolve_obstacle_cowboy_collisions("cacti", CactusScript.SIZE)
	_resolve_obstacle_cowboy_collisions("barricades", BarricadeScript.SIZE)
	# chicken_coops and chickens have get_cowboy_damage() == 0, so we
	# skip them in the cowboy-collision pass (no point processing).

	# Diagnostic — fallback to get_node in case @onready ref is stale.
	var dbg := debug_label if debug_label != null else get_node_or_null("UI/DebugInfo") as Label
	if dbg:
		dbg.text = "proc:%d input:%d type:%s\ntarget_x:%.0f cowboy_x:%.0f bullets_fired:%d barrels_dead:%d" % [
			_process_run_count, _input_event_count, _last_input_type,
			target_x, cowboy.position.x,
			_bullets_fired, _barrels_destroyed,
		]

func _spawn_bullet() -> void:
	if not _shooting_active:
		return
	var bullet := BulletScene.instantiate()
	bullet.position = cowboy.position + Vector2(0, BULLET_SPAWN_Y_OFFSET)
	add_child(bullet)
	_bullets_fired += 1

func _resolve_bullet_barrel_collisions() -> void:
	var bullets := get_tree().get_nodes_in_group("bullets")
	var barrels := get_tree().get_nodes_in_group("barrels")
	if bullets.is_empty() or barrels.is_empty():
		return
	for bullet in bullets:
		for barrel in barrels:
			if Collision2D.rects_overlap(
					bullet.position, BulletScript.SIZE,
					barrel.position, BarrelScript.SIZE):
				var was_destroyed: bool = barrel.take_damage(1)
				if was_destroyed:
					_barrels_destroyed += 1
					shake.add_trauma(0.4)
				# Bullet is consumed on hit. Remove from group so the
				# next iteration of this pass doesn't see it again.
				bullet.remove_from_group("bullets")
				bullet.queue_free()
				break  # this bullet is done; move to next bullet

func _resolve_bullet_gate_collisions() -> void:
	# Discover gates via _gather_gates (same duck-type check used in
	# _ready). Then for each unfired gate, check overlap with each
	# bullet — additive gates bump their values, mult gates just
	# absorb. Either way the bullet is consumed.
	var bullets := get_tree().get_nodes_in_group("bullets")
	if bullets.is_empty():
		return
	var gates := _gather_gates()
	if gates.is_empty():
		return
	for bullet in bullets:
		for gate in gates:
			if Collision2D.rects_overlap(
					bullet.position, BulletScript.SIZE,
					gate.position, gate.SIZE):
				var consumed: bool = gate.take_bullet_hit()
				if consumed:
					bullet.remove_from_group("bullets")
					bullet.queue_free()
					break

func _resolve_bullet_obstacle_collisions(group_name: String, obstacle_size: Vector2) -> void:
	# Generic bullet-vs-group collision pass. Each obstacle (tumbleweed,
	# cactus, barricade) defines take_bullet_hit() returning whether the
	# bullet is consumed. We call it on overlap and free the bullet.
	var bullets := get_tree().get_nodes_in_group("bullets")
	if bullets.is_empty():
		return
	var obstacles := get_tree().get_nodes_in_group(group_name)
	if obstacles.is_empty():
		return
	for bullet in bullets:
		for obstacle in obstacles:
			if Collision2D.rects_overlap(
					bullet.position, BulletScript.SIZE,
					obstacle.position, obstacle_size):
				var consumed: bool = obstacle.take_bullet_hit()
				if consumed:
					bullet.remove_from_group("bullets")
					bullet.queue_free()
					break  # this bullet is done

func _resolve_obstacle_cowboy_collisions(group_name: String, obstacle_size: Vector2) -> void:
	# Cowboy-vs-group collision pass. On contact: posse takes the
	# obstacle's declared damage, obstacle is destroyed (if destructible)
	# or just persists (barricade) — we free non-destructible ones too
	# so they don't keep colliding frame after frame.
	for obstacle in get_tree().get_nodes_in_group(group_name):
		if obstacle.get("_destroyed") == true:
			continue
		if not Collision2D.rects_overlap(
				obstacle.position, obstacle_size,
				cowboy.position, COWBOY_SIZE):
			continue
		var damage: int = obstacle.get_cowboy_damage()
		DebugLog.add("%s hit cowboy → posse -%d" % [group_name, damage])
		posse_count = maxi(1, posse_count - damage)
		_pulse_posse_label()
		shake.add_trauma(minf(0.4 + damage * 0.05, 0.95))
		# Destroy destructibles via take_damage if available, otherwise
		# queue_free directly (barricades don't have take_damage).
		if obstacle.has_method("take_damage"):
			obstacle.take_damage(99999)  # overkill
		else:
			obstacle.queue_free()

func _resolve_barrel_cowboy_collisions() -> void:
	# If a barrel reaches the cowboy intact, it slams into the posse:
	# damages posse_count by the barrel's remaining HP, destroys the barrel.
	# The barrel's destroy animation is reused; no separate "explosion".
	for barrel in get_tree().get_nodes_in_group("barrels"):
		if barrel._destroyed:
			continue
		if Collision2D.rects_overlap(
				barrel.position, BarrelScript.SIZE,
				cowboy.position, COWBOY_SIZE):
			var damage: int = barrel.hp
			DebugLog.add("barrel hit cowboy at hp=%d → posse -%d" % [damage, damage])
			posse_count = maxi(1, posse_count - damage)
			_pulse_posse_label()
			shake.add_trauma(0.65)
			# Force-destroy the barrel (overkill so take_damage returns true).
			barrel.take_damage(barrel.hp)

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
		# Also handled via go_back_requested signal in _ready. Both can fire;
		# we route the same way regardless of which arrived.
		DebugLog.add("level NOTIFICATION_WM_GO_BACK_REQUEST → menu")
		_go_back_to_menu()
	elif what == NOTIFICATION_WM_CLOSE_REQUEST:
		DebugLog.add("level NOTIFICATION_WM_CLOSE_REQUEST → quit")
		get_tree().quit()

func _on_back_requested_signal() -> void:
	DebugLog.add("level go_back_requested SIGNAL → menu")
	_go_back_to_menu()

# Idempotent — calling twice from both routes is safe; change_scene_to_file
# bails fast if scene is already changing.
func _go_back_to_menu() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

func _on_gate_triggered(gate_center_x: float, gate: Node) -> void:
	# Combo escalates per consecutive gate. Particle amount and screen
	# trauma both scale via CombosCounter's curves; over combo 3 we get
	# the "MEGA!" floating banner (Candy-Crush-style escalation).
	#
	# Explicit `: int` annotation on the step() call result is REQUIRED:
	# `combos` is typed as base RefCounted (since CombosCounter has no
	# class_name), so the parser can't infer `combos.step()`'s return
	# type. Without this annotation, the whole script fails to load at
	# runtime — manifesting as level.gd not attached, _ready/_process/
	# _input "nonexistent." Found via test_level_integration.gd in iter 14.
	var combo: int = combos.step()
	DebugLog.add("gate triggered combo=%d cowboy_x=%.0f" % [combo, cowboy.position.x])

	# Boost gate's particle amount BEFORE its _play_pass_animation runs.
	# Signal emission is synchronous, so this lands before emitting=true.
	var mult: float = CombosCounterScript.particle_multiplier(combo)
	if gate.has_node("Sparkles"):
		var sparkles := gate.get_node("Sparkles") as CPUParticles2D
		sparkles.amount = int(28.0 * mult)

	var side := GateHelper.which_side(cowboy.position.x, gate_center_x)
	posse_count = GateHelper.apply_effect(posse_count, side, gate.left_value, gate.right_value, gate.gate_type)
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
	# Stop new bullets from spawning during/after the win overlay. Bullets
	# already in flight continue until they exit the top of the screen
	# (cleaner than a hard-cancel; no abrupt visual stop).
	_shooting_active = false
	DebugLog.add("WIN: bullets stopped, %d posse remaining" % posse_count)
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
