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
# Iter 115: port the 2D gameplay's reload mechanic. Gun is a Resource
# carrying clip_size / fire_interval / reload_time defaults. GunState
# is the RefCounted per-shooter runtime (one per posse member; for now
# only the cowboy uses one — followers fire on the cowboy's fire event).
const GunScript = preload("res://scripts/gun.gd")
const GunStateScript = preload("res://scripts/gun_state.gd")
# Iter 99: moved up from mid-file (was between _ready and
# _build_3d_content). The mid-file `const := preload(...)` after func
# definitions appears to fail at Godot Android runtime — the script
# attaches at CI export time but Android refuses to instantiate it,
# which means _init, _enter_tree, _ready, _input ALL silently never
# run (verified by iter 98's null-instrumentation result). Module
# consts should all live at the top of the file, before any function.
const COWBOY_TEXTURE_LVL3D: Texture2D = preload("res://assets/sprites/posse_idle_00.png")

# Cowboy animation clips. The leader cowboy + posse followers are video
# billboards driven by these; _set_cowboy_anim() swaps the stream by
# level state. run/strafe/stand clips are back-view (face the outlaws);
# idle/celebrate are front-view.
const COWBOY_RUN_FWD_STREAM := preload("res://assets/videos/cowboy/run_shoot_fwd.ogv")
const COWBOY_RUN_LEFT_STREAM := preload("res://assets/videos/cowboy/run_shoot_left.ogv")
const COWBOY_RUN_RIGHT_STREAM := preload("res://assets/videos/cowboy/run_shoot_right.ogv")
const COWBOY_STRAFE_LEFT_STREAM := preload("res://assets/videos/cowboy/strafe_left.ogv")
const COWBOY_STRAFE_RIGHT_STREAM := preload("res://assets/videos/cowboy/strafe_right.ogv")
const COWBOY_STAND_SHOOT_STREAM := preload("res://assets/videos/cowboy/stand_shoot.ogv")
const COWBOY_IDLE_STREAMS: Array[VideoStream] = [
	preload("res://assets/videos/cowboy/idle_a.ogv"),
	preload("res://assets/videos/cowboy/idle_b.ogv"),
	preload("res://assets/videos/cowboy/idle_c.ogv"),
]
const COWBOY_CELEBRATE_STREAMS: Array[VideoStream] = [
	preload("res://assets/videos/cowboy/celebrate_a.ogv"),
	preload("res://assets/videos/cowboy/celebrate_b.ogv"),
	preload("res://assets/videos/cowboy/celebrate_c.ogv"),
]
# Video billboard render scale for the cowboy + followers (world units
# per texture pixel). Tunable after the first device check.
const COWBOY_PIXEL_SIZE: float = 0.0042

# 3D world bounds. The dirt PlaneMesh in terrain_3d_3d_prototype is
# 40 wide × 60 deep, centered at origin. Cowboy lane = x in [-18, 18].
const COWBOY_X_BOUND: float = 3.0  # iter 118: 6.0 → 3.0 to match the actual visible road width
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
const COWBOY_Z: float = 1.5  # iter 145: 0.0 → 1.5 (was middle of screen, user wants near bottom)
const OBSTACLE_SPAWN_Z: float = -28.0  # far end of plane
const OBSTACLE_DESPAWN_Z: float = 3.5   # past the cowboy
const OBSTACLE_SPEED: float = 2.5    # iter 144: 8→5→0.5 → iter 153: 0.5→2.5 (0.5 was non-functional — gates took ~56s to arrive while Pete spawned at 18s; 2.5 is ~31% of the original, slow but playable)
const OBSTACLE_SPAWN_INTERVAL: float = 1.2

# Iter 66: 3D bullets — small bright spheres that travel from cowboy
# along -z axis (away from camera toward the far end of the plane).
# Auto-fire at FIRE_INTERVAL while game is active. Collision: simple
# distance-squared check between each bullet and each obstacle.
const BULLET_SPEED: float = 28.0  # world units per second
const BULLET_FIRE_INTERVAL: float = 0.20
const BULLET_DESPAWN_Z: float = -10.0  # iter 118: -32 → -10 (was reaching off-screen outlaws before they appeared)
const BULLET_COLLISION_DIST_SQ: float = 1.5 * 1.5  # 1.5 world unit radius
const BULLET_PIXEL_SIZE: float = 0.18  # CSGSphere3D radius — iter 107: 0.5 → 0.18 (jelly-bean sized, was nearly cowboy-sized)
const BULLET_SPAWN_Y: float = 1.2  # waist-high at cowboy

@onready var terrain_3d_node: Node = $Terrain3D
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
# Iter 115: GunState owns ammo + reload state for the cowboy.
var _gun: Resource
var _gun_state: RefCounted
# Iter 118: level state machine.
#   COUNTDOWN  — 3-2-1-GO countdown, no scrolling, no firing
#   PLAYING    — normal play: scenery/outlaws scroll, cowboy fires
#   BOSS       — Pete is alive: cowboy fires + bullets travel, but
#                obstacles/scenery/outlaws stop scrolling so the duel
#                stays focused on Pete
#   FINISHED   — Pete defeated or posse=0: motion stops, modal up
enum LevelState { COUNTDOWN, PLAYING, BOSS, FINISHED }
var _level_state: int = LevelState.COUNTDOWN
const COUNTDOWN_TOTAL: float = 3.5  # 3, 2, 1, GO! across this window
var _countdown_remaining: float = COUNTDOWN_TOTAL
var _hits: int = 0
var _rng := RandomNumberGenerator.new()

# Iter 75: gate spawn parameters. Gates are 2 colored door quads
# straddling the lane center, math values painted on as Label3D.
# Posse count starts at STARTING_POSSE (5) and modifies as cowboy
# walks through gates.
const GATE_SPAWN_INTERVAL: float = 3.0  # iter 145: 4.5 → 3.0 (more gates per second with slower terrain)
const GATE_WIDTH: float = 4.0       # iter 107: 8.0 → 4.0 (each door is 2.0 wide)
const GATE_HEIGHT: float = 1.35     # iter 108: 2.5 → 1.35 = 1.5× cowboy height (~0.89)
const GATE_TRIGGER_Z: float = 0.5   # gates fire when their z passes this
var _gate_spawn_timer: float = 0.0
var _posse_count_3d: int = 5
const STARTING_POSSE_3D: int = 1  # iter 118: 5 → 1 (gates grow it from there)

# Iter 76: outlaw enemies. Spawn red boxes periodically at far z that
# scroll toward camera + fire red bullets at the cowboy.
const OUTLAW_SPAWN_INTERVAL: float = 0.5  # iter 118: 3.0 → 0.5 (~14 alive at once)
const OUTLAW_SPEED: float = 2.5  # iter 153: matched to OBSTACLE_SPEED so outlaws drift in with the world (not rushing) and actually reach the player before Pete
const OUTLAW_FIRE_INTERVAL: float = 3.6  # iter 121: 1.8 → 3.6 (halved fire rate)
# Iter 121: only fire when within this many world units of cowboy z.
# Halves the effective bullet range since outlaws spawn at z=-24 but
# only start shooting when z > cowboy.z - OUTLAW_FIRE_RANGE_Z. Gives
# player visible reaction time before bullets start coming.
const OUTLAW_FIRE_RANGE_Z: float = 10.0
const OUTLAW_BULLET_SPEED: float = 8.0  # iter 121: 14 → 8 (dodgeable — was too fast to react to)
const OUTLAW_BULLET_RADIUS: float = 0.12  # iter 136: 0.15→0.25 → iter 151: 0.25→0.12 (user: "bullets almost the size of a vagrant")
const OUTLAW_BULLET_DESPAWN_Z: float = 4.0
const OUTLAW_BULLET_HIT_X: float = 0.5  # iter 119: bullet only hits if within this x of any posse member
const OUTLAW_HIT_RADIUS_SQ: float = 1.5 * 1.5
const OUTLAW_HP: int = 10  # iter 118: 3 → 10 (1 cowboy firing 6/clip+1s reload = ~3.5 bullets/sec, dies in ~3s)
var _outlaw_spawn_timer: float = 0.0

# Iter 77: Slippery Pete boss. Appears at PETE_SPAWN_DELAY into the
# level. Slow approach, much higher HP, drops the WIN modal on defeat.
const PETE_SPAWN_DELAY: float = 30.0  # iter 153: 18 → 30. At OBSTACLE_SPEED 2.5 a gate takes ~11s to reach the player; 30s lets the player clear ~6 gates + a sustained outlaw firefight BEFORE the boss (user: "Pete appearing before reaching any gates or outlaws")
const PETE_HP: int = 500  # iter 119: 40 → 1000 → iter 147: 1000 → 500 (user: "Pete's HP is too high. cut it in half")
const PETE_SPEED: float = 10.0  # iter 124: 1.6 → 4.0 → iter 143: 4.0 → 10.0 (user reported "doesn't advance fast enough")
const PETE_FIRE_INTERVAL: float = 0.5  # iter 119: 1.0 → 0.5 (alternates L/R guns)
const PETE_HIT_RADIUS_SQ: float = 3.6 * 3.6  # iter 147: 2.6 → 3.6 (user: "bullets pass through him too")
const PETE_STAY_Z: float = -6.0  # holds at duel distance until melee phase
# Iter 119: Pete melee — if the duel drags on (Pete not yet defeated)
# he keeps walking past STAY_Z toward the cowboy. Once within MELEE_RANGE,
# he deals MELEE_DPS damage/second contact-style.
const PETE_MELEE_TRIGGER_T: float = 10.0  # seconds at STAY_Z before Pete advances
const PETE_MELEE_ADVANCE_SPEED: float = 0.8  # u/s during melee advance
const PETE_MELEE_RANGE: float = 1.8  # distance at which melee tick starts
const PETE_MELEE_DPS: float = 2.0  # posse members lost per second of contact
var _pete_stay_elapsed: float = 0.0
var _pete_melee_tick_accum: float = 0.0

# Iter 157: The Candy Rustler — the level-2 boss. A jointed paper-cutout
# puppet (candy_rustler_rig.gd) shown through a top-level SubViewport →
# 3D billboard, the same Android-safe indirection the video billboards
# use. Unlike Pete (video-anim + melee) he holds at duel distance and
# dismantles piece-by-piece as he is shot: the rig's take_damage() drives
# the threshold detachment, defeat() drives the death scatter.
const _CANDY_RUSTLER_RIG := preload("res://scripts/candy_rustler_rig.gd")
const RUSTLER_HP: int = 400  # tunable — rig sheds a piece at 75/50/25%
# Iter 163: the Rustler is a melee boss — strides in fast, holds at
# RUSTLER_STAY_Z and crinkles the posse by contact (no projectiles).
const RUSTLER_SPEED: float = 15.0  # approach speed — faster than Pete (10)
const RUSTLER_STAY_Z: float = -7.0  # holds + melees here; further back than Pete (-6) so his head clears the screen top
const RUSTLER_MELEE_DPS: float = 3.0  # posse members drained per second of contact
const RUSTLER_TAUNT_INTERVAL: float = 5.0
const _RUSTLER_VIEWPORT_PX := Vector2i(896, 768)  # rig figure is wide (arms spread)
const _RUSTLER_RIG_SCALE := Vector2(0.9, 0.9)     # framing eyeballed — tune post-sideload
const _RUSTLER_RIG_POS := Vector2(-187.0, 38.0)   # centers the v1 figure in the viewport
var _rustler_melee_accum: float = 0.0
var _rustler_taunt_timer: float = 5.0
var _rustler_hit_voice_cd: float = 0.0

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
# Iter 114: pulled IN from 7.5 / 14.0. The SubViewport is 1080×1920
# portrait — at vertical FOV 70°, the HORIZONTAL half-FOV is only ~21.5°.
# Anything beyond x=±3.5 at cowboy depth (8 world units from camera) is
# outside the visible cone. Buildings at x=±14 were never going to be on
# screen. Now buildings sit at the road's edge, fences just outside it.
const SCENERY_ROAD_SHOULDER: float = 3.5    # x distance from road center
const SCENERY_FAR_BAND: float = 5.0          # buildings — just past shoulder
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
	# Iter 130: prepare the breathing-prop placeholder texture for any
	# props the user hasn't yet authored. Idempotent.
	_ensure_placeholder_prop_tex()
	# Iter 96: terrain_3d.gd (attached to the Terrain3D instance) now
	# does its own subviewport→sprite binding in its _ready, so the
	# manual binding from iter 69 is no longer needed. Keeping a
	# breadcrumb so the log still shows the binding step succeeded.
	if subviewport != null:
		DebugLog.add("level_3d: terrain instance loaded; subviewport=%s" % subviewport.size)
	else:
		DebugLog.add("WARN level_3d: subviewport null after terrain instance")
	# Iter 153: sync the ground-texture scroll to OBSTACLE_SPEED so the
	# terrain and the world-space props advance at the SAME apparent rate
	# (user: "terrain and static props advance at different rates"). The
	# legacy terrain SCROLL_SPEED 0.25 was matched to OBSTACLE_SPEED 8.0.
	if terrain_3d_node != null and "scroll_speed" in terrain_3d_node:
		# Iter 165: scroll_speed is in UV-V units/sec; props move in world-Z
		# units/sec. The terrain plane is 60 deep with uv1_scale.y = 4, so
		# 1 UV-V = 60/4 = 15 world units. Dividing OBSTACLE_SPEED by 15 makes
		# the dirt scroll at the SAME apparent rate as the props sliding
		# over it. (The old 0.25/8 factor was a stale hand-tune from the
		# legacy 8.0 obstacle speed — it ran the terrain ~2× too slow.)
		terrain_3d_node.scroll_speed = OBSTACLE_SPEED / 15.0
		DebugLog.add("level_3d: terrain scroll synced to %.4f" % terrain_3d_node.scroll_speed)
	# Iter 107/118: override the terrain_3d.tscn instance's camera to a
	# steeper Evony-style top-down angle, sized for the portrait viewport.
	# Iter 118 added: fov=50 + KEEP_WIDTH so the horizontal extent reads
	# correctly on a 9:16 viewport. With the default KEEP_HEIGHT + vfov=70°
	# the horizontal half-FOV was only 21.5°, so anything beyond x=±3.35
	# at cowboy depth (8.5 units away) was off-screen. KEEP_WIDTH with
	# fov=50° gives horizontal half-FOV=25° → visible road x=±4 at the
	# cowboy and ~±10 at obstacle-spawn z=-24.
	if camera != null:
		camera.position = Vector3(0, 7.0, 3.0)
		camera.rotation_degrees = Vector3(-55, 0, 0)
		camera.fov = 50.0
		camera.keep_aspect = 0  # Camera3D.KEEP_WIDTH (portrait viewport)
		DebugLog.add("level_3d: camera overridden (y=7 z=3 pitch=-55° fov=50 KEEP_WIDTH)")
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
	# Iter 115: instantiate Gun + GunState. Default Gun.clip_size=6,
	# fire_interval=0.18s, reload_time=1.0s — matches the 2D defaults.
	_gun = GunScript.new()
	_gun_state = GunStateScript.new(_gun)
	DebugLog.add("level_3d: gun state initialized (clip=%d, fire=%.2fs, reload=%.1fs)" % [
		_gun.clip_size, _gun.fire_interval, _gun.reload_time,
	])
	if info_label != null:
		info_label.text = "iter97 RDY-5 followers ok"
	info_label.text = "iter97 OK · build %s · top-left to exit" % BuildInfo.SHA
	DebugLog.add("level_3d _ready (build=%s)" % BuildInfo.SHA)
	# Iter 124: honor DebugPreview.pending_test_range flag.
	if get_node_or_null("/root/DebugPreview") != null and DebugPreview.pending_test_range:
		_test_range_mode = true
		DebugPreview.pending_test_range = false
		DebugLog.add("level_3d: TEST RANGE mode active — cactus-only field")
		call_deferred("_setup_test_range_3d")
	# Iter 125-129: honor the remaining DebugPreview flags so the
	# debug menu's previews route into 3D ceremonies. Each flag enters
	# a 'preview' mode: skip normal gate/outlaw/Pete spawning, run the
	# chosen ceremony, leave the player in the empty scene afterward.
	if get_node_or_null("/root/DebugPreview") != null:
		if DebugPreview.pending_rush != "":
			var rush_id: String = DebugPreview.pending_rush
			DebugPreview.pending_rush = ""
			_preview_mode = true
			_level_state = LevelState.FINISHED
			DebugLog.add("level_3d: rush preview %s" % rush_id)
			call_deferred("_play_rush_3d", rush_id)
		elif DebugPreview.pending_sugar_rush:
			DebugPreview.pending_sugar_rush = false
			_preview_mode = true
			_level_state = LevelState.FINISHED
			DebugLog.add("level_3d: sugar rush preview")
			call_deferred("_play_sugar_rush_3d")
		elif DebugPreview.pending_weapon != "":
			var w: String = DebugPreview.pending_weapon
			DebugPreview.pending_weapon = ""
			_preview_mode = true
			_level_state = LevelState.FINISHED
			DebugLog.add("level_3d: weapon preview %s" % w)
			call_deferred("_preview_weapon_3d", w)
		elif DebugPreview.pending_posse_unlock != "":
			var h: String = DebugPreview.pending_posse_unlock
			DebugPreview.pending_posse_unlock = ""
			_preview_mode = true
			_level_state = LevelState.FINISHED
			DebugLog.add("level_3d: hero preview %s" % h)
			call_deferred("_preview_hero_3d", h)
		elif DebugPreview.pending_captive_hero != "":
			var ch: String = DebugPreview.pending_captive_hero
			var cc: String = DebugPreview.pending_captive_container
			var pc: int = DebugPreview.pending_pushed_count
			DebugPreview.pending_captive_hero = ""
			DebugPreview.pending_captive_container = ""
			DebugPreview.pending_pushed_count = 0
			_preview_mode = true
			_level_state = LevelState.FINISHED
			if pc > 0:
				DebugLog.add("level_3d: pushed wagon preview %s/%s × %d pushers" % [ch, cc, pc])
				call_deferred("_preview_pushed_wagon_3d", ch, cc, pc)
			else:
				DebugLog.add("level_3d: captive preview %s in %s" % [ch, cc])
				call_deferred("_preview_captive_3d", ch, cc)
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
	# 2) Cowboy3D — video billboard. Sprite3D textured by a shared video
	# viewport; _set_cowboy_anim() swaps the stream by level state. Starts
	# on run_shoot_fwd, a back-view clip, so the cowboy faces the outlaws.
	cowboy_3d = Sprite3D.new()
	cowboy_3d.name = "Cowboy3D"
	var cowboy_sv: SubViewport = _get_or_create_shared_video_viewport(COWBOY_RUN_FWD_STREAM)
	cowboy_3d.texture = cowboy_sv.get_texture()
	cowboy_3d.pixel_size = COWBOY_PIXEL_SIZE
	cowboy_3d.billboard = 1  # BILLBOARD_ENABLED (int literal — iter 100 lesson)
	# alpha_cut 0 = ALPHA_CUT_DISABLED — the chromakey shader's soft edge
	# needs alpha blending, not the hard discard the static sprite used.
	cowboy_3d.alpha_cut = 0
	cowboy_3d.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	# Iter 106: COWBOY_Z keeps this in sync if the camera angle changes.
	cowboy_3d.position = Vector3(0, 0.45, COWBOY_Z)
	subviewport.add_child(cowboy_3d)
	_cowboy_anim_stream = COWBOY_RUN_FWD_STREAM
	DebugLog.add("level_3d: cowboy_3d video billboard added")
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

# A posse follower — video billboard textured from the staggered pool,
# placed at a trapezoid formation slot computed from its index.
func _make_follower(idx: int) -> Sprite3D:
	var f := Sprite3D.new()
	var slot: int = _rng.randi()
	f.set_meta("pool_slot", slot)
	var tex: Texture2D = _posse_pool_texture(slot)
	f.texture = tex if tex != null else COWBOY_TEXTURE_LVL3D
	f.pixel_size = COWBOY_PIXEL_SIZE
	f.billboard = 1   # BILLBOARD_ENABLED (int literal — iter 100 lesson)
	f.alpha_cut = 0   # ALPHA_CUT_DISABLED — chromakey soft edge needs blending
	f.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var n: int = POSSE_FORMATION_OFFSETS.size()
	var offset: Vector3 = (POSSE_FORMATION_OFFSETS[idx % n] if n > 0
		else Vector3(0, 0, 0.6 + 0.2 * float(idx)))
	# Rows past the first push deeper: scale offset.z by the row index.
	var row_mul: float = 1.0 + floorf(float(idx) / float(maxi(n, 1)))
	f.position = Vector3(offset.x, 0.45, COWBOY_Z + offset.z * row_mul)
	f.set_meta("formation_offset", Vector3(offset.x, 0.0, offset.z * row_mul))
	subviewport.add_child(f)
	return f

# Iter 72: posse followers behind the leader in a trapezoid formation.
func _spawn_posse_followers() -> void:
	if cowboy_3d == null:
		return
	_build_posse_pool()
	for i in range(POSSE_FORMATION_OFFSETS.size()):
		_followers.append(_make_follower(i))

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
enum SceneryType { FENCE, ROCK, CACTUS, SCRUB, BUILDING, GRASS }
const SCENERY_WEIGHTS: Array[int] = [
	4,  # FENCE
	3,  # ROCK
	2,  # CACTUS
	2,  # SCRUB
	1,  # BUILDING (rarest — large, distinctive)
	4,  # GRASS (iter 155 — ground cover, clusters of tufts)
]

var _scenery_spawn_count: int = 0

func _spawn_scenery_item() -> void:
	_scenery_spawn_count += 1
	if _scenery_spawn_count == 1 or _scenery_spawn_count % 10 == 0:
		DebugLog.add("scenery spawn #%d (scenery_root.size=%d)" % [
			_scenery_spawn_count, scenery_root.get_child_count(),
		])
	_spawn_scenery_item_inner()

func _spawn_scenery_item_inner() -> void:
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
		SceneryType.GRASS:
			_spawn_grass(side, spawn_z)

func _spawn_fence_post(side: float, z: float) -> void:
	# Iter 131: if a fence_post PNG exists, spawn as breathing billboard
	# pair (matches the iter-112 two-post-plus-rail composition but as
	# sprites with sway). Falls back to CSG if PNG missing.
	if ResourceLoader.exists(PROP_TEX_REGISTRY["fence_post"].path):
		var x1: float = side * (SCENERY_ROAD_SHOULDER + _rng.randf_range(-0.2, 0.2))
		var x2: float = side * (SCENERY_ROAD_SHOULDER + _rng.randf_range(-0.2, 0.2))
		_spawn_prop_from_slug("fence_post", x1, z, scenery_root)
		_spawn_prop_from_slug("fence_post", x2, z + 0.8, scenery_root)
		return
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
	# Iter 131: try sprite billboards first. Small vs large picked by
	# random so the road has a mix of pebbles and boulders.
	var rock_slug: String = "rock_small" if _rng.randf() < 0.7 else "rock_large"
	if ResourceLoader.exists(PROP_TEX_REGISTRY[rock_slug].path):
		var rx: float = side * (SCENERY_ROAD_SHOULDER + _rng.randf_range(0.3, 2.5))
		_spawn_prop_from_slug(rock_slug, rx, z, scenery_root)
		return
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
	# Iter 131: try sprite billboard first — pick from 3 variants based on
	# which PNGs the user has generated. Falls back to CSG composition if
	# no cactus PNGs found.
	var cactus_slugs: Array[String] = ["cactus_saguaro", "cactus_barrel", "cactus_prickly"]
	var available: Array[String] = []
	for s in cactus_slugs:
		if ResourceLoader.exists(PROP_TEX_REGISTRY[s].path):
			available.append(s)
	if available.size() > 0:
		var slug: String = available[_rng.randi() % available.size()]
		var cx: float = side * (SCENERY_ROAD_SHOULDER + _rng.randf_range(1.0, 4.0))
		_spawn_prop_from_slug(slug, cx, z, scenery_root)
		return
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
	# Iter 131: try sprite billboard first.
	if ResourceLoader.exists(PROP_TEX_REGISTRY["scrub"].path):
		var sx: float = side * (SCENERY_ROAD_SHOULDER + _rng.randf_range(0.5, 5.0))
		_spawn_prop_from_slug("scrub", sx, z, scenery_root)
		return
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

