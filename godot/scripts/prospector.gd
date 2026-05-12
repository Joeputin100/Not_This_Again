extends Node2D

# Prospector — melee-only enemy. Iter 33+: animated via VideoStreamPlayer
# + chromakey shader (same pattern as Slippery Pete in iter 32). Six
# Veo-rendered animations: idle_drinking, steps_forward, strafe_left,
# strafe_right, reacts_to_gunshot, death.
#
# AI behavior (unchanged from iter 31):
#   - Tracks cowboy.x via lerpf at TRACK_SPEED (imperfect lag)
#   - Forward scroll at SCROLL_SPEED, STAY_SCROLL_SPEED crawl in range
#   - try_swing() on melee range overlap, called by level.gd
#   - HP bar above head
#
# State machine for video animations:
#   - DEATH overlays everything on _play_destroy_animation
#   - HIT overlays briefly on take_bullet_hit (REACTS_TO_GUNSHOT video)
#   - STRAFE_LEFT/RIGHT when horizontal velocity is significant
#   - FORWARD when scrolling forward
#   - IDLE_DRINKING otherwise (off-screen, in crawl, or stable position)

const DamagePopup = preload("res://scripts/damage_popup.gd")

const STREAM_IDLE := preload("res://assets/videos/prospector/idle_drinking.ogv")
const STREAM_FORWARD := preload("res://assets/videos/prospector/steps_forward.ogv")
const STREAM_STRAFE_LEFT := preload("res://assets/videos/prospector/strafe_left.ogv")
const STREAM_STRAFE_RIGHT := preload("res://assets/videos/prospector/strafe_right.ogv")
const STREAM_HIT := preload("res://assets/videos/prospector/reacts_to_gunshot.ogv")
const STREAM_DEATH := preload("res://assets/videos/prospector/death.ogv")

const DeathPolish := preload("res://scripts/death_polish.gd")
const HIT_OVERLAY_DURATION: float = 0.45
const DEATH_DURATION: float = 4.0  # prospector death is 4s (vs Pete's 8s)
# Per-frame horizontal velocity (px/frame at 60fps) above which we
# switch from FORWARD/IDLE to STRAFE_LEFT or STRAFE_RIGHT.
const STRAFE_VELOCITY_THRESHOLD: float = 1.5

signal destroyed(x: float)

const MAX_HP: int = 20
const SCROLL_SPEED: float = 220.0
const STAY_SCROLL_SPEED: float = 30.0
const STAY_DISTANCE_Y: float = 180.0
const TRACK_SPEED: float = 1.6
const SIZE: Vector2 = Vector2(140, 220)
const SWING_DAMAGE: int = 5
const SWING_INTERVAL: float = 0.8
const ON_SCREEN_Y: float = 0.0

enum State { IDLE, FORWARD, STRAFE_LEFT, STRAFE_RIGHT, HIT, DEATH }

var hp: int = MAX_HP
var _destroyed: bool = false
var _swing_cooldown_timer: float = 0.0
var _cowboy: Node2D = null
var _state: int = State.IDLE
var _override_timer: float = 0.0
var _last_x: float = 0.0

@onready var hp_label: Label = $HpLabel
@onready var hp_bar: Control = $HpBar
@onready var splinters: CPUParticles2D = $Splinters
@onready var video: VideoStreamPlayer = $Video

func _ready() -> void:
	hp = MAX_HP
	_refresh_hp_label()
	if hp_bar:
		hp_bar.init(MAX_HP)
	add_to_group("prospectors")
	_cowboy = _find_cowboy()
	_last_x = position.x
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
	_swing_cooldown_timer = maxf(0.0, _swing_cooldown_timer - delta)
	if _override_timer > 0.0:
		_override_timer -= delta
		if _override_timer <= 0.0:
			_apply_base_state()
	# Track + scroll
	var x_before: float = position.x
	if _cowboy:
		position.x = lerpf(position.x, _cowboy.position.x, clampf(TRACK_SPEED * delta, 0.0, 1.0))
	var dy: float = (_cowboy.position.y - position.y) if _cowboy else 1000.0
	position.y += (SCROLL_SPEED if dy > STAY_DISTANCE_Y else STAY_SCROLL_SPEED) * delta
	if position.y > 2200.0:
		queue_free()
		return
	# Base state choice (skipped while HIT overlay active).
	if _override_timer <= 0.0:
		var dx: float = position.x - x_before
		_apply_base_state(dx, dy)
	_last_x = position.x

func _apply_base_state(dx: float = 0.0, dy: float = 1000.0) -> void:
	if position.y < ON_SCREEN_Y:
		_switch_to(State.IDLE)
		return
	# Strafe when lateral velocity is significant AND we're still
	# approaching forward (otherwise idle/drink in crawl phase).
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
		State.HIT: video.stream = STREAM_HIT
		State.DEATH: video.stream = STREAM_DEATH
	video.play()

# Returns true and resets the swing cooldown if off-cooldown; false
# otherwise. Called by level.gd's melee collision pass.
func try_swing() -> bool:
	if _swing_cooldown_timer > 0.0:
		return false
	_swing_cooldown_timer = SWING_INTERVAL
	return true

func take_bullet_hit(damage: int = 1) -> bool:
	if _destroyed:
		return false
	DamagePopup.spawn(get_parent(), global_position, damage)
	hp -= damage
	_refresh_hp_label()
	if hp_bar:
		hp_bar.set_hp(hp)
	_emit_splinter()
	# Brief HIT overlay — plays REACTS_TO_GUNSHOT video for 0.45s,
	# then reverts to base state.
	_switch_to(State.HIT)
	_override_timer = HIT_OVERLAY_DURATION
	if hp <= 0:
		_destroyed = true
		destroyed.emit(position.x)
		_play_destroy_animation()
	return true

func get_cowboy_damage() -> int:
	return SWING_DAMAGE

func _refresh_hp_label() -> void:
	if hp_label:
		hp_label.text = str(maxi(hp, 0))

func _emit_splinter() -> void:
	if splinters:
		splinters.restart()
		splinters.emitting = true

func _play_destroy_animation() -> void:
	if splinters:
		splinters.amount = 50
		splinters.restart()
	# Iter 33+: death video + universal freeze-strobe polish.
	if video:
		video.loop = false
		video.stream = STREAM_DEATH
		video.play()
		await get_tree().create_timer(DEATH_DURATION).timeout
	await DeathPolish.play(self)
	queue_free()
