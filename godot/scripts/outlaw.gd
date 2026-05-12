extends Node2D

# Iter 31 rewrite: vagrant black-hat outlaw with tracking AI + aimed
# fire + HP bar. Replaces the iter 29 "scroll down + fire straight
# down" behavior with:
#   - lerps horizontal position toward cowboy.x (imperfect tracking
#     via TRACK_SPEED — the lag is intentional, gives the player a
#     window to dodge sideways).
#   - scrolls forward at SCROLL_SPEED only while > STAY_DISTANCE_Y px
#     above the cowboy. Within that range, crawls at STAY_SCROLL_SPEED
#     so the vagrant CROWDS the posse instead of passing by.
#   - each fired OutlawBullet aims at cowboy.position via the bullet's
#     velocity vector (iter 31 OutlawBullet.velocity).
#   - spawns a small muzzle flash at the visible gun position.
#   - floats an HpBar above the head, updated on every take_bullet_hit.

const OutlawBulletScene := preload("res://scenes/outlaw_bullet.tscn")
const OutlawBulletScript := preload("res://scripts/outlaw_bullet.gd")
const MuzzleFlashScene := preload("res://scenes/muzzle_flash.tscn")

signal destroyed(x: float)

const MAX_HP: int = 10
const SCROLL_SPEED: float = 240.0
# Crawl speed once within STAY_DISTANCE_Y of the cowboy. Slow enough
# that the vagrant doesn't run over the cowboy, fast enough to apply
# pressure if the player ignores them.
const STAY_SCROLL_SPEED: float = 25.0
# Distance above cowboy.y at which the vagrant transitions to crawl.
# 250 leaves the sprites ~100px apart visually — in-the-face but not
# overlapping.
const STAY_DISTANCE_Y: float = 250.0
# Lerp rate for horizontal tracking. Lower = more imperfect (more lag).
# 1.4 gives a ~700ms catch-up to a sudden cowboy lane change at 60fps.
const TRACK_SPEED: float = 1.4
const SIZE: Vector2 = Vector2(120, 200)
const COWBOY_DAMAGE: int = 15
const FIRE_INTERVAL: float = 1.2
# Bullet spawns from the vagrant's gun hand. vagrant.png has the gun
# raised at the cowboy's mid-right; tuned offset in node-local coords
# after the 0.22 sprite scale.
const MUZZLE_OFFSET: Vector2 = Vector2(20, -20)
const ON_SCREEN_Y: float = 0.0

var hp: int = MAX_HP
var _destroyed: bool = false
var _fire_timer: float = 0.0
var _cowboy: Node2D = null

@onready var hp_label: Label = $HpLabel
@onready var hp_bar: Control = $HpBar
@onready var splinters: CPUParticles2D = $Splinters

func _ready() -> void:
	hp = MAX_HP
	_refresh_hp_label()
	if hp_bar:
		hp_bar.init(MAX_HP)
	add_to_group("outlaws")
	_cowboy = _find_cowboy()

func _find_cowboy() -> Node2D:
	# Cowboy is a fixed-name child of the level. Search the parent first
	# (cheap & specific) before falling back to the broader scene tree.
	var level := get_parent()
	if level:
		var c := level.get_node_or_null("Cowboy")
		if c:
			return c as Node2D
	return get_tree().root.find_child("Cowboy", true, false) as Node2D

func _process(delta: float) -> void:
	if _destroyed:
		return
	# Horizontal tracking — lerp toward cowboy.x. The lerp(a, b, t) flavor
	# t = TRACK_SPEED * delta gives frame-rate-independent lag.
	if _cowboy:
		position.x = lerpf(position.x, _cowboy.position.x, clampf(TRACK_SPEED * delta, 0.0, 1.0))
	# Forward scroll, switching to crawl near the cowboy.
	var dy: float = (_cowboy.position.y - position.y) if _cowboy else 1000.0
	position.y += (SCROLL_SPEED if dy > STAY_DISTANCE_Y else STAY_SCROLL_SPEED) * delta
	if position.y > 2200.0:
		queue_free()
		return
	if position.y < ON_SCREEN_Y:
		return
	_fire_timer += delta
	if _fire_timer >= FIRE_INTERVAL:
		_fire_timer = 0.0
		_spawn_bullet()

func _spawn_bullet() -> void:
	var level := get_parent()
	if not level:
		return
	var bullet := OutlawBulletScene.instantiate()
	var spawn_pos: Vector2 = position + MUZZLE_OFFSET
	bullet.position = spawn_pos
	# Aim at the cowboy. If no cowboy (shouldn't happen in normal play),
	# fall back to straight down.
	if _cowboy:
		var dir: Vector2 = (_cowboy.position - spawn_pos).normalized()
		bullet.velocity = dir * OutlawBulletScript.SPEED
	level.add_child(bullet)
	# Muzzle flash at the gun position, parented to the vagrant so it
	# follows during the ~200ms animation. Scale of the flash is already
	# 0.17 in muzzle_flash.tscn (iter 31's 1/3-size reduction).
	var flash := MuzzleFlashScene.instantiate()
	flash.position = MUZZLE_OFFSET
	add_child(flash)

func take_bullet_hit(damage: int = 1) -> bool:
	if _destroyed:
		return false
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
	var tween := create_tween().set_parallel(true)
	tween.tween_property(self, "modulate:a", 0.0, 0.4)
	tween.tween_property(self, "scale", Vector2(1.3, 1.3), 0.4) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await tween.finished
	queue_free()
