extends Node2D

# Phase 1 level prototype: a draggable cowboy, one math gate scrolling
# down at it, and a posse counter that updates when the gate fires.
# Future commits add more gates, barricades, an outlaw boss, win/lose UI.

const MovementBounds = preload("res://scripts/movement_bounds.gd")
const GateHelper = preload("res://scripts/gate_helper.gd")

# Lerp speed for follow-the-finger smoothing. Higher = snappier;
# lower = laggier. ~12 feels responsive without jitter on 60Hz mid-range.
const FOLLOW_SPEED: float = 12.0

const STARTING_POSSE: int = 5

@onready var cowboy: Node2D = $Cowboy
@onready var gate: Node2D = $Gate
@onready var posse_label: Label = $UI/PosseCount

# Where the cowboy is being told to go; smoothed in _process().
var target_x: float

# Run-local state (NOT persisted in GameState — posse resets each run).
var posse_count: int = STARTING_POSSE:
	set(value):
		posse_count = maxi(1, value)
		_refresh_posse_label()

func _ready() -> void:
	target_x = cowboy.position.x
	gate.triggered.connect(_on_gate_triggered)
	_refresh_posse_label()

func _process(delta: float) -> void:
	cowboy.position.x = lerpf(cowboy.position.x, target_x, FOLLOW_SPEED * delta)

func _input(event: InputEvent) -> void:
	var new_x := -1.0
	if event is InputEventScreenDrag:
		new_x = (event as InputEventScreenDrag).position.x
	elif event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed:
		new_x = (event as InputEventScreenTouch).position.x
	elif event is InputEventMouseMotion and ((event as InputEventMouseMotion).button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		new_x = (event as InputEventMouseMotion).position.x
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			new_x = mb.position.x
	if new_x >= 0.0:
		target_x = MovementBounds.clamp_x(new_x)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
	elif what == NOTIFICATION_WM_CLOSE_REQUEST:
		get_tree().quit()

func _on_gate_triggered(gate_center_x: float) -> void:
	var side := GateHelper.which_side(cowboy.position.x, gate_center_x)
	posse_count = GateHelper.apply_effect(posse_count, side, gate.left_value, gate.right_value)
	AudioBus.play_gate_pass()
	_pulse_posse_label()

func _refresh_posse_label() -> void:
	if posse_label:
		posse_label.text = "POSSE: %d" % posse_count

# Visual punch when the count changes: scale-pop animation on the label.
# Without this the number just changes silently and the moment doesn't land.
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
