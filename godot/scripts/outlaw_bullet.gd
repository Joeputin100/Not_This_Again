extends Node2D

# Bullet fired by an outlaw or boss. Iter 31+: travels along an
# arbitrary velocity vector set by the shooter (instead of straight
# down), enabling aimed shots at the posse. Default velocity is
# (0, SPEED) for backward compatibility with any caller that doesn't
# bother setting it.
#
# On overlap with cowboy OR a posse follower (handled in level.gd's
# collision pass), the bullet kills ONE dude — POSSE_DAMAGE was bumped
# down from 2 to 1 in iter 31 so the per-dude semantics are clean:
# one bullet, one death.

const SPEED: float = 700.0
const SIZE: Vector2 = Vector2(10, 28)
const DESPAWN_X_LEFT: float = -100.0
const DESPAWN_X_RIGHT: float = 1180.0
const DESPAWN_Y_TOP: float = -300.0
const DESPAWN_Y_BOTTOM: float = 2080.0
const POSSE_DAMAGE: int = 1

# Velocity vector — overridden by the shooter to aim at the cowboy.
var velocity: Vector2 = Vector2(0, SPEED)

func _ready() -> void:
	add_to_group("outlaw_bullets")

func _process(delta: float) -> void:
	position += velocity * delta
	if position.y > DESPAWN_Y_BOTTOM \
			or position.y < DESPAWN_Y_TOP \
			or position.x < DESPAWN_X_LEFT \
			or position.x > DESPAWN_X_RIGHT:
		queue_free()
