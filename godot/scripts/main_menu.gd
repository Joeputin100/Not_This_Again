extends Node2D

# Phase 0 placeholder back handler. Catches both legacy back-button presses
# and Android 14+'s predictive-back gesture (Godot bridges OnBackInvokedCallback
# to NOTIFICATION_WM_GO_BACK_REQUEST internally; the manifest enables the new
# API, this script consumes it).
#
# Phase 1+ should replace this with a "Quit? Y/N" dialog rather than a
# silent exit. For now: out is out, no ceremony.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST or what == NOTIFICATION_WM_CLOSE_REQUEST:
		print("Back gesture / close request — exiting.")
		get_tree().quit()
