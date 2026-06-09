extends GutTest
const SingDuelFx = preload("res://scripts/sing_duel_fx.gd")
var fx
func before_each():
	fx = SingDuelFx.new()
	add_child_autofree(fx)
	fx.size = Vector2(1080, 1920)
	await get_tree().process_frame

func test_show_contour_makes_it_active():
	fx.show_contour([Vector2(0,0), Vector2(1,1), Vector2(2,0)])
	assert_true(fx.is_active())

func test_open_response_captures_swipe_points():
	fx.show_contour([Vector2(0,0), Vector2(1,1)])
	fx.open_response()
	fx.feed_point(Vector2(100, 100))
	fx.feed_point(Vector2(120, 90))
	var pts: Array = fx.end_response()
	assert_eq(pts.size(), 2, "captured the fed swipe points")

func test_clear_resets():
	fx.show_contour([Vector2(0,0), Vector2(1,1)])
	fx.clear()
	assert_false(fx.is_active())

func test_flash_does_not_crash():
	fx.out_sing_flash(Vector2(500, 800))
	fx.high_note_flash(Vector2(500, 800))
	fx._process(0.016)
	assert_true(true)
