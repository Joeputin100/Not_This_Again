extends GutTest

# Verifies level.gd's _equip_bonus() handler applies each bonus effect
# correctly. We exercise the dispatch directly without spawning Bonus
# nodes — those are tested separately (test_bonus.gd, test_barrel_bonus.gd).
# Together they cover the full pipeline: bonus emits → level dispatches →
# stat mutates.

const LevelScene = preload("res://scenes/level.tscn")

var level: Node = null

func before_each():
	level = LevelScene.instantiate()
	add_child_autofree(level)
	# Two frames so @onready vars resolve and _ready completes.
	await get_tree().process_frame
	await get_tree().process_frame

# ---------- fast_fire ----------

func test_fast_fire_reduces_fire_interval_30_pct():
	var before: float = level._gun.fire_interval
	level._equip_bonus("fast_fire")
	# 30% faster → multiplied by 0.7.
	assert_almost_eq(level._gun.fire_interval, before * 0.7, 0.0001,
		"fast_fire should multiply fire_interval by 0.7")

func test_fast_fire_stacks_multiplicatively():
	var before: float = level._gun.fire_interval
	level._equip_bonus("fast_fire")
	level._equip_bonus("fast_fire")
	assert_almost_eq(level._gun.fire_interval, before * 0.7 * 0.7, 0.0001,
		"two fast_fire pickups should compound to 0.49 of original")

# ---------- extra_dude ----------

func test_extra_dude_adds_two_to_posse():
	var before: int = level.posse_count
	level._equip_bonus("extra_dude")
	assert_eq(level.posse_count, before + 2,
		"extra_dude should add 2 to posse_count")

func test_extra_dude_multiple_stacks_linearly():
	var before: int = level.posse_count
	level._equip_bonus("extra_dude")
	level._equip_bonus("extra_dude")
	level._equip_bonus("extra_dude")
	assert_eq(level.posse_count, before + 6,
		"three extra_dude pickups should add 6 dudes total")

# ---------- rifle ----------

func test_rifle_swaps_gun_to_rifle_stats():
	level._equip_bonus("rifle")
	assert_eq(level._gun.display_name, "Rifle")
	assert_eq(level._gun.caliber, 3,
		"rifle has triple-damage rounds")
	assert_eq(level._gun.range_px, 900.0,
		"rifle reaches 50% further than six-shooter")
	assert_almost_eq(level._gun.fire_interval, 0.30, 0.0001,
		"rifle is slower — 0.30s between shots (tradeoff)")
	assert_eq(level._gun.clip_size, 4,
		"rifle clip is small — 4 rounds")
	assert_almost_eq(level._gun.reload_time, 1.3, 0.0001,
		"rifle reload is longer than six-shooter")

func test_rifle_resets_gun_state():
	# Drain a few shots, then pick up rifle — new gun state should be
	# full-clip and not-reloading regardless of prior state.
	for i in 4:
		level._gun_state.fire()
	level._equip_bonus("rifle")
	assert_eq(level._gun_state.ammo(), 4,
		"after rifle pickup, ammo should be at rifle clip_size")
	assert_false(level._gun_state.is_reloading(),
		"new gun state should not be mid-reload")

func test_rifle_state_uses_new_gun():
	level._equip_bonus("rifle")
	# Reach into _gun_state.gun to verify the references are aligned —
	# if the state still pointed at the six-shooter, fires would mismatch
	# the displayed clip.
	assert_eq(level._gun_state.gun, level._gun,
		"_gun_state should reference the new rifle resource")

# ---------- unknown type ----------

func test_unknown_type_does_not_mutate_stats():
	var before_fi: float = level._gun.fire_interval
	var before_posse: int = level.posse_count
	var before_gun: Resource = level._gun
	level._equip_bonus("nonexistent_type")
	assert_eq(level._gun.fire_interval, before_fi)
	assert_eq(level.posse_count, before_posse)
	assert_eq(level._gun, before_gun,
		"unknown type should not swap the gun")

# ---------- signal bridge ----------

func test_on_bonus_equipped_routes_to_equip_bonus():
	# _on_bonus_equipped is the signal handler — it just forwards to
	# _equip_bonus. Verifying the handler exists and dispatches by
	# calling it directly with a known type and checking the side effect.
	var before: int = level.posse_count
	level._on_bonus_equipped("extra_dude")
	assert_eq(level.posse_count, before + 2,
		"_on_bonus_equipped should route to _equip_bonus")
