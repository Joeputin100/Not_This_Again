extends GutTest

# Tests for bull.gd — the boss-tier charging hazard introduced in iter 22c.
# Verifies the state machine (CHARGING ↔ CONFUSED), HP / damage, caliber-
# aware bullet damage, and contact damage values.

const BullScene = preload("res://scenes/bull.tscn")
const BullScript = preload("res://scripts/bull.gd")

var bull: Node2D

func before_each():
	bull = BullScene.instantiate()
	add_child_autofree(bull)
	await get_tree().process_frame

# ---------- initial state ----------

func test_added_to_bulls_group():
	assert_true(bull.is_in_group("bulls"),
		"bull should add itself to 'bulls' group on _ready")

func test_starts_at_max_hp():
	assert_eq(bull.hp, BullScript.MAX_HP)
	assert_eq(BullScript.MAX_HP, 50, "boss-tier HP per design")

func test_hp_label_shows_max_hp():
	var label: Label = bull.get_node("HpLabel")
	assert_eq(label.text, str(BullScript.MAX_HP))

func test_default_state_is_charging():
	assert_eq(bull._state, BullScript.STATE_CHARGING)

# ---------- contact damage ----------

func test_cowboy_damage_charging_is_20():
	assert_eq(bull.get_cowboy_damage(), BullScript.COWBOY_DAMAGE_CHARGING)
	assert_eq(bull.get_cowboy_damage(), 20,
		"charging bull deals 20 (vs barricade's 10)")

func test_cowboy_damage_confused_is_5():
	bull.confuse()
	assert_eq(bull.get_cowboy_damage(), BullScript.COWBOY_DAMAGE_CONFUSED)
	assert_eq(bull.get_cowboy_damage(), 5,
		"confused bull deals 5 (much less than charging)")

func test_charging_damage_higher_than_other_obstacles():
	const BarricadeScript = preload("res://scripts/barricade.gd")
	const TumbleweedScript = preload("res://scripts/tumbleweed.gd")
	assert_gt(bull.get_cowboy_damage(), BarricadeScript.COWBOY_DAMAGE,
		"charging bull > barricade")
	assert_gt(bull.get_cowboy_damage(), TumbleweedScript.COWBOY_DAMAGE,
		"charging bull > tumbleweed")

# ---------- take_bullet_hit ----------

func test_take_bullet_hit_decrements_hp_by_one_default():
	var before: int = bull.hp
	bull.take_bullet_hit()
	assert_eq(bull.hp, before - 1)

func test_take_bullet_hit_always_returns_true():
	assert_true(bull.take_bullet_hit(),
		"bullets are always consumed by the bull's bulk")

func test_take_bullet_hit_caliber_aware():
	# A caliber-5 shot (e.g. shotgun) reduces HP by 5 in one hit.
	var before: int = bull.hp
	bull.take_bullet_hit(5)
	assert_eq(bull.hp, before - 5,
		"take_bullet_hit(5) reduces HP by 5 — caliber-aware")

func test_max_hp_hits_destroys_bull():
	for i in BullScript.MAX_HP:
		bull.take_bullet_hit()
	# After MAX_HP shots, the destroyed signal should have fired and the
	# destroy animation should be in progress.
	assert_lte(bull.hp, 0)

func test_destroyed_signal_fires_at_zero_hp():
	bull.position = Vector2(700, 500)
	watch_signals(bull)
	for i in BullScript.MAX_HP:
		bull.take_bullet_hit()
	assert_signal_emitted_with_parameters(bull, "destroyed", [700.0])

func test_destroyed_signal_does_not_fire_before_zero_hp():
	watch_signals(bull)
	# One shot below MAX should NOT trigger destruction.
	for i in BullScript.MAX_HP - 1:
		bull.take_bullet_hit()
	assert_signal_not_emitted(bull, "destroyed")

func test_overkill_damage_destroys_in_one_hit():
	watch_signals(bull)
	bull.position = Vector2(123, 0)
	bull.take_bullet_hit(BullScript.MAX_HP + 99)
	assert_signal_emitted_with_parameters(bull, "destroyed", [123.0])

# ---------- confuse() ----------

func test_confuse_switches_state_to_confused():
	bull.confuse()
	assert_eq(bull._state, BullScript.STATE_CONFUSED)

func test_confuse_resets_timer():
	bull.confuse()
	assert_almost_eq(bull._confused_timer, BullScript.CONFUSED_DURATION, 0.001)

func test_confuse_picks_left_drift_when_on_left_half():
	# Bull on left side of screen (x < 540) should drift LEFT.
	bull.position = Vector2(200, 0)
	bull.confuse()
	assert_lt(bull._drift_velocity.x, 0.0,
		"bull on left half should drift leftward, got %s" % bull._drift_velocity)

func test_confuse_picks_right_drift_when_on_right_half():
	bull.position = Vector2(800, 0)
	bull.confuse()
	assert_gt(bull._drift_velocity.x, 0.0,
		"bull on right half should drift rightward, got %s" % bull._drift_velocity)

func test_confuse_slows_forward_speed():
	bull.confuse()
	# y component of drift should equal CONFUSED_SPEED (much less than
	# CHARGING_SPEED).
	assert_eq(bull._drift_velocity.y, BullScript.CONFUSED_SPEED)
	assert_lt(bull._drift_velocity.y, BullScript.CHARGING_SPEED,
		"confused bull is slower than charging")

# ---------- _process motion ----------

func test_charging_bull_moves_downward():
	var y_before := bull.position.y
	bull._process(0.1)
	assert_gt(bull.position.y, y_before, "charging bull moves down (+y)")

func test_confused_bull_uses_drift_velocity():
	bull.position = Vector2(800, 0)
	bull.confuse()
	var before := bull.position
	bull._process(0.1)
	assert_ne(bull.position, before,
		"confused bull should move per _drift_velocity")
	# Should be moving right (positive x drift on right half).
	assert_gt(bull.position.x, before.x)

func test_confused_timer_decrements():
	bull.confuse()
	var t0: float = bull._confused_timer
	bull._process(0.5)
	assert_lt(bull._confused_timer, t0,
		"_confused_timer should tick down each process call")

func test_confused_bull_commits_escape_after_duration():
	# After CONFUSED_DURATION expires, the drift velocity is replaced
	# with a 60°-toward-edge escape vector.
	bull.position = Vector2(800, 0)
	bull.confuse()
	var initial_drift := bull._drift_velocity
	# Tick well past the confused-duration boundary.
	bull._process(BullScript.CONFUSED_DURATION + 0.1)
	# After commit, _drift_velocity.x magnitude should be the escape
	# horizontal component (≈ ESCAPE_SPEED * 0.866), much larger than
	# the drift-phase ±40.
	assert_gt(absf(bull._drift_velocity.x), absf(initial_drift.x),
		"escape vector should be steeper sideways than drift")
