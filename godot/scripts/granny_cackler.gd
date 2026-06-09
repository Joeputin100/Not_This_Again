extends Node

# Fires Granny's cackle (flipbook frames + VO burst) at random intervals so she
# cackles "inappropriately" wherever she's shown (pop-up, results, idle). Attach
# as a child of the Control hosting Granny; point sprite_path at her TextureRect.

const FRAMES: Array[String] = [
	"res://assets/sprites/props/granny_cackle_0.png",
	"res://assets/sprites/props/granny_cackle_1.png",
	"res://assets/sprites/props/granny_cackle_2.png",
	"res://assets/sprites/props/granny_cackle_3.png",
]
const MIN_GAP: float = 9.0
const MAX_GAP: float = 15.0
const FRAME_T: float = 0.12

@export var sprite_path: NodePath
var _t: float = 0.0
var _neutral: Texture2D = null
var _sprite: CanvasItem = null

func _ready() -> void:
	_sprite = get_node_or_null(sprite_path)
	if _sprite != null and _sprite.get("texture") != null:
		_neutral = _sprite.get("texture")
	_arm()

func _arm() -> void:
	_t = randf_range(MIN_GAP, MAX_GAP)

func _process(delta: float) -> void:
	if _sprite == null:
		return
	_t -= delta
	if _t <= 0.0:
		_cackle()
		_arm()

func _cackle() -> void:
	if get_node_or_null("/root/AudioBus") and AudioBus.has_method("play_character_line"):
		AudioBus.play_character_line("granny_cackle_%d" % (randi() % 4))
	var frames: Array[Texture2D] = []
	for p in FRAMES:
		if ResourceLoader.exists(p):
			frames.append(load(p))
	if frames.is_empty():
		return   # no flipbook art yet — the VO still plays
	var tw := create_tween()
	for f in frames:
		tw.tween_callback(func(): _sprite.set("texture", f))
		tw.tween_interval(FRAME_T)
	tw.tween_callback(func():
		if _neutral != null:
			_sprite.set("texture", _neutral))
