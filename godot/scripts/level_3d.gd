extends Node2D

# ============================================================================
# Iter 98: SCRIPT-ATTACH DIAGNOSIS
# ============================================================================
# Iter 97 confirmed: terrain renders (terrain_3d.gd works), but neither
# _ready NOR _input on this script ever fire on Android. The info_label
# stayed at the .tscn default, the BackButton signal was never wired,
# and the top-left-tap fallback in _input ALSO never triggered.
#
# This is the smoking gun: either (a) the script never attaches at
# runtime, or (b) it parses but Godot's Android runtime suppresses all
# lifecycle callbacks. CI export succeeds + the script appears in the
# .tscn — but Android runtime acts as if Level3D is a plain Node2D.
#
# Three callbacks below — _init, _enter_tree, _ready — each log via
# DebugLog (an autoload, always in tree). If ANY land in the disk log
# after opening 3D PREVIEW, the script attached and we know WHICH
# callback got suppressed. If NONE land, the script never attached and
# the bug is in the .tscn / asset pipeline.
# ============================================================================

func _init() -> void:
	# _init runs at allocation, before this node enters the tree. DebugLog
	# is already in the tree (autoload), so it can be called from here.
	# This is the EARLIEST possible breadcrumb from this script.
	DebugLog.add("level_3d.gd _init — script IS attached")

func _enter_tree() -> void:
	DebugLog.add("level_3d.gd _enter_tree")

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
# Iter 99: moved up from mid-file (was between _ready and
# _build_3d_content). The mid-file `const := preload(...)` after func
# definitions appears to fail at Godot Android runtime — the script
# attaches at CI export time but Android refuses to instantiate it,
# which means _init, _enter_tree, _ready, _input ALL silently never
# run (verified by iter 98's null-instrumentation result). Module
# consts should all live at the top of the file, before any function.
const COWBOY_TEXTURE_LVL3D: Texture2D = preload("res://assets/sprites/posse_idle_00.png")

# 3D world bounds. The dirt PlaneMesh in terrain_3d_3d_prototype is
# 40 wide × 60 deep, centered at origin. Cowboy lane = x in [-18, 18].
const COWBOY_X_BOUND: float = 6.0  # iter 108: 18.0 → 6.0 — was off the road
# Iter 106: cowboy z moved 1.5 → -3.0 because the previous value put
# the cowboy below the camera frustum. Camera is at (0, 3, 2) tilted
# -30° around X. Its look-ray (forward direction (0, -0.5, -0.866))
# from y=3 hits ground (y=0) at world position (0, 0, -3.2). For the
# cowboy to be visible on-screen at ground level (y≈0.45), it has to
# be near that intersection point. At z=1.5 the cowboy was 2.55 world
# units BELOW the visible field at that depth — exactly the symptom
# the user reported on iter 105 sideload ("cowboy not visible, nothing
# is tracking left/right" → the lerp was working but the sprite was
# below the screen so the visual tracking was invisible).
const COWBOY_Z: float = -3.0
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
const BULLET_PIXEL_SIZE: float = 0.18  # CSGSphere3D radius — iter 107: 0.5 → 0.18 (jelly-bean sized, was nearly cowboy-sized)
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
# Iter 111: scrolling roadside scenery — fence posts, rocks, cacti,
# distant building silhouettes. Spawn periodically off-road and scroll
# toward camera at OBSTACLE_SPEED so the world feels lived-in rather
# than a flat dirt plane.
var scenery_root: Node3D

var _spawn_timer: float = 0.0
var _fire_timer: float = 0.0
var _hits: int = 0
var _rng := RandomNumberGenerator.new()

# Iter 75: gate spawn parameters. Gates are 2 colored door quads
# straddling the lane center, math values painted on as Label3D.
# Posse count starts at STARTING_POSSE (5) and modifies as cowboy
# walks through gates.
const GATE_SPAWN_INTERVAL: float = 4.5
const GATE_WIDTH: float = 4.0       # iter 107: 8.0 → 4.0 (each door is 2.0 wide)
const GATE_HEIGHT: float = 1.35     # iter 108: 2.5 → 1.35 = 1.5× cowboy height (~0.89)
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
const PETE_SPAWN_DELAY: float = 12.0  # iter 110: 25 → 12 so testers don't have to wait
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

