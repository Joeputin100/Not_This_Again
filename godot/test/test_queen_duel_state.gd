extends GutTest

const QueenDuelState = preload("res://scripts/queen_duel_state.gd")

func _fresh() -> QueenDuelState:
	return QueenDuelState.new()

func test_perfect_trace_scores_high():
	var shape: Array = [Vector2(0,0), Vector2(1,1), Vector2(2,0), Vector2(3,1)]
	assert_gt(QueenDuelState.score_trace(shape, shape.duplicate()), 0.9)

func test_translated_and_scaled_copy_still_scores_high():
	var shape: Array = [Vector2(0,0), Vector2(1,1), Vector2(2,0), Vector2(3,1)]
	var moved: Array = []
	for p in shape:
		moved.append(p * 3.0 + Vector2(100, 50))
	assert_gt(QueenDuelState.score_trace(shape, moved), 0.85)

func test_different_shape_scores_low():
	# main diagonal vs anti-diagonal: both fill the unit box but go opposite ways,
	# so after normalization they are clearly different (~0.09).
	var a: Array = [Vector2(0,0), Vector2(1,1), Vector2(2,2), Vector2(3,3)]
	var b: Array = [Vector2(0,3), Vector2(1,2), Vector2(2,1), Vector2(3,0)]
	assert_lt(QueenDuelState.score_trace(a, b), 0.6)

func test_reversed_trace_scores_lower_than_forward():
	var shape: Array = [Vector2(0,0), Vector2(1,1), Vector2(2,0), Vector2(3,1)]
	var rev: Array = shape.duplicate(); rev.reverse()
	assert_lt(QueenDuelState.score_trace(shape, rev), QueenDuelState.score_trace(shape, shape.duplicate()))

func test_too_few_points_scores_zero():
	assert_eq(QueenDuelState.score_trace([Vector2(0,0)], [Vector2(0,0), Vector2(1,1)]), 0.0)

func test_starts_idle_full_hp():
	var s = _fresh()
	assert_eq(s.hp, QueenDuelState.MAX_HP)
	assert_eq(s.phase, 1)
	assert_false(s.is_over())

func test_tick_opens_a_phrase_then_response_window():
	var s = _fresh()
	var seen := {}
	for i in range(int((QueenDuelState.SING_T + 0.5) / 0.05)):
		for e in s.tick(0.05): seen[e] = true
	assert_true(seen.has("phrase_start"), "she sings")
	assert_true(seen.has("response_open"), "response window opens")
	assert_gt(s.current_contour().size(), 1, "a contour is available to trace")

func test_good_swipe_damages_queen():
	var s = _fresh()
	_advance_to_response(s)
	var before: int = s.hp
	var res: Dictionary = s.submit_swipe(s.current_contour().duplicate())
	assert_true(res["out_sing"], "perfect trace out-sings her")
	assert_lt(s.hp, before, "she takes damage")

func test_bad_swipe_drains_posse_not_hp():
	var s = _fresh()
	_advance_to_response(s)
	var before: int = s.hp
	var res: Dictionary = s.submit_swipe([Vector2(0,0), Vector2(9,9)])
	assert_false(res["out_sing"])
	assert_gt(res["posse_drain"], 0, "a botched answer drains the posse")
	assert_eq(s.hp, before, "no HP damage on a bad answer")

func test_phase2_at_half_hp():
	var s = _fresh()
	s.hp = int(QueenDuelState.MAX_HP * 0.5) - 1
	var saw := false
	for i in range(10):
		if s.tick(0.016).has("phase2"): saw = true; break
	assert_true(saw)
	assert_eq(s.phase, 2)

func test_defeat_to_dead_at_zero_hp():
	var s = _fresh()
	s.hp = 1
	_advance_to_response(s)
	s.submit_swipe(s.current_contour().duplicate())
	for i in range(40):
		s.tick(0.05)
	assert_lte(s.hp, 0)
	assert_eq(s.mode, QueenDuelState.Mode.DEAD)

func test_tutorial_mode_never_drains_or_damages():
	var s = QueenDuelState.new(true)
	_advance_to_response(s)
	var res: Dictionary = s.submit_swipe([Vector2(0,0), Vector2(9,9)])
	assert_eq(res["posse_drain"], 0, "tutorial never penalizes")
	assert_eq(s.hp, QueenDuelState.MAX_HP, "tutorial never damages HP either way")

func _advance_to_response(s) -> void:
	for i in range(int((QueenDuelState.SING_T + 0.1) / 0.02)):
		s.tick(0.02)
		if s.mode == QueenDuelState.Mode.RESPONSE:
			return
