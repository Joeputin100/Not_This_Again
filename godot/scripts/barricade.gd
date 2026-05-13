extends Node2D

# Wooden fence barricade — impenetrable. Bullets are absorbed without
# effect. The cowboy must navigate around it. Collision with cowboy
# deals HIGH damage to the posse (much more than a tumbleweed or barrel).

const SCROLL_SPEED: float = 220.0
const SIZE: Vector2 = Vector2(420, 110)
# A fence to the face is devastating. Higher than any other obstacle.
const COWBOY_DAMAGE: int = 10

func _ready() -> void:
	add_to_group("barricades")

func _process(delta: float) -> void:
	position.y += SCROLL_SPEED * WorldSpeed.mult * delta
	if position.y > 2200.0:
		queue_free()

# Bullets are absorbed but the barricade is unharmed. Returns true
# (bullet consumed). The barricade itself is never destroyed by shooting.
# `damage` is accepted for API consistency with other destructibles but
# ignored — even a cannon shell can't punch through this fence.
func take_bullet_hit(_damage: int = 1) -> bool:
	return true

func get_cowboy_damage() -> int:
	return COWBOY_DAMAGE
