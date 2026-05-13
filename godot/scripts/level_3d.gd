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
@onready var gates_root: Node3D = $Terrain3D/SubViewport/Gates
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

# Iter 75: gate spawn parameters. Gates are 2 colored door quads
# straddling the lane center, math values painted on as Label3D.
# Posse count starts at STARTING_POSSE (5) and modifies as cowboy
# walks through gates.
const GATE_SPAWN_INTERVAL: float = 4.5
const GATE_WIDTH: float = 8.0       # each door is 4.0 wide
const GATE_HEIGHT: float = 4.0
const GATE_TRIGGER_Z: float = 0.5   # gates fire when their z passes this
var _gate_spawn_timer: float = 0.0
var _posse_count_3d: int = 5
const STARTING_POSSE_3D: int = 5

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

# Iter 75: spawn a gate with two random door effects. Each door is a
# semi-transparent ColorRect-style 3D quad (CSGBox3D, very thin in z)
# with a math value Label3D billboard above it.
func _spawn_gate() -> void:
	var gate := Node3D.new()
	gate.position = Vector3(0, GATE_HEIGHT * 0.5, OBSTACLE_SPAWN_Z + 2.0)
	# Two random effects: ±[1..5] additive, or x[2..3] multiplicative.
	# Pick one side good, one side mediocre so the player has a choice.
	var values: Array[int] = []
	var operators: Array[String] = []
	for side in range(2):
		if _rng.randf() < 0.65:
			# Additive
			var v: int = _rng.randi_range(-5, 8)
			values.append(v)
			operators.append("+" if v > 0 else "")  # negative sign included in value
		else:
			# Multiplicative
			values.append(_rng.randi_range(2, 3))
			operators.append("×")
	gate.set_meta("left_value", values[0])
	gate.set_meta("left_op", operators[0])
	gate.set_meta("right_value", values[1])
	gate.set_meta("right_op", operators[1])
	gate.set_meta("triggered", false)
	# Left door (red if value would shrink, blue if grow)
	var left_door := CSGBox3D.new()
	left_door.size = Vector3(GATE_WIDTH * 0.5, GATE_HEIGHT, 0.15)
	left_door.position = Vector3(-GATE_WIDTH * 0.25, 0, 0)
	var lmat := StandardMaterial3D.new()
	lmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	lmat.albedo_color = _gate_color_for(values[0], operators[0])
	left_door.material = lmat
	gate.add_child(left_door)
	# Right door
	var right_door := CSGBox3D.new()
	right_door.size = Vector3(GATE_WIDTH * 0.5, GATE_HEIGHT, 0.15)
	right_door.position = Vector3(GATE_WIDTH * 0.25, 0, 0)
	var rmat := StandardMaterial3D.new()
	rmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rmat.albedo_color = _gate_color_for(values[1], operators[1])
	right_door.material = rmat
	gate.add_child(right_door)
	# Math value labels (Label3D billboards above each door)
	var llabel := Label3D.new()
	llabel.text = "%s%d" % [operators[0], values[0]]
	llabel.position = Vector3(-GATE_WIDTH * 0.25, GATE_HEIGHT * 0.55, 0)
	llabel.font_size = 96
	llabel.outline_size = 12
	llabel.modulate = Color.WHITE
	gate.add_child(llabel)
	var rlabel := Label3D.new()
	rlabel.text = "%s%d" % [operators[1], values[1]]
	rlabel.position = Vector3(GATE_WIDTH * 0.25, GATE_HEIGHT * 0.55, 0)
	rlabel.font_size = 96
	rlabel.outline_size = 12
	rlabel.modulate = Color.WHITE
	gate.add_child(rlabel)
	gates_root.add_child(gate)

# Gate door color helper. Blue = "growing" (good), red = "shrinking" (bad).
func _gate_color_for(value: int, op: String) -> Color:
	var growing: bool
	if op == "×":
		growing = value >= 2  # all multipliers grow in this prototype
	else:
		growing = value > 0
	return Color(0.25, 0.55, 1.0, 0.6) if growing else Color(1.0, 0.30, 0.30, 0.6)

# Iter 75: check whether the cowboy has crossed the gate's z plane.
# When triggered, apply the side's effect based on cowboy.x.
func _check_gate_trigger(gate: Node3D) -> void:
	if gate.get_meta("triggered", false):
		return
	if gate.position.z < GATE_TRIGGER_Z:
		return
	gate.set_meta("triggered", true)
	# Cowboy passed through which side?
	var x: float = cowboy_3d.position.x
	var value: int
	var op: String
	if x < 0:
		value = gate.get_meta("left_value")
		op = gate.get_meta("left_op")
	else:
		value = gate.get_meta("right_value")
		op = gate.get_meta("right_op")
	# Apply effect
	var before: int = _posse_count_3d
	if op == "×":
		_posse_count_3d *= value
	else:
		_posse_count_3d += value
	_posse_count_3d = maxi(0, _posse_count_3d)
	info_label.text = "POSSE %d (was %d)  ·  hits %d" % [
		_posse_count_3d, before, _hits,
	]
	AudioBus.play_gate_pass()

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
	# Iter 75: gates scroll like obstacles + check trigger when crossing z plane
	_gate_spawn_timer -= delta
	if _gate_spawn_timer <= 0.0:
		_gate_spawn_timer = GATE_SPAWN_INTERVAL
		_spawn_gate()
	for gate in gates_root.get_children():
		if gate is Node3D:
			gate.position.z += OBSTACLE_SPEED * delta
			_check_gate_trigger(gate)
			if gate.position.z > OBSTACLE_DESPAWN_Z:
				gate.queue_free()
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

