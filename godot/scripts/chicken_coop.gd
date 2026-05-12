extends Node2D

# Wooden chicken coop — destructible obstacle. Takes MAX_HP bullets to
# destroy. On destruction, spawns CHICKEN_COUNT loose chickens that
# scatter in random directions (vision blocker + visual chaos, see
# chicken.gd). No cowboy collision damage (the coop is decorative
# scenery; the chaos is the consequence).

signal destroyed(coop_x: float)

const ChickenScene := preload("res://scenes/chicken.tscn")

const MAX_HP: int = 10
const SCROLL_SPEED: float = 220.0
const SIZE: Vector2 = Vector2(140, 130)
const CHICKEN_COUNT_MIN: int = 6
const CHICKEN_COUNT_MAX: int = 10
const COWBOY_DAMAGE: int = 0  # coop is decorative; chickens are the payload

var hp: int = MAX_HP
var _destroyed: bool = false

@onready var hp_label: Label = $HpLabel
@onready var splinters: CPUParticles2D = $Splinters

func _ready() -> void:
	hp = MAX_HP
	_refresh_hp_label()
	add_to_group("chicken_coops")

func _process(delta: float) -> void:
	if _destroyed:
		return
	position.y += SCROLL_SPEED * delta
	if position.y > 2200.0:
		queue_free()

func take_bullet_hit(damage: int = 1) -> bool:
	if _destroyed:
		return false
	hp -= damage
	_refresh_hp_label()
	_emit_splinter()
	if hp <= 0:
		_destroyed = true
		destroyed.emit(position.x)
		_release_chickens()
		_play_destroy_animation()
	return true

func get_cowboy_damage() -> int:
	return COWBOY_DAMAGE

func _release_chickens() -> void:
	var n := randi_range(CHICKEN_COUNT_MIN, CHICKEN_COUNT_MAX)
	# Add chickens to the SAME parent as the coop (the level), so they
	# share the world transform. Position them clustered at the coop
	# spot — chicken.gd's random-heading picker handles their scatter.
	var level := get_parent()
	if not level:
		return
	for i in n:
		var c := ChickenScene.instantiate()
		c.position = position + Vector2(randf_range(-30, 30), randf_range(-30, 30))
		level.add_child(c)

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
	tween.tween_property(self, "modulate:a", 0.0, 0.35)
	tween.tween_property(self, "scale", Vector2(1.25, 1.25), 0.35) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await tween.finished
	queue_free()
