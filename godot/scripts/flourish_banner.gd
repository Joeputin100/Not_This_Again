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
const PRESETS: Dictionary = {
	"DOUBLE!":     {"text": "DOUBLE!",      "color": Color(1.00, 0.95, 0.40, 1), "size": 156, "ring": Color(1.00, 0.85, 0.30, 0.7), "trauma": 0.55},
	"MEGA!":       {"text": "MEGA!",        "color": Color(1.00, 0.55, 0.95, 1), "size": 200, "ring": Color(1.00, 0.45, 0.95, 0.7), "trauma": 0.75},
	"TASTY!":      {"text": "TASTY!",       "color": Color(1.00, 0.40, 0.50, 1), "size": 180, "ring": Color(1.00, 0.30, 0.45, 0.7), "trauma": 0.60},
	"JUICY!":      {"text": "JUICY!",       "color": Color(0.45, 1.00, 0.65, 1), "size": 180, "ring": Color(0.35, 1.00, 0.55, 0.7), "trauma": 0.60},
	"YEEHAW!":     {"text": "YEEHAW!",      "color": Color(1.00, 0.80, 0.30, 1), "size": 200, "ring": Color(1.00, 0.70, 0.20, 0.7), "trauma": 0.65},
	"RAMPAGE!":    {"text": "RAMPAGE!",     "color": Color(1.00, 0.35, 0.30, 1), "size": 220, "ring": Color(1.00, 0.25, 0.20, 0.75), "trauma": 0.85},
	"SWEET!":      {"text": "SWEET!",       "color": Color(1.00, 0.65, 0.95, 1), "size": 170, "ring": Color(1.00, 0.55, 0.95, 0.7), "trauma": 0.55},
	"FLAWLESS!":   {"text": "FLAWLESS!",    "color": Color(0.50, 0.95, 1.00, 1), "size": 200, "ring": Color(0.40, 0.85, 1.00, 0.7), "trauma": 0.70},
	"JELLY_FRENZY":{"text": "JELLY BEAN FRENZY!", "color": Color(1.00, 0.55, 0.85, 1), "size": 144, "ring": Color(1.00, 0.85, 0.40, 0.8), "trauma": 0.95},
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

# Plays the banner. Static spawn() calls this on the freshly-instantiated
# node; can also be called directly if the caller wants custom text
# outside the preset library.
func play(text: String, color: Color, font_size: int, ring_color: Color) -> void:
	# ---- Label setup ----
	label.text = text
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", font_size)
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
