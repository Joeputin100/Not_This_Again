extends GutTest

const JawbreakerState = preload("res://scripts/jawbreaker_state.gd")

func _fresh() -> JawbreakerState:
	return JawbreakerState.new()

func _tick_collect(s, total: float, step: float = 0.1) -> Array:
	var seen: Array = []
	var t := 0.0
	while t < total:
		for e in s.tick(step):
			seen.append(e)
		t += step
	return seen

func test_starts_idle_full_hp():
	var s = _fresh()
	assert_eq(s.hp, JawbreakerState.MAX_HP)
	assert_eq(s.phase, 1)
	assert_false(s.charging)
	assert_false(s.is_over())

func test_charge_then_blast_cycle():
	var s = _fresh()
	var pre: Array = _tick_collect(s, JawbreakerState.BLAST_INTERVAL - JawbreakerState.CHARGE_T - 0.3)
	assert_false(pre.has("charge_start"), "no charge before the wind-up window")
	var mid: Array = _tick_collect(s, 0.6)
	assert_true(mid.has("charge_start"), "charge telegraph fires at CHARGE_T remaining")
	assert_true(s.charging)
	var rel: Array = _tick_collect(s, JawbreakerState.CHARGE_T)
	assert_true(rel.has("blast"), "blast releases after the charge")
	assert_false(s.charging, "cycle resets after release")

func test_cycle_repeats():
	var s = _fresh()
	var seen: Array = _tick_collect(s, JawbreakerState.BLAST_INTERVAL * 2.2)
	var blasts := 0
	for e in seen:
		if e == "blast":
			blasts += 1
	assert_eq(blasts, 2, "one blast per interval")

func test_blast_payload_phase1_freeze_light():
	var s = _fresh()
	var p: Dictionary = s.blast_payload(100)
	assert_eq(p["loss"], 3)
	assert_almost_eq(float(p["freeze"]), 1.5, 0.001)

func test_blast_payload_phase2_chunk():
	var s = _fresh()
	s.apply_damage(JawbreakerState.MAX_HP / 2 + 1)
	assert_eq(s.phase, 2)
	var p: Dictionary = s.blast_payload(100)
	assert_eq(p["loss"], 12, "12% of 100")
	assert_almost_eq(float(p["freeze"]), 0.8, 0.001)
	var small: Dictionary = s.blast_payload(10)
	assert_eq(small["loss"], 4, "floor at loss_min")

func test_phase2_fires_once_and_speeds_cycle():
	var s = _fresh()
	var ev1: Array = s.apply_damage(JawbreakerState.MAX_HP / 2 + 1)
	assert_true(ev1.has("phase2"))
	var ev2: Array = s.apply_damage(1)
	assert_false(ev2.has("phase2"), "phase2 only announced once")
	assert_lt(s.blast_interval(), JawbreakerState.BLAST_INTERVAL, "phase 2 cycles faster")

func test_shed_events_at_thresholds():
	var s = _fresh()
	# 400 -> 299 crosses 0.75 (300)
	var ev: Array = s.apply_damage(101)
	assert_true(ev.has("shed"))
	# 299 -> 199 crosses 0.5 (200): shed AND phase2
	var ev2: Array = s.apply_damage(100)
	assert_true(ev2.has("shed"))
	assert_true(ev2.has("phase2"))
	# big hit crossing 0.25 (100)
	var ev3: Array = s.apply_damage(150)
	assert_true(ev3.has("shed"))

func test_defeat_once_at_zero():
	var s = _fresh()
	var ev: Array = s.apply_damage(JawbreakerState.MAX_HP)
	assert_true(ev.has("defeat"))
	assert_true(s.is_over())
	assert_false(s.apply_damage(5).has("defeat"), "defeat only announced once")

func test_no_ticking_after_death():
	var s = _fresh()
	s.apply_damage(JawbreakerState.MAX_HP)
	assert_eq(s.tick(5.0), [], "dead bosses don't charge")
