extends GutTest

const GunScript = preload("res://scripts/gun.gd")

# Sanity-check the six-shooter defaults baked into gun.gd. If a designer
# wants to rebalance the starter gun, this test fails and forces an
# intentional update — preventing silent stat drift.

func test_default_display_name():
	var gun := GunScript.new()
	assert_eq(gun.display_name, "Jelly Bean Six-Shooter")

func test_default_range_short():
	var gun := GunScript.new()
	assert_eq(gun.range_px, 600.0,
		"six-shooter has short range so far obstacles can't be hit")

func test_default_fire_interval():
	var gun := GunScript.new()
	# 0.18s ≈ 5.5 shots/sec — matches the pre-iter-21 hardcoded cadence.
	assert_eq(gun.fire_interval, 0.18)

func test_default_caliber_one():
	var gun := GunScript.new()
	assert_eq(gun.caliber, 1)

func test_default_clip_size_six():
	var gun := GunScript.new()
	assert_eq(gun.clip_size, 6,
		"six-shooter cylinder holds 6 rounds")

func test_default_reload_one_second():
	var gun := GunScript.new()
	assert_eq(gun.reload_time, 1.0)

func test_custom_values_override():
	var gun := GunScript.new()
	gun.clip_size = 30
	gun.reload_time = 2.5
	gun.caliber = 3
	assert_eq(gun.clip_size, 30)
	assert_eq(gun.reload_time, 2.5)
	assert_eq(gun.caliber, 3)
