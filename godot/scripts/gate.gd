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

@export var left_value: int = 10    # additive: +N when cowboy passes left
@export var right_value: int = 2    # multiplicative: ×N when cowboy passes right
@export var scroll_speed: float = 280.0  # px/sec; tune on device
@export var fire_y: float = 1480.0  # gate fires when position.y crosses this

var _fired: bool = false

@onready var _left_label: Label = $LeftDoor/LeftLabel
@onready var _right_label: Label = $RightDoor/RightLabel

func _ready() -> void:
	# Update labels to match the @export values. Lets one gate.tscn
	# serve every variant — caller sets left_value/right_value and the
	# UI follows.
	if _left_label:
		_left_label.text = _format_left(left_value)
	if _right_label:
		_right_label.text = _format_right(right_value)

func _format_left(v: int) -> String:
	# +N for adds, plain -N for subtracts (the - is already in the int)
	return "+%d" % v if v >= 0 else str(v)

func _format_right(v: int) -> String:
	return "x%d" % v

func _process(delta: float) -> void:
	position.y += scroll_speed * delta
	if not _fired and position.y >= fire_y:
		_fired = true
		triggered.emit(position.x)
		_play_pass_animation()

func _play_pass_animation() -> void:
	# Subtle "gate consumed" feedback: fade out and shrink as it scrolls
	# off the bottom. Real Candy-Crush polish (particle burst, screen
	# shake) lands in a later commit.
	var tween := create_tween().set_parallel(true)
	tween.tween_property(self, "modulate:a", 0.0, 0.4)
	tween.tween_property(self, "scale", Vector2(0.85, 0.85), 0.4) \
		.set_trans(Tween.TRANS_BACK) \
		.set_ease(Tween.EASE_IN)
