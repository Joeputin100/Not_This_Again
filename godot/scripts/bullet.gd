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

# Iter 40e: candy palette for jelly-bean bullets. Each shot picks a
# random color so a burst of rapid fire reads as a colorful spray
# rather than a stream of identical projectiles. Western framing kept
# (gun, posse, hat) — bullets are the part that needed softening for
# family-friendly tone.
const CANDY_COLORS: Array[Color] = [
	Color(1.00, 0.32, 0.42, 1),  # cherry
	Color(1.00, 0.84, 0.30, 1),  # lemon
	Color(0.42, 0.92, 0.68, 1),  # mint
	Color(0.78, 0.48, 0.92, 1),  # grape
	Color(1.00, 0.62, 0.30, 1),  # orange
	Color(0.95, 0.55, 0.78, 1),  # bubblegum
]

func _ready() -> void:
	add_to_group("bullets")
	_spawn_y = position.y
	# Randomize the bean color so successive bullets read as different
	# candies. Body is the @child Polygon2D in the scene; Highlight
	# stays its fixed white catch-light.
	var body: Polygon2D = get_node_or_null("Body") as Polygon2D
	if body:
		body.color = CANDY_COLORS[randi() % CANDY_COLORS.size()]

func _process(delta: float) -> void:
	position.y -= SPEED * velocity_mult * delta
	position.x += lateral_drift * delta
	if max_range > 0.0 and (_spawn_y - position.y) >= max_range:
		queue_free()
		return
	if position.y < DESPAWN_Y:
		queue_free()
