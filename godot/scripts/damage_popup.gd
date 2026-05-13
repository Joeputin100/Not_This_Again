extends Label

# Floating damage number that pops above a hit target, rises while
# fading, then frees itself. Ported from the roguelike project's
# addFloatingText mechanic (state.js:714, render.js ~1055). Tuned
# for portrait mobile + Candy Crush polish:
#   - Bigger font for bigger damage (visual weight encodes magnitude)
#   - Red text with dark outline so it reads against any background
#   - Cubic ease-out on y-rise so it pops up fast, then drifts
#   - 600ms lifespan — long enough to read, short enough not to clutter
#   - Small random horizontal jitter so rapid-fire bullets don't stack
#     popups directly on top of one another (gun fires ~6 bullets/sec
#     at base fire rate, so adjacent popups want a few px of separation
#     to remain individually legible)
#
# Call from any take_damage / take_bullet_hit method:
#   DamagePopup.spawn(get_parent(), global_position, damage_amount)
#
# The popup is parented to the LEVEL (typically get_parent()), not the
# enemy itself, so it keeps rising and fading even after the enemy is
# destroyed and queue_free'd. Otherwise the popup would vanish along
# with its target on the killing blow.

const SPAWN_SCENE: PackedScene = preload("res://scenes/damage_popup.tscn")

# Total time from spawn to queue_free. Both rise and fade complete in
# this window; the popup never lingers at zero alpha.
const LIFESPAN: float = 0.6

# Total vertical pixels the popup floats upward over its lifespan.
# Cubic ease-out means most of this distance is covered in the first
# ~200ms — fast pop, then a slow drift.
const RISE_DISTANCE: float = 80.0

# Random ±X jitter on spawn so consecutive popups at the same world
# position don't stack and become unreadable. Bullets at 6/s spawn
# popups ~167ms apart — within the 600ms lifespan they're all visible
# simultaneously, so spreading them across a band keeps them legible.
const X_JITTER: float = 28.0

# Damage → font size mapping. Each band represents a different gameplay
# beat: 1 = "bullet tick", 2-3 = "rifle round", 4-8 = "barrel hit",
# 9-20 = "heavy hit / posse loss", 21+ = "boss damage / explosion". The
# size jumps are intentionally chunky so the player feels the magnitude
# difference at a glance rather than having to read the digits.
static func _size_for_damage(damage: int) -> int:
	if damage <= 1:
		return 40
	elif damage <= 3:
		return 56
	elif damage <= 8:
		return 72
	elif damage <= 20:
		return 92
	else:
		return 112

# Spawn a BOUNTY popup at world_pos. Gold color, "+" prefix instead of
# "-", uses the same scale + lifespan as damage. Iter 43b: used by the
# end-of-level Gold Rush ceremony where each remaining dude fires their
# gun and a +50 BOUNTY popup floats up from their position. Visually
# distinct from damage popups (different color, different prefix) so
# the player reads "bonus earned" vs "enemy hurt" at a glance.
static func spawn_bounty(parent: Node, world_pos: Vector2, amount: int) -> void:
	if parent == null or not is_instance_valid(parent):
		return
	if amount <= 0:
		return
	var popup: Label = SPAWN_SCENE.instantiate()
	parent.add_child(popup)
	popup.text = "+%d" % amount
	# Gold color override — the popup scene defaults to red damage tint.
	popup.add_theme_color_override("font_color", Color(1.00, 0.92, 0.30, 1.0))
	popup.add_theme_font_size_override("font_size", _size_for_damage(amount))
	var jitter_x: float = randf_range(-X_JITTER, X_JITTER)
	popup.global_position = world_pos + Vector2(jitter_x - 160.0, -60.0)
	var tween: Tween = popup.create_tween().set_parallel(true)
	tween.tween_property(popup, "global_position:y",
		popup.global_position.y - RISE_DISTANCE, LIFESPAN) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(popup, "modulate:a", 0.0, LIFESPAN) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(popup.queue_free)

# Spawn a damage popup at world_pos. parent should typically be the
# level (so the popup outlives the killed enemy). damage drives both
# the text content and the font size.
static func spawn(parent: Node, world_pos: Vector2, damage: int) -> void:
	if parent == null or not is_instance_valid(parent):
		return
	if damage <= 0:
		return
	var popup: Label = SPAWN_SCENE.instantiate()
	parent.add_child(popup)
	popup.text = "-%d" % damage
	popup.add_theme_font_size_override("font_size", _size_for_damage(damage))
	# Center the label on world_pos. The custom_minimum_size on the
	# scene (320×120) is the bounding box for text; we offset top-left
	# so that box centers on the target.
	var jitter_x: float = randf_range(-X_JITTER, X_JITTER)
	popup.global_position = world_pos + Vector2(jitter_x - 160.0, -60.0)
	# Parallel tweens: rise + fade simultaneously. CUBIC EASE_OUT means
	# the popup leaps up the first 60-70% of the rise distance in the
	# first ~200ms, then drifts the rest of the way slowly. Reads as
	# "snap upward" rather than a constant glide. Fade uses QUAD EASE_IN
	# so the popup stays fully visible for the first ~300ms (when it's
	# most informative) and then fades quickly toward the end.
	var tween: Tween = popup.create_tween().set_parallel(true)
	tween.tween_property(popup, "global_position:y",
		popup.global_position.y - RISE_DISTANCE, LIFESPAN) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(popup, "modulate:a", 0.0, LIFESPAN) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	# chain() takes the tween out of parallel mode for the cleanup step.
	tween.chain().tween_callback(popup.queue_free)
