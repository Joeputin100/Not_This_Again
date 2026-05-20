extends Control

# Iter 153: debug preview for the Candy Rustler jointed-puppet rig.
# Centres + scales the rig so the full lurching figure is on screen.

func _ready() -> void:
	get_tree().set_quit_on_go_back(false)
	if get_window():
		get_window().go_back_requested.connect(_on_back)
	$BackButton.pressed.connect(_on_back)
	# v1 figure centre is ~image (705, 384); scale + place it mid-screen.
	var rig: Node2D = $Rig
	var s: float = 1.25
	rig.scale = Vector2(s, s)
	rig.position = Vector2(540.0 - 705.0 * s, 1000.0 - 384.0 * s)

func _on_back() -> void:
	if get_node_or_null("/root/AudioBus"):
		AudioBus.play_tap()
	get_tree().change_scene_to_file("res://scenes/debug_menu.tscn")
