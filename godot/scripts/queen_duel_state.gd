class_name QueenDuelState
extends RefCounted

# Pure call-and-response sing-duel logic for the Level-6 boss, Queen of the
# Night. Holds NO scene/render state; level_3d.gd drives rendering, swipe
# capture, audio, and WIN/FAIL from the public fields + the event list tick()
# returns. The RaisinKiddState pattern — unit-tested in GUT headless on CI.

enum Mode { IDLE, SINGING, RESPONSE, RESOLVE, DEAD }

const MAX_HP: int = 600
const SING_T: float = 1.6
const RESPONSE_T: float = 2.2
const RESOLVE_T: float = 0.8
const GOOD_THRESHOLD: float = 0.62
const HIT_DAMAGE: int = 60
const MISS_DRAIN: int = 3
const MATCH_TOLERANCE: float = 0.55
const RESAMPLE_N: int = 16
const PHASE2_HP_FRAC: float = 0.5

const PHRASES: Array = [
	[Vector2(0,2), Vector2(1,0), Vector2(2,0), Vector2(3,2)],
	[Vector2(0,3), Vector2(1,2), Vector2(2,1), Vector2(3,0)],
	[Vector2(0,3), Vector2(1,0), Vector2(2,3), Vector2(3,0), Vector2(4,3), Vector2(5,0)],
]

var hp: int = MAX_HP
var phase: int = 1
var mode: int = Mode.IDLE
var tutorial: bool = false

var _t: float = 0.0
var _phrase_i: int = 0
var _defeated: bool = false

func _init(is_tutorial: bool = false) -> void:
	tutorial = is_tutorial

func is_over() -> bool:
	return mode == Mode.DEAD

func current_contour() -> Array:
	return PHRASES[_phrase_i % PHRASES.size()]

static func score_trace(target: Array, swipe: Array) -> float:
	if target.size() < 2 or swipe.size() < 2:
		return 0.0
	var a: Array = _normalize(_resample(target, RESAMPLE_N))
	var b: Array = _normalize(_resample(swipe, RESAMPLE_N))
	var d: float = 0.0
	for i in range(RESAMPLE_N):
		d += (a[i] as Vector2).distance_to(b[i])
	d /= float(RESAMPLE_N)
	return clampf(1.0 - d / MATCH_TOLERANCE, 0.0, 1.0)

static func _resample(pts: Array, n: int) -> Array:
	var total: float = 0.0
	for i in range(pts.size() - 1):
		total += (pts[i] as Vector2).distance_to(pts[i + 1])
	if total <= 0.0:
		var flat: Array = []
		for i in range(n): flat.append(pts[0])
		return flat
	var step: float = total / float(n - 1)
	var out: Array = [pts[0]]
	var acc: float = 0.0
	var i: int = 0
	var cur: Vector2 = pts[0]
	while out.size() < n and i < pts.size() - 1:
		var seg: float = cur.distance_to(pts[i + 1])
		if acc + seg >= step:
			var t: float = (step - acc) / seg
			cur = cur.lerp(pts[i + 1], t)
			out.append(cur)
			acc = 0.0
		else:
			acc += seg
			cur = pts[i + 1]
			i += 1
	while out.size() < n:
		out.append(pts[pts.size() - 1])
	return out

static func _normalize(pts: Array) -> Array:
	var mn := Vector2(INF, INF)
	var mx := Vector2(-INF, -INF)
	for p in pts:
		mn = mn.min(p); mx = mx.max(p)
	var ext: Vector2 = mx - mn
	var s: float = maxf(ext.x, ext.y)
	if s <= 0.0:
		s = 1.0
	var out: Array = []
	for p in pts:
		out.append(((p as Vector2) - mn) / s)
	return out

func tick(delta: float) -> Array:
	var events: Array = []
	if mode == Mode.DEAD:
		return events
	if phase == 1 and hp <= int(MAX_HP * PHASE2_HP_FRAC) and hp > 0:
		phase = 2
		events.append("phase2")
	if hp <= 0:
		if not _defeated:
			_defeated = true
			mode = Mode.DEAD
			events.append("defeat")
		return events
	_t -= delta
	match mode:
		Mode.IDLE:
			mode = Mode.SINGING
			_t = sing_time()
			events.append("phrase_start")
		Mode.SINGING:
			if _t <= 0.0:
				mode = Mode.RESPONSE
				_t = RESPONSE_T
				events.append("response_open")
		Mode.RESPONSE:
			if _t <= 0.0:
				_resolve(0.0, events)
		Mode.RESOLVE:
			if _t <= 0.0:
				_phrase_i += 1
				mode = Mode.IDLE
	return events

func sing_time() -> float:
	return SING_T * (0.7 if phase == 2 else 1.0)

func submit_swipe(points: Array) -> Dictionary:
	if mode != Mode.RESPONSE:
		return {"out_sing": false, "score": 0.0, "posse_drain": 0, "damage": 0}
	var sc: float = score_trace(current_contour(), points)
	var dummy: Array = []
	_resolve(sc, dummy)
	var out_sing: bool = sc >= GOOD_THRESHOLD and not tutorial
	var drain: int = 0
	var dmg: int = 0
	if not tutorial:
		if sc >= GOOD_THRESHOLD:
			dmg = int(round(HIT_DAMAGE * sc))
		else:
			drain = MISS_DRAIN
	return {"out_sing": out_sing, "score": sc, "posse_drain": drain, "damage": dmg}

func _resolve(score: float, events: Array) -> void:
	if not tutorial and score >= GOOD_THRESHOLD:
		hp = maxi(0, hp - int(round(HIT_DAMAGE * score)))
		events.append("out_sing")
	elif not tutorial:
		events.append("high_note")
	mode = Mode.RESOLVE
	_t = RESOLVE_T
