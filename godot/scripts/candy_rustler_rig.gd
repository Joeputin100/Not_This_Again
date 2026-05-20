extends Node2D

# Iter 153: The Candy Rustler — jointed-puppet rig.
#
# Seven wrapper-collage pieces (sliced from the approved v1 boss art)
# nested in a transform hierarchy, each rotating around its brad-pivot
# joint. Procedural sine-oscillation per joint drives the perpetual
# jerky Terry-Gilliam lurch — no hand-authored animation.
#
# Coordinates are in the v1 image space (1408x768). Each piece's Sprite2D
# sits ON its joint pivot; the sprite `offset` shifts the texture so the
# slice lands at its original image position. So at rest the rig
# reassembles to exactly the v1 figure, and joint rotation pivots cleanly
# around the hinge.
#
# var (not const) for the data dictionaries on purpose — const Dictionaries
# holding Vector2/Vector4 have bitten this project before (iter 142 Color
# const compile fail); plain var sidesteps the const-eval path entirely.

const PIECE_DIR := "res://assets/sprites/rustler/"

# name -> { rect: Vector4(x0,y0,w,h), pivot: Vector2, parent: String }
var PIECES: Dictionary = {
	"torso":     {"rect": Vector4(455, 360, 510, 245), "pivot": Vector2(710, 540), "parent": ""},
	"leg_left":  {"rect": Vector4(455, 560, 290, 208), "pivot": Vector2(645, 575), "parent": "torso"},
	"leg_right": {"rect": Vector4(665, 560, 310, 208), "pivot": Vector2(770, 575), "parent": "torso"},
	"arm_left":  {"rect": Vector4(250, 240, 335, 325), "pivot": Vector2(560, 330), "parent": "torso"},
	"arm_right": {"rect": Vector4(835, 240, 325, 325), "pivot": Vector2(860, 330), "parent": "torso"},
	"head":      {"rect": Vector4(490, 150, 440, 255), "pivot": Vector2(710, 380), "parent": "torso"},
	"hat":       {"rect": Vector4(470,   0, 510, 235), "pivot": Vector2(710, 200), "parent": "head"},
}
# Parent-before-child build order; among torso's children = back-to-front.
var BUILD_ORDER: Array = ["torso", "leg_left", "leg_right", "arm_left", "arm_right", "head", "hat"]

# Procedural lurch per joint: [freq, amplitude(radians), phase].
var LURCH: Dictionary = {
	"head":      [1.4,  0.09, 0.0],
	"hat":       [1.9,  0.13, 1.1],
	"arm_left":  [1.15, 0.22, 0.0],
	"arm_right": [1.15, 0.22, 3.14159],
	"leg_left":  [0.95, 0.11, 0.6],
	"leg_right": [0.95, 0.11, 3.90000],
}

var _sprites: Dictionary = {}
var _t: float = 0.0

func _ready() -> void:
	for piece_name in BUILD_ORDER:
		var d: Dictionary = PIECES[piece_name]
		var rect: Vector4 = d["rect"]
		var pivot: Vector2 = d["pivot"]
		var spr := Sprite2D.new()
		spr.name = piece_name
		var tex_path: String = PIECE_DIR + piece_name + ".png"
		if ResourceLoader.exists(tex_path):
			spr.texture = load(tex_path)
		spr.centered = true
		# offset = slice-centre minus pivot → texture lands at its original
		# image position while the node itself sits on the joint.
		var slice_center := Vector2(rect.x + rect.z * 0.5, rect.y + rect.w * 0.5)
		spr.offset = slice_center - pivot
		var parent_name: String = d["parent"]
		if parent_name == "":
			spr.position = pivot
			add_child(spr)
		else:
			var ppivot: Vector2 = PIECES[parent_name]["pivot"]
			spr.position = pivot - ppivot
			(_sprites[parent_name] as Sprite2D).add_child(spr)
		_sprites[piece_name] = spr

func _process(delta: float) -> void:
	_t += delta
	for joint_name in LURCH.keys():
		if _sprites.has(joint_name):
			var p: Array = LURCH[joint_name]
			(_sprites[joint_name] as Sprite2D).rotation = sin(_t * p[0] + p[2]) * p[1]
	# Torso: slow whole-body sway + vertical bob (children inherit it).
	if _sprites.has("torso"):
		var torso: Sprite2D = _sprites["torso"]
		torso.rotation = sin(_t * 0.8) * 0.035
		var base: Vector2 = PIECES["torso"]["pivot"]
		torso.position = Vector2(base.x, base.y + sin(_t * 1.6) * 6.0)
