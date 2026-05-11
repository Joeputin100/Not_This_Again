extends GutTest

# Smoke test that proves the GUT pipeline is wired up end-to-end:
# 1. Godot loads the project
# 2. GUT framework loads
# 3. Test class extends GutTest correctly
# 4. assert_* methods exist and work
# 5. CI can detect pass/fail
#
# Phase 1+ tests will replace this with real unit tests for GameState,
# input handler, gate effects, etc.

func test_arithmetic_still_works():
	assert_eq(2 + 2, 4, "Basic arithmetic")

func test_godot_version():
	var v := Engine.get_version_info()
	assert_eq(v.major, 4, "Running on Godot 4.x")
	assert_eq(v.minor, 6, "Running on Godot 4.6.x")
