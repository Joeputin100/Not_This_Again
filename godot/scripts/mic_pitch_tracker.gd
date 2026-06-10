class_name MicPitchTracker
extends RefCounted

# Pure pitch-over-time extractor for Sing Mode (Level-6 sing-duel). Mono float
# samples in -> normalized melody curve out. No nodes, no audio APIs: fully
# unit-testable headless on CI.
# Spec: docs/superpowers/specs/2026-06-10-sing-mode-mic-input-design.md.
#
# Method: per-hop normalized autocorrelation (a poor-man's YIN). Plenty for
# hummed melodies — we only need the SHAPE: QueenDuelState.score_trace
# box-normalizes the curve, which makes scoring octave/key-forgiving.
#
# Curve points are Vector2(t_seconds, -log2(pitch_hz)): higher pitch = smaller
# y = "up", matching the duel contour's screen orientation.

const HOP := 512                 # samples per analysis hop (~46ms @ 11025)
const MIN_HZ := 80.0
const MAX_HZ := 1000.0
const ENERGY_GATE := 0.005       # mean |x| below this = silence
const PEAK_GATE := 0.55          # normalized autocorr peak below this = unvoiced

var voiced_frames: int = 0
var last_pitch_hz: float = 0.0

var _sr: float
var _buf := PackedFloat32Array()
var _t: float = 0.0              # seconds of audio consumed
var _curve: Array = []           # Vector2(t, -log2(hz)) per voiced hop

func _init(sample_rate: float) -> void:
	_sr = sample_rate

func push_samples(samples: PackedFloat32Array) -> void:
	_buf.append_array(samples)
	while _buf.size() >= HOP:
		_analyze_hop(_buf.slice(0, HOP))
		_buf = _buf.slice(HOP)
		_t += HOP / _sr

func curve() -> Array:
	return _curve

func clear() -> void:
	_buf = PackedFloat32Array()
	_curve = []
	voiced_frames = 0
	last_pitch_hz = 0.0
	_t = 0.0

func _analyze_hop(x: PackedFloat32Array) -> void:
	var energy := 0.0
	for v in x:
		energy += absf(v)
	energy /= x.size()
	if energy < ENERGY_GATE:
		return
	var lag_min := int(_sr / MAX_HZ)
	var lag_max := mini(int(_sr / MIN_HZ), x.size() - 1)
	var r0 := 0.0
	for v in x:
		r0 += v * v
	if r0 <= 0.0:
		return
	var best_lag := -1
	var best := 0.0
	for lag in range(lag_min, lag_max + 1):
		var r := 0.0
		for i in range(x.size() - lag):
			r += x[i] * x[i + lag]
		var norm := r / r0
		if norm > best:
			best = norm
			best_lag = lag
	if best_lag < 0 or best < PEAK_GATE:
		return
	last_pitch_hz = _sr / best_lag
	voiced_frames += 1
	_curve.append(Vector2(_t, -log(last_pitch_hz) / log(2.0)))
