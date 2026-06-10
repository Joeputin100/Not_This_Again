extends Control

# Mini-achievement banner. Candy-Crush-style "TASTY!"/"SWEET!"/"JUICY!"
# pop-up triggered by gameplay flourishes (gate combos, kill streaks,
# multiplier-gate passes, Sugar Rush activations, etc).
#
# Use the static helper:
#   FlourishBanner.spawn(parent, "RAMPAGE")
# where `parent` is typically the level's UI CanvasLayer so the banner
# overlays gameplay without scrolling with obstacles.
#
# Each banner is a one-shot transient: spawn → scale-pop + sparkles +
# shock-ring + camera shake → queue_free after the fade. Multiple
# concurrent banners are fine (they stack visually), but a per-call-
# site cooldown is wise to avoid spam — see level.gd's _kill_streak
# tracking for an example.
#
# Layered effects (no shaders needed — layering reads as polished):
#   1. ShockRing (ColorRect scaled out from 0→4× while alpha 0.6→0)
#   2. Sparkles (CPUParticles2D burst, candy palette)
#   3. Label (text with bounce scale-pop + slight upward drift)
#   4. Optional emoji prefix glyph (for JUICY, RAMPAGE, etc.)
# Plus camera shake (added trauma to level's _shake).

const SPAWN_SCENE: PackedScene = preload("res://scenes/flourish_banner.tscn")

const LIFESPAN: float = 1.25
const POP_DURATION: float = 0.22
const DRIFT_UP: float = -90.0
const SHOCK_RING_DURATION: float = 0.45
const STACK_PUSH: float = 220.0  # iter 121: vertical offset existing banners move up when a new one spawns

