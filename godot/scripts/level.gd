extends Node2D

# Phase 1 level prototype: a draggable cowboy at the bottom of the screen.
# Input events write to target_x; _process() smoothly lerps the cowboy
# toward target_x each frame so movement feels responsive but not jittery.
# Real gameplay (gates, barricades, boss) lands in subsequent commits.

const MovementBounds = preload("res://scripts/movement_bounds.gd")

# Lerp speed for follow-the-finger smoothing. Higher = snappier;
# lower = laggier. ~12 feels responsive without jitter on a 60Hz mid-range
# Android. Will tune on device.
const FOLLOW_SPEED: float = 12.0

@onready var cowboy: Node2D = $Cowboy

# Where the cowboy is being told to go. Defaults to current position so
# the first _process() call doesn't yank the cowboy off-screen.
var target_x: float

func _ready() -> void:
	target_x = cowboy.position.x

func _process(delta: float) -> void:
	cowboy.position.x = lerpf(cowboy.position.x, target_x, FOLLOW_SPEED * delta)

func _input(event: InputEvent) -> void:
	# Update target_x on any of: touch start, touch drag, mouse drag
	# (for desktop testing). Godot auto-emulates each from the other
	# when the corresponding project setting is on, but explicit
	# handling is more predictable than relying on emulation.
	var new_x := -1.0
	if event is InputEventScreenDrag:
		new_x = (event as InputEventScreenDrag).position.x
	elif event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed:
		new_x = (event as InputEventScreenTouch).position.x
	elif event is InputEventMouseMotion and ((event as InputEventMouseMotion).button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		new_x = (event as InputEventMouseMotion).position.x
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			new_x = mb.position.x
	if new_x >= 0.0:
		target_x = MovementBounds.clamp_x(new_x)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
	elif what == NOTIFICATION_WM_CLOSE_REQUEST:
		get_tree().quit()
