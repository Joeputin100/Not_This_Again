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
# Emitted when ANY door of this gate transitions from "shrinking" (red)
# to "growing" (blue) — i.e., when the player has shot the door enough
# that its previously-negative value crosses ≥0 (additive), or its
# previously-<1 value crosses ≥1 (multiplicative). Level.gd listens for
# this and confuses any on-screen bulls. NOT emitted on _ready paint.
signal direction_flipped(gate)

const GateHelper = preload("res://scripts/gate_helper.gd")

# Gate hit-box for bullet collisions. Roughly matches the visual span
# of the two doors (920 wide, 180 tall).
const SIZE: Vector2 = Vector2(920, 180)

# Door colors (per-door, iter 25+):
#   blue = this door GROWS the posse (additive ≥0 or multiplicative ≥1)
#   red  = this door SHRINKS the posse (additive <0 or multiplicative <1)
# Each door tints independently so a -3 / +10 additive gate now shows
# left=red, right=blue (rather than the whole gate going red on either
# negative value as in iter 24).
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
# Per-door growing state (iter 25+). Each door is colored based on its
# own value, NOT the gate as a whole. _is_growing (legacy whole-gate
# flag) is kept for any external readers / tests, computed as AND of
# the two doors.
var _left_growing: bool = true
var _right_growing: bool = true
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

# Legacy gate-as-a-whole growing flag — true iff BOTH doors grow.
# Kept for external callers / tests that may still read it.
var _is_growing: bool:
	get:
		return _left_growing and _right_growing

func _ready() -> void:
	# Update labels to match the @export values. Lets one gate.tscn
	# serve every variant — caller sets left_value/right_value and the
	# UI follows.
	if _left_label:
		_left_label.text = _format_left(left_value)
	if _right_label:
		_right_label.text = _format_right(right_value)
	# Per-door initial paint. Snap each door's tint based on its own value.
	_left_growing = GateHelper.door_is_growing(left_value, gate_type)
	_right_growing = GateHelper.door_is_growing(right_value, gate_type)
	if _left_door:
		_left_door.color = COLOR_GROWING if _left_growing else COLOR_SHRINKING
	if _right_door:
		_right_door.color = COLOR_GROWING if _right_growing else COLOR_SHRINKING
	# Mark initial paint complete. Any future flip via take_bullet_hit
	# now emits direction_flipped.
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
#   damage: per-bullet caliber (iter 21+)
#   side: GateHelper.SIDE_LEFT (-1), SIDE_RIGHT (+1), or 0 for legacy
#         "both doors" behavior. Iter 25+: level.gd computes side from
#         bullet.position.x vs gate.position.x so each door is bumped
#         independently. Tests that predate iter 25 pass no side arg
#         and still get the both-doors behavior.
# Returns true if the bullet was consumed (always, currently — bullets
# either bump additive gates or are absorbed by multiplicative gates).
func take_bullet_hit(damage: int = 1, side: int = 0) -> bool:
	if _fired:
		return false  # gate already passed; let bullet keep flying
	if gate_type != GateHelper.TYPE_ADDITIVE:
		return true  # multiplicative gates absorb bullets but don't change
	# Additive gates: bump the appropriate side(s) by `damage`. Six-shooter
	# (caliber 1): -3 → -2 → -1 → 0 → +1 on the door being shot.
	var any_red_to_blue: bool = false
	if side <= 0:  # SIDE_LEFT (-1) or both (0)
		left_value += damage
		if _left_label:
			_left_label.text = _format_left(left_value)
		var was_left_growing := _left_growing
		_left_growing = GateHelper.door_is_growing(left_value, gate_type)
		if _left_growing != was_left_growing:
			_tween_door_color(_left_door, _left_growing)
		if _left_growing and not was_left_growing:
			any_red_to_blue = true
	if side >= 0:  # SIDE_RIGHT (+1) or both (0)
		right_value += damage
		if _right_label:
			_right_label.text = _format_right(right_value)
		var was_right_growing := _right_growing
		_right_growing = GateHelper.door_is_growing(right_value, gate_type)
		if _right_growing != was_right_growing:
			_tween_door_color(_right_door, _right_growing)
		if _right_growing and not was_right_growing:
			any_red_to_blue = true
	_pulse_labels()
	# Emit on red→blue transition of EITHER door so the bull-confuse
	# mechanic still triggers when a previously-dangerous gate becomes
	# helpful. Guard on _initial_color_set so _ready's snap can't fire it.
	if any_red_to_blue and _initial_color_set:
		direction_flipped.emit(self)
	return true

# Tween a single door's color to its target (blue or red). Each door
# fades independently — left can flip red→blue while right stays blue.
func _tween_door_color(door: ColorRect, growing: bool) -> void:
	if door == null:
		return
	var target := COLOR_GROWING if growing else COLOR_SHRINKING
	var t := create_tween()
	t.tween_property(door, "color", target, COLOR_TWEEN_DURATION) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

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
