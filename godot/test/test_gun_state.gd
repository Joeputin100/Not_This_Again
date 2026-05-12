extends GutTest

const GunScript = preload("res://scripts/gun.gd")
const GunStateScript = preload("res://scripts/gun_state.gd")

# GunState tests use a "fast gun" (zero fire_interval) for most checks
# so we don't have to advance time between shots to empty a clip. Where
# fire_interval matters, we use the default six-shooter.

func _fast_gun() -> Resource:
	var g: Resource = GunScript.new()
	g.fire_interval = 0.0  # no cooldown — fire any time
	g.reload_time = 0.5
	g.clip_size = 6
	return g

func test_starts_with_full_clip():
	var state: RefCounted = GunStateScript.new(_fast_gun())
	assert_eq(state.ammo(), 6)
	assert_false(state.is_reloading())
	assert_true(state.can_fire())

func test_fire_decrements_ammo():
	var state: RefCounted = GunStateScript.new(_fast_gun())
	var fired: bool = state.fire()
	assert_true(fired, "first shot succeeds")
	assert_eq(state.ammo(), 5)

func test_fire_returns_false_when_reloading():
	var state: RefCounted = GunStateScript.new(_fast_gun())
	# Empty the clip — should kick into reload.
	for i in 6:
		state.fire()
	assert_true(state.is_reloading(), "empty clip → reloading")
	assert_false(state.can_fire(), "can't fire mid-reload")
	assert_false(state.fire(), "fire() returns false during reload")

func test_empty_clip_triggers_reload():
	var state: RefCounted = GunStateScript.new(_fast_gun())
	for i in 6:
		state.fire()
	assert_true(state.is_reloading())
	assert_eq(state.ammo(), 0)

func test_reload_completes_after_reload_time():
	var gun: Resource = _fast_gun()
	gun.reload_time = 1.0
	var state: RefCounted = GunStateScript.new(gun)
	for i in 6:
		state.fire()
	# Tick most of the reload — still reloading.
	state.tick(0.5)
	assert_true(state.is_reloading(), "0.5s in, still reloading")
	# Finish it — clip refills, reloading clears.
	state.tick(0.6)
	assert_false(state.is_reloading(), "after 1.1s total, reload done")
	assert_eq(state.ammo(), 6, "clip refilled to full")
	assert_true(state.can_fire())

func test_fire_interval_blocks_rapid_fire():
	var gun: Resource = GunScript.new()  # default six-shooter, 0.18s
	var state: RefCounted = GunStateScript.new(gun)
	state.fire()
	# Cooldown active — can_fire is false until tick advances.
	assert_false(state.can_fire(),
		"can't fire again immediately after a shot — cooldown active")
	state.tick(0.05)
	assert_false(state.can_fire(), "still cooling down at 0.05s")
	state.tick(0.2)
	assert_true(state.can_fire(), "after 0.25s total, cooldown done")

func test_reload_progress_zero_when_not_reloading():
	var state: RefCounted = GunStateScript.new(_fast_gun())
	assert_eq(state.reload_progress(), 0.0)

func test_reload_progress_increases_during_reload():
	var gun: Resource = _fast_gun()
	gun.reload_time = 1.0
	var state: RefCounted = GunStateScript.new(gun)
	for i in 6:
		state.fire()
	assert_eq(state.reload_progress(), 0.0,
		"reload just started, progress 0")
	state.tick(0.5)
	assert_almost_eq(state.reload_progress(), 0.5, 0.01,
		"halfway through reload, progress ~0.5")

func test_consecutive_clips():
	var state: RefCounted = GunStateScript.new(_fast_gun())
	# Empty, reload, fire again — full lifecycle.
	for i in 6:
		state.fire()
	state.tick(1.0)  # reload_time=0.5, this is well past
	assert_eq(state.ammo(), 6)
	var fired: bool = state.fire()
	assert_true(fired, "after reload, can fire again")
	assert_eq(state.ammo(), 5)
