extends Node2D

# Iter 64: prototype 3D level scene. The user chose the full 3D refactor
# path over the perspective-fake approach. This scene is the foundation
# for the migration:
#
#   - Terrain3D SubViewport renders the dirt PlaneMesh with the tilted
#     Camera3D (existing pattern, unchanged)
#   - INSIDE the same SubViewport's 3D scene: cowboy as a Sprite3D
#     billboard on the dirt + placeholder obstacles to demonstrate
#     "entities bound to the terrain" rather than overlaid 2D
#   - Cowboy moves in 3D x-axis via drag-input → screen-to-world mapping
#   - Obstacles scroll toward camera in 3D z-axis (z increases over time)
#
# This is a PROTOTYPE. Bullets, gates, gold rushes, posse, etc. all
# come in subsequent iters (65+). For now: walk the cowboy along the
# dirt, watch obstacles slide toward you, prove the architecture.
#
# Reachable from debug menu → "PREVIEW 3D LEVEL".

const BuildInfo = preload("res://scripts/build_info.gd")

# 3D world bounds. The dirt PlaneMesh in terrain_3d_3d_prototype is
# 40 wide × 60 deep, centered at origin. Cowboy lane = x in [-18, 18].
const COWBOY_X_BOUND: float = 18.0
const COWBOY_Z: float = 1.5         # close to camera (near plane)
const OBSTACLE_SPAWN_Z: float = -28.0  # far end of plane
const OBSTACLE_DESPAWN_Z: float = 3.5   # past the cowboy
const OBSTACLE_SPEED: float = 8.0    # world units per second
const OBSTACLE_SPAWN_INTERVAL: float = 1.2

@onready var subviewport: SubViewport = $Terrain3D/SubViewport
@onready var camera: Camera3D = $Terrain3D/SubViewport/Camera3D
@onready var cowboy_3d: Sprite3D = $Terrain3D/SubViewport/Cowboy3D
@onready var obstacles_root: Node3D = $Terrain3D/SubViewport/Obstacles
@onready var back_button: Button = $UI/BackButton
@onready var info_label: Label = $UI/InfoLabel

var _spawn_timer: float = 0.0
var _rng := RandomNumberGenerator.new()

# Target cowboy x in world units, lerped each frame. Set by drag input
# which converts screen-x to world-x via the camera-plane projection.
var _target_x: float = 0.0
const COWBOY_LERP_SPEED: float = 8.0

func _ready() -> void:
	get_tree().set_quit_on_go_back(false)
	get_window().go_back_requested.connect(_on_back_pressed)
	back_button.pressed.connect(_on_back_pressed)
	_rng.seed = 6464
	info_label.text = "3D PREVIEW · build %s · drag to steer" % BuildInfo.SHA
	DebugLog.add("level_3d _ready (build=%s)" % BuildInfo.SHA)

func _process(delta: float) -> void:
	# Lerp cowboy x toward target (drag input target).
	cowboy_3d.position.x = lerpf(cowboy_3d.position.x, _target_x,
		clampf(COWBOY_LERP_SPEED * delta, 0.0, 1.0))
	# Spawn obstacles periodically.
	_spawn_timer -= delta
	if _spawn_timer <= 0.0:
		_spawn_timer = OBSTACLE_SPAWN_INTERVAL
		_spawn_obstacle()
	# Move all obstacles toward camera (z increases since camera is at z>0).
	for child in obstacles_root.get_children():
		if child is Node3D:
			child.position.z += OBSTACLE_SPEED * delta
			if child.position.z > OBSTACLE_DESPAWN_Z:
				child.queue_free()

func _input(event: InputEvent) -> void:
	# Translate drag x to cowboy world-x via the screen-to-plane mapping.
	# Screen is 1080 wide; cowboy bounds are ±COWBOY_X_BOUND in world units.
	# Linear approximation (the 3D camera adds some perspective, but at
	# the cowboy's near-plane z=1.5 it's nearly orthographic across x).
	var sx: float = -1.0
	if event is InputEventScreenDrag:
		sx = (event as InputEventScreenDrag).position.x
	elif event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed:
		sx = (event as InputEventScreenTouch).position.x
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if (mm.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
			sx = mm.position.x
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			sx = mb.position.x
	if sx >= 0.0:
		var t: float = clampf(sx / 1080.0, 0.0, 1.0)
		_target_x = lerpf(-COWBOY_X_BOUND, COWBOY_X_BOUND, t)

# Iter 64: spawn a placeholder obstacle far away on a random lane.
# Uses a colored CSGBox3D for now — iter 65 will swap to proper
# 3D meshes per entity type (barrel, bull, etc.).
func _spawn_obstacle() -> void:
	var box := CSGBox3D.new()
	box.size = Vector3(2.0, 2.0, 2.0)
	# Random tan/brown color so it reads as a barrel-equivalent.
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color.from_hsv(_rng.randf_range(0.05, 0.12),
		0.65, _rng.randf_range(0.55, 0.85), 1.0)
	box.material = mat
	# Lane: random x in cowboy bounds
	var lane_x: float = _rng.randf_range(-COWBOY_X_BOUND * 0.85,
		COWBOY_X_BOUND * 0.85)
	box.position = Vector3(lane_x, 1.0, OBSTACLE_SPAWN_Z)
	obstacles_root.add_child(box)

func _on_back_pressed() -> void:
	AudioBus.play_tap()
	get_tree().change_scene_to_file("res://scenes/debug_menu.tscn")
