extends Node2D

# A single bullet — Node2D that moves straight up at SPEED px/sec.
# Bullets despawn when they exit the top of the visible area OR when
# they've travelled max_range pixels (whichever happens first).
# Added to "bullets" group so level.gd can iterate them for collision.

const SPEED: float = 1500.0
const SIZE: Vector2 = Vector2(10, 28)
const DESPAWN_Y: float = -80.0

# Max distance from spawn point before this bullet despawns. Set by the
# level when spawning, derived from the firing gun's range_px. <= 0
# means "no range limit" — fall back to off-screen despawn only.
var max_range: float = 0.0

# Damage applied to anything this bullet hits. Set by the level when
# spawning, derived from the firing gun's caliber. Read by collision
# handlers in level.gd, NOT applied here.
var damage: int = 1

var _spawn_y: float = 0.0

func _ready() -> void:
	add_to_group("bullets")
	_spawn_y = position.y

func _process(delta: float) -> void:
	position.y -= SPEED * delta
	if max_range > 0.0 and (_spawn_y - position.y) >= max_range:
		queue_free()
		return
	if position.y < DESPAWN_Y:
		queue_free()
