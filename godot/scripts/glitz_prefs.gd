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
	"pulse":            {"pulse_glow": 0.8, "hue_cycle": 0.0, "halo_strength": 0.0, "sparkle_orbit": 0.0, "rotation_mode": 0, "rotation_speed": 0.0},
	"pulse_halo":       {"pulse_glow": 0.8, "hue_cycle": 0.0, "halo_strength": 1.0, "sparkle_orbit": 0.0, "rotation_mode": 0, "rotation_speed": 0.0},
	"pulse_halo_yspin": {"pulse_glow": 0.8, "hue_cycle": 0.0, "halo_strength": 1.0, "sparkle_orbit": 0.5, "rotation_mode": 2, "rotation_speed": 1.5},
	"all_yspin":        {"pulse_glow": 1.2, "hue_cycle": 0.6, "halo_strength": 1.5, "sparkle_orbit": 1.0, "rotation_mode": 2, "rotation_speed": 2.0},
	"all_uvspin":       {"pulse_glow": 1.2, "hue_cycle": 0.6, "halo_strength": 1.5, "sparkle_orbit": 1.0, "rotation_mode": 1, "rotation_speed": 2.5},
}

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

# Convenience: apply a preset's uniforms to a ShaderMaterial in one call.
func apply_preset_to_material(preset: String, mat: ShaderMaterial) -> void:
	if mat == null:
		return
	var data: Dictionary = PRESETS.get(preset, PRESETS[DEFAULT_PRESET])
	for key in data.keys():
		mat.set_shader_parameter(key, data[key])
