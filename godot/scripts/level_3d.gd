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
# Iter 95: 3D content vars below were @onready against .tscn nodes
# that are now created in _build_3d_content() (called from _ready)
# instead of being baked into level_3d.tscn. The .tscn now matches
# terrain_3d.tscn's minimal SubViewport structure exactly.
var cowboy_3d: Sprite3D
var obstacles_root: Node3D
var bullets_root: Node3D
var gates_root: Node3D
var outlaws_root: Node3D
var outlaw_bullets_root: Node3D
var boss_root: Node3D
# Iter 69: terrain_3d.gd script wasn't attached to the inline Terrain3D
# node in level_3d.tscn, so the SubViewport→Sprite2D texture wiring
# never ran. Reference + manual hookup in _ready below.
@onready var terrain_sprite: Sprite2D = $Terrain3D/Sprite
@onready var back_button: Button = $UI/BackButton
@onready var info_label: Label = $UI/InfoLabel
# Iter 79: dedicated HUD labels.
@onready var hearts_label: Label = $UI/HeartsLabel
@onready var posse_label: Label = $UI/PosseLabel
@onready var hits_label: Label = $UI/HitsLabel
# Iter 95: also created in _build_3d_content().
var popups_root: Node3D
var bonuses_root: Node3D

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

# Iter 76: outlaw enemies. Spawn red boxes periodically at far z that
# scroll toward camera + fire red bullets at the cowboy.
const OUTLAW_SPAWN_INTERVAL: float = 3.0
const OUTLAW_SPEED: float = 4.0  # slower than obstacles — they're shooters
const OUTLAW_FIRE_INTERVAL: float = 1.8
const OUTLAW_BULLET_SPEED: float = 14.0
const OUTLAW_BULLET_RADIUS: float = 0.35
const OUTLAW_BULLET_DESPAWN_Z: float = 4.0
const OUTLAW_HIT_RADIUS_SQ: float = 1.5 * 1.5
const OUTLAW_HP: int = 3
var _outlaw_spawn_timer: float = 0.0

# Iter 77: Slippery Pete boss. Appears at PETE_SPAWN_DELAY into the
# level. Slow approach, much higher HP, drops the WIN modal on defeat.
const PETE_SPAWN_DELAY: float = 25.0
const PETE_HP: int = 40
const PETE_SPEED: float = 1.6
const PETE_FIRE_INTERVAL: float = 1.0
const PETE_HIT_RADIUS_SQ: float = 2.6 * 2.6
const PETE_STAY_Z: float = -6.0  # stops here for the duel

# Iter 88: bonus pickup spawn parameters. Pickups appear periodically
# at a random lane x, hover with sine y-bob, scroll toward cowboy.
# Collision with cowboy → BulletFireMode change for the rest of level.
const BONUS_SPAWN_INTERVAL: float = 7.0
const BONUS_PICKUP_RADIUS_SQ: float = 1.6 * 1.6
const BONUS_SPEED: float = OBSTACLE_SPEED  # match obstacle scroll
var _bonus_spawn_timer: float = 0.0

# Iter 88: bullet fire modes. Each pickup changes how _spawn_bullet
# colors / sizes its bullets. Default = candy palette random.
enum FireMode { CANDY, RIFLE, FROSTBITE, FRENZY }
var _fire_mode: int = FireMode.CANDY
var _pete_spawned: bool = false
var _pete_defeated: bool = false
var _level_elapsed: float = 0.0
var _pete_fire_timer: float = 0.0
@onready var win_overlay: ColorRect = $UI/WinOverlay
@onready var win_label: Label = $UI/WinOverlay/WinLabel
@onready var retry_button: Button = $UI/WinOverlay/RetryButton
@onready var fail_overlay: ColorRect = $UI/FailOverlay
@onready var fail_label: Label = $UI/FailOverlay/FailLabel
@onready var fail_retry_button: Button = $UI/FailOverlay/RetryButton
var _failed: bool = false

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

# Iter 85: subtle y-bob animation gives life to the otherwise-static
# billboards. Sine wave on position.y at each frame; followers get a
# phase offset so they don't bob in lockstep with the leader.
const BOB_AMPLITUDE: float = 0.06
const BOB_FREQUENCY: float = 4.5
var _bob_time: float = 0.0

