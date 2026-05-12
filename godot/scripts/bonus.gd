extends Node2D

# A bonus pickup dropped by a destroyed power-up barrel. Scrolls down at
# SCROLL_SPEED until the cowboy collides with it, at which point the
# level auto-equips the effect — NO tap-to-take prompt. The user's
# explicit design intent: a calculated player choice (is this rifle
# better than my six-shooter? do I want +2 dudes or do I trust my aim?).
# Tap-to-take would have broken the pacing; auto-equip preserves it.
#
# bonus_type strings recognized by level.gd's _equip_bonus():
#   "fast_fire"   — multiplies _gun.fire_interval by 0.7 (30% faster)
#   "extra_dude"  — posse_count += 2
#   "rifle"       — swap _gun to a slower, longer-range, harder-hitting Rifle
#
# Joins the "bonuses" group so level.gd's collision pass can find it.

signal equipped(type: String)

const SCROLL_SPEED: float = 220.0  # match barrels / obstacles
const SIZE: Vector2 = Vector2(50, 50)
const DESPAWN_Y: float = 2200.0

@export var bonus_type: String = ""

func _ready() -> void:
	add_to_group("bonuses")
	# Update the icon letter to match this bonus's type. The scene's
	# default text is "?" so an uninitialized bonus is visually obvious.
	var letter: Label = get_node_or_null("Letter") as Label
	if letter:
		letter.text = letter_for(bonus_type)

# Public so tests + scene editor can preview the mapping. Each bonus
# type gets a one- or two-glyph hint icon.
static func letter_for(type: String) -> String:
	match type:
		"fast_fire": return "F"
		"extra_dude": return "+D"
		"rifle": return "R"
		_: return "?"

func _process(delta: float) -> void:
	position.y += SCROLL_SPEED * delta
	# Safety net: a bonus the cowboy missed scrolls off the bottom.
	if position.y > DESPAWN_Y:
		queue_free()

# Called by the level's collision pass when the cowboy touches this
# bonus. Emits the equipped() signal so test code (and future listeners)
# can observe the equip event, then queue_frees so the same bonus can't
# fire twice.
func equip() -> void:
	equipped.emit(bonus_type)
	queue_free()
