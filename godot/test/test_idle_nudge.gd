extends GutTest

const IdleNudgeScript = preload("res://scripts/idle_nudge.gd")

var nudge: Node

func before_each():
	nudge = autofree(IdleNudgeScript.new())

# ---------- initial state ----------

func test_starts_not_idle():
	assert_false(nudge.is_idle())

func test_starts_with_zero_time():
	assert_eq(nudge.time_since_input(), 0.0)

# ---------- tick behavior ----------

func test_tick_increments_time():
	nudge.tick(0.5)
	assert_almost_eq(nudge.time_since_input(), 0.5, 0.001)

func test_tick_accumulates():
	nudge.tick(0.5)
	nudge.tick(0.5)
	assert_almost_eq(nudge.time_since_input(), 1.0, 0.001)

func test_tick_before_threshold_stays_not_idle():
	nudge.tick(nudge.IDLE_THRESHOLD - 0.1)
	assert_false(nudge.is_idle())

func test_tick_past_threshold_becomes_idle():
	nudge.tick(nudge.IDLE_THRESHOLD + 0.1)
	assert_true(nudge.is_idle())

# ---------- signals ----------

func test_idle_started_emitted_on_crossing_threshold():
	watch_signals(nudge)
	nudge.tick(nudge.IDLE_THRESHOLD + 0.1)
	assert_signal_emitted(nudge, "idle_started")

func test_idle_started_emitted_only_once():
	watch_signals(nudge)
	nudge.tick(nudge.IDLE_THRESHOLD + 0.1)
	nudge.tick(1.0)  # keep ticking past threshold
	nudge.tick(1.0)
	assert_signal_emit_count(nudge, "idle_started", 1)

func test_no_idle_started_below_threshold():
	watch_signals(nudge)
	nudge.tick(nudge.IDLE_THRESHOLD - 0.5)
	assert_signal_not_emitted(nudge, "idle_started")

func test_idle_ended_emitted_when_input_arrives_during_idle():
	nudge.tick(nudge.IDLE_THRESHOLD + 0.1)
	watch_signals(nudge)
	nudge._register_input()
	assert_signal_emitted(nudge, "idle_ended")

func test_idle_ended_not_emitted_when_input_arrives_while_not_idle():
	watch_signals(nudge)
	nudge._register_input()
	assert_signal_not_emitted(nudge, "idle_ended")

# ---------- input clears the clock ----------

func test_input_resets_time():
	nudge.tick(1.5)
	nudge._register_input()
	assert_eq(nudge.time_since_input(), 0.0)

func test_input_clears_idle_state():
	nudge.tick(nudge.IDLE_THRESHOLD + 0.1)
	assert_true(nudge.is_idle())
	nudge._register_input()
	assert_false(nudge.is_idle())

func test_can_cycle_idle_repeatedly():
	# Become idle, get input, become idle again.
	nudge.tick(nudge.IDLE_THRESHOLD + 0.1)
	nudge._register_input()
	watch_signals(nudge)
	nudge.tick(nudge.IDLE_THRESHOLD + 0.1)
	assert_signal_emitted(nudge, "idle_started")
	assert_signal_emit_count(nudge, "idle_started", 1)

# ---------- reset ----------

func test_reset_clears_idle_state_silently():
	nudge.tick(nudge.IDLE_THRESHOLD + 0.1)
	watch_signals(nudge)
	nudge.reset()
	assert_false(nudge.is_idle())
	assert_eq(nudge.time_since_input(), 0.0)
	# Reset must NOT emit idle_ended (it's a test helper, not a state transition)
	assert_signal_not_emitted(nudge, "idle_ended")
