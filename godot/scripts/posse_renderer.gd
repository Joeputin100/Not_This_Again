extends Node2D

# Renders the (posse_count - 1) followers of the leader cowboy in a
# loose, jittering trapezoid formation. The level.gd Cowboy node remains
# the gameplay-authoritative leader — its position drives target_x,
# collision math, and bullet spawn. This renderer is purely visual: it
# spawns dude scene instances as children of itself, anchors to the
# leader via set_leader_position(), and applies per-dude sinusoidal
# jitter so the crowd feels alive (not a rigid lattice).
#
# Lifecycle (per posse_count change):
#   - new > current: spawn (new - current) dudes, fade + scale in.
#   - new < current: tween (current - new) dudes out (fade) then free.
#   - active dudes are repositioned to the cached formation slots.
#
# Cached formation positions are recomputed ONLY when posse_count
# changes (via the setter). _process applies cheap jitter on top of
# the cache — no per-frame trig over the full formation array.

const PosseFormation = preload("res://scripts/posse_formation.gd")
const PosseDudeScene = preload("res://scenes/posse_dude.tscn")

# Sinusoidal jitter — each dude carries its own phase so the crowd
# doesn't move in lockstep. Amplitude is in pixels; freq is rad/sec for
# a clean ~1.7Hz wobble.
const JITTER_AMPLITUDE: float = 8.0
const JITTER_FREQUENCY: float = 1.7

# Fade/scale-in for newly-spawned dudes (posse grew).
const SPAWN_FADE_DURATION: float = 0.25
const SPAWN_SCALE_FROM: float = 0.5

# Fade-out for departing dudes (posse shrunk). queue_free after.
const DESPAWN_FADE_DURATION: float = 0.2

# Currently-active dude instances. Excludes "leaving" dudes that are
# mid-tween-out (those are still in the scene tree until queue_free,
# but logically gone from the formation).
var _active_dudes: Array[Node2D] = []

# Cached follower offsets relative to the leader. Recomputed only when
# posse_count changes (cheap per change, vs. per-frame).
var _cached_offsets: Array[Vector2] = []

# Elapsed time used as the phase argument for jitter sinusoids.
var _elapsed: float = 0.0

var posse_count: int = 1:
	set(value):
		var new_count: int = maxi(1, value)
		if new_count == posse_count and not _active_dudes.is_empty():
			# No-op if count unchanged AND we've already initialized. The
			# initial set from level.gd's _ready needs to fire through even
			# when value==default, hence the is_empty() guard.
			return
		posse_count = new_count
		_rebuild_formation()

func _process(delta: float) -> void:
	_elapsed += delta
	# Apply per-dude jitter on top of the cached base offset. Skip dudes
	# without base_pos metadata (defensive — shouldn't happen, but cheap).
	for dude in _active_dudes:
		if dude == null or not is_instance_valid(dude):
			continue
		var base_pos: Vector2 = dude.get_meta("base_pos", Vector2.ZERO)
		var phase_x: float = dude.get_meta("phase_x", 0.0)
		var phase_y: float = dude.get_meta("phase_y", 0.0)
		var jx: float = JITTER_AMPLITUDE * sin(_elapsed * JITTER_FREQUENCY + phase_x)
		var jy: float = JITTER_AMPLITUDE * cos(_elapsed * JITTER_FREQUENCY + phase_y)
		dude.position = base_pos + Vector2(jx, jy)

# Called from level.gd's _process each frame to anchor the formation to
# wherever the leader cowboy currently is. Cheap (just sets position).
func set_leader_position(pos: Vector2) -> void:
	position = pos

# Returns the number of currently-active followers (excludes those
# mid-tween-out). Used by tests to verify formation size.
func active_follower_count() -> int:
	return _active_dudes.size()

# Iter 25+: switches every active dude's AnimatedSprite2D to the given
# animation. Used by level.gd on win → "idle" so the crowd stops looking
# like it's still running into a wall after the bounty appears.
func set_animation(anim_name: String) -> void:
	for dude in _active_dudes:
		if dude == null or not is_instance_valid(dude):
			continue
		var sprite: AnimatedSprite2D = dude.get_node_or_null("Sprite") as AnimatedSprite2D
		if sprite and sprite.sprite_frames and sprite.sprite_frames.has_animation(anim_name):
			sprite.play(anim_name)

# Iter 25+: returns world-space positions of every active follower —
# used by level.gd to spawn a muzzle flash at each dude on every shot
# (visual fix for "only the leader has a muzzle flash"). Each position
# includes the current jitter offset, so flashes track wobble naturally.
func get_dude_world_positions() -> Array[Vector2]:
	var positions: Array[Vector2] = []
	for dude in _active_dudes:
		if dude == null or not is_instance_valid(dude):
			continue
		positions.append(global_position + dude.position)
	return positions

# Rebuilds the formation when posse_count changes. Spawns new dudes,
# tweens out departing ones, and reassigns cached offsets to actives.
func _rebuild_formation() -> void:
	_cached_offsets = PosseFormation.compute_positions(posse_count)
	var target_count: int = _cached_offsets.size()
	var current_count: int = _active_dudes.size()

	if target_count > current_count:
		# Grow: spawn new dudes, tween in.
		for i in range(target_count - current_count):
			var dude := _spawn_dude()
			_active_dudes.append(dude)
	elif target_count < current_count:
		# Shrink: remove the LAST few dudes (rearmost in formation, so
		# the crowd visibly thins from the back rather than from the
		# leader's flanks).
		var to_remove: int = current_count - target_count
		for i in range(to_remove):
			var dude: Node2D = _active_dudes.pop_back()
			_despawn_dude(dude)

	# Reassign base positions for all active dudes from the cached
	# offsets. (Order in _active_dudes mirrors order in _cached_offsets.)
	for i in range(_active_dudes.size()):
		var dude: Node2D = _active_dudes[i]
		if dude == null or not is_instance_valid(dude):
			continue
		dude.set_meta("base_pos", _cached_offsets[i])
		# Snap to base immediately so newly-spawned dudes appear at
		# their slot (jitter overlays on next _process tick).
		dude.position = _cached_offsets[i]

func _spawn_dude() -> Node2D:
	var dude: Node2D = PosseDudeScene.instantiate()
	dude.set_meta("phase_x", randf() * TAU)
	dude.set_meta("phase_y", randf() * TAU)
	dude.set_meta("base_pos", Vector2.ZERO)
	dude.modulate.a = 0.0
	dude.scale = Vector2(SPAWN_SCALE_FROM, SPAWN_SCALE_FROM)
	add_child(dude)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(dude, "modulate:a", 1.0, SPAWN_FADE_DURATION)
	tween.tween_property(dude, "scale", Vector2.ONE, SPAWN_FADE_DURATION) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	return dude

func _despawn_dude(dude: Node2D) -> void:
	if dude == null or not is_instance_valid(dude):
		return
	# Mark so _process skips it. Not strictly needed since we already
	# removed it from _active_dudes, but a defensive flag for any
	# debug/inspection code that walks get_children().
	dude.set_meta("leaving", true)
	var tween := create_tween()
	tween.tween_property(dude, "modulate:a", 0.0, DESPAWN_FADE_DURATION)
	await tween.finished
	if is_instance_valid(dude):
		dude.queue_free()
