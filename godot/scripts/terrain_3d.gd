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

# Iter 63: gate the auto-scroll so the level-select variant of the
# terrain can stay static (panned by finger drag instead). Default true
# preserves gameplay behavior; level_select sets this to false on its
# Terrain3D instance.
@export var auto_scroll: bool = true

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

# Iter 63: external nudge for drag-pan scenes (level_select). Negative
# delta scrolls "backward" so dragging UP makes the world come toward you.
func nudge_uv(delta_y: float) -> void:
	_uv_offset += delta_y
	while _uv_offset > 1.0:
		_uv_offset -= 1.0
	while _uv_offset < 0.0:
		_uv_offset += 1.0
	if _material:
		_material.uv1_offset = Vector3(0.0, _uv_offset, 0.0)

func _process(delta: float) -> void:
	if not _scroll_active or not auto_scroll:
		return
	# Iter 67: NEGATED — previous direction made the cowboy appear to
	# run backwards (dirt scrolled away from him toward the camera).
	# Subtracting moves the texture in the opposite UV direction so the
	# dirt now appears to move FROM the horizon TOWARD the camera —
	# matches the perception of "running forward into the scene."
	# Using fposmod for robust wrap-around in both directions.
	_uv_offset = fposmod(_uv_offset - SCROLL_SPEED * WorldSpeed.mult * delta, 1.0)
	if _material:
		_material.uv1_offset = Vector3(0.0, _uv_offset, 0.0)