func _ready() -> void:
	# Iter 97: VISIBLE breadcrumb. Iter 96 log showed no DebugLog entries
	# from this _ready despite the terrain rendering — meaning either
	# _ready never ran OR an early line threw before reaching the first
	# DebugLog.add. Set info_label.text BEFORE anything else, with a
	# null-guard, so the user can see on-screen whether _ready entered
	# at all. If the label still reads the .tscn default, _ready never
	# fired. If it reads "iter97 RDY-1" but no further updates appear,
	# the next line threw.
	if info_label != null:
		info_label.text = "iter97 RDY-1 entered"
	print("[level_3d] _ready ENTER")
	# Iter 91: breadcrumbs after every step so a freeze post-PREVIEW-3D
	# pinpoints the failing line in the COPY log.
	DebugLog.add("level_3d _ready start (build=%s iter=%s)" % [
		BuildInfo.SHA, BuildInfo.ITER,
	])
	if info_label != null:
		info_label.text = "iter97 RDY-2 logged"
	get_tree().set_quit_on_go_back(false)
	if get_window():
		get_window().go_back_requested.connect(_on_back_pressed)
	if back_button:
		back_button.pressed.connect(_on_back_pressed)
		# Iter 97: make the back button GIGANTIC + bright red so we can
		# verify it visually + clearly hits Android's touch slop. If the
		# button still doesn't work after this, the signal connect itself
		# is silently failing (Godot Android quirk?).
		back_button.add_theme_color_override("font_color", Color(1, 0.4, 0.3, 1))
	DebugLog.add("level_3d: back signals wired")
	if info_label != null:
		info_label.text = "iter97 RDY-3 back wired"
	_rng.seed = 6464
	# Iter 96: terrain_3d.gd (attached to the Terrain3D instance) now
	# does its own subviewport→sprite binding in its _ready, so the
	# manual binding from iter 69 is no longer needed. Keeping a
	# breadcrumb so the log still shows the binding step succeeded.
	if subviewport != null:
		DebugLog.add("level_3d: terrain instance loaded; subviewport=%s" % subviewport.size)
	else:
		DebugLog.add("WARN level_3d: subviewport null after terrain instance")
	# Iter 95: build 3D content (cowboy + mountains + 8 container Node3Ds)
	# AFTER initial setup. Hypothesis: bundling everything into .tscn was
	# overloading mobile scene-load — script-side spawn defers texture
	# upload / shader compile / node tree allocation to post-_ready frames.
	_build_3d_content()
	if info_label != null:
		info_label.text = "iter97 RDY-4 3D built"
	# Iter 72: spawn posse followers at trapezoid offsets behind leader.
	# Must run AFTER _build_3d_content since it clones cowboy_3d.
	_spawn_posse_followers()
	if info_label != null:
		info_label.text = "iter97 RDY-5 followers ok"
	info_label.text = "iter97 OK · build %s · top-left to exit" % BuildInfo.SHA
	DebugLog.add("level_3d _ready (build=%s)" % BuildInfo.SHA)
	# Iter 79: initial HUD render.
	_refresh_hud()
	# Iter 77: win-modal Retry button.
	if retry_button:
		retry_button.pressed.connect(_on_retry_pressed)
	# Iter 78: fail-modal Retry button.
	if fail_retry_button:
		fail_retry_button.pressed.connect(_on_retry_pressed)

# Iter 95: build all 3D scene content that used to live in level_3d.tscn.
# Order: containers → cowboy → mountains. After each step a DebugLog
# breadcrumb lands so a freeze midway through pinpoints the failing step.
const COWBOY_TEXTURE_LVL3D := preload("res://assets/sprites/posse_idle_00.png")

func _build_3d_content() -> void:
	if subviewport == null:
		DebugLog.add("WARN level_3d: subviewport null in _build_3d_content")
		return
	DebugLog.add("level_3d: building 3D content")
	# 1) Empty Node3D containers — cheapest first so they're available
	# to other systems even if cowboy/mountain spawn fails.
	obstacles_root = _make_lvl3d_container("Obstacles")
	bullets_root = _make_lvl3d_container("Bullets")
	gates_root = _make_lvl3d_container("Gates")
	outlaws_root = _make_lvl3d_container("Outlaws")
	outlaw_bullets_root = _make_lvl3d_container("OutlawBullets")
	boss_root = _make_lvl3d_container("Boss")
	popups_root = _make_lvl3d_container("Popups")
	bonuses_root = _make_lvl3d_container("Bonuses")
	DebugLog.add("level_3d: 8 containers added to subviewport")
	# 2) Cowboy3D Sprite3D billboard.
	cowboy_3d = Sprite3D.new()
	cowboy_3d.name = "Cowboy3D"
	cowboy_3d.texture = COWBOY_TEXTURE_LVL3D
	cowboy_3d.pixel_size = 0.002
	cowboy_3d.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	cowboy_3d.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	cowboy_3d.position = Vector3(0, 0.45, 1.5)
	subviewport.add_child(cowboy_3d)
	DebugLog.add("level_3d: cowboy_3d added")
	# 3) 4 mountain MeshInstance3D silhouettes.
	_spawn_mountains_lvl3d()
	DebugLog.add("level_3d: mountains added")

