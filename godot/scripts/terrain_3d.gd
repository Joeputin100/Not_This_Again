extends Node2D

# Pseudo-3D ground plane for the level playfield. A SubViewport renders
# a tilted-perspective dirt plane in 3D space; the Sprite2D in this
# scene displays that render at the playfield's pixel size (1080×1920
# scaled from the 540×960 SubViewport).
#
# The 3D plane is static — instead of moving the geometry, we scroll
# the UV offset over time. Perspective foreshortening makes the near
# ground appear to scroll fast and the far ground appear to scroll
# slow without any extra math — the same uniform UV-velocity reads as
# proper depth motion because the plane is tilted.
#
# Sits BEHIND all 2D gameplay nodes in level.tscn — gates, obstacles,
# bullets, cowboy and posse all overlay on top of the rendered terrain.

const SCROLL_SPEED: float = 0.25

@onready var sub_viewport: SubViewport = $SubViewport
@onready var ground: MeshInstance3D = $SubViewport/Ground
@onready var sprite_2d: Sprite2D = $Sprite

var _material: StandardMaterial3D
var _uv_offset: float = 0.0
# Iter 40c: set false during boss fights so the world stops moving
# while the duel resolves. The cowboy is stationary, the boss is in
# STAY mode — the dirt scroll was the only motion telegraphing
# "running forward", which contradicted the showdown framing.
var _scroll_active: bool = true

func _ready() -> void:
	if sprite_2d:
		sprite_2d.texture = sub_viewport.get_texture()
	if ground:
		_material = ground.material_override as StandardMaterial3D

# Iter 40c: level.gd flips this off when the boss-engaged signal fires.
# Kept as a generic boolean (rather than a one-way latch) so it could
# also be flipped back on for win cinematics or special level events.
func set_scroll_active(active: bool) -> void:
	_scroll_active = active

func _process(delta: float) -> void:
	if not _scroll_active:
		return
	_uv_offset += SCROLL_SPEED * WorldSpeed.mult * delta
	# Wrap to keep the offset bounded — UV repeat makes any whole-tile
	# offset visually equivalent, but unbounded floats could lose
	# precision after long sessions.
	if _uv_offset > 1.0:
		_uv_offset -= 1.0
	if _material:
		_material.uv1_offset = Vector3(0.0, _uv_offset, 0.0)
