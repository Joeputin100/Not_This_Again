extends Control
class_name HeartRow

# Vector-drawn hearts. Replaces the old Label with a "♥" text glyph: the
# theme font (Rye) has no ♥, so on the Android export the glyph fell back to a
# tiny missing-glyph dot (it only looked right locally because the editor
# supplies a fallback font). Drawing the heart as a polygon renders identically
# on every platform and scales cleanly with the breathing pulse.

@export var full_color: Color = Color(1.0, 0.32, 0.40, 1.0)
@export var spent_color: Color = Color(0.40, 0.26, 0.26, 0.55)
@export var outline_color: Color = Color(0.18, 0.05, 0.05, 1.0)

var _current: int = 5
var _max: int = 5

func set_hearts(current: int, maximum: int) -> void:
	_current = current
	_max = maxi(maximum, 1)
	queue_redraw()

func _draw() -> void:
	var slot: float = size.x / float(_max)
	# Heart radius: fit within the slot width and the control height.
	var r: float = minf(slot * 0.36, size.y * 0.40)
	var cy: float = size.y * 0.5
	for i in range(_max):
		var cx: float = slot * (float(i) + 0.5)
		var col: Color = full_color if i < _current else spent_color
		_draw_heart(Vector2(cx, cy), r, col)

func _draw_heart(c: Vector2, r: float, col: Color) -> void:
	# Parametric heart curve (classic sin^3 form), sampled to a polygon.
	var pts := PackedVector2Array()
	const STEPS := 28
	for s in range(STEPS):
		var t: float = TAU * float(s) / float(STEPS)
		var x: float = 16.0 * pow(sin(t), 3.0)
		var y: float = -(13.0 * cos(t) - 5.0 * cos(2.0 * t) - 2.0 * cos(3.0 * t) - cos(4.0 * t))
		pts.append(c + Vector2(x, y) * (r / 16.0))
	draw_colored_polygon(pts, col)
	# Closed outline for definition against the busy splash background.
	var ring := pts
	ring.append(pts[0])
	draw_polyline(ring, outline_color, maxf(r * 0.10, 2.0), true)
