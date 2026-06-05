class_name StarRating
extends Control

# Candy star-rating: 1..3 difficulty-matched candies seated in a top-down
# oval boat dish. set_rating(difficulty, earned) fills `earned` slots with the
# breathing candy; the rest show a faint ghost. Pure layout data is static so
# it is unit-testable without instancing the scene.

const DIR := "res://assets/sprites/ui/winflow/"
const CANDY_BY_DIFFICULTY := {1: "star_pepper", 2: "star_gold", 3: "star_gummy", 4: "star_sugar"}
# Slot centres as (x,y) fraction of the dish box; index 0 used for 1-star,
# 0+2 for 2-star, all three for 3-star. Centre slot is slightly larger.
const SLOT_FRACS := [Vector2(0.50, 0.50), Vector2(0.28, 0.50), Vector2(0.72, 0.50)]
const SLOT_SIZE := [1.0, 0.92, 0.92]   # centre bigger

static func candy_tex_path(difficulty: int) -> String:
	var name: String = CANDY_BY_DIFFICULTY.get(difficulty, "star_pepper")
	return DIR + name + ".png"

# Which slot indices are used for a given star count (so they stay centred).
static func slots_for(stars: int) -> Array:
	match clampi(stars, 0, 3):
		1: return [0]
		2: return [1, 2]
		3: return [0, 1, 2]
		_: return []

@onready var _dish: TextureRect = $Dish

# When false the oval boat Dish is hidden so the candy stars sit directly on the
# level-select orb (the map instances set this false). Defaults true so the
# win/fail MODALS keep their dish exactly as before. Candy slot positions are
# fractions of the WIDGET size (not the dish), so hiding the dish is safe.
var show_dish: bool = true

var _difficulty: int = 1
var _earned: int = 0
var _candies: Array = []   # holds spawned candy/ghost nodes
# When false, the per-candy internal breathe tween is suppressed (used by the
# level-select map orbs, which drive the whole widget's pulse from the orb's
# own breathe so it stays in lockstep instead of double-pulsing). Default true
# keeps the modal / win-flow usage breathing exactly as before.
var breathe_enabled: bool = true

func _ready() -> void:
	# The widget is purely decorative; it must never intercept taps (on the map it
	# sits on top of the orb tap-areas). Make the root + dish pass touches through.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _dish != null:
		_dish.mouse_filter = Control.MOUSE_FILTER_IGNORE

func set_rating(difficulty: int, earned: int, animate: bool = false) -> void:
	_difficulty = difficulty
	_earned = clampi(earned, 0, 3)
	_rebuild(animate)

# Map orbs hide the oval boat dish so the candies sit directly on the orb.
# Defaults true (modals keep their dish). Safe because candy positions are
# fractions of the widget size, not of the dish.
func set_dish_visible(v: bool) -> void:
	show_dish = v
	if _dish == null:
		_dish = get_node_or_null("Dish") as TextureRect
	if _dish != null:
		_dish.visible = v
	_rebuild(false)

func _rebuild(animate: bool) -> void:
	for c in _candies:
		if is_instance_valid(c): c.queue_free()
	_candies.clear()
	if _dish != null:
		_dish.visible = show_dish
	var box: Vector2 = size
	var tex := load(candy_tex_path(_difficulty)) as Texture2D
	var lit: Array = slots_for(_earned)
	# Without the dish the candies read alone on the orb, so size them a touch
	# bigger so they stay legible; with the dish, keep the original size.
	var candy_frac: float = 0.36 if not show_dish else 0.30
	for i in range(3):
		var frac: Vector2 = SLOT_FRACS[i]
		var sz: float = box.x * candy_frac * SLOT_SIZE[i]
		var node := TextureRect.new()
		node.texture = tex
		node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		node.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		node.custom_minimum_size = Vector2(sz, sz)
		node.size = Vector2(sz, sz)
		node.position = Vector2(frac.x * box.x - sz * 0.5, frac.y * box.y - sz * 0.5)
		node.pivot_offset = Vector2(sz * 0.5, sz * 0.5)
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE  # purely decorative; never eat taps meant for the orb beneath
		if lit.has(i):
			if breathe_enabled:
				_breathe(node, float(lit.find(i)) * 0.25)
			if animate: _pop_in(node, float(lit.find(i)) * 0.18)
		else:
			node.modulate = Color(1, 1, 1, 0.28)   # ghost slot
		add_child(node)
		_candies.append(node)

func _breathe(node: Control, delay: float) -> void:
	var t := node.create_tween().set_loops()
	t.tween_interval(delay)
	t.tween_property(node, "scale", Vector2(1.06, 1.06), 0.95).set_trans(Tween.TRANS_SINE)
	t.tween_property(node, "scale", Vector2.ONE, 0.95).set_trans(Tween.TRANS_SINE)

func _pop_in(node: Control, delay: float) -> void:
	node.scale = Vector2(0.2, 0.2)
	var t := node.create_tween()
	t.tween_interval(delay)
	t.tween_property(node, "scale", Vector2.ONE, 0.4) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if has_node("/root/AudioBus"):
		t.tween_callback(get_node("/root/AudioBus").play_sfx.bind("bonus_pickup"))