func _make_lvl3d_container(node_name: String) -> Node3D:
	var n := Node3D.new()
	n.name = node_name
	subviewport.add_child(n)
	return n

func _spawn_mountains_lvl3d() -> void:
	var box_mesh := BoxMesh.new()
	box_mesh.size = Vector3(1, 1, 1)
	var mat_a := StandardMaterial3D.new()
	mat_a.albedo_color = Color(0.35, 0.22, 0.32, 1)
	mat_a.roughness = 1.0
	var mat_b := StandardMaterial3D.new()
	mat_b.albedo_color = Color(0.42, 0.28, 0.36, 1)
	mat_b.roughness = 1.0
	var configs: Array = [
		{"pos": Vector3(-16, 3.0, -32), "scl": Vector3(12, 7, 1),  "mat": mat_a},
		{"pos": Vector3(-6,  4.0, -33), "scl": Vector3(10, 9, 1),  "mat": mat_b},
		{"pos": Vector3(4,   3.5, -32), "scl": Vector3(11, 8, 1),  "mat": mat_a},
		{"pos": Vector3(14,  4.5, -33), "scl": Vector3(10, 10, 1), "mat": mat_b},
	]
	for c in configs:
		var m := MeshInstance3D.new()
		m.mesh = box_mesh
		m.material_override = c["mat"]
		m.position = c["pos"]
		m.scale = c["scl"]
		subviewport.add_child(m)

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
	info_label.text = "gate passed: %s%d  (posse %d→%d)" % [
		op, value, before, _posse_count_3d,
	]
	AudioBus.play_gate_pass()
	_refresh_hud()

# Iter 88: spawn a bonus pickup. Tall thin floating Sprite3D-style box
# with a math-symbol Label3D billboard above it. Cowboy collides to
# collect; pickup_type meta drives the FireMode swap.
const BONUS_TYPES: Array[String] = ["rifle", "frostbite", "frenzy"]
const BONUS_COLORS: Dictionary = {
	"rifle":     Color(0.55, 0.32, 0.16, 1),    # brown wood-stock
	"frostbite": Color(0.55, 0.85, 1.00, 1),    # icy cyan
	"frenzy":    Color(1.00, 0.55, 0.85, 1),    # pink frenzy
}
const BONUS_LABELS: Dictionary = {
	"rifle":     "R",
	"frostbite": "❄",
	"frenzy":    "J!",
}

