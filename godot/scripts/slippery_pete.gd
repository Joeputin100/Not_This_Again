extends Node2D

# Slippery Pete — Level 1 boss. Iter 32+: animated via VideoStreamPlayer
# with chromakey shader instead of the static Sprite2D iter 30 used.
# Five animations provided by the user (4s each, 720×1280, 24fps,
# H.264 → re-encoded to WebM/VP9 for Godot 4 native playback):
#
#   idle               → taps_foot_idle.webm
#   forward            → steps_forward.webm
#   strafe (one-way)   → strafe_right_to_left.webm (flipped for L→R)
#   shoot              → shoots_at_player.webm
#   hit                → hit_by_gunfire.webm
#
# Still to come from user: death, celebration, shouting abuse. For now
# death is the existing scale/rotation tween; celebration not used yet.
# Abuse dialog (iter 32+) will be wired separately through Text.random().
#
# State machine: BASE state (idle/forward) determined by Pete's
# position/scrolling. OVERLAY states (shoot, hit) override the base
# briefly via _override_timer, then revert. Avoids spammy state changes
# when Pete fires + gets hit on the same frame.

const OutlawBulletScene := preload("res://scenes/outlaw_bullet.tscn")
const OutlawBulletScript := preload("res://scripts/outlaw_bullet.gd")
const MuzzleFlashScene := preload("res://scenes/muzzle_flash.tscn")

const STREAM_IDLE := preload("res://assets/videos/pete/taps_foot_idle.ogv")
const STREAM_FORWARD := preload("res://assets/videos/pete/steps_forward.ogv")
const STREAM_STRAFE := preload("res://assets/videos/pete/strafe_right_to_left.ogv")
const STREAM_SHOOT := preload("res://assets/videos/pete/shoots_at_player.ogv")
const STREAM_HIT := preload("res://assets/videos/pete/hit_by_gunfire.ogv")

signal destroyed(x: float)

const MAX_HP: int = 40
const SCROLL_SPEED: float = 200.0
const STAY_SCROLL_SPEED: float = 18.0
const STAY_DISTANCE_Y: float = 300.0
const TRACK_SPEED: float = 1.0
const SIZE: Vector2 = Vector2(180, 280)
const COWBOY_DAMAGE: int = 30
const FIRE_INTERVAL: float = 0.7
const LEFT_GUN_X_OFFSET: float = 45.0
const BULLET_SPAWN_Y_OFFSET: float = 30.0
const ON_SCREEN_Y: float = 0.0

# How long shoot/hit animations override the base state. Both source
# clips are 4s but Pete fires every 0.7s and gets hit far more often,
# so we clip the overlay duration to keep state changes snappy.
const SHOOT_OVERLAY_DURATION: float = 0.35
const HIT_OVERLAY_DURATION: float = 0.45

enum State { IDLE, FORWARD, STRAFE_LEFT, STRAFE_RIGHT, SHOOT, HIT }

var hp: int = MAX_HP
var _destroyed: bool = false
var _fire_timer: float = 0.0
var _cowboy: Node2D = null
var _state: int = State.IDLE
var _override_timer: float = 0.0

@onready var hp_label: Label = $HpLabel
@onready var hp_bar: Control = $HpBar
@onready var name_label: Label = $NameLabel
@onready var splinters: CPUParticles2D = $Splinters
@onready var video: VideoStreamPlayer = $Video

func _ready() -> void:
	hp = MAX_HP
	_refresh_hp_label()
	if hp_bar:
		hp_bar.init(MAX_HP)
	if name_label:
		name_label.text = Text.get("boss.slippery_pete_name") if Text else "SLIPPERY PETE"
	add_to_group("outlaws")
	add_to_group("bosses")
	_cowboy = _find_cowboy()
	_switch_to(State.IDLE)

func _find_cowboy() -> Node2D:
	var level := get_parent()
	if level:
		var c := level.get_node_or_null("Cowboy")
		if c:
			return c as Node2D
	return get_tree().root.find_child("Cowboy", true, false) as Node2D

