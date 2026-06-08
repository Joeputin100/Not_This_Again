class_name ChickenChaseRun
extends RefCounted

# Pure run-rules for Granny's Chicken Chase. The scene reports catches/stumbles
# and ticks the clock; this owns the tally, the stumble lockout, and the end
# condition. No scene refs — unit-tested in GUT (the RaisinKiddState pattern).

const DURATION: float = 25.0          # allotted seconds (device-tuned)
const FLOCK: int = 8                  # hens in the flock
const STUMBLE_LOCKOUT: float = 0.6    # seconds the cowboy can't lunge after an obstacle

var caught: int = 0
var time_left: float = DURATION
var _stumble_t: float = 0.0
var _over: bool = false

func is_over() -> bool:
	return _over

func can_lunge() -> bool:
	return _stumble_t <= 0.0 and not _over

# Credit a catch (caps at FLOCK). Use register_catch when the scene has already
# decided a catch lands; use try_catch when the run should gate on stumble state.
func register_catch() -> void:
	if _over:
		return
	caught = mini(FLOCK, caught + 1)
	if caught >= FLOCK:
		_finish()

func try_catch() -> bool:
	if not can_lunge():
		return false
	register_catch()
	return true

func stumble() -> void:
	if _over:
		return
	_stumble_t = STUMBLE_LOCKOUT

func tick(delta: float) -> void:
	if _over:
		return
	_stumble_t = maxf(0.0, _stumble_t - delta)
	time_left = maxf(0.0, time_left - delta)
	if time_left <= 0.0:
		_finish()

func _finish() -> void:
	_over = true
	time_left = 0.0