# Iter 111: scenery parameters. Spawn roadside props (fence posts,
# rocks, cacti, distant building silhouettes) at SCENERY_SPAWN_INTERVAL
# and let them scroll toward the camera. Range slightly wider than the
# road bounds so the props sit alongside the dirt strip, not on it.
const SCENERY_SPAWN_INTERVAL: float = 0.6  # one item every ~0.6s
const SCENERY_ROAD_SHOULDER: float = 7.5    # x distance from road center
const SCENERY_FAR_BAND: float = 14.0       # distant scenery (buildings, mountains-near)
var _scenery_spawn_timer: float = 0.0

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
const COWBOY_LERP_SPEED: float = 2.5  # iter 108: 4.0 → 2.5 (still felt twitchy)

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
	# Iter 110: randomize so bullet colors / lane choices / etc. don't
	# repeat the same sequence every preview session. The deterministic
	# seed (6464) was only useful for early reproduction; now we want
	# variety across runs.
	_rng.randomize()
	# Iter 96: terrain_3d.gd (attached to the Terrain3D instance) now
	# does its own subviewport→sprite binding in its _ready, so the
	# manual binding from iter 69 is no longer needed. Keeping a
	# breadcrumb so the log still shows the binding step succeeded.
	if subviewport != null:
		DebugLog.add("level_3d: terrain instance loaded; subviewport=%s" % subviewport.size)
	else:
		DebugLog.add("WARN level_3d: subviewport null after terrain instance")
	# Iter 107: override the terrain_3d.tscn instance's camera to a
	# steeper Evony-style top-down angle. We override in script (not
	# in terrain_3d.tscn) because terrain_3d.tscn is also instanced
	# by the gameplay level.tscn, where the existing 30° angle is
	# baked into the 2D-sprite placement. When the 3D refactor
	# replaces level.tscn, this override can move into terrain_3d.tscn
	# directly. Until then, level_3d gets the new angle in isolation.
	if camera != null:
		camera.position = Vector3(0, 7.0, 3.0)
		camera.rotation_degrees = Vector3(-55, 0, 0)
		DebugLog.add("level_3d: camera overridden (Evony top-down: y=7 z=3 pitch=-55°)")
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
# (Iter 99: COWBOY_TEXTURE_LVL3D moved to top of file with other consts —
# Godot Android refused to load the script when it lived mid-file.)

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
	scenery_root = _make_lvl3d_container("Scenery")
	DebugLog.add("level_3d: 8 containers added to subviewport")
	# 2) Cowboy3D Sprite3D billboard.
	cowboy_3d = Sprite3D.new()
	cowboy_3d.name = "Cowboy3D"
	cowboy_3d.texture = COWBOY_TEXTURE_LVL3D
	cowboy_3d.pixel_size = 0.002
	cowboy_3d.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	# Iter 100 (fix 8): SpriteBase3D.ALPHA_CUT_DISCARD parse-fails on
	# Godot 4.6.1 Android runtime even though it's valid on Linux export.
	# Use the int literal (1) directly with a comment for the human reader.
	# (Same enum value as SpriteBase3D.AlphaCutMode.ALPHA_CUT_DISCARD.)
	cowboy_3d.alpha_cut = 1  # ALPHA_CUT_DISCARD
	# Iter 106: use COWBOY_Z constant (= -3.0) so this stays in sync if
	# the camera angle ever changes again. Previous hardcoded 1.5 was
	# below the camera frustum.
	cowboy_3d.position = Vector3(0, 0.45, COWBOY_Z)
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
		# Iter 100 (fix 8): SpriteBase3D.BILLBOARD_ENABLED + ALPHA_CUT_DISCARD
		# parse-fail at Godot 4.6.1 Android runtime — the script silently
		# fails to attach (caught by smoke-test run 25903646479). Use int
		# literals with comments — they're stable across Godot versions
		# and the parser doesn't need to resolve the enum name.
		f.billboard = 1  # BillboardMode.BILLBOARD_ENABLED
		f.alpha_cut = 1  # AlphaCutMode.ALPHA_CUT_DISCARD
		f.position = Vector3(offset.x, 0.45, COWBOY_Z + offset.z)
		f.set_meta("formation_offset", offset)
		subviewport.add_child(f)
		_followers.append(f)

