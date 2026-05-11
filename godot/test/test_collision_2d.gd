extends GutTest

const Collision2D = preload("res://scripts/collision_2d.gd")

# ---------- clearly overlapping ----------

func test_concentric_rects_overlap():
	assert_true(Collision2D.rects_overlap(
		Vector2.ZERO, Vector2(100, 100),
		Vector2.ZERO, Vector2(50, 50)
	))

func test_partially_overlapping_rects():
	# Both 50x50, centers 30px apart on X → still overlap (25+25=50 > 30)
	assert_true(Collision2D.rects_overlap(
		Vector2(0, 0), Vector2(50, 50),
		Vector2(30, 0), Vector2(50, 50)
	))

# ---------- clearly NOT overlapping ----------

func test_far_apart_rects_dont_overlap():
	assert_false(Collision2D.rects_overlap(
		Vector2(0, 0), Vector2(10, 10),
		Vector2(500, 500), Vector2(10, 10)
	))

func test_horizontally_separate():
	# 10x10 rects centers 100 apart → gap >> sum of half widths (10)
	assert_false(Collision2D.rects_overlap(
		Vector2(0, 0), Vector2(10, 10),
		Vector2(100, 0), Vector2(10, 10)
	))

func test_vertically_separate():
	assert_false(Collision2D.rects_overlap(
		Vector2(0, 0), Vector2(10, 10),
		Vector2(0, 100), Vector2(10, 10)
	))

# ---------- edge cases ----------

func test_touching_edges_counts_as_overlap():
	# 50x50 rects with centers exactly 50 apart — touching but not overlapping
	# in strict geometry. We treat touch as overlap for game-feel.
	assert_true(Collision2D.rects_overlap(
		Vector2(0, 0), Vector2(50, 50),
		Vector2(50, 0), Vector2(50, 50)
	))

func test_bullet_centered_in_barrel():
	# Bullet 8x24 fully inside barrel 120x120
	assert_true(Collision2D.rects_overlap(
		Vector2(540, 1000), Vector2(8, 24),
		Vector2(540, 1000), Vector2(120, 120)
	))

func test_bullet_grazing_barrel_corner():
	# Bullet at (540, 1000), 8x24. Barrel at (480, 940), 120x120.
	# Barrel rect: x ∈ [420, 540], y ∈ [880, 1000]. Bullet center is at
	# the barrel's exact corner. Counts as touching.
	assert_true(Collision2D.rects_overlap(
		Vector2(540, 1000), Vector2(8, 24),
		Vector2(480, 940), Vector2(120, 120)
	))

func test_bullet_just_outside_barrel():
	# Bullet 8x24 at x=605, barrel 120x120 at x=540.
	# Sum of half widths: 4 + 60 = 64. dx = 65. → no overlap.
	assert_false(Collision2D.rects_overlap(
		Vector2(605, 1000), Vector2(8, 24),
		Vector2(540, 1000), Vector2(120, 120)
	))

# ---------- swap-arg symmetry ----------

func test_argument_order_doesnt_matter():
	var a_center := Vector2(100, 200)
	var a_size := Vector2(30, 40)
	var b_center := Vector2(110, 200)
	var b_size := Vector2(20, 20)
	assert_eq(
		Collision2D.rects_overlap(a_center, a_size, b_center, b_size),
		Collision2D.rects_overlap(b_center, b_size, a_center, a_size)
	)
