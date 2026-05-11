extends Node2D

# Main menu. Phase 0 was a placeholder screen; phase 1 introduces an actual
# PLAY button with a Candy-Crush-style tap-pop animation before scene change.
#
# Tone (per design.md, "Tone bible"): the narrator/UI voice leans Murderbot
# Diaries — dry, deadpan, mildly annoyed at having to explain anything.
# Keep all copy in that register.

@onready var play_button: Button = $UI/PlayButton

func _ready() -> void:
	play_button.pressed.connect(_on_play_pressed)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST or what == NOTIFICATION_WM_CLOSE_REQUEST:
		# From the main menu, both legacy back and predictive-back-gesture
		# should quit. Phase 1+ might add a "Quit? Y/N" dialog; not yet.
		get_tree().quit()

func _on_play_pressed() -> void:
	# Candy-Crush-style press feedback: quick squish, bouncy release, then
	# scene change. Pivot is set in the .tscn to the button's center so
	# scale animates symmetrically.
	play_button.disabled = true   # prevent double-tap during animation
	var tween := create_tween()
	tween.tween_property(play_button, "scale", Vector2(0.92, 0.92), 0.06)
	tween.tween_property(play_button, "scale", Vector2(1.0, 1.0), 0.18) \
		.set_trans(Tween.TRANS_BACK) \
		.set_ease(Tween.EASE_OUT)
	await tween.finished
	get_tree().change_scene_to_file("res://scenes/level.tscn")
