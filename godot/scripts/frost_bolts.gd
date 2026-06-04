extends Node2D

# iter404: FROSTBITE chain-lightning gunfire. Ported from the roguelike project's
# drawChainLightning (fractal midpoint-displacement bolts, 3-pass additive glow,
# branching, radial impact flashes), recoloured icy-frost and drawn over the 3D
# gameplay view. Each FROSTBITE shot adds a chain: muzzle → nearest enemies. The
# bolt is re-seeded every frame so it crackles/flickers, and fades over LIFE.

const LIFE: float = 0.30
const GLOW: Color = Color(0.31, 0.71, 1.0)     # icy blue (80,180,255)
const MID: Color = Color(0.62, 0.90, 1.0)      # cyan (140,220,255)
const CORE: Color = Color(0.92, 0.99, 1.0)     # near-white frost core

var _bolts: Array = []     # each: {pts: PackedVector2Array, life: float, power: float}
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	# Additive blend so overlapping glow passes read as bright energy.
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = m
	set_process(false)

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
	for b in _bolts:
		var pts: PackedVector2Array = b["pts"]
		var life_frac: float = clampf(b["life"] / LIFE, 0.0, 1.0)
		var power: float = b["power"]
		for i in range(pts.size() - 1):
			_draw_segment(pts[i], pts[i + 1], life_frac, power, flick + i * 911)
		for p in pts:
			_draw_flash(p, life_frac, power)

func _draw_segment(a: Vector2, b: Vector2, life: float, power: float, seed: int) -> void:
	var segs: Array = []
	_rng.seed = seed
	_subdivide(a, b, 4, 1.0, segs)
	# Pass 1: wide low-alpha blue glow.
	for s in segs:
		draw_line(s["a"], s["b"], Color(GLOW.r, GLOW.g, GLOW.b, 0.20 * life * s["w"]),
			24.0 * s["w"] * (1.0 + power * 0.3))
	# Pass 2: mid cyan glow.
	for s in segs:
		draw_line(s["a"], s["b"], Color(MID.r, MID.g, MID.b, 0.45 * life * s["w"]),
			9.0 * s["w"] * (1.0 + power * 0.2))
	# Pass 3: bright white core (trunk only).
	for s in segs:
		if s["w"] < 0.6:
			continue
		draw_line(s["a"], s["b"], Color(CORE.r, CORE.g, CORE.b, 1.0 * life * s["w"]), 4.0 * s["w"])

# Fractal midpoint displacement (with occasional branches), matching the roguelike.
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

func _draw_flash(p: Vector2, life: float, power: float) -> void:
	var r: float = 42.0 * (1.0 + power * 0.2)
	draw_circle(p, r, Color(GLOW.r, GLOW.g, GLOW.b, 0.14 * life))
	draw_circle(p, r * 0.55, Color(MID.r, MID.g, MID.b, 0.24 * life))
	draw_circle(p, r * 0.25, Color(CORE.r, CORE.g, CORE.b, 0.7 * life))