# Preset library. Each entry: text, primary color, font size, ring color,
# trauma (camera shake intensity, 0..1). Adding a preset is a 1-line
# dict entry — no scene/script changes elsewhere.
# Preset keys MATCH combos_counter.label_for's output ("DOUBLE!"/"MEGA!")
# so existing combo logic flows straight through without translation. New
# presets follow the same trailing-bang convention. JELLY_FRENZY (no bang)
# is the exception — Sugar Rush has its own activation flow, not a combo
# step.
# Iter 42a: preset keys stay stable (gameplay code references them by
# bang-suffix string), but displayed text is now in the Murderbot
# narrator voice per the design.md tone bible — dry, world-weary,
# slightly insulting in the affectionate way. Period punctuation (not
# bang) reinforces the deadpan read. The bigger the achievement, the
# more grudging the praise. This decouples gameplay triggers from
# voice — future tone passes only touch the text field.
#
# Cowboy-voice keys (DOUBLE!, MEGA!, YEEHAW!, RAMPAGE!) are kept loud
# and exclamatory because they're objective cause-and-effect feedback
# (gate-passed magnitude, kill-streak), not narrator commentary.
# Murderbot only weighs in on quality/precision events.
const PRESETS: Dictionary = {
	"DOUBLE!":     {"text": "DOUBLE!",      "color": Color(1.00, 0.95, 0.40, 1), "size": 156, "ring": Color(1.00, 0.85, 0.30, 0.7), "trauma": 0.55},
	"MEGA!":       {"text": "MEGA!",        "color": Color(1.00, 0.55, 0.95, 1), "size": 200, "ring": Color(1.00, 0.45, 0.95, 0.7), "trauma": 0.75},
	"TASTY!":      {"text": "ACCEPTABLE.",  "color": Color(1.00, 0.40, 0.50, 1), "size": 132, "ring": Color(1.00, 0.30, 0.45, 0.7), "trauma": 0.45},
	"JUICY!":      {"text": "EFFICIENT.",   "color": Color(0.45, 1.00, 0.65, 1), "size": 132, "ring": Color(0.35, 1.00, 0.55, 0.7), "trauma": 0.50},
	"YEEHAW!":     {"text": "YEEHAW!",      "color": Color(1.00, 0.80, 0.30, 1), "size": 200, "ring": Color(1.00, 0.70, 0.20, 0.7), "trauma": 0.65},
	"RAMPAGE!":    {"text": "RAMPAGE!",     "color": Color(1.00, 0.35, 0.30, 1), "size": 220, "ring": Color(1.00, 0.25, 0.20, 0.75), "trauma": 0.85},
	"SWEET!":      {"text": "ADEQUATE.",    "color": Color(1.00, 0.65, 0.95, 1), "size": 128, "ring": Color(1.00, 0.55, 0.95, 0.7), "trauma": 0.45},
	"FLAWLESS!":   {"text": "RELUCTANTLY COMPETENT.", "color": Color(0.50, 0.95, 1.00, 1), "size": 96, "ring": Color(0.40, 0.85, 1.00, 0.7), "trauma": 0.65},
	"JELLY_FRENZY":{"text": "JELLY BEAN FRENZY!", "color": Color(1.00, 0.55, 0.85, 1), "size": 144, "ring": Color(1.00, 0.85, 0.40, 0.8), "trauma": 0.95},
	# Iter 44: Gold Rush cascade banners. Each rush ends with one of
	# these as the "chain reaction completes" beat — equivalent to the
	# Candy Crush Striped+Wrapped explosion finale.
	"PERFECT_VOLLEY": {"text": "PERFECT VOLLEY!", "color": Color(1.00, 0.92, 0.30, 1), "size": 140, "ring": Color(1.00, 0.78, 0.20, 0.85), "trauma": 0.85},
	"SUGAR_CASCADE":  {"text": "SUGAR CASCADE!",  "color": Color(1.00, 0.55, 0.95, 1), "size": 140, "ring": Color(1.00, 0.45, 0.85, 0.85), "trauma": 0.85},
	"ROLLED":         {"text": "ROLLED!",         "color": Color(0.55, 0.95, 0.65, 1), "size": 160, "ring": Color(0.45, 0.95, 0.55, 0.85), "trauma": 0.80},
	"CHAIN":          {"text": "CHAIN!",          "color": Color(1.00, 0.65, 0.30, 1), "size": 180, "ring": Color(1.00, 0.55, 0.20, 0.85), "trauma": 0.90},
	"LOCOMOTIVE":     {"text": "LOCOMOTIVE!",     "color": Color(0.85, 0.45, 1.00, 1), "size": 160, "ring": Color(0.75, 0.35, 1.00, 0.85), "trauma": 0.90},
	"AVALANCHE":      {"text": "AVALANCHE!",      "color": Color(0.55, 0.85, 1.00, 1), "size": 180, "ring": Color(0.45, 0.75, 1.00, 0.85), "trauma": 0.95},
	"STAMPEDE":       {"text": "STAMPEDE!",       "color": Color(1.00, 0.45, 0.35, 1), "size": 180, "ring": Color(1.00, 0.35, 0.25, 0.85), "trauma": 0.95},
	# Iter 121: 3D PREVIEW countdown — reuse banner system so the start-
	# of-level "3 / 2 / 1 / GO!" gets the same big-Rye-font + sparkles +
	# shock-ring treatment as sugar rush. (Iter 120 attempt at this didn't
	# actually land in the file even though the commit said it did —
	# Edit silently no-op'd on a unicode mismatch in old_string.)
	"READY":          {"text": "READY",          "color": Color(0.95, 0.78, 0.35, 1), "size": 180, "ring": Color(1.00, 0.85, 0.40, 0.70), "trauma": 0.30},
	"COUNT_3":        {"text": "3",              "color": Color(1.00, 0.55, 0.30, 1), "size": 280, "ring": Color(1.00, 0.50, 0.30, 0.80), "trauma": 0.40},
	"COUNT_2":        {"text": "2",              "color": Color(1.00, 0.70, 0.30, 1), "size": 280, "ring": Color(1.00, 0.60, 0.30, 0.80), "trauma": 0.40},
	"COUNT_1":        {"text": "1",              "color": Color(1.00, 0.85, 0.30, 1), "size": 280, "ring": Color(1.00, 0.70, 0.30, 0.80), "trauma": 0.40},
	"GO":             {"text": "GO",             "color": Color(0.42, 1.00, 0.55, 1), "size": 300, "ring": Color(0.40, 1.00, 0.50, 0.80), "trauma": 0.70},
}