# Iter 155: grass tufts as roadside ground cover (ported in spirit from
# the roguelike webgl grass demo). Each scenery roll drops a small
# cluster of 2-4 tufts at varied x/z so the shoulder reads as a grassy
# patch, not a single sprite. The breathing shader (sway_amp 0.13) gives
# each tuft a lively wind sway.
func _spawn_grass(side: float, z: float) -> void:
	if not ResourceLoader.exists(PROP_TEX_REGISTRY["grass_tuft"].path):
		return
	var n: int = _rng.randi_range(2, 4)
	for i in range(n):
		var gx: float = side * (SCENERY_ROAD_SHOULDER + _rng.randf_range(-1.2, 4.5))
		var gz: float = z + _rng.randf_range(-1.4, 1.4)
		_spawn_prop_from_slug("grass_tuft", gx, gz, scenery_root)

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
	# Iter 131: try sprite billboard first. 5 building variants — saloon,
	# general store, bank, jail, stables. Pick a random one of those the
	# user has generated. If none available, fall back to CSG-composed
	# building (iter 112 false-front + gable + awning + label).
	var bld_slugs: Array[String] = [
		"building_saloon", "building_general_store", "building_bank",
		"building_jail", "building_stables"]
	var available: Array[String] = []
	for s in bld_slugs:
		if ResourceLoader.exists(PROP_TEX_REGISTRY[s].path):
			available.append(s)
	if available.size() > 0:
		var slug: String = available[_rng.randi() % available.size()]
		var bx: float = side * (SCENERY_FAR_BAND + _rng.randf_range(-1.0, 1.5))
		_spawn_prop_from_slug(slug, bx, z, scenery_root)
		return
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
const GATE_HITS_PER_STEP: int = 3  # iter 113: armor — 3 bullets per value decrement

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
		# Iter 113: armor — accumulate hits, decrement value only every
		# GATE_HITS_PER_STEP. Otherwise gates get pummeled to 0 instantly.
		var hits: int = gate.get_meta(side + "_hits", 0) + 1
		gate.set_meta(side + "_hits", hits)
		# Always show a small popup so the player gets shot feedback.
		_spawn_popup_3d(bullet.position + Vector3(0, 0.4, 0),
			"hit", Color(1.0, 0.92, 0.3, 0.9), 28)
		if hits < GATE_HITS_PER_STEP:
			return true  # bullet absorbed, but value not yet stepped
		# Step counter resets. Iter 114: invert direction — bullets
		# IMPROVE the gate (make it better for the player) rather than
		# pummeling it to 0. User said: 'add/subtract gates are supposed
		# to increase with bullet collision, but they are all going to 0'.
		# Rules:
		#   +N gate: bullets increase N (better for player)
		#   -N gate: bullets move toward 0 (less bad for player)
		#   ×N gate: bullets increase the multiplier
		gate.set_meta(side + "_hits", 0)
		var value: int = gate.get_meta(side + "_value", 0)
		var op: String = gate.get_meta(side + "_op", "+")
		if op == "×":
			pass  # iter 119: × gates absorb the bullet but DON'T increment. Multipliers stay at ×2 max so posse doesn't explode.
		elif value >= 0:
			value += 1
		else:  # value < 0
			value += 1  # move toward 0 (less negative)
		# Persist + update visuals.
		gate.set_meta(side + "_value", value)
		gate.set_meta(side + "_op", op)
		var lbl: Label3D = gate.get_meta(side + "_label")
		if lbl != null and is_instance_valid(lbl):
			lbl.text = "%s%d" % [op, value]
		if door is CSGBox3D and (door as CSGBox3D).material is StandardMaterial3D:
			(((door as CSGBox3D).material) as StandardMaterial3D).albedo_color = _gate_color_for(value, op)
		# Step-popup at impact: shows the new value so player sees the change.
		_spawn_popup_3d(bullet.position + Vector3(0, 0.5, 0),
			"%s%d" % [op, value], Color(1.0, 0.92, 0.3, 1), 40)
		return true
	return false

# Iter 124: lay out a static cactus grid for test range mode. 6 rows × 5
# cols of CSGBox3D cacti staggered in z so the player can practice fire
# aim without enemy interference. Reuses ObstacleType.CACTUS visual
# (green box, 0.7×2.4×0.7). Cacti are added to obstacles_root so the
# existing bullet-vs-obstacle collision treats them as targets.
func _setup_test_range_3d() -> void:
	# Cancel any pre-spawned obstacles + outlaws from the normal flow.
	for child in obstacles_root.get_children():
		child.queue_free()
	for child in outlaws_root.get_children():
		child.queue_free()
	for child in boss_root.get_children():
		child.queue_free()
	# Build the grid. Centered on x, rows extend forward in -z.
	for row in range(TEST_RANGE_ROWS):
		for col in range(TEST_RANGE_COLS):
			var x: float = (float(col) - float(TEST_RANGE_COLS - 1) * 0.5) * TEST_RANGE_SPACING_X
			var z: float = -3.0 - float(row) * TEST_RANGE_SPACING_Z
			var c := CSGBox3D.new()
			c.size = Vector3(0.7, 2.4, 0.7)
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(0.22, 0.45, 0.18, 1)
			c.material = mat
			c.position = Vector3(x, 1.2, z)
			obstacles_root.add_child(c)
	DebugLog.add("level_3d: test range cactus field — %d cacti spawned" % (TEST_RANGE_ROWS * TEST_RANGE_COLS))

# ============================================================================
# Iter 125-126: Gold Rush ceremonies (3D). Each rush is a 4-phase
# Candy-Crush-style cascade:
#   1. ANNOUNCE — big FlourishBanner with rush name
#   2. BUILD    — initial visual (rolling tumbleweed, cart entry, etc)
#   3. CASCADE  — staggered chain reactions with bounty drops
#   4. CRESCENDO — final big burst + BOUNTY total flourish
#
# Shared primitives (_burst_at, _drop_bonus_at, _add_bounty) compose
# each ceremony from the same building blocks. Visual escalation comes
# from staggered call_deferred + create_tween chains.
# ============================================================================

func _play_rush_3d(rush_id: String) -> void:
	# Small breath before the ceremony starts so the scene settles.
	await get_tree().create_timer(0.4).timeout
	match rush_id:
		"A": await _rush_a_six_shooter_salute()
		"B": await _rush_b_jelly_jar_cascade()
		"D": await _rush_d_tumbleweed_bonus_roll()
		"E": await _rush_e_candy_cart_chain()
		"F": await _rush_f_liquorice_locomotive()
		"G": await _rush_g_avalanche_bonanza()
		"H": await _rush_h_gumball_runaway()
		_:   await _rush_a_six_shooter_salute()
	# After every rush, show the final BOUNTY flourish + retry button.
	await get_tree().create_timer(0.6).timeout
	_show_preview_win("RUSH COMPLETE")

# ---- Shared primitives ------------------------------------------------------

# Iter 125: candy burst — N small colored CSGSpheres tween outward in
# a sphere from `pos`, scale to 0 and queue_free over `duration` seconds.
# `scale` multiplies the burst radius; bigger scale → wider burst.
func _burst_at(pos: Vector3, count: int, color: Color, scale: float = 1.0, duration: float = 0.7) -> void:
	for i in range(count):
		var c := CSGSphere3D.new()
		c.radius = 0.14
		c.radial_segments = 6
		c.rings = 4
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mat.emission_enabled = true
		mat.emission = color * 1.4
		c.material = mat
		c.position = pos
		popups_root.add_child(c)
		var angle: float = float(i) / float(count) * TAU + _rng.randf() * 0.4
		var horiz: float = _rng.randf_range(2.5, 4.0) * scale
		var verti: float = _rng.randf_range(3.0, 5.5) * scale
		var target := Vector3(
			pos.x + cos(angle) * horiz,
			pos.y + verti,
			pos.z + sin(angle) * horiz,
		)
		var tw := create_tween().set_parallel(true)
		tw.tween_property(c, "position", target, duration) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(c, "scale", Vector3(0.1, 0.1, 0.1), duration) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		var free_tween: Tween = create_tween()
		free_tween.tween_interval(duration)
		free_tween.tween_callback(c.queue_free)

# Iter 125: drop a candy 'bonus jar' from above at `landing` with a
# bounce-and-burst finale + bounty popup + GameState increment.
func _drop_bonus_at(landing: Vector3, value: int, color: Color, label: String = "") -> void:
	var c := CSGBox3D.new()
	c.size = Vector3(0.55, 0.55, 0.55)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color * 0.9
	c.material = mat
	c.rotation_degrees = Vector3(_rng.randf_range(0, 60), _rng.randf_range(0, 60), _rng.randf_range(0, 60))
	c.position = landing + Vector3(0, 9.0, 0)
	popups_root.add_child(c)
	var tw := create_tween()
	tw.tween_property(c, "position", landing + Vector3(0, 0.3, 0), 0.45) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	# Squash + recoil + burst
	tw.tween_property(c, "scale", Vector3(1.3, 0.5, 1.3), 0.08)
	tw.tween_property(c, "scale", Vector3.ZERO, 0.18) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_callback(_burst_at.bind(landing + Vector3(0, 0.4, 0), 10, color, 1.0, 0.6))
	var popup_label: String = label if label != "" else "+%d" % value
	tw.tween_callback(_spawn_popup_3d.bind(landing + Vector3(0, 1.5, 0), popup_label, color, 64))
	tw.tween_callback(c.queue_free)
	tw.tween_callback(_add_bounty.bind(value))

func _add_bounty(amount: int) -> void:
	if get_node_or_null("/root/GameState") != null:
		GameState.bounty = GameState.bounty + amount

# Iter 125: announce + camera shake at ceremony start.
func _ceremony_announce(preset: String) -> void:
	var ui_canvas: Node = get_node_or_null("UI")
	if ui_canvas != null:
		FlourishBanner.spawn(ui_canvas, preset)

# Iter 125: closing flourish — big final banner with the cumulative
# bounty value, plus a 360-burst at the cowboy's position.
func _ceremony_finale(preset: String, bounty_added: int) -> void:
	_burst_at(cowboy_3d.position + Vector3(0, 1.5, 0), 24, Color(1.0, 0.92, 0.40, 1), 1.6, 1.0)
	_spawn_popup_3d(cowboy_3d.position + Vector3(0, 4.0, 0),
		"+%d BOUNTY" % bounty_added, Color(1.0, 0.92, 0.30, 1), 96)
	_ceremony_announce(preset)

# Iter 125: show the WIN modal after a ceremony so the user can RETRY
# or back out. Reuses the existing WinOverlay; suppresses gameplay text.
func _show_preview_win(banner_text: String) -> void:
	if win_label:
		win_label.text = banner_text
	if win_overlay:
		win_overlay.visible = true
	if get_node_or_null("/root/AudioBus") and AudioBus.has_method("play_gate_pass"):
		AudioBus.play_gate_pass()

# ---- Rush A: Six-Shooter Salute (Easy, Frontier) ----------------------------
# Each posse member fires a celebratory upward bullet, staggered, with
# +50 bounty per shot. Iter 125 polish: pre-burst at cowboy + final
# PERFECT_VOLLEY banner.

func _rush_a_six_shooter_salute() -> void:
	_ceremony_announce("PERFECT_VOLLEY")
	await get_tree().create_timer(0.5).timeout
	await _gold_rush_salute_3d()
	_ceremony_finale("PERFECT_VOLLEY", 0)  # salute already added bounty

# ---- Rush B: Jelly Jar Cascade (Hard, Mine) ---------------------------------
# 12 colored jelly jars cascade DOWN onto the road in waves of 3 ahead
# of the cowboy. Each jar awards +75 bounty. Final burst + total flourish.

func _rush_b_jelly_jar_cascade() -> void:
	_ceremony_announce("SUGAR_CASCADE")
	await get_tree().create_timer(0.5).timeout
	const JAR_COLORS: Array[Color] = [
		Color(1.00, 0.32, 0.45, 1),   # cherry red
		Color(1.00, 0.85, 0.30, 1),   # lemon yellow
		Color(0.42, 0.92, 0.55, 1),   # lime green
		Color(0.55, 0.65, 1.00, 1),   # blueberry
		Color(0.95, 0.55, 0.95, 1),   # grape
	]
	# 4 waves of 3 jars each. Each wave staggered along x lanes, advancing
	# in z toward the cowboy. Lots of color variety + cascading impacts.
	var total_value: int = 0
	for wave in range(4):
		for col in range(3):
			var x: float = (float(col) - 1.0) * 1.6
			var z: float = -6.0 + float(wave) * 1.8
			var color: Color = JAR_COLORS[(wave * 3 + col) % JAR_COLORS.size()]
			_drop_bonus_at(Vector3(x, 0.0, z), 75, color)
			total_value += 75
			await get_tree().create_timer(0.18).timeout
		await get_tree().create_timer(0.15).timeout
	await get_tree().create_timer(0.8).timeout
	_ceremony_finale("SUGAR_CASCADE", total_value)

# ---- Rush D: Tumbleweed Bonus Roll (Medium, Farm) ---------------------------
# Giant brown tumbleweed (multi-sphere bundle) rolls from far z toward
# camera, dropping bounty wagons along its path. Final big bounce burst.

func _rush_d_tumbleweed_bonus_roll() -> void:
	_ceremony_announce("ROLLED")
	await get_tree().create_timer(0.5).timeout
	# Build the giant tumbleweed (4 stacked spheres, ~1.6 units total)
	var tw_node := Node3D.new()
	for i in range(4):
		var s := CSGSphere3D.new()
		s.radius = 0.6
		s.radial_segments = 10
		s.rings = 8
		var sm := StandardMaterial3D.new()
		sm.albedo_color = Color(
			_rng.randf_range(0.48, 0.62),
			_rng.randf_range(0.30, 0.40),
			_rng.randf_range(0.12, 0.20), 1)
		sm.roughness = 1.0
		s.material = sm
		s.scale = Vector3(_rng.randf_range(0.85, 1.10),
			_rng.randf_range(0.85, 1.10), _rng.randf_range(0.85, 1.10))
		s.position = Vector3(
			_rng.randf_range(-0.3, 0.3),
			_rng.randf_range(-0.3, 0.3),
			_rng.randf_range(-0.3, 0.3))
		tw_node.add_child(s)
	tw_node.position = Vector3(-1.5, 1.0, -22.0)
	popups_root.add_child(tw_node)
	# Roll along z toward cowboy + drop bounties at intervals
	var total: int = 0
	for i in range(8):
		var target_z: float = -22.0 + float(i + 1) * 3.2
		var roll := create_tween()
		roll.tween_property(tw_node, "position:z", target_z, 0.4)
		await roll.finished
		tw_node.rotation.x += PI * 0.6
		_drop_bonus_at(Vector3(tw_node.position.x + _rng.randf_range(-0.6, 0.6),
			0.0, tw_node.position.z - 1.0), 60, Color(1.0, 0.78, 0.30, 1))
		total += 60
	# Final big bounce + dissolve
	var final_tw := create_tween()
	final_tw.tween_property(tw_node, "scale", Vector3(1.4, 1.4, 1.4), 0.2)
	final_tw.tween_property(tw_node, "scale", Vector3.ZERO, 0.25) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	await final_tw.finished
	_burst_at(tw_node.position, 18, Color(1.0, 0.78, 0.30, 1), 1.5)
	tw_node.queue_free()
	total += 500
	_add_bounty(500)
	await get_tree().create_timer(0.4).timeout
	_ceremony_finale("ROLLED", total)

# ---- Rush E: Candy Cart Chain (Extreme, Frontier) ---------------------------
# 5 colorful candy carts roll across the road in sequence (left to right
# alternating direction). When each cart reaches its impact point, it
# explodes into a candy burst. Chain detonation builds left-to-right.

func _rush_e_candy_cart_chain() -> void:
	_ceremony_announce("CHAIN")
	await get_tree().create_timer(0.4).timeout
	const CART_COLORS: Array[Color] = [
		Color(1.0, 0.40, 0.55, 1),
		Color(1.0, 0.85, 0.30, 1),
		Color(0.55, 1.0, 0.55, 1),
		Color(0.55, 0.75, 1.0, 1),
		Color(0.85, 0.55, 1.0, 1),
	]
	var total: int = 0
	for i in range(5):
		var direction: float = 1.0 if i % 2 == 0 else -1.0
		var start_x: float = -direction * 6.0
		var end_x: float = direction * 6.0
		var cart := CSGBox3D.new()
		cart.size = Vector3(1.4, 1.0, 0.9)
		var cm := StandardMaterial3D.new()
		cm.albedo_color = CART_COLORS[i]
		cm.emission_enabled = true
		cm.emission = CART_COLORS[i] * 0.7
		cart.material = cm
		var lane_z: float = -2.0 - float(i) * 0.8
		cart.position = Vector3(start_x, 0.5, lane_z)
		popups_root.add_child(cart)
		var roll_tw := create_tween().set_parallel(true)
		roll_tw.tween_property(cart, "position:x", end_x, 0.55) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		roll_tw.tween_property(cart, "rotation:z",
			-direction * TAU, 0.55)
		await roll_tw.finished
		_burst_at(cart.position, 14, CART_COLORS[i], 1.2)
		_spawn_popup_3d(cart.position + Vector3(0, 2.0, 0),
			"+200", CART_COLORS[i], 64)
		cart.queue_free()
		total += 200
		_add_bounty(200)
		await get_tree().create_timer(0.10).timeout  # tight chain
	await get_tree().create_timer(0.6).timeout
	_ceremony_finale("CHAIN", total)

# ---- Stub implementations for iter 126+ ------------------------------------
# Rushes F/G/H + sugar/weapon/hero get their own ceremonies in iter 126-129.
# Stubs here keep the dispatch symbol-complete and announce the rush so
# previewing them in iter 125 sideload at least shows the banner.

# ---- Rush F: Liquorice Locomotive (Extreme, Mine) ---------------------------
# A long black-and-licorice-red train barrels horizontally across the
# scene. Engine in front with a chimney puffing CSGSphere smoke. As it
# passes, cars drop bounty bags. Final detonation when train exits.

func _rush_f_liquorice_locomotive() -> void:
	_ceremony_announce("LOCOMOTIVE")
	await get_tree().create_timer(0.4).timeout
	const TRAIN_LEN: int = 6
	const TRAVEL_TIME: float = 3.0
	const SMOKE_INTERVAL: float = 0.10
	var train := Node3D.new()
	popups_root.add_child(train)
	train.position = Vector3(-13.0, 0.0, -2.0)
	# Build cars
	for i in range(TRAIN_LEN):
		var car := CSGBox3D.new()
		car.size = Vector3(1.5, 1.4, 1.4)
		var m := StandardMaterial3D.new()
		# Engine darker, cars alternate licorice-red and black
		if i == 0:
			m.albedo_color = Color(0.08, 0.05, 0.05, 1)
		elif i % 2 == 0:
			m.albedo_color = Color(0.55, 0.05, 0.08, 1)  # licorice red
		else:
			m.albedo_color = Color(0.10, 0.05, 0.08, 1)
		m.emission_enabled = true
		m.emission = m.albedo_color * 0.4
		car.material = m
		car.position = Vector3(-float(i) * 1.8, 0.7, 0.0)
		train.add_child(car)
	# Engine chimney
	var chimney := CSGCylinder3D.new()
	chimney.radius = 0.18
	chimney.height = 0.9
	var chim_mat := StandardMaterial3D.new()
	chim_mat.albedo_color = Color(0.05, 0.04, 0.04, 1)
	chimney.material = chim_mat
	chimney.position = Vector3(0.4, 1.85, 0.0)
	train.add_child(chimney)
	# Engine front lamp
	var lamp := CSGSphere3D.new()
	lamp.radius = 0.18
	var lamp_mat := StandardMaterial3D.new()
	lamp_mat.albedo_color = Color(1.0, 0.95, 0.60, 1)
	lamp_mat.emission_enabled = true
	lamp_mat.emission = Color(1.0, 0.95, 0.60, 1) * 2.0
	lamp.material = lamp_mat
	lamp.position = Vector3(0.85, 0.9, 0.0)
	train.add_child(lamp)
	# Launch the train: tween x across the road
	var travel_tw: Tween = create_tween()
	travel_tw.tween_property(train, "position:x", 13.0, TRAVEL_TIME) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# Smoke + bounty drops while traveling
	var smoke_timer: float = 0.0
	var bounty_timer: float = 0.0
	var elapsed: float = 0.0
	var total: int = 0
	while elapsed < TRAVEL_TIME:
		await get_tree().create_timer(SMOKE_INTERVAL).timeout
		elapsed += SMOKE_INTERVAL
		# Smoke puff from chimney
		var smoke := CSGSphere3D.new()
		smoke.radius = 0.32 + _rng.randf_range(-0.05, 0.10)
		var sm := StandardMaterial3D.new()
		sm.albedo_color = Color(0.65, 0.62, 0.60, 0.85)
		sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		smoke.material = sm
		smoke.position = train.position + Vector3(0.4, 2.1, 0.0)
		popups_root.add_child(smoke)
		var smoke_tw := create_tween().set_parallel(true)
		smoke_tw.tween_property(smoke, "position:y", smoke.position.y + 2.5, 1.2)
		smoke_tw.tween_property(smoke, "scale", Vector3(2.5, 2.5, 2.5), 1.2)
		smoke_tw.tween_property(smoke, "transparency", 1.0, 1.2)
		var free_tw := create_tween()
		free_tw.tween_interval(1.3)
		free_tw.tween_callback(smoke.queue_free)
		# Bounty drop every ~0.5s
		bounty_timer += SMOKE_INTERVAL
		if bounty_timer >= 0.5:
			bounty_timer = 0.0
			var drop_x: float = train.position.x - _rng.randf_range(2.0, 4.0)
			_drop_bonus_at(Vector3(drop_x, 0.0, -3.0), 200,
				Color(1.0, 0.85, 0.30, 1))
			total += 200
	await travel_tw.finished
	# Massive exit detonation
	_burst_at(train.position + Vector3(0, 1.2, 0), 36,
		Color(0.95, 0.30, 0.20, 1), 2.2, 1.0)
	_spawn_popup_3d(cowboy_3d.position + Vector3(0, 4.5, 0),
		"+1000 BONUS", Color(1.0, 0.92, 0.30, 1), 84)
	train.queue_free()
	total += 1000
	_add_bounty(1000)
	await get_tree().create_timer(0.6).timeout
	_ceremony_finale("LOCOMOTIVE", total)

# ---- Rush G: Avalanche Bonanza (Extreme, Mountain) --------------------------
# Cascade of boulder CSGSpheres dropping from horizon toward cowboy.
# 20 medium boulders staggered + one giant climax boulder.

