# Sing Mode (Mic Input) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Optional microphone "Sing it!" input for the Level-6 sing-duel — pitch contour feeds the existing swipe scorer; swipe stays default; both sing minigames get debug-menu shortcuts.

**Architecture:** A pure `MicPitchTracker` RefCounted (autocorrelation pitch → normalized curve, GUT-tested headless) + a thin `mic_capture.gd` Node owning the Record bus/`AudioEffectCapture` + glue in `level_3d.gd` (pre-fight mode modal, audio duck, live trail, end-of-window `submit_swipe`). `QueenDuelState` is untouched.

**Tech Stack:** Godot 4.6 GDScript, GUT on GitHub Actions (NEVER run Godot locally), existing `sing_duel_fx` overlay + `DebugPreview` autoload patterns.

**Spec:** `docs/superpowers/specs/2026-06-10-sing-mode-mic-input-design.md`

---

## Task 1: `MicPitchTracker` — pure pitch-curve extraction (TDD)

**Files:**
- Create: `godot/scripts/mic_pitch_tracker.gd`
- Test: `godot/test/test_mic_pitch_tracker.gd`

- [ ] **Step 1: Write the failing tests**

```gdscript
extends GutTest

const MicPitchTracker = preload("res://scripts/mic_pitch_tracker.gd")

const SR := 11025.0

func _sine(freq: float, secs: float, amp: float = 0.4) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var n := int(SR * secs)
	out.resize(n)
	for i in range(n):
		out[i] = amp * sin(TAU * freq * float(i) / SR)
	return out

func test_detects_a440():
	var t = MicPitchTracker.new(SR)
	t.push_samples(_sine(440.0, 0.5))
	assert_gt(t.voiced_frames, 3, "a clear tone is voiced")
	var hz: float = t.last_pitch_hz
	assert_between(hz, 410.0, 470.0, "within ~a semitone of 440")

func test_rising_sweep_curve_goes_up_on_screen():
	var t = MicPitchTracker.new(SR)
	t.push_samples(_sine(220.0, 0.3))
	t.push_samples(_sine(440.0, 0.3))
	t.push_samples(_sine(880.0, 0.3))
	var c: Array = t.curve()
	assert_gt(c.size(), 6)
	# y = -log2(hz): higher pitch -> SMALLER y (up on screen)
	assert_lt(c[c.size() - 1].y, c[0].y, "rising pitch falls in y")

func test_silence_has_no_voiced_frames():
	var t = MicPitchTracker.new(SR)
	var z := PackedFloat32Array(); z.resize(int(SR * 0.5))
	t.push_samples(z)
	assert_eq(t.voiced_frames, 0)
	assert_eq(t.curve().size(), 0)

func test_noise_is_unvoiced():
	var t = MicPitchTracker.new(SR)
	var rng := RandomNumberGenerator.new(); rng.seed = 7
	var n := PackedFloat32Array(); n.resize(int(SR * 0.5))
	for i in range(n.size()): n[i] = rng.randf_range(-0.3, 0.3)
	t.push_samples(n)
	assert_lt(t.voiced_frames, 2, "white noise should (almost) never read as pitch")

func test_split_pushes_equal_one_push():
	var a = MicPitchTracker.new(SR)
	a.push_samples(_sine(330.0, 0.4))
	var b = MicPitchTracker.new(SR)
	var whole := _sine(330.0, 0.4)
	b.push_samples(whole.slice(0, 1000))
	b.push_samples(whole.slice(1000))
	assert_eq(a.voiced_frames, b.voiced_frames, "hop continuity across pushes")
```

- [ ] **Step 2: Implement `mic_pitch_tracker.gd`**

```gdscript
class_name MicPitchTracker
extends RefCounted

# Pure pitch-over-time extractor for Sing Mode (Level-6 duel). Mono float
# samples in -> normalized curve out. No nodes, no audio APIs: unit-testable
# headless on CI. See docs/superpowers/specs/2026-06-10-sing-mode-mic-input-design.md.
#
# Method: per-hop normalized autocorrelation (a.k.a. poor-man's YIN). Good
# enough for hummed melodies; we only need the SHAPE (score_trace normalizes
# scale/offset away, giving octave/key forgiveness).

const HOP := 512                 # samples per analysis hop (~46ms @ 11025)
const MIN_HZ := 80.0
const MAX_HZ := 1000.0
const ENERGY_GATE := 0.005       # mean |x| below this = silence
const PEAK_GATE := 0.55          # autocorr peak below this = unvoiced

var voiced_frames: int = 0
var last_pitch_hz: float = 0.0

var _sr: float
var _buf := PackedFloat32Array()
var _t: float = 0.0              # seconds consumed
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
	_buf = PackedFloat32Array(); _curve = []
	voiced_frames = 0; last_pitch_hz = 0.0; _t = 0.0

func _analyze_hop(x: PackedFloat32Array) -> void:
	var energy := 0.0
	for v in x: energy += absf(v)
	energy /= x.size()
	if energy < ENERGY_GATE:
		return
	var lag_min := int(_sr / MAX_HZ)
	var lag_max := mini(int(_sr / MIN_HZ), x.size() - 1)
	var r0 := 0.0
	for v in x: r0 += v * v
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
			best = norm; best_lag = lag
	if best_lag < 0 or best < PEAK_GATE:
		return
	last_pitch_hz = _sr / best_lag
	voiced_frames += 1
	_curve.append(Vector2(_t, -log(last_pitch_hz) / log(2.0)))
```

