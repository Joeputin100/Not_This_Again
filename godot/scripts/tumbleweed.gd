extends Node2D

# A rolling tumbleweed — round, scrolls down toward the cowboy.
# Shooting it pushes it back marginally AND chips away at its HP.
# Takes 36 shots to fully destroy. Splinters on each hit.
# Collision with cowboy damages the posse.

signal destroyed(x: float)

const MAX_HP: int = 36
const SCROLL_SPEED: float = 220.0
const SIZE: Vector2 = Vector2(120, 120)
const PUSHBACK_PER_HIT: float = 14.0
const COWBOY_DAMAGE: int = 3

var hp: int = MAX_HP
var _destroyed: bool = false

@onready var hp_label: Label = $HpLabel
@onready var splinters: CPUParticles2D = $Splinters

func _ready() -> void:
	hp = MAX_HP
	_refresh_hp_label()
	add_to_group("tumbleweeds")

func _process(delta: float) -> void:
	if _destroyed:
		return
	position.y += SCROLL_SPEED * delta
	if position.y > 2200.0:
		queue_free()

# Called by level.gd's bullet collision pass. `damage` is the firing
# gun's caliber — six-shooter sends 1, future high-caliber guns send more.
func take_bullet_hit(damage: int = 1) -> bool:
	if _destroyed:
		return false
	hp -= damage
	# Marginal pushback — tumbleweeds resist the bullet stream slightly.
	position.y -= PUSHBACK_PER_HIT
	_refresh_hp_label()
	_emit_splinter()
	if hp <= 0:
		_destroyed = true
		destroyed.emit(position.x)
		_play_destroy_animation()
	return true

# Called by level.gd on cowboy collision.
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
		splinters.amount = 60
		splinters.restart()
	var tween := create_tween().set_parallel(true)
	tween.tween_property(self, "modulate:a", 0.0, 0.4)
	tween.tween_property(self, "scale", Vector2(1.3, 1.3), 0.4) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await tween.finished
	queue_free()
