extends Node

# Iter 148: persistent prop-sway profile preference.
# Autoload — read by level_3d.gd when spawning breathing props so the
# user's picked sway profile is honored in actual gameplay.
#
# Stored at user://sway_prefs.cfg as:
#   [sway]
#   profile = 2
#
# Profiles (see breathing_prop.gdshader vertex()):
#   0 LEGACY      — iter-130 mobile sway (kept for reference)
#   1 TAP&SETTLE  — periodic sharp tap + damped settle
#   2 BOUNCY      — continuous asymmetric ball-bounce  ← default
#   3 WHIP        — continuous sway + strong top whip
#   4 SPRING POP  — periodic spring + alternating lurch
#   5 GENTLE      — restrained sway + small hop

const PREFS_PATH := "user://sway_prefs.cfg"
const DEFAULT_PROFILE: int = 2

const PROFILE_NAMES: Array[String] = [
	"LEGACY", "TAP & SETTLE", "BOUNCY", "WHIP WOBBLE", "SPRING POP", "GENTLE",
]

var _config: ConfigFile

func _ready() -> void:
	_config = ConfigFile.new()
	if FileAccess.file_exists(PREFS_PATH):
		_config.load(PREFS_PATH)

func get_profile() -> int:
	return int(_config.get_value("sway", "profile", DEFAULT_PROFILE))

func set_profile(profile: int) -> void:
	_config.set_value("sway", "profile", clampi(profile, 0, 5))
	_config.save(PREFS_PATH)
