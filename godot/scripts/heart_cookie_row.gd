class_name HeartCookieRow
extends Control

# Sprite-based lives row (replaces the vector-drawn HeartRow). Full = frosted
# heart cookie, empty = plain dough cookie. 2+ full hearts dance together;
# the last lone heart looks lonely; a regenerated slot pops in with a cheer.
# set_hearts(current, maximum) matches HeartRow's contract.

const DIR := "res://assets/sprites/ui/winflow/"
const FULL := preload("res://assets/sprites/ui/winflow/heart_full.png")
const EMPTY := preload("res://assets/sprites/ui/winflow/heart_empty.png")

# Default layout is a flat horizontal row (used by the win/fail modals, the
# main menu and the splash). The in-level taffy HUD sets `staggered = true`,
# which scatters the cookies in a ring around a central gap so a big outlaw
# number can sit in the middle, framed by the hearts.
@export var staggered: bool = false

var _current: int = 5
var _max: int = 5
var _slots: Array = []   # TextureRect per slot

static func _is_lonely_count(c: int) -> bool:
	return c == 1

func _is_lonely(c: int) -> bool:
	return HeartCookieRow._is_lonely_count(c)

func _is_regen(new_current: int) -> bool:
	return new_current > _current

func set_hearts(current: int, maximum: int) -> void:
	var regen := _is_regen(current)
	var regen_slot := _current   # the slot that just filled (0-based index)
	_current = clampi(current, 0, maxi(maximum, 1))
	_max = maxi(maximum, 1)
	_rebuild()
	if regen and regen_slot < _slots.size():
		_play_regen(regen_slot)

# Returns [centre_pos, size] for slot `i` in the current layout. The position
# is the cookie's top-left; centre_pos is the visual centre used as the tween
# anchor (so dance/lonely/regen behave the same in either layout).
func _slot_geometry(i: int) -> Array:
	if staggered:
		return _slot_geometry_staggered(i)
	var slot_w: float = size.x / float(_max)
	var sz: float = minf(slot_w * 0.9, size.y)
	var pos := Vector2(slot_w * (float(i) + 0.5) - sz * 0.5, (size.y - sz) * 0.5)
	return [pos, sz]

# Scatters the cookies in a staggered ring around the row's centre, leaving a
# clear central gap (for the big outlaw number). Cookies alternate up/down and
# fan out across the width; bigger than the flat row so they read clearly.
func _slot_geometry_staggered(i: int) -> Array:
	var n: int = maxi(_max, 1)
	var sz: float = minf(size.x / float(n) * 1.18, size.y * 0.62)
	var cx: float = size.x * 0.5
	var cy: float = size.y * 0.5
	# Spread the cookies across the width, framing a central gap. Fraction in
	# [-1, 1] from left to right; the centre slots are pushed outward so the
	# number is not crowded.
	var frac: float = 0.0
	if n > 1:
		frac = (float(i) / float(n - 1)) * 2.0 - 1.0
	var x: float = cx + frac * (size.x * 0.5 - sz * 0.5)
	# Alternate the vertical offset so the ring staggers; the outermost cookies
	# ride a touch lower so the whole cluster hugs the number.
	var stagger: float = (1.0 if (i % 2 == 0) else -1.0) * size.y * 0.18
	var dip: float = absf(frac) * size.y * 0.10
	var y: float = cy + stagger + dip
	return [Vector2(x - sz * 0.5, y - sz * 0.5), sz]

func _rebuild() -> void:
	for s in _slots:
		if is_instance_valid(s): s.queue_free()
	_slots.clear()
	for i in range(_max):
		var node := TextureRect.new()
		node.texture = FULL if i < _current else EMPTY
		node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		node.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		var geo: Array = _slot_geometry(i)
		var pos: Vector2 = geo[0]
		var sz: float = geo[1]
		node.custom_minimum_size = Vector2(sz, sz)
		node.size = Vector2(sz, sz)
		node.position = pos
		node.pivot_offset = Vector2(sz * 0.5, sz)   # pivot at the bottom-centre
		add_child(node)
		_slots.append(node)
		if i < _current:
			if _is_lonely(_current): _animate_lonely(node)
			else: _animate_dance(node, float(i) * 0.28)

func _animate_dance(node: Control, delay: float) -> void:
	var t := node.create_tween().set_loops()
	t.tween_interval(delay)
	# gentle ~2.2s sway: hop + tilt with squash-stretch on the landing
	t.tween_property(node, "rotation_degrees", 8.0, 1.1).set_trans(Tween.TRANS_SINE)
	t.parallel().tween_property(node, "position:y", node.position.y - 6.0, 0.55)
	t.parallel().tween_property(node, "position:y", node.position.y, 0.55).set_delay(0.55)
	t.tween_property(node, "rotation_degrees", -8.0, 1.1).set_trans(Tween.TRANS_SINE)

func _animate_lonely(node: Control) -> void:
	node.modulate = Color(0.92, 0.92, 0.92, 1.0)
	var t := node.create_tween().set_loops()
	t.tween_property(node, "rotation_degrees", -3.0, 1.6).set_trans(Tween.TRANS_SINE)
	t.tween_property(node, "rotation_degrees", -7.0, 1.6).set_trans(Tween.TRANS_SINE)

func _play_regen(slot: int) -> void:
	if slot >= _slots.size(): return
	var node: Control = _slots[slot]
	node.scale = Vector2(0.2, 0.2)
	var t := node.create_tween()
	t.tween_property(node, "scale", Vector2(1.15, 1.15), 0.35) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(node, "scale", Vector2.ONE, 0.15)
	if has_node("/root/AudioBus"):
		get_node("/root/AudioBus").play_sfx("heart_regen_cheer")
