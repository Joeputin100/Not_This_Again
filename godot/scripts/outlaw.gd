extends Node2D

# Vagrant outlaw — black-hat ranged enemy. Iter 36+: animated via
# VideoStreamPlayer + chromakey shader using 7 Veo-rendered animations.
# Tracks the posse + crowds (iter 31 AI) and now picks directional
# shooting animations based on relative cowboy position.
#
# Animations (godot/assets/videos/vagrant/):
#   idle_wobble    — drunk standing sway (loop)
#   drunk_walk     — unsteady forward gait (loop, replaces FORWARD)
#   strafe_left    — sideways shuffle (loop)
#   strafe_right   — sideways shuffle (loop)
#   shoot_left     — fires forward-left (one-shot overlay)
#   shoot_right    — fires forward-right (one-shot overlay)
#   shoot_down     — fires straight at camera (one-shot overlay)
#
# Death currently uses the iter 31 tween (user hasn't supplied a death
# video for the vagrant yet) — plus the universal DeathPolish (freeze
# + strobe).

const OutlawBulletScene := preload("res://scenes/outlaw_bullet.tscn")
const OutlawBulletScript := preload("res://scripts/outlaw_bullet.gd")
const MuzzleFlashScene := preload("res://scenes/muzzle_flash.tscn")
const DamagePopup := preload("res://scripts/damage_popup.gd")

const STREAM_IDLE := preload("res://assets/videos/vagrant/idle_wobble.ogv")
const STREAM_FORWARD := preload("res://assets/videos/vagrant/drunk_walk.ogv")
const STREAM_STRAFE_LEFT := preload("res://assets/videos/vagrant/strafe_left.ogv")
const STREAM_STRAFE_RIGHT := preload("res://assets/videos/vagrant/strafe_right.ogv")
const STREAM_SHOOT_LEFT := preload("res://assets/videos/vagrant/shoot_left.ogv")
const STREAM_SHOOT_RIGHT := preload("res://assets/videos/vagrant/shoot_right.ogv")
const STREAM_SHOOT_DOWN := preload("res://assets/videos/vagrant/shoot_down.ogv")
const STREAM_DEATH := preload("res://assets/videos/vagrant/death.ogv")

const DeathPolish := preload("res://scripts/death_polish.gd")

signal destroyed(x: float)

const MAX_HP: int = 10
const SCROLL_SPEED: float = 240.0
const STAY_SCROLL_SPEED: float = 25.0
const STAY_DISTANCE_Y: float = 250.0
const TRACK_SPEED: float = 1.4
const SIZE: Vector2 = Vector2(120, 200)
const COWBOY_DAMAGE: int = 15
const FIRE_INTERVAL: float = 1.2
# Bullet spawns from the vagrant's gun-hand. The vagrant.png art has
# the revolver raised; tuned offset for the 0.22 sprite scale era still
# works for the 150×270 video display.
const MUZZLE_OFFSET: Vector2 = Vector2(20, -20)
const ON_SCREEN_Y: float = 0.0

# Overlay durations. SHOOT animations are 4s clips but we cap the
# overlay so the vagrant isn't stuck in the firing pose between bullets.
const SHOOT_OVERLAY_DURATION: float = 0.35
# Strafe detection: horizontal velocity threshold (px/frame at 60fps)
# above which we switch to STRAFE_LEFT or STRAFE_RIGHT.
const STRAFE_VELOCITY_THRESHOLD: float = 1.5
# Horizontal distance (px) below which "shoot down" wins over
# "shoot left/right" — when the cowboy is nearly directly below.
const SHOOT_DOWN_BAND: float = 80.0

enum State { IDLE, FORWARD, STRAFE_LEFT, STRAFE_RIGHT, SHOOT_LEFT, SHOOT_RIGHT, SHOOT_DOWN, DEATH }

var hp: int = MAX_HP
var _destroyed: bool = false
var _fire_timer: float = 0.0
var _cowboy: Node2D = null
var _state: int = State.IDLE
var _override_timer: float = 0.0

@onready var hp_label: Label = $HpLabel
@onready var hp_bar: Control = $HpBar
@onready var splinters: CPUParticles2D = $Splinters
@onready var video: VideoStreamPlayer = $Video

