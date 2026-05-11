extends Node

# Autoloaded singleton: tracks "time since last user input" and emits
# idle_started / idle_ended signals when crossing the threshold.
#
# UI elements subscribe to these signals to start/stop their fidget
# animations (scale wobble, rotation jitter, etc) — the Candy Crush
# trick of getting elements to "fidget, sway, and dance" when the user
# isn't touching the screen.
#
# State machine is intentionally simple and testable: tests can call
# `tick(delta)` to advance the clock without waiting in real time.

signal idle_started
signal idle_ended

# How long after the last input event before we declare the user idle.
# Tuned to feel "I haven't touched the screen in a moment" without
# being so short it triggers during a deliberate pause-to-think.
const IDLE_THRESHOLD: float = 2.5

var _time_since_input: float = 0.0
var _is_idle: bool = false

func _process(delta: float) -> void:
	tick(delta)

# Pure state-machine tick. Exposed for tests so they don't have to
# wait real time. Game code calls _process() which calls this.
func tick(delta: float) -> void:
	_time_since_input += delta
	if not _is_idle and _time_since_input >= IDLE_THRESHOLD:
		_is_idle = true
		idle_started.emit()

func _input(event: InputEvent) -> void:
	# Any meaningful input wakes the user up. Listen for everything
	# (touch, drag, mouse, key) so the fidgets stop reliably.
	if (event is InputEventScreenTouch
			or event is InputEventScreenDrag
			or event is InputEventMouseButton
			or event is InputEventMouseMotion
			or event is InputEventKey):
		_register_input()

# Test hook: call directly to mark "user just did something" without
# constructing a fake InputEvent.
func _register_input() -> void:
	_time_since_input = 0.0
	if _is_idle:
		_is_idle = false
		idle_ended.emit()

func is_idle() -> bool:
	return _is_idle

func time_since_input() -> float:
	return _time_since_input

# Test helper: reset to fresh state without firing signals.
func reset() -> void:
	_time_since_input = 0.0
	_is_idle = false