func _rush_g_avalanche_bonanza() -> void:
	_ceremony_announce("AVALANCHE")
	await get_tree().create_timer(0.4).timeout
	const BOULDERS: int = 20
	var total: int = 0
	for i in range(BOULDERS):
		var x: float = _rng.randf_range(-3.0, 3.0)
		var z: float = _rng.randf_range(-12.0, 2.0)
		var size: float = _rng.randf_range(0.45, 0.85)
		var rock := CSGSphere3D.new()
		rock.radius = size
		rock.radial_segments = 8
		rock.rings = 6
		var rm := StandardMaterial3D.new()
		rm.albedo_color = Color(
			_rng.randf_range(0.40, 0.55),
			_rng.randf_range(0.35, 0.45),
			_rng.randf_range(0.30, 0.40), 1)
		rm.roughness = 1.0
		rock.material = rm
		rock.position = Vector3(x, 14.0, z)
		popups_root.add_child(rock)
		var spin: Vector3 = Vector3(
			_rng.randf_range(-PI, PI),
			_rng.randf_range(-PI, PI),
			_rng.randf_range(-PI, PI))
		var fall_tw := create_tween().set_parallel(true)
		fall_tw.tween_property(rock, "position:y", size, 0.55) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		fall_tw.tween_property(rock, "rotation", spin, 0.55)
		var finish_tw := create_tween()
		finish_tw.tween_interval(0.55)
		finish_tw.tween_callback(_burst_at.bind(Vector3(x, size, z),
			10, Color(0.85, 0.78, 0.55, 1), size, 0.5))
		finish_tw.tween_callback(rock.queue_free)
		finish_tw.tween_callback(_drop_bounty_value.bind(50))
		total += 50
		await get_tree().create_timer(0.10).timeout
	# Climax boulder — huge
	await get_tree().create_timer(0.6).timeout
	var big := CSGSphere3D.new()
	big.radius = 2.0
	big.radial_segments = 16
	big.rings = 10
	var big_mat := StandardMaterial3D.new()
	big_mat.albedo_color = Color(0.55, 0.45, 0.32, 1)
	big_mat.emission_enabled = true
	big_mat.emission = big_mat.albedo_color * 0.3
	big.material = big_mat
	big.position = Vector3(0, 20.0, -3.0)
	popups_root.add_child(big)
	var big_tw := create_tween().set_parallel(true)
	big_tw.tween_property(big, "position:y", 2.0, 0.8) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	big_tw.tween_property(big, "rotation", Vector3(TAU, TAU * 0.5, TAU * 0.7), 0.8)
	await big_tw.finished
	_burst_at(Vector3(0, 1.5, -3.0), 48,
		Color(1.0, 0.85, 0.40, 1), 2.5, 1.2)
	_spawn_popup_3d(cowboy_3d.position + Vector3(0, 4.5, 0),
		"+1500 AVALANCHE", Color(1.0, 0.92, 0.30, 1), 84)
	big.queue_free()
	total += 1500
	_add_bounty(1500)
	await get_tree().create_timer(0.5).timeout
	_ceremony_finale("AVALANCHE", total)

# Iter 126: counterpart helper that just adds bounty (callable from
# tween chains where we don't need the full _drop_bonus_at visual).
func _drop_bounty_value(amount: int) -> void:
	_add_bounty(amount)

# ---- Rush H: Gumball Runaway (Extreme, Mountain alt) ------------------------
# A chaotic swarm of bright primary-colored gumballs bouncing across the
# road. Many small bursts compound into a sugar-storm feel.

func _rush_h_gumball_runaway() -> void:
	_ceremony_announce("STAMPEDE")
	await get_tree().create_timer(0.4).timeout
	const GUMBALL_COUNT: int = 40
	const PALETTE: Array[Color] = [
		Color(1.00, 0.20, 0.35, 1),  # red
		Color(1.00, 0.62, 0.10, 1),  # orange
		Color(1.00, 0.85, 0.20, 1),  # yellow
		Color(0.20, 0.95, 0.45, 1),  # green
		Color(0.20, 0.70, 1.00, 1),  # blue
		Color(0.65, 0.30, 1.00, 1),  # purple
		Color(1.00, 0.45, 0.85, 1),  # pink
	]
	var total: int = 0
	for i in range(GUMBALL_COUNT):
		var color: Color = PALETTE[i % PALETTE.size()]
		var start_x: float = _rng.randf_range(-3.5, 3.5)
		var start_z: float = _rng.randf_range(-12.0, -2.0)
		var start_y: float = _rng.randf_range(6.0, 14.0)
		var gum := CSGSphere3D.new()
		gum.radius = _rng.randf_range(0.20, 0.36)
		gum.radial_segments = 8
		gum.rings = 6
		var gm := StandardMaterial3D.new()
		gm.albedo_color = color
		gm.emission_enabled = true
		gm.emission = color * 1.2
		gum.material = gm
		gum.position = Vector3(start_x, start_y, start_z)
		popups_root.add_child(gum)
		# Bounce sequence: fall, half-bounce, fall, burst.
		var bounce1_y: float = _rng.randf_range(1.5, 3.5)
		var bounce_tw := create_tween()
		bounce_tw.tween_property(gum, "position:y", gum.radius, 0.35) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		bounce_tw.tween_property(gum, "position:y", bounce1_y, 0.20) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		bounce_tw.tween_property(gum, "position:y", gum.radius, 0.25) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		bounce_tw.tween_callback(_burst_at.bind(gum.position, 6, color, 0.6, 0.4))
		bounce_tw.tween_callback(gum.queue_free)
		bounce_tw.tween_callback(_drop_bounty_value.bind(50))
		total += 50
		# Tight stagger — chaos accelerates over time
		var stagger: float = 0.05 if i > 20 else 0.10
		await get_tree().create_timer(stagger).timeout
	# Center crescendo
	await get_tree().create_timer(0.6).timeout
	_burst_at(cowboy_3d.position + Vector3(0, 2.0, -2.0), 40,
		Color(1.0, 0.45, 0.85, 1), 2.0, 1.0)
	_spawn_popup_3d(cowboy_3d.position + Vector3(0, 4.5, 0),
		"+1000 GUMBALL!", Color(1.0, 0.92, 0.30, 1), 84)
	total += 1000
	_add_bounty(1000)
	await get_tree().create_timer(0.5).timeout
	_ceremony_finale("STAMPEDE", total)

# ---- Sugar Rush: JELLY_FRENZY (mid-level activation) ------------------------
# Iter 127: rainbow jelly-bean cascade. 80 mini-jelly-beans falling at
# random positions over 3 seconds with the full candy palette. Each
# lands with a sparkle pop. Mid-cascade: 5 BIG bonus jars drop. Finale:
# 60-sphere rainbow burst at cowboy.

func _play_sugar_rush_3d() -> void:
	_ceremony_announce("JELLY_FRENZY")
	await get_tree().create_timer(0.4).timeout
	const FRENZY_BEANS: int = 80
	const FRENZY_DURATION: float = 3.0
	const RAINBOW: Array[Color] = [
		Color(1.00, 0.32, 0.42, 1),
		Color(1.00, 0.62, 0.30, 1),
		Color(1.00, 0.85, 0.30, 1),
		Color(0.42, 0.95, 0.55, 1),
		Color(0.30, 0.80, 1.00, 1),
		Color(0.55, 0.45, 1.00, 1),
		Color(0.95, 0.55, 0.95, 1),
	]
	var total: int = 0
	var bean_interval: float = FRENZY_DURATION / float(FRENZY_BEANS)
	# 5 big-bonus-jar moments mid-cascade for crescendo punctuation.
	var big_bonus_marks: Array[int] = [10, 25, 40, 55, 70]
	for i in range(FRENZY_BEANS):
		var color: Color = RAINBOW[i % RAINBOW.size()]
		var x: float = _rng.randf_range(-3.0, 3.0)
		var z: float = _rng.randf_range(-12.0, 1.0)
		var bean := CSGSphere3D.new()
		bean.radius = 0.18
		bean.radial_segments = 8
		bean.rings = 6
		# Stretch into a jelly-bean shape
		bean.scale = Vector3(1.0, 0.7, 1.5)
		bean.rotation_degrees = Vector3(
			_rng.randf_range(0, 360),
			_rng.randf_range(0, 360),
			_rng.randf_range(0, 360))
		var bm := StandardMaterial3D.new()
		bm.albedo_color = color
		bm.emission_enabled = true
		bm.emission = color * 1.3
		bean.material = bm
		bean.position = Vector3(x, 9.0 + _rng.randf_range(0, 3.0), z)
		popups_root.add_child(bean)
		var bean_tw := create_tween().set_parallel(true)
		bean_tw.tween_property(bean, "position:y", 0.2, 0.45) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		bean_tw.tween_property(bean, "rotation",
			bean.rotation + Vector3(TAU, TAU * 0.5, TAU * 0.7), 0.45)
		var finish_tw := create_tween()
		finish_tw.tween_interval(0.45)
		finish_tw.tween_callback(_burst_at.bind(Vector3(x, 0.3, z),
			5, color, 0.5, 0.3))
		finish_tw.tween_callback(bean.queue_free)
		finish_tw.tween_callback(_drop_bounty_value.bind(30))
		total += 30
		# Punctuating big bonus jars
		if i in big_bonus_marks:
			var bonus_x: float = _rng.randf_range(-2.0, 2.0)
			var bonus_z: float = _rng.randf_range(-6.0, 0.0)
			_drop_bonus_at(Vector3(bonus_x, 0.0, bonus_z), 250,
				RAINBOW[(i + 3) % RAINBOW.size()])
			total += 250
		await get_tree().create_timer(bean_interval).timeout
	# Finale — 60-sphere rainbow burst at cowboy
	await get_tree().create_timer(0.6).timeout
	for i in range(7):
		_burst_at(cowboy_3d.position + Vector3(0, 2.0 + float(i) * 0.3, 0),
			9, RAINBOW[i], 1.5, 0.8)
		await get_tree().create_timer(0.08).timeout
	_spawn_popup_3d(cowboy_3d.position + Vector3(0, 5.0, 0),
		"+2000 SUGAR HIGH!", Color(1.0, 0.55, 0.85, 1), 84)
	total += 2000
	_add_bounty(2000)
	await get_tree().create_timer(0.6).timeout
	_ceremony_finale("JELLY_FRENZY", total)

# ---- iter 128: Bonus weapon previews ---------------------------------------
# Each weapon's preview spawns a banner + a short demo-fire pattern
# spawning visually-distinct bullet shapes/colors from cowboy. The cowboy
# sprite stays as the default jelly six-shooter wielder; weapon flair is
# all about the projectiles.

const WEAPON_3D_DATA: Dictionary = {
	"jelly_six_shooter": {
		"name": "JELLY SIX-SHOOTER", "color": Color(1.0, 0.40, 0.55, 1),
		"size": 0.18, "shots": 6, "pattern": "rapid", "value": 100,
	},
	"marshmallow_cannon": {
		"name": "MARSHMALLOW CANNON", "color": Color(0.98, 0.92, 0.85, 1),
		"size": 0.55, "shots": 3, "pattern": "heavy", "value": 600,
	},
	"liquorice_whip": {
		"name": "LIQUORICE WHIP", "color": Color(0.12, 0.06, 0.10, 1),
		"size": 0.22, "shots": 1, "pattern": "whip", "value": 400,
	},
	"frostbite_rifle": {
		"name": "FROSTBITE RIFLE", "color": Color(0.55, 0.85, 1.00, 1),
		"size": 0.24, "shots": 4, "pattern": "precision", "value": 500,
	},
	"sugar_mortar": {
		"name": "SUGAR MORTAR", "color": Color(1.00, 0.85, 0.30, 1),
		"size": 0.42, "shots": 3, "pattern": "arc", "value": 700,
	},
	"gumdrop_grenade": {
		"name": "GUMDROP GRENADE", "color": Color(0.55, 1.00, 0.55, 1),
		"size": 0.35, "shots": 3, "pattern": "lob", "value": 600,
	},
	"peppermint_shotgun": {
		"name": "PEPPERMINT SHOTGUN", "color": Color(1.0, 0.95, 0.95, 1),
		"size": 0.20, "shots": 7, "pattern": "spread", "value": 550,
	},
	"caramel_lasso": {
		"name": "CARAMEL LASSO", "color": Color(0.85, 0.55, 0.28, 1),
		"size": 0.16, "shots": 18, "pattern": "lasso", "value": 450,
	},
}

func _preview_weapon_3d(slug: String) -> void:
	var data: Dictionary = WEAPON_3D_DATA.get(slug, WEAPON_3D_DATA["jelly_six_shooter"])
	# Announce
	var ui_canvas: Node = get_node_or_null("UI")
	if ui_canvas != null:
		# Use the weapon name as the banner text (PRESETS will fall back
		# to using it as literal display text since it isn't a preset).
		FlourishBanner.spawn(ui_canvas, data.name)
	await get_tree().create_timer(0.6).timeout
	# Dispatch by pattern
	match data.pattern:
		"rapid":     await _weapon_fire_rapid(data)
		"heavy":     await _weapon_fire_heavy(data)
		"whip":      await _weapon_fire_whip(data)
		"precision": await _weapon_fire_precision(data)
		"arc":       await _weapon_fire_arc(data)
		"lob":       await _weapon_fire_lob(data)
		"spread":    await _weapon_fire_spread(data)
		"lasso":     await _weapon_fire_lasso(data)
		_:           await _weapon_fire_rapid(data)
	# Equipped flourish
	_spawn_popup_3d(cowboy_3d.position + Vector3(0, 4.5, 0),
		"EQUIPPED  +%d" % data.value, data.color, 80)
	_burst_at(cowboy_3d.position + Vector3(0, 2.0, 0), 14, data.color, 1.0, 0.7)
	_add_bounty(data.value)
	await get_tree().create_timer(0.8).timeout
	_show_preview_win("WEAPON: %s" % data.name)

# Shared weapon-bullet spawn — Sprite3D-style CSG sphere with emission
# at the given world position + outgoing velocity. Auto-despawns at z<-10.
func _weapon_spawn_projectile(start: Vector3, velocity: Vector3,
		color: Color, size: float, lifetime: float = 0.9) -> void:
	var b := CSGSphere3D.new()
	b.radius = size
	b.radial_segments = 10
	b.rings = 8
	var bm := StandardMaterial3D.new()
	bm.albedo_color = color
	bm.emission_enabled = true
	bm.emission = color * 1.4
	b.material = bm
	b.position = start
	popups_root.add_child(b)
	var dest: Vector3 = start + velocity * lifetime
	var tw := create_tween().set_parallel(true)
	tw.tween_property(b, "position", dest, lifetime) \
		.set_trans(Tween.TRANS_LINEAR)
	tw.tween_property(b, "scale", Vector3(0.6, 0.6, 0.6), lifetime) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	var free_tw: Tween = create_tween()
	free_tw.tween_interval(lifetime)
	free_tw.tween_callback(b.queue_free)

func _weapon_fire_rapid(data: Dictionary) -> void:
	# 6 fast straight shots forward
	for i in range(data.shots):
		_weapon_spawn_projectile(cowboy_3d.position + Vector3(0, 1.0, -0.3),
			Vector3(0, 0, -28.0), data.color, data.size, 0.7)
		await get_tree().create_timer(0.08).timeout

func _weapon_fire_heavy(data: Dictionary) -> void:
	# 3 BIG slow projectiles with deep punch
	for i in range(data.shots):
		var b := CSGSphere3D.new()
		b.radius = data.size
		b.radial_segments = 12
		b.rings = 10
		var bm := StandardMaterial3D.new()
		bm.albedo_color = data.color
		bm.emission_enabled = true
		bm.emission = data.color * 1.0
		b.material = bm
		b.position = cowboy_3d.position + Vector3(0, 1.0, -0.5)
		popups_root.add_child(b)
		var dest: Vector3 = b.position + Vector3(0, 0, -10.0)
		var tw := create_tween()
		tw.tween_property(b, "position", dest, 0.55) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_callback(_burst_at.bind(dest, 20, data.color, 1.4, 0.7))
		tw.tween_callback(b.queue_free)
		await get_tree().create_timer(0.4).timeout

func _weapon_fire_whip(data: Dictionary) -> void:
	# Single arc — a chain of small spheres rotates outward in a half-circle
	var chain_count: int = 18
	var radius: float = 3.0
	var pivot: Vector3 = cowboy_3d.position + Vector3(0, 1.0, -0.3)
	var spheres: Array[CSGSphere3D] = []
	for i in range(chain_count):
		var s := CSGSphere3D.new()
		s.radius = data.size * (1.0 - float(i) / float(chain_count) * 0.5)
		var sm := StandardMaterial3D.new()
		sm.albedo_color = data.color
		sm.emission_enabled = true
		sm.emission = data.color * 1.2
		s.material = sm
		s.position = pivot
		popups_root.add_child(s)
		spheres.append(s)
	# Sweep the chain
	var sweep_duration: float = 0.55
	var sweep_tw := create_tween().set_parallel(true)
	for i in range(chain_count):
		var sphere: CSGSphere3D = spheres[i]
		var t_segment: float = float(i) / float(chain_count - 1)
		var start_angle: float = -PI * 0.5
		var end_angle: float = PI * 0.5
		var ax := start_angle + (end_angle - start_angle) * t_segment
		var dist: float = radius * (0.3 + t_segment * 0.7)
		var target := pivot + Vector3(cos(ax) * dist, 0, sin(ax) * dist - dist)
		sweep_tw.tween_property(sphere, "position", target, sweep_duration) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await sweep_tw.finished
	for s in spheres:
		s.queue_free()
	_burst_at(pivot + Vector3(0, 0, -3.0), 12, data.color, 1.2, 0.5)

func _weapon_fire_precision(data: Dictionary) -> void:
	# 4 well-aimed shots, longer cooldown, frost trail
	for i in range(data.shots):
		_weapon_spawn_projectile(cowboy_3d.position + Vector3(0, 1.2, -0.3),
			Vector3(0, 0, -24.0), data.color, data.size, 1.0)
		# Frost trail — extra particles
		for j in range(3):
			_weapon_spawn_projectile(cowboy_3d.position + Vector3(
					_rng.randf_range(-0.3, 0.3), 1.0 + _rng.randf_range(-0.2, 0.2),
					-0.3 - float(j) * 0.4),
				Vector3(0, 0, -10.0), data.color * 0.7, data.size * 0.5, 0.6)
		await get_tree().create_timer(0.3).timeout

func _weapon_fire_arc(data: Dictionary) -> void:
	# Mortar — 3 high-arc shots that land + burst at z=-6 / -4 / -2
	for i in range(data.shots):
		var land_z: float = -6.0 + float(i) * 2.0
		var b := CSGSphere3D.new()
		b.radius = data.size
		var bm := StandardMaterial3D.new()
		bm.albedo_color = data.color
		bm.emission_enabled = true
		bm.emission = data.color * 1.0
		b.material = bm
		b.position = cowboy_3d.position + Vector3(0, 1.5, -0.3)
		popups_root.add_child(b)
		var apex: Vector3 = Vector3(0, 5.0, (b.position.z + land_z) * 0.5)
		var landing: Vector3 = Vector3(0, 0.4, land_z)
		var up_tw := create_tween().set_parallel(true)
		up_tw.tween_property(b, "position", apex, 0.35) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		await up_tw.finished
		var down_tw := create_tween()
		down_tw.tween_property(b, "position", landing, 0.30) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		down_tw.tween_callback(_burst_at.bind(landing, 16, data.color, 1.5, 0.6))
		down_tw.tween_callback(b.queue_free)
		await get_tree().create_timer(0.18).timeout

func _weapon_fire_lob(data: Dictionary) -> void:
	# 3 grenades lobbed forward, exploding in clusters
	for i in range(data.shots):
		var land_z: float = -4.0 - float(i) * 2.0
		var lateral_x: float = (float(i) - 1.0) * 1.2
		var b := CSGSphere3D.new()
		b.radius = data.size
		var bm := StandardMaterial3D.new()
		bm.albedo_color = data.color
		bm.emission_enabled = true
		bm.emission = data.color * 1.0
		b.material = bm
		b.position = cowboy_3d.position + Vector3(0, 1.5, -0.3)
		popups_root.add_child(b)
		var apex: Vector3 = Vector3(lateral_x * 0.6, 4.5, (b.position.z + land_z) * 0.5)
		var landing: Vector3 = Vector3(lateral_x, 0.4, land_z)
		var lob_tw := create_tween()
		lob_tw.tween_property(b, "position", apex, 0.30) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		lob_tw.tween_property(b, "position", landing, 0.30) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		lob_tw.tween_callback(_burst_at.bind(landing, 20, data.color, 1.6, 0.7))
		lob_tw.tween_callback(b.queue_free)
		await get_tree().create_timer(0.20).timeout

func _weapon_fire_spread(data: Dictionary) -> void:
	# Shotgun blast — 7 bullets fan out simultaneously
	var spread_arc: float = 1.0  # radians (~60°)
	var step: float = spread_arc / float(data.shots - 1)
	for i in range(data.shots):
		var angle: float = -spread_arc * 0.5 + float(i) * step
		var velocity: Vector3 = Vector3(sin(angle) * 24.0, 0, -cos(angle) * 24.0)
		_weapon_spawn_projectile(cowboy_3d.position + Vector3(0, 1.0, -0.3),
			velocity, data.color, data.size, 0.7)

func _weapon_fire_lasso(data: Dictionary) -> void:
	# Caramel lasso — a ring of small spheres spinning around cowboy at
	# expanding radius, then snapping forward as a unified spear.
	var ring_count: int = data.shots
	var spheres: Array[CSGSphere3D] = []
	var pivot: Vector3 = cowboy_3d.position + Vector3(0, 1.2, -0.3)
	for i in range(ring_count):
		var s := CSGSphere3D.new()
		s.radius = data.size
		var sm := StandardMaterial3D.new()
		sm.albedo_color = data.color
		sm.emission_enabled = true
		sm.emission = data.color * 1.3
		s.material = sm
		s.position = pivot
		popups_root.add_child(s)
		spheres.append(s)
	# Spin out
	var spin_dur: float = 0.5
	var spin_tw := create_tween().set_parallel(true)
	for i in range(ring_count):
		var a: float = float(i) / float(ring_count) * TAU
		var target := pivot + Vector3(cos(a) * 1.8, 0, sin(a) * 1.8)
		spin_tw.tween_property(spheres[i], "position", target, spin_dur) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await spin_tw.finished
	# Snap forward
	var snap_tw := create_tween().set_parallel(true)
	for sphere in spheres:
		var dest: Vector3 = sphere.position + Vector3(0, 0, -8.0)
		snap_tw.tween_property(sphere, "position", dest, 0.40) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await snap_tw.finished
	for s in spheres:
		s.queue_free()
	_burst_at(pivot + Vector3(0, 0, -8.0), 16, data.color, 1.4, 0.6)

# ---- iter 129: Bonus hero previews -----------------------------------------
# Each hero gets a stand-in sprite (color-coded CSG silhouette) spawned
# alongside the cowboy, a floating Label3D name banner above them, and a
# short signature-ability demo (double-volley / spin-attack / heal-pulse
# / etc). Until proper Veo or Tripo character art is generated, these
# placeholder visuals communicate role + tone.

