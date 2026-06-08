extends GutTest

const RaisinKiddState = preload("res://scripts/raisin_kidd_state.gd")

func _fresh() -> RaisinKiddState:
	return RaisinKiddState.new()

func test_starts_guarding_and_invulnerable():
	var s = _fresh()
	assert_eq(s.mode, RaisinKiddState.Mode.GUARD)
	assert_false(s.is_vulnerable(), "guarding boss is invulnerable")
	assert_eq(s.hp, RaisinKiddState.MAX_HP)

func test_fire_while_guarding_fills_meter_but_deals_no_damage():
	var s = _fresh()
	s.register_fire(10)
	s.tick(0.016)
	assert_eq(s.hp, RaisinKiddState.MAX_HP, "no damage while guarding")
	assert_gt(s.meter, 0.0, "fire fills the guard-break meter")

func test_meter_decays_when_not_hit():
	var s = _fresh()
	s.register_fire(10)
	s.tick(0.016)
	var peak: float = s.meter
	for i in range(120):
		s.tick(0.05)
	assert_lt(s.meter, peak, "meter decays without sustained fire")

func test_sustained_fire_shatters_guard_and_opens_window():
	var s = _fresh()
	var saw_shatter := false
	for i in range(400):
		s.register_fire(20)
		var events: Array = s.tick(0.05)
		if events.has("guard_shatter"):
			saw_shatter = true
			break
	assert_true(saw_shatter, "sustained fire should shatter the guard")
	assert_eq(s.mode, RaisinKiddState.Mode.BROKEN)
	assert_true(s.is_vulnerable(), "broken guard is a damage window")

func test_broken_window_closes_and_reforms():
	var s = _fresh()
	for i in range(400):
		s.register_fire(20)
		if s.tick(0.05).has("guard_shatter"):
			break
	var saw_reform := false
	for i in range(int(RaisinKiddState.GUARD_BREAK_OPEN_T / 0.05) + 5):
		if s.tick(0.05).has("guard_reform"):
			saw_reform = true
			break
	assert_true(saw_reform, "guard reforms after the open window")
	assert_eq(s.mode, RaisinKiddState.Mode.GUARD)
	assert_almost_eq(s.meter, 0.0, 0.001, "meter resets on reform")

func test_damage_only_lands_during_a_window():
	var s = _fresh()
	for i in range(400):
		s.register_fire(20)
		if s.tick(0.05).has("guard_shatter"):
			break
	var before: int = s.hp
	s.register_fire(5)
	s.tick(0.016)
	assert_lt(s.hp, before, "fire during a window deals damage")

func test_grapes_of_wrath_cycles_windup_flurry_recovery():
	var s = _fresh()
	var seen := {}
	for i in range(int((RaisinKiddState.GOW_INTERVAL_P1 + RaisinKiddState.GOW_WINDUP + RaisinKiddState.GOW_RECOVERY_T + 1.0) / 0.05)):
		for e in s.tick(0.05):
			seen[e] = true
	assert_true(seen.has("gow_windup"), "telegraph fires")
	assert_true(seen.has("gow_flurry"), "flurry fires")
	assert_true(seen.has("gow_recovery_open"), "recovery window opens after flurry")

func test_recovery_is_a_vulnerable_window():
	var s = _fresh()
	var hit_recovery := false
	for i in range(2000):
		var events: Array = s.tick(0.05)
		if events.has("gow_recovery_open"):
			hit_recovery = true
			assert_true(s.is_vulnerable(), "recovery is a damage window")
			break
	assert_true(hit_recovery)

func test_warp_fires_on_cadence():
	var s = _fresh()
	var warps := 0
	for i in range(int((RaisinKiddState.WARP_INTERVAL_P1 * 2.5) / 0.05)):
		if s.tick(0.05).has("warp"):
			warps += 1
	assert_gte(warps, 2, "warp should fire ~every WARP_INTERVAL seconds")

func test_phase2_triggers_at_half_hp_and_speeds_up():
	var s = _fresh()
	s.hp = int(RaisinKiddState.MAX_HP * RaisinKiddState.PHASE2_HP_FRAC) + 1
	assert_eq(s.phase, 1)
	s.hp = int(RaisinKiddState.MAX_HP * RaisinKiddState.PHASE2_HP_FRAC) - 1
	var saw_phase2 := false
	for i in range(10):
		if s.tick(0.016).has("phase2"):
			saw_phase2 = true
			break
	assert_true(saw_phase2, "phase 2 triggers below half HP")
	assert_eq(s.phase, 2)
	assert_lt(s.gow_interval(), RaisinKiddState.GOW_INTERVAL_P1, "GoW faster in phase 2")
	assert_lt(s.warp_interval(), RaisinKiddState.WARP_INTERVAL_P1, "warp faster in phase 2")

func test_defeat_emitted_once_at_zero_hp():
	var s = _fresh()
	for i in range(400):
		s.register_fire(20)
		if s.tick(0.05).has("guard_shatter"):
			break
	var defeats := 0
	for i in range(2000):
		s.register_fire(50)
		for e in s.tick(0.05):
			if e == "defeat":
				defeats += 1
		if s.hp <= 0 and defeats >= 1:
			for j in range(20):
				for e2 in s.tick(0.05):
					if e2 == "defeat":
						defeats += 1
			break
	assert_eq(defeats, 1, "defeat emits exactly once")
	assert_eq(s.mode, RaisinKiddState.Mode.DEAD)
