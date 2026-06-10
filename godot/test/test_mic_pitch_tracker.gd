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
	assert_lt(c[c.size() - 1].y, c[0].y, "rising pitch goes up (falls in y)")

func test_silence_has_no_voiced_frames():
	var t = MicPitchTracker.new(SR)
	var z := PackedFloat32Array()
	z.resize(int(SR * 0.5))
	t.push_samples(z)
	assert_eq(t.voiced_frames, 0)
	assert_eq(t.curve().size(), 0)

func test_noise_is_unvoiced():
	var t = MicPitchTracker.new(SR)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var n := PackedFloat32Array()
	n.resize(int(SR * 0.5))
	for i in range(n.size()):
		n[i] = rng.randf_range(-0.3, 0.3)
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

func test_clear_resets_everything():
	var t = MicPitchTracker.new(SR)
	t.push_samples(_sine(440.0, 0.3))
	t.clear()
	assert_eq(t.voiced_frames, 0)
	assert_eq(t.curve().size(), 0)
	assert_eq(t.last_pitch_hz, 0.0)