# Iter 111: spawn a single roadside scenery item. Weighted pick from
# 5 categories so the world feels lived-in but not chaotic. Each item
# is a simple CSG primitive — billboard sprites + textured models can
# replace these in later iters once the spawn/scroll loop is stable.
#
# Categories:
#   FENCE     — short wooden post on the road shoulder
#   ROCK      — small grey boulder, scattered just past the shoulder
#   CACTUS    — tall green column further out
#   SCRUB     — low brown sphere (sagebrush), far side
#   BUILDING  — flat-front "building façade" silhouette at FAR_BAND
enum SceneryType { FENCE, ROCK, CACTUS, SCRUB, BUILDING }
const SCENERY_WEIGHTS: Array[int] = [
	4,  # FENCE
	3,  # ROCK
	2,  # CACTUS
	2,  # SCRUB
	1,  # BUILDING (rarest — large, distinctive)
]

func _spawn_scenery_item() -> void:
	# Pick category via cumulative weight.
	var total: int = 0
	for w in SCENERY_WEIGHTS:
		total += w
	var roll: int = _rng.randi_range(0, total - 1)
	var cum: int = 0
	var pick: int = SceneryType.FENCE
	for i in range(SCENERY_WEIGHTS.size()):
		cum += SCENERY_WEIGHTS[i]
		if roll < cum:
			pick = i
			break
	# Side: random ±1 left/right of road.
	var side: float = 1.0 if _rng.randf() < 0.5 else -1.0
	var spawn_z: float = OBSTACLE_SPAWN_Z + _rng.randf_range(-3.0, 3.0)
	match pick:
		SceneryType.FENCE:
			_spawn_fence_post(side, spawn_z)
		SceneryType.ROCK:
			_spawn_rock(side, spawn_z)
		SceneryType.CACTUS:
			_spawn_cactus_scenery(side, spawn_z)
		SceneryType.SCRUB:
			_spawn_scrub(side, spawn_z)
		SceneryType.BUILDING:
			_spawn_building(side, spawn_z)

func _spawn_fence_post(side: float, z: float) -> void:
	# Iter 112: two posts + a connecting horizontal rail. Reads as a
	# fence section instead of two unrelated sticks. Slight per-post
	# height variance gives a hand-built look.
	var post_xs: Array[float] = [
		side * (SCENERY_ROAD_SHOULDER + _rng.randf_range(-0.2, 0.2)),
		side * (SCENERY_ROAD_SHOULDER + _rng.randf_range(-0.2, 0.2)),
	]
	var heights: Array[float] = [
		_rng.randf_range(0.80, 1.00),
		_rng.randf_range(0.80, 1.00),
	]
	var wood_mat := StandardMaterial3D.new()
	wood_mat.albedo_color = Color(
		_rng.randf_range(0.42, 0.54),
		_rng.randf_range(0.28, 0.36),
		_rng.randf_range(0.14, 0.20),
		1,
	)
	for i in range(2):
		var post := CSGCylinder3D.new()
		post.radius = 0.06
		post.height = heights[i]
		post.material = wood_mat
		post.position = Vector3(post_xs[i], heights[i] * 0.5, z + float(i) * 0.8)
		scenery_root.add_child(post)
	# Horizontal rail connecting the two posts at ~70% post height.
	var rail := CSGBox3D.new()
	rail.size = Vector3(0.08, 0.10, 0.8)
	rail.material = wood_mat
	var rail_y: float = mini(heights[0], heights[1]) * 0.65
	rail.position = Vector3((post_xs[0] + post_xs[1]) * 0.5, rail_y, z + 0.4)
	scenery_root.add_child(rail)

func _spawn_rock(side: float, z: float) -> void:
	# Iter 112: per-rock color jitter + random Y rotation breaks up the
	# repetitive look. Asymmetric x/z scale makes rocks look like rocks
	# instead of squashed marbles.
	var rock := CSGSphere3D.new()
	rock.radius = _rng.randf_range(0.25, 0.7)
	rock.radial_segments = 6
	rock.rings = 4
	var mat := StandardMaterial3D.new()
	var base_grey: float = _rng.randf_range(0.38, 0.52)
	mat.albedo_color = Color(
		base_grey + _rng.randf_range(-0.03, 0.06),  # slight warm/cool variance
		base_grey,
		base_grey - _rng.randf_range(0.0, 0.05),
		1,
	)
	mat.roughness = 1.0
	rock.material = mat
	rock.scale = Vector3(
		_rng.randf_range(0.9, 1.3),
		_rng.randf_range(0.45, 0.85),
		_rng.randf_range(0.85, 1.35),
	)
	rock.rotation_degrees = Vector3(0, _rng.randf_range(0, 360), 0)
	rock.position = Vector3(
		side * (SCENERY_ROAD_SHOULDER + _rng.randf_range(0.3, 2.5)),
		rock.radius * 0.45,
		z,
	)
	scenery_root.add_child(rock)

