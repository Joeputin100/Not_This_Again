extends Node

# Iter 132: Persistent glitz/spin preferences per bonus type.
# Autoload — read by level_3d.gd when spawning bonus pickups so the
# user's picker-chosen presets are honored in actual gameplay.
#
# Stored at user://glitz_prefs.cfg as:
#   [bonus_rifle]
#   preset = "pulse_halo_yspin"
#   [bonus_frostbite]
#   preset = "all_yspin"
#   [bonus_frenzy]
#   preset = "all_uvspin"
#
# Defaults to "pulse_halo_yspin" — the middle-ground option that reads
# clearly without overwhelming the scene.

const PREFS_PATH := "user://glitz_prefs.cfg"
const DEFAULT_PRESET := "pulse_halo_yspin"

# Preset library — uniform values applied to the breathing_prop shader.
const PRESETS: Dictionary = {
	"none":             {"pulse_glow": 0.0, "hue_cycle": 0.0, "halo_strength": 0.0, "sparkle_orbit": 0.0, "rotation_mode": 0, "rotation_speed": 0.0},
	"pulse":            {"pulse_glow": 1.0, "hue_cycle": 0.0, "halo_strength": 0.0, "sparkle_orbit": 0.0, "rotation_mode": 0, "rotation_speed": 0.0},
	"pulse_halo":       {"pulse_glow": 1.0, "hue_cycle": 0.0, "halo_strength": 1.2, "sparkle_orbit": 0.0, "rotation_mode": 0, "rotation_speed": 0.0},
	"pulse_halo_yspin": {"pulse_glow": 1.0, "hue_cycle": 0.0, "halo_strength": 1.2, "sparkle_orbit": 0.7, "rotation_mode": 2, "rotation_speed": 0.35},
	"all_yspin":        {"pulse_glow": 1.4, "hue_cycle": 0.6, "halo_strength": 1.5, "sparkle_orbit": 1.0, "rotation_mode": 2, "rotation_speed": 0.45},
	"all_uvspin":       {"pulse_glow": 1.4, "hue_cycle": 0.6, "halo_strength": 1.5, "sparkle_orbit": 1.0, "rotation_mode": 1, "rotation_speed": 0.55},
}

# Iter 135: spin-speed multiplier override saved per bonus. Slider in
# the picker scales each preset's base rotation_speed. Default 1.0 =
# use preset's value as-is. Range 0.1-2.0 in the picker.
const DEFAULT_SPEED_MULT: float = 1.0

# Display order for picker UI (most subtle → most extreme)
const PRESET_ORDER: Array[String] = [
	"none", "pulse", "pulse_halo", "pulse_halo_yspin", "all_yspin", "all_uvspin",
]

const BONUS_TYPES: Array[String] = ["rifle", "frostbite", "frenzy"]

var _config: ConfigFile

func _ready() -> void:
	_config = ConfigFile.new()
	if FileAccess.file_exists(PREFS_PATH):
		_config.load(PREFS_PATH)

func get_preset_for_bonus(bonus_type: String) -> String:
	var section := "bonus_%s" % bonus_type
	return _config.get_value(section, "preset", DEFAULT_PRESET)

func set_preset_for_bonus(bonus_type: String, preset: String) -> void:
	if not PRESETS.has(preset):
		push_warning("unknown glitz preset: %s" % preset)
		return
	var section := "bonus_%s" % bonus_type
	_config.set_value(section, "preset", preset)
	_config.save(PREFS_PATH)

# Iter 135: per-bonus rotation-speed multiplier override.
func get_speed_mult_for_bonus(bonus_type: String) -> float:
	var section := "bonus_%s" % bonus_type
	return _config.get_value(section, "speed_mult", DEFAULT_SPEED_MULT)

func set_speed_mult_for_bonus(bonus_type: String, mult: float) -> void:
	var section := "bonus_%s" % bonus_type
	_config.set_value(section, "speed_mult", mult)
	_config.save(PREFS_PATH)

# Convenience: apply a preset's uniforms to a ShaderMaterial in one call.
func apply_preset_to_material(preset: String, mat: ShaderMaterial, speed_mult: float = 1.0) -> void:
	if mat == null:
		return
	var data: Dictionary = PRESETS.get(preset, PRESETS[DEFAULT_PRESET])
	for key in data.keys():
		var v = data[key]
		if key == "rotation_speed":
			v = float(v) * speed_mult
		mat.set_shader_parameter(key, v)
