extends RefCounted

# Pure-function utilities for gate-pass logic. Kept in its own file so
# the math is unit-testable without spinning up a scene tree.

const SIDE_LEFT: int = -1
const SIDE_RIGHT: int = 1

# Given a cowboy's X position and the gate's center X, return which side
# the cowboy is on. Ties (cowboy exactly on the divider) go right; the
# game ships with X clamped to lane bounds so exact-tie is rare anyway.
static func which_side(cowboy_x: float, gate_center_x: float) -> int:
	return SIDE_LEFT if cowboy_x < gate_center_x else SIDE_RIGHT

# Apply a gate effect to the current posse count. Left door is additive
# (+N), right door is multiplicative (×N). Result is clamped to ≥ 1
# because a posse of zero isn't a posse, it's a tragedy.
static func apply_effect(posse_count: int, side: int, left_value: int, right_value: int) -> int:
	var result: int
	if side == SIDE_LEFT:
		result = posse_count + left_value
	else:
		result = posse_count * right_value
	return maxi(1, result)
