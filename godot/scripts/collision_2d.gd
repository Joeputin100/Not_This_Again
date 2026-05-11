extends RefCounted

# Pure-function rect intersection. Used for bullet ↔ obstacle collision
# detection without spinning up Area2D / CollisionShape2D infrastructure.
# Treats positions as object CENTERS and sizes as full width/height.

# Returns true iff the two axis-aligned rectangles overlap (touching
# counts as overlapping for game-feel — bullets that graze still hit).
static func rects_overlap(a_center: Vector2, a_size: Vector2,
                          b_center: Vector2, b_size: Vector2) -> bool:
	var dx: float = absf(a_center.x - b_center.x)
	var dy: float = absf(a_center.y - b_center.y)
	var sum_half_w: float = (a_size.x + b_size.x) * 0.5
	var sum_half_h: float = (a_size.y + b_size.y) * 0.5
	return dx <= sum_half_w and dy <= sum_half_h