func _spawn_cactus_scenery(side: float, z: float) -> void:
	# Iter 112: three cactus variants. Saguaro (tall + arms), barrel
	# cactus (squat round), prickly pear (stacked flat ovals). All share
	# the same green palette but their silhouettes are distinct enough
	# that a viewer reads variety along the road.
	var cactus := Node3D.new()
	var green := Color(
		_rng.randf_range(0.22, 0.32),
		_rng.randf_range(0.38, 0.48),
		_rng.randf_range(0.18, 0.26),
		1,
	)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = green
	mat.roughness = 0.85
	var variant: int = _rng.randi() % 3
	if variant == 0:
		# Saguaro
		var trunk := CSGCylinder3D.new()
		trunk.radius = 0.18
		trunk.height = _rng.randf_range(1.4, 2.4)
		trunk.material = mat
		trunk.position = Vector3(0, trunk.height * 0.5, 0)
		cactus.add_child(trunk)
		# Random number of arms (0-2)
		var arm_count: int = _rng.randi_range(0, 2)
		for i in range(arm_count):
			var arm := CSGCylinder3D.new()
			arm.radius = 0.12
			arm.height = _rng.randf_range(0.5, 0.8)
			arm.material = mat
			var arm_side: float = 1.0 if i == 0 else -1.0
			arm.position = Vector3(arm_side * 0.22, trunk.height * _rng.randf_range(0.55, 0.80), 0)
			arm.rotation_degrees = Vector3(0, 0, -arm_side * 65)
			cactus.add_child(arm)
	elif variant == 1:
		# Barrel cactus — wide squat sphere
		var barrel := CSGSphere3D.new()
		barrel.radius = _rng.randf_range(0.35, 0.55)
		barrel.radial_segments = 8
		barrel.rings = 6
		barrel.material = mat
		barrel.scale = Vector3(1.0, _rng.randf_range(1.1, 1.5), 1.0)
		barrel.position = Vector3(0, barrel.radius * 0.7, 0)
		cactus.add_child(barrel)
	else:
		# Prickly pear — 3-5 flattened pads stacked at slight angles
		var pad_count: int = _rng.randi_range(3, 5)
		for i in range(pad_count):
			var pad := CSGSphere3D.new()
			pad.radius = _rng.randf_range(0.18, 0.28)
			pad.radial_segments = 6
			pad.rings = 4
			pad.material = mat
			pad.scale = Vector3(1.0, 1.4, 0.35)
			pad.rotation_degrees = Vector3(0, _rng.randf_range(0, 70), _rng.randf_range(-30, 30))
			pad.position = Vector3(
				_rng.randf_range(-0.10, 0.10),
				pad.radius * 0.8 + float(i) * 0.25,
				_rng.randf_range(-0.08, 0.08),
			)
			cactus.add_child(pad)
	cactus.position = Vector3(
		side * (SCENERY_ROAD_SHOULDER + _rng.randf_range(1.0, 4.0)),
		0,
		z,
	)
	scenery_root.add_child(cactus)

func _spawn_scrub(side: float, z: float) -> void:
	# Sagebrush — low matted sphere flattened on y.
	var scrub := CSGSphere3D.new()
	scrub.radius = _rng.randf_range(0.35, 0.55)
	scrub.radial_segments = 6
	scrub.rings = 4
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.50, 0.32, 1)  # dry sage-brown
	scrub.material = mat
	scrub.scale = Vector3(1.2, 0.35, 1.2)
	scrub.position = Vector3(
		side * (SCENERY_ROAD_SHOULDER + _rng.randf_range(0.5, 5.0)),
		0.15,
		z,
	)
	scenery_root.add_child(scrub)

const _BUILDING_SIGNS := ["SALOON", "BANK", "JAIL", "GEN. STORE", "STABLES", "HOTEL", "BARBER", "POST"]

func _spawn_building(side: float, z: float) -> void:
	# Iter 112: full false-front Western building. Tall + narrow body,
	# raised false-front gable, awning overhang, window/door indents.
	# Each instance varies in color + which sign. Spawn a 50% chance of
	# adjacent neighbors at ±8 z so buildings cluster into a street.
	_spawn_building_one(side, z)
	# Cluster: maybe add 1-2 more buildings on the same side, offset z.
	if _rng.randf() < 0.55:
		_spawn_building_one(side, z + 8.0)
	if _rng.randf() < 0.35:
		_spawn_building_one(side, z - 8.0)

