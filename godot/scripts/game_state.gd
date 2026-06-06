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

# Tests set this to a temp path; empty = use SAVE_PATH.
var SAVE_PATH_OVERRIDE: String = ""

func _save_path() -> String:
	return SAVE_PATH_OVERRIDE if SAVE_PATH_OVERRIDE != "" else SAVE_PATH

# Iter 82: timestamp when hearts last dropped below MAX. 0 = at full.
var _last_spend_unix: int = 0

# Win/retry flow: per-level best result {level:int -> {stars:int, bounty:int}}.
# Persisted. Drives the map orbs' star display.
var level_best: Dictionary = {}
# Transient (NOT persisted) handoff: set to the level number just won so
# level_select plays the celebration walk on its next _ready, then cleared.
var just_won_level: int = 0
var continue_to_next: bool = false  # transient: after the win celebration, auto-start the next level

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

# Human-readable time until the next heart regenerates ("full in 24:31").
func regen_text() -> String:
	if hearts >= MAX_HEARTS or _last_spend_unix == 0:
		return "full"
	var elapsed: int = int(Time.get_unix_time_from_system()) - _last_spend_unix
	var remain: int = int(REGEN_INTERVAL_S) - (elapsed % int(REGEN_INTERVAL_S))
	return "full in %d:%02d" % [remain / 60, remain % 60]

# Reset to a fresh-account state. Useful for tests + a future
# "wipe progress" debug menu.
func reset() -> void:
	hearts = MAX_HEARTS
	bounty = 0
	current_level = 1
	_last_spend_unix = 0

# Win/retry flow: record a level result, keeping the best stars and bounty.
func record_level_result(level: int, stars: int, run_bounty: int) -> void:
	var prev: Dictionary = level_best.get(level, {"stars": 0, "bounty": 0})
	level_best[level] = {
		"stars": maxi(int(prev["stars"]), stars),
		"bounty": maxi(int(prev["bounty"]), run_bounty),
	}
	_save_to_disk()

# Iter 82: persistence to user://gamestate.cfg. ConfigFile (INI-style)
# is the simplest portable Godot save format. Persisted fields are
# hearts + _last_spend_unix plus current_level + level_best (the
# win/retry progress). bounty stays run-local and is not persisted.
func _ready() -> void:
	_load_from_disk()

func _save_to_disk() -> void:
	# Iter 82: skip persistence for standalone test instances (autofree
	# instances aren't in the scene tree). Only the autoload at
	# /root/GameState writes to disk. Win/retry flow: tests may opt into
	# persistence by setting SAVE_PATH_OVERRIDE to a temp path.
	if not is_inside_tree() and SAVE_PATH_OVERRIDE == "":
		return
	var cfg := ConfigFile.new()
	cfg.set_value("hearts", "current", hearts)
	cfg.set_value("hearts", "last_spend_unix", _last_spend_unix)
	cfg.set_value("meta", "bounty", bounty)
	cfg.set_value("meta", "current_level", current_level)
	cfg.set_value("meta", "level_best", level_best)
	var _err: int = cfg.save(_save_path())

func _load_from_disk() -> void:
	if not FileAccess.file_exists(_save_path()):
		return
	var cfg := ConfigFile.new()
	if cfg.load(_save_path()) != OK:
		return
	# NOTE: hearts/bounty have setters, so these assignments DO run through them
	# (one redundant _save_to_disk on load — benign, since we load before any
	# subscribers are wired so no stale signals are acted on).
	hearts = clampi(int(cfg.get_value("hearts", "current", MAX_HEARTS)), 0, MAX_HEARTS)
	_last_spend_unix = int(cfg.get_value("hearts", "last_spend_unix", 0))
	bounty = int(cfg.get_value("meta", "bounty", 0))
	current_level = maxi(1, int(cfg.get_value("meta", "current_level", 1)))
	level_best = cfg.get_value("meta", "level_best", {})
	# Apply any regen that happened while the app was closed.
	apply_regen()

# Winflow: pick the achievement-header banner for a win, by PRIORITY (first
# match wins). Returns {"text": String, "color": Color}. The caller computes
# jackpot_threshold (typically star_thresholds[2] * 1.5). Pure + testable.
static func win_header(stars: int, hits: int, posse_end: int, posse_start: int,
		run_bounty: int, jackpot_threshold: int) -> Dictionary:
	if hits == 0:
		return {"text": "FLAWLESS!", "color": Color(0.25, 0.85, 0.75)}
	if posse_end >= posse_start:
		return {"text": "WHOLE POSSE!", "color": Color(1.0, 0.48, 0.66)}
	if run_bounty >= jackpot_threshold:
		return {"text": "JACKPOT!", "color": Color(1.0, 0.82, 0.25)}
	if stars >= 3:
		return {"text": "TOP GUMDROP!", "color": Color(0.69, 0.42, 1.0)}
	if stars == 2:
		return {"text": "TRIGGER TREAT!", "color": Color(1.0, 0.62, 0.17)}
	return {"text": "SWEET SHOT!", "color": Color(1.0, 0.62, 0.17)}

# Win/retry flow: stars (1..3) earned for a run's bounty against ascending
# thresholds. A win always grants >= 1 star; result is clamped to 3.
static func stars_for(run_bounty: int, thresholds: Array) -> int:
	var n: int = 1
	for t in thresholds:
		if run_bounty >= int(t):
			n = maxi(n, 1 + thresholds.find(t))
	return clampi(n, 1, 3)
