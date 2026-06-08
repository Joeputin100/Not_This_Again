extends Control

# Manga / fighting-anime FX overlay for the Raisin Kidd boss. An additive 2D
# canvas in the frost_bolts.gd tradition — focus lines, burst lines, written-out
# onomatopoeia SFX, a special-move title card, and the Five-Point gumdrop
# countdown + KA-BLOOM. Mobile-safe: pure Control _draw + a Rye font, no custom
# shaders. Mounted under UI by level_3d.
#
# Public API (all screen-space positions):
#   focus_lines(center)              # converging speed-lines telegraph
#   burst(center, text)              # radial burst-lines + onomatopoeia pop
#   title_card(text)                 # slam-in special-move name card
#   gumdrop_countdown(center)        # 5->1 gumdrop pips, then KA-BLOOM
#   clear()                          # wipe everything
#   is_active()                      # any live effect?

const RYE := preload("res://assets/fonts/Rye-Regular.ttf")

const FOCUS_LIFE := 1.0
const BURST_LIFE := 0.7
const TITLE_LIFE := 1.6
const PIP_STEP := 0.45
const BLOOM_LIFE := 0.9

var _focus: Array = []
var _bursts: Array = []
var _titles: Array = []
var _counts: Array = []
var _rng := RandomNumberGenerator.new()
var _font: Font

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = m
	_font = RYE
	set_process(false)

func is_active() -> bool:
	return not (_focus.is_empty() and _bursts.is_empty() \
		and _titles.is_empty() and _counts.is_empty())

func clear() -> void:
	_focus.clear(); _bursts.clear(); _titles.clear(); _counts.clear()
	set_process(false)
	queue_redraw()

func _wake() -> void:
	set_process(true)
	queue_redraw()

func focus_lines(center: Vector2) -> void:
	_focus.append({"center": center, "life": FOCUS_LIFE, "t0": FOCUS_LIFE})
	_wake()

func burst(center: Vector2, text: String = "") -> void:
	_bursts.append({"center": center, "text": text, "life": BURST_LIFE, "t0": BURST_LIFE})
	_wake()

func title_card(text: String) -> void:
	_titles.append({"text": text, "life": TITLE_LIFE, "t0": TITLE_LIFE})
	_wake()

func gumdrop_countdown(center: Vector2) -> void:
	_counts.append({"center": center, "n": 5, "step_t": PIP_STEP,
		"life": PIP_STEP * 5.0, "blooming": false, "bloom_life": BLOOM_LIFE})
	_wake()

func _process(delta: float) -> void:
	_focus = _age(_focus, delta)
	_bursts = _age(_bursts, delta)
	_titles = _age(_titles, delta)
	for c in _counts:
		if c["blooming"]:
			c["bloom_life"] -= delta
		else:
			c["step_t"] -= delta
			c["life"] -= delta
			if c["step_t"] <= 0.0:
				c["step_t"] = PIP_STEP
				c["n"] = maxi(0, int(c["n"]) - 1)
			if int(c["n"]) <= 0 and c["life"] <= 0.0:
				c["blooming"] = true
	var live_counts: Array = []
	for c in _counts:
		if not c["blooming"] or c["bloom_life"] > 0.0:
			live_counts.append(c)
	_counts = live_counts
	queue_redraw()
	if not is_active():
		set_process(false)

func _age(arr: Array, delta: float) -> Array:
	var out: Array = []
	for e in arr:
		e["life"] -= delta
		if e["life"] > 0.0:
			out.append(e)
	return out

func _draw() -> void:
	for f in _focus:
		_draw_focus(f)
	for b in _bursts:
		_draw_burst(b)
	for c in _counts:
		_draw_count(c)
	for t in _titles:
		_draw_title(t)

func _draw_focus(f: Dictionary) -> void:
	var c: Vector2 = f["center"]
	var frac: float = clampf(f["life"] / f["t0"], 0.0, 1.0)
	var a: float = frac * 0.85
	var R: float = maxf(size.x, size.y)
	var n := 64
	for i in range(n):
		var ang: float = TAU * float(i) / float(n) + sin(float(i) * 12.9) * 0.02
		var inner: float = lerpf(R * 0.55, R * 0.20, 1.0 - frac)
		var p_in: Vector2 = c + Vector2(cos(ang), sin(ang)) * inner
		var p_out: Vector2 = c + Vector2(cos(ang), sin(ang)) * R
		var w: float = 2.0 + 6.0 * abs(sin(float(i) * 7.3))
		draw_line(p_out, p_in, Color(1, 1, 1, a * 0.6), w)

