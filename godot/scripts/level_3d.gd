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

# Iter 66: 3D bullets — small bright spheres that travel from cowboy
# along -z axis (away from camera toward the far end of the plane).
# Auto-fire at FIRE_INTERVAL while game is active. Collision: simple
# distance-squared check between each bullet and each obstacle.
const BULLET_SPEED: float = 28.0  # world units per second
const BULLET_FIRE_INTERVAL: float = 0.20
const BULLET_DESPAWN_Z: float = -32.0
const BULLET_COLLISION_DIST_SQ: float = 1.5 * 1.5  # 1.5 world unit radius
const BULLET_PIXEL_SIZE: float = 0.5  # CSGSphere3D radius
const BULLET_SPAWN_Y: float = 1.2  # waist-high at cowboy

@onready var subviewport: SubViewport = $Terrain3D/SubViewport
@onready var camera: Camera3D = $Terrain3D/SubViewport/Camera3D
@onready var cowboy_3d: Sprite3D = $Terrain3D/SubViewport/Cowboy3D
@onready var obstacles_root: Node3D = $Terrain3D/SubViewport/Obstacles
@onready var bullets_root: Node3D = $Terrain3D/SubViewport/Bullets
# Iter 69: terrain_3d.gd script wasn't attached to the inline Terrain3D
# node in level_3d.tscn, so the SubViewport→Sprite2D texture wiring
# never ran. Reference + manual hookup in _ready below.
@onready var terrain_sprite: Sprite2D = $Terrain3D/Sprite
@onready var back_button: Button = $UI/BackButton
@onready var info_label: Label = $UI/InfoLabel

var _spawn_timer: float = 0.0
var _fire_timer: float = 0.0
var _hits: int = 0
var _rng := RandomNumberGenerator.new()

# Target cowboy x in world units, lerped each frame. Set by drag input
# which converts screen-x to world-x via the camera-plane projection.
var _target_x: float = 0.0
const COWBOY_LERP_SPEED: float = 8.0

# Iter 72: 3D posse followers — Sprite3D billboards spawned behind the
# leader cowboy in a trapezoid formation. Each follower tracks the
# leader's x with lag for crowd-runner feel.
const POSSE_FORMATION_OFFSETS: Array[Vector3] = [
	Vector3(-0.55, 0.0, 0.55),   # row 1 left
	Vector3( 0.55, 0.0, 0.55),   # row 1 right
	Vector3(-1.10, 0.0, 1.10),   # row 2 left
	Vector3( 0.00, 0.0, 1.10),   # row 2 center
	Vector3( 1.10, 0.0, 1.10),   # row 2 right
]
# Per-follower x-lerp speed (lower = more lag behind leader for crowd feel)
const FOLLOWER_LERP_SPEED: float = 5.5
var _followers: Array[Sprite3D] = []

func _ready() -> void:
	get_tree().set_quit_on_go_back(false)
	get_window().go_back_requested.connect(_on_back_pressed)
	back_button.pressed.connect(_on_back_pressed)
	_rng.seed = 6464
	# Iter 69: bind the SubViewport's render output to the Sprite2D.
	# Without this, the Sprite2D has no texture and the Background
	# ColorRect (dark brown) shows through — exactly what user reported.
	if terrain_sprite and subviewport:
		terrain_sprite.texture = subviewport.get_texture()
		DebugLog.add("level_3d: subviewport→sprite texture bound")
	else:
		DebugLog.add("WARN level_3d: terrain_sprite=%s subviewport=%s" % [
			str(terrain_sprite), str(subviewport),
		])
	# Iter 72: spawn posse followers at trapezoid offsets behind leader.
	_spawn_posse_followers()
	info_label.text = "3D PREVIEW · build %s · drag to steer" % BuildInfo.SHA
	DebugLog.add("level_3d _ready (build=%s)" % BuildInfo.SHA)