func _spawn_building_one(side: float, z: float) -> void:
	var building := Node3D.new()
	# Body: tall + narrow (4.5w × 4.5h × 2.5d) — Western false-front
	# style, much more vertical than the iter 111 cube.
	var body := CSGBox3D.new()
	body.size = Vector3(_rng.randf_range(4.0, 5.0), 4.5, _rng.randf_range(2.2, 2.8))
	var body_mat := StandardMaterial3D.new()
	# Color palette: weathered wood OR adobe tan OR pale whitewash.
	# Slight per-instance jitter inside each palette.
	var palette: int = _rng.randi() % 3
	if palette == 0:  # weathered wood (greys + browns)
		body_mat.albedo_color = Color(
			_rng.randf_range(0.45, 0.58),
			_rng.randf_range(0.32, 0.42),
			_rng.randf_range(0.22, 0.30),
			1,
		)
	elif palette == 1:  # adobe tan
		body_mat.albedo_color = Color(
			_rng.randf_range(0.60, 0.72),
			_rng.randf_range(0.46, 0.55),
			_rng.randf_range(0.30, 0.38),
			1,
		)
	else:  # pale whitewash
		body_mat.albedo_color = Color(
			_rng.randf_range(0.78, 0.88),
			_rng.randf_range(0.74, 0.84),
			_rng.randf_range(0.62, 0.72),
			1,
		)
	body_mat.roughness = 0.95
	body.material = body_mat
	body.position = Vector3(0, body.size.y * 0.5, 0)
	building.add_child(body)
	# False-front gable: wider + taller rectangle on top of body
	# extending only on the front face direction.
	var gable := CSGBox3D.new()
	gable.size = Vector3(body.size.x + 0.3, 1.2, 0.4)
	var gable_mat := StandardMaterial3D.new()
	gable_mat.albedo_color = body_mat.albedo_color.darkened(0.15)
	gable_mat.roughness = 0.95
	gable.material = gable_mat
	# Front face is +z direction.
	gable.position = Vector3(0, body.size.y + 0.5, body.size.z * 0.5 + 0.15)
	building.add_child(gable)
	# Awning: thin horizontal box jutting out from the front, at ~door height.
	var awning := CSGBox3D.new()
	awning.size = Vector3(body.size.x + 0.6, 0.10, 1.0)
	var awning_mat := StandardMaterial3D.new()
	awning_mat.albedo_color = Color(0.30, 0.20, 0.13, 1)  # darker than body
	awning_mat.roughness = 0.95
	awning.material = awning_mat
	awning.position = Vector3(0, 2.4, body.size.z * 0.5 + 0.45)
	building.add_child(awning)
	# Awning support posts (2): thin cylinders from awning down to ground.
	for awn_side in [-1.0, 1.0]:
		var post := CSGCylinder3D.new()
		post.radius = 0.06
		post.height = 2.4
		post.material = awning_mat
		post.position = Vector3(awn_side * (body.size.x * 0.4), 1.2, body.size.z * 0.5 + 0.95)
		building.add_child(post)
	# Door indent: dark CSGBox slightly recessed into the front face.
	var door := CSGBox3D.new()
	door.size = Vector3(0.7, 1.5, 0.1)
	var dark_mat := StandardMaterial3D.new()
	dark_mat.albedo_color = Color(0.08, 0.06, 0.04, 1)
	dark_mat.roughness = 0.7
	door.material = dark_mat
	door.position = Vector3(0, 0.75, body.size.z * 0.5 + 0.05)
	building.add_child(door)
	# Windows: 2 dark indents on either side of the door, plus 2 above.
	for win_x in [-1.0, 1.0]:
		var w := CSGBox3D.new()
		w.size = Vector3(0.55, 0.65, 0.06)
		w.material = dark_mat
		w.position = Vector3(win_x * (body.size.x * 0.30), 1.4, body.size.z * 0.5 + 0.04)
		building.add_child(w)
		var w2 := CSGBox3D.new()
		w2.size = Vector3(0.55, 0.65, 0.06)
		w2.material = dark_mat
		w2.position = Vector3(win_x * (body.size.x * 0.30), 3.2, body.size.z * 0.5 + 0.04)
		building.add_child(w2)
	# Sign label on the false-front gable.
	var sign := Label3D.new()
	sign.text = _BUILDING_SIGNS[_rng.randi() % _BUILDING_SIGNS.size()]
	sign.font_size = 56
	sign.outline_size = 8
	sign.modulate = Color(0.95, 0.85, 0.55, 1)
	sign.billboard = 0  # NOT camera-billboard — face the road shoulder
	# Orient sign face toward the road (negative-side buildings face +x,
	# positive-side face -x). Side comes from the function arg.
	sign.rotation_degrees = Vector3(0, 0 if side > 0 else 180, 0)
	# Position: just in front of the gable, on the road-facing side.
	sign.position = Vector3(0, body.size.y + 0.55, body.size.z * 0.5 + 0.36)
	building.add_child(sign)
	building.position = Vector3(
		side * (SCENERY_FAR_BAND + _rng.randf_range(-1.0, 1.5)),
		0,
		z,
	)
	# Buildings on the LEFT side of the road should face the road too
	# (rotate 180° so their front-face points to +x rather than -x).
	if side < 0:
		building.rotation_degrees = Vector3(0, 180, 0)
	scenery_root.add_child(building)