@onready var label: Label = $Label
@onready var shock_ring: ColorRect = $ShockRing
@onready var sparkles: CPUParticles2D = $Sparkles

# Spawn a banner with a named preset. `parent` should be a CanvasLayer
# (typically level.$UI) so the banner doesn't scroll with gameplay and
# the anchors-to-parent layout works as designed.
#
# Camera shake is added to a `shake_source` if one is supplied — that's
# typically the level node (which has a ScreenShake RefCounted at .shake).
# Pass null to skip shake.
static func spawn(parent: Node, preset_name: String, shake_source: Node = null) -> void:
	if parent == null or not is_instance_valid(parent):
		return
	var data: Dictionary = PRESETS.get(preset_name, {
		"text": preset_name, "color": Color(1, 1, 1, 1), "size": 156,
		"ring": Color(1, 1, 1, 0.6), "trauma": 0.5,
	})
	# Iter 121: stack — when a new banner spawns, push existing FlourishBanner
	# siblings UPWARD by STACK_PUSH so they don't overlap. They keep their
	# fade-out lifecycle; this just slides them above the newcomer.
	for child in parent.get_children():
		if child is Control and child.has_meta("is_flourish_banner"):
			var existing_y: float = (child as Control).position.y
			var push_tween: Tween = (child as Control).create_tween()
			push_tween.tween_property(child, "position:y",
				existing_y - STACK_PUSH, 0.25) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	var banner: Control = SPAWN_SCENE.instantiate()
	banner.set_meta("is_flourish_banner", true)
	banner.set_meta("preset_name", preset_name)
	banner.set_meta("trauma", float(data.get("trauma", 0.5)))
	parent.add_child(banner)
	banner.play(data.text, data.color, data.size, data.ring)
	if shake_source and "shake" in shake_source and shake_source.shake \
			and shake_source.shake.has_method("add_trauma"):
		shake_source.shake.add_trauma(data.trauma)
	# Iter 142: ElevenLabs voice-over per banner. Slug from trigger key:
	# "TASTY!" → tasty, "JELLY_FRENZY" → jelly_frenzy, "COUNT_3" → count_3.
	# (Iter 139's conditional used get_node_or_null inside this static func,
	# which raised a runtime error and aborted spawn() partway — so banners
	# stopped showing in iter 139+. AudioBus is registered as an autoload
	# in project.godot so we can reference it as a global identifier here.)
	AudioBus.play_flourish(preset_name.replace("!", "").to_lower())

# Iter 89/91: max horizontal width the banner text should occupy. The
# iter 44 scale-pop tween briefly overshoots to scale 1.15× before
# settling at 1.0×, so the EFFECTIVE peak width is text_width × 1.15.
# To make the peak fit a 1000px target area, we measure against
# 1000 / 1.15 ≈ 870px instead. User report iter 90: 'text starts too
# large for the screen then shrinks' — that overshoot was the cause.
const MAX_TEXT_WIDTH: float = 870.0

# Iter 90: use the ACTUAL theme font's measurement via
# Font.get_string_size rather than a character-width heuristic. Iter 89's
# 0.55 ratio was too low — RAMPAGE!, YEEHAW!, RELUCTANTLY COMPETENT.
# still overflowed at their preset sizes because the theme font (chunky
# Western display) is wider per-character than the heuristic predicted.
func _fit_font_size_measured(target_label: Label, text: String, base: int) -> int:
	if target_label == null:
		return base
	var font: Font = target_label.get_theme_font("font", "Label")
	if font == null:
		# Fallback to the old heuristic with a higher 0.72 ratio if no
		# theme font is available (shouldn't happen in normal scene load).
		var approx_w: float = float(text.length()) * float(base) * 0.72
		if approx_w <= MAX_TEXT_WIDTH:
			return base
		return maxi(int(float(base) * (MAX_TEXT_WIDTH / approx_w)), 32)
	var measured: Vector2 = font.get_string_size(
		text, HORIZONTAL_ALIGNMENT_LEFT, -1, base
	)
	if measured.x <= MAX_TEXT_WIDTH:
		return base
	return maxi(int(float(base) * MAX_TEXT_WIDTH / measured.x), 32)

