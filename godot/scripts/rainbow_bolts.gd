extends Node2D

# kimmy: RAINBOW PRISM CHAIN gunfire. Near-clone of frost_bolts.gd (FROSTBITE)
# but recoloured through a flowing rainbow gradient: each bolt segment is hued by
# its position ALONG the chain, with a slow time-scroll so the hues shimmer/flow.
# Same fractal midpoint-displacement bolts, 3-pass additive glow, radial impact
# flashes, re-seeded every frame so it crackles, fading over LIFE. Shader-free.

const LIFE: float = 0.34

var _bolts: Array = []     # each: {pts: PackedVector2Array, life: float, power: float}
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	# Additive blend so overlapping glow passes read as bright energy.
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = m
	set_process(false)

# Rainbow hue at parameter t (wraps). Saturated + full value for vivid prism color.
func _hue_color(t: float) -> Color:
	return Color.from_hsv(fmod(t, 1.0), 0.85, 1.0)

# Add a chain of bolts through `points` (screen-space). points[0] is the muzzle.
func add_chain(points: PackedVector2Array, power: float = 1.0) -> void:
	if points.size() < 2:
		return
	_bolts.append({"pts": points, "life": LIFE, "power": power})
	set_process(true)
	queue_redraw()

func _process(delta: float) -> void:
	var alive: Array = []
	for b in _bolts:
		b["life"] -= delta
		if b["life"] > 0.0:
			alive.append(b)
	_bolts = alive
	queue_redraw()
	if _bolts.is_empty():
		set_process(false)

func _draw() -> void:
	var flick: int = int(Time.get_ticks_msec() / 55)   # reseed → crackle
	var scroll: float = Time.get_ticks_msec() / 1000.0 * 0.3   # hues flow along chain
	for b in _bolts:
		var pts: PackedVector2Array = b["pts"]
		var life_frac: float = clampf(b["life"] / LIFE, 0.0, 1.0)
		var power: float = b["power"]
		var denom: int = maxi(1, pts.size() - 1)
		for i in range(pts.size() - 1):
			var t: float = float(i) / float(denom) + scroll
			_draw_segment(pts[i], pts[i + 1], life_frac, power, flick + i * 911, _hue_color(t))
		for i in range(pts.size()):
			var pt: float = float(i) / float(denom) + scroll
			_draw_flash(pts[i], life_frac, power, _hue_color(pt))

func _draw_segment(a: Vector2, b: Vector2, life: float, power: float, seed: int, hue: Color) -> void:
	var segs: Array = []
	_rng.seed = seed
	_subdivide(a, b, 4, 1.0, segs)
	# Pass 1: wide low-alpha rainbow glow.
	for s in segs:
		draw_line(s["a"], s["b"], Color(hue.r, hue.g, hue.b, 0.20 * life * s["w"]),
			24.0 * s["w"] * (1.0 + power * 0.3))
	# Pass 2: mid rainbow glow.
	for s in segs:
		draw_line(s["a"], s["b"], Color(hue.r, hue.g, hue.b, 0.45 * life * s["w"]),
			9.0 * s["w"] * (1.0 + power * 0.2))
	# Pass 3: bright white core (trunk only) — keeps it reading as hot energy.
	for s in segs:
		if s["w"] < 0.6:
			continue
		draw_line(s["a"], s["b"], Color(1, 1, 1, 1.0 * life * s["w"]), 4.0 * s["w"])

# Fractal midpoint displacement (with occasional branches), matching FROSTBITE.
func _subdivide(a: Vector2, b: Vector2, depth: int, w: float, segs: Array) -> void:
	if depth == 0:
		segs.append({"a": a, "b": b, "w": w})
		return
	var mid: Vector2 = (a + b) * 0.5 + Vector2(
		(_rng.randf() - 0.5), (_rng.randf() - 0.5)) * float(depth) * 22.0
	_subdivide(a, mid, depth - 1, w, segs)
	_subdivide(mid, b, depth - 1, w, segs)
	if depth >= 2 and _rng.randf() < 0.35:
		var br: Vector2 = mid + Vector2((_rng.randf() - 0.5), (_rng.randf() - 0.5)) * 50.0
		_subdivide(mid, br, depth - 2, w * 0.5, segs)

func _draw_flash(p: Vector2, life: float, power: float, hue: Color) -> void:
	var r: float = 42.0 * (1.0 + power * 0.2)
	draw_circle(p, r, Color(hue.r, hue.g, hue.b, 0.14 * life))
	draw_circle(p, r * 0.55, Color(hue.r, hue.g, hue.b, 0.24 * life))
	draw_circle(p, r * 0.25, Color(1, 1, 1, 0.7 * life))