const HERO_3D_DATA: Dictionary = {
	"marshmallow_sheriff": {
		"name": "MARSHMALLOW SHERIFF",
		"color": Color(0.98, 0.95, 0.90, 1),
		"trim":  Color(0.92, 0.20, 0.20, 1),  # red badge accent
		"ability": "double_volley",
		"value": 800,
	},
	"laughing_horse": {
		"name": "LAUGHING HORSE",
		"color": Color(0.55, 0.32, 0.18, 1),
		"trim":  Color(0.95, 0.85, 0.55, 1),
		"ability": "gallop_streak",
		"value": 700,
	},
	"scarecrow": {
		"name": "SCARECROW",
		"color": Color(0.85, 0.72, 0.32, 1),
		"trim":  Color(0.42, 0.22, 0.10, 1),
		"ability": "spin_attack",
		"value": 650,
	},
	"chocolate_outlaw": {
		"name": "CHOCOLATE OUTLAW",
		"color": Color(0.40, 0.22, 0.12, 1),
		"trim":  Color(0.85, 0.55, 0.30, 1),
		"ability": "dual_pistols",
		"value": 750,
	},
	"sugar_doc": {
		"name": "SUGAR DOC",
		"color": Color(1.00, 0.90, 0.95, 1),
		"trim":  Color(0.95, 0.30, 0.45, 1),
		"ability": "heal_pulse",
		"value": 850,
	},
	"taffy_kid": {
		"name": "TAFFY KID",
		"color": Color(1.00, 0.62, 0.30, 1),
		"trim":  Color(1.00, 0.85, 0.45, 1),
		"ability": "sticky_spread",
		"value": 600,
	},
}

func _preview_hero_3d(slug: String) -> void:
	var data: Dictionary = HERO_3D_DATA.get(slug, HERO_3D_DATA["marshmallow_sheriff"])
	# Announce
	var ui_canvas: Node = get_node_or_null("UI")
	if ui_canvas != null:
		FlourishBanner.spawn(ui_canvas, data.name)
	await get_tree().create_timer(0.5).timeout
	# Iter 143: hero preview uses the actual hero PNG via Sprite3D billboard.
	# Iter 129 used color-coded CSG boxes as placeholders; the PNGs have
	# existed since iter 131 but the preview was never updated to use them
	# (user reported "debug menu heroes — still polygons, PNGs not showing").
	var hero := Node3D.new()
	hero.position = cowboy_3d.position + Vector3(1.2, 0.0, 0.0)
	subviewport.add_child(hero)
	var hero_png_path := "res://assets/sprites/props/hero_%s.png" % slug
	if ResourceLoader.exists(hero_png_path):
		var hero_sprite := Sprite3D.new()
		hero_sprite.texture = load(hero_png_path)
		hero_sprite.pixel_size = 2.0 / float(hero_sprite.texture.get_height())
		hero_sprite.billboard = 1  # BILLBOARD_ENABLED
		hero_sprite.alpha_cut = 1  # ALPHA_CUT_DISCARD
		hero_sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		hero_sprite.position = Vector3(0, 1.0, 0)
		hero.add_child(hero_sprite)
	else:
		# Fallback: legacy CSG box (in case the hero PNG is missing)
		var body := CSGBox3D.new()
		body.size = Vector3(0.5, 1.2, 0.4)
		var body_mat := StandardMaterial3D.new()
		body_mat.albedo_color = data.color
		body.material = body_mat
		body.position = Vector3(0, 0.6, 0)
		hero.add_child(body)
	# Floating name plate
	var name_label := Label3D.new()
	name_label.text = data.name
	name_label.font_size = 56
	name_label.outline_size = 8
	name_label.modulate = Color(1.0, 0.92, 0.55, 1)
	name_label.billboard = 1  # BILLBOARD_ENABLED
	name_label.position = Vector3(0, 2.0, 0)
	hero.add_child(name_label)
	# Entry pop — scale from 0 to 1 with TRANS_BACK
	hero.scale = Vector3.ZERO
	var entry_tw := create_tween()
	entry_tw.tween_property(hero, "scale", Vector3.ONE, 0.35) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await entry_tw.finished
	# Ability demo
	match data.ability:
		"double_volley":  await _hero_double_volley(hero, data)
		"gallop_streak":  await _hero_gallop_streak(hero, data)
		"spin_attack":    await _hero_spin_attack(hero, data)
		"dual_pistols":   await _hero_dual_pistols(hero, data)
		"heal_pulse":     await _hero_heal_pulse(hero, data)
		"sticky_spread":  await _hero_sticky_spread(hero, data)
	# Exit + unlock flourish
	await get_tree().create_timer(0.4).timeout
	_spawn_popup_3d(hero.position + Vector3(0, 3.0, 0),
		"UNLOCKED  +%d" % data.value, data.trim, 80)
	_burst_at(hero.position + Vector3(0, 1.0, 0), 18, data.color, 1.2, 0.7)
	_add_bounty(data.value)
	# Hero departs
	var exit_tw := create_tween()
	exit_tw.tween_property(hero, "scale", Vector3.ZERO, 0.25) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	await exit_tw.finished
	hero.queue_free()
	await get_tree().create_timer(0.4).timeout
	_show_preview_win("HERO: %s" % data.name)

# ---- Hero ability demos ----------------------------------------------------

func _hero_double_volley(hero: Node3D, data: Dictionary) -> void:
	# Two parallel bullets per shot, double the throughput.
	for i in range(5):
		for x_off in [-0.25, 0.25]:
			_weapon_spawn_projectile(hero.position + Vector3(x_off, 1.0, 0),
				Vector3(0, 0, -22.0), data.trim, 0.18, 0.7)
		await get_tree().create_timer(0.12).timeout

func _hero_gallop_streak(hero: Node3D, data: Dictionary) -> void:
	# Forward sweep — hero (mounted) dashes forward, leaves dust trail.
	var start: Vector3 = hero.position
	var end: Vector3 = start + Vector3(0, 0, -3.5)
	var dash_tw := create_tween()
	dash_tw.tween_property(hero, "position", end, 0.30) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	for i in range(8):
		_burst_at(hero.position + Vector3(_rng.randf_range(-0.3, 0.3),
			0.2, _rng.randf_range(-0.3, 0.3)),
			4, Color(0.78, 0.65, 0.48, 1), 0.5, 0.4)
		await get_tree().create_timer(0.05).timeout
	await dash_tw.finished
	# Return
	var back_tw := create_tween()
	back_tw.tween_property(hero, "position", start, 0.35) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await back_tw.finished

func _hero_spin_attack(hero: Node3D, data: Dictionary) -> void:
	# Ring of 12 small bullets fanning out 360°
	var pivot: Vector3 = hero.position + Vector3(0, 1.0, 0)
	for i in range(12):
		var a: float = float(i) / 12.0 * TAU
		var velocity: Vector3 = Vector3(cos(a) * 14.0, 0, sin(a) * 14.0)
		_weapon_spawn_projectile(pivot, velocity, data.trim, 0.18, 0.8)
	# Hero spin animation
	var spin_tw := create_tween()
	spin_tw.tween_property(hero, "rotation:y", hero.rotation.y + TAU, 0.6)
	await spin_tw.finished

func _hero_dual_pistols(hero: Node3D, data: Dictionary) -> void:
	# Alternating L/R rapid pistol shots
	for i in range(8):
		var x_off: float = -0.30 if i % 2 == 0 else 0.30
		_weapon_spawn_projectile(hero.position + Vector3(x_off, 0.9, 0),
			Vector3(0, 0, -26.0), data.trim, 0.16, 0.7)
		await get_tree().create_timer(0.08).timeout

func _hero_heal_pulse(hero: Node3D, data: Dictionary) -> void:
	# 3 outward shockwave rings of green-pink particles around the cowboy
	for pulse in range(3):
		var pulse_center: Vector3 = cowboy_3d.position + Vector3(0, 1.0, 0)
		for i in range(20):
			var a: float = float(i) / 20.0 * TAU
			var p := CSGSphere3D.new()
			p.radius = 0.10
			var pm := StandardMaterial3D.new()
			pm.albedo_color = data.trim
			pm.emission_enabled = true
			pm.emission = data.trim * 1.8
			p.material = pm
			p.position = pulse_center
			popups_root.add_child(p)
			var target: Vector3 = pulse_center + Vector3(cos(a) * 2.5, 0, sin(a) * 2.5)
			var pt := create_tween().set_parallel(true)
			pt.tween_property(p, "position", target, 0.55) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			pt.tween_property(p, "scale", Vector3.ZERO, 0.55)
			var ft: Tween = create_tween()
			ft.tween_interval(0.55)
			ft.tween_callback(p.queue_free)
		await get_tree().create_timer(0.30).timeout
	# Heart popup
	_spawn_popup_3d(cowboy_3d.position + Vector3(0, 3.0, 0),
		"+1 HEART", data.trim, 64)

func _hero_sticky_spread(hero: Node3D, data: Dictionary) -> void:
	# Spread of sticky balls that arc + settle on the ground (no despawn)
	for i in range(7):
		var angle: float = -PI * 0.3 + float(i) / 6.0 * (PI * 0.6)
		var b := CSGSphere3D.new()
		b.radius = 0.22
		b.radial_segments = 8
		b.rings = 6
		var bm := StandardMaterial3D.new()
		bm.albedo_color = data.color
		bm.emission_enabled = true
		bm.emission = data.trim * 0.8
		b.material = bm
		b.position = hero.position + Vector3(0, 1.0, 0)
		popups_root.add_child(b)
		var dist: float = 4.0
		var landing: Vector3 = hero.position + Vector3(sin(angle) * dist,
			0.22, -cos(angle) * dist)
		var apex: Vector3 = Vector3(
			(b.position.x + landing.x) * 0.5,
			3.0,
			(b.position.z + landing.z) * 0.5)
		var arc_tw := create_tween()
		arc_tw.tween_property(b, "position", apex, 0.25) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		arc_tw.tween_property(b, "position", landing, 0.25) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		# Sticky linger — fade out over 1.2s where it landed
		arc_tw.tween_property(b, "scale", Vector3(1.5, 0.3, 1.5), 0.2)
		arc_tw.tween_property(b, "scale", Vector3.ZERO, 1.0) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		arc_tw.tween_callback(b.queue_free)
	await get_tree().create_timer(0.7).timeout

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
			# Multiplicative — iter 144: pool [2, 3, 5] (was capped at ×2).
			# User: "add in a x5 gate so I can get enough posse members to
			# kill Pete." MAX_VISIBLE_FOLLOWERS already caps the visible tail
			# (the iter-119 problem was visual explosion, not logic). Weighted
			# so ×2 stays most common, ×5 is the jackpot.
			var mult_pool: Array[int] = [2, 2, 2, 3, 3, 5]
			values.append(mult_pool[_rng.randi() % mult_pool.size()])
			operators.append("×")
	gate.set_meta("left_value", values[0])
	gate.set_meta("left_op", operators[0])
	gate.set_meta("right_value", values[1])
	gate.set_meta("right_op", operators[1])
	gate.set_meta("triggered", false)
	# Iter 113: per-door HP-style hit counter. Each bullet adds 1 to the
	# counter; only every GATE_HITS_PER_STEP decrements the displayed
	# value. Without this, 5-posse fire-rate (15-20 bullets per gate flight)
	# pummels every gate to 0 before the player can choose a side.
	gate.set_meta("left_hits", 0)
	gate.set_meta("right_hits", 0)
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
	# Iter 123: port the 2D level's gate-pass flourishes into 3D.
	# Combo counter ticks on every gate; banner preset by streak depth.
	# Plus a sugar-rush 'JELLY_FRENZY' when the posse first crosses 50,
	# matching the 2D 'Jelly Bean Frenzy' threshold beat.
	_gate_combo_count += 1
	_gate_combo_decay = GATE_COMBO_DECAY_TIME
	var combo_preset: String = ""
	if _gate_combo_count >= 5:
		combo_preset = "RAMPAGE!"
	elif _gate_combo_count >= 3:
		combo_preset = "MEGA!"
	elif _gate_combo_count >= 2:
		combo_preset = "DOUBLE!"
	# Single quality flourish — only when gain was meaningful.
	if combo_preset == "":
		var gain: int = _posse_count_3d - before
		if op == "×" and value >= 2:
			combo_preset = "TASTY!"
		elif gain >= 5:
			combo_preset = "SWEET!"
		elif gain >= 1 and _gate_combo_count == 1:
			combo_preset = "JUICY!"
	if combo_preset != "":
		var ui_canvas: Node = get_node_or_null("UI")
		if ui_canvas != null:
			FlourishBanner.spawn(ui_canvas, combo_preset)
	# Sugar Rush threshold — first time posse crosses 50, fire JELLY_FRENZY.
	if before < 50 and _posse_count_3d >= 50:
		var ui_canvas2: Node = get_node_or_null("UI")
		if ui_canvas2 != null:
			FlourishBanner.spawn(ui_canvas2, "JELLY_FRENZY")
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
		_followers.append(_make_follower(_followers.size()))

# ---- Iter 149: special posse members (rescued heroes) ----------------------
# Rescued heroes persist as distinct units: own PNG, a hero skill on a timer,
# and HP — killable by outlaw ranged fire and Pete/pusher melee.
var _special_followers: Array[Dictionary] = []
const SPECIAL_FOLLOWER_HP: int = 6
const SPECIAL_FOLLOWER_HIT_RADIUS_SQ: float = 0.85 * 0.85
# Formation slots flanking the leader — heroes ride at the posse front.
const SPECIAL_FORMATION: Array[Vector3] = [
	Vector3(1.5, 0.0, 0.1), Vector3(-1.5, 0.0, 0.1),
	Vector3(2.3, 0.0, 0.8), Vector3(-2.3, 0.0, 0.8),
	Vector3(1.5, 0.0, 1.5), Vector3(-1.5, 0.0, 1.5),
]
const HERO_SKILL_INTERVAL: Dictionary = {
	"marshmallow_sheriff": 3.5, "laughing_horse": 4.5, "scarecrow": 2.8,
	"chocolate_outlaw": 1.0, "sugar_doc": 7.0, "taffy_kid": 1.8,
}

func _add_special_follower(slug: String) -> void:
	if cowboy_3d == null or not is_instance_valid(cowboy_3d):
		return
	var tex_path := "res://assets/sprites/props/hero_%s.png" % slug
	if not ResourceLoader.exists(tex_path):
		DebugLog.add("special follower SKIPPED — no PNG for %s" % slug)
		return
	var spr := Sprite3D.new()
	spr.texture = load(tex_path)
	# Size to 125% of the cowboy's on-screen height. The cowboy is now a
	# video billboard (its texture is a viewport, not the figure), so use
	# a fixed nominal height rather than texture-height × pixel_size.
	var cowboy_h: float = 0.95
	spr.pixel_size = (cowboy_h * 1.25) / float(spr.texture.get_height())
	spr.billboard = 1
	spr.alpha_cut = 1
	spr.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var slot: Vector3 = SPECIAL_FORMATION[_special_followers.size() % SPECIAL_FORMATION.size()]
	spr.position = Vector3(cowboy_3d.position.x + slot.x, 1.2,
		cowboy_3d.position.z + slot.z)
	subviewport.add_child(spr)
	var interval: float = HERO_SKILL_INTERVAL.get(slug, 3.0)
	_special_followers.append({
		"node": spr, "slug": slug,
		"hp": SPECIAL_FOLLOWER_HP, "max_hp": SPECIAL_FOLLOWER_HP,
		"skill_timer": interval, "skill_interval": interval, "slot": slot,
	})
	DebugLog.add("special follower joined: %s (%d total)" % [slug, _special_followers.size()])

# Per-frame: formation-follow the leader + tick each hero's skill timer.
func _update_special_followers(delta: float) -> void:
	if cowboy_3d == null or not is_instance_valid(cowboy_3d):
		return
	var i: int = 0
	while i < _special_followers.size():
		var e: Dictionary = _special_followers[i]
		var node: Sprite3D = e["node"]
		if node == null or not is_instance_valid(node):
			_special_followers.remove_at(i)
			continue
		var slot: Vector3 = e["slot"]
		var target := Vector3(cowboy_3d.position.x + slot.x, node.position.y,
			cowboy_3d.position.z + slot.z)
		node.position = node.position.lerp(target, clampf(4.0 * delta, 0.0, 1.0))
		e["skill_timer"] = float(e["skill_timer"]) - delta
		if float(e["skill_timer"]) <= 0.0:
			e["skill_timer"] = e["skill_interval"]
			_special_follower_skill(e)
		i += 1

func _special_follower_skill(e: Dictionary) -> void:
	var node: Sprite3D = e["node"]
	if node == null or not is_instance_valid(node):
		return
	match String(e["slug"]):
		"marshmallow_sheriff":
			# Marshmallow Cannon — wide AOE, eliminates up to 6.
			_hero_strike(node, 6, 5.0, Color(1.0, 0.92, 0.85, 1), 0.55)
		"laughing_horse":
			# Stun Whinny — cyan ring, neutralizes up to 3.
			_hero_strike(node, 3, 4.2, Color(0.55, 0.92, 1.0, 1), 0.4)
		"scarecrow":
			# Straw Sweep — forward arc melee, up to 4.
			_hero_strike(node, 4, 3.4, Color(0.85, 0.72, 0.30, 1), 0.45)
		"chocolate_outlaw":
			# Dual jelly-bean pistols — fast, 2 nearest.
			_hero_strike(node, 2, 7.0, Color(0.55, 0.32, 0.18, 1), 0.3)
		"taffy_kid":
			# Slingshot spread — 3 nearest.
			_hero_strike(node, 3, 6.0, Color(1.0, 0.65, 0.25, 1), 0.32)
		"sugar_doc":
			# Heal Pulse — restore a posse member instead of attacking.
			_posse_count_3d += 1
			_sync_followers_to_count(_posse_count_3d)
			_refresh_hud()
			_burst_at(node.position + Vector3(0, 1.0, 0), 16,
				Color(1.0, 0.7, 0.85, 1), 1.3, 0.7)
			_spawn_popup_3d(node.position + Vector3(0, 2.2, 0),
				"+1 POSSE", Color(1.0, 0.7, 0.85, 1), 56)

# Shared offensive skill — eliminate up to `count` outlaws within `max_dist`
# of the hero, with a coloured burst at each + a projectile streak from the
# hero to the target.
func _hero_strike(from_node: Node3D, count: int, max_dist: float,
		vfx_color: Color, proj_size: float) -> void:
	var origin: Vector3 = from_node.position
	var targets: Array = []
	for ob in outlaws_root.get_children():
		if not (ob is Node3D):
			continue
		if ob.get_meta("is_captive", false) or ob.get_meta("dying", false):
			continue
		var d: float = origin.distance_to((ob as Node3D).position)
		if d <= max_dist:
			targets.append({"node": ob, "dist": d})
	targets.sort_custom(func(a, b): return a["dist"] < b["dist"])
	var struck: int = 0
	for entry in targets:
		if struck >= count:
			break
		var ob: Node3D = entry["node"]
		if not is_instance_valid(ob):
			continue
		_weapon_spawn_projectile(origin + Vector3(0, 1.0, 0),
			(ob.position - origin) / 0.25, vfx_color, proj_size, 0.25)
		_burst_at(ob.position + Vector3(0, 0.8, 0), 12, vfx_color, 1.1, 0.6)
		_skill_kill_outlaw(ob)
		struck += 1

# Eliminate an outlaw the same way a posse bullet's killing blow does —
# swap to the death stream + delayed free so the death anim plays.
func _skill_kill_outlaw(outlaw: Node3D) -> void:
	if outlaw.get_meta("is_pusher", false):
		_pusher_take_damage(outlaw)
		return
	outlaw.set_meta("hp", 0)
	outlaw.set_meta("dying", true)
	outlaw.set_meta("death_timer", VAGRANT_DEATH_LIFETIME)
	var death_sprite: Sprite3D = outlaw.get_meta("sprite_3d", null)
	if death_sprite != null and is_instance_valid(death_sprite):
		var death_sv: SubViewport = _get_or_create_shared_video_viewport(VAGRANT_DEATH_STREAM)
		death_sprite.texture = death_sv.get_texture()
	_hits += 1
	_refresh_hud()

# Outlaw fire / melee damages a special follower. Removes it on HP 0.
func _damage_special_follower(e: Dictionary, dmg: int) -> void:
	e["hp"] = int(e["hp"]) - dmg
	var node: Sprite3D = e["node"]
	if node != null and is_instance_valid(node):
		node.modulate = Color(1.7, 1.2, 1.2, 1)
		var tw: Tween = node.create_tween()
		tw.tween_property(node, "modulate", Color(1, 1, 1, 1), 0.25)
		_spawn_popup_3d(node.position + Vector3(0, 2.2, 0),
			"-%d" % dmg, Color(1, 0.4, 0.3, 1), 48)
	if int(e["hp"]) <= 0:
		_kill_special_follower(e)

func _kill_special_follower(e: Dictionary) -> void:
	var node: Sprite3D = e["node"]
	if node != null and is_instance_valid(node):
		_burst_at(node.position + Vector3(0, 0.8, 0), 22,
			Color(0.9, 0.3, 0.3, 1), 1.5, 0.8)
		_spawn_popup_3d(node.position + Vector3(0, 2.4, 0),
			"%s DOWN" % String(e["slug"]).to_upper().replace("_", " "),
			Color(1, 0.4, 0.3, 1), 52)
		node.queue_free()
	_special_followers.erase(e)
	DebugLog.add("special follower KILLED: %s (%d left)" % [e["slug"], _special_followers.size()])

# Closest special follower to a world point within `radius` (or empty).
func _nearest_special_follower(point: Vector3, radius: float) -> Dictionary:
	var best: Dictionary = {}
	var best_d: float = radius
	for e in _special_followers:
		var node: Sprite3D = e["node"]
		if node == null or not is_instance_valid(node):
			continue
		var d: float = point.distance_to(node.position)
		if d < best_d:
			best_d = d
			best = e
	return best

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
const PETE_FORWARD_STREAM := preload("res://assets/videos/pete/steps_forward.ogv")
const PETE_SHOOT_STREAM := preload("res://assets/videos/pete/shoots_at_player.ogv")
const PETE_HIT_STREAM := preload("res://assets/videos/pete/hit_by_gunfire.ogv")
const PETE_SHOUT_STREAM := preload("res://assets/videos/pete/shouts.ogv")
const PETE_CELEBRATE_STREAM := preload("res://assets/videos/pete/celebrate.ogv")
const PETE_COMPLAINS_STREAM := preload("res://assets/videos/pete/complains.ogv")
const PETE_DEATH_STREAM := preload("res://assets/videos/pete/death.ogv")

# Iter 146: Pete animation state machine. Helper to swap his video billboard
# texture to a different stream's SubViewport without recreating the sprite.
# Stores the active anim slug as meta + a return-to-idle timer.
func _set_pete_anim(pete: Node3D, stream: VideoStream, duration: float = 0.0) -> void:
	var sprite: Sprite3D = pete.get_meta("video_sprite", null) as Sprite3D
	if sprite == null:
		return
	var sv: SubViewport = _get_or_create_shared_video_viewport(stream)
	sprite.texture = sv.get_texture()
	pete.set_meta("anim_revert_t", duration)

