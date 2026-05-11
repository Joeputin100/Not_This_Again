extends Node2D

# A single bullet — Node2D that moves straight up at SPEED px/sec.
# Bullets despawn when they exit the top of the visible area.
# Added to "bullets" group so level.gd can iterate them for collision.

const SPEED: float = 1500.0
const SIZE: Vector2 = Vector2(10, 28)
const DESPAWN_Y: float = -80.0

func _ready() -> void:
	add_to_group("bullets")

func _process(delta: float) -> void:
	position.y -= SPEED * delta
	if position.y < DESPAWN_Y:
		queue_free()