func _spawn_bonus() -> void:
	var t: String = BONUS_TYPES[_rng.randi() % BONUS_TYPES.size()]
	var bonus := CSGBox3D.new()
	bonus.size = Vector3(1.0, 1.0, 1.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = BONUS_COLORS[t]
	mat.emission_enabled = true
	mat.emission = mat.albedo_color * 0.6
	bonus.material = mat
	var lane_x: float = _rng.randf_range(-COWBOY_X_BOUND * 0.65,
		COWBOY_X_BOUND * 0.65)
	bonus.position = Vector3(lane_x, 1.5, OBSTACLE_SPAWN_Z + 2.0)
	bonus.set_meta("bonus_type", t)
	bonus.set_meta("spawn_time", _level_elapsed)
	# Floating type label above the box
	var lbl := Label3D.new()
	lbl.text = BONUS_LABELS[t]
	lbl.font_size = 64
	lbl.outline_size = 8
	lbl.modulate = Color(1, 1, 1, 1)
	lbl.position = Vector3(0, 1.0, 0)
	bonus.add_child(lbl)
	bonuses_root.add_child(bonus)

# Iter 88: cowboy collects a bonus → swap FireMode + show feedback popup.
func _collect_bonus(bonus: Node3D) -> void:
	var t: String = bonus.get_meta("bonus_type", "candy")
	match t:
		"rifle":     _fire_mode = FireMode.RIFLE
		"frostbite": _fire_mode = FireMode.FROSTBITE
		"frenzy":    _fire_mode = FireMode.FRENZY
	_spawn_popup_3d(bonus.position + Vector3(0, 2.0, 0),
		t.to_upper(), BONUS_COLORS[t], 56)
	bonus.queue_free()

# Iter 77: spawn the Slippery Pete boss. Big yellow CSGBox3D with an
# HP meta field + state machine. Stops at PETE_STAY_Z for the duel.
func _spawn_pete() -> void:
	var pete := CSGBox3D.new()
	pete.size = Vector3(2.4, 4.2, 1.2)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.92, 0.78, 0.22, 1)  # mustard yellow
	mat.emission_enabled = true
	mat.emission = Color(0.40, 0.30, 0.05, 1)
	pete.material = mat
	pete.position = Vector3(0.0, 2.1, OBSTACLE_SPAWN_Z + 4.0)
	pete.set_meta("hp", PETE_HP)
	boss_root.add_child(pete)
	# Big "BOSS" label floating above him
	var label := Label3D.new()
	label.text = "SLIPPERY PETE"
	label.font_size = 80
	label.outline_size = 14
	label.modulate = Color(1, 0.45, 0.30, 1)
	label.position = Vector3(0, 3.2, 0)
	pete.add_child(label)
	# Iter 84: HP bar above name. Background bar (dark) + foreground
	# (red) that shrinks as HP drops. Stored under meta 'hp_fg' so the
	# bullet-hit handler can refresh it.
	var hp_bg := CSGBox3D.new()
	hp_bg.size = Vector3(2.5, 0.25, 0.05)
	hp_bg.position = Vector3(0, 2.7, 0)
	var bg_mat := StandardMaterial3D.new()
	bg_mat.albedo_color = Color(0.05, 0.05, 0.05, 0.85)
	hp_bg.material = bg_mat
	pete.add_child(hp_bg)
	var hp_fg := CSGBox3D.new()
	hp_fg.size = Vector3(2.5, 0.20, 0.08)
	hp_fg.position = Vector3(0, 2.7, 0.01)  # forward of bg to avoid z-fight
	var fg_mat := StandardMaterial3D.new()
	fg_mat.albedo_color = Color(0.95, 0.25, 0.25, 1)
	fg_mat.emission_enabled = true
	fg_mat.emission = Color(0.5, 0.1, 0.1, 1)
	hp_fg.material = fg_mat
	pete.add_child(hp_fg)
	pete.set_meta("hp_fg", hp_fg)
	pete.set_meta("hp_fg_max_width", 2.5)
	info_label.text = "BOSS APPEARS — SHOOT PETE"

# Iter 84: refresh Pete's HP bar foreground width + color based on HP %.
func _refresh_pete_hp(pete: Node3D) -> void:
	var fg: CSGBox3D = pete.get_meta("hp_fg")
	if fg == null or not is_instance_valid(fg):
		return
	var hp: int = pete.get_meta("hp", PETE_HP)
	var max_w: float = pete.get_meta("hp_fg_max_width", 2.5)
	var pct: float = float(maxi(hp, 0)) / float(PETE_HP)
	fg.size.x = max_w * pct
	# Re-center on shrink so the bar shrinks from the right edge.
	fg.position.x = (max_w * pct - max_w) * 0.5
	# Color: green > 60%, yellow > 30%, red below.
	var c: Color
	if pct > 0.6:
		c = Color(0.35, 0.85, 0.32, 1)
	elif pct > 0.3:
		c = Color(0.95, 0.85, 0.25, 1)
	else:
		c = Color(0.95, 0.25, 0.25, 1)
	(fg.material as StandardMaterial3D).albedo_color = c

# Iter 77/83: Pete fires a red bullet at the cowboy. Iter 83 adds a
# random taunt shout above his head every 3rd-4th fire — pulls from
# the existing en.json corpus via the Text autoload.
var _pete_fire_count: int = 0
const PETE_TAUNT_INTERVAL: int = 3  # taunt every Nth shot

func _pete_fire() -> void:
	if boss_root.get_child_count() == 0:
		return
	var pete: Node3D = boss_root.get_child(0)
	if not (pete is Node3D):
		return
	_outlaw_fire(pete)
	_pete_fire_count += 1
	if _pete_fire_count % PETE_TAUNT_INTERVAL == 0:
		_pete_spawn_taunt(pete)

