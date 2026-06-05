extends GutTest

const HeartCookieRow = preload("res://scripts/heart_cookie_row.gd")

var row

func before_each():
	row = autofree(HeartCookieRow.new())

func test_set_hearts_records_state():
	row.set_hearts(3, 5)
	assert_eq(row._current, 3)
	assert_eq(row._max, 5)

func test_detects_regen_increase():
	row.set_hearts(2, 5)
	assert_true(row._is_regen(3), "current going up = regen")
	assert_false(row._is_regen(1), "going down is not regen")

func test_lonely_only_at_one():
	assert_true(row._is_lonely(1))
	assert_false(row._is_lonely(2))
	assert_false(row._is_lonely(0))