# Iter 110: bullet-vs-gate collision. Returns true if the bullet hit
# a not-yet-triggered gate door, in which case the caller queue_frees
# the bullet. Decrements the hit door's value toward zero (or degrades
# a multiplier toward additive zero), updates the Label3D + door tint.
const GATE_BULLET_Z_RANGE: float = 0.5
const GATE_BULLET_X_HALF: float = 2.0  # half door width (= GATE_WIDTH * 0.5 * 0.5 = 1.0)

func _check_bullet_gate_collision(bullet: Node3D) -> bool:
	for gate_node in gates_root.get_children():
		if not (gate_node is Node3D):
			continue
		var gate: Node3D = gate_node
		if gate.get_meta("triggered", false):
			continue
		if absf(bullet.position.z - gate.position.z) > GATE_BULLET_Z_RANGE:
			continue
		# Which door? Bullet x relative to gate center.
		var side: String = "left" if bullet.position.x < gate.position.x else "right"
		var door: Node = gate.get_meta(side + "_door")
		if door == null or not is_instance_valid(door):
			continue
		# Confirm bullet is actually within door width (avoid hitting the
		# unfilled middle gap that doesn't have a door behind it).
		var door_center_x: float = gate.position.x + (-1.0 if side == "left" else 1.0) * (GATE_WIDTH * 0.25)
		if absf(bullet.position.x - door_center_x) > GATE_BULLET_X_HALF:
			continue
		# Decrement the door's value toward 0.
		var value: int = gate.get_meta(side + "_value", 0)
		var op: String = gate.get_meta(side + "_op", "+")
		if op == "×":
			# Degrade multiplier toward 2, then collapse to additive 0.
			value = maxi(value - 1, 1)
			if value < 2:
				op = "+"
				value = 0
		elif value > 0:
			value -= 1
		elif value < 0:
			value += 1
		# Persist + update visuals.
		gate.set_meta(side + "_value", value)
		gate.set_meta(side + "_op", op)
		var lbl: Label3D = gate.get_meta(side + "_label")
		if lbl != null and is_instance_valid(lbl):
			lbl.text = "%s%d" % [op, value]
		if door is CSGBox3D and (door as CSGBox3D).material is StandardMaterial3D:
			(((door as CSGBox3D).material) as StandardMaterial3D).albedo_color = _gate_color_for(value, op)
		# Hit-popup at impact point
		_spawn_popup_3d(bullet.position + Vector3(0, 0.5, 0),
			"%s%d" % [op, value], Color(1.0, 0.92, 0.3, 1), 40)
		return true
	return false

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
	gate.set_meta("left_door", left_door)  # iter 110: bullets find door via meta
	# Right door
	var right_door := CSGBox3D.new()
	right_door.size = Vector3(GATE_WIDTH * 0.5, GATE_HEIGHT, 0.15)
	right_door.position = Vector3(GATE_WIDTH * 0.25, 0, 0)
	var rmat := StandardMaterial3D.new()
	rmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rmat.albedo_color = _gate_color_for(values[1], operators[1])
	right_door.material = rmat
	gate.add_child(right_door)
	gate.set_meta("right_door", right_door)
	# Math value labels (Label3D billboards above each door)
	var llabel := Label3D.new()
	llabel.text = "%s%d" % [operators[0], values[0]]
	llabel.position = Vector3(-GATE_WIDTH * 0.25, GATE_HEIGHT * 0.55, 0)
	llabel.font_size = 96
	llabel.outline_size = 12
	llabel.modulate = Color.WHITE
	gate.add_child(llabel)
	gate.set_meta("left_label", llabel)  # iter 110: bullets update label text via meta
	var rlabel := Label3D.new()
	rlabel.text = "%s%d" % [operators[1], values[1]]
	rlabel.position = Vector3(GATE_WIDTH * 0.25, GATE_HEIGHT * 0.55, 0)
	rlabel.font_size = 96
	rlabel.outline_size = 12
	rlabel.modulate = Color.WHITE
	gate.add_child(rlabel)
	gate.set_meta("right_label", rlabel)
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
	# Iter 110: sync visible posse Sprite3Ds to the new count so the
	# screen actually shows the change instead of just the HUD number.
	_sync_followers_to_count(_posse_count_3d)
	# Iter 110: disintegrate the gate instead of letting it slide past.
	# Scale-collapse + queue_free so the player feels the contact.
	var tween := create_tween()
	tween.tween_property(gate, "scale", Vector3(0.01, 0.01, 0.01), 0.25) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_callback(gate.queue_free)

