extends Control

# Iter 161: debug-build-only overlay for the level selector.
#
# Draws a 100px coordinate grid (major lines + labels every 500) and an
# outlined polygon over every tap area, each with a centre crosshair and
# an (x, y) readout. It lets the player read exact pixel positions off a
# sideloaded build and hand back precise nudge instructions.
#
# level_select.gd instances this ONLY when OS.has_feature("debug"), so
# release builds never show it. mouse_filter = IGNORE — taps fall
# straight through to the real controls underneath.

const GRID_STEP: int = 100
const GRID_MAJOR: int = 500
const SCREEN := Vector2(1080.0, 1920.0)

# Each entry: { name: String, color: Color, quad: PackedVector2Array }
var targets: Array = []

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	queue_redraw()

func _draw() -> void:
	_draw_grid()
	for t in targets:
		_draw_target(t)

func _draw_grid() -> void:
	var font: Font = ThemeDB.fallback_font
	var minor := Color(1.0, 1.0, 1.0, 0.12)
	var major := Color(0.35, 1.0, 0.55, 0.45)
	var lbl := Color(0.50, 1.0, 0.68, 1.0)
	var x: int = 0
	while x <= int(SCREEN.x):
		var x_major: bool = (x % GRID_MAJOR == 0)
		draw_line(Vector2(x, 0), Vector2(x, SCREEN.y),
			major if x_major else minor, 2.0 if x_major else 1.0)
		_label(font, Vector2(x + 3, 27), str(x), 18, lbl)
		x += GRID_STEP
	var y: int = 0
	while y <= int(SCREEN.y):
		var y_major: bool = (y % GRID_MAJOR == 0)
		draw_line(Vector2(0, y), Vector2(SCREEN.x, y),
			major if y_major else minor, 2.0 if y_major else 1.0)
		_label(font, Vector2(6, y - 6), str(y), 18, lbl)
		y += GRID_STEP

func _draw_target(t: Dictionary) -> void:
	var quad: PackedVector2Array = t["quad"]
	if quad.size() < 4:
		return
	var col: Color = t["color"]
	draw_colored_polygon(quad, Color(col.r, col.g, col.b, 0.13))
	for i in 4:
		draw_line(quad[i], quad[(i + 1) % 4], col, 3.0)
	var font: Font = ThemeDB.fallback_font
	# centre crosshair + readout
	var c: Vector2 = (quad[0] + quad[1] + quad[2] + quad[3]) / 4.0
	draw_line(c - Vector2(13, 0), c + Vector2(13, 0), col, 2.0)
	draw_line(c - Vector2(0, 13), c + Vector2(0, 13), col, 2.0)
	_label(font, c + Vector2(9, 5), "c " + _xy(c), 19, Color(1, 1, 1, 1))
	# name (inside, top-left) + an (x,y) at every vertex — corners 0/1
	# (top) label above, 2/3 (bottom) label below, each with a dot.
	_label(font, quad[0] + Vector2(6, 30), t["name"], 22, Color(1.0, 0.95, 0.5, 1.0))
	for i in 4:
		var v: Vector2 = quad[i]
		draw_circle(v, 5.0, col)
		var off := Vector2(7, -9) if i < 2 else Vector2(7, 23)
		_label(font, v + off, _xy(v), 17, Color(0.85, 1.0, 1.0, 1.0))

# "(x, y)" with rounded integer coordinates.
func _xy(p: Vector2) -> String:
	return "(%d, %d)" % [int(round(p.x)), int(round(p.y))]

# Draw text with a 1.5px black shadow so labels stay legible over any art.
func _label(font: Font, pos: Vector2, text: String, size: int, color: Color) -> void:
	draw_string(font, pos + Vector2(1.5, 1.5), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0, 0, 0, 0.85))
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
