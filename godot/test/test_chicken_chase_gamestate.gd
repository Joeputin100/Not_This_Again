extends GutTest

const GameStateScript = preload("res://scripts/game_state.gd")

var state

func before_each():
	state = autofree(GameStateScript.new())

# --- proportional reward mapping (pure static) ---
func test_posse_bonus_zero_for_zero_caught():
	assert_eq(GameStateScript.posse_bonus_for(0), 0)

func test_posse_bonus_max_for_full_haul():
	assert_eq(GameStateScript.posse_bonus_for(8), 20)

func test_posse_bonus_is_rounded_proportion():
	assert_eq(GameStateScript.posse_bonus_for(1), 3)
	assert_eq(GameStateScript.posse_bonus_for(3), 8)
	assert_eq(GameStateScript.posse_bonus_for(5), 13)
	assert_eq(GameStateScript.posse_bonus_for(7), 18)

func test_posse_bonus_clamps_out_of_range():
	assert_eq(GameStateScript.posse_bonus_for(-2), 0)
	assert_eq(GameStateScript.posse_bonus_for(99), 20)

# --- 24h gate ---
func test_chase_available_when_never_played():
	assert_true(state.chicken_chase_available(), "available before first play")

func test_chase_unavailable_right_after_spend():
	state.chicken_chase_spend()
	assert_false(state.chicken_chase_available(), "locked immediately after a run begins")

func test_chase_available_again_after_24h():
	state.chicken_chase_spend()
	state.chicken_chase_last_unix -= 24 * 3600 + 1
	assert_true(state.chicken_chase_available(), "re-available after 24h")

func test_seconds_until_chase_decreases_with_time():
	state.chicken_chase_spend()
	var full: int = state.seconds_until_chase()
	state.chicken_chase_last_unix -= 1000
	assert_lt(state.seconds_until_chase(), full)

# --- pending booster ---
func test_award_sets_pending_bonus_from_haul():
	state.chicken_chase_award(6)
	assert_eq(state.pending_posse_bonus, 15)

func test_claim_returns_and_clears_pending_bonus():
	state.chicken_chase_award(8)
	assert_eq(state.claim_posse_bonus(), 20, "claim returns the pending bonus")
	assert_eq(state.pending_posse_bonus, 0, "claim clears it")
	assert_eq(state.claim_posse_bonus(), 0, "second claim is zero")
