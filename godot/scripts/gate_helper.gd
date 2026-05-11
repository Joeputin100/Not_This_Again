extends RefCounted

# Pure-function utilities for gate-pass logic. Kept in its own file so
# the math is unit-testable without spinning up a scene tree.

const SIDE_LEFT: int = -1
const SIDE_RIGHT: int = 1

# Gate types. Each gate uses one math operation for BOTH doors.
const TYPE_ADDITIVE: int = 0       # +N / -N display, posse += amount
const TYPE_MULTIPLICATIVE: int = 1 # xN / xM display, posse *= amount

# Given a cowboy's X position and the gate's center X, return which side
# the cowboy is on. Ties (cowboy exactly on the divider) go right; the
# game ships with X clamped to lane bounds so exact-tie is rare anyway.
static func which_side(cowboy_x: float, gate_center_x: float) -> int:
	return SIDE_LEFT if cowboy_x < gate_center_x else SIDE_RIGHT

# Apply a gate effect to the current posse count.
#   side: SIDE_LEFT or SIDE_RIGHT (which door the cowboy passed through)
#   left_value/right_value: the per-door values from gate.tscn @exports
#   gate_type: TYPE_ADDITIVE or TYPE_MULTIPLICATIVE
# Result is clamped to ≥ 1 — a posse of zero isn't a posse, it's a tragedy.
static func apply_effect(posse_count: int, side: int, left_value: int, right_value: int, gate_type: int) -> int:
	var amount: int = left_value if side == SIDE_LEFT else right_value
	var result: int
	if gate_type == TYPE_ADDITIVE:
		result = posse_count + amount
	else:  # TYPE_MULTIPLICATIVE
		result = posse_count * amount
	return maxi(1, result)
