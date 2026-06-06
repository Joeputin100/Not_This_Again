extends Node2D

# weapon fx: RIFLE "Rainbow Comet Trail" 2D-canvas additive streak overlay.
# Mirrors frost_bolts.gd's structure (Node2D on the UI CanvasLayer, additive
# blend, lifetime-pooled, re-drawn each frame). Each shot adds a streak: a bright
# comet head at the muzzle with a fading, hue-scrolling tapering tail running
# toward the target/forward point. Shader-free — pure draw_line/draw_circle so
# Android can't white-rect it.

const LIFE: float = 0.26

var _streaks: Array = []   # each: {a: Vector2 (muzzle), b: Vector2 (tip), life: float, hue0: float}

func _ready() -> void:
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = m
	set_process(false)

# a = muzzle (comet origin), b = forward tip (toward target). hue0 seeds the scroll.
func add_streak(a: Vector2, b: Vector2, hue0: float = 0.0) -> void:
	_streaks.append({"a": a, "b": b, "life": LIFE, "hue0": hue0})
	set_process(true)
	queue_redraw()

func _process(delta: float) -> void:
	var alive: Array = []
	for s in _streaks:
		s["life"] -= delta
		if s["life"] > 0.0:
			alive.append(s)
	_streaks = alive
	queue_redraw()
	if _streaks.is_empty():
		set_process(false)

func _draw() -> void:
	var scroll: float = Time.get_ticks_msec() / 1000.0 * 0.6
	for s in _streaks:
		var a: Vector2 = s["a"]
		var b: Vector2 = s["b"]
		var life_frac: float = clampf(s["life"] / LIFE, 0.0, 1.0)
		var hue0: float = s["hue0"]
		# Comet HEAD travels from muzzle toward the tip as life burns down (0→1).
		var travel: float = 1.0 - life_frac
		var head: Vector2 = a.lerp(b, travel)
		# Tapering hue-scrolling tail: a strip of segments from a recent trail point
		# up to the head, each hued along the strip + time-scrolled, fading with life.
		var tail_start: Vector2 = a.lerp(head, 0.35)
		var steps: int = 8
		for i in range(steps):
			var t0: float = float(i) / float(steps)
			var t1: float = float(i + 1) / float(steps)
			var p0: Vector2 = tail_start.lerp(head, t0)
			var p1: Vector2 = tail_start.lerp(head, t1)
			var hue: Color = Color.from_hsv(fmod(hue0 + t0 * 0.5 + scroll, 1.0), 0.8, 1.0)
			var w: float = lerpf(2.0, 12.0, t1)   # widens toward the head
			# wide low glow + brighter mid pass
			draw_line(p0, p1, Color(hue.r, hue.g, hue.b, 0.18 * life_frac), w * 1.9)
			draw_line(p0, p1, Color(hue.r, hue.g, hue.b, 0.45 * life_frac), w)
		# Bright additive comet head (white-hot core + colored halo).
		var head_hue: Color = Color.from_hsv(fmod(hue0 + 0.5 + scroll, 1.0), 0.7, 1.0)
		draw_circle(head, 22.0, Color(head_hue.r, head_hue.g, head_hue.b, 0.22 * life_frac))
		draw_circle(head, 11.0, Color(head_hue.r, head_hue.g, head_hue.b, 0.5 * life_frac))
		draw_circle(head, 5.0, Color(1, 1, 1, 0.9 * life_frac))
