extends Node

# Autoloaded singleton holding run-persistent state. Phase 1 keeps everything
# in memory; phase 2 (procgen + economy) will add save/load via save_data.gd
# but the signal API stays the same — UI components subscribe to these
# signals and re-render automatically.
#
# Tests instantiate this script directly via preload + .new() rather than
# touching the autoload, so test runs don't share state through the
# singleton.

signal hearts_changed(new_value: int)
signal bounty_changed(new_value: int)
signal level_changed(new_value: int)

const MAX_HEARTS: int = 5

var hearts: int = MAX_HEARTS:
	set(value):
		var clamped := clampi(value, 0, MAX_HEARTS)
		if clamped != hearts:
			hearts = clamped
			hearts_changed.emit(hearts)

var bounty: int = 0:
	set(value):
		var clamped := maxi(0, value)
		if clamped != bounty:
			bounty = clamped
			bounty_changed.emit(bounty)

var current_level: int = 1:
	set(value):
		var clamped := maxi(1, value)
		if clamped != current_level:
			current_level = clamped
			level_changed.emit(current_level)

func can_play() -> bool:
	return hearts > 0

# Returns true if the heart was actually deducted. False means the player
# was already out — UI should route to the "out of hearts" screen instead.
func spend_heart() -> bool:
	if hearts <= 0:
		return false
	hearts -= 1
	return true

# Reset to a fresh-account state. Useful for tests + a future
# "wipe progress" debug menu.
func reset() -> void:
	hearts = MAX_HEARTS
	bounty = 0
	current_level = 1
