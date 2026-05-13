extends Node2D

# Saguaro cactus — vertical, tall, narrow. Takes 36 bullets to destroy
# like a tumbleweed, but does NOT get pushed back when shot. Just stands
# its ground while you chip away. Collision damages the posse.

signal destroyed(x: float)

const MAX_HP: int = 36
const SCROLL_SPEED: float = 220.0
# Cactus is tall + narrow.
const SIZE: Vector2 = Vector2(80, 220)
const COWBOY_DAMAGE: int = 4  # spikes hurt more than soft tumbleweed

const DamagePopup = preload("res://scripts/damage_popup.gd")

var hp: int = MAX_HP
var _destroyed: bool = false

@onready var hp_label: Label = $HpLabel
@onready var hp_bar: Control = $HpBar
@onready var splinters: CPUParticles2D = $Splinters

func _ready() -> void:
	hp = MAX_HP
	_refresh_hp_label()
	if hp_bar:
		hp_bar.init(MAX_HP)
	add_to_group("cacti")

func _process(delta: float) -> void:
	if _destroyed:
		return
	position.y += SCROLL_SPEED * WorldSpeed.mult * delta
	if position.y > 2200.0:
		queue_free()

# Bullets damage but do NOT push back. `damage` = firing gun's caliber.
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
		splinters.amount = 50
		splinters.restart()
	var tween := create_tween().set_parallel(true)
	tween.tween_property(self, "modulate:a", 0.0, 0.4)
	# Cactus topples sideways on death — quick rotation to give it character.
	tween.tween_property(self, "rotation_degrees", 75.0, 0.4) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await tween.finished
	queue_free()