# Iter 83: spawn a Label3D speech bubble above Pete with a random taunt
# from the en.json dialog corpus (boss.slippery_pete_dialog_taunts).
# Tweens up + fades out over 1.8s like the iter 55 2D speech bubble.
func _pete_spawn_taunt(pete: Node3D) -> void:
	if get_node_or_null("/root/Text") == null:
		return
	var line: String = Text.random("boss.slippery_pete_dialog_taunts")
	if line == "" or line == "boss.slippery_pete_dialog_taunts":
		return
	var bubble := Label3D.new()
	bubble.text = line
	bubble.font_size = 56
	bubble.outline_size = 12
	bubble.modulate = Color(1, 0.92, 0.55, 1)
	bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	bubble.no_depth_test = true
	bubble.position = pete.position + Vector3(0, 4.0, 0)
	popups_root.add_child(bubble)
	var t := create_tween().set_parallel(true)
	t.tween_property(bubble, "position:y",
		bubble.position.y + 2.0, 1.8) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(bubble, "modulate:a", 0.0, 1.8) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.chain().tween_callback(bubble.queue_free)

# Iter 80: spawn a 3D damage popup at a world position. Label3D billboard
# floats up + fades over 0.7s, then queue_frees. Sized via font_size +
# outline. Color override via the modulate property.
const POPUP_LIFESPAN: float = 0.7
const POPUP_RISE: float = 2.0

func _spawn_popup_3d(world_pos: Vector3, text: String, color: Color, size: int) -> void:
	var label := Label3D.new()
	label.text = text
	label.font_size = size
	label.outline_size = 12
	label.modulate = color
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.position = world_pos
	popups_root.add_child(label)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(label, "position:y", world_pos.y + POPUP_RISE,
		POPUP_LIFESPAN).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, POPUP_LIFESPAN) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(label.queue_free)

# Iter 79: render the 3-label HUD from current state. Called after any
# event that changes hearts/posse/hits (gate pass, outlaw kill, posse
# damage). Hearts read from GameState if available.
func _refresh_hud() -> void:
	if hearts_label:
		var max_h: int = 5
		var current: int = 5
		if get_node_or_null("/root/GameState"):
			max_h = GameState.MAX_HEARTS
			current = GameState.hearts
		var parts: PackedStringArray = PackedStringArray()
		for i in range(max_h):
			parts.append("♥" if i < current else "·")
		hearts_label.text = " ".join(parts)
	if posse_label:
		posse_label.text = "POSSE: %d" % _posse_count_3d
	if hits_label:
		hits_label.text = "HITS: %d" % _hits

# Iter 78: trigger the FAIL flow on posse=0. Deduct a heart, pop the
# FailOverlay, freeze the game (skip _process via _failed flag).
func _show_fail() -> void:
	if _failed:
		return
	_failed = true
	# Iter 87: kill any lingering gunshot pool samples so the sound
	# doesn't keep playing after the firefight ends.
	if get_node_or_null("/root/AudioBus") and AudioBus.has_method("stop_gunfire"):
		AudioBus.stop_gunfire()
	# Deduct one heart from the autoloaded GameState (Murderbot voice
	# context: 'one less posse for next time').
	if get_node_or_null("/root/GameState"):
		GameState.spend_heart()
	info_label.text = "DEAD  ·  posse 0  ·  hits %d" % _hits
	if fail_label:
		fail_label.text = "DEAD\n%d hits" % _hits
	if fail_overlay:
		fail_overlay.visible = true

# Iter 77/81: trigger the win flow. Pop the WIN overlay AFTER playing
# the iter 81 Gold Rush salute ceremony — each remaining posse member
# fires a celebratory shot + spawns a +50 BOUNTY popup. Total bounty
# accumulated in GameState.
func _show_win() -> void:
	_pete_defeated = true
	# Iter 87: stop the lingering gunshot pool so the salute (which
	# spawns its own gunfire) doesn't fight the trailing combat audio.
	if get_node_or_null("/root/AudioBus") and AudioBus.has_method("stop_gunfire"):
		AudioBus.stop_gunfire()
	info_label.text = "WIN!  Pete defeated · posse %d · hits %d" % [
		_posse_count_3d, _hits,
	]
	await _gold_rush_salute_3d()
	if win_label:
		win_label.text = "BOUNTY!\nposse %d · hits %d" % [_posse_count_3d, _hits]
	if win_overlay:
		win_overlay.visible = true
	AudioBus.play_gate_pass()

# Iter 81: Gold Rush A — Six-Shooter Salute, ported to 3D.
# Each remaining posse member (leader + active followers) fires a
# bright bullet straight up + spawns a +50 BOUNTY 3D popup at their
# position. Staggered 280ms per shot. GameState.bounty incremented.
const SALUTE_PER_SHOT: int = 50
const SALUTE_STAGGER_S: float = 0.28
const SALUTE_CASCADE_BONUS: int = 500

