class_name TerrainThemes
extends RefCounted

# Per-terrain environment look + the pure terrain math (unit-tested in
# test/test_terrain_themes.gd). Keyed to LevelDef.terrain. "frontier" is the
# fully-authored baseline; mine/farm/mountain are added in phase 3 (until then
# they fall back to frontier via get_theme).
const TERRAIN_THEMES: Dictionary = {
	"frontier": {
		"ground_albedo": "res://assets/textures/dirt_2k.png",
		"ground_detail": "res://assets/textures/ground_detail.png",
		"tint_low": Color(0.50, 0.40, 0.28),    # compacted valley (darker)
		"tint_high": Color(0.86, 0.74, 0.56),   # sun-bleached ridge
		"fog_color": Color(0.96, 0.78, 0.62),    # warm dusty horizon
		"fog_density": 0.018,
	},
}

# Hill profile = sum of sine octaves whose periods all divide HILL_PERIOD, so it
# stays periodic and the static world wraps seamlessly (level_3d wraps the world
# at PATH_PATTERN_LEN == 140). FastNoiseLite would NOT work here — it isn't periodic.
const HILL_PERIOD: float = 140.0

static func get_theme(name: String) -> Dictionary:
	return TERRAIN_THEMES.get(name, TERRAIN_THEMES["frontier"])

static func hill_height(d: float) -> float:
	return (1.10 * sin(d * TAU / 140.0)
		+ 0.55 * sin(d * TAU / 70.0)
		+ 0.30 * sin(d * TAU / 35.0)
		+ 0.16 * sin(d * TAU / 28.0))

# Map a vertex's hill height (-amp..amp) to a valley→ridge albedo-multiplier color.
static func tint(hill_y: float, lo: Color, hi: Color, amp: float) -> Color:
	var t: float = clampf((hill_y + amp) / (2.0 * amp), 0.0, 1.0)
	return lo.lerp(hi, t)

# Low-frequency albedo MULTIPLIER (~0.8..1.15) that varies across the surface to
# break the obvious texture-tile repeat. Periodic in lz (period HILL_PERIOD) so the
# wrapping world stays seamless; gx (lateral) is unconstrained.
static func mottle(gx: float, lz: float) -> float:
	var w: float = lz * TAU / HILL_PERIOD
	var m: float = (sin(gx * 0.43 + w * 3.0)
		+ 0.6 * sin(gx * 0.91 - w * 5.0)
		+ 0.4 * sin(gx * 0.19 + w * 8.0))
	return clampf(1.0 + 0.11 * m, 0.78, 1.16)