# Iter 110: keep the visible posse Sprite3Ds in sync with _posse_count_3d.
# Called from gate-trigger and bullet-damage paths. Adds followers up to
# the new count (minus 1 for the leader cowboy_3d), trims excess from
# the tail. Cap at MAX_VISIBLE_FOLLOWERS so a ×4 gate doesn't spawn 100
# Sprite3Ds and tank the framerate.
const MAX_VISIBLE_FOLLOWERS: int = 24

func _sync_followers_to_count(target: int) -> void:
	var want: int = clampi(target - 1, 0, MAX_VISIBLE_FOLLOWERS)
	# Trim excess from tail.
	while _followers.size() > want:
		var f: Sprite3D = _followers.pop_back()
		if is_instance_valid(f):
			f.queue_free()
	# Grow up to want — clone leader sprite, place at trapezoid offset
	# computed from index.
	if cowboy_3d == null or not is_instance_valid(cowboy_3d):
		return
	while _followers.size() < want:
		var idx: int = _followers.size()
		var f := Sprite3D.new()
		f.texture = cowboy_3d.texture
		f.pixel_size = cowboy_3d.pixel_size
		f.billboard = 1
		f.alpha_cut = 1
		var offset: Vector3 = (POSSE_FORMATION_OFFSETS[idx % POSSE_FORMATION_OFFSETS.size()]
			if POSSE_FORMATION_OFFSETS.size() > 0
			else Vector3(0, 0, 0.6 + 0.2 * float(idx)))
		# Extra rows: scale offset.z by (1 + idx / OFFSETS.size())
		var row_mul: float = 1.0 + floorf(float(idx) / float(POSSE_FORMATION_OFFSETS.size()))
		f.position = Vector3(offset.x, 0.45, COWBOY_Z + offset.z * row_mul)
		f.set_meta("formation_offset", Vector3(offset.x, 0.0, offset.z * row_mul))
		subviewport.add_child(f)
		_followers.append(f)

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
const PETE_IDLE_STREAM := preload("res://assets/videos/pete/taps_foot_idle.ogv")

func _spawn_pete() -> void:
	# Iter 109: video-driven billboard using pete/taps_foot_idle.ogv +
	# chromakey shader (matches the 2D gameplay outlaw.tscn pattern).
	# State-machine swapping between Pete's other 8 streams (FORWARD,
	# STRAFE, SHOOT, HIT, DEATH, CELEBRATE, SHOUTS, COMPLAINS) is a
	# follow-up — for now IDLE on loop while we verify the billboard
	# pipeline works at all on Android.
	var pete := Node3D.new()
	pete.position = Vector3(0.0, 2.1, OBSTACLE_SPAWN_Z + 4.0)
	pete.set_meta("hp", PETE_HP)
	boss_root.add_child(pete)
	var billboard: Node3D = _make_video_billboard(PETE_IDLE_STREAM, 4.2)
	pete.add_child(billboard)
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
const VAGRANT_IDLE_STREAM := preload("res://assets/videos/vagrant/idle_wobble.ogv")

