extends Node2D

# Slippery Pete — Level 1 boss. Iter 31 update: shares the same tracking
# + aimed-fire behavior as iter 31's vagrant outlaw, but with boss-tier
# stats (4× HP, 2× contact damage, dual six-shooters firing 2 aimed
# bullets per tick). Crowds the posse on arrival and stays in range
# until killed — does NOT pass by like an iter 29 outlaw would have.
#
# Future iter 32: shout abuse / Yosemite-Sam insults that float above
# his head when hit, when low on HP, and when dying. Hooks for the
# dialog system are not in this iter — focus is on the gameplay AI.

const OutlawBulletScene := preload("res://scenes/outlaw_bullet.tscn")
const OutlawBulletScript := preload("res://scripts/outlaw_bullet.gd")
const MuzzleFlashScene := preload("res://scenes/muzzle_flash.tscn")

signal destroyed(x: float)

const MAX_HP: int = 40
const SCROLL_SPEED: float = 200.0
const STAY_SCROLL_SPEED: float = 18.0
# Pete crowds slightly less than a vagrant (300 vs 250) because his
# dual-fire pattern needs horizontal space to spread.
const STAY_DISTANCE_Y: float = 300.0
# Boss tracks more slowly than a vagrant — he's heavy, deliberate. 1.0
# means a ~1s catch-up vs vagrant's ~700ms. Gives a more "looming"
# silhouette.
const TRACK_SPEED: float = 1.0
const SIZE: Vector2 = Vector2(180, 280)
const COWBOY_DAMAGE: int = 30
const FIRE_INTERVAL: float = 0.7
# Horizontal offset of each pistol from Pete's center, matching the
# slippery_pete.png art. Two bullets spawn per fire tick, one from each.
const LEFT_GUN_X_OFFSET: float = 45.0
# Y-offset of bullet spawn — Pete's pistols are at chest/hip height.
const BULLET_SPAWN_Y_OFFSET: float = 30.0
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
	add_to_group("bosses")
	_cowboy = _find_cowboy()

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
	if _cowboy:
		position.x = lerpf(position.x, _cowboy.position.x, clampf(TRACK_SPEED * delta, 0.0, 1.0))
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
		_spawn_dual_bullets()

func _spawn_dual_bullets() -> void:
	var level := get_parent()
	if not level:
		return
	for offset_x in [-LEFT_GUN_X_OFFSET, LEFT_GUN_X_OFFSET]:
		var spawn_pos: Vector2 = position + Vector2(offset_x, BULLET_SPAWN_Y_OFFSET)
		var bullet := OutlawBulletScene.instantiate()
		bullet.position = spawn_pos
		if _cowboy:
			var dir: Vector2 = (_cowboy.position - spawn_pos).normalized()
			bullet.velocity = dir * OutlawBulletScript.SPEED
		level.add_child(bullet)
		# One muzzle flash per pistol, parented to Pete so they track
		# during the brief flash animation.
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