func _spawn_pete() -> void:
	# Iter 109: video-driven billboard using pete/taps_foot_idle.ogv +
	# chromakey shader (matches the 2D gameplay outlaw.tscn pattern).
	# Iter 146: state machine wired — IDLE default, SHOOT on fire,
	# SHOUT on taunt, HIT on damage, FORWARD during approach.
	var pete := Node3D.new()
	# Iter 137: Pete sizing fix. cowboy_3d uses pixel_size=0.002 against
	# a ~1024px-tall texture → cowboy is ~2.0 world units tall. User wants
	# Pete 3-4× cowboy = 6-8 units. Settled on 7.0 (3.5× cowboy). y=3.5
	# so feet touch ground. Previous 16.8 was ~8.4× — visually "30× cowboy"
	# because the close camera magnified the silhouette.
	var pete_height: float = 7.0
	pete.position = Vector3(0.0, pete_height * 0.5, OBSTACLE_SPAWN_Z + 4.0)
	pete.set_meta("hp", PETE_HP)
	pete.set_meta("hp_max", PETE_HP)
	pete.set_meta("boss_kind", "pete")
	boss_root.add_child(pete)
	var billboard: Node3D = _make_video_billboard(PETE_IDLE_STREAM, pete_height)
	pete.add_child(billboard)
	# Iter 146: store the Sprite3D so the anim state machine can swap its
	# texture between stream viewports.
	if billboard.get_child_count() > 0:
		var sprite: Sprite3D = billboard.get_child(0) as Sprite3D
		if sprite != null:
			pete.set_meta("video_sprite", sprite)
	pete.set_meta("anim_revert_t", 0.0)
	DebugLog.add("pete spawned at (%.1f, %.1f, %.1f), HP=%d, height=%.1f" % [pete.position.x, pete.position.y, pete.position.z, PETE_HP, pete_height])
	# Iter 146: play arrival intro voice + shout animation.
	if get_node_or_null("/root/AudioBus") and AudioBus.has_method("play_character_line"):
		AudioBus.play_character_line("pete_intro")
	_set_pete_anim(pete, PETE_SHOUT_STREAM, 2.5)
	# Iter 144: HP bar lives on 2D HUD (top of screen) instead of attached
	# to Pete in 3D. With Pete head at world y=7 = camera y=7 and a -55°
	# pitch, anything at Pete's head height or above is off-screen at the
	# top. 2D HUD overlay is always visible regardless of 3D position.
	# Keep a small 3D name plate above Pete so the player can identify
	# which enemy is the boss.
	var name_plate := Label3D.new()
	name_plate.text = "BOSS"
	name_plate.font_size = 64
	name_plate.outline_size = 10
	name_plate.modulate = Color(1, 0.45, 0.30, 1)
	name_plate.position = Vector3(0, 0.5, 0.6)
	pete.add_child(name_plate)
	_install_pete_hud(pete)
	info_label.text = "BOSS APPEARS — SHOOT PETE"

# Iter 144: build the 2D HUD overlay for Pete's HP bar — anchored to top
# of UI CanvasLayer, always visible. Stores refs in pete meta for refresh.
func _install_pete_hud(pete: Node3D, boss_name: String = "SLIPPERY PETE") -> void:
	var ui_canvas: CanvasLayer = get_node_or_null("UI") as CanvasLayer
	if ui_canvas == null:
		return
	var hud := Control.new()
	hud.name = "PeteHPHUD"
	hud.anchor_left = 0.0
	hud.anchor_right = 1.0
	hud.anchor_top = 0.0
	hud.anchor_bottom = 0.0
	hud.offset_top = 70.0
	hud.offset_bottom = 220.0
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var name_label := Label.new()
	name_label.text = boss_name
	name_label.anchor_left = 0.0
	name_label.anchor_right = 1.0
	name_label.offset_top = 0.0
	name_label.offset_bottom = 80.0
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 56)
	name_label.add_theme_color_override("font_color", Color(1, 0.45, 0.30, 1))
	name_label.add_theme_color_override("font_outline_color", Color(0.18, 0.10, 0.05, 1))
	name_label.add_theme_constant_override("outline_size", 10)
	hud.add_child(name_label)
	var hp_bg := ColorRect.new()
	hp_bg.color = Color(0.05, 0.05, 0.05, 0.90)
	hp_bg.anchor_left = 0.10
	hp_bg.anchor_right = 0.90
	hp_bg.anchor_top = 0.0
	hp_bg.anchor_bottom = 0.0
	hp_bg.offset_top = 90.0
	hp_bg.offset_bottom = 130.0
	hud.add_child(hp_bg)
	var hp_fg := ColorRect.new()
	hp_fg.color = Color(0.35, 0.85, 0.32, 1)
	hp_fg.anchor_left = 0.10
	hp_fg.anchor_right = 0.90
	hp_fg.anchor_top = 0.0
	hp_fg.anchor_bottom = 0.0
	hp_fg.offset_top = 94.0
	hp_fg.offset_bottom = 126.0
	hud.add_child(hp_fg)
	ui_canvas.add_child(hud)
	pete.set_meta("hp_hud", hud)
	pete.set_meta("hp_hud_fg", hp_fg)

func _refresh_pete_hp(pete: Node3D) -> void:
	var fg: ColorRect = pete.get_meta("hp_hud_fg", null) as ColorRect
	if fg == null or not is_instance_valid(fg):
		return
	var hp_max: int = pete.get_meta("hp_max", PETE_HP)
	var hp: int = pete.get_meta("hp", hp_max)
	var pct: float = float(maxi(hp, 0)) / float(maxi(hp_max, 1))
	# Bar fills from left edge (0.10) to right edge (0.90). New right anchor
	# = 0.10 + 0.80 * pct so bar shrinks from the right side as HP drops.
	fg.anchor_right = 0.10 + 0.80 * pct
	# Color: green > 60%, yellow > 30%, red below.
	if pct > 0.6:
		fg.color = Color(0.35, 0.85, 0.32, 1)
	elif pct > 0.3:
		fg.color = Color(0.95, 0.85, 0.25, 1)
	else:
		fg.color = Color(0.95, 0.25, 0.25, 1)

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
	# Iter 146: swap to SHOOT animation during fire, revert to IDLE in 0.6s
	# (handled by _process tick on anim_revert_t).
	_set_pete_anim(pete, PETE_SHOOT_STREAM, 0.6)
	var gun_offset_x: float = -0.6 if (_pete_fire_count % 2 == 0) else 0.6
	var orig_pos: Vector3 = pete.position
	pete.position = orig_pos + Vector3(gun_offset_x, 0, 0)
	_outlaw_fire(pete)
	pete.position = orig_pos
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
	# Iter 146: SHOUT animation flash + voice line. Bubble lowered from
	# Pete's head (y+4 = off-screen at top) to chest level so the user
	# actually sees the banter.
	_set_pete_anim(pete, PETE_SHOUT_STREAM, 1.5)
	if get_node_or_null("/root/AudioBus") and AudioBus.has_method("play_character_line"):
		AudioBus.play_character_line("pete_intro")  # reuse intro until per-taunt clips exist
	var bubble := Label3D.new()
	bubble.text = line
	bubble.font_size = 56
	bubble.outline_size = 12
	bubble.modulate = Color(1, 0.92, 0.55, 1)
	bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	bubble.no_depth_test = true
	bubble.position = pete.position + Vector3(0, 0.5, 0.8)
	popups_root.add_child(bubble)
	var t := create_tween().set_parallel(true)
	t.tween_property(bubble, "position:y",
		bubble.position.y + 2.0, 1.8) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(bubble, "modulate:a", 0.0, 1.8) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.chain().tween_callback(bubble.queue_free)

# ===========================================================================
# Iter 157: The Candy Rustler — level-2 boss.
# ===========================================================================

# Which boss spawns this run. Level 2 → The Candy Rustler; all else → Pete.
func _boss_kind() -> String:
	var lvl: int = 1
	if get_node_or_null("/root/GameState") != null:
		lvl = GameState.current_level
	return "rustler" if lvl == 2 else "pete"

# Spawn The Candy Rustler. Mirrors _spawn_pete's framing (a Node3D in
# boss_root + the 2D HUD HP bar) but the billboard wraps the jointed rig
# instead of a video, and the boss HP is mirrored onto the rig so its
# piece-detachment thresholds track the on-screen bar.
func _spawn_candy_rustler() -> void:
	var boss := Node3D.new()
	# Iter 163: 7.5 → 5.0 — at 7.5 his head clipped off the top of the
	# screen at the duel distance (camera sits at y=7). y tracks height:
	# the v1 figure is centred in its viewport, so the billboard centre
	# sits at the figure's mid-height (~0.45 × height puts feet on dirt).
	var boss_height: float = 5.0
	boss.position = Vector3(0.0, 2.25, OBSTACLE_SPAWN_Z + 4.0)
	boss.set_meta("hp", RUSTLER_HP)
	boss.set_meta("hp_max", RUSTLER_HP)
	boss.set_meta("boss_kind", "rustler")
	boss_root.add_child(boss)
	var bb: Dictionary = _make_rig_billboard(boss_height)
	boss.add_child(bb["wrap"])
	var rig = bb["rig"]
	if rig != null:
		# The rig defaults to max_hp 12 (preview scale). Rescale to the
		# boss HP so one bullet = take_damage(1) and the 75/50/25%
		# detach thresholds line up with the on-screen HP bar.
		rig.max_hp = RUSTLER_HP
		rig.hp = RUSTLER_HP
	boss.set_meta("rig", rig)
	boss.set_meta("viewport", bb["viewport"])
	var name_plate := Label3D.new()
	name_plate.text = "THE CANDY RUSTLER"
	name_plate.font_size = 44
	name_plate.outline_size = 9
	name_plate.modulate = Color(0.98, 0.55, 0.30, 1)
	name_plate.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	name_plate.no_depth_test = true
	name_plate.position = Vector3(0, 0.6, 0.6)
	boss.add_child(name_plate)
	_install_pete_hud(boss, "THE CANDY RUSTLER")
	_refresh_pete_hp(boss)
	info_label.text = "BOSS — THE CANDY RUSTLER"
	_rustler_say(boss, "intro")
	DebugLog.add("candy rustler spawned at z=%.1f, HP=%d" % [boss.position.z, RUSTLER_HP])

# Build the rig billboard. The rig (a Node2D puppet) lives in a top-level
# SubViewport — NOT nested in the game viewport (nested SubViewports fail
# on Android Vulkan; the iter 116 constraint). A Sprite3D samples that
# viewport's texture. Returns { wrap, rig, viewport }.
func _make_rig_billboard(world_height: float) -> Dictionary:
	var sv := SubViewport.new()
	sv.size = _RUSTLER_VIEWPORT_PX
	sv.transparent_bg = true
	sv.disable_3d = true
	sv.render_target_update_mode = 4  # SubViewport.UPDATE_ALWAYS
	add_child(sv)
	var rig = _CANDY_RUSTLER_RIG.new()
	rig.scale = _RUSTLER_RIG_SCALE
	rig.position = _RUSTLER_RIG_POS
	sv.add_child(rig)
	var wrap := Node3D.new()
	var sprite := Sprite3D.new()
	sprite.texture = sv.get_texture()
	sprite.pixel_size = world_height / float(_RUSTLER_VIEWPORT_PX.y)
	sprite.billboard = 1   # BILLBOARD_ENABLED
	sprite.alpha_cut = 0   # rig pieces already carry alpha — blend, don't clip
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	wrap.add_child(sprite)
	return {"wrap": wrap, "rig": rig, "viewport": sv}

# Candy Rustler per-frame behavior (iter 163): a melee boss — strides in
# fast, holds at RUSTLER_STAY_Z and crinkles the posse by contact (no
# projectiles). Takes bullet hits → the rig dismantles; on HP 0 the rig
# scatters and the WIN flow runs.
func _process_rustler(boss: Node3D, delta: float) -> void:
	if _pete_defeated or boss.get_meta("dying", false):
		return
	_rustler_hit_voice_cd = maxf(0.0, _rustler_hit_voice_cd - delta)
	var rig = boss.get_meta("rig", null)
	if boss.position.z < RUSTLER_STAY_Z:
		boss.position.z += RUSTLER_SPEED * delta
	else:
		# Engaged — drain the posse by melee contact. Special followers
		# soak the hit first (as with Pete's melee phase).
		_rustler_melee_accum += delta * RUSTLER_MELEE_DPS
		while _rustler_melee_accum >= 1.0:
			_rustler_melee_accum -= 1.0
			var sf: Dictionary = _nearest_special_follower(boss.position, 99.0)
			if not sf.is_empty():
				_damage_special_follower(sf, 1)
			else:
				_posse_count_3d = maxi(0, _posse_count_3d - 1)
				_sync_followers_to_count(_posse_count_3d)
				_refresh_hud()
	_rustler_taunt_timer -= delta
	if _rustler_taunt_timer <= 0.0:
		_rustler_taunt_timer = RUSTLER_TAUNT_INTERVAL
		_rustler_say(boss, "taunt")
	# Bullet hits — every overlapping posse bullet counts (no per-frame
	# break; matches the iter 147 Pete fix).
	for bullet in bullets_root.get_children():
		if not (bullet is Node3D):
			continue
		var dx: float = bullet.position.x - boss.position.x
		var dz: float = bullet.position.z - boss.position.z
		if dx * dx + dz * dz < PETE_HIT_RADIUS_SQ:
			var hp: int = boss.get_meta("hp", RUSTLER_HP) - 1
			boss.set_meta("hp", hp)
			if rig != null and rig.has_method("take_damage"):
				rig.take_damage(1)
			_spawn_popup_3d(boss.position + Vector3(0, 1.5, 0),
				"-1", Color(0.98, 0.55, 0.30, 1), 72)
			bullet.queue_free()
			_hits += 1
			_refresh_hud()
			_refresh_pete_hp(boss)
			if _rustler_hit_voice_cd <= 0.0:
				_rustler_hit_voice_cd = 3.5
				_rustler_say(boss, "hit")
			if hp <= 0:
				boss.set_meta("dying", true)
				if rig != null and rig.has_method("defeat"):
					rig.defeat()
				_rustler_say(boss, "dying")
				_show_win("The Candy Rustler", boss,
					boss.get_meta("viewport", null))
				break

# Candy Rustler voice line + speech bubble. kind ∈ intro/taunt/hit/dying.
# Bookend lines (intro/dying) always play; mid-fight chatter (taunt/hit)
# yields if another character line is still going — the anti-overlap rule
# the menu Humbug banter uses (iter 153).
func _rustler_say(boss: Node3D, kind: String) -> void:
	var banks: Dictionary = {
		"intro": ["candy_rustler_intro_", 2, "boss.candy_rustler_dialog_intro"],
		"taunt": ["candy_rustler_taunt_", 4, "boss.candy_rustler_dialog_taunts"],
		"hit": ["candy_rustler_hit_", 4, "boss.candy_rustler_dialog_when_hit"],
		"dying": ["candy_rustler_dying_", 4, "boss.candy_rustler_dialog_dying"],
	}
	if not banks.has(kind):
		return
	var entry: Array = banks[kind]
	var audio := get_node_or_null("/root/AudioBus")
	if audio != null and audio.has_method("play_character_line"):
		var force: bool = (kind == "intro" or kind == "dying")
		var busy: bool = audio.has_method("any_character_line_playing") and audio.any_character_line_playing()
		if force or not busy:
			audio.play_character_line("%s%d" % [entry[0], randi() % int(entry[1])])
	if get_node_or_null("/root/Text") != null:
		var line: String = Text.random(entry[2])
		if line != "" and line != entry[2]:
			_boss_speech_bubble(boss.position + Vector3(0, 0.6, 0.8), line)

# Floating speech bubble for a boss line — modeled on the iter 83 Pete
# taunt bubble (Pete keeps its own copy; this is the shared boss path).
func _boss_speech_bubble(world_pos: Vector3, line: String) -> void:
	var bubble := Label3D.new()
	bubble.text = line
	bubble.font_size = 56
	bubble.outline_size = 12
	bubble.modulate = Color(1, 0.92, 0.55, 1)
	bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	bubble.no_depth_test = true
	bubble.position = world_pos
	popups_root.add_child(bubble)
	var t := create_tween().set_parallel(true)
	t.tween_property(bubble, "position:y", bubble.position.y + 2.0, 1.8) \
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
# Iter 120: countdown now uses FlourishBanner (same big scale-pop +
# sparkles + shock-ring + camera shake treatment as the sugar rush).
# Track the most-recently-displayed phase so each step pops exactly
# once instead of spamming a banner every frame.
const FlourishBanner = preload("res://scripts/flourish_banner.gd")
var _countdown_last_phase: int = -1
func _render_countdown() -> void:
	var t: float = _countdown_remaining
	var phase: int
	var preset: String
	# Iter 121: preset names use plain alpha (READY/GO) instead of "GO!" —
	# the previous iter saw "COUNT_3" displayed on-screen because the iter
	# 120 PRESET-edit didn't actually land in flourish_banner.gd, so the
	# fallback path used the preset_name AS the text. Now the names match
	# what's in PRESETS verbatim.
	if t > 2.5:
		phase = 0; preset = "READY"
	elif t > 1.5:
		phase = 1; preset = "COUNT_3"
	elif t > 0.5:
		phase = 2; preset = "COUNT_2"
	elif t > -0.5:
		phase = 3; preset = "COUNT_1"
	else:
		phase = 4; preset = "GO"
	if phase != _countdown_last_phase:
		_countdown_last_phase = phase
		var ui_canvas: Node = get_node_or_null("UI")
		if ui_canvas != null:
			FlourishBanner.spawn(ui_canvas, preset)

# Iter 115/117: render the cowboy's ammo + reload status on a HUD label.
# Iter 117: ported the EXACT 2D pip-glyph infographic from level.gd
# (▰ filled, ▱ empty). User noted iter 115's plain text didn't match.
# Two states:
#   reloading      → "RELOADING ▰▰▱▱▱▱"  (pips fill as reload progresses)
#   ready-to-fire  → "AMMO ▰▰▰▰▱▱"        (pips empty as ammo drains)
func _refresh_ammo_label_3d() -> void:
	if info_label == null or _gun_state == null:
		return
	var clip: int = _gun.clip_size
	if _gun_state.is_reloading():
		var filled: int = int(round(float(clip) * _gun_state.reload_progress()))
		info_label.text = "RELOADING " + "▰".repeat(filled) + "▱".repeat(clip - filled)
		info_label.modulate = Color(1.0, 0.55, 0.25, 1)  # amber
	else:
		var ammo: int = _gun_state.ammo()
		info_label.text = "AMMO " + "▰".repeat(ammo) + "▱".repeat(clip - ammo)
		info_label.modulate = Color(1.0, 0.92, 0.55, 1)  # gold

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
func _show_win(boss_label: String = "Pete", cleanup_node: Node = null, cleanup_viewport: Node = null) -> void:
	_pete_defeated = true
	# Iter 87: stop the lingering gunshot pool so the salute (which
	# spawns its own gunfire) doesn't fight the trailing combat audio.
	if get_node_or_null("/root/AudioBus") and AudioBus.has_method("stop_gunfire"):
		AudioBus.stop_gunfire()
	info_label.text = "WIN!  %s defeated · posse %d · hits %d" % [
		boss_label, _posse_count_3d, _hits,
	]
	# Iter 123: Gold Rush A — PERFECT_VOLLEY banner pops before the
	# salute fire ceremony, matching the 2D level.gd Gold Rush A flow.
	var ui_canvas: Node = get_node_or_null("UI")
	if ui_canvas != null:
		FlourishBanner.spawn(ui_canvas, "PERFECT_VOLLEY")
	await _gold_rush_salute_3d()
	if win_label:
		win_label.text = "BOUNTY!\nposse %d · hits %d" % [_posse_count_3d, _hits]
	if win_overlay:
		win_overlay.visible = true
	AudioBus.play_gate_pass()
	# Iter 157: free the boss node + its SubViewport when passed in. Pete
	# frees himself before calling _show_win; the Rustler is kept alive
	# through the salute so his death scatter plays, then cleaned up here.
	if cleanup_node != null and is_instance_valid(cleanup_node):
		cleanup_node.queue_free()
	if cleanup_viewport != null and is_instance_valid(cleanup_viewport):
		cleanup_viewport.queue_free()

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
const VAGRANT_DEATH_STREAM := preload("res://assets/videos/vagrant/death.ogv")
const VAGRANT_DEATH_LIFETIME: float = 1.2  # seconds before queue_free

var _outlaw_spawn_count: int = 0
# Iter 114/118: outlaw spawn x narrowed to ±2.5 to fit the visible road.
const OUTLAW_SPAWN_X_MAX: float = 2.5
# Iter 118: prospector ("miner") spawns rarely as a tougher mid-tier
# enemy. Uses the existing prospector.png + shared video billboard path.
const PROSPECTOR_IDLE_STREAM := preload("res://assets/videos/prospector/idle_drinking.ogv")
const PROSPECTOR_SPAWN_INTERVAL: float = 5.0
const PROSPECTOR_HP: int = 18
var _prospector_spawn_timer: float = 2.0  # first one a couple seconds in
var _prospector_spawn_count: int = 0

func _spawn_prospector() -> void:
	# Iter 118: a tougher mid-tier enemy. Same scroll/fire/track behavior
	# as the outlaw via the outlaws_root container; differentiated by HP
	# meta + video stream. The _process outlaw loop handles both transparently.
	var prosp := Node3D.new()
	var lane_x: float = _rng.randf_range(-OUTLAW_SPAWN_X_MAX, OUTLAW_SPAWN_X_MAX)
	prosp.position = Vector3(lane_x, 1.0, OBSTACLE_SPAWN_Z + 4.0)
	prosp.set_meta("hp", PROSPECTOR_HP)
	prosp.set_meta("fire_timer", _rng.randf() * OUTLAW_FIRE_INTERVAL)
	outlaws_root.add_child(prosp)
	var billboard: Node3D = _make_video_billboard(PROSPECTOR_IDLE_STREAM, 2.6)
	prosp.add_child(billboard)
	# Iter 151: HP bar above the prospector (hidden until first hit).
	_attach_outlaw_hp_bar(prosp, PROSPECTOR_HP)
	_prospector_spawn_count += 1
	DebugLog.add("prospector spawn #%d at x=%.1f" % [_prospector_spawn_count, lane_x])

# ============================================================================
# Iter 133: Captive hero release ceremony.
# Container holds a trapped hero. Player shoots container; on HP=0,
# container shatters and hero detaches + flips to face forward + joins
# formation. Glitz preset from GlitzPrefs applied during release.
# ============================================================================

const CONTAINER_HP_BY_TIER: Dictionary = {1: 30, 2: 60, 3: 100}
const CONTAINER_TEX: Dictionary = {
	"wagon_covered": {"path": "res://assets/sprites/props/wagon_covered.png", "w": 2.4, "h": 1.6},
	"mining_cart":   {"path": "res://assets/sprites/props/mining_cart.png",   "w": 2.0, "h": 1.4},
	"barrel":        {"path": "res://assets/sprites/props/barrel.png",        "w": 1.2, "h": 1.6},
}
const HERO_TEX: Dictionary = {
	"marshmallow_sheriff": "res://assets/sprites/props/hero_marshmallow_sheriff.png",
	"laughing_horse":      "res://assets/sprites/props/hero_laughing_horse.png",
	"scarecrow":           "res://assets/sprites/props/hero_scarecrow.png",
	"chocolate_outlaw":    "res://assets/sprites/props/hero_chocolate_outlaw.png",
	"sugar_doc":           "res://assets/sprites/props/hero_sugar_doc.png",
	"taffy_kid":           "res://assets/sprites/props/hero_taffy_kid.png",
}