func _ready() -> void:
	hp = MAX_HP
	_refresh_hp_label()
	if hp_bar:
		hp_bar.init(MAX_HP)
	add_to_group("outlaws")
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
	if _override_timer > 0.0:
		_override_timer -= delta
		if _override_timer <= 0.0:
			_apply_base_state()
	# Track + scroll
	var x_before: float = position.x
	if _cowboy:
		position.x = lerpf(position.x, _cowboy.position.x, clampf(TRACK_SPEED * delta, 0.0, 1.0))
	var dy: float = (_cowboy.position.y - position.y) if _cowboy else 1000.0
	position.y += (SCROLL_SPEED if dy > STAY_DISTANCE_Y else STAY_SCROLL_SPEED) * WorldSpeed.mult * delta
	if position.y > 2200.0:
		queue_free()
		return
	# Base state choice (skipped while overlay active).
	if _override_timer <= 0.0:
		var dx: float = position.x - x_before
		_apply_base_state(dx, dy)
	if position.y < ON_SCREEN_Y:
		return
	_fire_timer += delta
	if _fire_timer >= FIRE_INTERVAL:
		_fire_timer = 0.0
		_spawn_bullet()

func _apply_base_state(dx: float = 0.0, dy: float = 1000.0) -> void:
	if position.y < ON_SCREEN_Y:
		_switch_to(State.IDLE)
		return
	if dx < -STRAFE_VELOCITY_THRESHOLD:
		_switch_to(State.STRAFE_LEFT)
	elif dx > STRAFE_VELOCITY_THRESHOLD:
		_switch_to(State.STRAFE_RIGHT)
	elif dy > STAY_DISTANCE_Y:
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
		State.STRAFE_LEFT: video.stream = STREAM_STRAFE_LEFT
		State.STRAFE_RIGHT: video.stream = STREAM_STRAFE_RIGHT
		State.SHOOT_LEFT: video.stream = STREAM_SHOOT_LEFT
		State.SHOOT_RIGHT: video.stream = STREAM_SHOOT_RIGHT
		State.SHOOT_DOWN: video.stream = STREAM_SHOOT_DOWN
		State.DEATH: video.stream = STREAM_DEATH
	video.play()

func _spawn_bullet() -> void:
	var level := get_parent()
	if not level:
		return
	# Pick the matching directional shoot animation based on where the
	# cowboy is relative to this vagrant. SHOOT_DOWN when the cowboy is
	# in a narrow vertical band; SHOOT_LEFT/RIGHT for offset targets.
	var shoot_state: int = State.SHOOT_DOWN
	if _cowboy:
		var dx: float = _cowboy.position.x - position.x
		if absf(dx) < SHOOT_DOWN_BAND:
			shoot_state = State.SHOOT_DOWN
		elif dx < 0:
			shoot_state = State.SHOOT_LEFT
		else:
			shoot_state = State.SHOOT_RIGHT
	_switch_to(shoot_state)
	_override_timer = SHOOT_OVERLAY_DURATION
	var bullet := OutlawBulletScene.instantiate()
	var spawn_pos: Vector2 = position + MUZZLE_OFFSET
	bullet.position = spawn_pos
	if _cowboy:
		var dir: Vector2 = (_cowboy.position - spawn_pos).normalized()
		bullet.velocity = dir * OutlawBulletScript.SPEED
	level.add_child(bullet)
	var flash := MuzzleFlashScene.instantiate()
	flash.position = MUZZLE_OFFSET
	add_child(flash)

func take_bullet_hit(damage: int = 1) -> bool:
	if _destroyed:
		return false
	DamagePopup.spawn(get_parent(), global_position, damage)
	hp -= damage
	_refresh_hp_label()
	if hp_bar:
		hp_bar.set_hp(hp)
	_emit_splinter()
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
		splinters.amount = 40
		splinters.restart()
	# Iter 40c: switch to the Veo-rendered DEATH animation (vagrant looks
	# surprised, jumps back, falls with arms flailing — ~3s of motion).
	# Play it through, THEN run the universal DeathPolish strobe.
	# _override_timer is set absurdly high so no state transitions can
	# preempt DEATH while it plays. The await-on-finished pattern (used
	# elsewhere) doesn't fit a VideoStreamPlayer; instead we wait a fixed
	# duration matching the clip length.
	_switch_to(State.DEATH)
	_override_timer = 10.0  # block any state preemption
	# Death clip is 4s but the figure lies still after ~3s — pacing
	# feels right to start the strobe just before the clip ends.
	await get_tree().create_timer(3.0).timeout
	await DeathPolish.play(self)
	queue_free()
