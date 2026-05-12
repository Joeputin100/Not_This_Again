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
		# Iter 31+: if the caller has already removed dudes manually via
		# kill_specific_dude(), the renderer's internal state may already
		# match the new count. Skip rebuild in that case so the surviving
		# dudes keep their existing formation slots (no reshuffle on death).
		if new_count == _active_dudes.size() + 1:
			posse_count = new_count
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

# Iter 25+: switches every active dude's animation. Iter 28+: dudes now
# wrap a Cowboy3D node (3D Mixamo model rendered to a SubViewport-backed
# Sprite2D), so we delegate to its play_anim() rather than poking an
# AnimatedSprite2D.
func set_animation(anim_name: String) -> void:
	for dude in _active_dudes:
		if dude == null or not is_instance_valid(dude):
			continue
		var c3d: Node2D = dude.get_node_or_null("Cowboy3D") as Node2D
		if c3d and c3d.has_method("play_anim"):
			c3d.play_anim(anim_name)

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

# Iter 31+: returns each active follower as a dict with the node
# reference + world-space rect, for per-dude bullet collision checks
# in level.gd. The bullet-kills-dude flow needs to identify the
# SPECIFIC dude hit, then call kill_specific_dude(node) to remove just
# that one (rather than the rear-most via posse_count decrement).
func get_follower_world_rects() -> Array:
	var result: Array = []
	for dude in _active_dudes:
		if dude == null or not is_instance_valid(dude):
			continue
		result.append({
			"node": dude,
			"position": global_position + dude.position,
			"size": Vector2(120, 200),  # matches the visible cowboy sprite
		})
	return result

# Iter 31+: removes a specific dude from the formation without
# triggering a formation rebuild. Use when a bullet identifies and
# kills a particular follower. Caller is responsible for updating its
# posse_count tracking AFTER calling this — the renderer's
# posse_count setter detects post-kill alignment and won't rebuild.
# Returns true if the dude was active; false if not in the list.
func kill_specific_dude(dude: Node2D) -> bool:
	if not (dude in _active_dudes):
		return false
	_active_dudes.erase(dude)
	_despawn_dude(dude)
	return true

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
