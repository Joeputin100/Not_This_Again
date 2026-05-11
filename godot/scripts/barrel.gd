extends Node2D

# A wooden barrel barricade — scrolls down toward the cowboy at scroll_speed,
# takes max_hp shots before being destroyed. HP label on top updates per hit.
# Added to "barrels" group so level.gd's collision pass can find it.

signal destroyed(barrel_x: float)

@export var max_hp: int = 4
@export var scroll_speed: float = 220.0

const SIZE: Vector2 = Vector2(140, 140)

var hp: int
var _destroyed: bool = false

@onready var hp_label: Label = $HpLabel
@onready var sparkles: CPUParticles2D = $Sparkles

func _ready() -> void:
	hp = max_hp
	_refresh_hp_label()
	add_to_group("barrels")

func _process(delta: float) -> void:
	if _destroyed:
		return
	position.y += scroll_speed * delta
	# Despawn if it scrolled past the bottom — safety net so unfought
	# barrels don't accumulate forever.
	if position.y > 2200.0:
		queue_free()

# Called by level.gd's collision pass when a bullet hits this barrel.
# Returns true if the barrel was destroyed by this shot.
func take_damage(amount: int = 1) -> bool:
	if _destroyed:
		return false
	hp -= amount
	_refresh_hp_label()
	# Subtle hit reaction so the player FEELS the impact.
	_hit_flash()
	if hp <= 0:
		_destroyed = true
		destroyed.emit(position.x)
		_play_destroy_animation()
		return true
	return false

func _refresh_hp_label() -> void:
	if hp_label:
		hp_label.text = str(maxi(hp, 0))

func _hit_flash() -> void:
	# Quick white tint then back to normal — like Subway Surfers / Vampire
	# Survivors hit feedback.
	modulate = Color(1.6, 1.4, 1.2, 1.0)
	var tween := create_tween()
	tween.tween_property(self, "modulate", Color(1, 1, 1, 1), 0.10)

func _play_destroy_animation() -> void:
	if sparkles:
		sparkles.emitting = true
	var tween := create_tween().set_parallel(true)
	tween.tween_property(self, "modulate:a", 0.0, 0.35)
	tween.tween_property(self, "scale", Vector2(1.25, 1.25), 0.35) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await tween.finished
	queue_free()
