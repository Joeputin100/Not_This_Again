class_name WeaponFactory
extends RefCounted

# Iter 56+: factory for candy-Western weapons. Each `build_*` static
# method returns a configured Gun resource. Per-weapon stats live here
# (not in @export defaults) so adding a new weapon is one method + one
# entry in _equip_bonus's match. Keeps gun.gd resource defaults pristine.
#
# Catalog reference: memory/project_weapons_catalog.md.

const GunScript = preload("res://scripts/gun.gd")

# ---- Posse weapons (handheld, any cowboy) ----

static func build_default() -> Resource:
	# Jelly Bean Six-Shooter — the level-start default.
	var g: Resource = GunScript.new()
	g.display_name = "Jelly Bean Six-Shooter"
	return g

static func build_liquorice_whip() -> Resource:
	# Short range, slow swing, hits 3 enemies in a horizontal arc via
	# pierce_count. Infinite clip with long fire interval simulates the
	# "swing slow" feel.
	var g: Resource = GunScript.new()
	g.display_name = "Liquorice Whip"
	g.range_px = 400.0
	g.fire_interval = 0.55
	g.caliber = 2
	g.clip_size = 99  # effectively infinite
	g.reload_time = 0.0
	g.pierce_count = 2  # passes through 2, hits 3rd
	return g

static func build_cotton_candy_rifle() -> Resource:
	# Long range, pinpoint, slow.
	var g: Resource = GunScript.new()
	g.display_name = "Cotton Candy Rifle"
	g.range_px = 1100.0
	g.fire_interval = 0.50
	g.caliber = 2
	g.clip_size = 4
	g.reload_time = 1.2
	return g

static func build_gumdrop_gatling() -> Resource:
	# Blistering DPS, modest range, big clip.
	var g: Resource = GunScript.new()
	g.display_name = "Gumdrop Gatling"
	g.range_px = 550.0
	g.fire_interval = 0.067  # ~15/s
	g.caliber = 1
	g.clip_size = 30
	g.reload_time = 2.2
	return g

static func build_fudgicle_frostbite() -> Resource:
	# Slow enemies 50% for 4s on hit.
	var g: Resource = GunScript.new()
	g.display_name = "Fudgicle Frostbite Pistol"
	g.range_px = 500.0
	g.fire_interval = 0.20
	g.caliber = 1
	g.clip_size = 6
	g.reload_time = 1.0
	g.slow_duration_s = 4.0
	return g

# ---- Siege weapons (heavy, AOE) ----

static func build_jawbreaker_grenades() -> Resource:
	# AOE splash on impact, slow throw, 3 in pouch.
	var g: Resource = GunScript.new()
	g.display_name = "Jawbreaker Grenades"
	g.range_px = 700.0
	g.fire_interval = 0.85
	g.caliber = 3
	g.clip_size = 3
	g.reload_time = 1.6
	g.aoe_radius = 120.0
	return g

static func build_screaming_tnt() -> Resource:
	# Long-range, very slow, huge AOE.
	var g: Resource = GunScript.new()
	g.display_name = "Screaming Red-Hot TNT"
	g.range_px = 950.0
	g.fire_interval = 1.40
	g.caliber = 5
	g.clip_size = 2
	g.reload_time = 2.4
	g.aoe_radius = 180.0
	return g

# ---- Hero-locked weapons ----

static func build_marshmallow_cannon() -> Resource:
	# Marshmallow Sheriff's unique weapon. Huge AOE, slow reload.
	var g: Resource = GunScript.new()
	g.display_name = "Marshmallow Cannon"
	g.range_px = 700.0
	g.fire_interval = 1.10
	g.caliber = 4
	g.clip_size = 3
	g.reload_time = 2.0
	g.aoe_radius = 140.0
	return g

static func build_stun_whinny() -> Resource:
	# Laughing Horse's whinny — no damage, freezes target 2s.
	var g: Resource = GunScript.new()
	g.display_name = "Stun Whinny"
	g.range_px = 600.0
	g.fire_interval = 0.95
	g.caliber = 0  # damage zero — debuff only
	g.clip_size = 99
	g.reload_time = 0.0
	g.freeze_duration_s = 2.0
	return g

# ---- Dispatch helper ----

# Maps a bonus_type / weapon slug string to a built Gun resource. Used
# by level.gd's _equip_bonus when the player picks up a weapon bonus.
# Returns null for unknown slugs (caller should fall through).
static func gun_for_slug(slug: String) -> Resource:
	match slug:
		"default":                return build_default()
		"liquorice_whip":         return build_liquorice_whip()
		"cotton_candy_rifle":     return build_cotton_candy_rifle()
		"gumdrop_gatling":        return build_gumdrop_gatling()
		"fudgicle_frostbite":     return build_fudgicle_frostbite()
		"jawbreaker_grenades":    return build_jawbreaker_grenades()
		"screaming_tnt":          return build_screaming_tnt()
		"marshmallow_cannon":     return build_marshmallow_cannon()
		"stun_whinny":            return build_stun_whinny()
	return null