func _gold_rush_salute_3d() -> void:
	# Collect firing positions: leader + all active followers.
	var positions: Array[Vector3] = []
	if cowboy_3d:
		positions.append(cowboy_3d.position)
	for f in _followers:
		if is_instance_valid(f):
			positions.append(f.position)
	for pos in positions:
		await get_tree().create_timer(SALUTE_STAGGER_S).timeout
		if not is_inside_tree():
			return
		# Salute bullet — fired straight up, bright yellow.
		var b := CSGSphere3D.new()
		b.radius = 0.4
		b.radial_segments = 8
		b.rings = 6
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(1.0, 0.9, 0.3, 1)
		mat.emission_enabled = true
		mat.emission = Color(0.8, 0.6, 0.1, 1)
		b.material = mat
		b.position = pos + Vector3(0, 1.0, 0)
		bullets_root.add_child(b)
		# Tween straight up + fade
		var t := create_tween().set_parallel(true)
		t.tween_property(b, "position:y", pos.y + 5.0, 0.6) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		t.tween_property(b, "scale", Vector3(0.2, 0.2, 0.2), 0.6) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		t.chain().tween_callback(b.queue_free)
		_spawn_popup_3d(pos + Vector3(0, 2.0, 0),
			"+%d" % SALUTE_PER_SHOT, Color(1.0, 0.92, 0.30, 1), 64)
		AudioBus.play_gunfire()
		if get_node_or_null("/root/GameState"):
			GameState.bounty += SALUTE_PER_SHOT
	# Cascade beat — central +500 popup
	await get_tree().create_timer(0.3).timeout
	_spawn_popup_3d(Vector3(0, 3.0, cowboy_3d.position.z),
		"+%d PERFECT" % SALUTE_CASCADE_BONUS,
		Color(1.0, 0.92, 0.30, 1), 88)
	if get_node_or_null("/root/GameState"):
		GameState.bounty += SALUTE_CASCADE_BONUS
	await get_tree().create_timer(0.5).timeout

# Iter 76: spawn a red outlaw at a random lane position at far z.
func _spawn_outlaw() -> void:
	var outlaw := CSGBox3D.new()
	outlaw.size = Vector3(0.9, 2.0, 0.6)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.78, 0.18, 0.18, 1)
	outlaw.material = mat
	var lane_x: float = _rng.randf_range(-COWBOY_X_BOUND * 0.75,
		COWBOY_X_BOUND * 0.75)
	outlaw.position = Vector3(lane_x, 1.0, OBSTACLE_SPAWN_Z + 4.0)
	outlaw.set_meta("hp", OUTLAW_HP)
	outlaw.set_meta("fire_timer", _rng.randf() * OUTLAW_FIRE_INTERVAL)
	outlaws_root.add_child(outlaw)

# Iter 76: outlaw fires a red bullet aimed at the cowboy.
func _outlaw_fire(outlaw: Node3D) -> void:
	var b := CSGSphere3D.new()
	b.radius = OUTLAW_BULLET_RADIUS
	b.radial_segments = 8
	b.rings = 6
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.3, 0.2, 1)
	mat.emission_enabled = true
	mat.emission = mat.albedo_color * 0.5
	b.material = mat
	b.position = outlaw.position
	# Velocity: from outlaw toward cowboy, normalized × speed
	var to_cowboy: Vector3 = cowboy_3d.position - outlaw.position
	to_cowboy.y = 0.0  # keep bullets level
	if to_cowboy.length() > 0.001:
		to_cowboy = to_cowboy.normalized() * OUTLAW_BULLET_SPEED
	else:
		to_cowboy = Vector3(0, 0, OUTLAW_BULLET_SPEED)
	b.set_meta("velocity", to_cowboy)
	outlaw_bullets_root.add_child(b)