# Captive root structure (added to outlaws_root for bullet-collision reuse):
#   captive Node3D                          (the gameplay actor, has hp+hero meta)
#     ├── container_sprite Sprite3D         (the wagon/cart/barrel body)
#     ├── hero_sprite Sprite3D              (smaller, layered front, Y-billboard)
#     ├── halo_sprite Sprite3D              (behind, Y-spin to signal "shoot me")
#     └── hp_label Label3D                  (overhead, shrinks text as hp drops)
func _spawn_captive_hero(container_slug: String, hero_slug: String,
		lane_x: float, lane_z: float, hero_tier: int = 2) -> Node3D:
	var c_data: Dictionary = CONTAINER_TEX.get(container_slug, CONTAINER_TEX["wagon_covered"])
	var c_tex: Texture2D = load(c_data.path) if ResourceLoader.exists(c_data.path) else null
	var h_tex_path: String = HERO_TEX.get(hero_slug, "")
	var h_tex: Texture2D = load(h_tex_path) if (h_tex_path != "" and ResourceLoader.exists(h_tex_path)) else null
	var halo_tex: Texture2D = load("res://assets/sprites/props/bonus_halo.png") if ResourceLoader.exists("res://assets/sprites/props/bonus_halo.png") else null
	var hp: int = CONTAINER_HP_BY_TIER.get(hero_tier, 60)

	var captive := Node3D.new()
	captive.position = Vector3(lane_x, 0, lane_z)
	captive.set_meta("hp", hp)
	captive.set_meta("max_hp", hp)
	captive.set_meta("hero_slug", hero_slug)
	captive.set_meta("container_slug", container_slug)
	captive.set_meta("is_captive", true)
	captive.set_meta("fire_timer", 999999.0)  # captives don't fire
	outlaws_root.add_child(captive)

	# Halo behind — Y-spinning to signal "shoot me"
	if halo_tex != null:
		var halo := Sprite3D.new()
		halo.texture = halo_tex
		halo.pixel_size = (c_data.h + 0.6) / float(halo_tex.get_height())
		halo.billboard = 1
		halo.alpha_cut = 0
		halo.modulate = Color(1.0, 0.92, 0.45, 0.7)
		halo.position = Vector3(0, c_data.h * 0.5, -0.05)
		captive.add_child(halo)
		# Continuous Y rotation tween
		var halo_tw: Tween = halo.create_tween().set_loops()
		halo_tw.tween_property(halo, "rotation_degrees:y", 360.0, 4.0) \
			.set_trans(Tween.TRANS_LINEAR)
		halo_tw.tween_callback(func(): halo.rotation_degrees.y = 0.0)

	# Container body
	var container_sprite := Sprite3D.new()
	if c_tex != null:
		container_sprite.texture = c_tex
		container_sprite.pixel_size = c_data.h / float(c_tex.get_height())
	container_sprite.billboard = 1
	container_sprite.alpha_cut = 1
	container_sprite.position = Vector3(0, c_data.h * 0.5, 0)
	captive.add_child(container_sprite)
	captive.set_meta("container_sprite", container_sprite)

	# Hero sprite layered ON TOP — billboard so always faces player
	if h_tex != null:
		var hero_sprite := Sprite3D.new()
		hero_sprite.texture = h_tex
		# Hero is ~70% the container height visually
		hero_sprite.pixel_size = (c_data.h * 0.7) / float(h_tex.get_height())
		hero_sprite.billboard = 1
		hero_sprite.alpha_cut = 1
		hero_sprite.position = Vector3(0, c_data.h * 0.65, 0.15)
		captive.add_child(hero_sprite)
		captive.set_meta("hero_sprite", hero_sprite)

	# HP label overhead
	var hp_label := Label3D.new()
	hp_label.text = "%d / %d" % [hp, hp]
	hp_label.font_size = 48
	hp_label.outline_size = 8
	hp_label.modulate = Color(1.0, 0.55, 0.55, 1.0)
	hp_label.billboard = 1
	hp_label.position = Vector3(0, c_data.h + 0.6, 0)
	captive.add_child(hp_label)
	captive.set_meta("hp_label", hp_label)

	# Trapped! label
	var trapped_label := Label3D.new()
	trapped_label.text = "TRAPPED!"
	trapped_label.font_size = 56
	trapped_label.outline_size = 10
	trapped_label.modulate = Color(1.0, 0.85, 0.30, 1.0)
	trapped_label.billboard = 1
	trapped_label.position = Vector3(0, c_data.h + 1.1, 0)
	captive.add_child(trapped_label)
	captive.set_meta("trapped_label", trapped_label)

	return captive

# Iter 134: handle bullet hitting a pusher — instant kill, fade out.
func _pusher_take_damage(pusher: Node3D) -> void:
	if pusher.get_meta("is_dead", false):
		return
	pusher.set_meta("is_dead", true)
	var sprite: Sprite3D = pusher.get_meta("sprite", null)
	if sprite != null and is_instance_valid(sprite):
		var tw: Tween = sprite.create_tween().set_parallel(true)
		tw.tween_property(sprite, "modulate", Color(1.5, 0.3, 0.3, 0.0), 0.30)
		tw.tween_property(sprite, "position:y", sprite.position.y - 0.4, 0.30)
	# Cleanup after fade
	var free_tw: Tween = create_tween()
	free_tw.tween_interval(0.35)
	free_tw.tween_callback(pusher.queue_free)
	_spawn_popup_3d(pusher.position + Vector3(0, 1.2, 0),
		"-1", Color(1, 0.55, 0.30, 1), 36)
	_hits += 1
	_refresh_hud()

# Iter 133: handle bullet hitting a captive — damages container, on
# HP=0 triggers the release ceremony. Called from the bullet/outlaw
# collision loop when outlaw.get_meta("is_captive") is true.
func _captive_take_damage(captive: Node3D, bullet_pos: Vector3) -> void:
	if captive.get_meta("released", false):
		return  # iter 164: already freed — ignore trailing bullets
	var hp: int = captive.get_meta("hp", 0) - 1
	captive.set_meta("hp", hp)
	var max_hp: int = captive.get_meta("max_hp", 60)
	# Update HP label
	var hp_label: Label3D = captive.get_meta("hp_label", null)
	if hp_label != null and is_instance_valid(hp_label):
		hp_label.text = "%d / %d" % [maxi(hp, 0), max_hp]
	# Damage popup
	_spawn_popup_3d(bullet_pos + Vector3(0, 0.5, 0),
		"-1", Color(1.0, 0.55, 0.40, 1), 36)
	# Small flash modulate on container
	var container_sprite: Sprite3D = captive.get_meta("container_sprite", null)
	if container_sprite != null and is_instance_valid(container_sprite):
		container_sprite.modulate = Color(1.5, 1.5, 1.5, 1.0)
		var flash_tw: Tween = container_sprite.create_tween()
		flash_tw.tween_property(container_sprite, "modulate", Color.WHITE, 0.12)
	if hp <= 0:
		_release_captive_hero_pushed_aware(captive)

# Iter 133: container shatters → hero pops out → flips to face forward
# → joins posse formation.
# Iter 134: pushed wagon's release adds pusher-melee conversion.
func _release_captive_hero_pushed_aware(captive: Node3D) -> void:
	# Iter 164: release exactly once. The captive lingers ~1.5s for the
	# rescue ceremony; without this guard every trailing bullet re-fired
	# the release and stacked duplicate followers (the "6 sheriffs" bug).
	if captive.get_meta("released", false):
		return
	captive.set_meta("released", true)
	if captive.get_meta("is_pushed", false):
		captive.set_meta("is_pushed", false)
		_convert_pushers_to_melee(captive)
	_release_captive_hero(captive)

func _release_captive_hero(captive: Node3D) -> void:
	var hero_slug: String = captive.get_meta("hero_slug", "marshmallow_sheriff")
	var hero_sprite: Sprite3D = captive.get_meta("hero_sprite", null)
	var container_sprite: Sprite3D = captive.get_meta("container_sprite", null)
	var hp_label: Label3D = captive.get_meta("hp_label", null)
	var trapped_label: Label3D = captive.get_meta("trapped_label", null)
	# Hide HUD labels immediately
	if hp_label != null: hp_label.visible = false
	if trapped_label != null: trapped_label.visible = false
	# Container shatter — scale to 0 with TRANS_BACK + bonk
	if container_sprite != null and is_instance_valid(container_sprite):
		var shatter_tw: Tween = container_sprite.create_tween().set_parallel(true)
		shatter_tw.tween_property(container_sprite, "scale", Vector3(0.01, 0.01, 0.01), 0.4) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		shatter_tw.tween_property(container_sprite, "modulate:a", 0.0, 0.4)
	# Splinter burst
	_burst_at(captive.position + Vector3(0, 0.8, 0), 18,
		Color(0.85, 0.65, 0.40, 1), 1.2, 0.6)
	# Hero scale-pop reveal
	if hero_sprite != null and is_instance_valid(hero_sprite):
		var pop_tw: Tween = hero_sprite.create_tween()
		pop_tw.tween_property(hero_sprite, "scale", Vector3(1.5, 1.5, 1.5), 0.25) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		pop_tw.tween_property(hero_sprite, "scale", Vector3.ONE, 0.20) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN_OUT)
	# Banner + bounty
	var ui_canvas: Node = get_node_or_null("UI")
	if ui_canvas != null:
		FlourishBanner.spawn(ui_canvas, "%s RESCUED" % hero_slug.to_upper().replace("_", " "))
	_spawn_popup_3d(captive.position + Vector3(0, 2.0, 0),
		"+500 BOUNTY", Color(1.0, 0.92, 0.30, 1), 64)
	_add_bounty(500)
	# Posse +1
	_posse_count_3d += 1
	_sync_followers_to_count(_posse_count_3d)
	_refresh_hud()
	# Iter 149: the rescued hero JOINS as a persistent special follower —
	# its own PNG, a hero skill, and HP (killable by outlaws). The ceremony
	# hero_sprite still does its slide-and-fade; _add_special_follower
	# spawns the real persistent unit at a formation slot.
	_add_special_follower(hero_slug)
	# Hero slides to posse formation: tween hero_sprite to leader area, then queue_free
	if hero_sprite != null and is_instance_valid(hero_sprite):
		var target_pos: Vector3 = cowboy_3d.position + Vector3(_rng.randf_range(-0.6, 0.6), 0.5, 0.6)
		var slide_tw: Tween = hero_sprite.create_tween().set_parallel(true)
		slide_tw.tween_property(hero_sprite, "global_position", target_pos, 0.6) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		slide_tw.tween_property(hero_sprite, "scale", Vector3(0.6, 0.6, 0.6), 0.6)
		# hero_sprite is a child of `captive` — the cleanup_tw below frees
		# the whole container, so no separate free needed here. The
		# persistent unit is the one _add_special_follower spawned.
	# Cleanup container after ceremony
	var cleanup_tw: Tween = captive.create_tween()
	cleanup_tw.tween_interval(1.5)
	cleanup_tw.tween_callback(captive.queue_free)

# Iter 133: debug preview entry for captive hero rescue.
func _preview_captive_3d(hero_slug: String, container_slug: String) -> void:
	if container_slug == "":
		container_slug = "wagon_covered"
	# Big banner
	var ui_canvas: Node = get_node_or_null("UI")
	if ui_canvas != null:
		FlourishBanner.spawn(ui_canvas, "CAPTIVE HERO")
	await get_tree().create_timer(0.5).timeout
	# Spawn captive in front of cowboy
	var captive: Node3D = _spawn_captive_hero(container_slug, hero_slug, 0.0, -4.0, 2)
	# Switch state back to PLAYING so cowboy can fire at it
	_level_state = LevelState.PLAYING
	_preview_mode = false  # let firing happen normally

# ============================================================================
# Iter 134: Pushed-wagon mob mechanic.
# A captive hero in a wagon is being shoved toward a cliff by 10-100
# beagle-boy pushers. Player must allocate bullets across attacking
# outlaws, pushers (to slow the wagon), and the wagon itself (to free
# the hero before it goes over).
#
# v1 scope (this iter):
#   - Linear push only — wagon moves in cliff direction at speed
#     proportional to alive-pusher count. Asymmetric tug-of-war
#     (kill-corner-to-swerve) deferred to v2.
#   - Pushers are 1-shot kill, smaller sprite (~70% normal outlaw)
#   - Pusher sprite: pusher_left if on wagon's right side, pusher_right
#     if on wagon's left side (they face the wagon)
#   - Wagon HP scales with hero tier (uses iter 133 CONTAINER_HP_BY_TIER)
#   - HP reaches 0 → release ceremony from iter 133 + pushers convert
#     to melee mode (pusher_melee sprite, rush posse)
#   - Wagon position.x > CLIFF_X → hero dies, pushers convert to melee
#   - Visual: cliff edge marker at CLIFF_X (rope + red zone tint)
# ============================================================================

const CLIFF_X: float = 7.0
const PUSH_FORCE_PER_PUSHER: float = 0.09  # world units/sec per pusher (iter 164: 0.18 → 0.09, cliff race was too fast)
const MAX_PUSH_SPEED: float = 2.4  # iter 164: cap so high pusher counts stay winnable
var _cart_encounter: bool = false  # iter 173: a pushed-cart encounter pauses the world's forward scroll
const PUSHER_TEX_LEFT := "res://assets/sprites/props/pusher_left.png"
const PUSHER_TEX_RIGHT := "res://assets/sprites/props/pusher_right.png"
const PUSHER_TEX_MELEE := "res://assets/sprites/props/pusher_melee.png"
const PUSHER_HEIGHT_WORLD: float = 1.2  # ~70% of regular outlaw
const PUSHER_MELEE_DPS: float = 0.5  # posse members / sec while in contact
const PUSHER_MELEE_RANGE: float = 1.5

func _spawn_pushed_wagon(hero_slug: String, container_slug: String,
		n_pushers: int, hero_tier: int = 2) -> Node3D:
	# Reuse iter 133 captive hero spawn; mark it as pushed.
	var captive: Node3D = _spawn_captive_hero(container_slug, hero_slug,
		0.0, -5.0, hero_tier)
	captive.set_meta("is_pushed", true)
	# Pusher tracking via meta array (we'd lose references if pushers were
	# children of captive — they need to be in outlaws_root for the
	# existing bullet collision loop to find them).
	var pushers: Array = []
	captive.set_meta("pushers", pushers)
	# Spawn pushers in a grid behind + flanking the wagon. For visual
	# density at 10-100 count, lay out cols × rows behind the wagon.
	var cols: int = clampi(int(ceil(sqrt(float(n_pushers)))), 3, 8)
	var rows: int = int(ceil(float(n_pushers) / float(cols)))
	for i in range(n_pushers):
		var col: int = i % cols
		var row: int = i / cols
		# col centered around 0, row stacking BEHIND wagon (-x = away from cliff)
		var ox: float = -1.5 - float(row) * 0.7
		var oz: float = (float(col) - float(cols - 1) * 0.5) * 0.55
		var is_left_side: bool = oz < 0.0  # left side of wagon
		var pusher: Node3D = _spawn_pusher(
			captive.position + Vector3(ox, 0, oz), is_left_side)
		pushers.append(pusher)
	captive.set_meta("pushers", pushers)
	# Cliff marker — red zone strip at CLIFF_X with rope
	_spawn_cliff_marker(captive.position.z)
	# UI: 'PUSHED' label above captive (replaces TRAPPED!)
	var trapped: Label3D = captive.get_meta("trapped_label", null)
	if trapped != null:
		trapped.text = "PUSHED!"
		trapped.modulate = Color(1.0, 0.30, 0.30, 1.0)
	DebugLog.add("pushed wagon: %s in %s with %d pushers" % [hero_slug, container_slug, n_pushers])
	return captive

func _spawn_pusher(world_pos: Vector3, is_left_side: bool) -> Node3D:
	var p := Node3D.new()
	p.position = world_pos
	p.set_meta("hp", 1)
	p.set_meta("is_pusher", true)
	p.set_meta("is_dead", false)
	p.set_meta("state", "pushing")  # or "melee" after release
	# Critical: also set generic outlaw flags so the existing bullet
	# loop's collision check finds it. fire_timer = huge → never fires.
	p.set_meta("fire_timer", 999999.0)
	outlaws_root.add_child(p)
	var sprite := Sprite3D.new()
	# Pusher faces the wagon; pushers ON the LEFT push toward the right
	# (so use pusher_right sprite facing right). Vice versa.
	var tex_path: String = PUSHER_TEX_RIGHT if is_left_side else PUSHER_TEX_LEFT
	if ResourceLoader.exists(tex_path):
		sprite.texture = load(tex_path)
		sprite.pixel_size = PUSHER_HEIGHT_WORLD / float(sprite.texture.get_height())
	sprite.billboard = 1
	sprite.alpha_cut = 1
	sprite.position = Vector3(0, PUSHER_HEIGHT_WORLD * 0.5, 0)
	p.add_child(sprite)
	p.set_meta("sprite", sprite)
	p.set_meta("is_left_side", is_left_side)
	return p

# Iter 134: cliff marker — a red ground strip at the cliff edge to
# telegraph the danger zone to the player.
func _spawn_cliff_marker(wagon_z: float) -> void:
	var marker := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(0.5, 8.0)
	marker.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.20, 0.10, 0.85)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.20, 0.10, 1.0)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	marker.material_override = mat
	marker.position = Vector3(CLIFF_X, 0.05, wagon_z)
	# Pulse the marker so it draws the eye
	var pulse_tw: Tween = marker.create_tween().set_loops()
	pulse_tw.tween_property(marker, "scale", Vector3(1.2, 1.0, 1.0), 0.5)
	pulse_tw.tween_property(marker, "scale", Vector3(1.0, 1.0, 1.0), 0.5)
	popups_root.add_child(marker)

# Iter 173: enter/leave a cart encounter. Edge-triggered so the terrain
# scroll is toggled only at the boundaries — never per-frame, which would
# stomp the boss-engagement scroll stop. Freezing via scroll_speed (not
# set_scroll_active) keeps it independent of that boss mechanic.
# motion_delta is gated separately, per-frame, on _cart_encounter.
func _set_cart_encounter(active: bool) -> void:
	if active == _cart_encounter:
		return
	_cart_encounter = active
	if terrain_3d_node != null and "scroll_speed" in terrain_3d_node:
		terrain_3d_node.scroll_speed = 0.0 if active else (OBSTACLE_SPEED / 15.0)
	DebugLog.add("cart encounter %s" % (
		"BEGIN — world scroll paused" if active else "END — scroll resumed"))

# Iter 134: every frame, advance each pushed-wagon by alive-pusher count.
# Called from _process during PLAYING/BOSS.
func _update_pushed_wagons(delta: float) -> void:
	# Iter 173: a cart encounter PAUSES the world's forward scroll — the
	# terrain + props freeze in lockstep, the cart freezes with them, and
	# only the outlaws keep advancing on the posse. The pushers shove the
	# cart toward the cliff; on cliff / rescue the scroll resumes.
	var wagon_present: bool = false
	for child in outlaws_root.get_children():
		# iter 178: a plain captive cart freezes the world too, not only
		# pushed wagons — matches the player-facing "carts stop momentum".
		if is_instance_valid(child) and (child.get_meta("is_pushed", false) or child.get_meta("is_captive", false)):
			wagon_present = true
			break
	_set_cart_encounter(wagon_present)
	for child in outlaws_root.get_children():
		if not child.get_meta("is_pushed", false):
			continue
		# Skip if hero already released (captive will queue_free after ceremony)
		if not is_instance_valid(child):
			continue
		var captive: Node3D = child
		var pushers: Array = captive.get_meta("pushers", [])
		var alive: int = 0
		for p in pushers:
			if is_instance_valid(p) and not p.get_meta("is_dead", false) and \
					p.get_meta("state", "pushing") == "pushing":
				alive += 1
		if alive == 0:
			continue
		var push_speed: float = minf(float(alive) * PUSH_FORCE_PER_PUSHER, MAX_PUSH_SPEED)
		captive.position.x += push_speed * delta
		# Move pushers with the wagon (they're chasing it)
		for p in pushers:
			if is_instance_valid(p) and not p.get_meta("is_dead", false) and \
					p.get_meta("state", "pushing") == "pushing":
				p.position.x += push_speed * delta
		# Cliff check
		if captive.position.x > CLIFF_X:
			_wagon_fall_off_cliff(captive)
	# Pusher melee phase: pushers in 'melee' state slowly chase cowboy
	# and deal damage when in range.
	for p in outlaws_root.get_children():
		if not p.get_meta("is_pusher", false):
			continue
		if p.get_meta("is_dead", false):
			continue
		if p.get_meta("state", "pushing") != "melee":
			continue
		# Move toward cowboy
		var to_cb: Vector3 = cowboy_3d.position - p.position
		to_cb.y = 0
		var dist: float = to_cb.length()
		if dist > 0.001:
			p.position += to_cb.normalized() * 3.0 * delta
		if dist < PUSHER_MELEE_RANGE:
			# Apply damage tick-style
			var accum: float = p.get_meta("melee_accum", 0.0) + delta * PUSHER_MELEE_DPS
			if accum >= 1.0:
				p.set_meta("melee_accum", accum - 1.0)
				_posse_count_3d = maxi(0, _posse_count_3d - 1)
				_sync_followers_to_count(_posse_count_3d)
				_refresh_hud()
			else:
				p.set_meta("melee_accum", accum)

# Iter 134: wagon went over cliff. Hero "dies", pushers convert to melee
# to harass the player as punishment for losing the hero.
func _wagon_fall_off_cliff(captive: Node3D) -> void:
	if not is_instance_valid(captive):
		return
	captive.set_meta("is_pushed", false)  # stop further updates
	# Falling tween — wagon drops below ground + spins
	var fall_tw: Tween = captive.create_tween().set_parallel(true)
	fall_tw.tween_property(captive, "position:y", -3.0, 0.7) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	fall_tw.tween_property(captive, "rotation:z", -PI * 0.5, 0.7) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	# Narrator beat
	var ui_canvas: Node = get_node_or_null("UI")
	if ui_canvas != null:
		FlourishBanner.spawn(ui_canvas, "HERO LOST!")
	_spawn_popup_3d(captive.position + Vector3(0, 2.0, 0),
		"-200 PENALTY", Color(1.0, 0.20, 0.10, 1), 64)
	_add_bounty(-200)
	# Convert all pushers to melee mode
	_convert_pushers_to_melee(captive)
	# Cleanup captive after fall animation
	var cleanup_tw: Tween = create_tween()
	cleanup_tw.tween_interval(1.0)
	cleanup_tw.tween_callback(captive.queue_free)

# Iter 134: when hero released OR cliff fall, all alive pushers swap
# sprite to pusher_melee and start hunting the posse.
func _convert_pushers_to_melee(captive: Node3D) -> void:
	var pushers: Array = captive.get_meta("pushers", [])
	for p in pushers:
		if not is_instance_valid(p) or p.get_meta("is_dead", false):
			continue
		p.set_meta("state", "melee")
		p.set_meta("melee_accum", 0.0)
		var sprite: Sprite3D = p.get_meta("sprite", null)
		if sprite != null and is_instance_valid(sprite) and ResourceLoader.exists(PUSHER_TEX_MELEE):
			sprite.texture = load(PUSHER_TEX_MELEE)
			sprite.pixel_size = PUSHER_HEIGHT_WORLD / float(sprite.texture.get_height())

# Iter 134: extended _release_captive_hero — when called on a pushed
# wagon, also convert pushers to melee. We wrap by checking is_pushed.
# Done via post-call check below since iter 133's _release_captive_hero
# is reused as-is.

