class_name LevelDirector
extends RefCounted

# SP2 slice 2: the pacing brain. Hybrid — PACING events set an authored cruise
# speed; between beats the actual factor eases toward that cruise, DAMPED by
# action intensity (more live enemies => slower, never below SLOW_FLOOR).
# APPROACH_ZONE events halt the world (factor -> 0) while enemies advance on the
# stationary posse, resolving by the zone's authored exit. Pure logic — level_3d
# feeds it (delta, live-enemy count) + reads speed_factor()/world_held().
enum ApproachExit { CLEAR, TIMER, EVENT }

const INTENSITY_FULL_AT: float = 8.0   # enemy count at which cruise is fully damped (matches the camera)
const SLOW_FLOOR: float = 0.35         # busiest cruise multiplier — keep crawling, don't fully stop
const EASE: float = 4.0                # how fast the factor eases toward its target

var cruise: float = 1.0                # authored cruise (1.0 = today's normal scroll)
var _factor: float = 1.0
var _zone_active: bool = false
var _zone_exit: int = ApproachExit.CLEAR
var _zone_timeout: float = 0.0         # safety (CLEAR/EVENT) or duration (TIMER); 0 = none
var _zone_elapsed: float = 0.0
var _event_flag: bool = false

func set_cruise(speed_factor: float) -> void:
	cruise = speed_factor

func enter_zone(exit: int, timeout: float) -> void:
	_zone_active = true
	_zone_exit = exit
	_zone_timeout = timeout
	_zone_elapsed = 0.0
	_event_flag = false

func notify_event() -> void:
	_event_flag = true

# Per-frame. live_enemy_count drives both the reactive damping + the CLEAR exit.
func update(delta: float, live_enemy_count: int) -> void:
	if _zone_active:
		_zone_elapsed += delta
		var resolved := false
		match _zone_exit:
			ApproachExit.CLEAR:
				resolved = live_enemy_count <= 0 or (_zone_timeout > 0.0 and _zone_elapsed >= _zone_timeout)
			ApproachExit.TIMER:
				resolved = _zone_elapsed >= _zone_timeout
			ApproachExit.EVENT:
				resolved = _event_flag or (_zone_timeout > 0.0 and _zone_elapsed >= _zone_timeout)
		if resolved:
			_zone_active = false
		else:
			_factor = lerpf(_factor, 0.0, clampf(EASE * delta, 0.0, 1.0))
			return
	var intensity := clampf(float(live_enemy_count) / INTENSITY_FULL_AT, 0.0, 1.0)
	var target := cruise * lerpf(1.0, SLOW_FLOOR, intensity)
	_factor = lerpf(_factor, target, clampf(EASE * delta, 0.0, 1.0))

func speed_factor() -> float:
	return _factor

func world_held() -> bool:
	return _zone_active