# ---- Soda-Crush text pass (owner notes 2026-06-10) -------------------------
const GLITTER_SHADER: Shader = preload("res://shaders/flourish_glitter.gdshader")
const SHEEN_SHADER: Shader = preload("res://shaders/flourish_sheen.gdshader")
const GOLD := Color(1.0, 0.84, 0.35, 1.0)
# Gold-Rush finishing flourishes use the two-row Soda-Crush animation.
const GOLDRUSH_KEYS: Array = ["PERFECT_VOLLEY", "SUGAR_CASCADE", "ROLLED",
	"CHAIN", "LOCOMOTIVE", "AVALANCHE", "STAMPEDE"]

# First letter of each word slightly larger (owner: Soda-Crush lettering).
# Pure + GUT-tested.
static func first_letter_bbcode(text: String, base_size: int) -> String:
	var big: int = int(base_size * 1.18)
	var words := text.split(" ")
	var out: Array = []
	for w in words:
		if w.length() == 0:
			out.append(w)
		else:
			out.append("[font_size=%d]%s[/font_size]%s" % [big, w.substr(0, 1), w.substr(1)])
	return " ".join(out)

# Split a finishing-flourish into the two Soda-Crush rows. Multi-word →
# first word / rest; single word → "GOLD RUSH" / word. Pure + GUT-tested.
static func split_rows(text: String) -> Array:
	var words := text.strip_edges().split(" ", false)
	if words.size() >= 2:
		var rest: Array = []
		for i in range(1, words.size()):
			rest.append(words[i])
		return [words[0], " ".join(rest)]
	return ["GOLD RUSH", text.strip_edges()]

# Animation style per preset. Pure + GUT-tested.
#   count    — 3/2/1/GO: classic pop in place (pastel + emboss)
#   goldrush — finishing flourishes: two-row Soda-Crush drop sequence
#   divine   — big feedback (trauma >= .75): rise-through + sparkle trail
#   rise     — everything else: rise from bottom, pause centre, exit top
static func style_for(preset_name: String, trauma: float) -> String:
	if preset_name.begins_with("COUNT_") or preset_name == "GO" or preset_name == "READY":
		return "count"
	if GOLDRUSH_KEYS.has(preset_name):
		return "goldrush"
	if trauma >= 0.75:
		return "divine"
	return "rise"

# Build one embossed text row: dark shadow copy (+3,+3), pale highlight copy
# (-2,-2), and the main layer carrying the sheen shader (gold by default,
# pastel tint for the countdown). Returns the row Control (full-width,
# centred text), with meta "row_h" = pixel height.
func _make_embossed_row(text: String, base_size: int, tint: Color) -> Control:
	var fitted: int = _fit_font_size_measured(label, text, base_size)
	var row := Control.new()
	row.set_anchors_preset(Control.PRESET_TOP_WIDE)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row_h: float = float(fitted) * 1.45
	row.custom_minimum_size = Vector2(0, row_h)
	# anchored controls reject direct size sets — height comes from the offset
	row.offset_bottom = row_h
	var layers: Array = [
		[Vector2(3, 4), Color(0.32, 0.18, 0.04, 0.9), null],
		[Vector2(-2, -2), Color(1.0, 0.97, 0.88, 0.85), null],
		[Vector2.ZERO, Color.WHITE, SHEEN_SHADER],
	]
	for spec in layers:
		var rtl := RichTextLabel.new()
		rtl.bbcode_enabled = true
		rtl.fit_content = true
		rtl.scroll_active = false
		rtl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rtl.set_anchors_preset(Control.PRESET_FULL_RECT)
		rtl.position = spec[0]
		rtl.add_theme_font_size_override("normal_font_size", fitted)
		rtl.text = "[center]%s[/center]" % first_letter_bbcode(text, fitted)
		if spec[2] != null:
			var mat := ShaderMaterial.new()
			mat.shader = spec[2]
			mat.set_shader_parameter("tint", tint)
			mat.set_shader_parameter("row_height", row_h)
			rtl.material = mat
		else:
			rtl.modulate = spec[1]
		row.add_child(rtl)
	row.set_meta("row_h", row_h)
	return row

