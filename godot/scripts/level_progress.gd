extends RefCounted

# Tiny pure-state class tracking "how many gates left in this run."
# Lives in its own file so we can unit-test the boundary cases (zero
# gates, partial progress, exact completion, over-counting) without
# spinning up a scene.

var gates_total: int = 0
var gates_passed: int = 0

func reset(total: int) -> void:
	gates_total = maxi(0, total)
	gates_passed = 0

func record_pass() -> void:
	gates_passed += 1

# True only when at least one gate existed AND all of them have fired.
# A reset-to-zero state returns false (no run in progress = not complete).
func is_complete() -> bool:
	return gates_total > 0 and gates_passed >= gates_total

func gates_remaining() -> int:
	return maxi(0, gates_total - gates_passed)

func progress_fraction() -> float:
	if gates_total <= 0:
		return 0.0
	return clampf(float(gates_passed) / float(gates_total), 0.0, 1.0)
