extends GutTest

const L3D = preload("res://scripts/level_3d.gd")

# --- cage damage: Kimmy's cage only takes damage from rainbow bullets ---
func test_cage_takes_rainbow_damage():
	assert_eq(L3D.kimmy_cage_damage(true, true, 5), 5)   # is_kimmy, bullet_rainbow, base
func test_cage_ignores_nonrainbow_on_kimmy():
	assert_eq(L3D.kimmy_cage_damage(true, false, 5), 0)
func test_noncage_captive_takes_any_damage():
	assert_eq(L3D.kimmy_cage_damage(false, false, 5), 5)  # a normal captive is unaffected by the rule

# --- rescue outcome: cracked vs timed_out vs ongoing ---
func test_rescue_cracked_when_hp_zero():
	assert_eq(L3D.kimmy_rescue_outcome(0, 4.0), "cracked")
func test_rescue_timed_out_when_window_elapsed():
	assert_eq(L3D.kimmy_rescue_outcome(50, 0.0), "timed_out")
func test_rescue_ongoing():
	assert_eq(L3D.kimmy_rescue_outcome(50, 4.0), "ongoing")
func test_rescue_cracked_beats_timeout():
	assert_eq(L3D.kimmy_rescue_outcome(0, 0.0), "cracked")  # freeing at the buzzer still counts

# --- screen-clear targets: outlaws + destructible obstacles incl bulls, never the cage ---
func test_clear_includes_outlaw_and_bull():
	assert_true(L3D.kimmy_clears_node({"is_outlaw": true}))
	assert_true(L3D.kimmy_clears_node({"is_bull": true}))
	assert_true(L3D.kimmy_clears_node({}))   # a plain destructible obstacle (no special meta)
func test_clear_excludes_cage_and_captive():
	assert_false(L3D.kimmy_clears_node({"is_captive": true}))
	assert_false(L3D.kimmy_clears_node({"is_kimmy": true}))
	assert_false(L3D.kimmy_clears_node({"dying": true}))
