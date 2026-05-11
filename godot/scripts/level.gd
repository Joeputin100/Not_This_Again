extends Node2D

# Phase 1 placeholder level. Real swerve / gate / barricade / boss content
# lands in subsequent commits. For now, this scene exists so the menu's
# PLAY button has a real destination and we can verify scene transitions
# work end-to-end.

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		# Back gesture from a level returns to the menu (not quit).
		# Phase 1+ should show "Quit run? Y/N" when there's run state to lose.
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
	elif what == NOTIFICATION_WM_CLOSE_REQUEST:
		get_tree().quit()
