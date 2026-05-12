extends Node2D

# Slippery Pete — Level 1 boss. Bigger, beefier, dual-wielding outlaw.
# Scrolls down slower than vagrants (200 vs 240) but fires TWO bullets
# per tick from his left + right pistols, takes 4× the HP, and deals
# 2× contact damage. The first proper boss encounter in the game.
#
# Visual is the slippery_pete.png hand-drawn cartoon — bearded, snarling,
# dual six-shooters, red bandana. Sized larger than a vagrant so the
# player reads "this is a boss, not just another mook" immediately.
#
# Designed so a 5-dude posse with a fast_fire bonus and rifle has a fair
# fight: rifle (caliber 3) takes ~14 hits to drop Pete; Pete fires once
# per 0.7s in a 14s approach window = ~20 dual-bullet salvos = 40 bullets
# × 2 damage = 80 potential posse damage. Player needs to land hits
# quickly and dodge gracefully — meaningful skill check.

const OutlawBulletScene := preload("res://scenes/outlaw_bullet.tscn")

signal destroyed(x: float)

const MAX_HP: int = 40
const SCROLL_SPEED: float = 200.0
const SIZE: Vector2 = Vector2(180, 280)
const COWBOY_DAMAGE: int = 30
# Dual six-shooters fire faster than a vagrant's single revolver.
const FIRE_INTERVAL: float = 0.7
# Each gun's horizontal offset from Pete's center — matches the
# slippery_pete.png art where he holds a pistol in each hand.
const LEFT_GUN_X_OFFSET: float = 45.0
const BULLET_SPAWN_Y_OFFSET: float = 130.0
const ON_SCREEN_Y: float = 0.0

var hp: int = MAX_HP
var _destroyed: bool = false
var _fire_timer: float = 0.0

@onready var hp_label: Label = $HpLabel
@onready var splinters: CPUParticles2D = $Splinters

func _ready() -> void:
	hp = MAX_HP
	_refresh_hp_label()
	# Joins the "outlaws" group so the existing level.gd collision
	# passes (_resolve_bullet_obstacle_collisions("outlaws", ...) and
	# _resolve_obstacle_cowboy_collisions("outlaws", ...)) catch Pete
	# without code changes. The boss-y stats above are what differentiate
	# Pete from a regular vagrant for the player.
	add_to_group("outlaws")
	add_to_group("bosses")

func _process(delta: float) -> void:
	if _destroyed:
		return
	position.y += SCROLL_SPEED * delta
	if position.y > 2200.0:
		queue_free()
		return
	if position.y < ON_SCREEN_Y:
		return
	_fire_timer += delta
	if _fire_timer >= FIRE_INTERVAL:
		_fire_timer = 0.0
		_spawn_dual_bullets()

# Spawns two bullets per tick — one from each visible pistol. Both
# travel straight down via OutlawBullet's existing physics. The horizontal
# spread forces the player to dodge a wider hit pattern than a single
# vagrant produces.
func _spawn_dual_bullets() -> void:
	var level := get_parent()
	if not level:
		return
	var left_bullet := OutlawBulletScene.instantiate()
	left_bullet.position = position + Vector2(-LEFT_GUN_X_OFFSET, BULLET_SPAWN_Y_OFFSET)
	level.add_child(left_bullet)
	var right_bullet := OutlawBulletScene.instantiate()
	right_bullet.position = position + Vector2(LEFT_GUN_X_OFFSET, BULLET_SPAWN_Y_OFFSET)
	level.add_child(right_bullet)

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
		splinters.amount = 80
		splinters.restart()
	# Boss death: longer, bigger, more dramatic than vagrant death.
	# Player needs the visual feedback that they've felled the big bad.
	var tween := create_tween().set_parallel(true)
	tween.tween_property(self, "modulate:a", 0.0, 0.7)
	tween.tween_property(self, "scale", Vector2(1.5, 1.5), 0.7) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "rotation_degrees", 25.0, 0.7) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await tween.finished
	queue_free()