# Iter 72: create 5 Sprite3D followers (matches default posse_count=5
# minus the leader at index 0). Each is a clone of the leader cowboy
# sprite, positioned at COWBOY_Z + offset_z and ±x offset.
func _spawn_posse_followers() -> void:
	if cowboy_3d == null:
		return
	var leader_tex: Texture2D = cowboy_3d.texture
	var leader_pixel: float = cowboy_3d.pixel_size
	for offset in POSSE_FORMATION_OFFSETS:
		var f := Sprite3D.new()
		f.texture = leader_tex
		f.pixel_size = leader_pixel
		f.billboard = SpriteBase3D.BILLBOARD_ENABLED
		f.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
		f.position = Vector3(offset.x, 0.45, COWBOY_Z + offset.z)
		f.set_meta("formation_offset", offset)
		subviewport.add_child(f)
		_followers.append(f)

func _process(delta: float) -> void:
	# Lerp cowboy x toward target (drag input target).
	cowboy_3d.position.x = lerpf(cowboy_3d.position.x, _target_x,
		clampf(COWBOY_LERP_SPEED * delta, 0.0, 1.0))
	# Iter 72: followers track the leader's x with formation-offset lag.
	for f in _followers:
		if not is_instance_valid(f):
			continue
		var offset: Vector3 = f.get_meta("formation_offset", Vector3.ZERO)
		var target_fx: float = cowboy_3d.position.x + offset.x
		f.position.x = lerpf(f.position.x, target_fx,
			clampf(FOLLOWER_LERP_SPEED * delta, 0.0, 1.0))
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
	# Iter 66: auto-fire bullets. Cowboy emits bullets along the -z axis
	# every BULLET_FIRE_INTERVAL seconds. Bullets are CSGSphere3Ds for
	# simplicity (no texture needed, gets the candy-colored material).
	_fire_timer -= delta
	if _fire_timer <= 0.0:
		_fire_timer = BULLET_FIRE_INTERVAL
		_spawn_bullet()
	# Move + collision-check each bullet.
	for bullet in bullets_root.get_children():
		if not (bullet is Node3D):
			continue
		bullet.position.z -= BULLET_SPEED * delta
		# Despawn off the far end.
		if bullet.position.z < BULLET_DESPAWN_Z:
			bullet.queue_free()
			continue
		# Collision check: any obstacle within BULLET_COLLISION_DIST_SQ.
		for obstacle in obstacles_root.get_children():
			if not (obstacle is Node3D):
				continue
			# Quick AABB-ish check using squared distance in x,z plane
			# (y is roughly the same — both at ground level).
			var dx: float = bullet.position.x - obstacle.position.x
			var dz: float = bullet.position.z - obstacle.position.z
			if dx * dx + dz * dz < BULLET_COLLISION_DIST_SQ:
				obstacle.queue_free()
				bullet.queue_free()
				_hits += 1
				info_label.text = "3D PREVIEW · hits: %d" % _hits
				break

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

# Iter 66: spawn a single jelly-bean-colored bullet at the cowboy's
# position, traveling along -z toward the far edge of the plane.
func _spawn_bullet() -> void:
	var bullet := CSGSphere3D.new()
	bullet.radius = BULLET_PIXEL_SIZE
	bullet.radial_segments = 12
	bullet.rings = 8
	# Candy-color palette from iter 40e jelly bean bullets, picked at random
	var candy: Array[Color] = [
		Color(1.00, 0.32, 0.42, 1),
		Color(1.00, 0.84, 0.30, 1),
		Color(0.42, 0.92, 0.68, 1),
		Color(0.78, 0.48, 0.92, 1),
		Color(1.00, 0.62, 0.30, 1),
		Color(0.95, 0.55, 0.78, 1),
	]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = candy[_rng.randi() % candy.size()]
	mat.emission_enabled = true
	mat.emission = mat.albedo_color * 0.4
	bullet.material = mat
	bullet.position = Vector3(cowboy_3d.position.x,
		BULLET_SPAWN_Y, cowboy_3d.position.z - 0.5)
	bullets_root.add_child(bullet)

func _on_back_pressed() -> void:
	AudioBus.play_tap()
	get_tree().change_scene_to_file("res://scenes/debug_menu.tscn")
