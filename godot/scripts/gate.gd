extends Node2D

# A math gate. Scrolls down toward the cowboy at scroll_speed.
# Fires exactly once — when its Y position crosses fire_y — with a
# "triggered" signal carrying the gate's X so the level can determine
# which side the cowboy was on.
#
# The gate doesn't know about the cowboy. Level.gd hears the signal and
# applies the effect via GateHelper, so the gate stays a dumb scrolling
# visual that's trivial to clone (multiple gates per level later).

signal triggered(gate_center_x: float)
# Emitted when the gate's effective direction crosses from "shrinking"
# (red) to "growing" (blue) — i.e., when the player has shot the gate
# enough that previously-negative values cross into non-negative
# territory (additive), or into ≥1 territory (multiplicative).
# Level.gd listens for this and confuses any on-screen bulls.
# NOT emitted on the initial _ready paint (initial-snap is silent).
signal direction_flipped(gate)

const GateHelper = preload("res://scripts/gate_helper.gd")

# Gate hit-box for bullet collisions. Roughly matches the visual span
# of the two doors (920 wide, 180 tall).
const SIZE: Vector2 = Vector2(920, 180)

# Door colors. Blue = growing (helpful), red = shrinking (dangerous).
# Tweened between as the gate's effective direction flips (e.g. when
# bullets bump a "-3" door past 0 to become "+1", the whole gate goes
# from red to blue and a future bull hazard would visibly hesitate).
const COLOR_GROWING: Color = Color(0.32, 0.55, 0.92, 0.94)
const COLOR_SHRINKING: Color = Color(0.92, 0.32, 0.32, 0.94)
const COLOR_TWEEN_DURATION: float = 0.22

# 0 = additive (+N/-N), 1 = multiplicative (xN/xM). See gate_helper.gd.
@export var gate_type: int = 0
@export var left_value: int = -3
@export var right_value: int = 10
@export var scroll_speed: float = 280.0  # px/sec; tune on device
@export var fire_y: float = 1480.0  # gate fires when position.y crosses this

var _fired: bool = false
# Tracks whether the gate is currently rendering as "growing" (blue).
# Compared each refresh to decide whether to snap-set the color or
# tween it (so a threshold-crossing color flip gets a visible beat).
var _is_growing: bool = true
# Guards against direction_flipped emission during the _ready() initial
# color snap. Once _ready has finished its first paint, subsequent
# threshold crossings (caused by take_bullet_hit) are real events and
# the signal fires.
var _initial_color_set: bool = false

@onready var _left_label: Label = $LeftDoor/LeftLabel
@onready var _right_label: Label = $RightDoor/RightLabel
@onready var _sparkles: CPUParticles2D = $Sparkles
@onready var _left_door: ColorRect = $LeftDoor
@onready var _right_door: ColorRect = $RightDoor

func _ready() -> void:
	# Update labels to match the @export values. Lets one gate.tscn
	# serve every variant — caller sets left_value/right_value and the
	# UI follows.
	if _left_label:
		_left_label.text = _format_left(left_value)
	if _right_label:
		_right_label.text = _format_right(right_value)
	# Pick blue/red door tint based on the gate's current effective
	# direction. Snap on init (no tween needed for first paint).
	_is_growing = GateHelper.gate_is_growing(left_value, right_value, gate_type)
	var color := COLOR_GROWING if _is_growing else COLOR_SHRINKING
	if _left_door:
		_left_door.color = color
	if _right_door:
		_right_door.color = color
	# Mark initial paint complete. Any future _refresh_color() call that
	# transitions red→blue is now a real mid-game flip and will emit
	# the direction_flipped signal.
	_initial_color_set = true

func _format_left(v: int) -> String:
	if gate_type == GateHelper.TYPE_MULTIPLICATIVE:
		return "x%d" % v
	# Additive: +N for positive, plain -N for negative (sign already there)
	return "+%d" % v if v >= 0 else str(v)

func _format_right(v: int) -> String:
	if gate_type == GateHelper.TYPE_MULTIPLICATIVE:
		return "x%d" % v
	return "+%d" % v if v >= 0 else str(v)

# Called by level.gd's bullet-vs-gate collision pass.
# Returns true if the bullet was consumed (always, currently — bullets
# either bump additive gates or are absorbed by multiplicative gates).
func take_bullet_hit(damage: int = 1) -> bool:
	if _fired:
		return false  # gate already passed; let bullet keep flying
	if gate_type == GateHelper.TYPE_ADDITIVE:
		# Shooting an additive gate makes it MORE GENEROUS by `damage`
		# in each door. Six-shooter (caliber 1): -3 → -2 → -1 → 0 → +1.
		# A future high-caliber gun would walk gates up faster.
		left_value += damage
		right_value += damage
		if _left_label:
			_left_label.text = _format_left(left_value)
		if _right_label:
			_right_label.text = _format_right(right_value)
		_pulse_labels()
		_refresh_color()
	return true

# Re-evaluate the gate's direction (growing or shrinking) and update the
# door tint. When the threshold crosses (red → blue or blue → red),
# tween the color so the moment is visible. When the direction is
# unchanged, do nothing (color is already correct).
func _refresh_color() -> void:
	var now_growing := GateHelper.gate_is_growing(left_value, right_value, gate_type)
	if now_growing == _is_growing:
		return
	# Capture the "red → blue" transition BEFORE we overwrite _is_growing.
	# This is the moment the on-screen bull gets dazed.
	var flipped_to_growing: bool = now_growing and not _is_growing
	_is_growing = now_growing
	var target := COLOR_GROWING if now_growing else COLOR_SHRINKING
	for door in [_left_door, _right_door]:
		if door == null:
			continue
		var t := create_tween()
		t.tween_property(door, "color", target, COLOR_TWEEN_DURATION) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	# Emit AFTER starting the color tween so any listener sees the
	# visual change in progress. Guard on _initial_color_set so the
	# _ready() snap (which doesn't go through this function anyway,
	# but defensively) can never fire this signal.
	if flipped_to_growing and _initial_color_set:
		direction_flipped.emit(self)

func _pulse_labels() -> void:
	for label in [_left_label, _right_label]:
		if not label:
			continue
		label.pivot_offset = label.size / 2.0
		var t := create_tween()
		t.tween_property(label, "scale", Vector2(1.18, 1.18), 0.08) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		t.tween_property(label, "scale", Vector2.ONE, 0.12) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func _process(delta: float) -> void:
	position.y += scroll_speed * delta
	if not _fired and position.y >= fire_y:
		_fired = true
		triggered.emit(position.x)
		_play_pass_animation()

func _play_pass_animation() -> void:
	# Doors fade + shrink. Particles fire independently so the burst
	# doesn't get faded out along with the doors.
	if _sparkles:
		_sparkles.emitting = true
	var tween := create_tween().set_parallel(true)
	tween.tween_property($LeftDoor, "modulate:a", 0.0, 0.35)
	tween.tween_property($RightDoor, "modulate:a", 0.0, 0.35)
	tween.tween_property($LeftDoor, "scale", Vector2(0.85, 0.85), 0.35) \
		.set_trans(Tween.TRANS_BACK) \
		.set_ease(Tween.EASE_IN)
	tween.tween_property($RightDoor, "scale", Vector2(0.85, 0.85), 0.35) \
		.set_trans(Tween.TRANS_BACK) \
		.set_ease(Tween.EASE_IN)
