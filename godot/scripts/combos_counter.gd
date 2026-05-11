extends RefCounted

# Tiny stateful counter + pure escalation curves for combo feedback.
# `current` increments on each gate pass; static helpers return the
# particle multiplier, trauma value, and label text for any count.
#
# Keeping the curves as static methods means tests can verify them
# without instantiating, and the level can call them inline without
# holding extra references.

const _PARTICLE_BASE: float = 1.0
const _PARTICLE_STEP: float = 0.5     # +50% per combo step
const _PARTICLE_CAP_COMBO: int = 3    # don't keep scaling forever

const _TRAUMA_BASE: float = 0.40
const _TRAUMA_STEP: float = 0.15
const _TRAUMA_CAP_COMBO: int = 4

var current: int = 0

func step() -> int:
	current += 1
	return current

func reset() -> void:
	current = 0

# Visual feedback label for the given combo. Empty string = no label
# (don't celebrate single passes; the existing scale-pop is enough).
static func label_for(combo: int) -> String:
	if combo >= 3:
		return "MEGA!"
	elif combo == 2:
		return "DOUBLE!"
	return ""

# Multiplier on the gate's particle amount. Single pass = 1.0× (no change).
# Combo 2 = 1.5×, combo 3 = 2.0×, capped there.
static func particle_multiplier(combo: int) -> float:
	var capped: int = mini(combo, _PARTICLE_CAP_COMBO)
	return _PARTICLE_BASE + _PARTICLE_STEP * float(capped - 1)

# Trauma value to add to screen shake. Single = 0.40, combo 2 = 0.55,
# combo 3 = 0.70, combo 4 = 0.85, capped.
static func trauma_for(combo: int) -> float:
	var capped: int = mini(combo, _TRAUMA_CAP_COMBO)
	return _TRAUMA_BASE + _TRAUMA_STEP * float(capped - 1)
