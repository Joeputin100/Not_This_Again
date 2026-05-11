extends GutTest

# Unit tests for GameState. Tests load the script directly and create a
# fresh instance per test (autofree handles cleanup), so we never read or
# mutate the autoloaded singleton.

const GameStateScript = preload("res://scripts/game_state.gd")

var state: Node

func before_each():
	state = autofree(GameStateScript.new())

# ---------- defaults ----------

func test_starts_with_max_hearts():
	assert_eq(state.hearts, state.MAX_HEARTS)

func test_starts_with_zero_bounty():
	assert_eq(state.bounty, 0)

func test_starts_at_level_one():
	assert_eq(state.current_level, 1)

func test_can_play_at_start():
	assert_true(state.can_play())

# ---------- hearts ----------

func test_spend_heart_decrements():
	state.spend_heart()
	assert_eq(state.hearts, state.MAX_HEARTS - 1)

func test_spend_heart_returns_true_when_available():
	assert_true(state.spend_heart())

func test_spend_heart_returns_false_at_zero():
	state.hearts = 0
	assert_false(state.spend_heart())

func test_spend_heart_does_not_go_negative():
	state.hearts = 0
	state.spend_heart()
	assert_eq(state.hearts, 0)

func test_hearts_clamped_to_max():
	state.hearts = 99
	assert_eq(state.hearts, state.MAX_HEARTS)

func test_hearts_clamped_to_zero():
	state.hearts = -3
	assert_eq(state.hearts, 0)

func test_cannot_play_at_zero_hearts():
	state.hearts = 0
	assert_false(state.can_play())

# ---------- bounty ----------

func test_bounty_increases_via_assignment():
	state.bounty = 50
	assert_eq(state.bounty, 50)

func test_bounty_clamped_to_zero():
	state.bounty = -5
	assert_eq(state.bounty, 0)

# ---------- level ----------

func test_level_clamped_to_minimum_one():
	state.current_level = 0
	assert_eq(state.current_level, 1)
	state.current_level = -5
	assert_eq(state.current_level, 1)

# ---------- signals ----------

func test_hearts_changed_signal_fires():
	watch_signals(state)
	state.hearts = 2
	assert_signal_emitted_with_parameters(state, "hearts_changed", [2])

func test_hearts_changed_no_emit_when_same_value():
	watch_signals(state)
	state.hearts = state.hearts  # no change
	assert_signal_not_emitted(state, "hearts_changed")

func test_bounty_changed_signal_fires():
	watch_signals(state)
	state.bounty = 100
	assert_signal_emitted_with_parameters(state, "bounty_changed", [100])

func test_level_changed_signal_fires():
	watch_signals(state)
	state.current_level = 5
	assert_signal_emitted_with_parameters(state, "level_changed", [5])

# ---------- reset ----------

func test_reset_restores_defaults():
	state.hearts = 1
	state.bounty = 999
	state.current_level = 47
	state.reset()
	assert_eq(state.hearts, state.MAX_HEARTS)
	assert_eq(state.bounty, 0)
	assert_eq(state.current_level, 1)
