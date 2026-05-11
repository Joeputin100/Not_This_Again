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

const GateHelper = preload("res://scripts/gate_helper.gd")

# Gate hit-box for bullet collisions. Roughly matches the visual span
# of the two doors (920 wide, 180 tall).
const SIZE: Vector2 = Vector2(920, 180)

# 0 = additive (+N/-N), 1 = multiplicative (xN/xM). See gate_helper.gd.
@export var gate_type: int = 0
@export var left_value: int = -3
@export var right_value: int = 10
@export var scroll_speed: float = 280.0  # px/sec; tune on device
@export var fire_y: float = 1480.0  # gate fires when position.y crosses this

var _fired: bool = false

@onready var _left_label: Label = $LeftDoor/LeftLabel
@onready var _right_label: Label = $RightDoor/RightLabel
@onready var _sparkles: CPUParticles2D = $Sparkles

func _ready() -> void:
	# Update labels to match the @export values. Lets one gate.tscn
	# serve every variant — caller sets left_value/right_value and the
	# UI follows.
	if _left_label:
		_left_label.text = _format_left(left_value)
	if _right_label:
		_right_label.text = _format_right(right_value)

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
func take_bullet_hit() -> bool:
	if _fired:
		return false  # gate already passed; let bullet keep flying
	if gate_type == GateHelper.TYPE_ADDITIVE:
		# Shooting an additive gate makes it MORE GENEROUS by 1 in each
		# door: -3 → -2 → -1 → 0 → +1; +10 → +11 → +12. Encourages the
		# player to weaken penalty doors before passing through.
		left_value += 1
		right_value += 1
		if _left_label:
			_left_label.text = _format_left(left_value)
		if _right_label:
			_right_label.text = _format_right(right_value)
		_pulse_labels()
	return true

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