# Plays the banner. Static spawn() calls this on the freshly-instantiated
# node; dispatches to the style fitting the preset (owner's Soda-Crush notes).
func play(text: String, color: Color, font_size: int, ring_color: Color) -> void:
	var preset_name: String = get_meta("preset_name", "")
	var trauma: float = get_meta("trauma", 0.5)
	match style_for(preset_name, trauma):
		"goldrush":
			_play_goldrush(text, font_size, ring_color)
		"divine":
			_play_rise(text, font_size, color, ring_color, true)
		"rise":
			_play_rise(text, font_size, color, ring_color, false)
		_:
			_play_count(text, color, font_size, ring_color)

# NORMAL (sugar-rush type): single embossed gold row rises from the bottom,
# pauses centre, exits off the top. DIVINE adds the falling sparkle trail.
func _play_rise(text: String, font_size: int, color: Color, ring_color: Color, divine: bool) -> void:
	label.visible = false
	shock_ring.visible = false
	var vp: Vector2 = get_viewport_rect().size
	var row := _make_embossed_row(text, font_size, GOLD)
	add_child(row)
	var row_h: float = row.get_meta("row_h")
	# Control root is anchored to vertical centre: local y=0 is screen centre.
	var below: float = vp.y * 0.5 + row_h
	var centre: float = -row_h * 0.5
	var above: float = -vp.y * 0.5 - row_h * 2.0
	row.position.y = below
	var trail: CPUParticles2D = null
	if divine:
		trail = CPUParticles2D.new()
		trail.amount = 90
		trail.lifetime = 0.9
		trail.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
		trail.emission_rect_extents = Vector2(vp.x * 0.28, 6)
		trail.position = Vector2(vp.x * 0.5, row_h)   # the row's bottom edge
		trail.direction = Vector2(0, 1)
		trail.initial_velocity_min = 30.0
		trail.initial_velocity_max = 90.0
		trail.gravity = Vector2(0, 240)
		trail.scale_amount_min = 2.0
		trail.scale_amount_max = 5.0
		var grad := Gradient.new()
		grad.set_color(0, Color(1.0, 0.95, 0.7, 0.95))   # heavy at the text
		grad.set_color(1, Color(1.0, 0.8, 0.5, 0.0))     # fades as it falls
		trail.color_ramp = grad
		trail.emitting = true
		row.add_child(trail)
	sparkles.color = color
	var tw := create_tween()
	tw.tween_property(row, "position:y", centre, 0.45) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func() -> void:
		sparkles.restart(); sparkles.emitting = true)
	tw.tween_interval(0.65)
	tw.tween_property(row, "position:y", above, 0.50) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await tw.finished
	queue_free()

# GOLD RUSH (Soda-Crush style): row 1 drops from the top and parks mid; row 2
# drops past it and parks just under; hold; row 2 exits bottom, then row 1.
# Big glowing sparkles play around the screen edges (never on the text).
func _play_goldrush(text: String, font_size: int, _ring_color: Color) -> void:
	label.visible = false
	shock_ring.visible = false
	AudioBus.play_flourish("gold_rush_jingle")
	var vp: Vector2 = get_viewport_rect().size
	var rows: Array = split_rows(text)
	var r1 := _make_embossed_row(rows[0], font_size, GOLD)
	var r2 := _make_embossed_row(rows[1], font_size, GOLD)
	add_child(r1)
	add_child(r2)
	var h1: float = r1.get_meta("row_h")
	var h2: float = r2.get_meta("row_h")
	var above: float = -vp.y * 0.5 - h1 * 2.0
	var park1: float = -h1 - 8.0          # just above screen centre
	var park2: float = 8.0                # right under row 1
	var below: float = vp.y * 0.5 + h2
	r1.position.y = above
	r2.position.y = above
	_goldrush_edge_sparkles(vp)
	var tw := create_tween()
	tw.tween_property(r1, "position:y", park1, 0.50) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.25)
	tw.tween_property(r2, "position:y", park2, 0.55) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.80)
	tw.tween_property(r2, "position:y", below, 0.45) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(r1, "position:y", below, 0.45) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await tw.finished
	queue_free()