# Iter 74: spawn a typed obstacle. Random pick from 4 entity flavors,
# each with proper proportions + color palette matching their 2D
# counterparts in the gameplay scene.
#   barrel:     short brown cylinder (CSGCylinder3D)
#   cactus:     tall green box (CSGBox3D)
#   tumbleweed: brown sphere (CSGSphere3D, rolls)
#   bull:       wide dark-brown box (CSGBox3D)
enum ObstacleType { BARREL, CACTUS, TUMBLEWEED, BULL }

func _spawn_obstacle() -> void:
	var lane_x: float = _rng.randf_range(-COWBOY_X_BOUND * 0.85,
		COWBOY_X_BOUND * 0.85)
	var pick: int = _rng.randi() % 4
	var obstacle: Node3D
	var mat := StandardMaterial3D.new()
	match pick:
		ObstacleType.BARREL:
			var b := CSGCylinder3D.new()
			b.radius = 0.8
			b.height = 1.4
			mat.albedo_color = Color(0.42, 0.26, 0.13, 1)
			b.material = mat
			b.position = Vector3(lane_x, 0.7, OBSTACLE_SPAWN_Z)
			obstacle = b
		ObstacleType.CACTUS:
			var c := CSGBox3D.new()
			c.size = Vector3(0.7, 2.4, 0.7)
			mat.albedo_color = Color(0.22, 0.45, 0.18, 1)
			c.material = mat
			c.position = Vector3(lane_x, 1.2, OBSTACLE_SPAWN_Z)
			obstacle = c
		ObstacleType.TUMBLEWEED:
			var t := CSGSphere3D.new()
			t.radius = 0.9
			t.radial_segments = 8
			t.rings = 6
			mat.albedo_color = Color(0.55, 0.36, 0.18, 1)
			t.material = mat
			t.position = Vector3(lane_x, 0.9, OBSTACLE_SPAWN_Z)
			obstacle = t
		_:  # BULL
			var bull := CSGBox3D.new()
			bull.size = Vector3(2.5, 1.6, 1.8)
			mat.albedo_color = Color(0.32, 0.18, 0.10, 1)
			bull.material = mat
			bull.position = Vector3(lane_x, 0.8, OBSTACLE_SPAWN_Z)
			obstacle = bull
	obstacles_root.add_child(obstacle)

# Iter 66/73: spawn jelly-bean-colored bullets at the cowboy's position
# AND at every follower's position (iter 73). One AudioBus.play_gunfire
# call per fire trigger (not per bullet) so a 5-dude posse doesn't
# overlap-stack 5 gunshot samples.
const CANDY_BULLET_COLORS: Array[Color] = [
	Color(1.00, 0.32, 0.42, 1),
	Color(1.00, 0.84, 0.30, 1),
	Color(0.42, 0.92, 0.68, 1),
	Color(0.78, 0.48, 0.92, 1),
	Color(1.00, 0.62, 0.30, 1),
	Color(0.95, 0.55, 0.78, 1),
]

func _spawn_bullet() -> void:
	# Iter 73: gunfire SFX. Single call so multi-dude firing doesn't
	# stack 5 layered samples per shot.
	if get_node_or_null("/root/AudioBus"):
		AudioBus.play_gunfire()
	# Spawn one bullet at leader.
	_spawn_bullet_at(cowboy_3d.position.x, cowboy_3d.position.z)
	# Iter 73: also spawn a bullet at each posse follower's position so
	# the full posse fires (matches 2D level.gd's iter 61 multi-shooter).
	for f in _followers:
		if is_instance_valid(f):
			_spawn_bullet_at(f.position.x, f.position.z)

# Iter 73: factored out per-position bullet spawner. Same candy-color
# palette + emissive material + -z velocity as iter 66.
func _spawn_bullet_at(world_x: float, world_z: float) -> void:
	var bullet := CSGSphere3D.new()
	bullet.radius = BULLET_PIXEL_SIZE
	bullet.radial_segments = 12
	bullet.rings = 8
	var mat := StandardMaterial3D.new()
	mat.albedo_color = CANDY_BULLET_COLORS[_rng.randi() % CANDY_BULLET_COLORS.size()]
	mat.emission_enabled = true
	mat.emission = mat.albedo_color * 0.4
	bullet.material = mat
	bullet.position = Vector3(world_x, BULLET_SPAWN_Y, world_z - 0.5)
	bullets_root.add_child(bullet)

func _on_back_pressed() -> void:
	AudioBus.play_tap()
	get_tree().change_scene_to_file("res://scenes/debug_menu.tscn")