func _process(delta: float) -> void:
	if _pete_defeated or _failed:
		return
	# Iter 78: posse-wiped check fires once per frame.
	if _posse_count_3d <= 0 and not _failed:
		_show_fail()
		return
	_level_elapsed += delta
	# Lerp cowboy x toward target (drag input target).
	cowboy_3d.position.x = lerpf(cowboy_3d.position.x, _target_x,
		clampf(COWBOY_LERP_SPEED * delta, 0.0, 1.0))
	# Iter 72: followers track the leader's x with formation-offset lag.
	# Iter 85: y-bob animation overlays on top of the base 0.45 anchor.
	_bob_time += delta
	cowboy_3d.position.y = 0.45 + sin(_bob_time * BOB_FREQUENCY) * BOB_AMPLITUDE
	for i in range(_followers.size()):
		var f := _followers[i]
		if not is_instance_valid(f):
			continue
		var offset: Vector3 = f.get_meta("formation_offset", Vector3.ZERO)
		var target_fx: float = cowboy_3d.position.x + offset.x
		f.position.x = lerpf(f.position.x, target_fx,
			clampf(FOLLOWER_LERP_SPEED * delta, 0.0, 1.0))
		# Phase offset per follower so the crowd looks alive.
		f.position.y = 0.45 + sin(_bob_time * BOB_FREQUENCY + float(i) * 0.7) * BOB_AMPLITUDE
	# Spawn obstacles periodically.
	_spawn_timer -= delta
	if _spawn_timer <= 0.0:
		_spawn_timer = OBSTACLE_SPAWN_INTERVAL
		_spawn_obstacle()
	# Move all obstacles toward camera (z increases since camera is at z>0).
	# Iter 87: tumbleweeds (CSGSphere3D) rotate as they roll forward —
	# adds life vs just sliding rigid shapes. Other shapes (barrel /
	# cactus / bull boxes) stay rigid since they don't roll IRL.
	for child in obstacles_root.get_children():
		if child is Node3D:
			child.position.z += OBSTACLE_SPEED * delta
			if child is CSGSphere3D:
				child.rotation.x += OBSTACLE_SPEED * delta * 0.5
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
	# Iter 76: outlaws — spawn / scroll / fire / despawn.
	_outlaw_spawn_timer -= delta
	if _outlaw_spawn_timer <= 0.0:
		_outlaw_spawn_timer = OUTLAW_SPAWN_INTERVAL
		_spawn_outlaw()
	for outlaw in outlaws_root.get_children():
		if not (outlaw is Node3D):
			continue
		outlaw.position.z += OUTLAW_SPEED * delta
		var ft: float = outlaw.get_meta("fire_timer", 0.0)
		ft -= delta
		if ft <= 0.0:
			ft = OUTLAW_FIRE_INTERVAL
			_outlaw_fire(outlaw)
		outlaw.set_meta("fire_timer", ft)
		if outlaw.position.z > OBSTACLE_DESPAWN_Z:
			outlaw.queue_free()
		# Bullet-vs-outlaw collision (use posse bullets)
		for bullet in bullets_root.get_children():
			if not (bullet is Node3D):
				continue
			var dx: float = bullet.position.x - outlaw.position.x
			var dz: float = bullet.position.z - outlaw.position.z
			if dx * dx + dz * dz < OUTLAW_HIT_RADIUS_SQ:
				var hp: int = outlaw.get_meta("hp", 1) - 1
				outlaw.set_meta("hp", hp)
				_spawn_popup_3d(outlaw.position + Vector3(0, 1.2, 0),
					"-1", Color(1, 0.32, 0.22, 1), 56)
				bullet.queue_free()
				if hp <= 0:
					outlaw.queue_free()
					_hits += 1
					_refresh_hud()
				break
	# Iter 76: outlaw bullets move along their stored velocity vector.
	# Despawn off-screen or after reaching cowboy.
	for ob in outlaw_bullets_root.get_children():
		if not (ob is Node3D):
			continue
		var vel: Vector3 = ob.get_meta("velocity", Vector3.ZERO)
		ob.position += vel * delta
		# Posse-hit: if bullet reaches cowboy's near plane, decrement
		# posse and kill the bullet.
		if ob.position.z > cowboy_3d.position.z - 0.3:
			ob.queue_free()
			_posse_count_3d = maxi(0, _posse_count_3d - 1)
			_refresh_hud()
		elif ob.position.z > OUTLAW_BULLET_DESPAWN_Z or absf(ob.position.x) > 25.0:
			ob.queue_free()
	# Iter 88: bonus pickup spawn / scroll / collect.
	_bonus_spawn_timer -= delta
	if _bonus_spawn_timer <= 0.0:
		_bonus_spawn_timer = BONUS_SPAWN_INTERVAL
		_spawn_bonus()
	for bonus in bonuses_root.get_children():
		if not (bonus is Node3D):
			continue
		bonus.position.z += BONUS_SPEED * delta
		# Sine y-bob for floating feel
		var st: float = bonus.get_meta("spawn_time", 0.0)
		bonus.position.y = 1.5 + sin((_level_elapsed - st) * 4.0) * 0.2
		bonus.rotation.y += 2.0 * delta  # slow spin
		# Cowboy collision check
		var bdx: float = bonus.position.x - cowboy_3d.position.x
		var bdz: float = bonus.position.z - cowboy_3d.position.z
		if bdx * bdx + bdz * bdz < BONUS_PICKUP_RADIUS_SQ:
			_collect_bonus(bonus)
		elif bonus.position.z > OBSTACLE_DESPAWN_Z:
			bonus.queue_free()
	# Iter 77: spawn Pete after PETE_SPAWN_DELAY.
	if not _pete_spawned and _level_elapsed >= PETE_SPAWN_DELAY:
		_pete_spawned = true
		_spawn_pete()
	# Iter 77: Pete behavior — approach to PETE_STAY_Z, fire periodically,
	# check bullet hits.
	if _pete_spawned and boss_root.get_child_count() > 0:
		var pete: Node3D = boss_root.get_child(0)
		if is_instance_valid(pete) and pete is Node3D:
			# Approach until STAY_Z
			if pete.position.z < PETE_STAY_Z:
				pete.position.z += PETE_SPEED * delta
			# Fire periodically
			_pete_fire_timer -= delta
			if _pete_fire_timer <= 0.0:
				_pete_fire_timer = PETE_FIRE_INTERVAL
				_pete_fire()
			# Bullet hit check
			for bullet in bullets_root.get_children():
				if not (bullet is Node3D):
					continue
				var dx: float = bullet.position.x - pete.position.x
				var dz: float = bullet.position.z - pete.position.z
				if dx * dx + dz * dz < PETE_HIT_RADIUS_SQ:
					var hp: int = pete.get_meta("hp", PETE_HP) - 1
					pete.set_meta("hp", hp)
					_spawn_popup_3d(pete.position + Vector3(0, 1.5, 0),
						"-1", Color(1, 0.45, 0.25, 1), 72)
					bullet.queue_free()
					_hits += 1
					_refresh_hud()
					_refresh_pete_hp(pete)
					if hp <= 0:
						pete.queue_free()
						_show_win()
					break
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
				_spawn_popup_3d(obstacle.position + Vector3(0, 1, 0),
					"-1", Color(1, 0.32, 0.22, 1), 56)
				obstacle.queue_free()
				bullet.queue_free()
				_hits += 1
				_refresh_hud()
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
		var st: InputEventScreenTouch = event as InputEventScreenTouch
		# Iter 97: fallback BACK detection — top-left corner tap (matches
		# the BackButton's area + some slop) always triggers exit. Defensive
		# against the iter 96 bug where the BackButton signal somehow
		# wasn't firing on Android. Logs separately so we can tell whether
		# the button itself worked or this fallback kicked in.
		if st.position.x < 260 and st.position.y < 140:
			DebugLog.add("level_3d: top-left fallback tap → back")
			_on_back_pressed()
			return
		sx = st.position.x
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

