class_name TerrainThemes
extends RefCounted

# Per-terrain environment look + the pure terrain math (unit-tested in
# test/test_terrain_themes.gd). Keyed to LevelDef.terrain. "frontier" is the
# fully-authored baseline; mine/farm/mountain are added in phase 3 (until then
# they fall back to frontier via get_theme).
const TERRAIN_THEMES: Dictionary = {
	"frontier": {
		"ground_albedo": "res://assets/textures/ground_frontier.png",
		"ground_normal": "res://assets/textures/ground_frontier_n.png",
		"ground_detail": "res://assets/textures/ground_detail.png",
		"ground_uv_tile": 26.0, "macro_strength": 2.4,
		"tint_low": Color(0.50, 0.40, 0.28), "tint_high": Color(0.86, 0.74, 0.56),
		"fog_color": Color(0.96, 0.78, 0.62), "fog_density": 0.018,
		"trail": {"albedo": "res://assets/textures/trail_frontier.png", "half_width": 2.6},
		"boardwalk": {"side": "right", "albedo": "res://assets/textures/boardwalk_planks.png", "width": 2.2},
		"cliff": null,
		"scatter": [
			{"slug": "grass_tuft", "density": 0.9, "scale": [0.5, 1.0]},
			{"slug": "scrub", "density": 0.5, "scale": [0.6, 1.1]},
			{"slug": "rock_small", "density": 0.4, "scale": [0.5, 1.0]},
			{"slug": "cactus_prickly", "density": 0.25, "scale": [0.8, 1.3]},
			{"slug": "tumbleweed", "density": 0.2, "scale": [0.6, 1.0]},
		],
	},
	"mine": {
		"ground_albedo": "res://assets/textures/ground_mine.png",
		"ground_normal": "res://assets/textures/ground_mine_n.png",
		"ground_detail": "res://assets/textures/ground_detail.png",
		"ground_uv_tile": 24.0, "macro_strength": 2.2,
		"tint_low": Color(0.34, 0.31, 0.30), "tint_high": Color(0.62, 0.58, 0.54),
		"fog_color": Color(0.72, 0.66, 0.58), "fog_density": 0.024,
		"trail": {"albedo": "res://assets/textures/trail_mine.png", "half_width": 2.6},
		"boardwalk": null, "cliff": null,
		"scatter": [
			{"slug": "rock_large", "density": 0.6, "scale": [0.7, 1.4]},
			{"slug": "rock_small", "density": 0.7, "scale": [0.5, 1.0]},
			{"slug": "scrub", "density": 0.3, "scale": [0.5, 0.9]},
		],
	},
	"farm": {
		"ground_albedo": "res://assets/textures/ground_farm.png",
		"ground_normal": "res://assets/textures/ground_farm_n.png",
		"ground_detail": "res://assets/textures/ground_detail.png",
		"ground_uv_tile": 22.0, "macro_strength": 2.0,
		"tint_low": Color(0.34, 0.36, 0.22), "tint_high": Color(0.62, 0.62, 0.40),
		"fog_color": Color(0.80, 0.84, 0.70), "fog_density": 0.016,
		"trail": {"albedo": "res://assets/textures/trail_farm.png", "half_width": 2.6},
		"boardwalk": null, "cliff": null,
		"scatter": [
			{"slug": "grass_tuft", "density": 1.6, "scale": [0.6, 1.2]},
			{"slug": "fence_post", "density": 0.3, "scale": [0.9, 1.1]},
			{"slug": "rock_small", "density": 0.3, "scale": [0.4, 0.8]},
		],
	},
	"mountain": {
		"ground_albedo": "res://assets/textures/ground_mountain.png",
		"ground_normal": "res://assets/textures/ground_mountain_n.png",
		"ground_detail": "res://assets/textures/ground_detail.png",
		"ground_uv_tile": 24.0, "macro_strength": 1.8,
		"tint_low": Color(0.62, 0.66, 0.72), "tint_high": Color(0.92, 0.95, 1.0),
		"fog_color": Color(0.86, 0.90, 0.96), "fog_density": 0.030,
		"trail": {"albedo": "res://assets/textures/ground_mountain.png", "half_width": 2.6},
		"boardwalk": null, "puddle_style": "ice",
		"cliff": {"side": "left", "depth": 30.0},
		"scatter": [
			{"slug": "snow_drift", "density": 0.8, "scale": [0.7, 1.4], "side": "right"},
			{"slug": "pine_tree", "density": 0.5, "scale": [1.0, 2.0], "side": "right"},
			{"slug": "rock_large", "density": 0.4, "scale": [0.6, 1.2], "side": "right"},
		],
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
static func mottle(gx: float, lz: float, strength: float = 1.0) -> float:
	var w: float = lz * TAU / HILL_PERIOD
	var m: float = (sin(gx * 0.43 + w * 3.0)
		+ 0.6 * sin(gx * 0.91 - w * 5.0)
		+ 0.4 * sin(gx * 0.19 + w * 8.0))
	return clampf(1.0 + 0.11 * strength * m, 1.0 - 0.22 * strength, 1.0 + 0.22 * strength)

static func cliff_drop(gx_world: float, trail_half: float, side: String, depth: float) -> float:
	if side == "left" and gx_world < -trail_half:
		return minf((-trail_half - gx_world) * 6.0, depth)
	if side == "right" and gx_world > trail_half:
		return minf((gx_world - trail_half) * 6.0, depth)
	return 0.0

static func scatter_positions(slug_seed: int, cell: int, count: int,
		z0: float, z1: float, x_lo: float, x_hi: float) -> Array:
	var out: Array = []
	var rng := RandomNumberGenerator.new()
	for i in range(count):
		rng.seed = hash([slug_seed, cell, i])
		var z: float = lerpf(z0, z1, rng.randf())
		var x: float = lerpf(x_lo, x_hi, rng.randf())
		if rng.randf() < 0.5:
			x = -x
		out.append(Vector2(x, z))
	return out
