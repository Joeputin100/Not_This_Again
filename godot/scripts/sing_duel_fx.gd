extends Control

# Sing-duel overlay for the Queen of the Night. Additive 2D canvas in the
# manga_fx.gd tradition: draws the glowing melodic contour + note-dots while she
# sings, the player's live swipe trail, and out-sing / high-note hit flashes.
# Captures the swipe.
#
#   show_contour(points)   # screen-space points of her phrase
#   open_response()        # begin capturing the player's swipe
#   feed_point(p)          # add a swipe point
#   end_response() -> Array # stop capturing, return captured points
#   out_sing_flash(at) / high_note_flash(at)
#   clear() / is_active()

const RYE := preload("res://assets/fonts/Rye-Regular.ttf")

var _contour: Array = []
var _sing_anim: float = 0.0
var _capturing: bool = false
var _swipe: Array = []
var _flashes: Array = []

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = m
	set_process(false)

func is_active() -> bool:
	return not _contour.is_empty() or _capturing or not _flashes.is_empty()

func clear() -> void:
	_contour.clear(); _swipe.clear(); _flashes.clear()
	_capturing = false; _sing_anim = 0.0
	set_process(false); queue_redraw()

func show_contour(points: Array) -> void:
	_contour = points.duplicate()
	_sing_anim = 0.0
	set_process(true); queue_redraw()

func open_response() -> void:
	_capturing = true
	_swipe.clear()
	set_process(true)

func feed_point(p: Vector2) -> void:
	if _capturing:
		_swipe.append(p)
		queue_redraw()

func end_response() -> Array:
	_capturing = false
	var out: Array = _swipe.duplicate()
	queue_redraw()
	return out

func out_sing_flash(at: Vector2) -> void:
	_flashes.append({"pos": at, "life": 0.8, "t0": 0.8, "color": Color(0.5, 1.0, 0.6), "text": "OUT-SING!"})
	set_process(true); queue_redraw()

func high_note_flash(at: Vector2) -> void:
	_flashes.append({"pos": at, "life": 0.8, "t0": 0.8, "color": Color(1.0, 0.4, 0.6), "text": "HIGH NOTE!"})
	set_process(true); queue_redraw()

func _process(delta: float) -> void:
	if _sing_anim < 1.0 and not _contour.is_empty():
		_sing_anim = minf(1.0, _sing_anim + delta * 1.2)
	var live: Array = []
	for f in _flashes:
		f["life"] -= delta
		if f["life"] > 0.0:
			live.append(f)
	_flashes = live
	queue_redraw()
	if not is_active():
		set_process(false)

func _draw() -> void:
	if _contour.size() >= 2:
		var n: int = _contour.size()
		var lit: int = maxi(1, int(_sing_anim * (n - 1)))
		for i in range(lit):
			draw_line(_contour[i], _contour[i + 1], Color(1.0, 0.84, 0.4, 0.9), 8.0)
		for i in range(n):
			if float(i) / float(n - 1) <= _sing_anim:
				draw_circle(_contour[i], 9.0, Color(1.0, 0.84, 0.4, 0.95))
	for i in range(_swipe.size() - 1):
		draw_line(_swipe[i], _swipe[i + 1], Color(0.47, 0.82, 1.0, 0.95), 7.0)
	for f in _flashes:
		var frac: float = clampf(f["life"] / f["t0"], 0.0, 1.0)
		var c: Color = f["color"]; c.a = frac
		draw_circle(f["pos"], lerpf(60.0, 180.0, 1.0 - frac), Color(c.r, c.g, c.b, frac * 0.4))
		var tw: float = RYE.get_string_size(f["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, 64).x
		draw_string(RYE, f["pos"] - Vector2(tw * 0.5, 0), f["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, 64, c)