# Iter 134: debug preview entry for pushed wagon.
func _preview_pushed_wagon_3d(hero_slug: String, container_slug: String, n_pushers: int) -> void:
	var ui_canvas: Node = get_node_or_null("UI")
	if ui_canvas != null:
		FlourishBanner.spawn(ui_canvas, "PUSHED WAGON")
	await get_tree().create_timer(0.5).timeout
	_spawn_pushed_wagon(hero_slug, container_slug, n_pushers, 2)
	_level_state = LevelState.PLAYING
	_preview_mode = false

# Iter 151: small HP bar above an outlaw/prospector. Two BoxMesh planes
# (dark bg + coloured fg), hidden until the unit takes its first hit (the
# iter-25 "hidden until <100%" rule). Refreshed by _refresh_outlaw_hp_bar
# from the bullet-hit handler. fg is SCALED (not mesh-resized) so a hit
# costs no mesh rebuild.
func _attach_outlaw_hp_bar(unit: Node3D, max_hp: int) -> void:
	var bar_w: float = 1.3
	var bg := MeshInstance3D.new()
	var bgmesh := BoxMesh.new()
	bgmesh.size = Vector3(bar_w, 0.20, 0.06)
	bg.mesh = bgmesh
	var bgm := StandardMaterial3D.new()
	bgm.albedo_color = Color(0.05, 0.05, 0.05, 0.92)
	bgm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bg.material_override = bgm
	bg.position = Vector3(0, 1.65, 0)
	bg.visible = false
	unit.add_child(bg)
	var fg := MeshInstance3D.new()
	var fgmesh := BoxMesh.new()
	fgmesh.size = Vector3(bar_w, 0.16, 0.09)
	fg.mesh = fgmesh
	var fgm := StandardMaterial3D.new()
	fgm.albedo_color = Color(0.35, 0.85, 0.32, 1)
	fgm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fg.material_override = fgm
	fg.position = Vector3(0, 1.65, 0.03)
	fg.visible = false
	unit.add_child(fg)
	unit.set_meta("hp_bar_bg", bg)
	unit.set_meta("hp_bar_fg", fg)
	unit.set_meta("hp_bar_max", max_hp)
	unit.set_meta("hp_bar_w", bar_w)

func _refresh_outlaw_hp_bar(unit: Node3D) -> void:
	var fg: MeshInstance3D = unit.get_meta("hp_bar_fg", null)
	var bg: MeshInstance3D = unit.get_meta("hp_bar_bg", null)
	if fg == null or not is_instance_valid(fg) or bg == null or not is_instance_valid(bg):
		return
	var hp: int = unit.get_meta("hp", 1)
	var max_hp: int = unit.get_meta("hp_bar_max", 1)
	var bar_w: float = unit.get_meta("hp_bar_w", 1.3)
	var pct: float = clampf(float(hp) / float(maxi(max_hp, 1)), 0.0, 1.0)
	var show_bar: bool = pct < 0.999 and hp > 0
	bg.visible = show_bar
	fg.visible = show_bar
	# Scale x from the right edge so the bar drains right-to-left.
	fg.scale.x = maxf(pct, 0.001)
	fg.position.x = (pct - 1.0) * bar_w * 0.5
	var c: Color
	if pct > 0.6:
		c = Color(0.35, 0.85, 0.32, 1)
	elif pct > 0.3:
		c = Color(0.95, 0.85, 0.25, 1)
	else:
		c = Color(0.95, 0.25, 0.25, 1)
	(fg.material_override as StandardMaterial3D).albedo_color = c

func _spawn_outlaw() -> void:
	# Iter 116: re-enable video billboard, but this time via SHARED top-
	# level SubViewports (see _make_video_billboard) — iter 114 confirmed
	# that nested-SubViewport video billboards don't render on Android.
	var outlaw := Node3D.new()
	var lane_x: float = _rng.randf_range(-OUTLAW_SPAWN_X_MAX, OUTLAW_SPAWN_X_MAX)
	outlaw.position = Vector3(lane_x, 1.0, OBSTACLE_SPAWN_Z + 4.0)
	outlaw.set_meta("hp", OUTLAW_HP)
	outlaw.set_meta("fire_timer", _rng.randf() * OUTLAW_FIRE_INTERVAL)
	# Iter 120: per-unit horizontal offset around the cowboy. Without this,
	# all outlaws lerp to the SAME cowboy_3d.position.x and form a single
	# vertical column — what the user called 'standing in a line'.
	# With a stable random offset in ±1.2, outlaws crowd around the posse
	# at varied x positions, looking like a swarm instead of a queue.
	outlaw.set_meta("track_offset_x", _rng.randf_range(-1.2, 1.2))
	outlaw.set_meta("dying", false)
	outlaw.set_meta("death_timer", 0.0)
	outlaws_root.add_child(outlaw)
	var billboard: Node3D = _make_video_billboard(VAGRANT_IDLE_STREAM, 2.5)
	outlaw.add_child(billboard)
	# Stash the Sprite3D ref so death-anim swap can replace its texture
	# without searching the tree.
	if billboard.get_child_count() > 0:
		outlaw.set_meta("sprite_3d", billboard.get_child(0))
	# Iter 151: HP bar above the vagrant (hidden until first hit).
	_attach_outlaw_hp_bar(outlaw, OUTLAW_HP)
	_outlaw_spawn_count += 1
	if _outlaw_spawn_count == 1 or _outlaw_spawn_count % 5 == 0:
		DebugLog.add("outlaw spawn #%d at x=%.1f z=%.1f (outlaws_root.size=%d)" % [
			_outlaw_spawn_count, lane_x, outlaw.position.z, outlaws_root.get_child_count(),
		])

# Iter 116: SHARED-SubViewport video billboards. Each unique VideoStream
# gets ONE SubViewport attached at Level3D scene root (NOT inside the
# main Terrain3D/SubViewport). All enemies sharing that stream reference
# the same ViewportTexture, so they animate in lockstep — acceptable
# visual quirk; the alternative is per-enemy SubViewports, which don't
# render on Android Vulkan when nested inside the main SubViewport.
#
# iter 114's static-PNG sideload confirmed the nesting was the bug:
# vagrants WERE being spawned (logs showed outlaws_root.size=1) but
# the inner SubViewport never got its render pass propagated.
const _CHROMAKEY_SHADER := preload("res://shaders/chromakey.gdshader")
# Iter 130: breathing/sway shader for paper-cutout props. Single shader
# instance reused across all prop billboards; per-instance variation via
# uniforms (sway_amp/freq, bob_amp/freq, time_offset, damage/bonk pulses).
const _BREATHING_SHADER := preload("res://shaders/breathing_prop.gdshader")

# Iter 130: helper to create a billboard prop sprite with the breathing
# shader applied. Returns a MeshInstance3D with a subdivided PlaneMesh
# (needed because vertex displacement requires more than 4 verts to
# read as wave motion — Sprite3D's 4-vert quad can only flap corners).
#
# Args:
#   texture        — Texture2D for the prop (alpha-cutout PNG)
#   width, height  — world-space size (matches Sprite3D's pixel_size scaling)
#   sway_amp/freq  — top-vertex lateral wobble in world units / Hz
#   bob_amp/freq   — full-mesh breathing pulse magnitude / Hz
# Per-spawn random time_offset is set so props don't sway in unison.
func _make_breathing_prop(
		texture: Texture2D,
		width: float,
		height: float,
		sway_amp: float = 0.06,
		sway_freq: float = 1.5,
		bob_amp: float = 0.015,
		bob_freq: float = 2.2,
		) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(width, height)
	plane.subdivide_width = 5
	plane.subdivide_depth = 7
	# orientation 2 = FACE_Z (vertical plane facing +Z) which lines up
	# with our billboard shader's expected mesh frame.
	plane.orientation = 2
	mesh.mesh = plane
	var mat := ShaderMaterial.new()
	mat.shader = _BREATHING_SHADER
	if texture != null:
		mat.set_shader_parameter("albedo_tex", texture)
	else:
		# Fallback: 1×1 solid color so the prop is at least visible while
		# the user is still generating PNGs. Color picked from caller via
		# modulate uniform if desired.
		mat.set_shader_parameter("albedo_tex", _PLACEHOLDER_PROP_TEX)
	mat.set_shader_parameter("modulate", Color(1, 1, 1, 1))
	mat.set_shader_parameter("sway_amp", sway_amp)
	mat.set_shader_parameter("sway_freq", sway_freq)
	mat.set_shader_parameter("bob_amp", bob_amp)
	mat.set_shader_parameter("bob_freq", bob_freq)
	mat.set_shader_parameter("time_offset", _rng.randf_range(0.0, 6.28))
	# Iter 148: apply the user-picked puppet sway profile. mesh_height lets
	# the shader anchor squash/lean at the prop's true bottom. sway_intensity
	# reuses the per-prop sway_amp as a 0..N scale (fence baseline 0.06 = 1.0)
	# so buildings barely move while scrub/heroes get the full puppet motion.
	if get_node_or_null("/root/SwayPrefs"):
		mat.set_shader_parameter("sway_profile", SwayPrefs.get_profile())
	mat.set_shader_parameter("sway_intensity", sway_amp / 0.06)
	mat.set_shader_parameter("mesh_height", height)
	mesh.material_override = mat
	return mesh

# Iter 130: 64×96 transparent-checker placeholder texture for props
# that don't yet have a real PNG. Filled procedurally on first call.
var _PLACEHOLDER_PROP_TEX: Texture2D = null

# Iter 131: NB2-generated prop PNG slot registry. Each entry declares
# the expected file path + nominal world size + per-type sway params.
# When user drops a real PNG at the listed path, it slots into the
# breathing system automatically (no code changes needed). Missing
# PNGs fall back to the magenta-checker placeholder so it's obvious
# what's not yet generated.
#
# All paths under res://assets/sprites/props/ — keep that directory
# clean so the user can rsync NB2 batches in/out without affecting
# character sprites in res://assets/sprites/.
const PROP_TEX_REGISTRY: Dictionary = {
	# Cacti — 3 variants for visual variety along the road shoulder.
	"cactus_saguaro":  {"path": "res://assets/sprites/props/cactus_saguaro.png",  "w": 1.4, "h": 2.8, "sway_amp": 0.04, "bob_amp": 0.012},
	"cactus_barrel":   {"path": "res://assets/sprites/props/cactus_barrel.png",   "w": 1.2, "h": 1.4, "sway_amp": 0.02, "bob_amp": 0.020},
	"cactus_prickly":  {"path": "res://assets/sprites/props/cactus_prickly.png",  "w": 1.3, "h": 1.6, "sway_amp": 0.03, "bob_amp": 0.018},
	# Rocks (mostly static; tiny bob)
	"rock_small":      {"path": "res://assets/sprites/props/rock_small.png",      "w": 0.8, "h": 0.6, "sway_amp": 0.0,  "bob_amp": 0.008},
	"rock_large":      {"path": "res://assets/sprites/props/rock_large.png",      "w": 1.4, "h": 1.1, "sway_amp": 0.0,  "bob_amp": 0.006},
	# Fence post (rigid, slight sway as if wind hits it)
	"fence_post":      {"path": "res://assets/sprites/props/fence_post.png",      "w": 0.4, "h": 1.1, "sway_amp": 0.05, "bob_amp": 0.0},
	# Scrub / sagebrush — most flexible, biggest sway
	"scrub":           {"path": "res://assets/sprites/props/scrub.png",           "w": 1.0, "h": 0.6, "sway_amp": 0.10, "bob_amp": 0.022},
	# Iter 155: grass tuft — ground cover, flexible, lively wind sway
	"grass_tuft":      {"path": "res://assets/sprites/props/grass_tuft.png",      "w": 0.9, "h": 0.7, "sway_amp": 0.13, "bob_amp": 0.020},
	# Buildings — near-zero sway (heavy timber doesn't breathe), tiny bob
	"building_saloon":         {"path": "res://assets/sprites/props/building_saloon.png",         "w": 4.5, "h": 5.5, "sway_amp": 0.003, "bob_amp": 0.004},
	"building_general_store":  {"path": "res://assets/sprites/props/building_general_store.png",  "w": 4.5, "h": 5.5, "sway_amp": 0.003, "bob_amp": 0.004},
	"building_bank":           {"path": "res://assets/sprites/props/building_bank.png",           "w": 4.5, "h": 5.5, "sway_amp": 0.003, "bob_amp": 0.004},
	"building_jail":           {"path": "res://assets/sprites/props/building_jail.png",           "w": 4.5, "h": 5.0, "sway_amp": 0.003, "bob_amp": 0.004},
	"building_stables":        {"path": "res://assets/sprites/props/building_stables.png",        "w": 5.0, "h": 4.5, "sway_amp": 0.003, "bob_amp": 0.004},
	# Tumbleweed — for FUTURE conversion of obstacle CSGSphere. Tumble
	# applied via UV-rotation in a shader variant (iter 132+).
	"tumbleweed":      {"path": "res://assets/sprites/props/tumbleweed.png",      "w": 1.4, "h": 1.4, "sway_amp": 0.0,  "bob_amp": 0.020},
}

# Iter 131: try-load a prop texture by slug. Returns null if the file
# isn't there yet (user hasn't generated it). Caller wraps with the
# placeholder fallback inside _make_breathing_prop.
func _load_prop_tex(slug: String) -> Texture2D:
	var entry: Variant = PROP_TEX_REGISTRY.get(slug, null)
	if entry == null:
		return null
	var path: String = entry.path
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D

# Iter 131: convenience — spawn a fully-configured breathing prop by
# slug (looks up registry entry for w/h/sway/bob). Falls back to
# placeholder texture if PNG missing. Returns MeshInstance3D positioned
# with bottom at y=0 so the caller just sets x/z.
func _spawn_prop_from_slug(slug: String, x: float, z: float, parent: Node) -> MeshInstance3D:
	var entry: Variant = PROP_TEX_REGISTRY.get(slug, null)
	if entry == null:
		push_warning("unknown prop slug: %s" % slug)
		return null
	var tex: Texture2D = _load_prop_tex(slug)
	var prop: MeshInstance3D = _make_breathing_prop(
		tex, entry.w, entry.h, entry.sway_amp, 1.5, entry.bob_amp, 2.2)
	# Plane is centered on origin; raise so bottom touches y=0
	prop.position = Vector3(x, entry.h * 0.5, z)
	parent.add_child(prop)
	return prop

func _ensure_placeholder_prop_tex() -> void:
	if _PLACEHOLDER_PROP_TEX != null:
		return
	var img := Image.create(64, 96, false, Image.FORMAT_RGBA8)
	# Magenta-on-transparent checker so "missing texture" is obvious
	for y in range(96):
		for x in range(64):
			var checker: bool = ((x / 8) + (y / 8)) % 2 == 0
			img.set_pixel(x, y, Color(0.95, 0.30, 0.85, 1) if checker else Color(0.20, 0.10, 0.20, 1))
	_PLACEHOLDER_PROP_TEX = ImageTexture.create_from_image(img)

# Iter 130: trigger a one-shot damage pulse on a breathing prop. Tweens
# damage_strength 1.0 → 0.0 over 0.4s. Use this when a bullet hits a
# scenery prop, or when an enemy melees a cactus, etc.
func _damage_pulse_prop(mesh_inst: MeshInstance3D) -> void:
	if mesh_inst == null or not is_instance_valid(mesh_inst):
		return
	var mat: ShaderMaterial = mesh_inst.material_override as ShaderMaterial
	if mat == null:
		return
	var tw: Tween = create_tween()
	tw.tween_method(_set_damage_strength.bind(mat), 1.0, 0.0, 0.4) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _set_damage_strength(value: float, mat: ShaderMaterial) -> void:
	if mat != null:
		mat.set_shader_parameter("damage_strength", value)

# Iter 130: bonk-squash pulse. Tweens bonk_squash 1.0 → 0.6 → 1.0 over
# 0.25s. Triggered by collisions where the prop doesn't break (e.g.,
# tumbleweed bouncing off a fence).
func _bonk_pulse_prop(mesh_inst: MeshInstance3D) -> void:
	if mesh_inst == null or not is_instance_valid(mesh_inst):
		return
	var mat: ShaderMaterial = mesh_inst.material_override as ShaderMaterial
	if mat == null:
		return
	var tw: Tween = create_tween()
	tw.tween_method(_set_bonk_squash.bind(mat), 1.0, 0.6, 0.08) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_method(_set_bonk_squash.bind(mat), 0.6, 1.0, 0.17) \
		.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)

func _set_bonk_squash(value: float, mat: ShaderMaterial) -> void:
	if mat != null:
		mat.set_shader_parameter("bonk_squash", value)
const _BILLBOARD_VIEWPORT_PX := Vector2i(256, 448)  # iter 144: 150×270 → 256×448 (user: "Pete animation dim pixelated")
var _shared_video_viewports: Dictionary = {}  # VideoStream → SubViewport

func _get_or_create_shared_video_viewport(stream: VideoStream) -> SubViewport:
	if _shared_video_viewports.has(stream):
		return _shared_video_viewports[stream]
	var sv := SubViewport.new()
	sv.size = _BILLBOARD_VIEWPORT_PX
	sv.transparent_bg = true
	sv.disable_3d = true
	sv.render_target_update_mode = 4  # SubViewport.UPDATE_ALWAYS
	# Add at Level3D scene root — NOT inside the main SubViewport.
	# This is the whole point of the iter 116 refactor.
	add_child(sv)
	var vp := VideoStreamPlayer.new()
	vp.stream = stream
	vp.autoplay = true
	vp.loop = true
	vp.expand = true
	vp.size = Vector2(_BILLBOARD_VIEWPORT_PX)
	var mat := ShaderMaterial.new()
	mat.shader = _CHROMAKEY_SHADER
	mat.set_shader_parameter("chroma_color", Color(0, 1, 0, 1))
	# Iter 147: similarity 0.22 → 0.12 (stricter — only near-exact green is
	# keyed out). User reported "Pete's chromakey is messy. parts of his body
	# are transparent" — 0.22 was wide enough to eat costume colors that
	# leaned green-ish.
	mat.set_shader_parameter("similarity", 0.12)
	mat.set_shader_parameter("blend_amount", 0.10)
	vp.material = mat
	sv.add_child(vp)
	_shared_video_viewports[stream] = sv
	var stream_path: String = stream.resource_path if stream != null else "<null>"
	DebugLog.add("shared video viewport created for %s (count=%d)" % [
		stream_path.get_file(), _shared_video_viewports.size(),
	])
	return sv

func _make_video_billboard(
	stream: VideoStream,
	world_height: float,
	viewport_px: Vector2i = _BILLBOARD_VIEWPORT_PX,
) -> Node3D:
	var sv: SubViewport = _get_or_create_shared_video_viewport(stream)
	var wrap := Node3D.new()
	var sprite := Sprite3D.new()
	sprite.texture = sv.get_texture()
	sprite.pixel_size = world_height / float(viewport_px.y)
	sprite.billboard = 1   # BILLBOARD_ENABLED
	sprite.alpha_cut = 0   # ALPHA_CUT_DISABLED — chromakey's smooth edge needs alpha blending
	# Iter 143: force LINEAR filter so smaller-billboard scaling stays smooth
	# (user reported Pete looking pixelated after iter 142's 16.8→7.0 height
	# shrink). Default texture_filter inherits from project; explicit override
	# guarantees consistent quality regardless of project setting.
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	wrap.add_child(sprite)
	return wrap

# ── Cowboy / posse video animation ───────────────────────────────────────
# The leader cowboy is one video billboard whose stream swaps by level
# state. The follower crowd can't each own a video decoder — Android
# won't run two dozen — so the crowd draws from a small POOL: run_shoot
# at a few phase offsets plus one idle clip. Each follower keeps a
# fixed random pool slot, which de-syncs the crowd.
var _cowboy_anim_stream: VideoStream = null
var _posse_run_pool: Array[SubViewport] = []
var _posse_idle_pool: Array[SubViewport] = []
var _posse_anim_group: String = "run"
const POSSE_RUN_PHASES: int = 2

func _make_posse_viewport(stream: VideoStream) -> SubViewport:
	var sv := SubViewport.new()
	sv.size = _BILLBOARD_VIEWPORT_PX
	sv.transparent_bg = true
	sv.disable_3d = true
	sv.render_target_update_mode = 4  # UPDATE_ALWAYS
	add_child(sv)
	var vp := VideoStreamPlayer.new()
	vp.stream = stream
	vp.autoplay = true
	vp.loop = true
	vp.expand = true
	vp.size = Vector2(_BILLBOARD_VIEWPORT_PX)
	var mat := ShaderMaterial.new()
	mat.shader = _CHROMAKEY_SHADER
	mat.set_shader_parameter("chroma_color", Color(0, 1, 0, 1))
	mat.set_shader_parameter("similarity", 0.12)
	mat.set_shader_parameter("blend_amount", 0.10)
	vp.material = mat
	sv.add_child(vp)
	# Deferred scrub so the player has started — a random start position
	# de-syncs two pool viewports that play the same clip.
	vp.call_deferred("set", "stream_position", _rng.randf() * 3.6)
	return sv

func _build_posse_pool() -> void:
	if not _posse_run_pool.is_empty():
		return
	for i in range(POSSE_RUN_PHASES):
		_posse_run_pool.append(_make_posse_viewport(COWBOY_RUN_FWD_STREAM))
	# One idle viewport — idle is a frozen-state look, not worth a decoder
	# per variant. iter 178 cut the pool 6 → 3 for frame rate.
	_posse_idle_pool.append(_make_posse_viewport(COWBOY_IDLE_STREAMS[0]))
	DebugLog.add("posse pool: %d run + %d idle viewports" % [
		_posse_run_pool.size(), _posse_idle_pool.size()])

# Texture for a follower at pool slot `slot`, in the current anim group.
func _posse_pool_texture(slot: int) -> Texture2D:
	var pool: Array[SubViewport] = (_posse_idle_pool
		if _posse_anim_group == "idle" else _posse_run_pool)
	if pool.is_empty():
		return null
	return pool[slot % pool.size()].get_texture()

# Swap the leader cowboy's video stream (no-op if already on it).
func _set_cowboy_anim(stream: VideoStream) -> void:
	if stream == null or stream == _cowboy_anim_stream:
		return
	if cowboy_3d == null or not is_instance_valid(cowboy_3d):
		return
	# Reuse a pool viewport for the two most common streams so the leader
	# doesn't spin up its own decoder for them (perf — iter 178).
	var sv: SubViewport
	if stream == COWBOY_RUN_FWD_STREAM and not _posse_run_pool.is_empty():
		sv = _posse_run_pool[0]
	elif stream in COWBOY_IDLE_STREAMS and not _posse_idle_pool.is_empty():
		sv = _posse_idle_pool[0]
	else:
		sv = _get_or_create_shared_video_viewport(stream)
	cowboy_3d.texture = sv.get_texture()
	_cowboy_anim_stream = stream

