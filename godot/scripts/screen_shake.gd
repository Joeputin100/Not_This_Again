extends RefCounted

# Squirrel-Eiserloh-style trauma shake.
#
#   add_trauma() spikes a 0..1 value.
#   tick(delta) decays it linearly and returns a Vector2 offset whose
#   magnitude is trauma² × max_offset (the squaring makes light shakes
#   imperceptible and big shakes feel heavy).
#
# Pure RefCounted — no SceneTree, no Camera2D dependency, so the math
# is unit-testable. Level.gd holds an instance and applies the offset
# to a Camera2D each frame.

var trauma: float = 0.0
var max_offset: float = 28.0
var decay_per_second: float = 1.6

func add_trauma(amount: float) -> void:
	trauma = clampf(trauma + amount, 0.0, 1.0)

# Advance the shake by delta seconds and return the current offset.
# Pass delta=0 in tests if you want to inspect the offset without
# affecting trauma.
func tick(delta: float) -> Vector2:
	if trauma <= 0.0:
		return Vector2.ZERO
	var magnitude: float = trauma * trauma * max_offset
	var offset := Vector2(
		randf_range(-1.0, 1.0),
		randf_range(-1.0, 1.0)
	) * magnitude
	trauma = maxf(0.0, trauma - decay_per_second * delta)
	return offset

# Test helper — reset state without firing anything.
func reset() -> void:
	trauma = 0.0
