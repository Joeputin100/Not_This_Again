extends Node2D

# Iter 153/156: The Candy Rustler — jointed-puppet rig.
#
# Seven wrapper-collage pieces (sliced from the approved v1 boss art)
# nested in a transform hierarchy, each rotating around its brad-pivot.
# Procedural sine-oscillation per joint gives the perpetual jerky
# Terry-Gilliam lurch — no hand-authored animation.
#
# Iter 156 adds: wrapper-rustle SFX while he lurches, HP-threshold
# piece-detachment (he physically dismantles as he's damaged), and a
# death scatter where every remaining piece pops its hinge and flutters
# off. take_damage() / defeat() are the public API the level-2 boss
# integration will drive.
#
# Coordinates are in the v1 image space (1408x768): each piece's Sprite2D
# sits ON its joint pivot, the sprite `offset` shifts the texture so the
# slice lands at its original image position — so at rest the rig
# reassembles to exactly v1 and joint rotation hinges cleanly.

const PIECE_DIR := "res://assets/sprites/rustler/"
const RUSTLE_STREAMS: Array = [
	preload("res://assets/sfx/candy_rustler_rustle_0.mp3"),
	preload("res://assets/sfx/candy_rustler_rustle_1.mp3"),
	preload("res://assets/sfx/candy_rustler_rustle_2.mp3"),
]

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

# Iter 156: HP + detachment. A piece tears off at 75 / 50 / 25 % HP; the
# rest scatter on defeat.
var max_hp: int = 12
var hp: int = 12
var _detach_order: Array = ["hat", "arm_left", "leg_left"]
var _detached_count: int = 0
var _alive: bool = true

var _sprites: Dictionary = {}
var _t: float = 0.0
var _rustle_player: AudioStreamPlayer
var _rustle_timer: float = 0.9

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
	_rustle_player = AudioStreamPlayer.new()
	_rustle_player.bus = "Master"
	_rustle_player.volume_db = -3.0
	add_child(_rustle_player)

func _process(delta: float) -> void:
	_t += delta
	for joint_name in LURCH.keys():
		if _sprites.has(joint_name):
			var p: Array = LURCH[joint_name]
			(_sprites[joint_name] as Sprite2D).rotation = sin(_t * p[0] + p[2]) * p[1]
	if _sprites.has("torso"):
		var torso: Sprite2D = _sprites["torso"]
		torso.rotation = sin(_t * 0.8) * 0.035
		var base: Vector2 = PIECES["torso"]["pivot"]
		torso.position = Vector2(base.x, base.y + sin(_t * 1.6) * 6.0)
	# Wrapper-rustle SFX while he's still lurching.
	if _alive and not _sprites.is_empty():
		_rustle_timer -= delta
		if _rustle_timer <= 0.0:
			_rustle_timer = randf_range(0.7, 1.4)
			_play_rustle()

func _play_rustle() -> void:
	if _rustle_player == null:
		return
	_rustle_player.stream = RUSTLE_STREAMS[randi() % RUSTLE_STREAMS.size()]
	_rustle_player.play()

# --- Public API (driven by the level-2 boss wiring) ----------------------

# Iter 156: take damage → tear pieces off at the HP thresholds.
func take_damage(amount: int) -> void:
	if not _alive:
		return
	hp = maxi(0, hp - amount)
	_play_rustle()
	var frac: float = float(hp) / float(max_hp)
	var want_detached: int = 0
	if frac <= 0.75:
		want_detached = 1
	if frac <= 0.50:
		want_detached = 2
	if frac <= 0.25:
		want_detached = 3
	while _detached_count < want_detached and _detached_count < _detach_order.size():
		_detach_piece(_detach_order[_detached_count], false)
		_detached_count += 1
	if hp <= 0:
		defeat()

# Iter 156: defeat → every remaining piece pops its hinge and scatters.
func defeat() -> void:
	if not _alive:
		return
	_alive = false
	_play_rustle()
	for piece_name in _sprites.keys().duplicate():
		_detach_piece(piece_name, true)

# Reparent a piece to the rig root and fling it off — tumble + flutter +
# fade. `big` = death-scatter (faster, wider) vs a single threshold detach.
func _detach_piece(piece_name: String, big: bool) -> void:
	if not _sprites.has(piece_name):
		return
	var spr: Sprite2D = _sprites[piece_name]
	_sprites.erase(piece_name)  # _process stops animating it
	var gt: Transform2D = spr.global_transform
	spr.reparent(self)
	spr.global_transform = gt
	var dir := Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, -0.2)).normalized()
	var dist: float = randf_range(500.0, 900.0) if big else randf_range(220.0, 420.0)
	var fall: float = randf_range(700.0, 1100.0)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(spr, "position",
		spr.position + dir * dist + Vector2(0.0, fall), 1.4) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(spr, "rotation",
		spr.rotation + randf_range(-10.0, 10.0), 1.4)
	tw.tween_property(spr, "modulate:a", 0.0, 1.0).set_delay(0.5)
	tw.chain().tween_callback(spr.queue_free)
