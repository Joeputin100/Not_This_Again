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
	var banner: Control = SPAWN_SCENE.instantiate()
	parent.add_child(banner)
	banner.play(data.text, data.color, data.size, data.ring)
	if shake_source and "shake" in shake_source and shake_source.shake \
			and shake_source.shake.has_method("add_trauma"):
		shake_source.shake.add_trauma(data.trauma)

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

# Plays the banner. Static spawn() calls this on the freshly-instantiated
# node; can also be called directly if the caller wants custom text
# outside the preset library.
func play(text: String, color: Color, font_size: int, ring_color: Color) -> void:
	# ---- Label setup ----
	label.text = text
	label.add_theme_color_override("font_color", color)
	# Iter 90: accurate font measurement via the actual theme font.
	# Previous heuristic (0.55 ratio) under-estimated character widths
	# for the chunky Western display font — banners like YEEHAW! and
	# RAMPAGE! still overflowed at their nominal preset sizes.
	label.add_theme_font_size_override("font_size",
		_fit_font_size_measured(label, text, font_size))
	# pivot for scale-pop tween — center of the label's bounding box.
	label.pivot_offset = label.size / 2.0
	label.scale = Vector2(0.35, 0.35)
	label.modulate.a = 0.0

	# ---- Shock ring setup ----
	shock_ring.color = ring_color
	shock_ring.scale = Vector2(0.1, 0.1)
	shock_ring.modulate.a = ring_color.a

	# ---- Sparkles tint ----
	sparkles.color = color
	sparkles.restart()
	sparkles.emitting = true

	# ---- Parallel pop tween: scale-overshoot + alpha-in + drift up ----
	var pop: Tween = create_tween().set_parallel(true)
	pop.tween_property(label, "scale", Vector2(1.15, 1.15), POP_DURATION) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	pop.tween_property(label, "modulate:a", 1.0, 0.10)
	pop.tween_property(label, "position:y",
		label.position.y + DRIFT_UP, LIFESPAN) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# Shock ring: rapid expand-out + fade.
	pop.tween_property(shock_ring, "scale", Vector2(4.0, 4.0), SHOCK_RING_DURATION) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	pop.tween_property(shock_ring, "modulate:a", 0.0, SHOCK_RING_DURATION) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

	# After the pop completes, settle to 1.0 scale, hold briefly, then fade.
	await pop.finished
	var settle: Tween = create_tween().set_parallel(true)
	settle.tween_property(label, "scale", Vector2.ONE, 0.10)
	await settle.finished
	await get_tree().create_timer(LIFESPAN - POP_DURATION - 0.10 - 0.25).timeout
	var fade: Tween = create_tween()
	fade.tween_property(label, "modulate:a", 0.0, 0.25)
	await fade.finished
	queue_free()
