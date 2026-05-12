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

func _ready() -> void:
	if sprite_2d:
		sprite_2d.texture = sub_viewport.get_texture()
	if ground:
		_material = ground.material_override as StandardMaterial3D

func _process(delta: float) -> void:
	_uv_offset += SCROLL_SPEED * delta
	# Wrap to keep the offset bounded — UV repeat makes any whole-tile
	# offset visually equivalent, but unbounded floats could lose
	# precision after long sessions.
	if _uv_offset > 1.0:
		_uv_offset -= 1.0
	if _material:
		_material.uv1_offset = Vector3(0.0, _uv_offset, 0.0)
