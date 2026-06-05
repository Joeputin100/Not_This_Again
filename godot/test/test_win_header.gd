extends GutTest

# Unit tests for GameState.win_header — the achievement-banner picker for the
# win modal. PRIORITY order (first match wins):
#   1 hits==0           -> FLAWLESS!     teal
#   2 posse_end>=start  -> WHOLE POSSE!  pink
#   3 bounty>=jackpot   -> JACKPOT!      gold
#   4 stars>=3          -> TOP GUMDROP!  purple
#   5 stars==2          -> TRIGGER TREAT! orange
#   6 else              -> SWEET SHOT!   orange

const GameStateScript = preload("res://scripts/game_state.gd")

# Build args that, on their own, would NOT trigger any high-priority branch,
# so each test can isolate the branch it cares about. Defaults: took hits,
# lost posse members, under jackpot, 1 star.
func _h(stars := 1, hits := 3, posse_end := 5, posse_start := 10,
		run_bounty := 100, jackpot := 5000) -> Dictionary:
	return GameStateScript.win_header(stars, hits, posse_end, posse_start, run_bounty, jackpot)

# ---------- each branch in isolation ----------

func test_flawless_on_zero_hits():
	var r = _h(1, 0)
	assert_eq(r["text"], "FLAWLESS!")
	assert_eq(r["color"], Color(0.25, 0.85, 0.75))

func test_whole_posse_when_kept_all():
	var r = _h(1, 3, 10, 10)   # posse_end == posse_start
	assert_eq(r["text"], "WHOLE POSSE!")
	assert_eq(r["color"], Color(1.0, 0.48, 0.66))

func test_whole_posse_when_grew():
	var r = _h(1, 3, 12, 10)   # posse_end > posse_start (deputized)
	assert_eq(r["text"], "WHOLE POSSE!")

func test_jackpot_on_big_bounty():
	var r = _h(1, 3, 5, 10, 6000, 5000)
	assert_eq(r["text"], "JACKPOT!")
	assert_eq(r["color"], Color(1.0, 0.82, 0.25))

func test_top_gumdrop_on_three_stars():
	var r = _h(3, 3, 5, 10, 100, 5000)
	assert_eq(r["text"], "TOP GUMDROP!")
	assert_eq(r["color"], Color(0.69, 0.42, 1.0))

func test_trigger_treat_on_two_stars():
	var r = _h(2, 3, 5, 10, 100, 5000)
	assert_eq(r["text"], "TRIGGER TREAT!")
	assert_eq(r["color"], Color(1.0, 0.62, 0.17))

func test_sweet_shot_fallback_one_star():
	var r = _h(1, 3, 5, 10, 100, 5000)
	assert_eq(r["text"], "SWEET SHOT!")
	assert_eq(r["color"], Color(1.0, 0.62, 0.17))

# ---------- priority order ----------

func test_flawless_beats_three_stars():
	# 0 hits AND 3 stars -> FLAWLESS wins.
	var r = _h(3, 0, 5, 10, 9999, 5000)
	assert_eq(r["text"], "FLAWLESS!")

func test_whole_posse_beats_jackpot_and_stars():
	# kept posse AND jackpot AND 3 stars (but took hits) -> WHOLE POSSE wins.
	var r = _h(3, 2, 10, 10, 9999, 5000)
	assert_eq(r["text"], "WHOLE POSSE!")

func test_jackpot_beats_stars():
	# jackpot AND 3 stars (took hits, lost posse) -> JACKPOT wins.
	var r = _h(3, 2, 5, 10, 9999, 5000)
	assert_eq(r["text"], "JACKPOT!")

func test_three_stars_beats_two():
	var r = _h(3, 2, 5, 10, 100, 5000)
	assert_eq(r["text"], "TOP GUMDROP!")
