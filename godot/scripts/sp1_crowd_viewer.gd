extends Node3D

# SP1 debug crowd viewer: a 3D scene with a grassy plane, one FlipbookCrowd,
# a slider to dial the member count, and a d-pad to walk the crowd around
# the plane. Lets you look at the crowd animations in isolation from
# gameplay — wired to the debug menu, not the gameplay path.

const FlipbookCrowd = preload("res://scripts/flipbook_crowd.gd")

# Character → animation clips that crowd loops between. Each character has
# its own list because clip names are character-prefixed by Task 5.
const CHARACTERS := {
	"cowboy": [
		"cowboy_idle_a", "cowboy_idle_b", "cowboy_idle_c",
		"cowboy_celebrate_a", "cowboy_celebrate_b", "cowboy_celebrate_c",
		"cowboy_run_shoot_fwd", "cowboy_run_shoot_left",
		"cowboy_run_shoot_right", "cowboy_strafe_left",
		"cowboy_strafe_right", "cowboy_stand_shoot",
	],
	"pete": [
		"pete_celebrate", "pete_complains", "pete_death",
		"pete_hit_by_gunfire", "pete_shoots_at_player", "pete_shouts",
		"pete_steps_forward", "pete_strafe_right_to_left",
		"pete_taps_foot_idle",
	],
	"vagrant": [
		"vagrant_death", "vagrant_drunk_walk", "vagrant_idle_wobble",
		"vagrant_shoot_down", "vagrant_shoot_left", "vagrant_shoot_right",
		"vagrant_strafe_left", "vagrant_strafe_right",
	],
	"prospector": [
		"prospector_death", "prospector_idle_drinking",
		"prospector_reacts_to_gunshot", "prospector_steps_forward",
		"prospector_strafe_left", "prospector_strafe_right",
	],
	"pusher": [
		"pusher_melee", "pusher_run_forward",
		"pusher_push_left_a", "pusher_push_left_b", "pusher_push_left_c",
		"pusher_push_right_a", "pusher_push_right_b", "pusher_push_right_c",
	],
	"chicken": [
		"chicken_rir_flap", "chicken_rir_scramble", "chicken_rir_tumble",
		"chicken_leghorn_flap", "chicken_leghorn_scramble",
		"chicken_leghorn_tumble", "chicken_silkie_flap",
		"chicken_silkie_scramble", "chicken_silkie_tumble",
	],
	"humbug": ["humbug_tip", "humbug_thought", "humbug_canard"],
}

const MOVE_SPEED := 4.0   # m/s when a d-pad direction is held
const SPAWN_RADIUS := 5.0 # crowd members spread within this XZ radius

var _crowd: Node3D = null
var _character := "cowboy"
var _target_count := 20
var _ids: Array[int] = []     # member ids in insertion order
var _move := Vector3.ZERO     # velocity from d-pad

@onready var slider: HSlider = $UI/Panel/VBox/CountSlider
@onready var count_label: Label = $UI/Panel/VBox/CountLabel
@onready var char_select: OptionButton = $UI/Panel/VBox/CharSelect
@onready var perf: Label = $UI/Perf
@onready var back_button: Button = $UI/BackButton
@onready var dpad_up: Button = $UI/Panel/VBox/DPad/Up
@onready var dpad_down: Button = $UI/Panel/VBox/DPad/Down
@onready var dpad_left: Button = $UI/Panel/VBox/DPad/Left
@onready var dpad_right: Button = $UI/Panel/VBox/DPad/Right

func _ready() -> void:
	get_tree().set_quit_on_go_back(false)
	if get_window():
		get_window().go_back_requested.connect(_on_back_pressed)
	back_button.pressed.connect(_on_back_pressed)
	_populate_character_options()
	slider.value_changed.connect(_on_slider_changed)
	char_select.item_selected.connect(_on_character_selected)
	_wire_dpad()
	_build_crowd(_character)
	_set_count(_target_count)
	_update_count_label()

func _populate_character_options() -> void:
	char_select.clear()
	for c in CHARACTERS.keys():
		char_select.add_item(c)
	char_select.selected = 0  # cowboy

func _wire_dpad() -> void:
	dpad_up.button_down.connect(func(): _move.z = -MOVE_SPEED)
	dpad_up.button_up.connect(func(): _move.z = 0.0)
	dpad_down.button_down.connect(func(): _move.z = MOVE_SPEED)
	dpad_down.button_up.connect(func(): _move.z = 0.0)
	dpad_left.button_down.connect(func(): _move.x = -MOVE_SPEED)
	dpad_left.button_up.connect(func(): _move.x = 0.0)
	dpad_right.button_down.connect(func(): _move.x = MOVE_SPEED)
	dpad_right.button_up.connect(func(): _move.x = 0.0)

func _on_character_selected(idx: int) -> void:
	var keys: Array = CHARACTERS.keys()
	var name: String = keys[idx]
	if name == _character:
		return
	_character = name
	_build_crowd(_character)
	_set_count(_target_count)

func _on_slider_changed(val: float) -> void:
	_target_count = int(val)
	_update_count_label()
	_set_count(_target_count)

func _update_count_label() -> void:
	count_label.text = "Crowd size: %d" % _target_count

func _build_crowd(character: String) -> void:
	# Tear down any prior crowd and its MultiMesh children, then build fresh.
	if _crowd:
		_crowd.queue_free()
		_crowd = null
	_ids.clear()
	_crowd = FlipbookCrowd.new()
	_crowd.name = "Crowd"
	add_child(_crowd)
	_crowd.configure(character, CHARACTERS[character])

func _set_count(n: int) -> void:
	var clips: Array = CHARACTERS[_character]
	while _ids.size() < n:
		var clip: String = clips[_ids.size() % clips.size()]
		var x := Transform3D(Basis(), Vector3(
			randf_range(-SPAWN_RADIUS, SPAWN_RADIUS), 0.0,
			randf_range(-SPAWN_RADIUS, SPAWN_RADIUS)))
		_ids.append(_crowd.add_member(clip, x))
	while _ids.size() > n:
		var id: int = _ids.pop_back()
		_crowd.remove_member(id)

func _process(dt: float) -> void:
	if _crowd and _move.length_squared() > 0.0:
		_crowd.position += _move * dt
	perf.text = "FPS %d  draws %d  VRAM %.0f MB" % [
		Engine.get_frames_per_second(),
		RenderingServer.get_rendering_info(
			RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		RenderingServer.get_rendering_info(
			RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED) / 1048576.0]

func _on_back_pressed() -> void:
	if get_node_or_null("/root/AudioBus"):
		AudioBus.play_tap()
	get_tree().change_scene_to_file("res://scenes/debug_menu.tscn")
