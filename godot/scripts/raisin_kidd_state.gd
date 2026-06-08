class_name RaisinKiddState
extends RefCounted

# Pure combat state machine for the Level-5 boss "Raisin Kidd" — the
# "Untouchable" deflect-and-counter timing fight. Holds NO scene or render
# state; level_3d.gd drives rendering, contact, audio, and the WIN flow from
# the public fields + the event list tick() returns. This is the TerrainThemes
# pattern: pure logic here, unit-tested in GUT headless on CI.
#
# Per-frame contract from level_3d:
#   state.register_fire(n)            # n = posse bullets overlapping the boss this frame
#   var events: Array = state.tick(delta)
#   # react to events (move boss, play VO/FX, drain posse, run win flow)
#
# All durations in seconds; meter is an abstract 0..THRESHOLD scale.

enum Mode { GUARD, WINDUP, FLURRY, RECOVERY, BROKEN, DEAD }

# --- tunables (device-tuned later) ---
const MAX_HP: int = 600
const GUARD_BREAK_FILL_PER_HIT: float = 1.4
const GUARD_BREAK_THRESHOLD: float = 100.0
const GUARD_BREAK_DECAY: float = 22.0
const GUARD_BREAK_OPEN_T: float = 3.0
const DAMAGE_PER_HIT: int = 1
const GOW_INTERVAL_P1: float = 6.0
const GOW_INTERVAL_P2: float = 4.0
const GOW_WINDUP: float = 1.0
const GOW_FLURRY_T: float = 0.6
const GOW_RECOVERY_T: float = 1.5
const WARP_INTERVAL_P1: float = 10.0
const WARP_INTERVAL_P2: float = 7.0
const PHASE2_HP_FRAC: float = 0.5

var hp: int = MAX_HP
var meter: float = 0.0
var mode: int = Mode.GUARD
var phase: int = 1

var _fire_this_frame: int = 0
var _open_t: float = 0.0
var _gow_t: float = GOW_INTERVAL_P1
var _gow_phase_t: float = 0.0
var _warp_t: float = WARP_INTERVAL_P1
var _defeated_emitted: bool = false

func gow_interval() -> float:
	return GOW_INTERVAL_P2 if phase == 2 else GOW_INTERVAL_P1

func warp_interval() -> float:
	return WARP_INTERVAL_P2 if phase == 2 else WARP_INTERVAL_P1

func is_vulnerable() -> bool:
	return mode == Mode.BROKEN or mode == Mode.RECOVERY

func register_fire(n: int) -> void:
	_fire_this_frame += n

func tick(delta: float) -> Array:
	var events: Array = []
	if mode == Mode.DEAD:
		_fire_this_frame = 0
		return events

	var fired: int = _fire_this_frame
	_fire_this_frame = 0

	# apply fire: damage if a window is open, else fill/decay the meter
	if is_vulnerable():
		if fired > 0:
			hp = maxi(0, hp - fired * DAMAGE_PER_HIT)
	elif mode == Mode.GUARD or mode == Mode.WINDUP or mode == Mode.FLURRY:
		if fired > 0:
			meter += fired * GUARD_BREAK_FILL_PER_HIT
		else:
			meter = maxf(0.0, meter - GUARD_BREAK_DECAY * delta)

	# phase transition (one-shot)
	if phase == 1 and hp <= int(MAX_HP * PHASE2_HP_FRAC) and hp > 0:
		phase = 2
		events.append("phase2")
		_gow_t = minf(_gow_t, gow_interval())
		_warp_t = minf(_warp_t, warp_interval())

	# death
	if hp <= 0:
		if not _defeated_emitted:
			_defeated_emitted = true
			mode = Mode.DEAD
			events.append("defeat")
		return events

	# guard-break shatter (only while guarding-ish)
	if (mode == Mode.GUARD or mode == Mode.WINDUP or mode == Mode.FLURRY) \
			and meter >= GUARD_BREAK_THRESHOLD:
		mode = Mode.BROKEN
		_open_t = GUARD_BREAK_OPEN_T
		meter = 0.0
		events.append("guard_shatter")
		return events

	# window countdowns
	if mode == Mode.BROKEN:
		_open_t -= delta
		if _open_t <= 0.0:
			mode = Mode.GUARD
			meter = 0.0
			events.append("guard_reform")
		return events

	if mode == Mode.RECOVERY:
		_open_t -= delta
		if _open_t <= 0.0:
			mode = Mode.GUARD
			events.append("gow_recovery_end")
		return events

	# Grapes of Wrath cycle (progresses only while GUARD-ing)
	if mode == Mode.GUARD:
		_warp_t -= delta
		if _warp_t <= 0.0:
			_warp_t = warp_interval()
			events.append("warp")
		_gow_t -= delta
		if _gow_t <= 0.0:
			mode = Mode.WINDUP
			_gow_phase_t = GOW_WINDUP
			events.append("gow_windup")
		return events

	if mode == Mode.WINDUP:
		_gow_phase_t -= delta
		if _gow_phase_t <= 0.0:
			mode = Mode.FLURRY
			_gow_phase_t = GOW_FLURRY_T
			events.append("gow_flurry")
		return events

	if mode == Mode.FLURRY:
		_gow_phase_t -= delta
		if _gow_phase_t <= 0.0:
			mode = Mode.RECOVERY
			_open_t = GOW_RECOVERY_T
			_gow_t = gow_interval()
			events.append("gow_recovery_open")
		return events

	return events
