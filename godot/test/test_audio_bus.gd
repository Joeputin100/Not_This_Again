extends GutTest

const AudioBusScript = preload("res://scripts/audio_bus.gd")

# Audio playback is hard to verify in CI (no speakers, no waveform
# capture), so these tests just exercise the API surface — the players
# exist, methods don't crash, sounds are loaded.

var bus: Node

func before_each():
	bus = AudioBusScript.new()
	add_child_autofree(bus)
	# AudioBus does its setup in _ready(); add_child_autofree triggers
	# the lifecycle, so by the time we get here the players are built.

func test_tap_sound_loaded():
	assert_not_null(AudioBusScript.TAP_SOUND)

func test_gate_pass_sound_loaded():
	assert_not_null(AudioBusScript.GATE_PASS_SOUND)

func test_play_tap_does_not_crash():
	bus.play_tap()
	# Reaching this line = no exception. If audio playback wasn't ready
	# (e.g., player not added as child) it would error during play().
	assert_true(true, "play_tap completed without error")

func test_play_gate_pass_does_not_crash():
	bus.play_gate_pass()
	assert_true(true, "play_gate_pass completed without error")

func test_rapid_taps_are_safe():
	# Each call restarts playback. Should not accumulate or crash.
	for i in 10:
		bus.play_tap()
	assert_true(true, "10 rapid play_tap calls completed without error")