# Per-frame: choose the cowboy + crowd animation from the level state.
func _update_cowboy_anim() -> void:
	if cowboy_3d == null or not is_instance_valid(cowboy_3d):
		return
	var group := "run"
	var leader: VideoStream = COWBOY_RUN_FWD_STREAM
	var dx: float = _target_x - cowboy_3d.position.x
	if _level_state == LevelState.COUNTDOWN:
		group = "idle"
		leader = COWBOY_IDLE_STREAMS[0]
	elif _level_state == LevelState.FINISHED:
		group = "idle"
		leader = (COWBOY_CELEBRATE_STREAMS[0] if _pete_defeated
			else COWBOY_IDLE_STREAMS[0])
	elif _cart_encounter:
		# World frozen but the player can still steer → strafe in place.
		group = "idle"
		if dx < -0.25:
			leader = COWBOY_STRAFE_LEFT_STREAM
		elif dx > 0.25:
			leader = COWBOY_STRAFE_RIGHT_STREAM
		else:
			leader = COWBOY_STAND_SHOOT_STREAM
	elif _level_state == LevelState.BOSS:
		group = "idle"
		leader = COWBOY_STAND_SHOOT_STREAM
	else:
		# PLAYING and moving — steering picks the directional run clip.
		if dx < -0.25:
			leader = COWBOY_RUN_LEFT_STREAM
		elif dx > 0.25:
			leader = COWBOY_RUN_RIGHT_STREAM
	_set_cowboy_anim(leader)
	if group != _posse_anim_group:
		_posse_anim_group = group
		for f in _followers:
			if is_instance_valid(f):
				var tex: Texture2D = _posse_pool_texture(f.get_meta("pool_slot", 0))
				if tex != null:
					f.texture = tex

# Iter 76: outlaw fires a red bullet aimed at the cowboy.
func _outlaw_fire(outlaw: Node3D) -> void:
	var b := CSGSphere3D.new()
	b.radius = OUTLAW_BULLET_RADIUS
	b.radial_segments = 8
	b.rings = 6
	var mat := StandardMaterial3D.new()
	# Iter 124/136: bright emission + larger bullet so the player can
	# see incoming fire and dodge it. iter 136 also adds an unshaded
	# render so bullets glow consistently even in low-light scenes.
	mat.albedo_color = Color(1.00, 0.20, 0.15, 1)
	mat.emission_enabled = true
	mat.emission = Color(1.00, 0.40, 0.25, 1)
	mat.emission_energy_multiplier = 2.5
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	b.material = mat
	# Iter 146: bullet emerges from gun-height (outlaw.position.y + 0.5
	# offset). User reported "bullets do not emerge from Pete's guns, they
	# emerge from between his legs" — iter 135 had clamped Y=1.0 for ALL
	# outlaws which puts Pete's bullet (Pete y=3.5) below his crotch. Now
	# the ballistic Y velocity descends to cowboy chest height by arrival
	# so the collision check (x-z plane) still hits correctly.
	b.position = outlaw.position
	b.position.y = outlaw.position.y + 0.5
	var to_cowboy_xz: Vector3 = cowboy_3d.position - outlaw.position
	to_cowboy_xz.y = 0.0
	var xz_dist: float = to_cowboy_xz.length()
	var vel: Vector3
	if xz_dist > 0.001:
		vel = to_cowboy_xz.normalized() * OUTLAW_BULLET_SPEED
		var travel_time: float = xz_dist / OUTLAW_BULLET_SPEED
		# Drop from gun-height to cowboy chest (~1.0) over the travel time.
		var y_drop: float = b.position.y - 1.0
		vel.y = -y_drop / max(travel_time, 0.001)
	else:
		vel = Vector3(0, 0, OUTLAW_BULLET_SPEED)
	b.set_meta("velocity", vel)
	outlaw_bullets_root.add_child(b)

var _process_first_tick_logged: bool = false
# Iter 124: test-range mode flag, mirrors 2D level.gd's _test_range_mode.
# When DebugPreview.pending_test_range is set, level_3d._ready strips
# normal outlaw/prospector spawning and seeds a static cactus grid for
# weapon-tuning practice (cowboy can shoot, nothing fires back).
var _test_range_mode: bool = false
# Iter 125: preview mode — when true, the scene is hosting a debug
# ceremony (rush / sugar / weapon / hero) and normal gameplay flow is
# suspended (no gates, no outlaws, no Pete, no fail state).
var _preview_mode: bool = false
const TEST_RANGE_ROWS: int = 6
const TEST_RANGE_COLS: int = 5
const TEST_RANGE_SPACING_X: float = 1.0
const TEST_RANGE_SPACING_Z: float = 2.5
# Iter 123: gate-combo tracking (ported from 2D level.gd's iter-41
# flourish system). _gate_combo_decay counts down each frame after the
# last gate; if it expires before the next gate, the streak resets.
const GATE_COMBO_DECAY_TIME: float = 2.5
var _gate_combo_count: int = 0
var _gate_combo_decay: float = 0.0

func _process(delta: float) -> void:
	if not _process_first_tick_logged:
		_process_first_tick_logged = true
		DebugLog.add("_process first tick — game loop is running, state=%d" % _level_state)
	# Swap the cowboy + crowd video clips to match the level state.
	_update_cowboy_anim()
	if _pete_defeated or _failed:
		_level_state = LevelState.FINISHED
		return
	# Iter 123: tick the gate combo decay. When it hits 0 the streak
	# resets — so the player has to keep chaining gates to climb the
	# DOUBLE → MEGA → RAMPAGE banner ladder.
	if _gate_combo_decay > 0.0:
		_gate_combo_decay -= delta
		if _gate_combo_decay <= 0.0:
			_gate_combo_count = 0
	# Iter 120: terrain UV scroll is independent of the obstacle/scenery
	# motion_delta gate — it lives in terrain_3d.gd as its own _process
	# animating uv1_offset. Call set_scroll_active() so the dirt freezes
	# during COUNTDOWN and BOSS too (matching the visual stop).
	if terrain_3d_node != null and terrain_3d_node.has_method("set_scroll_active"):
		terrain_3d_node.set_scroll_active(_level_state == LevelState.PLAYING)
	# Iter 118: COUNTDOWN phase — show 3/2/1/GO, freeze world motion.
	if _level_state == LevelState.COUNTDOWN:
		_countdown_remaining -= delta
		_render_countdown()
		if _countdown_remaining <= -0.6:
			_level_state = LevelState.PLAYING
			DebugLog.add("level state: COUNTDOWN → PLAYING")
		return
	# Iter 110 cowboy lerp: runs in PLAYING + BOSS so the player can
	# still steer + fire during the boss duel.
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
		# Iter 119: clamp follower target to the visible road so when the
		# leader nears the edge, followers bunch up at the same edge
		# instead of trailing off-screen.
		var target_fx: float = clampf(cowboy_3d.position.x + offset.x,
			-COWBOY_X_BOUND, COWBOY_X_BOUND)
		f.position.x = lerpf(f.position.x, target_fx,
			clampf(FOLLOWER_LERP_SPEED * delta, 0.0, 1.0))
		# Phase offset per follower so the crowd looks alive.
		f.position.y = 0.45 + sin(_bob_time * BOB_FREQUENCY + float(i) * 0.7) * BOB_AMPLITUDE
	# Iter 178: drive the pushed-wagon / captive cart encounter. This
	# updater was defined but never called, so the cart-freeze and the
	# pusher mechanic never ran — fixes carts not stopping the scroll.
	if _level_state == LevelState.PLAYING or _level_state == LevelState.BOSS:
		_update_pushed_wagons(delta)
	# Iter 118: world motion delta — 0 during BOSS so obstacles/gates/
	# outlaws/scenery freeze in place during the duel. Cowboy steering +
	# bullets + Pete continue to update on the real delta.
	var motion_delta: float = delta if (_level_state == LevelState.PLAYING and not _cart_encounter) else 0.0
	# Spawn obstacles periodically (PLAYING only).
	if _level_state != LevelState.PLAYING:
		_spawn_timer = OBSTACLE_SPAWN_INTERVAL  # reset so they don't pile up
	_spawn_timer -= delta
	if _level_state == LevelState.PLAYING and _spawn_timer <= 0.0:
		_spawn_timer = OBSTACLE_SPAWN_INTERVAL
		_spawn_obstacle()
	# Move all obstacles toward camera (z increases since camera is at z>0).
	# Iter 87: tumbleweeds (CSGSphere3D) rotate as they roll forward —
	# adds life vs just sliding rigid shapes. Other shapes (barrel /
	# cactus / bull boxes) stay rigid since they don't roll IRL.
	for child in obstacles_root.get_children():
		if child is Node3D:
			child.position.z += OBSTACLE_SPEED * motion_delta
			if child is CSGSphere3D:
				child.rotation.x += OBSTACLE_SPEED * motion_delta * 0.5
			if child.position.z > OBSTACLE_DESPAWN_Z:
				child.queue_free()
	# Iter 75: gates scroll like obstacles + check trigger when crossing z plane
	_gate_spawn_timer -= delta
	if _gate_spawn_timer <= 0.0:
		_gate_spawn_timer = GATE_SPAWN_INTERVAL
		_spawn_gate()
	for gate in gates_root.get_children():
		if gate is Node3D:
			gate.position.z += OBSTACLE_SPEED * motion_delta
			_check_gate_trigger(gate)
			if gate.position.z > OBSTACLE_DESPAWN_Z:
				gate.queue_free()
	# Iter 76: outlaws — spawn / scroll / fire / despawn.
	# Iter 118: only spawn during PLAYING (not BOSS — boss fight has its
	# own focus). Outlaws already spawned keep moving via _world_motion.
	# Iter 124: skip all outlaw + prospector spawning in test range mode
	# (cactus-only practice — nothing fires back).
	if _level_state == LevelState.PLAYING and not _test_range_mode:
		_outlaw_spawn_timer -= delta
		if _outlaw_spawn_timer <= 0.0:
			_outlaw_spawn_timer = OUTLAW_SPAWN_INTERVAL
			_spawn_outlaw()
		# Iter 118: prospector spawn (rarer, alongside outlaws).
		_prospector_spawn_timer -= delta
		if _prospector_spawn_timer <= 0.0:
			_prospector_spawn_timer = PROSPECTOR_SPAWN_INTERVAL
			_spawn_prospector()
	for outlaw in outlaws_root.get_children():
		if not (outlaw is Node3D):
			continue
		# Iter 120: dying outlaws skip movement + fire + collision and
		# just tick their death timer. queue_free when the death.ogv
		# animation has played out.
		if outlaw.get_meta("dying", false):
			var dt: float = outlaw.get_meta("death_timer", 0.0) - delta
			outlaw.set_meta("death_timer", dt)
			if dt <= 0.0:
				outlaw.queue_free()
			continue
		# Iter 120: slow z-scroll once outlaw is close to the cowboy so
		# they cluster around the posse instead of marching past at
		# constant speed. Beyond cowboy_z - 2.0 (= still in front), full
		# OUTLAW_SPEED. Within 2.0 of cowboy_z, slow to 20% speed.
		var z_speed: float = OUTLAW_SPEED
		if outlaw.position.z > cowboy_3d.position.z - 2.0:
			z_speed = OUTLAW_SPEED * 0.20
		# Iter 173: the pushed cart + its pushers freeze in z — during a
		# cart encounter the whole world's forward scroll is paused anyway
		# (terrain + props), so the cart stays in lockstep with the ground.
		if outlaw.get_meta("is_pushed", false) or outlaw.get_meta("is_pusher", false):
			z_speed = 0.0
		# Iter 136: real delta (not motion_delta) so outlaws keep advancing
		# on the posse even while the world scroll is paused / during BOSS.
		outlaw.position.z += z_speed * delta
		# Iter 120: x-tracking with PER-OUTLAW offset (set at spawn).
		# Each outlaw heads for cowboy.x + their personal offset so the
		# group reads as a crowd, not a column. Clamped to road bounds.
		var ox: float = outlaw.get_meta("track_offset_x", 0.0)
		var target_x: float = clampf(cowboy_3d.position.x + ox,
			-COWBOY_X_BOUND, COWBOY_X_BOUND)
		# Iter 164: the set-piece doesn't x-track the posse — the wagon
		# "tracking the posse" was this lerp. Pushers move it instead.
		if outlaw.get_meta("is_pushed", false) or outlaw.get_meta("is_pusher", false):
			target_x = outlaw.position.x
		# Iter 136: real delta so x-tracking continues during BOSS state too
		outlaw.position.x = lerpf(outlaw.position.x, target_x,
			clampf(1.5 * delta, 0.0, 1.0))
		var ft: float = outlaw.get_meta("fire_timer", 0.0)
		ft -= delta
		if ft <= 0.0:
			ft = OUTLAW_FIRE_INTERVAL
			# Iter 121: only fire when within OUTLAW_FIRE_RANGE_Z of cowboy z.
			# Halves the effective bullet range — far outlaws hold their fire
			# until they're close enough to be visually threatening.
			var z_gap: float = cowboy_3d.position.z - outlaw.position.z
			if z_gap >= 0.0 and z_gap <= OUTLAW_FIRE_RANGE_Z:
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
				# Iter 134: pushers route to specialized 1-shot-kill handler.
				if outlaw.get_meta("is_pusher", false):
					_pusher_take_damage(outlaw)
					bullet.queue_free()
					break
				# Iter 133: captives route to specialized damage handler
				# (HP scales with hero tier, no death-stream, release ceremony).
				if outlaw.get_meta("is_captive", false):
					_captive_take_damage(outlaw, bullet.position)
					bullet.queue_free()
					break
				var hp: int = outlaw.get_meta("hp", 1) - 1
				outlaw.set_meta("hp", hp)
				_refresh_outlaw_hp_bar(outlaw)  # iter 151
				_spawn_popup_3d(outlaw.position + Vector3(0, 1.2, 0),
					"-1", Color(1, 0.32, 0.22, 1), 56)
				bullet.queue_free()
				if hp <= 0:
					# Iter 120: swap to vagrant death stream + delay
					# queue_free so the death animation plays. The
					# shared-SubViewport pattern means all dying outlaws
					# share one death-stream render (they sync, acceptable).
					outlaw.set_meta("dying", true)
					outlaw.set_meta("death_timer", VAGRANT_DEATH_LIFETIME)
					var death_sprite: Sprite3D = outlaw.get_meta("sprite_3d", null)
					if death_sprite != null and is_instance_valid(death_sprite):
						var death_sv: SubViewport = _get_or_create_shared_video_viewport(VAGRANT_DEATH_STREAM)
						death_sprite.texture = death_sv.get_texture()
					_hits += 1
					_refresh_hud()
				break
	# Iter 76: outlaw bullets move along their stored velocity vector.
	# Despawn off-screen or after reaching cowboy.
	# Iter 149: special posse members — formation-follow + skill ticks.
	_update_special_followers(delta)
	for ob in outlaw_bullets_root.get_children():
		if not (ob is Node3D):
			continue
		var vel: Vector3 = ob.get_meta("velocity", Vector3.ZERO)
		ob.position += vel * delta
		# Iter 149: outlaw bullets can strike a special follower anywhere
		# along their flight path (heroes flank the posse front, off the
		# leader's lane). Hit → damage that follower, consume the bullet.
		var sf_struck: bool = false
		for e in _special_followers:
			var sfn: Sprite3D = e["node"]
			if sfn == null or not is_instance_valid(sfn):
				continue
			var sdx: float = ob.position.x - sfn.position.x
			var sdz: float = ob.position.z - sfn.position.z
			if sdx * sdx + sdz * sdz < SPECIAL_FOLLOWER_HIT_RADIUS_SQ:
				_damage_special_follower(e, 1)
				ob.queue_free()
				sf_struck = true
				break
		if sf_struck:
			continue
		# Posse-hit: if bullet reaches cowboy's near plane, decrement
		# posse and kill the bullet.
		if ob.position.z > cowboy_3d.position.z - 0.3:
			# Iter 119: dodgeable bullet — only damage if it crosses
			# CLOSE to the leader OR any follower (x distance check).
			# If the player swerves out of the way, the bullet expires
			# without harming anyone. Hitting a follower kills the
			# tail-end of the posse (handled by _sync_followers_to_count
			# popping from the back); the leader Sprite3D stays put.
			var bx: float = ob.position.x
			var min_dx: float = absf(bx - cowboy_3d.position.x)
			for f in _followers:
				if is_instance_valid(f):
					min_dx = minf(min_dx, absf(bx - f.position.x))
			ob.queue_free()
			if min_dx < OUTLAW_BULLET_HIT_X:
				_posse_count_3d = maxi(0, _posse_count_3d - 1)
				_refresh_hud()
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
		s.position.z += OBSTACLE_SPEED * motion_delta
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
		bonus.position.z += BONUS_SPEED * motion_delta
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
	# Iter 118: only counts elapsed during PLAYING.
	# Iter 124: skip Pete in test range mode.
	if _level_state == LevelState.PLAYING and not _pete_spawned and not _test_range_mode and _level_elapsed >= PETE_SPAWN_DELAY:
		_pete_spawned = true
		# Iter 157: boss dispatch by level — level 2 → The Candy Rustler,
		# every other level → Slippery Pete.
		if _boss_kind() == "rustler":
			_spawn_candy_rustler()
		else:
			_spawn_pete()
		_level_state = LevelState.BOSS
		DebugLog.add("level state: PLAYING → BOSS (kind=%s)" % _boss_kind())
	# Iter 77: Pete behavior — approach to PETE_STAY_Z, fire periodically,
	# check bullet hits.
	if _pete_spawned and boss_root.get_child_count() > 0:
		var pete: Node3D = boss_root.get_child(0)
		if is_instance_valid(pete) and pete is Node3D and pete.get_meta("boss_kind", "pete") != "rustler":
			# Iter 146: anim revert timer — if running, count down; on
			# expiry switch Pete back to IDLE.
			var revert_t: float = pete.get_meta("anim_revert_t", 0.0)
			if revert_t > 0.0:
				revert_t -= delta
				if revert_t <= 0.0:
					_set_pete_anim(pete, PETE_IDLE_STREAM, 0.0)
				else:
					pete.set_meta("anim_revert_t", revert_t)
			# Approach until STAY_Z — use FORWARD animation while walking
			if pete.position.z < PETE_STAY_Z:
				pete.position.z += PETE_SPEED * delta
				# Only switch to FORWARD if not currently in a transient
				# (e.g., shout / shoot still has time left).
				if revert_t <= 0.0:
					var current: Sprite3D = pete.get_meta("video_sprite", null) as Sprite3D
					var forward_sv: SubViewport = _get_or_create_shared_video_viewport(PETE_FORWARD_STREAM)
					if current != null and current.texture != forward_sv.get_texture():
						_set_pete_anim(pete, PETE_FORWARD_STREAM, 0.0)
			else:
				# Iter 119: Pete is at duel distance. After
				# PETE_MELEE_TRIGGER_T seconds of holding still, he
				# starts advancing toward the cowboy at MELEE_ADVANCE_SPEED.
				# Once within MELEE_RANGE of the leader, deal MELEE_DPS
				# damage per second of contact.
				_pete_stay_elapsed += delta
				if _pete_stay_elapsed >= PETE_MELEE_TRIGGER_T:
					var dx_pete: float = absf(pete.position.x - cowboy_3d.position.x)
					var dz_pete: float = absf(pete.position.z - cowboy_3d.position.z)
					var dist_pete: float = sqrt(dx_pete * dx_pete + dz_pete * dz_pete)
					if dist_pete > PETE_MELEE_RANGE:
						pete.position.z += PETE_MELEE_ADVANCE_SPEED * delta
					else:
						# Melee contact — drain posse at MELEE_DPS rate.
						_pete_melee_tick_accum += delta * PETE_MELEE_DPS
						while _pete_melee_tick_accum >= 1.0:
							_pete_melee_tick_accum -= 1.0
							# Iter 149: a special follower near Pete soaks the
							# melee hit before the generic posse does.
							var sf_pete: Dictionary = _nearest_special_follower(
								pete.position, PETE_MELEE_RANGE + 2.0)
							if not sf_pete.is_empty():
								_damage_special_follower(sf_pete, 1)
							else:
								_posse_count_3d = maxi(0, _posse_count_3d - 1)
								_sync_followers_to_count(_posse_count_3d)
								_refresh_hud()
			# Fire periodically. Iter 122: Pete only fires when within
			# OUTLAW_FIRE_RANGE_Z of cowboy z (= within camera frustum
			# foreground). Same gate as regular outlaws — holds fire
			# during the long approach walk, opens up once he's close
			# enough for the player to see the gun telegraph.
			_pete_fire_timer -= delta
			if _pete_fire_timer <= 0.0:
				_pete_fire_timer = PETE_FIRE_INTERVAL
				var pete_z_gap: float = cowboy_3d.position.z - pete.position.z
				if pete_z_gap >= 0.0 and pete_z_gap <= OUTLAW_FIRE_RANGE_Z:
					_pete_fire()
			# Bullet hit check. Iter 147: removed the per-frame `break` so
			# EVERY bullet overlapping Pete this frame registers a hit. The
			# break consumed only 1 bullet/frame — excess bullets visually
			# flew through Pete (user: "bullets pass through him too").
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
	# Iter 157: the Candy Rustler runs a separate process branch — he is a
	# stationary jointed puppet, not Pete's video-anim/melee actor. The
	# Pete block above is skipped for him via the boss_kind guard on its
	# `if is_instance_valid(...)`.
	if _pete_spawned and boss_root.get_child_count() > 0:
		var rustler_boss: Node3D = boss_root.get_child(0)
		if is_instance_valid(rustler_boss) and rustler_boss.get_meta("boss_kind", "pete") == "rustler":
			_process_rustler(rustler_boss, delta)
	# Iter 115: GunState-driven auto-fire. Replaces the iter-66 fixed
	# fire_timer. tick(delta) advances the cooldown + reload countdown;
	# the while-can_fire loop drains as many shots as the cowboy is
	# entitled to this frame (usually 0-1 depending on cooldown). Each
	# fire() consumes one ammo; ammo=0 → reload kicks in automatically.
	# Iter 118: gate firing on PLAYING + BOSS. Countdown blocks firing.
	if _gun_state != null and _level_state != LevelState.COUNTDOWN:
		_gun_state.tick(delta)
		while _gun_state.can_fire():
			_gun_state.fire()
			_spawn_bullet()
		_refresh_ammo_label_3d()
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
			# Iter 113: was a single smooth sphere with no detail. User
			# called them "featureless spheres". Stack 3 spheres at slight
			# offsets + each with random color jitter so the shape reads as
			# tangled grass-ball instead of a billiard ball. Still CSG —
			# a real tumbleweed mesh is a future asset upgrade.
			var t := Node3D.new()
			for i in range(3):
				var s := CSGSphere3D.new()
				s.radius = 0.7 + _rng.randf_range(-0.1, 0.2)
				s.radial_segments = 12
				s.rings = 8
				var m := StandardMaterial3D.new()
				m.albedo_color = Color(
					_rng.randf_range(0.42, 0.58),
					_rng.randf_range(0.28, 0.38),
					_rng.randf_range(0.10, 0.20),
					1,
				)
				m.roughness = 1.0
				s.material = m
				s.position = Vector3(
					_rng.randf_range(-0.25, 0.25),
					_rng.randf_range(-0.15, 0.15),
					_rng.randf_range(-0.25, 0.25),
				)
				s.scale = Vector3(
					_rng.randf_range(0.85, 1.10),
					_rng.randf_range(0.85, 1.10),
					_rng.randf_range(0.85, 1.10),
				)
				t.add_child(s)
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
	# Iter 136: diagnostic + ensure DebugPreview state is cleared so
	# the reloaded scene doesn't accidentally re-trigger a preview that
	# was pending from the original entry. Also call clear() so test
	# range / captive / pushed flags don't repeat.
	DebugLog.add("RETRY button pressed → reloading scene")
	if get_node_or_null("/root/AudioBus"):
		AudioBus.play_tap()
	if get_node_or_null("/root/DebugPreview") and DebugPreview.has_method("clear"):
		DebugPreview.clear()
	get_tree().reload_current_scene()
