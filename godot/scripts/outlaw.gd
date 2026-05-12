extends Node2D

# An outlaw — black-hat antagonist that scrolls DOWN toward the cowboy
# at SCROLL_SPEED, firing OutlawBullets at FIRE_INTERVAL while it's
# on-screen. Takes MAX_HP posse bullets to destroy (caliber-aware via
# take_bullet_hit's damage param, iter 21+ convention). If it reaches
# the cowboy alive, contact deals COWBOY_DAMAGE — high enough to make
# letting one through expensive but survivable for a healthy posse.
#
# Movement is straight scroll for v1 — no side-to-side dodge, no AI.
# Outlaws are added to scenes/level.tscn as static positioned instances.
# Future iters: spawned by level builder, varying speeds / fire rates,
# multi-stage boss outlaws.

const OutlawBulletScene := preload("res://scenes/outlaw_bullet.tscn")

signal destroyed(x: float)

const MAX_HP: int = 10
const SCROLL_SPEED: float = 240.0
# Outlaw collision-rect — slightly wider than the cowboy hitbox so they
# read as "menacing" on the playfield. Tune on device.
const SIZE: Vector2 = Vector2(120, 200)
# Contact damage if the outlaw reaches the cowboy alive. Half a barricade
# (10) hit, enough to make ignoring outlaws costly without one-shotting
# a starting 5-dude posse.
const COWBOY_DAMAGE: int = 15
# Bullets per second. 1.2s interval ≈ 0.83 shots/sec — slow enough to
# give the player visible projectiles to dodge, fast enough to threaten.
const FIRE_INTERVAL: float = 1.2
# Bullet spawn is below the outlaw's center so the muzzle visually
# lines up with the lower half of the body.
const BULLET_SPAWN_Y_OFFSET: float = 100.0
# Only fire while on-screen (>= ON_SCREEN_Y). Stops outlaws from
# pre-emptively shooting before the player can see them.
const ON_SCREEN_Y: float = 0.0

var hp: int = MAX_HP
var _destroyed: bool = false
var _fire_timer: float = 0.0

@onready var hp_label: Label = $HpLabel
@onready var splinters: CPUParticles2D = $Splinters

func _ready() -> void:
	hp = MAX_HP
	_refresh_hp_label()
	add_to_group("outlaws")

func _process(delta: float) -> void:
	if _destroyed:
		return
	position.y += SCROLL_SPEED * delta
	if position.y > 2200.0:
		# Off the bottom — shouldn't happen normally (would have hit
		# cowboy first) but defensive so dead outlaws don't linger.
		queue_free()
		return
	if position.y < ON_SCREEN_Y:
		return
	_fire_timer += delta
	if _fire_timer >= FIRE_INTERVAL:
		_fire_timer = 0.0
		_spawn_bullet()

func _spawn_bullet() -> void:
	var bullet := OutlawBulletScene.instantiate()
	bullet.position = position + Vector2(0, BULLET_SPAWN_Y_OFFSET)
	var level := get_parent()
	if level:
		level.add_child(bullet)

func take_bullet_hit(damage: int = 1) -> bool:
	if _destroyed:
		return false
	hp -= damage
	_refresh_hp_label()
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
	var tween := create_tween().set_parallel(true)
	tween.tween_property(self, "modulate:a", 0.0, 0.4)
	tween.tween_property(self, "scale", Vector2(1.3, 1.3), 0.4) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await tween.finished
	queue_free()
