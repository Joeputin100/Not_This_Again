extends GutTest

# Unit tests for posse_formation.gd — pure helper, no scene tree needed.
# Verifies that the trapezoid shape holds (rear rows wider than front),
# offset counts match (posse_count - 1) followers, and the partial
# front row stays narrower than any full row behind it.

const PosseFormation = preload("res://scripts/posse_formation.gd")

# ---------- count of followers returned ----------

func test_n1_returns_empty_array():
	var positions: Array[Vector2] = PosseFormation.compute_positions(1)
	assert_eq(positions.size(), 0, "n=1 (leader only) should produce 0 followers")

func test_n2_returns_one_follower():
	var positions: Array[Vector2] = PosseFormation.compute_positions(2)
	assert_eq(positions.size(), 1, "n=2 → 1 follower")

func test_n5_returns_four_followers():
	var positions: Array[Vector2] = PosseFormation.compute_positions(5)
	assert_eq(positions.size(), 4, "n=5 → 4 followers")

func test_n10_returns_nine_followers():
	var positions: Array[Vector2] = PosseFormation.compute_positions(10)
	assert_eq(positions.size(), 9, "n=10 → 9 followers")

func test_n20_returns_nineteen_followers():
	var positions: Array[Vector2] = PosseFormation.compute_positions(20)
	assert_eq(positions.size(), 19, "n=20 → 19 followers")

# ---------- positions are behind the leader (y > 0) ----------

func test_all_followers_behind_leader():
	# Every follower offset.y should be strictly positive (behind leader,
	# since gates approach from the top → leader faces -y → posse trails +y).
	for n in [2, 5, 10, 20]:
		var positions: Array[Vector2] = PosseFormation.compute_positions(n)
		for p in positions:
			assert_gt(p.y, 0.0,
				"n=%d: follower at %s should have y > 0 (behind leader)" % [n, p])

# ---------- trapezoid shape: rear rows wider than (or equal to) front ----------

func test_trapezoid_shape_n10():
	# Group followers by y (row), compute width per row = max(x) - min(x),
	# verify monotonic non-decreasing front-to-back.
	var positions: Array[Vector2] = PosseFormation.compute_positions(10)
	var widths_per_row: Array[float] = _row_widths(positions)
	# At least 2 rows for n=10.
	assert_gte(widths_per_row.size(), 2,
		"n=10 should produce multiple rows, got %d" % widths_per_row.size())
	# Each subsequent row should be >= the previous (trapezoid widens).
	for i in range(1, widths_per_row.size()):
		assert_gte(widths_per_row[i], widths_per_row[i - 1],
			"row %d width %.1f should be >= row %d width %.1f (trapezoid)" % [
				i, widths_per_row[i], i - 1, widths_per_row[i - 1]
			])

func test_trapezoid_shape_n20():
	var positions: Array[Vector2] = PosseFormation.compute_positions(20)
	var widths_per_row: Array[float] = _row_widths(positions)
	assert_gte(widths_per_row.size(), 3,
		"n=20 should produce >= 3 rows, got %d" % widths_per_row.size())
	for i in range(1, widths_per_row.size()):
		assert_gte(widths_per_row[i], widths_per_row[i - 1],
			"row %d should be >= row %d for trapezoid shape" % [i, i - 1])

# ---------- offsets are within reasonable bounds ----------

func test_max_x_offset_bounded_n20():
	# At n=20 (max row width 6), half-width is 5 * H_SPACING / 2 = ~110px.
	# Allow 240px (generous) so we don't fail on future tuning bumps.
	var positions: Array[Vector2] = PosseFormation.compute_positions(20)
	for p in positions:
		assert_lt(absf(p.x), 240.0,
			"x offset %.1f exceeds 240px bound at n=20" % p.x)

func test_max_y_offset_bounded_n20():
	# At n=20 (~5 rows), max y = 5 * VERTICAL_SPACING = 290px.
	# Allow 500px bound to absorb tuning.
	var positions: Array[Vector2] = PosseFormation.compute_positions(20)
	for p in positions:
		assert_lt(p.y, 500.0,
			"y offset %.1f exceeds 500px bound at n=20" % p.y)

# ---------- partial front row stays narrower than full rows behind ----------

func test_n5_front_row_narrower_than_rear():
	# n=5: 4 followers. Algorithm produces row 0 (front) partial = 1, row 1 = 3.
	# The front row's effective width (1 follower → 0) should be < rear row width.
	var positions: Array[Vector2] = PosseFormation.compute_positions(5)
	var widths_per_row: Array[float] = _row_widths(positions)
	assert_lte(widths_per_row[0], widths_per_row[widths_per_row.size() - 1],
		"front row width %.1f should be <= rear row width %.1f" % [
			widths_per_row[0], widths_per_row[widths_per_row.size() - 1]
		])

func test_n2_single_follower_centered():
	# n=2 has 1 follower → should land roughly at x=0 (centered behind leader).
	var positions: Array[Vector2] = PosseFormation.compute_positions(2)
	assert_eq(positions.size(), 1)
	assert_almost_eq(positions[0].x, 0.0, 1.0,
		"single follower should be centered behind leader, got x=%.2f" % positions[0].x)

# ---------- positions are unique (no overlap) ----------

func test_no_duplicate_positions_n20():
	var positions: Array[Vector2] = PosseFormation.compute_positions(20)
	for i in range(positions.size()):
		for j in range(i + 1, positions.size()):
			assert_ne(positions[i], positions[j],
				"duplicate position at indices %d and %d: %s" % [i, j, positions[i]])

# ---------- helper ----------

# Groups positions by y-coordinate (rounded to nearest int to absorb
# float jitter) and returns an Array[float] of row widths (max_x - min_x)
# ordered front-to-back.
func _row_widths(positions: Array[Vector2]) -> Array[float]:
	# Map y → Array[float] of x values.
	var rows: Dictionary = {}
	for p in positions:
		var key: int = int(round(p.y))
		if not rows.has(key):
			rows[key] = []
		rows[key].append(p.x)
	# Sort keys ascending (front=smallest y, back=largest y).
	var keys: Array = rows.keys()
	keys.sort()
	var widths: Array[float] = []
	for k in keys:
		var xs: Array = rows[k]
		var min_x: float = xs[0]
		var max_x: float = xs[0]
		for x in xs:
			if x < min_x:
				min_x = x
			if x > max_x:
				max_x = x
		widths.append(max_x - min_x)
	return widths
