extends RefCounted

# Pure-function helper that computes follower offsets for a trapezoid
# posse formation. The leader cowboy stays at the origin (0,0); followers
# fan out BEHIND (in +y direction since gates approach from the top of
# the screen) in rows that widen toward the back. Posse reads as a crowd
# pushing forward together, not a single general leading troops — which
# is why we use a trapezoid (wider rear, narrow front) and NOT a pyramid
# (wider front, narrow rear).
#
# Caller passes `posse_count` (total including leader). Result is an
# Array[Vector2] of (posse_count - 1) follower offsets. n=1 returns [].
#
# Row width pattern (front → back): 2, 3, 4, 5, 6, 6, 6, ... (capped at
# MAX_ROW_WIDTH). Rows are filled BACK-TO-FRONT: the rearmost row(s) are
# always full, and the FRONT row (narrowest, nearest leader) may be
# partial. This preserves the trapezoid silhouette even at odd counts —
# the partial row sits inside the wider rows behind it.
#
# Spacing constants are tuned so a 20-person posse fits comfortably in
# the playable width (~920px) without runners overlapping each other
# or clipping into the lane guides.

const HORIZONTAL_SPACING: float = 44.0
const VERTICAL_SPACING: float = 58.0
const MAX_ROW_WIDTH: int = 6

# Returns follower offsets relative to the leader at (0,0). Does NOT
# include the leader itself. For posse_count <= 1, returns empty.
static func compute_positions(posse_count: int) -> Array[Vector2]:
	var positions: Array[Vector2] = []
	var followers: int = posse_count - 1
	if followers <= 0:
		return positions

	# 1) Determine row widths front-to-back: w[i] = min(i + 2, MAX).
	#    Append until cumulative capacity >= followers.
	var widths: Array[int] = []
	var cumulative: int = 0
	var idx: int = 0
	while cumulative < followers:
		var w: int = mini(idx + 2, MAX_ROW_WIDTH)
		widths.append(w)
		cumulative += w
		idx += 1

	# 2) Allocate followers per row. Back rows are FULL; front row holds
	#    the partial remainder. Single-row case: front row = all followers.
	var row_counts: Array[int] = []
	if widths.size() == 1:
		row_counts.append(followers)
	else:
		var back_sum: int = 0
		for j in range(1, widths.size()):
			back_sum += widths[j]
		row_counts.append(followers - back_sum)
		for j in range(1, widths.size()):
			row_counts.append(widths[j])

	# 3) Generate (x, y) offsets per row. Row r sits at y = (r+1)*VSPACE
	#    (so row 0 is one VSPACE behind the leader). Within a row of
	#    nominal width w with k followers, place them in the MIDDLE k of
	#    the w slots — that way a partial front row stays narrower than
	#    the full row behind it (trapezoid preserved).
	for r in range(widths.size()):
		var w_r: int = widths[r]
		var k_r: int = row_counts[r]
		if k_r <= 0:
			continue
		var y_off: float = float(r + 1) * VERTICAL_SPACING
		var slot_start: float = float(w_r - k_r) / 2.0
		var center_offset: float = float(w_r - 1) / 2.0
		for s in range(k_r):
			var slot_idx: float = slot_start + float(s)
			var x_off: float = (slot_idx - center_offset) * HORIZONTAL_SPACING
			positions.append(Vector2(x_off, y_off))

	return positions
