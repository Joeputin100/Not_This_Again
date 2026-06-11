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
		"backdrop": "res://assets/sprites/props/backdrop_frontier.png",
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
		"backdrop": "res://assets/sprites/props/backdrop_mine.png",
		"tint_low": Color(0.34, 0.31, 0.30), "tint_high": Color(0.62, 0.58, 0.54),
		"fog_color": Color(0.72, 0.66, 0.58), "fog_density": 0.024,
		"trail": {"albedo": "res://assets/textures/trail_mine.png", "half_width": 2.6},
		"boardwalk": null, "cliff": null,
		"scatter": [
			{"slug": "ore_crystal", "density": 0.5, "scale": [0.7, 1.3]},
			{"slug": "boulder_choc", "density": 0.5, "scale": [0.7, 1.4]},
			{"slug": "lantern_gumdrop", "density": 0.35, "scale": [0.9, 1.1]},
			{"slug": "mine_portal", "density": 0.12, "scale": [1.4, 1.8], "side": "right"},
			{"slug": "rock_small", "density": 0.5, "scale": [0.5, 1.0]},
		],
	},
	"farm": {
		"ground_albedo": "res://assets/textures/ground_farm.png",
		"ground_normal": "res://assets/textures/ground_farm_n.png",
		"ground_detail": "res://assets/textures/ground_detail.png",
		"ground_uv_tile": 22.0, "macro_strength": 2.0,
		"backdrop": "res://assets/sprites/props/backdrop_farm.png",
		"tint_low": Color(0.34, 0.36, 0.22), "tint_high": Color(0.62, 0.62, 0.40),
		"fog_color": Color(0.80, 0.84, 0.70), "fog_density": 0.016,
		"trail": {"albedo": "res://assets/textures/trail_farm.png", "half_width": 2.6},
		"boardwalk": null, "cliff": null,
		"scatter": [
			{"slug": "candycorn_row", "density": 0.7, "scale": [0.8, 1.3]},
			{"slug": "licorice_fence", "density": 0.45, "scale": [0.9, 1.1]},
			{"slug": "hay_gumdrop", "density": 0.45, "scale": [0.7, 1.2]},
			{"slug": "windmill_lolly", "density": 0.15, "scale": [1.5, 2.0], "side": "right"},
			{"slug": "taffy_trough", "density": 0.25, "scale": [0.8, 1.1]},
			{"slug": "grass_tuft", "density": 1.2, "scale": [0.6, 1.2]},
		],
	},
	"mountain": {
		"ground_albedo": "res://assets/textures/ground_mountain.png",
		"ground_normal": "res://assets/textures/ground_mountain_n.png",
		"ground_detail": "res://assets/textures/ground_detail.png",
		"ground_uv_tile": 24.0, "macro_strength": 1.8, "hill_scale": 1.9,
		"backdrop": "res://assets/sprites/props/backdrop_mountain.png",
		"tint_low": Color(0.62, 0.66, 0.72), "tint_high": Color(0.92, 0.95, 1.0),
		"fog_color": Color(0.86, 0.90, 0.96), "fog_density": 0.030,
		"trail": {"albedo": "res://assets/textures/ground_mountain.png", "half_width": 2.6},
		"boardwalk": null, "puddle_style": "ice",
		"cliff": {"side": "left", "depth": 30.0},
		"scatter": [
			{"slug": "pine_clay", "density": 0.6, "scale": [1.0, 2.0], "side": "right"},
			{"slug": "ice_spire_clay", "density": 0.35, "scale": [0.9, 1.6]},
			{"slug": "boulder_frost_clay", "density": 0.45, "scale": [0.7, 1.4], "side": "right"},
			{"slug": "signpost_cane_clay", "density": 0.18, "scale": [0.9, 1.1]},
			{"slug": "marshmallow_mound_clay", "density": 0.5, "scale": [0.7, 1.3]},
			{"slug": "snow_drift", "density": 0.7, "scale": [0.7, 1.4], "side": "right"},
		],
	},
	"vineyard": {   # L5 (was "vineyard"): Raisin Kidd's vine country. Textures still the
		# badlands set until props task #77 delivers vineyard art.
		"ground_albedo": "res://assets/textures/ground_badlands.png",
		"ground_normal": "res://assets/textures/ground_badlands_n.png",
		"ground_detail": "res://assets/textures/ground_detail.png",
		"ground_uv_tile": 24.0, "macro_strength": 2.6,
		"backdrop": "res://assets/sprites/props/backdrop_badlands.png",
		"tint_low": Color(0.36, 0.30, 0.14), "tint_high": Color(0.84, 0.68, 0.36),
		"fog_color": Color(0.95, 0.82, 0.55), "fog_density": 0.020,
		"trail": {"albedo": "res://assets/textures/trail_badlands.png", "half_width": 2.6},
		"boardwalk": null, "cliff": null,
		"scatter": [
			{"slug": "vine_trellis_clay", "density": 0.65, "scale": [0.9, 1.3], "side": "right"},
			{"slug": "vine_trellis_clay_flip", "density": 0.65, "scale": [0.9, 1.3], "side": "left"},
			{"slug": "wine_barrel_clay", "density": 0.3, "scale": [0.7, 1.0]},
			{"slug": "raisin_crates_clay", "density": 0.3, "scale": [0.7, 1.1]},
			{"slug": "cypress_lolly_clay", "density": 0.35, "scale": [1.2, 1.9]},
			{"slug": "candy_wall_clay", "density": 0.4, "scale": [0.9, 1.2], "side": "right"},
			{"slug": "candy_wall_clay_flip", "density": 0.4, "scale": [0.9, 1.2], "side": "left"},
		],
	},
	"canyon": {
		"ground_albedo": "res://assets/textures/ground_canyon.png",
		"ground_normal": "res://assets/textures/ground_canyon_n.png",
		"ground_detail": "res://assets/textures/ground_detail.png",
		"ground_uv_tile": 24.0, "macro_strength": 2.2, "hill_scale": 1.6,
		"backdrop": "res://assets/sprites/props/backdrop_canyon.png",
		"tint_low": Color(0.10, 0.09, 0.18), "tint_high": Color(0.26, 0.28, 0.48),
		"fog_color": Color(0.20, 0.22, 0.40), "fog_density": 0.030,
		"trail": {"albedo": "res://assets/textures/trail_canyon.png", "half_width": 2.6},
		"boardwalk": null,
		"cliff": {"side": "left", "depth": 30.0},
		"scatter": [
			{"slug": "hoodoo_licorice", "density": 0.45, "scale": [1.0, 1.8], "side": "right"},
			{"slug": "gumdrop_bush_glow", "density": 0.55, "scale": [0.6, 1.1]},
			{"slug": "candy_arch", "density": 0.18, "scale": [1.2, 1.7], "side": "right"},
			{"slug": "star_cactus", "density": 0.45, "scale": [0.8, 1.4]},
			{"slug": "taffy_boulder_moon", "density": 0.4, "scale": [0.7, 1.3]},
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
