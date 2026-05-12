extends Node2D

# Bullet fired by an outlaw. Mirrors the posse's bullet.gd but moves
# DOWN (toward the cowboy) instead of UP. On contact with the cowboy
# node, deals POSSE_DAMAGE to the posse and despawns. Self-frees when
# off the bottom of the playfield.
#
# Outlaw bullets are visually red (vs posse's orange muzzle flash) so
# the player can immediately tell which projectiles are dangerous.

const SPEED: float = 700.0
const SIZE: Vector2 = Vector2(10, 28)
const DESPAWN_Y: float = 2080.0
const POSSE_DAMAGE: int = 2

func _ready() -> void:
	add_to_group("outlaw_bullets")

func _process(delta: float) -> void:
	position.y += SPEED * delta
	if position.y > DESPAWN_Y:
		queue_free()
