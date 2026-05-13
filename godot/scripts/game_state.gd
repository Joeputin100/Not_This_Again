extends Node

# Autoloaded singleton holding run-persistent state. Phase 1 keeps everything
# in memory; phase 2 (procgen + economy) will add save/load via save_data.gd
# but the signal API stays the same — UI components subscribe to these
# signals and re-render automatically.
#
# Tests instantiate this script directly via preload + .new() rather than
# touching the autoload, so test runs don't share state through the
# singleton.
#
# Iter 82: heart regen with disk persistence. Hearts refill 1 per
# REGEN_INTERVAL_S of real time, lazy-computed on every read via
# apply_regen(). _last_spend_unix persists to user://gamestate.cfg so
# a 30-minute wait survives app restart.

signal hearts_changed(new_value: int)
signal bounty_changed(new_value: int)
signal level_changed(new_value: int)

const MAX_HEARTS: int = 5
# Iter 82: 30 minutes per heart regen.
const REGEN_INTERVAL_S: float = 1800.0
const SAVE_PATH: String = "user://gamestate.cfg"

# Iter 82: timestamp when hearts last dropped below MAX. 0 = at full.
var _last_spend_unix: int = 0

var hearts: int = MAX_HEARTS:
	set(value):
		var clamped := clampi(value, 0, MAX_HEARTS)
		if clamped != hearts:
			# Iter 82: stamp last-spend time on drop from MAX.
			if clamped < MAX_HEARTS and hearts == MAX_HEARTS:
				_last_spend_unix = int(Time.get_unix_time_from_system())
			hearts = clamped
			hearts_changed.emit(hearts)
			# Iter 82: persist to disk on every change.
			_save_to_disk()

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
	apply_regen()
	return hearts > 0

# Returns true if the heart was actually deducted. False means the player
# was already out — UI should route to the "out of hearts" screen instead.
func spend_heart() -> bool:
	if hearts <= 0:
		return false
	hearts -= 1
	return true

# Iter 82: lazy heart-regen — call on UI entry. Counts elapsed seconds
# since _last_spend_unix, awards floor(elapsed / REGEN_INTERVAL_S)
# hearts up to MAX. Returns true if any heart was added.
func apply_regen() -> bool:
	if hearts >= MAX_HEARTS:
		_last_spend_unix = 0
		return false
	if _last_spend_unix == 0:
		_last_spend_unix = int(Time.get_unix_time_from_system())
		_save_to_disk()
		return false
	var now: int = int(Time.get_unix_time_from_system())
	var elapsed: int = now - _last_spend_unix
	var earned: int = elapsed / int(REGEN_INTERVAL_S)
	if earned <= 0:
		return false
	var new_hearts: int = mini(hearts + earned, MAX_HEARTS)
	if new_hearts == MAX_HEARTS:
		_last_spend_unix = 0
	else:
		# Shift _last_spend_unix forward by the full intervals consumed
		# so the remainder of the elapsed time isn't lost.
		_last_spend_unix += earned * int(REGEN_INTERVAL_S)
	hearts = new_hearts
	return true

# Seconds until the next heart arrives. 0 if hearts are full.
func seconds_until_next_heart() -> int:
	if hearts >= MAX_HEARTS or _last_spend_unix == 0:
		return 0
	var now: int = int(Time.get_unix_time_from_system())
	var elapsed: int = now - _last_spend_unix
	return maxi(int(REGEN_INTERVAL_S) - (elapsed % int(REGEN_INTERVAL_S)), 0)

# Reset to a fresh-account state. Useful for tests + a future
# "wipe progress" debug menu.
func reset() -> void:
	hearts = MAX_HEARTS
	bounty = 0
	current_level = 1
	_last_spend_unix = 0

# Iter 82: persistence to user://gamestate.cfg. ConfigFile (INI-style)
# is the simplest portable Godot save format. Only ITER 82 persisted
# fields are hearts + _last_spend_unix; bounty + current_level will
# join when their run-persistent semantics are decided.
func _ready() -> void:
	_load_from_disk()

func _save_to_disk() -> void:
	# Iter 82: skip persistence for standalone test instances (autofree
	# instances aren't in the scene tree). Only the autoload at
	# /root/GameState writes to disk.
	if not is_inside_tree():
		return
	var cfg := ConfigFile.new()
	cfg.set_value("hearts", "current", hearts)
	cfg.set_value("hearts", "last_spend_unix", _last_spend_unix)
	cfg.set_value("meta", "bounty", bounty)
	var _err: int = cfg.save(SAVE_PATH)

func _load_from_disk() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var cfg := ConfigFile.new()
	var err: int = cfg.load(SAVE_PATH)
	if err != OK:
		return
	# Directly assign without going through the setter (we don't want
	# to trigger _save_to_disk in a load loop or emit signals before
	# subscribers are wired).
	var saved_hearts: int = int(cfg.get_value("hearts", "current", MAX_HEARTS))
	hearts = clampi(saved_hearts, 0, MAX_HEARTS)
	_last_spend_unix = int(cfg.get_value("hearts", "last_spend_unix", 0))
	bounty = int(cfg.get_value("meta", "bounty", 0))
	# Apply any regen that happened while the app was closed.
	apply_regen()