# Iter 73/88: per-position bullet spawner — bullet visual + size now
# depends on _fire_mode set by iter 88 bonus pickups.
func _spawn_bullet_at(world_x: float, world_z: float) -> void:
	var bullet := CSGSphere3D.new()
	var mat := StandardMaterial3D.new()
	match _fire_mode:
		FireMode.RIFLE:
			# Bigger, faster, brown rifle round
			bullet.radius = BULLET_PIXEL_SIZE * 1.4
			mat.albedo_color = Color(0.75, 0.55, 0.25, 1)
		FireMode.FROSTBITE:
			# Cyan icy bullet
			bullet.radius = BULLET_PIXEL_SIZE * 1.1
			mat.albedo_color = Color(0.55, 0.85, 1.00, 1)
		FireMode.FRENZY:
			# Bright pink frenzy
			bullet.radius = BULLET_PIXEL_SIZE
			mat.albedo_color = Color(1.00, 0.45, 0.85, 1)
		_:  # CANDY (default)
			bullet.radius = BULLET_PIXEL_SIZE
			mat.albedo_color = CANDY_BULLET_COLORS[_rng.randi() % CANDY_BULLET_COLORS.size()]
	bullet.radial_segments = 12
	bullet.rings = 8
	mat.emission_enabled = true
	mat.emission = mat.albedo_color * 0.5
	bullet.material = mat
	bullet.position = Vector3(world_x, BULLET_SPAWN_Y, world_z - 0.5)
	bullets_root.add_child(bullet)

func _on_back_pressed() -> void:
	AudioBus.play_tap()
	get_tree().change_scene_to_file("res://scenes/debug_menu.tscn")

# Iter 77: retry button on the WIN modal reloads the level_3d scene.
func _on_retry_pressed() -> void:
	AudioBus.play_tap()
	get_tree().reload_current_scene()