# A handful of large soft-glowing sparkles in the screen margins (left/right
# thirds + top corners — clear of the central text column).
func _goldrush_edge_sparkles(vp: Vector2) -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var spots: Array = [
		Vector2(vp.x * 0.10, -vp.y * 0.30), Vector2(vp.x * 0.88, -vp.y * 0.34),
		Vector2(vp.x * 0.07, vp.y * 0.05), Vector2(vp.x * 0.92, vp.y * 0.10),
		Vector2(vp.x * 0.14, vp.y * 0.34), Vector2(vp.x * 0.85, vp.y * 0.30),
	]
	for i in range(spots.size()):
		var s := Label.new()
		s.text = "✦"
		s.add_theme_font_size_override("font_size", rng.randi_range(90, 150))
		s.add_theme_color_override("font_color",
			[GOLD, Color(1.0, 0.7, 0.9), Color(0.8, 0.9, 1.0)][i % 3])
		s.position = spots[i] - Vector2(vp.x * 0.5, 0)  # root x-anchors are full-wide; centre on x
		s.position.x = spots[i].x
		s.mouse_filter = Control.MOUSE_FILTER_IGNORE
		s.modulate.a = 0.0
		s.pivot_offset = Vector2(40, 40)
		add_child(s)
		var tw := s.create_tween()
		tw.tween_interval(rng.randf_range(0.0, 0.9))
		tw.tween_property(s, "modulate:a", 1.0, 0.35)
		tw.parallel().tween_property(s, "scale", Vector2(1.35, 1.35), 0.7) \
			.set_trans(Tween.TRANS_SINE)
		tw.tween_property(s, "modulate:a", 0.0, 0.5)

# COUNTDOWN (3/2/1/GO): the classic pop, now with the pastel-tinted emboss.
func _play_count(text: String, color: Color, font_size: int, ring_color: Color) -> void:
	# Owner notes 2026-06-10: keep the pastel colors but add the emboss —
	# the pop animation itself is unchanged (pacing slowed via COUNTDOWN_TOTAL).
	label.visible = false
	var row := _make_embossed_row(text, font_size, color)
	add_child(row)
	var row_h: float = row.get_meta("row_h")
	row.position.y = -row_h * 0.5
	row.pivot_offset = Vector2(get_viewport_rect().size.x * 0.5, row_h * 0.5)
	row.scale = Vector2(0.35, 0.35)
	row.modulate.a = 0.0

	shock_ring.color = ring_color
	shock_ring.scale = Vector2(0.1, 0.1)
	shock_ring.modulate.a = ring_color.a
	sparkles.color = color
	sparkles.restart()
	sparkles.emitting = true

	var pop: Tween = create_tween().set_parallel(true)
	pop.tween_property(row, "scale", Vector2(1.15, 1.15), POP_DURATION) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	pop.tween_property(row, "modulate:a", 1.0, 0.10)
	pop.tween_property(row, "position:y", row.position.y + DRIFT_UP, LIFESPAN) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	pop.tween_property(shock_ring, "scale", Vector2(4.0, 4.0), SHOCK_RING_DURATION) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	pop.tween_property(shock_ring, "modulate:a", 0.0, SHOCK_RING_DURATION) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await pop.finished
	var settle: Tween = create_tween()
	settle.tween_property(row, "scale", Vector2.ONE, 0.10)
	await settle.finished
	await get_tree().create_timer(LIFESPAN - POP_DURATION - 0.10 - 0.25).timeout
	var fade: Tween = create_tween()
	fade.tween_property(row, "modulate:a", 0.0, 0.25)
	await fade.finished
	queue_free()