- [ ] **Step 3: Commit, push, `gh run watch` GUT green.**

```bash
git add godot/scripts/mic_pitch_tracker.gd godot/test/test_mic_pitch_tracker.gd
git commit -m "feat(sing): MicPitchTracker pure pitch-curve extractor + tests"
```

---

## Task 2: `mic_capture.gd` + Android plumbing

**Files:**
- Create: `godot/scripts/mic_capture.gd`
- Modify: `godot/project.godot` ([audio] add `driver/enable_input=true`)
- Modify: `godot/export_presets.cfg` (`permissions/record_audio=true`)

- [ ] **Step 1: `mic_capture.gd`**

```gdscript
extends Node

# Runtime mic capture for Sing Mode. Owns a dedicated muted "MicRecord" audio
# bus with an AudioEffectCapture, fed by an AudioStreamMicrophone player.
# Polls captured frames each _process into a MicPitchTracker (pure, tested).
# Inert (no-ops) when input is unavailable. Frames are processed and
# DISCARDED — nothing is stored or transmitted.

const MicPitchTrackerScript = preload("res://scripts/mic_pitch_tracker.gd")

var tracker = null
var _player: AudioStreamPlayer = null
var _capture: AudioEffectCapture = null
var _bus_idx: int = -1
var _active: bool = false

func start() -> bool:
	if _active:
		return true
	if _bus_idx < 0:
		_bus_idx = AudioServer.bus_count
		AudioServer.add_bus(_bus_idx)
		AudioServer.set_bus_name(_bus_idx, "MicRecord")
		AudioServer.set_bus_mute(_bus_idx, true)   # never echo the mic
		_capture = AudioEffectCapture.new()
		AudioServer.add_bus_effect(_bus_idx, _capture)
	tracker = MicPitchTrackerScript.new(AudioServer.get_mix_rate())
	if _player == null:
		_player = AudioStreamPlayer.new()
		_player.stream = AudioStreamMicrophone.new()
		_player.bus = "MicRecord"
		add_child(_player)
	_player.play()
	_capture.clear_buffer()
	_active = true
	return true

func stop() -> void:
	if _player != null and _player.playing:
		_player.stop()
	_active = false

func curve() -> Array:
	return tracker.curve() if tracker != null else []

func voiced() -> int:
	return tracker.voiced_frames if tracker != null else 0

func _process(_delta: float) -> void:
	if not _active or _capture == null:
		return
	var avail: int = _capture.get_frames_available()
	if avail <= 0:
		return
	var frames: PackedVector2Array = _capture.get_buffer(avail)
	var mono := PackedFloat32Array()
	mono.resize(frames.size())
	for i in range(frames.size()):
		mono[i] = (frames[i].x + frames[i].y) * 0.5
	tracker.push_samples(mono)
```

- [ ] **Step 2:** `project.godot` `[audio]` section: add `driver/enable_input=true`. `export_presets.cfg`: set `permissions/record_audio=true` in the Android preset.
- [ ] **Step 3: Commit + push (parse/CI green).**

---

## Task 3: `GameState` headphone-hint flag (tiny, TDD)

**Files:**
- Modify: `godot/scripts/game_state.gd` (field + persist round-trip)
- Test: append to `godot/test/test_game_state.gd`

- [ ] **Step 1: Failing test** — `sing_hint_shown` defaults false, set+`_save_to_disk`+reload (SAVE_PATH_OVERRIDE temp) round-trips true.
- [ ] **Step 2:** `var sing_hint_shown: bool = false`; persist under `("settings", "sing_hint_shown")` in `_save_to_disk`/`_load_from_disk`.
- [ ] **Step 3: Commit.**

---

## Task 4: Pre-fight mode choice modal + duel gating (`level_3d.gd`)

**Files:** Modify `godot/scripts/level_3d.gd`

- [ ] **Step 1:** Members: `var _queen_mode: String = ""` ("", "swipe", "sing") + `var _mic: Node = null`. In `_spawn_queen()`, build the modal (level-start-modal visual style: dim ColorRect + centered candy panel, title "HOW WILL YOU ANSWER HER?", two big buttons "👆 SWIPE" (default focus) / "🎤 SING") instead of playing the intro; the Queen idles behind it.
- [ ] **Step 2:** `_process_queen()` first line: `if _queen_mode == "": return` (duel frozen until pick; billboard still loops).
- [ ] **Step 3:** SWIPE press → `_queen_mode="swipe"`, free modal, `_queen_say("intro")`. SING press → if `"android.permission.RECORD_AUDIO" in OS.get_granted_permissions()` (or not Android) → `_enter_sing_mode()`; else `OS.request_permission("RECORD_AUDIO")` + connect `get_tree().on_request_permissions_result` one-shot → granted ⇒ `_enter_sing_mode()`, denied ⇒ swipe + `info_label.text = "No mic — swipin' it is, partner!"`.
- [ ] **Step 4:** `_enter_sing_mode()`: `_queen_mode="sing"`; lazily `_mic = preload("res://scripts/mic_capture.gd").new(); add_child(_mic)`; one-time headphone hint (`GameState.sing_hint_shown`) via `info_label`; free modal; `_queen_say("intro")`.
- [ ] **Step 5: Commit + push (parse green).**

