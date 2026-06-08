extends GutTest

const MangaFx = preload("res://scripts/manga_fx.gd")

var fx

func before_each():
	fx = MangaFx.new()
	add_child_autofree(fx)
	fx.size = Vector2(1080, 1920)
	await get_tree().process_frame

func test_starts_idle():
	assert_false(fx.is_active(), "no effects queued -> idle")

func test_burst_activates_then_expires():
	fx.burst(Vector2(540, 900), "DOON!")
	assert_true(fx.is_active(), "burst makes it active")
	for i in range(120):
		fx._process(0.05)
	assert_false(fx.is_active(), "burst expires")

func test_focus_lines_and_title_card_dont_crash_draw():
	fx.focus_lines(Vector2(540, 900))
	fx.title_card("FIVE-POINT RAISIN\nEXPLODING GUMDROP!")
	fx._process(0.016)
	fx.queue_redraw()
	assert_true(fx.is_active())

func test_gumdrop_countdown_runs_five_to_one():
	fx.gumdrop_countdown(Vector2(540, 1100))
	assert_true(fx.is_active())
	var huge := 0.0
	while fx.is_active() and huge < 60.0:
		fx._process(0.1)
		huge += 0.1
	assert_lt(huge, 60.0, "countdown terminates")

func test_clear_stops_everything():
	fx.focus_lines(Vector2(1, 1))
	fx.burst(Vector2(2, 2), "ZUSH!")
	fx.clear()
	assert_false(fx.is_active(), "clear() empties all effects")