func _spawn_outlaw() -> void:
	# Iter 109: video-driven billboard using vagrant/idle_wobble.ogv +
	# chromakey shader. Was vagrant.png (iter 108) which was just the
	# static fallback the user had asked us not to use.
	var outlaw := Node3D.new()
	var lane_x: float = _rng.randf_range(-COWBOY_X_BOUND * 0.75,
		COWBOY_X_BOUND * 0.75)
	outlaw.position = Vector3(lane_x, 1.0, OBSTACLE_SPAWN_Z + 4.0)
	outlaw.set_meta("hp", OUTLAW_HP)
	outlaw.set_meta("fire_timer", _rng.randf() * OUTLAW_FIRE_INTERVAL)
	outlaws_root.add_child(outlaw)
	var billboard: Node3D = _make_video_billboard(VAGRANT_IDLE_STREAM, 2.5)  # iter 110: 2.0 → 2.5 (+25%)
	outlaw.add_child(billboard)

# Iter 109: helper for video-driven 3D billboards. Pattern:
#   wrapper Node3D
#     ├── SubViewport (offscreen render, transparent_bg, 3D disabled)
#     │     └── VideoStreamPlayer (the .ogv with chromakey shader)
#     └── Sprite3D (billboard, texture = SubViewport.get_texture())
#
# world_height: how tall the sprite should be in world units. The
#   pixel_size derives from the SubViewport's pixel height.
# viewport_px: SubViewport resolution. Higher = sharper but more GPU.
#   150×270 ≈ 40K pixels per billboard, fine for a few enemies; bump
#   down if many simultaneous outlaws cause perf issues on mobile.
const _CHROMAKEY_SHADER := preload("res://shaders/chromakey.gdshader")

func _make_video_billboard(
	stream: VideoStream,
	world_height: float,
	viewport_px: Vector2i = Vector2i(150, 270),
) -> Node3D:
	var wrap := Node3D.new()
	var sv := SubViewport.new()
	sv.size = viewport_px
	sv.transparent_bg = true
	sv.disable_3d = true        # this SubViewport renders 2D only
	sv.render_target_update_mode = 4  # SubViewport.UPDATE_ALWAYS — needed for video
	wrap.add_child(sv)
	var vp := VideoStreamPlayer.new()
	vp.stream = stream
	vp.autoplay = true
	vp.loop = true
	vp.expand = true
	vp.size = Vector2(viewport_px)
	var mat := ShaderMaterial.new()
	mat.shader = _CHROMAKEY_SHADER
	mat.set_shader_parameter("chroma_color", Color(0, 1, 0, 1))
	mat.set_shader_parameter("similarity", 0.22)
	mat.set_shader_parameter("blend_amount", 0.10)
	vp.material = mat
	sv.add_child(vp)
	var sprite := Sprite3D.new()
	sprite.texture = sv.get_texture()
	sprite.pixel_size = world_height / float(viewport_px.y)
	sprite.billboard = 1   # BILLBOARD_ENABLED
	sprite.alpha_cut = 0   # ALPHA_CUT_DISABLED — chromakey's smooth edge needs alpha blending, not threshold cut
	wrap.add_child(sprite)
	return wrap

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
		# Iter 110: outlaws slowly track the cowboy's x position so
		# they aren't just sliding straight forward in a single lane.
		outlaw.position.x = lerpf(outlaw.position.x, cowboy_3d.position.x,
			clampf(1.2 * delta, 0.0, 1.0))
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
			# Iter 110: drop a visible follower when posse takes damage.
			_sync_followers_to_count(_posse_count_3d)
		elif ob.position.z > OUTLAW_BULLET_DESPAWN_Z or absf(ob.position.x) > 25.0:
			ob.queue_free()
	# Iter 111: scenery spawn / scroll / despawn. Cheaper than obstacles
	# (no collision checks) so we run it more often for visual density.
	_scenery_spawn_timer -= delta
	if _scenery_spawn_timer <= 0.0:
		_scenery_spawn_timer = SCENERY_SPAWN_INTERVAL
		_spawn_scenery_item()
	for s in scenery_root.get_children():
		if not (s is Node3D):
			continue
		s.position.z += OBSTACLE_SPEED * delta
		if s.position.z > OBSTACLE_DESPAWN_Z + 2.0:
			s.queue_free()
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
		# Iter 110: gate-vs-bullet collision — bullets count down the
		# gate door's value (moving toward 0). For multiplicative gates,
		# degrade the multiplier toward 2 then collapse to additive 0.
		if _check_bullet_gate_collision(bullet):
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