---

## Task 5: Sing-mode response window — duck, live trail, submit, nudge

**Files:** Modify `godot/scripts/level_3d.gd`

- [ ] **Step 1:** Members: `_sing_window_t: float = 0.0`, `_sing_nudged: bool = false`, `_duck_prev_db: float = 0.0`. On `response_open` when `_queen_mode == "sing"`: do NOT set `_queen_swiping`; instead `_sing_window_t = 0.0`; `_mic.start()`; duck: `_duck_prev_db = AudioServer.get_bus_volume_db(0); AudioServer.set_bus_volume_db(0, _duck_prev_db - 24.0)`.
- [ ] **Step 2:** In `_process_queen` while in sing response: `_sing_window_t += delta`; map `_mic.curve()` tail point into the contour band (x = `_sing_window_t / QueenDuelState.RESPONSE_T` across the band width; y = curve y unit-normalized against the curve's own min/max so far, into the band height) → `_sing_fx.feed_point()` for the glowing trail.
- [ ] **Step 3:** At `_sing_window_t >= QueenDuelState.RESPONSE_T - 0.25` (once): `_mic.stop()`; restore bus dB; `_sing_fx.end_response()`; if `_mic.voiced() < 4` (empty take): first time per fight → `info_label.text = "Sing out, sugar — she can't hear you!"`, submit NOTHING (let the state's timeout fire `high_note`… but tutorial-grade mercy: directly skip drain by submitting the perfect contour is WRONG — instead set `_sing_nudged = true` and swallow the next `high_note` drain once: on `high_note` event, if `_queen_mode=="sing" and _sing_nudged_pending` → play nudge instead of `_outlaw_drain_posse`); repeat empty takes → normal miss path. Voiced take → `_queen.submit_swipe(_mic.curve())` (state-space points; score_trace normalizes) + reuse the existing swipe-result handling (out_sing flash / damage already keyed off submit result in the swipe path — mirror it).
- [ ] **Step 4:** `defeat`/level-exit cleanup: `_mic.stop()` + restore bus dB if mid-window.
- [ ] **Step 5: Commit + push.**

---

## Task 6: Debug-menu shortcuts for both sing minigames

**Files:**
- Modify: `godot/scripts/debug_preview.gd` (flags + `clear()` + `has_pending()`)
- Modify: `godot/scripts/debug_menu.gd` (two buttons, `_on_preview_*` pattern: set flag, `GameState.current_level = 6`, change scene to the level)
- Modify: `godot/scripts/level_3d.gd` (consume in `_ready` beside `pending_kimmy`)

- [ ] **Step 1:** `var pending_queen_duel: bool = false` / `var pending_papageno_duet: bool = false` in DebugPreview (+clear/has_pending rows).
- [ ] **Step 2:** Buttons "QUEEN SING-DUEL (L6 BOSS)" and "PAPAGENO DUET (L6 TUTORIAL)" in debug_menu.gd following the kimmy handler exactly (set flag → scene change).
- [ ] **Step 3:** In `level_3d._ready` DebugPreview block: `pending_queen_duel` → consume flag, defer `_spawn_queen()` (mode modal included) after scene settles, skip outlaw quota/run; `pending_papageno_duet` → consume flag, defer `_run_papageno_tutorial()`.
- [ ] **Step 4: Commit + push; confirm GUT + parse green.**

---

## Task 7: Memory + docs close-out

- [ ] Update `project_queen_sing_mic_mode.md` memory (DEFERRED → BUILT, v1, debug shortcuts) and `project_queen_of_the_night_boss.md` (sing mode shipped; device-pass items += mic thresholds/duck feel/permission flow).
- [ ] Final commit; whole branch CI-green.

**Device pass (owner's phone, NOT in this plan):** permission popup UX, ENERGY/PEAK gates vs real mics, duck depth, nudge wording, modal styling.

---

## Self-review

**Spec coverage:** §2 toggle→Task 4; bleed both→Tasks 4 (hint) + 5 (duck); bad take→Task 5 Step 3; tutorial swipe-only→no change needed; debug access→Task 6. §3 components 1–6 → Tasks 1,2,3,4,5,6. §4 scorer-unchanged → submit path in Task 5 uses raw curve. §6 tests → Task 1 + parse. ✓
**Placeholders:** none — every code step has code or an exact one-line change. ✓
**Type consistency:** `MicPitchTracker.{push_samples,curve,voiced_frames,last_pitch_hz,clear}` consistent across Tasks 1/2/5; `mic_capture.{start,stop,curve,voiced}` across 2/4/5; `_queen_mode` across 4/5; DebugPreview flags across 6. ✓