func _process(delta: float) -> void:
	if _destroyed:
		return
	# Update overlay timer for momentary states (shoot/hit). When it
	# runs out, revert to the base state determined by movement.
	if _override_timer > 0.0:
		_override_timer -= delta
		if _override_timer <= 0.0:
			_apply_base_state()
	if _cowboy:
		position.x = lerpf(position.x, _cowboy.position.x, clampf(TRACK_SPEED * delta, 0.0, 1.0))
	var dy: float = (_cowboy.position.y - position.y) if _cowboy else 1000.0
	position.y += (SCROLL_SPEED if dy > STAY_DISTANCE_Y else STAY_SCROLL_SPEED) * delta
	if position.y > 2200.0:
		queue_free()
		return
	# Update base state (skipped if overlay is active — overlay reverts
	# via the timer above, then base state is reapplied).
	if _override_timer <= 0.0:
		_apply_base_state()
	if position.y < ON_SCREEN_Y:
		return
	_fire_timer += delta
	if _fire_timer >= FIRE_INTERVAL:
		_fire_timer = 0.0
		_spawn_dual_bullets()

func _apply_base_state() -> void:
	# IDLE while off-screen or close to cowboy (crawl phase). FORWARD
	# while scrolling toward cowboy. Strafe state is currently unused
	# — kept in the enum for iter 33 when sideways tracking velocity
	# is high enough to read as "strafing."
	if position.y < ON_SCREEN_Y:
		_switch_to(State.IDLE)
	elif _cowboy and (_cowboy.position.y - position.y) > STAY_DISTANCE_Y:
		_switch_to(State.FORWARD)
	else:
		_switch_to(State.IDLE)

func _switch_to(new_state: int) -> void:
	if new_state == _state:
		return
	_state = new_state
	if video == null:
		return
	match new_state:
		State.IDLE: video.stream = STREAM_IDLE
		State.FORWARD: video.stream = STREAM_FORWARD
		State.STRAFE_LEFT:
			video.stream = STREAM_STRAFE
			video.scale.x = absf(video.scale.x) * -1.0  # flip for L direction
		State.STRAFE_RIGHT:
			video.stream = STREAM_STRAFE
			video.scale.x = absf(video.scale.x)
		State.SHOOT: video.stream = STREAM_SHOOT
		State.HIT: video.stream = STREAM_HIT
	video.play()

func _spawn_dual_bullets() -> void:
	var level := get_parent()
	if not level:
		return
	# Switch to SHOOT animation briefly. Even if HIT is also queued,
	# SHOOT takes precedence because firing is something we initiated;
	# HIT can re-fire on the next take_bullet_hit and override again.
	_switch_to(State.SHOOT)
	_override_timer = SHOOT_OVERLAY_DURATION
	for offset_x in [-LEFT_GUN_X_OFFSET, LEFT_GUN_X_OFFSET]:
		var spawn_pos: Vector2 = position + Vector2(offset_x, BULLET_SPAWN_Y_OFFSET)
		var bullet := OutlawBulletScene.instantiate()
		bullet.position = spawn_pos
		if _cowboy:
			var dir: Vector2 = (_cowboy.position - spawn_pos).normalized()
			bullet.velocity = dir * OutlawBulletScript.SPEED
		level.add_child(bullet)
		var flash := MuzzleFlashScene.instantiate()
		flash.position = Vector2(offset_x, BULLET_SPAWN_Y_OFFSET)
		add_child(flash)

func take_bullet_hit(damage: int = 1) -> bool:
	if _destroyed:
		return false
	hp -= damage
	_refresh_hp_label()
	if hp_bar:
		hp_bar.set_hp(hp)
	_emit_splinter()
	# Trigger HIT overlay. If currently in SHOOT, replace it — getting
	# shot is the more immediate event for the player to feel.
	_switch_to(State.HIT)
	_override_timer = HIT_OVERLAY_DURATION
	if hp <= 0:
		_destroyed = true
		destroyed.emit(position.x)
		_play_destroy_animation()
	return true

func get_cowboy_damage() -> int:
	return COWBOY_DAMAGE

func _refresh_hp_label() -> void:
	if hp_label:
		hp_label.text = str(maxi(hp, 0))

func _emit_splinter() -> void:
	if splinters:
		splinters.restart()
		splinters.emitting = true

func _play_destroy_animation() -> void:
	if splinters:
		splinters.amount = 80
		splinters.restart()
	var tween := create_tween().set_parallel(true)
	tween.tween_property(self, "modulate:a", 0.0, 0.7)
	tween.tween_property(self, "scale", Vector2(1.5, 1.5), 0.7) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "rotation_degrees", 25.0, 0.7) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await tween.finished
	queue_free()
