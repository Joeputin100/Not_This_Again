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

# Weather modifier — multiplied into SPEED each frame. RAIN sets this
# to 0.8 (bullets travel slower in rain). Default 1.0 = no effect.
# Set by the level via _spawn_bullet() before add_child, so _ready/_process
# both observe the modified value.
var velocity_mult: float = 1.0

# Weather modifier — lateral px/sec added to position.x each frame.
# WIND_STORM sets this to ~40.0 (bullets curve sideways). Default 0.0 =
# no drift, bullets travel straight up.
var lateral_drift: float = 0.0

var _spawn_y: float = 0.0

func _ready() -> void:
	add_to_group("bullets")
	_spawn_y = position.y

func _process(delta: float) -> void:
	position.y -= SPEED * velocity_mult * delta
	position.x += lateral_drift * delta
	if max_range > 0.0 and (_spawn_y - position.y) >= max_range:
		queue_free()
		return
	if position.y < DESPAWN_Y:
		queue_free()