func _draw_burst(b: Dictionary) -> void:
	var c: Vector2 = b["center"]
	var frac: float = clampf(b["life"] / b["t0"], 0.0, 1.0)
	var grow: float = 1.0 - frac
	var R: float = lerpf(40.0, 520.0, grow)
	var n := 40
	for i in range(n):
		var ang: float = TAU * float(i) / float(n)
		var jag: float = 0.78 + 0.22 * abs(sin(float(i) * 5.1))
		var p_in: Vector2 = c + Vector2(cos(ang), sin(ang)) * (R * 0.45)
		var p_out: Vector2 = c + Vector2(cos(ang), sin(ang)) * (R * jag)
		draw_line(p_in, p_out, Color(1, 0.95, 0.5, frac * 0.9), 3.0 + 5.0 * jag)
	if String(b["text"]) != "":
		_draw_sfx_text(String(b["text"]), c + Vector2(0, -20), lerpf(54, 96, grow), frac)

func _draw_count(c: Dictionary) -> void:
	var center: Vector2 = c["center"]
	if c["blooming"]:
		var bf: float = clampf(c["bloom_life"] / BLOOM_LIFE, 0.0, 1.0)
		var R: float = lerpf(60.0, 600.0, 1.0 - bf)
		draw_circle(center, R * 0.5, Color(1, 1, 1, bf * 0.5))
		_draw_sfx_text("KA-BLOOM!", center, lerpf(72, 130, 1.0 - bf), bf)
		return
	var lit: int = int(c["n"])
	for i in range(5):
		var px: Vector2 = center + Vector2((i - 2) * 70.0, 0.0)
		var on: bool = i < lit
		var col := Color(0.9, 0.4, 0.9, 0.95) if on else Color(0.4, 0.2, 0.4, 0.4)
		_draw_gumdrop(px, 26.0, col)

func _draw_gumdrop(p: Vector2, r: float, col: Color) -> void:
	draw_circle(p + Vector2(0, r * 0.25), r, col)
	var pts := PackedVector2Array([
		p + Vector2(-r * 0.7, r * 0.1), p + Vector2(0, -r), p + Vector2(r * 0.7, r * 0.1)])
	draw_colored_polygon(pts, col)

func _draw_title(t: Dictionary) -> void:
	var frac: float = clampf(t["life"] / t["t0"], 0.0, 1.0)
	var age: float = 1.0 - frac
	var scale_in: float = clampf(age / 0.18, 0.0, 1.0)
	var fade: float = clampf(frac / 0.25, 0.0, 1.0)
	var fs: float = lerpf(160.0, 96.0, scale_in)
	# speed-line backing behind the card
	_draw_focus({"center": size * 0.5, "life": 1.0, "t0": 1.0})
	var lines: PackedStringArray = String(t["text"]).split("\n")
	var y: float = size.y * 0.42
	for ln in lines:
		_draw_sfx_text(ln, Vector2(size.x * 0.5, y), fs, fade)
		y += fs * 1.05

func _draw_sfx_text(text: String, center: Vector2, font_size: float, alpha: float) -> void:
	var fs := int(font_size)
	var tw: float = _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var pos: Vector2 = center - Vector2(tw * 0.5, 0)
	for ox in [-4, 0, 4]:
		for oy in [-4, 0, 4]:
			if ox == 0 and oy == 0:
				continue
			draw_string(_font, pos + Vector2(ox, oy), text, HORIZONTAL_ALIGNMENT_LEFT,
				-1, fs, Color(0.05, 0.0, 0.08, alpha))
	draw_string(_font, pos + Vector2(0, -2), text, HORIZONTAL_ALIGNMENT_LEFT,
		-1, fs, Color(1, 1, 1, alpha))
	draw_string(_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT,
		-1, fs, Color(1.0, 0.78, 0.25, alpha))
