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

# Rainbow Kimmy: her cage only takes damage from rainbow bullets; non-Kimmy
# captives are unaffected by this rule (base damage passes through).
static func kimmy_cage_damage(is_kimmy: bool, bullet_rainbow: bool, base: int) -> int:
	if is_kimmy and not bullet_rainbow:
		return 0
	return base

# Rainbow Kimmy: rescue resolves to "cracked" (freed) the instant cage HP hits
# 0 (even at the buzzer); else "timed_out" when the window is spent; else "ongoing".
static func kimmy_rescue_outcome(cage_hp: int, window_left: float) -> String:
	if cage_hp <= 0:
		return "cracked"
	if window_left <= 0.0:
		return "timed_out"
	return "ongoing"

# Rainbow Kimmy sugar rush: destroy outlaws + destructible obstacles (incl. bulls);
# never the cage/captive (Kimmy) or already-dying nodes. `meta` = the node's flags.
static func kimmy_clears_node(meta: Dictionary) -> bool:
	if meta.get("is_captive", false) or meta.get("is_kimmy", false) or meta.get("dying", false):
		return false
	return true

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
const WIN_MODAL_SCENE := preload("res://scenes/ui/win_modal.tscn")
const FAIL_MODAL_SCENE := preload("res://scenes/ui/fail_modal.tscn")
var _end_modal: Control = null
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

# iter410: bulls are charging hazards (ported from the 2D prototype's bull.gd), not
# static props. They barrel toward the posse faster than other obstacles, soak many
# hits, and gore the posse on contact. Signature beat: when the player shoots a RED
# (shrinking) gate enough to FLIP it BLUE (growing), every bull on screen is
# "confused" — it veers off the track and flees. Makes the gate-flip feel powerful.
const BULL_HP: int = 30
const BULL_CHARGE_MULT: float = 2.4    # z-speed vs other obstacles (charge feel)
const BULL_CONFUSED_FWD_MULT: float = 0.35
const BULL_DRIFT_SPEED: float = 4.0    # lateral veer-off speed while fleeing
const BULL_CONTACT_POSSE_LOSS: int = 8 # posse members gored if a bull reaches them
# winflow R3: a bull is a heavy charging hazard. If one spawns in the very first
# obstacle wave it reaches the posse (~3-4s) before the player has crossed the
# first GATE to grow the posse, so a small starting posse gets wiped (device
# report, level 2). Suppress bulls for an opening grace window so the first gate
# appears + is crossable first. Longer on L2 (smaller start posse, mine terrain).
const BULL_GRACE_DEFAULT: float = 10.0  # seconds before the first bull can charge
const BULL_GRACE_LEVEL2: float = 16.0   # L2: extra lead time to reach the first gate

# iter411: chicken coop set-piece (ported from the 2D prototype). A destructible
# decorative prop; shoot it down and it bursts into scattering chickens + a cloud of
# tumbling feathers — pure visual chaos / a sightline distraction (no posse damage).
const COOP_HP: int = 12
const COOP_SPAWN_INTERVAL: float = 13.0
var _coop_spawn_timer: float = 7.0     # first coop ~7s in
const CHICKEN_TEX: Array = [
	preload("res://assets/sprites/props/chicken_rir.png"),
	preload("res://assets/sprites/props/chicken_leghorn.png"),
	preload("res://assets/sprites/props/chicken_silkie.png"),
]
const FEATHER_TEX: Array = [
	preload("res://assets/sprites/fx/feather_0.png"),
	preload("res://assets/sprites/fx/feather_1.png"),
	preload("res://assets/sprites/fx/feather_2.png"),
]

# SP2 slice3 (curves): the path bends left/right as it recedes. Per the spec's
# (distance, lateral) mechanism, every scrolling entity's world x is offset by the
# path's lateral curve at ITS distance-along-path, minus the curve at the PLAYER's
# distance, so the player's lane stays centred while the road ahead snakes. iter399
# adds the VISIBLE bend: a dirt-road ribbon mesh (built like the level-select trail)
# that follows the same curve and scrolls, so the GROUND reads as curving — uniform
# dirt alone can't show a bend (nothing lateral to deform).
#
# _PATH_KEYS = (distance, x-offset) keyframes over one PATH_PATTERN_LEN, smoothstep-
# interpolated and tiled. This supports BOTH sharp curves (big x-delta over a short
# distance) and gentle ones (small delta over a long distance). First/last y match
# for a seamless wrap. PATH_AMP = max |x-offset| in the pattern (used for clamps).
const PATH_PATTERN_LEN: float = 140.0
const PATH_AMP: float = 8.0
const _PATH_KEYS: Array = [
	Vector2(0.0, 0.0), Vector2(26.0, 0.0),         # straight start
	Vector2(50.0, 5.0),                            # gentle right (24u → gentle)
	Vector2(72.0, 0.0),                            # ease back (22u → gentle)
	Vector2(88.0, -6.0), Vector2(102.0, -6.0),     # sharp left (16u) + hold
	Vector2(120.0, 5.5),                           # sharp right (18u)
	Vector2(140.0, 0.0),                           # ease back to straight (wrap)
]
# iter400: STATIC WORLD. Instead of the UV-scroll treadmill, a real curved + hilly
# terrain mesh is built ONCE in a WorldRoot; the posse "advances" by translating
# WorldRoot by the INVERSE of its path motion (z = distance, x = -path_lateral) so
# the curving path stays centred under the fixed camera (no combat rework). The
# terrain + features are periodic over PATH_PATTERN_LEN so WorldRoot.z wraps
# seamlessly → an endless static-feeling world. Features (hills/holes/puddles) are
# authored by distance within one period — the level-designer coordinate model.
const TERR_HALF_W: float = 26.0        # terrain half-width — extends well past the screen edges both sides
const TERR_DX: float = 2.0
const TERR_Z_BEHIND: float = 12.0      # mesh local-z behind the posse
const TERR_Z_AHEAD: float = -200.0     # ...and far ahead (≥ window + one period, for seamless wrap)
const TERR_DZ: float = 2.0
const HILL_AMP1: float = 1.1           # rolling-hill amplitudes (periods 70 & 35 divide 140 → seamless)
const HILL_AMP2: float = 0.55
const HOLE_DEPTH: float = 4.0
const POSSE_BASE_Y: float = 0.45
const OUTLAW_BASE_Y: float = 1.0   # outlaws spawn at this foot height (see _spawn_outlaw)
# Authored features within one 140u period (the designer will place these later):
const _HOLES: Array = [
	# iter418: narrowed to half-road pits — each leaves a clear dodge lane on the
	# opposite side (road is x in [-3,3]). Now also rendered (see _make_pit).
	{"d0": 38.0, "d1": 46.0, "x0": -3.2, "x1": -0.5},  # left pit  → dodge right
	{"d0": 96.0, "d1": 104.0, "x0": 0.5, "x1": 3.2},   # right pit → dodge left
]
const _PUDDLES: Array = [   # Vector3(distance, x-from-path-centre, radius)
	Vector3(22.0, -2.5, 2.2), Vector3(68.0, 2.0, 2.4), Vector3(126.0, 0.0, 2.0),
]

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
var holes_root: Node3D   # SP2 slice3: pits/cliffs that posse + outlaws fall into
var _world_root: Node3D = null   # SP2 slice3/iter400: static curved+hilly terrain the posse advances through
var _terr_cliff_side: String = ""   # terrain: "left"/"right" cliff edge (mountain), "" = none
var _terr_cliff_depth: float = 0.0
var _hill_scale: float = 1.0   # terrain: per-theme hill amplitude (mountain = steeper)
var _cliff_fall_accum: float = 0.0   # terrain: fractional posse lost over the cliff edge
# iter434: ice-slip — frozen puddles make the cowboy/posse keep momentum with no steering.
var _cowboy_on_ice: bool = false
var _ice_slip_vx: float = 0.0
var _prev_cowboy_x: float = 0.0
var _cowboy_ice_cube: Node3D = null
var _ice_puddles: Array = []   # iter434: cached frozen puddles (slip triggers)
const FrostBoltsScript = preload("res://scripts/frost_bolts.gd")
var _frost_bolts: Node2D = null   # iter404: FROSTBITE chain-lightning overlay
const RainbowBoltsScript = preload("res://scripts/rainbow_bolts.gd")
var _rainbow_bolts: Node2D = null   # kimmy: RAINBOW prism-chain overlay
const MangaFxScript = preload("res://scripts/manga_fx.gd")
var _manga_fx: Control = null   # level5: Raisin Kidd manga FX overlay
const CometStreakScript = preload("res://scripts/comet_streak.gd")
var _comet_streak: Node2D = null   # weapon fx: RIFLE rainbow-comet trail overlay
var outlaw_bullets_root: Node3D
var boss_root: Node3D
# Iter 69: terrain_3d.gd script wasn't attached to the inline Terrain3D
# node in level_3d.tscn, so the SubViewport→Sprite2D texture wiring
# never ran. Reference + manual hookup in _ready below.
@onready var terrain_sprite: Sprite2D = $Terrain3D/Sprite
@onready var back_button: Button = $UI/BackButton
@onready var info_label: Label = $UI/InfoLabel
# Iter 79: dedicated HUD labels.
@onready var hearts_label: HeartCookieRow = $UI/HeartsCutout/HeartCookieRow
@onready var _hud_outlaws: Label = $UI/HeartsCutout/OutlawNumber
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
var _volley_dmg: int = 1   # iter406: per-bullet damage = the posse's per-member firepower
var _kimmy_cue_shown: bool = false   # kimmy: "RAINBOW ONLY" cue shown once per cage
# iter426: rebalanced for winnability — at a small posse (demo POSSE 20) _volley_dmg
# is 1, the cage-hit loop breaks after one bullet/frame (~10 hits/s), so 240 HP / 16 s
# was unwinnable. Per-Kimmy-hit damage now floors at KIMMY_CAGE_HIT_FLOOR, HP is lower,
# and the window is longer — a focused rainbow burst cracks it in ~7s with margin.
const KIMMY_CAGE_HP: int = 150          # cracks under sustained rainbow fire within the window
const KIMMY_CAGE_HIT_FLOOR: int = 2     # min cage damage per rainbow hit (bigger posse > this)
const KIMMY_RESCUE_WINDOW: float = 20.0 # seconds before the pushers haul her off
var _kimmy_captive: Node3D = null
var _kimmy_window_left: float = 0.0
var _kimmy_countdown: Label = null   # kimmy: rainbow strobing rescue-timer HUD readout
var _was_reloading: bool = false   # iter413: edge-detect reload start for the click SFX
var _last_lap: float = 0.0   # iter414: puddle-cross splash detector
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
# SP2: data-driven level (LevelDef timeline played by LevelPlayer).
var _level_def: LevelDef = null
var _level_num: int = 1   # winflow R3: current level (1-based); drives bull grace
var _first_bull_logged: bool = false   # winflow R3: one-shot debug of first bull timing
var _level_player: LevelPlayer = null
var _level_distance: float = 0.0      # world distance scrolled (drives the timeline)
var _bounty_at_start: int = 0   # GameState.bounty when this level began (for run-bounty)
var _boss_from_data: bool = false     # true when the LevelDef has a BOSS event (legacy timer yields)
var _director: LevelDirector = null   # SP2 slice2: pacing (variable scroll speed + approach-zone halts)
# iter417: per-level weather, driven by LevelDef.weather_type. The visual layer is
# the 2D weather scene (rain/snow/dust/wind) drawn on a CanvasLayer over the 3D
# viewport; the gameplay modifiers below re-map the iter-22d 2D knobs to 3D.
const WeatherData = preload("res://scripts/weather.gd")
# Drift params in weather.gd are px/sec on a 1080-wide screen; the visible road is
# COWBOY_X_BOUND*2 world units across, so this converts px/sec → world-units/sec.
const WEATHER_PX_TO_WORLD: float = (COWBOY_X_BOUND * 2.0) / 1080.0
var _weather_range_mult: float = 1.0        # scales bullet range (despawn z)
var _weather_bullet_speed_mult: float = 1.0 # scales bullet forward speed
var _weather_bullet_drift: float = 0.0      # world-units/sec lateral bullet push
var _weather_cowboy_drift: float = 0.0      # world-units/sec lateral cowboy push
var _weather_steering_mult: float = 1.0     # scales the cowboy follow-lerp
var _weather_layer: CanvasLayer = null
const COUNTDOWN_TOTAL: float = 3.5  # 3, 2, 1, GO! across this window
var _countdown_remaining: float = COUNTDOWN_TOTAL
var _hits: int = 0
var _rng := RandomNumberGenerator.new()

# Iter 75: gate spawn parameters. Gates are 2 colored door quads
# straddling the lane center, math values painted on as Label3D.
# Posse count starts at STARTING_POSSE (5) and modifies as cowboy
# walks through gates.
const GATE_SPAWN_INTERVAL: float = 3.0  # iter 145: 4.5 → 3.0 (more gates per second with slower terrain)
const GATE_WIDTH: float = 13.0      # iter402: ~4× bigger gates (was 4.0) — much more prominent
const GATE_HEIGHT: float = 5.4      # iter402: 1.35 → 5.4 (×4)
const GATE_TRIGGER_Z: float = 0.5   # gates fire when their z passes this
var _gate_spawn_timer: float = 0.0
var _posse_count_3d: int = 5
const STARTING_POSSE_3D: int = 1  # iter 118: 5 → 1 (gates grow it from there)

# Iter 76: outlaw enemies. Spawn red boxes periodically at far z that
# scroll toward camera + fire red bullets at the cowboy.
const OUTLAW_SPAWN_INTERVAL: float = 0.5  # iter 118: 3.0 → 0.5 (~14 alive at once)
const OUTLAW_SPEED: float = 1.5  # iter402: 2.5 → 1.5 — outlaws were rushing the posse before the first gate
const OUTLAW_GRACE: float = 9.0  # iter402: no outlaws for the first 9s so the player reaches a gate or two first
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

# ── Farm outlaw cast (Level 3) ───────────────────────────────────────────
# 4 video-billboard enemy kinds, each with its own movement/offense/defense.
# Streams loaded lazily in _spawn_outlaw; per-kind stats live in OUTLAW_KINDS.
# "vagrant" keeps the original behavior for all other levels.
const FARM_OUTLAW_VIDEOS: Dictionary = {
	"candy_corn":  "res://assets/videos/farm/candy_corn.ogv",
	"gummi_bear":  "res://assets/videos/farm/gummi_bear.ogv",
	"fried_dough": "res://assets/videos/farm/fried_dough.ogv",
	"triffid":     "res://assets/videos/farm/triffid.ogv",
}
# kind -> {hp, height}. Roster weights are in FARM_OUTLAW_WEIGHTS below.
const OUTLAW_KINDS: Dictionary = {
	"candy_corn":    {"hp": 10, "height": 2.5},
	"gummi_bear":    {"hp": 8,  "height": 2.3},
	"fried_dough":   {"hp": 16, "height": 2.8},
	"triffid":       {"hp": 14, "height": 3.0},
	"fireball_monk": {"hp": 18, "height": 2.7},
	"star_monk":     {"hp": 9,  "height": 2.5},
	"flit_finch":    {"hp": 8,  "height": 2.2},
	"peck_jay":      {"hp": 11, "height": 2.4},
}
# candy_corn + gummi common; fried_dough + triffid rarer.
const FARM_OUTLAW_WEIGHTS: Array = [
	["candy_corn", 35], ["gummi_bear", 35], ["fried_dough", 18], ["triffid", 12],
]
# Level-5 Shaolin candy-monks (no guns). Same video-billboard path as the
# farm kinds. fireball_monk = orange, slow/heavy telegraphed lob; star_monk =
# blue, fast/light multi-shot harasser. Tuned on device (Task 10).
const MONK_OUTLAW_VIDEOS: Dictionary = {
	"fireball_monk": "res://assets/videos/candy_monk/hadouken.ogv",
	"star_monk":     "res://assets/videos/candy_monk/candy_star_blue.ogv",
}
const BADLANDS_OUTLAW_WEIGHTS: Array = [
	["fireball_monk", 45], ["star_monk", 55],
]
# Level-6 candy songbirds (no guns). flit_finch = warm, erratic light harasser;
# peck_jay = cool, swoops to peck on a cooldown. Tuned on device (Task 10).
const BIRD_OUTLAW_VIDEOS: Dictionary = {
	"flit_finch": "res://assets/videos/canyon_birds/flit_finch.ogv",
	"peck_jay":   "res://assets/videos/canyon_birds/peck_jay.ogv",
}
const CANYON_OUTLAW_WEIGHTS: Array = [
	["flit_finch", 55], ["peck_jay", 45],
]
const PECK_JAY_SWOOP_COOLDOWN: float = 2.2   # reserved for later AI tuning (do not remove)
const FIREBALL_MONK_HOLD_Z: float = 7.0     # heavy lobber holds at range
const STAR_MONK_HOLD_Z: float = 5.0         # harasser closes a bit more
# candy_corn KITER: holds this many units in front of the cowboy (stops closing).
const CANDY_CORN_HOLD_Z: float = 6.0
const CANDY_CORN_BURST: int = 3        # bullets per fire interval
const CANDY_CORN_BURST_GAP: float = 0.12
# gummi BOUNCY: hop arc + apex-only hittable window.
const GUMMI_SPEED_MUL: float = 1.3
const GUMMI_HOP_HEIGHT: float = 1.6
const GUMMI_HOP_PERIOD: float = 0.85   # seconds per hop
const GUMMI_APEX_WINDOW: float = 0.45  # fraction-of-arc (centered on apex) that is hittable
# fried_dough RUSHER: closes fast to melee.
const FRIED_DOUGH_SPEED_MUL: float = 1.6
# triffid ROOTED: lashes the posse on a cooldown within this z-range.
const TRIFFID_LASH_RANGE_Z: float = 3.5
const TRIFFID_LASH_COOLDOWN: float = 1.8
const TRIFFID_LASH_X: float = 2.0      # lane reach for the whip
# shared melee contact range (gummi/fried_dough)
const OUTLAW_MELEE_Z: float = 1.6
var _outlaws_remaining: int = 0   # ticks down as outlaws leave the field; 0 -> boss
var _outlaws_spawned: int = 0     # stop spawning once this reaches the quota

# Iter 77: Slippery Pete boss. Appears at PETE_SPAWN_DELAY into the
# level. Slow approach, much higher HP, drops the WIN modal on defeat.
const PETE_SPAWN_DELAY: float = 30.0  # iter 153: 18 → 30. At OBSTACLE_SPEED 2.5 a gate takes ~11s to reach the player; 30s lets the player clear ~6 gates + a sustained outlaw firefight BEFORE the boss (user: "Pete appearing before reaching any gates or outlaws")
const PETE_HP: int = 500  # iter 119: 40 → 1000 → iter 147: 1000 → 500 (user: "Pete's HP is too high. cut it in half")
const PETE_SPEED: float = 10.0  # iter 124: 1.6 → 4.0 → iter 143: 4.0 → 10.0 (user reported "doesn't advance fast enough")
const PETE_FIRE_INTERVAL: float = 0.5  # iter 119: 1.0 → 0.5 (alternates L/R guns)
const PETE_HIT_RADIUS_SQ: float = 5.5 * 5.5  # iter402b: 3.6 → 5.5 — the posse crowd now sprays bullets across its full width; a point-radius let most of a huge posse's fire pass beside the boss
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

# Iter (level5): Raisin Kidd — the "Untouchable" deflect/counter boss. Combat
# timing lives in RaisinKiddState (unit-tested); this scene drives rendering,
# contact, FX, audio, and the WIN/lose flow from its events.
const _RAISIN_KIDD_STATE := preload("res://scripts/raisin_kidd_state.gd")
const RAISIN_GUARD_STREAM := "res://assets/videos/raisin_kidd/guard_idle.ogv"
const RAISIN_STAY_Z: float = -7.0       # arena center, like the Rustler
const RAISIN_HEIGHT: float = 5.0
const RAISIN_WARP_X_MAX: float = 4.0    # lateral range he can reappear at
const RAISIN_FLURRY_DPS: float = 4.0    # posse drained/sec during a Grapes of Wrath flurry
var _raisin: RaisinKiddState = null
var _raisin_flurry_accum: float = 0.0
var _raisin_hit_voice_cd: float = 0.0

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
enum FireMode { CANDY, RIFLE, FROSTBITE, FRENZY, RAINBOW }
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
var _followers: Array[Sprite3D] = []   # iter401: now always empty — posse renders via _posse_crowd

# iter401: posse crowd port. The video-clip follower pool capped the visible posse
# (MAX_VISIBLE_FOLLOWERS) because Android can't run many video decoders. The posse
# now renders as a FlipbookCrowd MultiMesh mob (the SP1 system) behind the leader,
# scaling to the full _posse_count_3d. The formation is frame-fitted to the LIVE
# camera pitch (which eases CALM↔busy), so the mob rearranges to stay on-screen.
const FlipbookCrowdScript = preload("res://scripts/flipbook_crowd.gd")
const POSSE_CROWD_CLIPS: Array = [
	# iter402: BACK-VIEW clips only — the posse faces INTO the screen (toward the
	# outlaws) like the leader. The idle clips are front-view (faced the camera =
	# "running backwards"); stand_shoot/run_shoot_fwd are back-view.
	"cowboy_stand_shoot", "cowboy_run_shoot_fwd",
]
const POSSE_CROWD_DEPTH: float = 1.0   # how far back the mob extends behind the leader
const CROWD_RENDER_CAP: int = 1500     # iter408: max MultiMesh members drawn (logical posse can exceed this)
var _posse_crowd: Node3D = null
var _crowd_built_count: int = -1
var _crowd_built_pitch: float = 999.0
var _hole_lose_accum: float = 0.0
var _over_hole: bool = false   # iter414b: pit-entry edge for the fall whistle
# winflow: cumulative members already dropped during the CURRENT pit visit, so
# the immediate-fall logic only drops the *newly* overlapping increment each
# frame (reset to 0 the moment the crowd leaves the pit).
var _hole_dropped_this_visit: int = 0
var _dyn_hole_count: int = 0   # winflow: cycles candy fills across runtime-spawned holes

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
	# iter359: the SP2 director owns world scroll speed now. Neutralise the legacy
	# finger-position WorldSpeed multiplier (terrain_3d still reads it) so a stale
	# value carried over from the dead 2D prototype (level.gd sets it to 0.0 on its
	# freeze) can't desync — or freeze — the terrain scroll vs the director props.
	if get_node_or_null("/root/WorldSpeed") != null:
		WorldSpeed.set_mult(1.0)
	# iter361: per-level music — L1 "Running From The Clock", L2 "High Noon at the
	# Glass Saloon" (splash track as fallback). MusicPlayer is an autoload, so a
	# retry of the same level keeps the track playing (same stream = no restart).
	if get_node_or_null("/root/MusicPlayer") != null:
		MusicPlayer.play_level(GameState.current_level if get_node_or_null("/root/GameState") != null else 1)
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
		# iter 335/337: start at the CALM pitch + position (scenic, sky visible,
		# posse framed); _process eases toward BUSY (-55°, pulled in) as threats
		# appear.
		camera.position = CAM_POS_CALM
		camera.rotation_degrees = Vector3(CAM_PITCH_CALM, 0, 0)
		camera.fov = 62.0   # iter418: 50 → 62 — the new hilly landscape felt cramped;
		# wider horizontal FOV (half ≈ 31° → visible road x≈±5.1 at the cowboy) shows
		# both shoulders + dodge lanes around pits. Input still maps to ±COWBOY_X_BOUND.
		camera.keep_aspect = 0  # Camera3D.KEEP_WIDTH (portrait viewport)
		DebugLog.add("level_3d: camera overridden (y=7 z=3 dynamic pitch fov=62 KEEP_WIDTH)")
	# Iter 95: build 3D content (cowboy + mountains + 8 container Node3Ds)
	# AFTER initial setup. Hypothesis: bundling everything into .tscn was
	# overloading mobile scene-load — script-side spawn defers texture
	# upload / shader compile / node tree allocation to post-_ready frames.
	_build_3d_content()
	# Load the level def BEFORE the terrain build so PER-TERRAIN theming actually
	# applies. (It used to load further down, so every level built with _level_def
	# null → the default "frontier" terrain — all 4 levels looked identical.)
	var _lvl: int = GameState.current_level if get_node_or_null("/root/GameState") else 1
	_level_num = _lvl   # winflow R3: remember the level for bull-grace timing
	var _def_path := "res://resources/levels/level_%d.tres" % _lvl
	if ResourceLoader.exists(_def_path):
		_level_def = load(_def_path)
	_build_world_terrain()   # iter400: static curved+hilly terrain the posse advances through
	_apply_terrain_theme()   # iter415: per-terrain fog
	_build_frost_bolts()     # iter404: FROSTBITE chain-lightning overlay
	_build_rainbow_bolts()   # kimmy: RAINBOW prism-chain overlay
	_build_manga_fx()        # level5: Raisin Kidd manga FX overlay
	_build_comet_streak()    # weapon fx: RIFLE rainbow-comet trail overlay
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
	# iter357: top build-id removed (it's in the debug log). info_label is kept
	# only for transient gate/boss messages. Add the debug speed + pause controls.
	if info_label != null:
		info_label.text = ""
	_build_top_debug()
	_build_weapon_indicator()
	_build_quake_bar()
	# SP2: the level def + its event timeline. (_level_def is now loaded earlier,
	# above the terrain build, so per-terrain theming applies — see that block.)
	if get_node_or_null("/root/GameState"):
		_bounty_at_start = GameState.bounty
	if _level_def != null and _level_def.outlaw_quota > 0:
		_outlaws_remaining = _level_def.outlaw_quota
	if _hud_outlaws != null:
		_hud_outlaws.text = str(_outlaws_remaining)
	# SP2: starting posse size from the level definition (default 5).
	if _level_def != null and _level_def.start_posse > 0 and _level_def.start_posse != _posse_count_3d:
		_posse_count_3d = _level_def.start_posse
		_sync_followers_to_count(_posse_count_3d)
		_refresh_hud()
	# Chicken-chase Posse Brew: one-shot starting-posse bonus, consumed
	# unconditionally at level start (self-clears, so it applies to exactly
	# one level regardless of the start_posse guard above).
	if get_node_or_null("/root/GameState") != null:
		var _brew: int = GameState.claim_posse_bonus()
		if _brew > 0:
			_posse_count_3d += _brew
			_sync_followers_to_count(_posse_count_3d)
			_refresh_hud()
			DebugLog.add("posse brew applied: +%d (start now %d)" % [_brew, _posse_count_3d])
	if _level_def != null and not _level_def.events.is_empty():
		_level_player = LevelPlayer.new(_level_def.events)
		_director = LevelDirector.new()  # SP2 slice2: drives variable scroll + approach zones
		for _ev in _level_def.events:
			if _ev.kind == LevelEvent.EventKind.BOSS:
				_boss_from_data = true
	DebugLog.add("level_3d _ready (build=%s, leveldef=%s, boss_from_data=%s)" % [BuildInfo.SHA, str(_level_def != null), str(_boss_from_data)])
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
		elif DebugPreview.pending_kimmy:
			# kimmy: interactive preview — equip the RAINBOW weapon and drop her cage
			# right away so the rescue + sugar rush can be played without reaching L3.
			DebugPreview.pending_kimmy = false
			_fire_mode = FireMode.RAINBOW
			_update_weapon_label()
			call_deferred("_spawn_kimmy_cage")
			DebugLog.add("level_3d: kimmy preview")
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
	holes_root = _make_lvl3d_container("Holes")
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
	# 3) Sky — sun/moon + clouds + candy mountains (iter 335). The mountains are
	# baked into the cloud sky shader's horizon (not separate meshes/sprites — a
	# transparent sprite over the sky erases it; see memory). Replaces the old
	# purple CSG box mountains. The dynamic camera (calm → -25°) reveals it.
	_build_sky_3d()
	_apply_weather_3d()   # iter417: per-level weather visuals + gameplay modifiers
	DebugLog.add("level_3d: sky + candy mountains added")

func _make_lvl3d_container(node_name: String) -> Node3D:
	var n := Node3D.new()
	n.name = node_name
	subviewport.add_child(n)
	return n


# Iter 335: dynamic action camera. Pitch eases between CALM (more sky / the
# sun-moon visible, when little is happening — e.g. level start) and BUSY
# (steeper, tactical) based on how many threats are active.
const CAM_PITCH_CALM := -25.0
const CAM_PITCH_BUSY := -55.0
const CAM_PITCH_LERP := 1.3
# iter337: the camera also pulls UP + BACK as it tilts shallow (calm), so it
# orbits the posse instead of pivoting in place — otherwise the shallow calm
# angle drops the foreground posse off the bottom of the frame. BUSY position
# is the original (0,7,3) that framed the posse at -55°.
const CAM_POS_BUSY := Vector3(0.0, 7.0, 3.0)
const CAM_POS_CALM := Vector3(0.0, 11.5, 7.5)
var _sky: SkyBodies = null
var _cam_pitch: float = CAM_PITCH_CALM

# Ease the camera pitch by action intensity: more active threats → steeper
# (BUSY/tactical), few/none → shallower (CALM, sky + sun/moon visible). Boss
# fights pin it to BUSY. (iter 335)
func _update_dynamic_camera(delta: float) -> void:
	if camera == null:
		return
	var threats: int = 0
	for c in outlaws_root.get_children():
		if is_instance_valid(c) and not c.get_meta("is_captive", false):
			threats += 1
	var intensity: float = clampf(float(threats) / 8.0, 0.0, 1.0)
	if _level_state == LevelState.BOSS:
		intensity = 1.0
	var target: float = lerpf(CAM_PITCH_CALM, CAM_PITCH_BUSY, intensity)
	var ease: float = clampf(delta * CAM_PITCH_LERP, 0.0, 1.0)
	_cam_pitch = lerpf(_cam_pitch, target, ease)
	camera.rotation_degrees.x = _cam_pitch
	var target_pos: Vector3 = CAM_POS_BUSY.lerp(CAM_POS_CALM, 1.0 - intensity)
	camera.position = camera.position.lerp(target_pos, ease)

# Build the sun/moon + cloud sky in the gameplay subviewport (self-building
# SkyBodies) and apply this level's sky look.
func _build_sky_3d() -> void:
	_sky = SkyBodies.new()
	_sky.name = "SkyBodies"
	subviewport.add_child(_sky)
	if camera != null:
		_sky.bind_camera(camera)
	_apply_level_sky()

# Gameplay sky: time-of-day from the system clock × this level's signature
# weather (iter 336). The SKY_TOD presets keep the sun/moon LOW so they read at
# the down-tilted gameplay camera.
func _apply_level_sky() -> void:
	if _sky == null:
		return
	var preset: Dictionary = SkyBodies.make_sky_preset(
		SkyBodies.tod_from_clock(), _level_weather())
	# Per-terrain distant-mountain backdrop (frontier/mine/farm/mountain).
	var _terrain: String = _level_def.terrain if _level_def != null else "frontier"
	var _backdrop_path: String = TerrainThemes.get_theme(_terrain).get("backdrop", "")
	if _backdrop_path != "":
		_sky.set_backdrop_texture(load(_backdrop_path) as Texture2D)
	_sky.apply_preset(preset, Vector3(-0.5, 0.0, 1.0))

# Per-level signature weather → sky slug, derived from LevelDef.weather_type
# (iter417). "" / clear → "fair". The cloud tint/cover/SPEED for each slug live
# in SkyBodies.SKY_WEATHER.
func _level_weather() -> String:
	var wt: String = _level_def.weather_type if _level_def != null else ""
	return WeatherData.sky_for(wt)

# iter417: apply this level's weather to the 3D game. Reads the iter-22d weather
# param table and (a) caches the gameplay-modifier multipliers used in _process
# and at bullet spawn, and (b) instances the weather's 2D visual scene onto a
# CanvasLayer that draws over the 3D viewport but under the HUD. Clear/unknown
# weather leaves every modifier at its identity value and spawns no visual.
func _apply_weather_3d() -> void:
	var wt: String = _level_def.weather_type if _level_def != null else ""
	if not WeatherData.is_valid(wt):
		return
	var p: Dictionary = WeatherData.params_for(wt)
	_weather_range_mult = float(p.get("range_mult", 1.0))
	_weather_bullet_speed_mult = float(p.get("bullet_velocity_mult", 1.0))
	_weather_bullet_drift = float(p.get("bullet_drift", 0.0)) * WEATHER_PX_TO_WORLD
	_weather_cowboy_drift = float(p.get("cowboy_drift_x", 0.0)) * WEATHER_PX_TO_WORLD
	_weather_steering_mult = float(p.get("steering_mult", 1.0))
	var scene_path: String = String(p.get("scene_path", ""))
	var packed: PackedScene = load(scene_path) as PackedScene
	if packed != null:
		_weather_layer = CanvasLayer.new()
		_weather_layer.name = "WeatherOverlay"
		_weather_layer.layer = 0   # over the 3D viewport (base canvas), under UI (layer 1)
		add_child(_weather_layer)
		_weather_layer.add_child(packed.instantiate())
	else:
		DebugLog.add("level_3d: weather %s failed to load %s" % [wt, scene_path])
	DebugLog.add("level_3d weather=%s (range×%.2f speed×%.2f drift=%.3f)" %
		[wt, _weather_range_mult, _weather_bullet_speed_mult, _weather_bullet_drift])

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

# Iter 335: candy-Western "deputized" flourish when a posse member joins from a
# gate (was a flat pop-into-existence). They bounce in inside a powdered-sugar
# poof, and a glossy candy sheriff-star pops over their head and lingers —
# "you're deputized into the posse". Western entrance (dust) × candy badge.
const POWERUP_PUFF_TEX := preload("res://assets/sprites/fx/sugar_puff.png")
const POWERUP_STAR_TEX := preload("res://assets/sprites/fx/candy_sheriff_star.png")

func _spawn_powerup_flourish(member: Sprite3D) -> void:
	if get_node_or_null("/root/AudioBus") and AudioBus.has_method("play_sfx"): AudioBus.play_sfx("deputize_join")
	if not is_instance_valid(member):
		return
	# Bounce in instead of blinking in, with a brief warm flash.
	member.scale = Vector3(0.25, 0.25, 0.25)
	var pop := member.create_tween()
	pop.tween_property(member, "scale", Vector3.ONE * 1.15, 0.18) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	pop.tween_property(member, "scale", Vector3.ONE, 0.12)
	member.modulate = Color(1.5, 1.35, 0.95, 1.0)
	member.create_tween().tween_property(member, "modulate", Color.WHITE, 0.5)
	# Powdered-sugar poof at the member's feet (Western dust, candy-fied).
	var puff := Sprite3D.new()
	puff.texture = POWERUP_PUFF_TEX
	puff.billboard = 1
	puff.shaded = false
	puff.pixel_size = 2.2 / float(maxi(POWERUP_PUFF_TEX.get_height(), 1))
	puff.position = member.position + Vector3(0.0, 0.25, 0.0)
	puff.scale = Vector3(0.4, 0.4, 0.4)
	popups_root.add_child(puff)
	var pt := puff.create_tween().set_parallel(true)
	pt.tween_property(puff, "scale", Vector3.ONE * 1.5, 0.5) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	pt.tween_property(puff, "modulate:a", 0.0, 0.55)
	pt.chain().tween_callback(puff.queue_free)
	# Candy sheriff-star pops in overhead, lingers, then rises + fades.
	var star := Sprite3D.new()
	star.texture = POWERUP_STAR_TEX
	star.billboard = 1
	star.shaded = false
	star.pixel_size = 1.1 / float(maxi(POWERUP_STAR_TEX.get_height(), 1))
	star.position = member.position + Vector3(0.0, 1.5, -0.02)
	star.scale = Vector3.ZERO
	popups_root.add_child(star)
	var base_y: float = star.position.y
	var st := star.create_tween()
	st.tween_property(star, "scale", Vector3.ONE * 1.3, 0.20) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	st.tween_property(star, "scale", Vector3.ONE, 0.12)
	st.tween_interval(0.45)
	st.set_parallel(true)
	st.tween_property(star, "position:y", base_y + 0.8, 0.5) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	st.tween_property(star, "modulate:a", 0.0, 0.5)
	st.chain().tween_callback(star.queue_free)

# Iter 72: posse followers behind the leader in a trapezoid formation.
func _spawn_posse_followers() -> void:
	# iter401: instead of video-billboard followers, build the FlipbookCrowd mob.
	# The leader stays the video cowboy_3d; the crowd is everyone behind him.
	if cowboy_3d == null:
		return
	_posse_crowd = FlipbookCrowdScript.new()
	_posse_crowd.name = "PosseCrowd"
	subviewport.add_child(_posse_crowd)
	_posse_crowd.position = Vector3(0.0, POSSE_BASE_Y, COWBOY_Z)
	_posse_crowd.call("configure", "cowboy", POSSE_CROWD_CLIPS)
	_build_posse_formation(maxi(0, _posse_count_3d - 1))

# iter401: count is the single source of truth; the crowd re-syncs from it each
# frame in _update_posse_crowd, so this is now a no-op kept for its many callers.
func _sync_followers_to_count(_target: int) -> void:
	pass

# Horizontal half-width on screen at the mob's depth, from the LIVE camera (pos +
# eased pitch). fov=50 KEEP_WIDTH → horizontal half-FOV = fov/2, no aspect factor.
func _crowd_frame_halfwidth() -> float:
	if camera == null or _posse_crowd == null:
		return 4.0
	var pitch: float = camera.rotation.x
	var fwd_y: float = sin(pitch)
	var fwd_z: float = -cos(pitch)
	var mz: float = _posse_crowd.position.z + POSSE_CROWD_DEPTH * 0.5
	var d: float = (0.6 - camera.position.y) * fwd_y + (mz - camera.position.z) * fwd_z
	return maxf(0.8, d * tan(deg_to_rad(camera.fov * 0.5)) - 0.7)

# Build the mob formation behind the leader, frame-fitted to the current pitch.
func _build_posse_formation(want: int) -> void:
	if _posse_crowd == null:
		return
	# iter408: cap the RENDERED crowd. The logical posse (_posse_count_3d) can reach
	# thousands via ×gates and still drives damage, but drawing/​rebuilding 4000+
	# MultiMesh members every frame tanked FPS — which ballooned delta, which made
	# bullets tunnel + despawn in a single frame (the real "can't hit Pete" cause).
	# A dense ~1500 reads as a huge mob; the rest are "off-screen" reinforcements.
	want = mini(want, CROWD_RENDER_CAP)
	var halfw: float = _crowd_frame_halfwidth()
	var rng := RandomNumberGenerator.new()
	var specs: Array = []
	for i in range(want):
		rng.seed = i * 2654435761 + 777   # stable per index → no reshuffle on rebuild
		var depth: float = 0.5 + rng.randf() * POSSE_CROWD_DEPTH   # behind leader (toward camera)
		var x: float = halfw * tanh(rng.randfn(0.0, 0.72))         # frame-fitted, centre-dense
		specs.append({
			"clip": POSSE_CROWD_CLIPS[i % POSSE_CROWD_CLIPS.size()],
			"xform": Transform3D(Basis(), Vector3(x, 0.0, depth)),
		})
	_posse_crowd.call("set_population", specs)
	_crowd_built_count = want
	_crowd_built_pitch = _cam_pitch

# Each frame: follow the leader (x lag), ride the hills (y), and rebuild the
# formation when the count changes or the camera pitch eases enough to need
# reframing (the dynamic in-frame fit).
func _update_posse_crowd(delta: float) -> void:
	if _posse_crowd == null or cowboy_3d == null:
		return
	_posse_crowd.position.x = lerpf(_posse_crowd.position.x, cowboy_3d.position.x,
		clampf(FOLLOWER_LERP_SPEED * delta, 0.0, 1.0))
	# iter402: sit ON the terrain at the mob's own world-z (the terrain scrolls in
	# WorldRoot, so the surface under world-z Z is at distance _level_distance − Z).
	# Using _level_distance alone sank the mob into the hill, so it was occluded.
	_posse_crowd.position.y = 0.55 + _hill_y(_level_distance - COWBOY_Z)
	# Cap BEFORE the change-test so a 4000-posse doesn't rebuild every frame.
	var want: int = mini(maxi(0, _posse_count_3d - 1), CROWD_RENDER_CAP)
	if want != _crowd_built_count or absf(_cam_pitch - _crowd_built_pitch) > 2.0:
		_build_posse_formation(want)

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
		if side > 0:
			_spawn_boardwalk_segment(z)
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
	if side > 0:
		_spawn_boardwalk_segment(z)

# Iter 110: bullet-vs-gate collision. Returns true if the bullet hit
# a not-yet-triggered gate door, in which case the caller queue_frees
# the bullet. Decrements the hit door's value toward zero (or degrades
# a multiplier toward additive zero), updates the Label3D + door tint.
const GATE_BULLET_Z_RANGE: float = 0.5
const GATE_BULLET_X_HALF: float = 3.25  # half door width (= GATE_WIDTH * 0.25) — iter402 bigger gates
const GATE_HITS_PER_STEP: int = 3  # iter 113: armor — 3 bullets per value decrement

func _check_bullet_gate_collision(bullet: Node3D, prev_z: float = INF) -> bool:
	for gate_node in gates_root.get_children():
		if not (gate_node is Node3D):
			continue
		var gate: Node3D = gate_node
		if gate.get_meta("triggered", false):
			continue
		# iter364: swept z-crossing so fast bullets can't TUNNEL through the gate
		# between frames (BULLET_SPEED 28/s ≈ 0.5-0.9 units/frame can exceed the
		# proximity band, letting shots pass through and hit outlaws beyond). Hit
		# if the bullet's path this frame (prev_z -> z, moving -z) spanned the gate
		# plane; otherwise fall back to the in-band test for slow/stationary cases.
		var gz: float = gate.position.z
		var crossed: bool = prev_z != INF and prev_z >= gz and bullet.position.z <= gz
		if not crossed and absf(bullet.position.z - gz) > GATE_BULLET_Z_RANGE:
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
		_spawn_impact_blast(bullet.position)   # iter409: 💥 on gate hit
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
		var _was_red: bool = (value < 0)   # iter410: for the red→blue bull-confuse beat
		if op == "×":
			pass  # iter 119: × gates absorb the bullet but DON'T increment. Multipliers stay at ×2 max so posse doesn't explode.
		elif value >= 0:
			value += 1
		else:  # value < 0 — climb toward 0, but iter337: skip the dead "0 red"
			# dwell and flip straight to +1 so a shot -N gate visibly turns
			# positive (was getting stuck at 0 / staying red).
			value += 1
			if value == 0:
				value = 1
		# iter337: once positive, carry the "+" op so the label reads "+N" and
		# _gate_color_for paints it blue (it keys on value sign, not op).
		# iter432: but NEVER rewrite a ×/÷ multiplier gate to "+" — that was turning
		# multiply gates into addition gates on the first hit.
		if value > 0 and op != "×" and op != "÷":
			op = "+"
		# iter410: a red (shrinking) gate just flipped to blue (growing) — confuse
		# every bull on screen so they veer off and flee. The gate-flip reward beat.
		if _was_red and value > 0:
			_confuse_all_bulls()
		# Persist + update visuals.
		gate.set_meta(side + "_value", value)
		gate.set_meta(side + "_op", op)
		var lbl: Label3D = gate.get_meta(side + "_label")
		if lbl != null and is_instance_valid(lbl):
			lbl.text = "%s%d" % [op, value]
		if door is MeshInstance3D and (door as MeshInstance3D).material_override is StandardMaterial3D:
			(((door as MeshInstance3D).material_override) as StandardMaterial3D).albedo_texture = _gate_texture_for(value, op)
		# Step-popup at impact: shows the new value so player sees the change.
		_spawn_popup_3d(bullet.position + Vector3(0, 0.5, 0),
			"%s%d" % [op, value], Color(1.0, 0.92, 0.3, 1), 40)
		if get_node_or_null("/root/AudioBus") and AudioBus.has_method("play_sfx"): AudioBus.play_sfx("gate_step")
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
func _burst_at(pos: Vector3, count: int, _color: Color, scale: float = 1.0, duration: float = 0.7) -> void:
	for i in range(count):
		# iter 331/333: candy billboard instead of a faceted CSGSphere. The old
		# spheres flew up+out and read as "polygons raining from the sky"
		# during the JELLY_FRENZY sugar rush (and every other burst). Uses the
		# full FRENZY candy set (gummies + cotton/bomb/fireball/jawbreaker) so
		# bursts aren't all gummies. Candy art is pre-colored → `color` ignored.
		var c: Sprite3D = _make_candy_billboard(CANDY_BULLET_TEX[FireMode.FRENZY], 0.3)
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
	# iter 333: a big candy "prize" billboard instead of a faceted CSGBox —
	# the box was the last polygon raining during the sugar rush. `color` is
	# still used for the bounty popup below.
	var c: Sprite3D = _make_candy_billboard(CANDY_BULLET_TEX[FireMode.FRENZY], 0.8)
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

func _run_bounty() -> int:
	if get_node_or_null("/root/GameState") == null:
		return 0
	return maxi(0, GameState.bounty - _bounty_at_start)

func _add_bounty(amount: int) -> void:
	if get_node_or_null("/root/GameState") != null:
		GameState.bounty = GameState.bounty + amount
	# iter414: big cascade payouts (the gold-rush finales) get the chain-reaction sting.
	if amount >= 500 and get_node_or_null("/root/AudioBus") and AudioBus.has_method("play_sfx"):
		AudioBus.play_sfx("rush_cascade")

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
		# iter 330: candy billboard (was a CSGSphere "polygon"). Uses the same
		# FRENZY candy art set as the fire-mode bullets so the cascade matches.
		var bean: Sprite3D = _make_candy_billboard(
			CANDY_BULLET_TEX[FireMode.FRENZY], 0.55)
		bean.position = Vector3(x, 9.0 + _rng.randf_range(0, 3.0), z)
		popups_root.add_child(bean)
		var bean_tw := create_tween()
		bean_tw.tween_property(bean, "position:y", 0.2, 0.45) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
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
	# Left door — authored gate PNG (blue grow / red shrink).
	var left_door := _make_gate_door(values[0], operators[0])
	left_door.position = Vector3(-GATE_WIDTH * 0.25, 0, 0)
	gate.add_child(left_door)
	gate.set_meta("left_door", left_door)  # iter 110: bullets find door via meta
	# Right door
	var right_door := _make_gate_door(values[1], operators[1])
	right_door.position = Vector3(GATE_WIDTH * 0.25, 0, 0)
	gate.add_child(right_door)
	gate.set_meta("right_door", right_door)
	# Math value labels (Label3D billboards centered across each door face — iter424:
	# was at GATE_HEIGHT*0.55 (above the gate); the gates are tall now, so center them)
	var llabel := Label3D.new()
	llabel.text = "%s%d" % [operators[0], values[0]]
	llabel.position = Vector3(-GATE_WIDTH * 0.25, 0.0, 0.35)
	llabel.no_depth_test = true
	llabel.font_size = 180
	llabel.outline_size = 24
	llabel.modulate = Color.WHITE
	gate.add_child(llabel)
	gate.set_meta("left_label", llabel)  # iter 110: bullets update label text via meta
	var rlabel := Label3D.new()
	rlabel.text = "%s%d" % [operators[1], values[1]]
	rlabel.position = Vector3(GATE_WIDTH * 0.25, 0.0, 0.35)
	rlabel.no_depth_test = true
	rlabel.font_size = 180
	rlabel.outline_size = 24
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

# iter365: gate doors now render as the authored blue/red gate PNGs (they were
# CSGBox3D colour panes — the PNGs existed in assets but were never wired in).
# Blue = growing (good), red = shrinking (bad), matching _gate_color_for.
const GATE_TEX_GROW: Texture2D = preload("res://assets/sprites/props/gate_fence_blue.png")
const GATE_TEX_SHRINK: Texture2D = preload("res://assets/sprites/props/gate_fence_red.png")

func _gate_texture_for(value: int, op: String) -> Texture2D:
	var growing: bool = (value >= 2) if op == "×" else (value > 0)
	return GATE_TEX_GROW if growing else GATE_TEX_SHRINK

func _make_gate_door(value: int, op: String) -> MeshInstance3D:
	var door := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(GATE_WIDTH * 0.5, GATE_HEIGHT)
	door.mesh = qm
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _gate_texture_for(value, op)
	# iter416: ALPHA_SCISSOR (not blend) — the transparent pixels still carry gray
	# checkerboard RGB; alpha-blend + mipmaps bled that gray into the edges. Scissor
	# discards the transparent pixels outright (matches the clean SP1 gate).
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mat.alpha_scissor_threshold = 0.5
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	door.material_override = mat
	return door

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
		_spawn_frenzy_candy_rain()
	# Iter 110: disintegrate the gate instead of letting it slide past.
	# Scale-collapse + queue_free so the player feels the contact.
	var tween := create_tween()
	tween.tween_property(gate, "scale", Vector3(0.01, 0.01, 0.01), 0.25) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_callback(gate.queue_free)

# Iter 333: in-game JELLY_FRENZY augments gunfire with a NON-BLOCKING candy
# sky-rain. (The debug sugar-rush ceremony pauses the world; this runs while
# the player keeps shooting — the original "augment gunfire" design.) ~30
# candy billboards fall over 3s, each popping into a small candy burst. Added
# to popups_root so they're purely visual (no bullet collision/despawn).
func _spawn_frenzy_candy_rain() -> void:
	const RAIN_COUNT: int = 30
	const RAIN_DURATION: float = 3.0
	var interval: float = RAIN_DURATION / float(RAIN_COUNT)
	for i in range(RAIN_COUNT):
		var x: float = _rng.randf_range(-3.5, 3.5)
		var z: float = _rng.randf_range(-12.0, 0.0)
		var candy: Sprite3D = _make_candy_billboard(CANDY_BULLET_TEX[FireMode.FRENZY], 0.4)
		candy.position = Vector3(x, 12.0 + _rng.randf_range(0.0, 3.0), z)
		popups_root.add_child(candy)
		var fall := create_tween()
		fall.tween_property(candy, "position:y", 0.2, 0.7) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		fall.tween_callback(_burst_at.bind(Vector3(x, 0.3, z), 4, Color.WHITE, 0.4, 0.3))
		fall.tween_callback(candy.queue_free)
		await get_tree().create_timer(interval).timeout

# Iter 110: keep the visible posse Sprite3Ds in sync with _posse_count_3d.
# Called from gate-trigger and bullet-damage paths. Adds followers up to
# the new count (minus 1 for the leader cowboy_3d), trims excess from
# the tail. Cap at MAX_VISIBLE_FOLLOWERS so a ×4 gate doesn't spawn 100
# Sprite3Ds and tank the framerate.
const MAX_VISIBLE_FOLLOWERS: int = 24


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
	_outlaw_left_field(outlaw)
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
	"rainbow":   Color(0.7, 0.5, 1.0, 1),
}
const BONUS_LABELS: Dictionary = {
	"rifle":     "R",
	"frostbite": "❄",
	"frenzy":    "J!",
	"rainbow":   "★",
}

func _spawn_bonus() -> void:
	_spawn_bonus_typed(BONUS_TYPES[_rng.randi() % BONUS_TYPES.size()])

func _spawn_bonus_typed(t: String) -> void:
	var glitz: Dictionary = GlitzPrefs.get_bonus_glitz(t)
	# Iter 179: the bonus crate is a glitz sprite — breathing-shader plane
	# textured with the crate PNG, with the per-bonus glitz uniforms applied.
	var tex_path := "res://assets/sprites/props/bonus_crate_%s.png" % t
	var crate_tex: Texture2D = load(tex_path) if ResourceLoader.exists(tex_path) else null
	var bonus: MeshInstance3D = _make_breathing_prop(crate_tex, 1.4, 1.4, 0.04, 1.5, 0.02, 2.2)
	var mat: ShaderMaterial = bonus.material_override
	if mat != null:
		mat.set_shader_parameter("pulse_glow", glitz["pulse_glow"])
		mat.set_shader_parameter("hue_cycle", glitz["hue_cycle"])
		mat.set_shader_parameter("halo_strength", glitz["halo_strength"])
		mat.set_shader_parameter("sparkle_orbit", glitz["sparkle_orbit"])
		mat.set_shader_parameter("rotation_mode", glitz["rotation_mode"])
		mat.set_shader_parameter("rotation_speed", glitz["rotation_speed"])
	var lane_x: float = _rng.randf_range(-COWBOY_X_BOUND * 0.65, COWBOY_X_BOUND * 0.65)
	bonus.position = Vector3(lane_x, 1.2, OBSTACLE_SPAWN_Z + 2.0)
	bonus.set_meta("bonus_type", t)
	bonus.set_meta("spawn_time", _level_elapsed)
	# Iter 179: aura behind the crate if the glitz config calls for one.
	var aura: MeshInstance3D = _make_bonus_aura(glitz["aura"])
	if aura != null:
		bonus.add_child(aura)
		bonus.set_meta("aura", aura)
	# Floating type label above the crate.
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
	if get_node_or_null("/root/AudioBus") and AudioBus.has_method("play_sfx"):
		AudioBus.play_sfx("bonus_pickup")   # iter413
	var t: String = bonus.get_meta("bonus_type", "candy")
	match t:
		"rifle":     _fire_mode = FireMode.RIFLE
		"frostbite": _fire_mode = FireMode.FROSTBITE
		"frenzy":    _fire_mode = FireMode.FRENZY
		"rainbow":   _fire_mode = FireMode.RAINBOW
	_update_weapon_label()
	_spawn_popup_3d(bonus.position + Vector3(0, 2.0, 0),
		t.to_upper(), BONUS_COLORS[t], 56)
	bonus.queue_free()

# Iter 336: top-right indicator of the posse's currently-loaded weapon (the
# active FireMode), with a candy-bullet icon + name. Updated on pickup.
const WEAPON_NAMES := {
	FireMode.CANDY: "JELLY BEAN", FireMode.RIFLE: "RIFLE",
	FireMode.FROSTBITE: "FROSTBITE", FireMode.FRENZY: "FRENZY",
	FireMode.RAINBOW: "RAINBOW",
}
const WEAPON_ICONS := {
	FireMode.CANDY: "candy_red.png", FireMode.RIFLE: "candy_choc_stripe.png",
	FireMode.FROSTBITE: "candy_freezeray.png", FireMode.FRENZY: "candy_bomb.png",
	FireMode.RAINBOW: "../props/weapon_rainbow.png",
}
const WEAPON_COLORS := {
	FireMode.CANDY: Color(1.0, 0.62, 0.80, 1), FireMode.RIFLE: Color(0.88, 0.66, 0.40, 1),
	FireMode.FROSTBITE: Color(0.60, 0.86, 1.0, 1), FireMode.FRENZY: Color(1.0, 0.58, 0.88, 1),
	FireMode.RAINBOW: Color(0.7, 0.5, 1.0, 1),
}
var _weapon_label: Label = null
var _weapon_icon: TextureRect = null

func _build_weapon_indicator() -> void:
	var ui: Node = get_node_or_null("UI")
	if ui == null:
		return
	_weapon_icon = TextureRect.new()
	_weapon_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_weapon_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_weapon_icon.anchor_left = 1.0
	_weapon_icon.anchor_right = 1.0
	_weapon_icon.offset_left = -110.0
	_weapon_icon.offset_right = -20.0
	_weapon_icon.offset_top = 275.0
	_weapon_icon.offset_bottom = 365.0
	_weapon_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(_weapon_icon)
	_weapon_label = Label.new()
	_weapon_label.add_theme_font_size_override("font_size", 38)
	_weapon_label.add_theme_color_override("font_outline_color", Color(0.14, 0.05, 0.03, 1))
	_weapon_label.add_theme_constant_override("outline_size", 7)
	_weapon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_weapon_label.anchor_left = 1.0
	_weapon_label.anchor_right = 1.0
	_weapon_label.offset_left = -460.0
	_weapon_label.offset_right = -120.0
	_weapon_label.offset_top = 301.0
	_weapon_label.offset_bottom = 351.0
	_weapon_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(_weapon_label)
	_update_weapon_label()

# ── Iter 343: Quake bottom bar (Layout A) ──────────────────────────────────
# One consolidated strip: weapon hero + name footnote · 4-colour jelly-bean
# ammo clip · hearts · posse counter (pulses on change) · Slippery Pete end
# badge (dim→lit→spent). Reuses the existing weapon icon/label + HeartRow,
# reparented into the bar; the old scattered POSSE label is hidden.
var _quake_bar: Control = null
var _ammo_box: HBoxContainer = null
var _ammo_pips: Array = []
var _posse_bar_label: Label = null
var _pete_badge: TextureRect = null
var _levelname_label: Label = null
var _bullet_icon: TextureRect = null   # footnote: the bullet TYPE (candy) under the weapon hero
var _boss_fill: ColorRect = null       # level-progress fill leading to the boss badge
var _reload_label: Label = null        # iter357: RELOADING indicator on the bar (was top info_label)
var _speed_label: Label = null         # iter357: debug scroll-speed readout (top)
var _pause_btn: Button = null          # iter357: debug pause/resume (top)
var _last_ammo_shown: int = -1
var _last_posse_shown: int = -1
const _RYE3D := preload("res://assets/fonts/Rye-Regular.ttf")
const BOSS_TRACK_W: float = 300.0
# Weapon HERO art (the gun, not the bullet). Only the six-shooter is drawn so
# far; other modes fall back to it until their art exists.
const WEAPON_HERO := {
	FireMode.CANDY: "res://assets/sprites/props/weapon_six_shooter.png",
	FireMode.RIFLE: "res://assets/sprites/props/weapon_six_shooter.png",
	FireMode.FROSTBITE: "res://assets/sprites/props/weapon_six_shooter.png",
	FireMode.FRENZY: "res://assets/sprites/props/weapon_six_shooter.png",
	FireMode.RAINBOW: "res://assets/sprites/props/weapon_six_shooter.png",
}
# Per-weapon magazine size — drives both the gun + the ammo clip pip count.
const CLIP_BY_MODE := {
	FireMode.CANDY: 6, FireMode.RIFLE: 4, FireMode.FROSTBITE: 5, FireMode.FRENZY: 8,
	FireMode.RAINBOW: 7,
}
# Per-weapon rate of fire (seconds between shots) — lower = faster.
const FIRE_INTERVAL_BY_MODE := {
	FireMode.CANDY: 0.18, FireMode.RIFLE: 0.34, FireMode.FROSTBITE: 0.26, FireMode.FRENZY: 0.07,
	FireMode.RAINBOW: 0.10,
}
# Per-weapon range: the z a bullet travels to before despawning (more negative
# = longer reach; outlaws spawn at z=-24, so the rifle reaches them, the
# short-range frostbite only hits close).
const RANGE_Z_BY_MODE := {
	FireMode.CANDY: -10.0, FireMode.RIFLE: -26.0, FireMode.FROSTBITE: -6.0, FireMode.FRENZY: -13.0,
	FireMode.RAINBOW: -20.0,
}
var _bullet_despawn_z: float = -10.0   # current weapon's bullet range (set on weapon change)

func _build_quake_bar() -> void:
	var ui: Node = get_node_or_null("UI")
	if ui == null:
		return
	var bar := Control.new()
	bar.name = "QuakeBar"
	bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_top = -200.0
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(bar)
	_quake_bar = bar
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.16, 0.09, 0.06, 0.88)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(bg)
	# iter359: organic candy-Western top edge (was a perfectly straight pink rail).
	# A wavy dark-candy lip with a pink rim, baked into quakebar_edge.png (1080×52:
	# the bar-colour body sits below an undulating boundary, a candy-pink rim runs
	# along it, transparent above). Anchored full-width and lifted so the crests
	# rise ~30px above the bar's old straight top into the game — soft, not a ruler line.
	var edge := TextureRect.new()
	edge.set_anchors_preset(Control.PRESET_TOP_WIDE)
	edge.offset_top = -44.0
	edge.offset_bottom = 12.0
	edge.stretch_mode = TextureRect.STRETCH_SCALE
	var _edge_tex := "res://assets/sprites/props/quakebar_edge.png"
	if ResourceLoader.exists(_edge_tex):
		edge.texture = load(_edge_tex)
	else:
		edge.self_modulate = Color(1.0, 0.45, 0.62, 1.0)  # fallback flat rail
	edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(edge)
	_levelname_label = Label.new()
	_levelname_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_levelname_label.offset_top = 12.0
	_levelname_label.offset_bottom = 50.0
	_levelname_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_levelname_label.add_theme_font_override("font", _RYE3D)
	_levelname_label.add_theme_font_size_override("font_size", 30)
	_levelname_label.add_theme_color_override("font_color", Color(1, 0.95, 0.8))
	_levelname_label.add_theme_constant_override("outline_size", 6)
	_levelname_label.add_theme_color_override("font_outline_color", Color(0.1, 0.04, 0.03))
	_levelname_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(_levelname_label)
	# 4-colour jelly-bean ammo clip (count = current weapon's magazine)
	_ammo_box = HBoxContainer.new()
	_ammo_box.name = "AmmoPips"
	_ammo_box.position = Vector2(286, 58)
	_ammo_box.add_theme_constant_override("separation", 8)
	_ammo_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(_ammo_box)
	_rebuild_ammo_pips()
	# RELOADING caption — a compact word in the gap directly UNDER the clip row
	# (pips at y58..102, hearts at y124). The clip itself refills (the pips fill
	# back up as the reload progresses, see _refresh_ammo_label_3d) so the reload
	# reads as part of the ammo clip, not a separate floating bar over it.
	_reload_label = Label.new()
	_reload_label.position = Vector2(286, 99)
	_reload_label.size = Vector2(320.0, 26.0)
	_reload_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_reload_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_reload_label.add_theme_font_size_override("font_size", 18)
	_reload_label.add_theme_color_override("font_color", Color(1.0, 0.62, 0.32))
	_reload_label.add_theme_constant_override("outline_size", 4)
	_reload_label.add_theme_color_override("font_outline_color", Color(0.1, 0.04, 0.03))
	_reload_label.visible = false
	_reload_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(_reload_label)
	# posse counter (pulses on change)
	_posse_bar_label = Label.new()
	_posse_bar_label.position = Vector2(632, 40)
	_posse_bar_label.add_theme_font_override("font", _RYE3D)
	_posse_bar_label.add_theme_font_size_override("font_size", 48)
	_posse_bar_label.add_theme_color_override("font_color", Color(1, 0.9, 0.5))
	_posse_bar_label.add_theme_constant_override("outline_size", 8)
	_posse_bar_label.add_theme_color_override("font_outline_color", Color(0.1, 0.04, 0.03))
	_posse_bar_label.pivot_offset = Vector2(90, 34)
	_posse_bar_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(_posse_bar_label)
	# Slippery Pete end badge
	_pete_badge = TextureRect.new()
	_pete_badge.position = Vector2(944, 38)
	_pete_badge.size = Vector2(120, 150)
	_pete_badge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_pete_badge.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_pete_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ResourceLoader.exists("res://assets/sprites/slippery_pete.png"):
		_pete_badge.texture = load("res://assets/sprites/slippery_pete.png")
	_pete_badge.modulate = Color(0.5, 0.5, 0.55, 0.8)  # dim until the boss arrives
	bar.add_child(_pete_badge)
	# level-progress trail leading into the boss badge
	var boss_track := ColorRect.new()
	boss_track.position = Vector2(632, 116)
	boss_track.size = Vector2(BOSS_TRACK_W, 22)
	boss_track.color = Color(0.0, 0.0, 0.0, 0.45)
	boss_track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(boss_track)
	_boss_fill = ColorRect.new()
	_boss_fill.position = Vector2(632, 116)
	_boss_fill.size = Vector2(0, 22)
	_boss_fill.color = Color(1.0, 0.45, 0.30, 1.0)
	_boss_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(_boss_fill)
	# bullet-TYPE footnote chip beside the weapon hero
	_bullet_icon = TextureRect.new()
	_bullet_icon.position = Vector2(148, 60)
	_bullet_icon.size = Vector2(44, 44)
	_bullet_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bullet_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_bullet_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(_bullet_icon)
	# reparent the weapon hero + name + hearts into the bar (top of the z-order)
	_reparent_into_bar(_weapon_icon, Vector2(14, 52), Vector2(124, 124))
	if _weapon_label != null:
		_weapon_label.add_theme_font_override("font", _RYE3D)
		_weapon_label.add_theme_font_size_override("font_size", 26)
		_weapon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_reparent_into_bar(_weapon_label, Vector2(2, 160), Vector2(280, 36))
	# iter370 winflow: hearts no longer live on the Quake bar — they're pinned
	# in the top-left taffy cutout ($UI/HeartsCutout/HeartCookieRow) where the
	# cookies dance, so the reparent into the bar is removed.
	if posse_label != null:
		posse_label.visible = false  # absorbed into the bar

# iter357: top debug controls — a scroll-speed readout (SP2 pacing) + a
# pause/resume button. The button uses PROCESS_MODE_ALWAYS so it stays
# clickable while the tree is paused.
func _build_top_debug() -> void:
	var ui: Node = get_node_or_null("UI")
	if ui == null:
		return
	_speed_label = Label.new()
	_speed_label.position = Vector2(24, 22)
	_speed_label.add_theme_font_size_override("font_size", 30)
	_speed_label.add_theme_color_override("font_color", Color(0.55, 1.0, 0.7))
	_speed_label.add_theme_constant_override("outline_size", 5)
	_speed_label.add_theme_color_override("font_outline_color", Color(0.1, 0.04, 0.03))
	_speed_label.text = "spd —"
	_speed_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(_speed_label)
	_pause_btn = Button.new()
	_pause_btn.text = "PAUSE"  # text, not ⏸/▶ — the theme font has no emoji glyphs (tofu)
	_pause_btn.add_theme_font_size_override("font_size", 26)
	_pause_btn.anchor_left = 1.0
	_pause_btn.anchor_right = 1.0
	_pause_btn.offset_left = -150.0
	_pause_btn.offset_right = -16.0
	_pause_btn.offset_top = 16.0
	_pause_btn.offset_bottom = 84.0
	_pause_btn.process_mode = Node.PROCESS_MODE_ALWAYS
	_pause_btn.pressed.connect(_toggle_pause)
	ui.add_child(_pause_btn)

func _toggle_pause() -> void:
	var p: bool = not get_tree().paused
	get_tree().paused = p
	if _pause_btn != null:
		_pause_btn.text = "PLAY" if p else "PAUSE"

func _reparent_into_bar(node: Control, pos: Vector2, sz: Vector2) -> void:
	if node == null or _quake_bar == null:
		return
	var par := node.get_parent()
	if par != null:
		par.remove_child(node)
	_quake_bar.add_child(node)
	node.anchor_left = 0.0
	node.anchor_top = 0.0
	node.anchor_right = 0.0
	node.anchor_bottom = 0.0
	node.offset_left = pos.x
	node.offset_top = pos.y
	node.offset_right = pos.x + sz.x
	node.offset_bottom = pos.y + sz.y
	node.size = sz

# Rebuild the clip to the current weapon's magazine size, then colour the pips.
func _rebuild_ammo_pips() -> void:
	if _ammo_box == null:
		return
	for c in _ammo_box.get_children():
		c.queue_free()
	_ammo_pips.clear()
	var clip: int = int(_gun.clip_size) if _gun != null else 6
	for i in clip:
		var pip := TextureRect.new()
		pip.custom_minimum_size = Vector2(44, 44)
		pip.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pip.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_ammo_box.add_child(pip)
		_ammo_pips.append(pip)
	_recolor_ammo_pips()
	_last_ammo_shown = -1  # force a refresh of the filled/spent state

func _recolor_ammo_pips() -> void:
	if _ammo_pips.is_empty():
		return
	var cols: Array = CANDY_BULLET_TEX.get(_fire_mode, CANDY_BULLET_TEX[FireMode.CANDY])
	for i in _ammo_pips.size():
		var cp: String = _CANDY_DIR + str(cols[i % cols.size()])
		if ResourceLoader.exists(cp):
			(_ammo_pips[i] as TextureRect).texture = load(cp)

func _level_display_name() -> String:
	var lv: int = 1
	if get_node_or_null("/root/GameState"):
		lv = GameState.current_level
	var names := {1: "PEPPERMINT FRONTIER TOWN"}
	return names.get(lv, "LEVEL %d" % lv)

func _refresh_quake_bar() -> void:
	if _quake_bar == null:
		return
	var ammo: int = _gun_state.ammo() if _gun_state != null else _ammo_pips.size()
	for i in _ammo_pips.size():
		(_ammo_pips[i] as TextureRect).modulate.a = 1.0 if i < ammo else 0.20
	_last_ammo_shown = ammo
	if _posse_bar_label != null:
		_posse_bar_label.text = "POSSE %d" % _posse_count_3d
		if _last_posse_shown >= 0 and _posse_count_3d != _last_posse_shown:
			var t := create_tween()
			t.tween_property(_posse_bar_label, "scale", Vector2(1.3, 1.3), 0.08)
			t.tween_property(_posse_bar_label, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK)
		_last_posse_shown = _posse_count_3d
	if _levelname_label != null:
		_levelname_label.text = _level_display_name()
	if _boss_fill != null:
		var prog: float = 1.0 if _level_state == LevelState.BOSS or _pete_spawned \
			else clampf(_level_elapsed / PETE_SPAWN_DELAY, 0.0, 1.0)
		_boss_fill.size.x = BOSS_TRACK_W * prog
	if _pete_badge != null:
		if _pete_defeated:
			_pete_badge.modulate = Color(0.3, 0.3, 0.3, 0.5)
		elif _pete_spawned:
			_pete_badge.modulate = Color(1, 1, 1, 1)
		else:
			_pete_badge.modulate = Color(0.5, 0.5, 0.55, 0.8)

func _update_weapon_label() -> void:
	if _weapon_label == null:
		return
	_weapon_label.text = WEAPON_NAMES.get(_fire_mode, "JELLY BEAN")
	_weapon_label.add_theme_color_override("font_color", WEAPON_COLORS.get(_fire_mode, Color.WHITE))
	# Hero = the WEAPON (gun) image; the bullet candy is the footnote chip.
	if _weapon_icon != null:
		var hero_path: String = WEAPON_HERO.get(_fire_mode, WEAPON_HERO[FireMode.CANDY])
		if ResourceLoader.exists(hero_path):
			_weapon_icon.texture = load(hero_path)
	if _bullet_icon != null:
		var bpath: String = _CANDY_DIR + str(WEAPON_ICONS.get(_fire_mode, "candy_red.png"))
		if ResourceLoader.exists(bpath):
			_bullet_icon.texture = load(bpath)
	# Per-weapon rate of fire + bullet range.
	if _gun != null:
		_gun.fire_interval = float(FIRE_INTERVAL_BY_MODE.get(_fire_mode, 0.18))
	_bullet_despawn_z = float(RANGE_Z_BY_MODE.get(_fire_mode, -10.0))
	# Resize the magazine to this weapon's clip + give a fresh full mag, then
	# rebuild the clip pips to match (count + colours).
	var want: int = int(CLIP_BY_MODE.get(_fire_mode, 6))
	if _gun != null and int(_gun.clip_size) != want:
		_gun.clip_size = want
		_gun_state = GunStateScript.new(_gun)  # fresh full mag of the new size
		_rebuild_ammo_pips()
	else:
		_recolor_ammo_pips()

# ── Iter 179: bonus-crate auras (ported from glitz_picker.gd) ─────────────
# A bonus's glitz config (GlitzPrefs.BONUS_GLITZ) can carry an aura behind
# the crate sprite: "sunburst" (a static filled 12-petal star that slowly
# rotates) or "electric" (12 spinning, pulsing arcs rebuilt each frame).
const AURA_PETALS: int = 12
const AURA_SEGS: int = 16
const AURA_RADIUS: float = 2.5
const AURA_HALF_WIDTH: float = 0.05

func _make_sunburst_mesh() -> ArrayMesh:
	var verts := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var seg: int = 96
	verts.append(Vector3.ZERO)
	colors.append(Color(1.0, 0.92, 0.58, 1.0))
	for i in range(seg + 1):
		var th: float = TAU * float(i) / float(seg)
		var r: float = 0.70 + 0.32 * cos(12.0 * th)
		verts.append(Vector3(cos(th) * r, sin(th) * r, 0.0))
		colors.append(Color(1.0, 0.74, 0.30, 0.0))
	for i in range(seg):
		indices.append(0)
		indices.append(1 + i)
		indices.append(2 + i)
	var arr: Array = []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_COLOR] = colors
	arr[Mesh.ARRAY_INDEX] = indices
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return am

func _aura_tri(im: ImmediateMesh, a: Vector3, ca: Color,
		b: Vector3, cb: Color, c: Vector3, cc: Color) -> void:
	im.surface_set_color(ca)
	im.surface_add_vertex(a)
	im.surface_set_color(cb)
	im.surface_add_vertex(b)
	im.surface_set_color(cc)
	im.surface_add_vertex(c)

func _emit_aura_petal(im: ImmediateMesh, i: int, t: float) -> void:
	var angle_base: float = (float(i) / float(AURA_PETALS)) * TAU + t * 0.7
	var pulse: float = 0.28 + 0.08 * sin(t * 2.1 + float(i) * 1.3)
	var whip: float = sin(t * 0.6 + float(i) * 0.5)
	var hue: float = fmod(0.55 + 0.05 * sin(t * 0.5 + float(i)), 1.0)
	var core: Color = Color.from_hsv(hue, 0.45, 1.0, 0.9)
	var edge: Color = Color(core.r, core.g, core.b, 0.0)
	var pts: Array[Vector3] = []
	for k in AURA_SEGS + 1:
		var s: float = float(k) / float(AURA_SEGS)
		var r: float = sin(s * PI) * pulse * AURA_RADIUS
		var ang: float = angle_base + s * PI * 0.9 * whip
		pts.append(Vector3(cos(ang) * r, sin(ang) * r, 0.0))
	for k in AURA_SEGS:
		var p0: Vector3 = pts[k]
		var p1: Vector3 = pts[k + 1]
		var d: Vector3 = p1 - p0
		if d.length() < 0.0001:
			continue
		d = d.normalized()
		var perp: Vector3 = Vector3(-d.y, d.x, 0.0) * AURA_HALF_WIDTH
		_aura_tri(im, p0 + perp, edge, p0, core, p1, core)
		_aura_tri(im, p0 + perp, edge, p1, core, p1 + perp, edge)
		_aura_tri(im, p0, core, p0 - perp, edge, p1 - perp, edge)
		_aura_tri(im, p0, core, p1 - perp, edge, p1, core)

func _emit_aura_orb(im: ImmediateMesh, t: float) -> void:
	var pr: float = (0.16 + 0.05 * sin(t * 3.5)) * AURA_RADIUS
	var core: Color = Color(0.82, 0.90, 1.0, 0.95)
	var edge: Color = Color(0.30, 0.50, 1.0, 0.0)
	var rim: int = 22
	for k in rim:
		var a0: float = TAU * float(k) / float(rim)
		var a1: float = TAU * float(k + 1) / float(rim)
		_aura_tri(im, Vector3.ZERO, core,
			Vector3(cos(a0) * pr, sin(a0) * pr, 0.0), edge,
			Vector3(cos(a1) * pr, sin(a1) * pr, 0.0), edge)

func _rebuild_electric_aura(im: ImmediateMesh, t: float) -> void:
	im.clear_surfaces()
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in AURA_PETALS:
		_emit_aura_petal(im, i, t)
	_emit_aura_orb(im, t)
	im.surface_end()

# Build an aura MeshInstance3D for a bonus crate; null for aura "none".
func _make_bonus_aura(aura_type: String) -> MeshInstance3D:
	if aura_type != "sunburst" and aura_type != "electric":
		return null
	var aura := MeshInstance3D.new()
	var amat := StandardMaterial3D.new()
	amat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	amat.vertex_color_use_as_albedo = true
	amat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	amat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	amat.cull_mode = BaseMaterial3D.CULL_DISABLED
	amat.billboard_mode = 1  # BILLBOARD_ENABLED — keep the aura facing the camera
	aura.material_override = amat
	aura.set_meta("aura_type", aura_type)
	aura.position = Vector3(0, 0, -0.06)  # just behind the crate sprite
	if aura_type == "sunburst":
		aura.mesh = _make_sunburst_mesh()
	else:
		aura.mesh = ImmediateMesh.new()
	return aura

# Per-frame: rebuild each electric aura's geometry (the sunburst is static).
var _bonus_aura_t: float = 0.0

func _update_bonus_auras(delta: float) -> void:
	if bonuses_root == null:
		return
	_bonus_aura_t += delta
	for b in bonuses_root.get_children():
		var aura: Variant = b.get_meta("aura", null)
		if aura is MeshInstance3D and aura.get_meta("aura_type", "") == "electric":
			_rebuild_electric_aura(aura.mesh as ImmediateMesh, _bonus_aura_t)

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

# SP2: route a timeline event to its gameplay spawner. Only BOSS is wired in
# slice 1; later slices add the other EventKinds.
func _dispatch_level_event(ev: LevelEvent) -> void:
	match ev.kind:
		LevelEvent.EventKind.BOSS:
			if not _pete_spawned and not _test_range_mode and not _quota_driven():
				_pete_spawned = true
				var _bk := String(ev.params.get("boss", "pete"))
				if _bk == "rustler":
					_spawn_candy_rustler()
				elif _bk == "raisin":
					_spawn_raisin_kidd()
				else:
					_spawn_pete()
				# iter418: clear on-screen gates so the boss isn't hidden behind one
				# (the legacy Pete path did this; the data path did not, which is why the
				# L2 Rustler was unhittable). New gates are blocked once state != PLAYING.
				for _g in gates_root.get_children():
					_g.queue_free()
				_level_state = LevelState.BOSS
				DebugLog.add("SP2: boss spawned from data event at dist %.1f (gates cleared)" % ev.distance)
		LevelEvent.EventKind.PACING:
			if _director != null:
				_director.set_cruise(float(ev.params.get("speed_factor", 1.0)))
				DebugLog.add("SP2: pacing cruise=%.2f at dist %.1f" % [_director.cruise, ev.distance])
		LevelEvent.EventKind.APPROACH_ZONE:
			if _director != null:
				var exit_name := String(ev.params.get("exit", "clear"))
				var exit_id := LevelDirector.ApproachExit.CLEAR
				if exit_name == "timer":
					exit_id = LevelDirector.ApproachExit.TIMER
				elif exit_name == "event":
					exit_id = LevelDirector.ApproachExit.EVENT
				_director.enter_zone(exit_id, float(ev.params.get("timeout", 12.0)))
				DebugLog.add("SP2: approach zone (%s) at dist %.1f" % [exit_name, ev.distance])
		LevelEvent.EventKind.HOLE:
			_spawn_hole(ev.params)
		LevelEvent.EventKind.BONUS:
			_spawn_bonus_typed(String(ev.params.get("type", "frenzy")))
		LevelEvent.EventKind.KIMMY:
			_spawn_kimmy_cage()

# SP2: live (non-captive) enemy count — drives the director's reactive damping
# + the CLEAR approach-zone exit. Mirrors the dynamic-camera threat count.
func _live_enemy_count() -> int:
	var n: int = 0
	for c in outlaws_root.get_children():
		if is_instance_valid(c) and not c.get_meta("is_captive", false):
			n += 1
	return n

# SP2 slice3: a pit/cliff the posse + outlaws fall into. A flat dark decal on
# the ground that scrolls in with the world; its (x,z) extent is the fall zone.
func _spawn_hole(params: Dictionary) -> void:
	if holes_root == null:
		return
	var hole := Node3D.new()
	hole.position = Vector3(float(params.get("x", 0.0)), 0.02, OBSTACLE_SPAWN_Z)
	hole.set_meta("x_half", float(params.get("x_half", 1.2)))
	hole.set_meta("z_half", float(params.get("z_half", 1.6)))
	# winflow: dynamic holes also get a candy fill (cycles with the spawn count).
	var fill: String = _PIT_FILLS[_dyn_hole_count % _PIT_FILLS.size()]
	_dyn_hole_count += 1
	hole.set_meta("pit_fill", fill)
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()  # PlaneMesh lies flat on XZ (normal up)
	pm.size = Vector2(hole.get_meta("x_half") * 2.0, hole.get_meta("z_half") * 2.0)
	mi.mesh = pm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var dyn_path: String = "res://assets/sprites/ui/winflow/pit_%s.png" % fill
	if ResourceLoader.exists(dyn_path):
		m.albedo_texture = load(dyn_path)
	else:
		m.albedo_texture = load("res://assets/sprites/props/pit_hole.png")
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	hole.add_child(mi)
	holes_root.add_child(hole)
	DebugLog.add("SP2: hole x=%.1f xh=%.1f zh=%.1f" % [hole.position.x, hole.get_meta("x_half"), hole.get_meta("z_half")])

func _in_box(px: float, pz: float, cx: float, cz: float, half_x: float, half_z: float) -> bool:
	return absf(px - cx) <= half_x and absf(pz - cz) <= half_z

# Drop an entity into a pit: fall + shrink, then free. Marked "falling" so the
# regular loops skip it.
func _fall_entity(node: Node3D) -> void:
	if get_node_or_null("/root/AudioBus") and AudioBus.has_method("play_sfx"): AudioBus.play_sfx("hole_fall")
	if not is_instance_valid(node):
		return
	node.set_meta("falling", true)
	var t := node.create_tween()
	t.set_parallel(true)
	t.tween_property(node, "position:y", node.position.y - 6.0, 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.tween_property(node, "scale", node.scale * 0.15, 0.55)
	t.chain().tween_callback(node.queue_free)


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
	# Pick a taunt by INDEX so the spoken clip (pete_taunt_N) matches the
	# bubble text. Per-line angry VO now exists (gen_pete_vo.py).
	var ti: int = randi() % 4
	var line: String = Text.lookup("boss.slippery_pete_dialog_taunts.%d" % ti)
	if line == "" or line.begins_with("boss."):
		return
	# Iter 146: SHOUT animation flash + voice line. Bubble lowered from
	# Pete's head (y+4 = off-screen at top) to chest level so the user
	# actually sees the banter.
	_set_pete_anim(pete, PETE_SHOUT_STREAM, 1.5)
	# Only speak if no other Pete line is mid-playback, so taunts and hit
	# reactions don't talk over each other (iter 330).
	if get_node_or_null("/root/AudioBus") and AudioBus.has_method("play_character_line") \
			and not (AudioBus.has_method("any_character_line_playing") \
				and AudioBus.any_character_line_playing()):
		AudioBus.play_character_line("pete_taunt_%d" % ti)
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

# Which boss spawns this run. Level 2 → The Candy Rustler; level 5 → Raisin Kidd; all else → Pete.
func _boss_kind() -> String:
	var lvl: int = 1
	if get_node_or_null("/root/GameState") != null:
		lvl = GameState.current_level
	if lvl == 2:
		return "rustler"
	if lvl == 5:
		return "raisin"
	if lvl == 6:
		return "queen"
	return "pete"

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

# Spawn the Level-5 boss, Raisin Kidd. Video-billboard actor (guard idle clip),
# HUD HP bar mirrored from RaisinKiddState. Per-frame logic is _process_raisin_kidd.
func _spawn_raisin_kidd() -> void:
	_raisin = _RAISIN_KIDD_STATE.new()
	var boss := Node3D.new()
	boss.position = Vector3(0.0, 2.25, OBSTACLE_SPAWN_Z + 4.0)
	boss.set_meta("hp", _raisin.hp)
	boss.set_meta("hp_max", RaisinKiddState.MAX_HP)
	boss.set_meta("boss_kind", "raisin")
	boss_root.add_child(boss)
	var bb: Node3D = _make_video_billboard(load(RAISIN_GUARD_STREAM), RAISIN_HEIGHT)
	boss.add_child(bb)
	if bb.get_child_count() > 0:
		boss.set_meta("sprite_3d", bb.get_child(0))
	var name_plate := Label3D.new()
	name_plate.text = "RAISIN KIDD"
	name_plate.font_size = 44
	name_plate.outline_size = 9
	name_plate.modulate = Color(0.85, 0.45, 0.85, 1)
	name_plate.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	name_plate.no_depth_test = true
	name_plate.position = Vector3(0, 0.6, 0.6)
	boss.add_child(name_plate)
	_install_pete_hud(boss, "RAISIN KIDD")
	_refresh_pete_hp(boss)
	info_label.text = "BOSS — RAISIN KIDD"
	_raisin_say("intro")
	DebugLog.add("raisin kidd spawned at z=%.1f, HP=%d" % [boss.position.z, _raisin.hp])

# Raisin Kidd per-frame behavior. Counts overlapping posse bullets into the
# state machine, reacts to the events it emits (deflect sparks / damage popups,
# manga FX, warp reposition, GoW posse drain, WIN flow). The boss holds near
# arena center, so manga FX anchor at a fixed upper-center screen point (robust
# vs projecting the SubViewport camera; device-tune later).
func _process_raisin_kidd(boss: Node3D, delta: float) -> void:
	if _raisin == null or boss.get_meta("dying", false):
		return
	if boss.position.z < RAISIN_STAY_Z:
		boss.position.z += RUSTLER_SPEED * delta
	# Overlapping posse bullets this frame (consumed visually either way).
	var hits := 0
	for bullet in bullets_root.get_children():
		if not (bullet is Node3D):
			continue
		var dx: float = bullet.position.x - boss.position.x
		var dz: float = bullet.position.z - boss.position.z
		if dx * dx + dz * dz < PETE_HIT_RADIUS_SQ:
			hits += 1
			bullet.queue_free()
	_raisin_hit_voice_cd = maxf(0.0, _raisin_hit_voice_cd - delta)
	if hits > 0:
		_raisin.register_fire(hits)
		_hits += hits        # run hit tally (matches rustler/Pete), feeds the end-of-run bounty
		_refresh_hud()
		if _raisin.is_vulnerable():
			_spawn_popup_3d(boss.position + Vector3(0, 1.6, 0),
				"-%d" % hits, Color(0.85, 0.45, 0.85, 1), 64)
			if _raisin_hit_voice_cd <= 0.0:
				_raisin_hit_voice_cd = 3.5
				_raisin_say("hit")
		else:
			_spawn_popup_3d(boss.position + Vector3(0, 1.6, 0), "TINK",
				Color(0.8, 0.85, 1.0, 1), 48)
	var events: Array = _raisin.tick(delta)
	boss.set_meta("hp", _raisin.hp)
	_refresh_pete_hp(boss)
	var anchor: Vector2 = get_viewport_rect().size * Vector2(0.5, 0.4)
	# Unlisted events (gow_recovery_open/_end, guard_reform) are intentionally
	# not handled here — the vulnerability window is read via _raisin.is_vulnerable().
	for e in events:
		match e:
			"gow_windup":
				if _manga_fx: _manga_fx.focus_lines(anchor)
				_raisin_say("gow")
			"gow_flurry":
				if _manga_fx: _manga_fx.burst(anchor, "DOON!")
			"warp":
				boss.position.x = _rng.randf_range(-RAISIN_WARP_X_MAX, RAISIN_WARP_X_MAX)
				if _manga_fx: _manga_fx.burst(anchor, "")
				_raisin_say("warp")
			"phase2":
				_raisin_say("phase2")
			"guard_shatter":
				if _manga_fx: _manga_fx.burst(anchor, "KRAK!")
			"defeat":
				boss.set_meta("dying", true)
				_raisin_say("dying")
				_show_win("Raisin Kidd", boss, null)
				return
	if _raisin.mode == RaisinKiddState.Mode.FLURRY:
		_raisin_flurry_accum += delta * RAISIN_FLURRY_DPS
		while _raisin_flurry_accum >= 1.0:
			_raisin_flurry_accum -= 1.0
			_outlaw_drain_posse(boss.position, "")

# Raisin Kidd voice line. Banks generated in a later task; no-ops safely until
# the audio + keys exist (mirrors the rustler/pete line pattern).
func _raisin_say(kind: String) -> void:
	var banks: Dictionary = {
		"intro": ["raisin_intro_", 2], "gow": ["raisin_gow_", 3],
		"warp": ["raisin_warp_", 3], "phase2": ["raisin_phase2_", 2],
		"hit": ["raisin_hit_", 4], "dying": ["raisin_dying_", 2],
		"finisher": ["raisin_finisher_", 2],
	}
	if not banks.has(kind):
		return
	var audio := get_node_or_null("/root/AudioBus")
	if audio == null or not audio.has_method("play_character_line"):
		return
	var entry: Array = banks[kind]
	audio.play_character_line("%s%d" % [entry[0], randi() % int(entry[1])])

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
	# iter357: ammo lives on the Quake bar (pips); the top label is gone.
	# iter359: integrate the reload into the clip itself — the candy pips refill
	# (empty → full) as the reload progresses, with a small "RELOADING" caption in
	# the gap under them. Runs every frame (called from _process) so the fill
	# animates; _refresh_quake_bar restores the ammo-based fill once reload ends.
	if _reload_label == null or _gun_state == null:
		return
	if _gun_state.is_reloading():
		var filled: int = int(round(float(_ammo_pips.size()) * _gun_state.reload_progress()))
		for i in _ammo_pips.size():
			(_ammo_pips[i] as TextureRect).modulate.a = 1.0 if i < filled else 0.20
		_last_ammo_shown = -1  # force _refresh_quake_bar to repaint pips when reload ends
		_reload_label.visible = true
		_reload_label.text = "RELOADING…"
	else:
		_reload_label.visible = false

func _refresh_hud() -> void:
	if hearts_label:
		var max_h: int = 5
		var current: int = 5
		if get_node_or_null("/root/GameState"):
			max_h = GameState.MAX_HEARTS
			current = GameState.hearts
		hearts_label.set_hearts(current, max_h)  # iter337: drawn, not ♥ glyph
	if posse_label:
		posse_label.text = "POSSE: %d" % _posse_count_3d
	if hits_label:
		hits_label.text = "HITS: %d" % _hits
	_refresh_quake_bar()

# Iter 78: trigger the FAIL flow on posse=0. Deduct a heart, pop the
# FailOverlay, freeze the game (skip _process via _failed flag).
func _show_fail() -> void:
	if _failed:
		return
	_failed = true
	if get_node_or_null("/root/AudioBus") and AudioBus.has_method("play_sfx"):
		AudioBus.play_sfx("fail_sting")   # iter413
	# Iter 87: kill any lingering gunshot pool samples so the sound
	# doesn't keep playing after the firefight ends.
	if get_node_or_null("/root/AudioBus") and AudioBus.has_method("stop_gunfire"):
		AudioBus.stop_gunfire()
	info_label.text = "DEAD  ·  posse 0  ·  hits %d" % _hits
	# Level-5: if the player fell at Raisin Kidd, play his Five-Point finisher
	# cinematic before the Fail modal. (_failed is already true, so re-entry is
	# guarded.)
	var raisin_live := false
	if boss_root.get_child_count() > 0:
		var b: Node = boss_root.get_child(0)
		raisin_live = is_instance_valid(b) and b.get_meta("boss_kind", "") == "raisin"
	if raisin_live:
		await _play_raisin_finisher()
	_present_fail_modal()

# Five-Point Raisin Exploding Gumdrop Technique — the lose cinematic, only when
# the player is defeated AT the Raisin Kidd boss. Non-interactive flourish that
# runs before the Fail modal.
func _play_raisin_finisher() -> void:
	if _manga_fx == null:
		return
	var vp: Vector2 = get_viewport_rect().size
	var strike: Vector2 = vp * Vector2(0.5, 0.6)
	_raisin_say("finisher")   # triumphant five-point cackle (he WON this exchange)
	_manga_fx.title_card("FIVE-POINT RAISIN\nEXPLODING GUMDROP!")
	await get_tree().create_timer(1.1).timeout
	for i in range(5):
		_manga_fx.burst(strike + Vector2((i - 2) * 30, (i - 2) * 12), "BAP!")
		await get_tree().create_timer(0.12).timeout
	_manga_fx.gumdrop_countdown(strike)
	# matches manga_fx.gd PIP_STEP*5 + BLOOM_LIFE (5 pips, then the KA-BLOOM)
	var countdown_dur: float = 0.45 * 5.0 + 0.9
	await get_tree().create_timer(countdown_dur).timeout
	_manga_fx.title_card("DEFEATED")
	await get_tree().create_timer(0.9).timeout

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
	if get_node_or_null("/root/AudioBus") and AudioBus.has_method("play_sfx"):
		AudioBus.play_sfx("win_fanfare")   # iter413
	info_label.text = "WIN!  %s defeated · posse %d · hits %d" % [
		boss_label, _posse_count_3d, _hits,
	]
	# Iter 123: Gold Rush A — PERFECT_VOLLEY banner pops before the
	# salute fire ceremony, matching the 2D level.gd Gold Rush A flow.
	var ui_canvas: Node = get_node_or_null("UI")
	if ui_canvas != null:
		FlourishBanner.spawn(ui_canvas, "PERFECT_VOLLEY")
	await _gold_rush_salute_3d()
	AudioBus.play_gate_pass()
	_present_win_modal()
	# Iter 157: free the boss node + its SubViewport when passed in. Pete
	# frees himself before calling _show_win; the Rustler is kept alive
	# through the salute so his death scatter plays, then cleaned up here.
	if cleanup_node != null and is_instance_valid(cleanup_node):
		cleanup_node.queue_free()
	if cleanup_viewport != null and is_instance_valid(cleanup_viewport):
		cleanup_viewport.queue_free()

func _present_win_modal() -> void:
	var diff: int = _level_def.difficulty if _level_def != null else 1
	var thr: Array = _level_def.star_thresholds if _level_def != null else [0, 1500, 3500]
	var rb: int = _run_bounty()
	var stars: int = GameState.stars_for(rb, thr)
	var next_needed: int = 0
	for t in thr:
		if rb < int(t):
			next_needed = int(t) - rb
			break
	var lvl: int = GameState.current_level if get_node_or_null("/root/GameState") else 1
	if get_node_or_null("/root/GameState"):
		GameState.record_level_result(lvl, stars, rb)
		GameState.current_level = lvl + 1
		GameState.just_won_level = lvl
	var hearts: int = GameState.hearts if get_node_or_null("/root/GameState") else 5
	var hmax: int = GameState.MAX_HEARTS if get_node_or_null("/root/GameState") else 5
	# Winflow: achievement-header banner (FLAWLESS / WHOLE POSSE / JACKPOT / ...).
	var posse_start: int = _level_def.start_posse if _level_def != null else 0
	var jackpot: int = int(int(thr[2]) * 1.5) if thr.size() > 2 else 999999
	var hdr: Dictionary = GameState.win_header(
		stars, _hits, _posse_count_3d, posse_start, rb, jackpot)
	_end_modal = WIN_MODAL_SCENE.instantiate()
	get_node("UI").add_child(_end_modal)
	_end_modal.show_win(diff, rb, stars, next_needed, hearts, hmax, hdr)
	_end_modal.continue_pressed.connect(_goto_map.bind(true))
	_end_modal.replay_pressed.connect(_retry_level)
	_end_modal.map_pressed.connect(_goto_map.bind(false))

func _present_fail_modal() -> void:
	var hearts: int = GameState.hearts if get_node_or_null("/root/GameState") else 5
	var hmax: int = GameState.MAX_HEARTS if get_node_or_null("/root/GameState") else 5
	var regen_text: String = ""
	if get_node_or_null("/root/GameState") and GameState.has_method("regen_text"):
		regen_text = GameState.regen_text()
	_end_modal = FAIL_MODAL_SCENE.instantiate()
	get_node("UI").add_child(_end_modal)
	_end_modal.show_fail(_run_bounty(), hearts, hmax, regen_text)
	_end_modal.retry_pressed.connect(_retry_level)
	_end_modal.map_pressed.connect(_goto_map.bind(false))

func _goto_map(continue_next: bool) -> void:
	# just_won_level was set on win; level_select reads it to celebrate.
	# continue_next: CONTINUE auto-starts the next level after the celebration;
	# MAP (and fail's MAP) stay on the level-select map.
	if get_node_or_null("/root/GameState"):
		GameState.continue_to_next = continue_next
	get_tree().change_scene_to_file("res://scenes/level_select.tscn")

func _retry_level() -> void:
	# Retry costs a heart, charged HERE (not on death). If broke, do nothing
	# (the FailModal disables the button at 0 hearts).
	if get_node_or_null("/root/GameState"):
		if GameState.hearts <= 0:
			return
		GameState.spend_heart()
	if get_node_or_null("/root/DebugPreview") and DebugPreview.has_method("clear"):
		DebugPreview.clear()
	get_tree().reload_current_scene()

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
		# Salute bullet — a bright jelly-bean fired straight up. iter359: was a
		# faceted CSGSphere3D (radial_segments 8 / rings 6) — the last raw polygon
		# visible in gameplay, popping up during PERFECT_VOLLEY. Swapped to the same
		# candy billboard the migrated bursts use (_burst_at / _drop_bonus_at) so
		# the volley reads as candy, not low-poly geometry.
		var b: Sprite3D = _make_candy_billboard(CANDY_BULLET_TEX[FireMode.CANDY], 0.8)
		b.position = pos + Vector3(0, 1.0, 0)
		# iter363: parent to popups_root, NOT bullets_root. The bullet _process
		# loop moves every bullets_root child downrange at BULLET_SPEED and
		# despawns it — which rocketed the salute away instantly (invisible).
		# popups_root is tween-only (same container _burst_at uses), so the
		# salute now actually rises straight up and is seen.
		popups_root.add_child(b)
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
	# winflow R3: prospectors ARE enemies the player defeats (HP, fire back,
	# death anim), so they now COUNT toward the outlaw quota — otherwise the
	# top-left "outlaws remaining" number reads lower than the enemies the
	# player can see on screen (device report: "3 visible, count said 1").
	# They consume quota slots like a regular outlaw, so obey the same cap.
	if _level_def != null and _level_def.outlaw_quota > 0 and _outlaws_spawned >= _level_def.outlaw_quota:
		return   # quota fully emitted — no more enemies of any kind
	var prosp := Node3D.new()
	var lane_x: float = _rng.randf_range(-OUTLAW_SPAWN_X_MAX, OUTLAW_SPAWN_X_MAX)
	prosp.position = Vector3(lane_x, 1.0, OBSTACLE_SPAWN_Z + 4.0)
	prosp.set_meta("hp", PROSPECTOR_HP)
	prosp.set_meta("fire_timer", _rng.randf() * OUTLAW_FIRE_INTERVAL)
	prosp.set_meta("is_outlaw", true)   # winflow R3: counts toward the quota
	_outlaws_spawned += 1
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
	# body_half_w = visible (opaque) half-width in world units — the sprites
	# have wide transparent margins, so this is much less than w/2. Pushers
	# press against THIS edge, not the invisible frame (iter 334).
	"wagon_covered": {"path": "res://assets/sprites/props/wagon_covered.png", "w": 3.3, "h": 2.2, "body_half_w": 1.16},
	"mining_cart":   {"path": "res://assets/sprites/props/mining_cart.png",   "w": 2.0, "h": 1.4, "body_half_w": 0.69},
	"barrel":        {"path": "res://assets/sprites/props/barrel.png",        "w": 1.2, "h": 1.6, "body_half_w": 0.53},
	# kimmy: the rock-candy cage wagon (back layer — wagon + rear crystal bars).
	# Frame is 320x380; back container drawn 280w @ y113. Tall, narrow body.
	"kimmy_cage_back": {"path": "res://assets/sprites/props/kimmy_cage_back.png", "w": 3.5, "h": 4.2, "body_half_w": 1.25},
}
const HERO_TEX: Dictionary = {
	"marshmallow_sheriff": "res://assets/sprites/props/hero_marshmallow_sheriff.png",
	"laughing_horse":      "res://assets/sprites/props/hero_laughing_horse.png",
	"scarecrow":           "res://assets/sprites/props/hero_scarecrow.png",
	"chocolate_outlaw":    "res://assets/sprites/props/hero_chocolate_outlaw.png",
	"sugar_doc":           "res://assets/sprites/props/hero_sugar_doc.png",
	"taffy_kid":           "res://assets/sprites/props/hero_taffy_kid.png",
	"kimmy_caged":         "res://assets/sprites/props/kimmy_caged.png",
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

	# HP label overhead — BIG number (iter 334, Evony-style). Wagons/barrels are
	# the player's key targets, so the HP reads at a glance like the math-gate
	# numbers: a large, heavily-outlined current-HP figure that draws on top of
	# everything (no_depth_test) so the wagon/pushers never occlude it.
	var hp_label := Label3D.new()
	hp_label.text = str(hp)
	hp_label.font_size = 110
	hp_label.outline_size = 18
	hp_label.modulate = Color(1.0, 0.96, 0.55, 1.0)
	hp_label.outline_modulate = Color(0.20, 0.05, 0.04, 1.0)
	hp_label.billboard = 1
	hp_label.no_depth_test = true
	hp_label.render_priority = 10
	hp_label.position = Vector3(0, c_data.h + 0.8, 0)
	captive.add_child(hp_label)
	captive.set_meta("hp_label", hp_label)

	# Trapped! label — sits above the big HP number.
	var trapped_label := Label3D.new()
	trapped_label.text = "TRAPPED!"
	trapped_label.font_size = 56
	trapped_label.outline_size = 10
	trapped_label.modulate = Color(1.0, 0.85, 0.30, 1.0)
	trapped_label.billboard = 1
	trapped_label.no_depth_test = true
	trapped_label.position = Vector3(0, c_data.h + 2.0, 0)
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
func _captive_take_damage(captive: Node3D, bullet_pos: Vector3, bullet_rainbow: bool = false) -> void:
	if captive.get_meta("released", false):
		return  # iter 164: already freed — ignore trailing bullets
	# kimmy: cage takes damage ONLY from rainbow-mode bullets.
	var is_kimmy: bool = captive.get_meta("is_kimmy", false)
	var base_dmg: int = maxi(_volley_dmg, KIMMY_CAGE_HIT_FLOOR) if is_kimmy else 1
	var dmg: int = kimmy_cage_damage(is_kimmy, bullet_rainbow, base_dmg)
	if dmg <= 0:
		if is_kimmy:
			_kimmy_rainbow_only_cue(bullet_pos)
		return
	var hp: int = captive.get_meta("hp", 0) - dmg
	captive.set_meta("hp", hp)
	var max_hp: int = captive.get_meta("max_hp", 60)
	# Update HP label
	var hp_label: Label3D = captive.get_meta("hp_label", null)
	if hp_label != null and is_instance_valid(hp_label):
		hp_label.text = str(maxi(hp, 0))
		# Pulse the number on each hit so the damage reads (Evony-ish punch).
		hp_label.scale = Vector3.ONE * 1.25
		hp_label.create_tween().tween_property(hp_label, "scale", Vector3.ONE, 0.12) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# Damage popup
	_spawn_popup_3d(bullet_pos + Vector3(0, 0.5, 0),
		"-%d" % dmg, Color(1.0, 0.55, 0.40, 1), 36)
	# Small flash modulate on container
	var container_sprite: Sprite3D = captive.get_meta("container_sprite", null)
	if container_sprite != null and is_instance_valid(container_sprite):
		container_sprite.modulate = Color(1.5, 1.5, 1.5, 1.0)
		var flash_tw: Tween = container_sprite.create_tween()
		flash_tw.tween_property(container_sprite, "modulate", Color.WHITE, 0.12)
	if hp <= 0:
		_release_captive_hero_pushed_aware(captive)

# kimmy: one-time "RAINBOW ONLY" hint when a non-rainbow bullet pings Kimmy's cage.
func _kimmy_rainbow_only_cue(pos: Vector3) -> void:
	if _kimmy_cue_shown:
		return
	_kimmy_cue_shown = true
	_spawn_popup_3d(pos + Vector3(0, 1.5, 0), "RAINBOW ONLY!", Color(0.7, 0.5, 1.0, 1), 56)

# kimmy: spawn the 3-layer rock-candy cage at the locked centre-lane placement.
# Layers (z back→front): kimmy_cage_back (wagon + rear crystals) → kimmy_caged
# (the plain caged stallion, the captive "hero") → kimmy_cage_front (front bars).
# _spawn_captive_hero builds the back container + the stallion + hp/labels; we
# bolt the FRONT bars on as an extra child rendered over everything.
func _spawn_kimmy_cage() -> void:
	_kimmy_cue_shown = false
	# Centre lane, a touch ahead of the posse (matches the pushed-wagon lane_z).
	_kimmy_captive = _spawn_captive_hero("kimmy_cage_back", "kimmy_caged", 0.0, -5.0, 2)
	if _kimmy_captive == null:
		return
	_kimmy_captive.set_meta("is_kimmy", true)
	# Override HP to the high cage value (the tier system only gives 60).
	_kimmy_captive.set_meta("hp", KIMMY_CAGE_HP)
	_kimmy_captive.set_meta("max_hp", KIMMY_CAGE_HP)
	var hp_label: Label3D = _kimmy_captive.get_meta("hp_label", null)
	if hp_label != null and is_instance_valid(hp_label):
		hp_label.text = str(KIMMY_CAGE_HP)
		hp_label.position.y += 0.4   # kimmy: raise the cage HP number up very slightly
	var trapped: Label3D = _kimmy_captive.get_meta("trapped_label", null)
	if trapped != null and is_instance_valid(trapped):
		trapped.text = "CAGED!"
		trapped.modulate = Color(0.80, 0.55, 1.0, 1.0)
	# Derive the back container's rendered geometry so the front bars line up
	# proportionally (locked tuner layout: back 280w@y113, stallion 183w@y119,
	# front 200w@y119 in a 320x380 frame → front ≈ 0.71× back width).
	var c_data: Dictionary = CONTAINER_TEX["kimmy_cage_back"]
	var back_h: float = float(c_data.h)              # back container world height
	var fbars := Sprite3D.new()
	var ftex: Texture2D = load("res://assets/sprites/props/kimmy_cage_front.png")
	fbars.texture = ftex
	fbars.billboard = 1
	fbars.shaded = false
	# 80% opacity so the caged stallion reads clearly THROUGH the bars. alpha_cut=0
	# (DISABLED) lets the modulate alpha actually blend (scissor would be binary).
	fbars.alpha_cut = 0
	fbars.modulate.a = 0.80
	fbars.render_priority = 5     # draw over the stallion + back container
	# Back container rendered width ≈ back_tex_w * (back_h / back_tex_h). Front
	# bars target ≈ 0.71× that. Size the front sprite to hit that world width.
	var back_tex: Texture2D = load(c_data.path)
	var back_render_w: float = float(back_tex.get_width()) * (back_h / float(back_tex.get_height()))
	var front_target_w: float = back_render_w * 0.66
	fbars.pixel_size = front_target_w / float(ftex.get_width())
	# Vertical: bars sit over the stallion (hero centre ≈ back_h*0.65), centred,
	# pushed forward in z so they read as "in front of" the caged stallion.
	fbars.position = Vector3(0.0, back_h * 0.64, 0.30)
	_kimmy_captive.add_child(fbars)
	_kimmy_captive.set_meta("front_bars", fbars)
	# kimmy: the caged stallion paces/rocks in her cell so she reads as alive and
	# agitated, not a static prop. Gentle looping local sway + a slight tilt.
	var caged_hs: Sprite3D = _kimmy_captive.get_meta("hero_sprite", null)
	if caged_hs is Sprite3D:
		var bx: float = caged_hs.position.x
		var sway := caged_hs.create_tween().set_loops()
		sway.tween_property(caged_hs, "position:x", bx + 0.14, 0.7) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		sway.parallel().tween_property(caged_hs, "rotation:z", deg_to_rad(-5.0), 0.7) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		sway.tween_property(caged_hs, "position:x", bx - 0.14, 0.7) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		sway.parallel().tween_property(caged_hs, "rotation:z", deg_to_rad(5.0), 0.7) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_kimmy_window_left = KIMMY_RESCUE_WINDOW
	_kimmy_spawn_countdown()
	# Halt the world scroll while she blocks the path. _update_pushed_wagons also
	# auto-sets this each frame (the cage is an is_captive node), but set it now
	# so the very first frame is already frozen.
	_set_cart_encounter(true)

# kimmy: the rescue-timer HUD readout — a big Rye-font countdown just BELOW the
# top-left taffy cutout ($UI/HeartsCutout, which ends at y≈571). Rainbow-strobed
# + pulsed each frame in _process while the cage is up; freed on resolve.
func _kimmy_spawn_countdown() -> void:
	var ui: Node = get_node_or_null("UI")
	if ui == null:
		return
	_kimmy_clear_countdown()
	var lbl := Label.new()
	lbl.name = "KimmyCountdown"
	lbl.add_theme_font_override("font", _RYE3D)
	lbl.add_theme_font_size_override("font_size", 96)
	lbl.add_theme_color_override("font_outline_color", Color(0.16, 0.05, 0.04, 1))
	lbl.add_theme_constant_override("outline_size", 12)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Align under the taffy cutout (offset_left 12 → right 588, bottom 571).
	lbl.offset_left = 12.0
	lbl.offset_top = 560.0
	lbl.offset_right = 588.0
	lbl.offset_bottom = 700.0
	lbl.pivot_offset = Vector2(288.0, 70.0)
	lbl.text = str(int(ceil(KIMMY_RESCUE_WINDOW)))
	ui.add_child(lbl)
	_kimmy_countdown = lbl

# kimmy: per-frame countdown tick — rainbow-cycle the colour + pulse the scale so
# it strobes urgently. Called from _process while _kimmy_captive is alive.
func _kimmy_update_countdown() -> void:
	if _kimmy_countdown == null or not is_instance_valid(_kimmy_countdown):
		return
	_kimmy_countdown.text = str(maxi(0, int(ceil(_kimmy_window_left))))
	var t: float = float(Time.get_ticks_msec()) * 0.001
	# Rainbow strobe: cycle hue fast; pulse brightness + scale on a faster beat.
	_kimmy_countdown.modulate = Color.from_hsv(fmod(t * 1.6, 1.0), 0.85, 1.0)
	var pulse: float = 1.0 + 0.12 * sin(t * 12.0)
	_kimmy_countdown.scale = Vector2(pulse, pulse)

# kimmy: remove the countdown HUD (on rescue, haul-away, or respawn).
func _kimmy_clear_countdown() -> void:
	if _kimmy_countdown != null and is_instance_valid(_kimmy_countdown):
		_kimmy_countdown.queue_free()
	_kimmy_countdown = null

# kimmy: rescue window expired — the pushers haul her off. Miss, but NO soft-lock:
# the cage slides off-left, frees, and the world scroll resumes.
func _kimmy_haul_away(captive: Node3D) -> void:
	var ui: Node = get_node_or_null("UI")
	if ui != null:
		FlourishBanner.spawn(ui, "SHE GOT AWAY")
	if is_instance_valid(captive):
		var t := captive.create_tween()
		t.tween_property(captive, "position:x", captive.position.x - 14.0, 1.0)
		t.tween_callback(captive.queue_free)
	_kimmy_resume_scroll()

# kimmy: drop the scroll-halt and let the world advance again.
func _kimmy_resume_scroll() -> void:
	_set_cart_encounter(false)

const KIMMY_BOMB_TEX := preload("res://assets/sprites/props/kimmy_bomb.png")
const KIMMY_RAINBOW_TEX := preload("res://assets/sprites/props/kimmy_rainbow.png")
var _kimmy_glow_tex: GradientTexture2D = null   # cached soft radial glow (blooms + embers)

# A soft white radial glow that fades to transparent — the additive building block
# for the Skittles Bloom (bloom core + each candy ember) and the 2D overlay glow.
func _kimmy_soft_glow() -> GradientTexture2D:
	if _kimmy_glow_tex != null:
		return _kimmy_glow_tex
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.35, Color(1, 1, 1, 0.55))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = 128
	t.height = 128
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	_kimmy_glow_tex = t
	return t

# kimmy: the sugar rush. The cage is gone, a big 2D Rainbow Kimmy overlay takes the
# screen (bounce in -> crescendo glow -> launch off the top), and gumball bombs rock
# down onto every on-screen outlaw + destructible obstacle, each detonating in a
# Skittles Bloom. Posse + the cage are never targeted.
func _rush_kimmy(freed_captive: Node3D) -> void:
	if is_instance_valid(freed_captive):
		freed_captive.queue_free()
	_kimmy_clear_countdown()
	if get_node_or_null("/root/AudioBus") and AudioBus.has_method("play_sfx"):
		AudioBus.play_sfx("kimmy_riff")
	var ui: Node = get_node_or_null("UI")
	if ui != null:
		FlourishBanner.spawn(ui, "RAINBOW KIMMY")
	_play_kimmy_overlay()
	var targets: Array = []
	for o in outlaws_root.get_children():
		if o is Node3D and kimmy_clears_node(_node_meta_flags(o)):
			targets.append(o)
	for ob in obstacles_root.get_children():
		if ob is Node3D and kimmy_clears_node(_node_meta_flags(ob)):
			targets.append(ob)
	# Candy-bomb cascade, staggered so it reads as a wave rolling across the screen.
	var i: int = 0
	for t in targets:
		get_tree().create_timer(1.2 + float(i) * 0.06).timeout.connect(_kimmy_drop_bomb.bind(t))
		i += 1
	await get_tree().create_timer(3.4).timeout
	_kimmy_resume_scroll()

# kimmy: the 2D cinematic. Rainbow Kimmy bounces up from the bottom, pulse/glows with
# the riff crescendo, then launches up and off the top. CanvasLayer overlay only.
func _play_kimmy_overlay() -> void:
	var ui: Node = get_node_or_null("UI")
	if ui == null:
		return
	var screen := Vector2(1080.0, 1920.0)
	var root := Control.new()
	root.name = "KimmyOverlay"
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.add_child(root)
	# Additive glow behind her.
	var glow := TextureRect.new()
	glow.texture = _kimmy_soft_glow()
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow.size = Vector2(1200.0, 1200.0)
	glow.position = Vector2(screen.x * 0.5 - 600.0, screen.y * 0.66 - 600.0)
	glow.modulate = Color(1.0, 0.72, 0.32, 0.0)
	var gmat := CanvasItemMaterial.new()
	gmat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	glow.material = gmat
	root.add_child(glow)
	# Kimmy.
	var kim := TextureRect.new()
	kim.texture = KIMMY_RAINBOW_TEX
	kim.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	kim.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	kim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var kw := 760.0
	var kh := kw * float(KIMMY_RAINBOW_TEX.get_height()) / float(KIMMY_RAINBOW_TEX.get_width())
	kim.size = Vector2(kw, kh)
	kim.pivot_offset = Vector2(kw * 0.5, kh * 0.5)
	var cx := screen.x * 0.5 - kw * 0.5
	var rest_y := screen.y - kh * 0.92      # planted near the bottom, mostly on-screen
	kim.position = Vector2(cx, screen.y + kh)   # start fully below
	root.add_child(kim)
	# Position track: rise (small overshoot) -> settle -> hold -> launch off top -> free.
	var pos := kim.create_tween()
	pos.tween_property(kim, "position:y", rest_y - 36.0, 0.34).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	pos.tween_property(kim, "position:y", rest_y, 0.18).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	pos.tween_interval(1.7)
	pos.tween_property(kim, "position:y", -kh, 0.55).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	pos.tween_callback(root.queue_free)
	# Scale pulse track: pulses START small and GROW toward the crescendo peak.
	var scl := kim.create_tween()
	scl.tween_interval(0.5)
	for amp in [1.04, 1.07, 1.10, 1.15]:
		scl.tween_property(kim, "scale", Vector2(amp, amp), 0.20).set_trans(Tween.TRANS_SINE)
		scl.tween_property(kim, "scale", Vector2.ONE, 0.20).set_trans(Tween.TRANS_SINE)
	# Glow track: fade in, swell with the crescendo, then fade as she launches.
	var gt := glow.create_tween()
	gt.tween_property(glow, "modulate:a", 0.55, 0.5)
	gt.tween_property(glow, "modulate:a", 1.0, 1.6)
	gt.tween_property(glow, "modulate:a", 0.0, 0.5)

# kimmy: a gumball bomb rocks down onto `target` and detonates in a Skittles Bloom.
func _kimmy_drop_bomb(target: Node3D) -> void:
	if not is_instance_valid(target):
		return
	var land: Vector3 = target.position + Vector3(0, 0.6, 0)
	var bomb := Sprite3D.new()
	bomb.texture = KIMMY_BOMB_TEX
	bomb.shaded = false
	bomb.no_depth_test = true
	bomb.render_priority = 6
	bomb.pixel_size = 0.010
	bomb.position = land + Vector3(0, 9.0, 0)
	bomb.rotation.z = deg_to_rad(-12.0)
	popups_root.add_child(bomb)
	var fall := bomb.create_tween()
	fall.tween_property(bomb, "position", land, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	fall.tween_callback(_kimmy_bomb_land.bind(target, land, bomb))
	# Rock while falling (independent loop; auto-stops when the bomb frees).
	var rock := bomb.create_tween().set_loops()
	rock.tween_property(bomb, "rotation:z", deg_to_rad(12.0), 0.14).set_trans(Tween.TRANS_SINE)
	rock.tween_property(bomb, "rotation:z", deg_to_rad(-12.0), 0.14).set_trans(Tween.TRANS_SINE)

func _kimmy_bomb_land(target: Node3D, land: Vector3, bomb: Node3D) -> void:
	_kimmy_skittles_bloom(land)
	if is_instance_valid(target):
		_add_bounty(50)
		if target.get_meta("is_outlaw", false):
			_outlaw_left_field(target)   # decrement the quota via the existing path
		target.queue_free()
	if is_instance_valid(bomb):
		bomb.queue_free()

# Collect the flags kimmy_clears_node() checks from a live node's meta.
func _node_meta_flags(n: Node) -> Dictionary:
	return {
		"is_outlaw": n.get_meta("is_outlaw", false),
		"is_bull": n.get_meta("is_bull", false),
		"is_captive": n.get_meta("is_captive", false),
		"is_kimmy": n.get_meta("is_kimmy", false),
		"dying": n.get_meta("dying", false),
	}

# kimmy: the "Skittles Bloom" explosion — additive, FROSTBITE/Prism-caliber. A warm
# bloom core flash + an expanding rainbow shock ring + a burst of soft glowing candy
# embers that drift out and fade. All additive sprites/particles — no shaders.
func _kimmy_skittles_bloom(pos: Vector3) -> void:
	_kimmy_bloom_flash(pos)
	_spawn_rainbow_shock(pos)
	var p := CPUParticles3D.new()
	p.position = pos
	p.amount = 40
	p.lifetime = 0.9
	p.one_shot = true
	p.explosiveness = 0.92
	p.spread = 180.0
	p.direction = Vector3(0, 1, 0)
	p.initial_velocity_min = 2.5
	p.initial_velocity_max = 7.0
	p.gravity = Vector3(0, -5.0, 0)
	p.damping_min = 1.0
	p.damping_max = 2.5
	p.scale_amount_min = 0.22
	p.scale_amount_max = 0.55
	# Per-ember random candy colour (color_initial_ramp), faded out over life (color_ramp).
	var candy := Gradient.new()
	candy.offsets = PackedFloat32Array([0.0, 0.25, 0.5, 0.75, 1.0])
	candy.colors = PackedColorArray([Color(1,0.25,0.25), Color(1,0.82,0.25),
		Color(0.35,1,0.42), Color(0.3,0.65,1), Color(0.78,0.38,1)])
	p.color_initial_ramp = candy
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 1))
	fade.set_color(1, Color(1, 1, 1, 0))
	p.color_ramp = fade
	# Each ember draws a soft additive glow quad (a meshless CPUParticles3D is invisible).
	var quad := QuadMesh.new()
	quad.size = Vector2(0.5, 0.5)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.albedo_texture = _kimmy_soft_glow()
	mat.vertex_color_use_as_albedo = true
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	quad.material = mat
	p.mesh = quad
	popups_root.add_child(p)
	p.emitting = true
	get_tree().create_timer(1.6).timeout.connect(p.queue_free)

# kimmy: warm additive bloom core that pops + fades — the bright heart of the bloom.
func _kimmy_bloom_flash(pos: Vector3) -> void:
	var s := Sprite3D.new()
	s.texture = _kimmy_soft_glow()
	s.shaded = false
	s.no_depth_test = true
	s.render_priority = 7
	s.modulate = Color(1.0, 0.86, 0.5, 1.0)
	s.pixel_size = 0.012
	s.position = pos
	var mat := StandardMaterial3D.new()
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_texture = _kimmy_soft_glow()
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	s.material_override = mat
	popups_root.add_child(s)
	var t := s.create_tween().set_parallel(true)
	t.tween_property(s, "pixel_size", 0.032, 0.30).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(s, "modulate:a", 0.0, 0.30)
	t.chain().tween_callback(s.queue_free)

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
const PUSHER_HEIGHT_WORLD: float = 0.85  # iter 334: 1.2 → 0.85 so a bigger mob fits on screen
# iter 334: the wagon rocks on its wheels while being shoved (was rigid/wooden).
# Applied as a small rotation.z on the captive node — its billboarded children
# swing in an arc about the ground pivot, reading as a cart rocking.
const WAGON_ROCK_DEG: float = 4.5
const WAGON_ROCK_FREQ: float = 3.2
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
	# Front rank presses against the wagon's VISIBLE (opaque) left face — the
	# body_half_w accounts for the sprite's transparent margins, so the pushers
	# actually touch the cart instead of standing off in empty space. A small
	# overlap (−0.15) reads as "pressing into it". Tighter ranks (0.42) + columns
	# (0.40) pack the smaller pushers shoulder-to-shoulder (iter 334).
	var c_entry: Dictionary = CONTAINER_TEX.get(container_slug, CONTAINER_TEX["wagon_covered"])
	var body_half_w: float = float(c_entry.get("body_half_w", float(c_entry.w) * 0.5))
	for i in range(n_pushers):
		var col: int = i % cols
		var row: int = i / cols
		var ox: float = -(body_half_w - 0.15) - float(row) * 0.42
		var oz: float = (float(col) - float(cols - 1) * 0.5) * 0.40
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
		# iter 334: rock the wagon on its wheels while it's shoved (was rigid).
		# Tilt scales with push intensity so a mobbed wagon lurches harder. The
		# rotation pivots at the ground origin, so the billboarded body swings
		# in an arc — reads as rocking, not sliding.
		var rock_t: float = float(Time.get_ticks_msec()) * 0.001 * WAGON_ROCK_FREQ \
			+ float(captive.get_instance_id() % 360)
		var rock_intensity: float = clampf(push_speed / MAX_PUSH_SPEED, 0.25, 1.0)
		captive.rotation.z = sin(rock_t) * deg_to_rad(WAGON_ROCK_DEG) * rock_intensity
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

func outlaws_remaining() -> int:
	return _outlaws_remaining

func _quota_driven() -> bool:
	return _level_def != null and _level_def.outlaw_quota > 0

# Single chokepoint: an outlaw has LEFT THE FIELD (defeated or scrolled past).
# The `counted` meta guard makes a double-call safe.
func _outlaw_left_field(outlaw: Node) -> void:
	if _level_def == null or _level_def.outlaw_quota <= 0:
		return
	if outlaw == null or not outlaw.get_meta("is_outlaw", false):
		return   # prospectors/pushers/captives don't count toward the outlaw quota
	if outlaw != null and outlaw.get_meta("counted", false):
		return
	if outlaw != null:
		outlaw.set_meta("counted", true)
	_outlaws_remaining = maxi(0, _outlaws_remaining - 1)
	DebugLog.add("outlaw left field -> remaining=%d" % _outlaws_remaining)
	_set_outlaws_label(_outlaws_remaining)   # defined in the next task; guard if missing
	if _outlaws_remaining == 0:
		_trigger_quota_boss()

# Set the taffy's outlaws-remaining number with a small bump on change.
func _set_outlaws_label(n: int) -> void:
	if _hud_outlaws == null:
		return
	_hud_outlaws.text = str(n)
	_hud_outlaws.pivot_offset = _hud_outlaws.size * 0.5
	var t := _hud_outlaws.create_tween()
	t.tween_property(_hud_outlaws, "scale", Vector2(1.25, 1.25), 0.08)
	t.tween_property(_hud_outlaws, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_BACK)

func _trigger_quota_boss() -> void:
	if _pete_spawned or _test_range_mode:
		return
	_pete_spawned = true
	if _boss_kind() == "rustler":
		_spawn_candy_rustler()
	elif _boss_kind() == "raisin":
		_spawn_raisin_kidd()
	else:
		_spawn_pete()
	for _g in gates_root.get_children():
		_g.queue_free()
	_level_state = LevelState.BOSS
	DebugLog.add("quota cleared -> boss (kind=%s)" % _boss_kind())

# Farm outlaw contact/melee/lash drain — pulls one posse member (special
# followers soak first, like Pete/Rustler melee). pos is the attacker's
# position for picking the nearest special follower; sfx is played on hit.
func _outlaw_drain_posse(pos: Vector3, sfx: String = "") -> void:
	if sfx != "" and get_node_or_null("/root/AudioBus") and AudioBus.has_method("play_sfx"):
		AudioBus.play_sfx(sfx)
	var sf: Dictionary = _nearest_special_follower(pos, 99.0)
	if not sf.is_empty():
		_damage_special_follower(sf, 1)
	else:
		_posse_count_3d = maxi(0, _posse_count_3d - 1)
		_sync_followers_to_count(_posse_count_3d)
		_refresh_hud()
	if get_node_or_null("/root/AudioBus") and AudioBus.has_method("play_sfx"):
		AudioBus.play_sfx("posse_hurt")

# Pick the kind to spawn. Farm levels draw from the 4-kind roster; every
# other level keeps the original "vagrant". (Spec: simplest is a terrain check.)
func _pick_outlaw_kind() -> String:
	if _level_def == null:
		return "vagrant"
	var roster: Array
	match _level_def.terrain:
		"farm": roster = FARM_OUTLAW_WEIGHTS
		"badlands": roster = BADLANDS_OUTLAW_WEIGHTS
		"canyon": roster = CANYON_OUTLAW_WEIGHTS
		_: return "vagrant"
	var total: int = 0
	for entry in roster:
		total += entry[1]
	var roll: int = _rng.randi_range(0, total - 1)
	for entry in roster:
		roll -= entry[1]
		if roll < 0:
			return entry[0]
	return roster[0][0]

func _spawn_outlaw(kind: String = "") -> void:
	if _level_def != null and _level_def.outlaw_quota > 0 and _outlaws_spawned >= _level_def.outlaw_quota:
		return   # quota fully emitted — no more outlaws
	if kind == "":
		kind = _pick_outlaw_kind()
	var has_kind_stats: bool = OUTLAW_KINDS.has(kind)
	var max_hp: int = OUTLAW_KINDS[kind]["hp"] if has_kind_stats else OUTLAW_HP
	# Iter 116: re-enable video billboard, but this time via SHARED top-
	# level SubViewports (see _make_video_billboard) — iter 114 confirmed
	# that nested-SubViewport video billboards don't render on Android.
	var outlaw := Node3D.new()
	var lane_x: float = _rng.randf_range(-OUTLAW_SPAWN_X_MAX, OUTLAW_SPAWN_X_MAX)
	outlaw.position = Vector3(lane_x, 1.0, OBSTACLE_SPAWN_Z + 4.0)
	outlaw.set_meta("kind", kind)
	outlaw.set_meta("hp", max_hp)
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
	outlaw.set_meta("is_outlaw", true)
	# triffid is ROOTED: stash a per-spawn lash cooldown phase so a cluster
	# doesn't all lash on the same frame.
	if kind == "triffid":
		outlaw.set_meta("lash_timer", _rng.randf() * TRIFFID_LASH_COOLDOWN)
	# gummi BOUNCY: random hop phase so the swarm hops out of sync.
	if kind == "gummi_bear":
		outlaw.set_meta("hop_phase", _rng.randf() * GUMMI_HOP_PERIOD)
	_outlaws_spawned += 1
	var billboard: Node3D
	if FARM_OUTLAW_VIDEOS.has(kind):
		billboard = _make_video_billboard(load(FARM_OUTLAW_VIDEOS[kind]), OUTLAW_KINDS[kind]["height"])
	elif MONK_OUTLAW_VIDEOS.has(kind):
		billboard = _make_video_billboard(load(MONK_OUTLAW_VIDEOS[kind]), OUTLAW_KINDS[kind]["height"])
	elif BIRD_OUTLAW_VIDEOS.has(kind):
		billboard = _make_video_billboard(load(BIRD_OUTLAW_VIDEOS[kind]), OUTLAW_KINDS[kind]["height"])
	else:
		billboard = _make_video_billboard(VAGRANT_IDLE_STREAM, 2.5)
	outlaw.add_child(billboard)
	# Stash the Sprite3D ref so death-anim swap can replace its texture
	# without searching the tree.
	if billboard.get_child_count() > 0:
		outlaw.set_meta("sprite_3d", billboard.get_child(0))
	# Iter 151: HP bar above the outlaw (hidden until first hit).
	_attach_outlaw_hp_bar(outlaw, max_hp)
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
	# Iter 334: obstacle sprites (were CSG placeholders). Barrel = wooden keg
	# (rigid, tiny bob); bull = wide beast (no sway, slight breathing bob).
	"barrel":          {"path": "res://assets/sprites/props/barrel.png",          "w": 1.2, "h": 1.6, "sway_amp": 0.01, "bob_amp": 0.012},
	"bull":            {"path": "res://assets/sprites/props/bull.png",            "w": 2.6, "h": 1.42, "sway_amp": 0.0,  "bob_amp": 0.016},
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
	# Keep every follower on the current anim group EVERY frame, not just on a
	# group change — the transition-only version left any follower that got out
	# of sync (spawn-timing race / stale viewport texture) stuck on the wrong
	# clip forever (some posse idle while the rest ran). Self-healing + cheap
	# (guarded compare over a handful of sprites; get_texture() is the cached
	# ViewportTexture).
	_posse_anim_group = group
	for f in _followers:
		if is_instance_valid(f):
			var tex: Texture2D = _posse_pool_texture(f.get_meta("pool_slot", 0))
			if tex != null and f.texture != tex:
				f.texture = tex

# Iter 76: outlaw fires a red bullet aimed at the cowboy.
func _outlaw_fire(outlaw: Node3D) -> void:
	if randf() < 0.25 and get_node_or_null("/root/AudioBus") and AudioBus.has_method("play_sfx"): AudioBus.play_sfx("outlaw_fire")
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

# candy_corn KITER triple-volley: 3 quick shots spaced CANDY_CORN_BURST_GAP
# apart. Each shot is a normal _outlaw_fire from the (still-valid) outlaw, so
# the burst re-aims at the cowboy mid-volley. Plays its own SFX once.
func _candy_corn_volley(outlaw: Node3D) -> void:
	if get_node_or_null("/root/AudioBus") and AudioBus.has_method("play_sfx"):
		AudioBus.play_sfx("sfx_candy_corn")
	_outlaw_fire(outlaw)
	for i in range(1, CANDY_CORN_BURST):
		var t := get_tree().create_timer(CANDY_CORN_BURST_GAP * float(i))
		t.timeout.connect(func ():
			if is_instance_valid(outlaw) and not outlaw.get_meta("dying", false):
				_outlaw_fire(outlaw))

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
	# iter408: clamp delta so a frame-rate dip can't balloon per-frame motion. Without
	# this, a low-FPS frame moves bullets 50+ units in one step — they tunnel past
	# targets and despawn the same frame (the "bullets=0 / can't hit Pete" symptom).
	# Below ~12 FPS the game just runs in slow-motion instead of breaking.
	delta = minf(delta, 1.0 / 12.0)
	if not _process_first_tick_logged:
		_process_first_tick_logged = true
		DebugLog.add("_process first tick — game loop is running, state=%d" % _level_state)
	# Iter 343: keep the Quake bar's ammo/posse live without hunting every mutation.
	if _quake_bar != null:
		if _gun_state != null and _gun_state.ammo() != _last_ammo_shown:
			_refresh_quake_bar()
		if _boss_fill != null and _level_state == LevelState.PLAYING:
			_boss_fill.size.x = BOSS_TRACK_W * clampf(_level_elapsed / PETE_SPAWN_DELAY, 0.0, 1.0)
	# Swap the cowboy + crowd video clips to match the level state.
	_update_cowboy_anim()
	# Iter 179: animate the bonus-crate electric auras.
	_update_bonus_auras(delta)
	_update_dynamic_camera(delta)
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
	# iter417: wind weather nudges the cowboy's target sideways (player can fight
	# it by dragging, which resets _target_x to the finger position).
	# iter434: ice-slip — on a frozen puddle the cowboy keeps his entry momentum
	# with NO steering until he slides off the ice.
	var _on_ice: bool = _over_ice(cowboy_3d.position.x, cowboy_3d.position.z)
	if _on_ice and not _cowboy_on_ice:
		_cowboy_on_ice = true
		_ice_slip_vx = cowboy_3d.position.x - _prev_cowboy_x
		_cowboy_ice_cube = _spawn_ice_cube(cowboy_3d)
	elif not _on_ice and _cowboy_on_ice:
		_cowboy_on_ice = false
		_target_x = cowboy_3d.position.x
		if _cowboy_ice_cube != null and is_instance_valid(_cowboy_ice_cube):
			_cowboy_ice_cube.queue_free()
		_cowboy_ice_cube = null
	_prev_cowboy_x = cowboy_3d.position.x
	if _weather_cowboy_drift != 0.0 and not _cowboy_on_ice:
		_target_x = clampf(_target_x + _weather_cowboy_drift * delta,
			-COWBOY_X_BOUND, COWBOY_X_BOUND)
	if _cowboy_on_ice:
		cowboy_3d.position.x = clampf(cowboy_3d.position.x + _ice_slip_vx, -COWBOY_X_BOUND, COWBOY_X_BOUND)
	else:
		cowboy_3d.position.x = lerpf(cowboy_3d.position.x, _target_x,
			clampf(COWBOY_LERP_SPEED * _weather_steering_mult * delta, 0.0, 1.0))
	# Iter 72: followers track the leader's x with formation-offset lag.
	# Iter 85: y-bob animation overlays on top of the base 0.45 anchor.
	_bob_time += delta
	cowboy_3d.position.y = 0.45 + sin(_bob_time * BOB_FREQUENCY) * BOB_AMPLITUDE
	_update_posse_crowd(delta)   # iter401: posse mob follows + reframes
	_check_authored_holes(delta)
	_check_cliff_fall(delta)
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
	# kimmy: resolve the cage rescue each frame -- crack (rainbow fire broke the
	# cage) -> rush; time out (pushers haul her off) -> miss + resume scroll.
	if is_instance_valid(_kimmy_captive):
		_kimmy_window_left -= delta
		_kimmy_update_countdown()
		var k_hp: int = int(_kimmy_captive.get_meta("hp", 0))
		match kimmy_rescue_outcome(k_hp, _kimmy_window_left):
			"cracked":
				var freed := _kimmy_captive
				_kimmy_captive = null
				_kimmy_clear_countdown()
				_rush_kimmy(freed)
			"timed_out":
				var lost := _kimmy_captive
				_kimmy_captive = null
				_kimmy_clear_countdown()
				_kimmy_haul_away(lost)
			_:
				pass
	# Iter 118: world motion delta — 0 during BOSS so obstacles/gates/
	# outlaws/scenery freeze in place during the duel. Cowboy steering +
	# bullets + Pete continue to update on the real delta.
	# SP2 slice2: the director eases the scroll speed (reactive to enemy count)
	# + holds the world (factor -> 0) during approach zones while outlaws advance.
	if _director != null:
		_director.update(delta, _live_enemy_count())
	var _sf: float = _director.speed_factor() if _director != null else 1.0
	if _speed_label != null:
		_speed_label.text = "spd %.2f%s" % [_sf, "  HELD" if (_director != null and _director.world_held()) else ""]
	var motion_delta: float = (delta * _sf) if (_level_state == LevelState.PLAYING and not _cart_encounter) else 0.0
	# SP2 slice3b-fix: anchor the TERRAIN scroll to the same variable speed as
	# the props/gates (was a fixed 0.1667/s, so the ground slid out of sync when
	# the director sped up / slowed / halted). scroll_speed in UV-V/s = base × factor.
	if terrain_3d_node != null and "scroll_speed" in terrain_3d_node:
		var _scroll_fac: float = _sf if (_level_state == LevelState.PLAYING and not _cart_encounter) else 0.0
		terrain_3d_node.scroll_speed = (OBSTACLE_SPEED / 15.0) * _scroll_fac
	# SP2: advance the data timeline by the scrolled distance + dispatch crossings.
	if _level_player != null:
		_level_distance += OBSTACLE_SPEED * motion_delta
		for ev in _level_player.advance(_level_distance):
			_dispatch_level_event(ev)
	# Spawn obstacles periodically (PLAYING only).
	if _level_state != LevelState.PLAYING:
		_spawn_timer = OBSTACLE_SPAWN_INTERVAL  # reset so they don't pile up
	_spawn_timer -= delta
	if _level_state == LevelState.PLAYING and _spawn_timer <= 0.0:
		_spawn_timer = OBSTACLE_SPAWN_INTERVAL
		_spawn_obstacle()
	# iter411: periodic chicken coop set-piece.
	if _level_state == LevelState.PLAYING:
		_coop_spawn_timer -= delta
		if _coop_spawn_timer <= 0.0:
			_coop_spawn_timer = COOP_SPAWN_INTERVAL
			_spawn_chicken_coop()
	# Move all obstacles toward camera (z increases since camera is at z>0).
	# Iter 334: obstacles are breathing sprites now; the tumbleweed's roll is
	# the shader UV-spin (set in _spawn_obstacle), so no per-frame node spin
	# is needed here.
	for child in obstacles_root.get_children():
		if child is Node3D:
			if child.get_meta("is_bull", false):
				_update_bull(child, motion_delta, delta)
				continue
			child.position.z += OBSTACLE_SPEED * motion_delta
			if child.position.z > OBSTACLE_DESPAWN_Z:
				child.queue_free()
	# SP2 slice3: scroll holes; drop posse followers + outlaws that wander over one.
	for hole in holes_root.get_children():
		if not (hole is Node3D):
			continue
		hole.position.z += OBSTACLE_SPEED * motion_delta
		if hole.position.z > OBSTACLE_DESPAWN_Z + 3.0:
			hole.queue_free()
			continue
		var hx: float = hole.get_meta("x_half", 1.2)
		var hz: float = hole.get_meta("z_half", 1.6)
		var hfill: String = hole.get_meta("pit_fill", "fudge")
		for f in _followers.duplicate():
			if is_instance_valid(f) and not f.get_meta("falling", false) \
			and _in_box(f.position.x, f.position.z, hole.position.x, hole.position.z, hx, hz):
				_followers.erase(f)
				_posse_count_3d = maxi(0, _posse_count_3d - 1)
				_fall_entity(f)
				_spawn_pit_splash(f.position, hfill)
				_refresh_hud()
				if _posse_count_3d <= 0:
					_show_fail()
		for o in outlaws_root.get_children():
			if is_instance_valid(o) and not o.get_meta("falling", false) and not o.get_meta("is_captive", false) \
			and not o.get_meta("dying", false) and _in_box(o.position.x, o.position.z, hole.position.x, hole.position.z, hx, hz):
				_outlaw_left_field(o)
				_fall_entity(o)
				_spawn_pit_splash(o.position, hfill)
			# iter434: the posse is a MultiMesh CROWD now (_followers is empty), so the loop
			# above never dropped posse members into these event-spawned ditches (only the
			# const _HOLES dropped the crowd) — why strafing into some ditches dropped no one.
			if _level_state == LevelState.PLAYING and _posse_count_3d > 1 and cowboy_3d != null \
			and absf(hole.position.z - cowboy_3d.position.z) < hz + 0.5:
				var cl: float = cowboy_3d.position.x - COWBOY_X_BOUND
				var cr: float = cowboy_3d.position.x + COWBOY_X_BOUND
				var ov: float = minf(cr, hole.position.x + hx) - maxf(cl, hole.position.x - hx)
				if ov > 0.0:
					var fr: float = clampf(ov / (2.0 * COWBOY_X_BOUND), 0.0, 1.0)
					var already: int = int(hole.get_meta("crowd_dropped", 0))
					var present: int = _posse_count_3d + already
					var target: int = mini(present - 1, int(floor(fr * float(present))))
					var dn: int = clampi(target - already, 0, _posse_count_3d - 1)
					if dn > 0:
						hole.set_meta("crowd_dropped", already + dn)
						_posse_count_3d = maxi(0, _posse_count_3d - dn)
						_sync_followers_to_count(_posse_count_3d)
						_spawn_pit_splash(Vector3(cowboy_3d.position.x, 0.0, hole.position.z), hfill)
						_refresh_hud()
						if get_node_or_null("/root/AudioBus") and AudioBus.has_method("play_sfx"):
							AudioBus.play_sfx("hole_fall")
						if _posse_count_3d <= 0:
							_show_fail()
				else:
					hole.set_meta("crowd_dropped", 0)
	# Iter 75: gates scroll like obstacles + check trigger when crossing z plane
	_gate_spawn_timer -= delta
	if _gate_spawn_timer <= 0.0 and _level_state == LevelState.PLAYING:
		_gate_spawn_timer = GATE_SPAWN_INTERVAL
		_spawn_gate()   # iter414b: PLAYING only — no new gates to occlude the boss
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
	if _level_state == LevelState.PLAYING and not _test_range_mode and _level_elapsed > OUTLAW_GRACE:
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
		if outlaw.get_meta("falling", false):
			continue  # SP2 slice3: being dropped into a pit; tween owns it
		# Iter 120: dying outlaws skip movement + fire + collision and
		# just tick their death timer. queue_free when the death.ogv
		# animation has played out.
		if outlaw.get_meta("dying", false):
			# Iter 340: scroll the dying outlaw WITH the terrain (same world
			# velocity as props/scenery) so its death-anim stays stuck to its
			# spot on the ground instead of drifting backward relative to it.
			outlaw.position.z += OBSTACLE_SPEED * motion_delta
			var dt: float = outlaw.get_meta("death_timer", 0.0) - delta
			outlaw.set_meta("death_timer", dt)
			if dt <= 0.0:
				outlaw.queue_free()
			continue
		# Farm kind: per-kind speed / movement style. "vagrant" + any
		# unknown kind keep the original behavior below.
		var _kind: String = outlaw.get_meta("kind", "vagrant")
		var _rooted: bool = _kind == "triffid"
		# Iter 120: slow z-scroll once outlaw is close to the cowboy so
		# they cluster around the posse instead of marching past at
		# constant speed. Beyond cowboy_z - 2.0 (= still in front), full
		# OUTLAW_SPEED. Within 2.0 of cowboy_z, slow to 20% speed.
		var z_speed: float = OUTLAW_SPEED
		if _kind == "fried_dough":
			z_speed = OUTLAW_SPEED * FRIED_DOUGH_SPEED_MUL  # RUSHER: keep closing fast
		elif _kind == "gummi_bear":
			z_speed = OUTLAW_SPEED * GUMMI_SPEED_MUL
			if outlaw.position.z > cowboy_3d.position.z - 2.0:
				z_speed *= 0.20
		elif _kind == "candy_corn":
			# KITER: hold ~6 units in front of the cowboy, stop closing.
			if outlaw.position.z >= cowboy_3d.position.z - CANDY_CORN_HOLD_Z:
				z_speed = 0.0
		elif outlaw.position.z > cowboy_3d.position.z - 2.0:
			z_speed = OUTLAW_SPEED * 0.20
		# triffid ROOTED: never advances on the posse — it scrolls in with
		# the world (toward the player as the world moves past).
		if _rooted:
			z_speed = 0.0
			outlaw.position.z += OBSTACLE_SPEED * motion_delta
		# Iter 173: the pushed cart + its pushers freeze in z — during a
		# cart encounter the whole world's forward scroll is paused anyway
		# (terrain + props), so the cart stays in lockstep with the ground.
		# kimmy: her cage is a STATIC blocker (not pushed) — freeze it in z too,
		# so it sits still in the halted world instead of creeping like an outlaw.
		if outlaw.get_meta("is_pushed", false) or outlaw.get_meta("is_pusher", false) \
				or outlaw.get_meta("is_kimmy", false):
			z_speed = 0.0
		# Iter 136: real delta (not motion_delta) so outlaws keep advancing
		# on the posse even while the world scroll is paused / during BOSS.
		outlaw.position.z += z_speed * delta
		# Iter 120: x-tracking with PER-OUTLAW offset (set at spawn).
		# Each outlaw heads for cowboy.x + their personal offset so the
		# group reads as a crowd, not a column. Clamped to road bounds.
		var ox: float = outlaw.get_meta("track_offset_x", 0.0)
		# SP2 slice3: include the path bend at the outlaw's depth so distant outlaws
		# arrive along the curving road (the offset fades to ~0 as they near the player).
		var curve_ox: float = _path_offset_at_z(outlaw.position.z, _path_lateral(_level_distance))
		var target_x: float = clampf(cowboy_3d.position.x + ox + curve_ox,
			-COWBOY_X_BOUND - PATH_AMP, COWBOY_X_BOUND + PATH_AMP)
		# Iter 164: the set-piece doesn't x-track the posse — the wagon
		# "tracking the posse" was this lerp. Pushers move it instead.
		# iter434: ice-slip — an outlaw on a frozen puddle locks its x-tracking
		# (slides straight) + gets a floating ice cube until it clears the ice.
		if _over_ice(outlaw.position.x, outlaw.position.z):
			target_x = outlaw.position.x
			if not outlaw.has_meta("ice_cube"):
				outlaw.set_meta("ice_cube", _spawn_ice_cube(outlaw))
		elif outlaw.has_meta("ice_cube"):
			var _ic = outlaw.get_meta("ice_cube")
			if is_instance_valid(_ic):
				_ic.queue_free()
			outlaw.remove_meta("ice_cube")
		if _rooted or outlaw.get_meta("is_pushed", false) or outlaw.get_meta("is_pusher", false) \
				or outlaw.get_meta("is_kimmy", false):
			target_x = outlaw.position.x   # triffid is rooted; set-pieces own their x
		# Iter 136: real delta so x-tracking continues during BOSS state too
		outlaw.position.x = lerpf(outlaw.position.x, target_x,
			clampf(1.5 * delta, 0.0, 1.0))
		# iter400: ride the hilly terrain (sit on the ground, not float over it).
		# Skip the pushed-wagon set-piece (it owns its own y). iter401: outlaws spawn
		# at y=1.0 (their foot offset) — use that, not POSSE_BASE_Y, or their feet clip.
		if not outlaw.get_meta("is_pushed", false) and not outlaw.get_meta("is_pusher", false) \
				and not outlaw.get_meta("is_kimmy", false):
			var _ground_y: float = OUTLAW_BASE_Y + _hill_y(_level_distance + (cowboy_3d.position.z - outlaw.position.z))
			if _kind == "gummi_bear":
				# BOUNCY: sine y-arc hop on top of the ground. hop_t in [0,1) over
				# GUMMI_HOP_PERIOD; apex at 0.5. Stash hop_t so the defense check
				# (apex-only-hittable) reads the same phase.
				var _hp_phase: float = outlaw.get_meta("hop_phase", 0.0) + delta
				if _hp_phase >= GUMMI_HOP_PERIOD:
					_hp_phase = fmod(_hp_phase, GUMMI_HOP_PERIOD)
					if get_node_or_null("/root/AudioBus") and AudioBus.has_method("play_sfx"):
						AudioBus.play_sfx("sfx_gummi_bear")  # land thump each hop
				outlaw.set_meta("hop_phase", _hp_phase)
				var _hop_t: float = _hp_phase / GUMMI_HOP_PERIOD
				outlaw.set_meta("hop_t", _hop_t)
				outlaw.position.y = _ground_y + sin(_hop_t * PI) * GUMMI_HOP_HEIGHT
			else:
				outlaw.position.y = _ground_y
		# Per-kind offense.
		var _z_gap: float = cowboy_3d.position.z - outlaw.position.z
		if _kind == "gummi_bear" or _kind == "fried_dough":
			# CONTACT / MELEE: drain a posse member when it reaches them, then
			# despawn (it spent itself on the hit). Counts toward the quota.
			if _z_gap >= 0.0 and _z_gap <= OUTLAW_MELEE_Z and absf(outlaw.position.x - cowboy_3d.position.x) <= 1.6:
				_outlaw_drain_posse(outlaw.position,
					"sfx_fried_dough" if _kind == "fried_dough" else "sfx_gummi_bear")
				_outlaw_left_field(outlaw)
				outlaw.queue_free()
				continue
		elif _kind == "triffid":
			# ROOTED reach-lash: whip posse members in its lane on a cooldown.
			var lt: float = outlaw.get_meta("lash_timer", 0.0) - delta
			if lt <= 0.0:
				var in_z: bool = _z_gap >= -1.0 and _z_gap <= TRIFFID_LASH_RANGE_Z
				if in_z and absf(outlaw.position.x - cowboy_3d.position.x) <= TRIFFID_LASH_X:
					_outlaw_drain_posse(outlaw.position, "sfx_triffid")
					lt = TRIFFID_LASH_COOLDOWN
				else:
					lt = 0.3  # re-check soon while waiting for the posse to enter range
			outlaw.set_meta("lash_timer", lt)
		elif _kind == "candy_corn":
			# KITER ranged triple-volley.
			var ftc: float = outlaw.get_meta("fire_timer", 0.0) - delta
			if ftc <= 0.0:
				ftc = OUTLAW_FIRE_INTERVAL
				if _z_gap >= 0.0 and _z_gap <= OUTLAW_FIRE_RANGE_Z:
					_candy_corn_volley(outlaw)
			outlaw.set_meta("fire_timer", ftc)
		else:
			# vagrant (+ any unknown kind): the original single-shot fire.
			var ft: float = outlaw.get_meta("fire_timer", 0.0)
			ft -= delta
			if ft <= 0.0:
				ft = OUTLAW_FIRE_INTERVAL
				# Iter 121: only fire when within OUTLAW_FIRE_RANGE_Z of cowboy z.
				if _z_gap >= 0.0 and _z_gap <= OUTLAW_FIRE_RANGE_Z:
					_outlaw_fire(outlaw)
			outlaw.set_meta("fire_timer", ft)
		if outlaw.position.z > OBSTACLE_DESPAWN_Z:
			_outlaw_left_field(outlaw)
			outlaw.queue_free()
		# Bullet-vs-outlaw collision (use posse bullets)
		for bullet in bullets_root.get_children():
			if not (bullet is Node3D):
				continue
			var dx: float = bullet.position.x - outlaw.position.x
			var dz: float = bullet.position.z - outlaw.position.z
			if dx * dx + dz * dz < OUTLAW_HIT_RADIUS_SQ:
				# gummi DEFENSE: only hittable near the APEX of its hop. While
				# grounded/squashed the bullet passes through (not consumed) — a
				# generous window centered on apex (hop_t == 0.5).
				if _kind == "gummi_bear":
					var _ht: float = outlaw.get_meta("hop_t", 0.5)
					if absf(_ht - 0.5) > GUMMI_APEX_WINDOW * 0.5:
						continue  # mid-flight pass-through; bullet survives
				# Iter 134: pushers route to specialized 1-shot-kill handler.
				if outlaw.get_meta("is_pusher", false):
					_pusher_take_damage(outlaw)
					bullet.queue_free()
					break
				# Iter 133: captives route to specialized damage handler
				# (HP scales with hero tier, no death-stream, release ceremony).
				if outlaw.get_meta("is_captive", false):
					_captive_take_damage(outlaw, bullet.position, bullet.get_meta("rainbow", false))
					bullet.queue_free()
					break
				var hp: int = outlaw.get_meta("hp", 1) - bullet.get_meta("dmg", 1)
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
					_outlaw_left_field(outlaw)
					var death_sprite: Sprite3D = outlaw.get_meta("sprite_3d", null)
					if death_sprite != null and is_instance_valid(death_sprite):
						var death_sv: SubViewport = _get_or_create_shared_video_viewport(VAGRANT_DEATH_STREAM)
						death_sprite.texture = death_sv.get_texture()
					_hits += 1
					_refresh_hud()
					# iter413: occasional defeat grunt (prob-gated so a kill wave doesn't stack).
					if randf() < 0.3 and get_node_or_null("/root/AudioBus") and AudioBus.has_method("play_sfx"):
						AudioBus.play_sfx("outlaw_down")
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
				if randf() < 0.3 and get_node_or_null("/root/AudioBus") and AudioBus.has_method("play_sfx"): AudioBus.play_sfx("posse_hurt")
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
	if _level_state == LevelState.PLAYING and not _pete_spawned and not _test_range_mode and not _boss_from_data and not _quota_driven() and _level_elapsed >= PETE_SPAWN_DELAY:
		_pete_spawned = true
		# Iter 157: boss dispatch by level — level 2 → The Candy Rustler,
		# every other level → Slippery Pete.
		if _boss_kind() == "rustler":
			_spawn_candy_rustler()
		elif _boss_kind() == "raisin":
			_spawn_raisin_kidd()
		else:
			_spawn_pete()
		# iter414b: clear any gates so the boss isn't hidden behind one.
		for _g in gates_root.get_children():
			_g.queue_free()
		_level_state = LevelState.BOSS
		DebugLog.add("level state: PLAYING → BOSS (kind=%s)" % _boss_kind())
	# Iter 77: Pete behavior — approach to PETE_STAY_Z, fire periodically,
	# check bullet hits.
	if _pete_spawned and boss_root.get_child_count() > 0:
		var pete: Node3D = boss_root.get_child(0)
		if is_instance_valid(pete) and pete is Node3D and not (pete.get_meta("boss_kind", "pete") in ["rustler", "raisin"]):
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
							if randf() < 0.4 and get_node_or_null("/root/AudioBus") and AudioBus.has_method("play_sfx"): AudioBus.play_sfx("pete_melee")
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
				# iter409: Pete invulnerable until he's arrived + a brief beat (was one-shot mid-approach).
				if _pete_stay_elapsed <= 1.0:
					break
				if not (bullet is Node3D):
					continue
				var dx: float = bullet.position.x - pete.position.x
				var dz: float = bullet.position.z - pete.position.z
				if dx * dx + dz * dz < PETE_HIT_RADIUS_SQ:
					var hp: int = pete.get_meta("hp", PETE_HP) - bullet.get_meta("dmg", 1)
					pete.set_meta("hp", hp)
					_spawn_popup_3d(pete.position + Vector3(0, 1.5, 0),
						"-1", Color(1, 0.45, 0.25, 1), 72)
					bullet.queue_free()
					_hits += 1
					_refresh_hud()
					_refresh_pete_hp(pete)
					var has_bus := get_node_or_null("/root/AudioBus") != null \
						and AudioBus.has_method("play_character_line")
					if hp <= 0:
						# Dying line before the win screen.
						if has_bus:
							AudioBus.play_character_line("pete_dying_%d" % (randi() % 4))
						pete.queue_free()
						_show_win()
						break
					# Occasional angry "ow" so he reacts without spamming on
					# every hit (and never over an in-flight line).
					elif has_bus and randf() < 0.25 \
							and not (AudioBus.has_method("any_character_line_playing") \
								and AudioBus.any_character_line_playing()):
						AudioBus.play_character_line("pete_hit_%d" % (randi() % 4))
	# Iter 157: the Candy Rustler runs a separate process branch — he is a
	# stationary jointed puppet, not Pete's video-anim/melee actor. The
	# Pete block above is skipped for him via the boss_kind guard on its
	# `if is_instance_valid(...)`.
	if _pete_spawned and boss_root.get_child_count() > 0:
		var rustler_boss: Node3D = boss_root.get_child(0)
		if is_instance_valid(rustler_boss) and rustler_boss.get_meta("boss_kind", "pete") == "rustler":
			_process_rustler(rustler_boss, delta)
		elif is_instance_valid(rustler_boss) and rustler_boss.get_meta("boss_kind", "pete") == "raisin":
			_process_raisin_kidd(rustler_boss, delta)
	# Iter 115: GunState-driven auto-fire. Replaces the iter-66 fixed
	# fire_timer. tick(delta) advances the cooldown + reload countdown;
	# the while-can_fire loop drains as many shots as the cowboy is
	# entitled to this frame (usually 0-1 depending on cooldown). Each
	# fire() consumes one ammo; ammo=0 → reload kicks in automatically.
	# Iter 118: gate firing on PLAYING + BOSS. Countdown blocks firing.
	if _gun_state != null and _level_state != LevelState.COUNTDOWN:
		_gun_state.tick(delta)
		# iter413: reload click on the empty->reloading transition.
		var reloading_now: bool = _gun_state.is_reloading()
		if reloading_now and not _was_reloading and get_node_or_null("/root/AudioBus") and AudioBus.has_method("play_sfx"):
			AudioBus.play_sfx("gun_reload")
		_was_reloading = reloading_now
		while _gun_state.can_fire():
			_gun_state.fire()
			_spawn_bullet()
		_refresh_ammo_label_3d()
	# Move + collision-check each bullet.
	for bullet in bullets_root.get_children():
		if not (bullet is Node3D):
			continue
		var _prev_z: float = bullet.position.z   # iter364: for swept gate collision
		bullet.position.z -= BULLET_SPEED * _weather_bullet_speed_mult * delta
		# iter417: wind weather pushes bullets sideways as they fly.
		if _weather_bullet_drift != 0.0:
			bullet.position.x += _weather_bullet_drift * delta
		# Despawn at the weapon's range (per-bullet; default const otherwise).
		if bullet.position.z < float(bullet.get_meta("despawn_z", BULLET_DESPAWN_Z)):
			bullet.queue_free()
			continue
		# Iter 110: gate-vs-bullet collision — bullets count down the
		# gate door's value (moving toward 0). For multiplicative gates,
		# degrade the multiplier toward 2 then collapse to additive 0.
		if _check_bullet_gate_collision(bullet, _prev_z):
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
				_spawn_impact_blast(bullet.position)
				bullet.queue_free()
				if obstacle.get_meta("is_bull", false) or obstacle.get_meta("is_coop", false):
					# iter410/411: bulls + coops soak many hits (scaled by posse damage).
					var ohp: int = obstacle.get_meta("hp", BULL_HP) - bullet.get_meta("dmg", 1)
					obstacle.set_meta("hp", ohp)
					if ohp <= 0:
						if obstacle.get_meta("is_coop", false):
							_bust_coop(obstacle.position)
							_spawn_popup_3d(obstacle.position + Vector3(0, 1.4, 0),
								"FEATHERS!", Color(1.0, 0.95, 0.7, 1), 50)
						else:
							_spawn_popup_3d(obstacle.position + Vector3(0, 1.3, 0),
								"BULL DOWN!", Color(1.0, 0.82, 0.3, 1), 52)
							if get_node_or_null("/root/AudioBus") and AudioBus.has_method("play_sfx"):
								AudioBus.play_sfx("bull_bellow")
						obstacle.queue_free()
						_hits += 1
						_refresh_hud()
					break
				_spawn_popup_3d(obstacle.position + Vector3(0, 1, 0),
					"-1", Color(1, 0.32, 0.22, 1), 56)
				if get_node_or_null("/root/AudioBus") and AudioBus.has_method("play_sfx"):
					AudioBus.play_sfx("impact_thud")   # iter413: prop shattered
				obstacle.queue_free()
				_hits += 1
				_refresh_hud()
				break
	# SP2 slice3: bend the road by the path curve (after all z-updates this frame).
	_apply_path_curve()

# ---- SP2 slice3: curved path ------------------------------------------------
# Lateral world-x offset of the path centreline at a given distance-along-path.
# Smoothstep-interpolated keyframes tiled over PATH_PATTERN_LEN — supports sharp
# and gentle bends. A data-driven PathProfile.lateral Curve can replace this later.
func _path_lateral(dist: float) -> float:
	var w: float = fposmod(dist, PATH_PATTERN_LEN)
	for i in range(_PATH_KEYS.size() - 1):
		var k0: Vector2 = _PATH_KEYS[i]
		var k1: Vector2 = _PATH_KEYS[i + 1]
		if w >= k0.x and w <= k1.x:
			var t: float = (w - k0.x) / maxf(0.001, k1.x - k0.x)
			return lerpf(k0.y, k1.y, smoothstep(0.0, 1.0, t))
	return 0.0

# The bend an entity at world-z should show: its distance-along-path is the
# player's scrolled distance plus how far AHEAD it still is (cowboy_z − z).
# Subtracting the player's own lateral keeps the player lane at x≈0.
func _path_offset_at_z(z: float, base_lat: float) -> float:
	var d: float = _level_distance + (cowboy_3d.position.z - z)
	return _path_lateral(d) - base_lat

func _apply_path_curve() -> void:
	if cowboy_3d == null:
		return
	var base_lat: float = _path_lateral(_level_distance)
	# Non-tracking scrollers: x = their spawn lane + the bend at their depth. Ground
	# props/gates also follow the hill height so they sit ON the terrain (bonuses
	# float, so they keep their own y).
	for root in [obstacles_root, scenery_root, gates_root, bonuses_root, holes_root]:
		if root == null:
			continue
		var ground_follow: bool = (root == obstacles_root or root == scenery_root or root == gates_root)
		for c in root.get_children():
			if not (c is Node3D):
				continue
			if not c.has_meta("lane_x"):
				c.set_meta("lane_x", c.position.x)
				c.set_meta("lane_y", c.position.y)
			var d_at: float = _level_distance + (cowboy_3d.position.z - c.position.z)
			c.position.x = c.get_meta("lane_x") + _path_lateral(d_at) - base_lat
			if ground_follow:
				# Subtract the hole drop so a prop over a ditch sinks into it rather than
				# floating in midair above the dropped ground (iter431 cactus-over-ditch fix).
				c.position.y = c.get_meta("lane_y") + _hill_y(d_at) - _hole_drop(d_at, c.get_meta("lane_x"))
	_update_world_root()

func _check_puddle_splash() -> void:
	if _level_state != LevelState.PLAYING:
		return
	var lap: float = fposmod(_level_distance, PATH_PATTERN_LEN)
	var prev: float = _last_lap
	_last_lap = lap
	if lap < prev:   # wrapped this frame
		prev -= PATH_PATTERN_LEN
	for pud in _PUDDLES:
		var pd: float = pud.x   # Vector3(distance, lateral, radius)
		if (prev < pd and pd <= lap) or (prev < pd - PATH_PATTERN_LEN and pd - PATH_PATTERN_LEN <= lap):
			if get_node_or_null("/root/AudioBus") and AudioBus.has_method("play_sfx"):
				AudioBus.play_sfx("puddle_splash")
			break

# Rolling hills as a function of distance — periods divide PATH_PATTERN_LEN (140)
# so the terrain tiles seamlessly when WorldRoot.z wraps.
func _hill_y(d: float) -> float:
	return TerrainThemes.hill_height(d) * _hill_scale

# Depth a pit drops at (distance d, lateral offset gx from the path centre).
func _hole_drop(d: float, gx: float) -> float:
	var dd: float = fposmod(d, PATH_PATTERN_LEN)
	for h in _HOLES:
		if dd >= h["d0"] and dd <= h["d1"] and gx >= h["x0"] and gx <= h["x1"]:
			return HOLE_DEPTH
	return 0.0

# A terrain vertex: the curve is baked into x, hills + pits into y. lz<0 is ahead;
# distance d = -lz so it matches the entity offset (_path_offset_at_z) when WorldRoot
# is translated by (-_path_lateral(dist), 0, dist).
func _terr_vertex(gx: float, lz: float) -> Vector3:
	var d: float = -lz
	var y: float = _hill_y(d) - _hole_drop(d, gx)
	if _terr_cliff_side != "":
		# gx is lane-relative x; the cliff lip sits at the trail half-width (2.6).
		y -= TerrainThemes.cliff_drop(gx, 2.6, _terr_cliff_side, _terr_cliff_depth)
	return Vector3(gx + _path_lateral(d), y, lz)

# iter400: build the static curved+hilly terrain (+ puddles) ONCE under WorldRoot,
# replacing the UV-scroll flat plane. The posse advances by translating WorldRoot.
# iter415: per-terrain environment look (fog). Ground tex/tint/detail are baked at
# build time in _build_world_terrain; this adds the atmospheric layer.
func _apply_terrain_theme() -> void:
	if subviewport == null:
		return
	var theme: Dictionary = TerrainThemes.get_theme(_level_def.terrain if _level_def != null else "frontier")
	var env := Environment.new()
	env.background_mode = Environment.BG_CANVAS
	env.fog_enabled = true
	env.fog_light_color = theme["fog_color"]
	env.fog_density = theme["fog_density"]
	var we := WorldEnvironment.new()
	we.name = "TerrainEnv"
	we.environment = env
	subviewport.add_child(we)
	# terrain: build the surface dressing (world root already built in _build_world_terrain).
	_build_cliff_void()
	_build_trail_mesh()
	_build_scatter()

func _build_world_terrain() -> void:
	if subviewport == null or _world_root != null:
		return
	_world_root = Node3D.new()
	_world_root.name = "WorldRoot"
	subviewport.add_child(_world_root)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cols: int = int(TERR_HALF_W * 2.0 / TERR_DX)
	var rows: int = int((TERR_Z_BEHIND - TERR_Z_AHEAD) / TERR_DZ)
	# terrain: per-theme ground surface — albedo+normal+detail, larger UV tiling, and a
	# STRONG baked per-vertex macro-variation (the main "not one flat tile" win). The
	# theme also drives the optional cliff edge (mountain), set on the _terr_* members.
	var _theme: Dictionary = TerrainThemes.get_theme(_level_def.terrain if _level_def != null else "frontier")
	var tile: float = float(_theme.get("ground_uv_tile", 13.0))
	var _macro: float = float(_theme.get("macro_strength", 1.0))
	_hill_scale = float(_theme.get("hill_scale", 1.0))   # mountain = steeper hills
	var _cliff: Variant = _theme.get("cliff", null)
	_terr_cliff_side = String(_cliff["side"]) if _cliff != null else ""
	_terr_cliff_depth = float(_cliff["depth"]) if _cliff != null else 0.0
	var _gorge := Color(0.10, 0.12, 0.18)   # dark shadow the cliff face fades to (reads as a gorge)
	var _tlo: Color = _theme["tint_low"]
	var _thi: Color = _theme["tint_high"]
	var _tamp: float = 2.2 * _hill_scale   # ~max |hill_height|, scaled
	var _vcol := func(py: float, gx: float, lz: float) -> Color:
		var c: Color = TerrainThemes.tint(py, _tlo, _thi, _tamp)
		var m: float = TerrainThemes.mottle(gx, lz, _macro)
		var col := Color(c.r * m, c.g * m, c.b * m, 1.0)
		if _terr_cliff_side != "":
			# Darken the dropped cliff face toward shadow so it reads as a gorge, not a white wall.
			var drop: float = TerrainThemes.cliff_drop(gx, 2.6, _terr_cliff_side, _terr_cliff_depth)
			if drop > 0.0:
				col = col.lerp(_gorge, clampf(drop / 8.0, 0.0, 1.0))
		return col
	for r in range(rows):
		var lz0: float = TERR_Z_BEHIND - float(r) * TERR_DZ
		var lz1: float = TERR_Z_BEHIND - float(r + 1) * TERR_DZ
		for c in range(cols):
			var gx0: float = -TERR_HALF_W + float(c) * TERR_DX
			var gx1: float = gx0 + TERR_DX
			var p00: Vector3 = _terr_vertex(gx0, lz0)
			var p10: Vector3 = _terr_vertex(gx1, lz0)
			var p01: Vector3 = _terr_vertex(gx0, lz1)
			var p11: Vector3 = _terr_vertex(gx1, lz1)
			# +0.37 U offset so the lane centre isn't on a tile boundary (kills the seam).
			var u0: float = (gx0 + TERR_HALF_W) / tile + 0.37
			var u1: float = (gx1 + TERR_HALF_W) / tile + 0.37
			var v0: float = -lz0 / tile
			var v1: float = -lz1 / tile
			st.set_color(_vcol.call(p00.y, gx0, lz0)); st.set_uv(Vector2(u0, v0)); st.set_uv2(Vector2(u0 * 4.0, v0 * 4.0)); st.add_vertex(p00)
			st.set_color(_vcol.call(p10.y, gx1, lz0)); st.set_uv(Vector2(u1, v0)); st.set_uv2(Vector2(u1 * 4.0, v0 * 4.0)); st.add_vertex(p10)
			st.set_color(_vcol.call(p11.y, gx1, lz1)); st.set_uv(Vector2(u1, v1)); st.set_uv2(Vector2(u1 * 4.0, v1 * 4.0)); st.add_vertex(p11)
			st.set_color(_vcol.call(p00.y, gx0, lz0)); st.set_uv(Vector2(u0, v0)); st.set_uv2(Vector2(u0 * 4.0, v0 * 4.0)); st.add_vertex(p00)
			st.set_color(_vcol.call(p11.y, gx1, lz1)); st.set_uv(Vector2(u1, v1)); st.set_uv2(Vector2(u1 * 4.0, v1 * 4.0)); st.add_vertex(p11)
			st.set_color(_vcol.call(p01.y, gx0, lz1)); st.set_uv(Vector2(u0, v1)); st.set_uv2(Vector2(u0 * 4.0, v1 * 4.0)); st.add_vertex(p01)
	st.generate_normals()
	st.generate_tangents()   # so the normal map lights correctly
	var mi := MeshInstance3D.new()
	mi.name = "Terrain"
	mi.mesh = st.commit()
	var sm := StandardMaterial3D.new()
	sm.albedo_texture = load(_theme["ground_albedo"])
	if _theme.has("ground_normal"):
		sm.normal_enabled = true
		sm.normal_texture = load(_theme["ground_normal"])
	sm.roughness = 1.0
	sm.cull_mode = BaseMaterial3D.CULL_DISABLED
	sm.vertex_color_use_as_albedo = true
	sm.uv1_scale = Vector3(1, 1, 1)
	# (detail layer intentionally omitted: StandardMaterial3D detail with MIX and no
	# detail_mask fully REPLACES the base albedo with the grey detail tile. The
	# realistic look comes from the albedo + normal + baked macro-variation; a masked
	# detail layer can be re-added later.)
	mi.material_override = sm
	_world_root.add_child(mi)
	# Puddles: flat translucent blue discs on the terrain at authored spots.
	_ice_puddles.clear()
	for p in _PUDDLES:
		var _pud := _make_puddle(p.x, p.y, p.z)
		_world_root.add_child(_pud)
		if _pud.get_meta("is_ice", false):
			_ice_puddles.append(_pud)
	# iter418: pits were invisible (only a distance+x kill-zone) so the posse
	# seemed to float over nothing. Render each authored hole as a world-anchored
	# dark decal that scrolls + rides the hills exactly like the puddles, so it
	# lines up with the _check_authored_holes trigger.
	for hi in range(_HOLES.size()):
		var hh: Dictionary = _HOLES[hi]
		var hd: float = (float(hh["d0"]) + float(hh["d1"])) * 0.5
		var hgx: float = (float(hh["x0"]) + float(hh["x1"])) * 0.5
		var hxh: float = (float(hh["x1"]) - float(hh["x0"])) * 0.5
		var hzh: float = (float(hh["d1"]) - float(hh["d0"])) * 0.5
		_world_root.add_child(_make_pit(hd, hgx, hxh, hzh, _pit_fill_for(hi)))
	# Retire the UV-scroll "treadmill": hide the flat ground + stop its auto-scroll.
	var flat := get_node_or_null("Terrain3D/SubViewport/Ground")
	if flat != null and flat is Node3D:
		(flat as Node3D).visible = false
	if terrain_3d_node != null and "auto_scroll" in terrain_3d_node:
		terrain_3d_node.auto_scroll = false

# terrain: the mountain cliff is a FALL-TO-DEATH edge. If the posse strays past the
# cliff lip, members tumble off the ledge (drain the crowd while over the edge). Floors
# at 1 like the pit hazard.
func _check_cliff_fall(delta: float) -> void:
	if _terr_cliff_side == "" or _level_state != LevelState.PLAYING:
		return
	if cowboy_3d == null or _posse_count_3d <= 1:
		return
	var lip: float = 2.6
	var off: bool = (_terr_cliff_side == "left" and cowboy_3d.position.x < -lip) \
		or (_terr_cliff_side == "right" and cowboy_3d.position.x > lip)
	if not off:
		_cliff_fall_accum = 0.0
		return
	_cliff_fall_accum += delta * 4.0   # ~4 members/sec lost over the edge
	var drop: int = int(_cliff_fall_accum)
	if drop >= 1:
		_cliff_fall_accum -= float(drop)
		_posse_count_3d = maxi(1, _posse_count_3d - drop)
		_sync_followers_to_count(_posse_count_3d)
		_refresh_hud()

# terrain: a small lateral wobble for a trail edge at depth lz (phase shifts the two
# edges so the width varies irregularly). Periodic over PATH_PATTERN_LEN for a seamless wrap.
func _trail_wob(lz: float, phase: float) -> float:
	var w: float = (-lz + phase) * TAU / PATH_PATTERN_LEN
	return 0.55 * sin(3.0 * w) + 0.30 * sin(7.0 * w + 1.0)

# terrain: a worn central trail ribbon laid over the earth down the posse's lane,
# riding the hills via _terr_vertex (raised a hair to avoid z-fighting). Skips themes
# with no trail. Called from _apply_terrain_theme (world root already built).
func _build_trail_mesh() -> void:
	if _world_root == null:
		return
	var theme: Dictionary = TerrainThemes.get_theme(_level_def.terrain if _level_def != null else "frontier")
	var trail: Variant = theme.get("trail", null)
	if trail == null:
		return
	var half: float = float(trail["half_width"])
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rows: int = int((TERR_Z_BEHIND - TERR_Z_AHEAD) / TERR_DZ)
	for r in range(rows):
		var lz0: float = TERR_Z_BEHIND - float(r) * TERR_DZ
		var lz1: float = lz0 - TERR_DZ
		var v0: float = -lz0 / 6.0
		var v1: float = -lz1 / 6.0
		# Wobble each edge independently so the trail meanders like a worn path
		# instead of a clean straight strip (periodic over PATH_PATTERN_LEN → seamless).
		var pL0 := _terr_vertex(-half + _trail_wob(lz0, 0.0), lz0) + Vector3(0, 0.02, 0)
		var pR0 := _terr_vertex(half + _trail_wob(lz0, 47.0), lz0) + Vector3(0, 0.02, 0)
		var pL1 := _terr_vertex(-half + _trail_wob(lz1, 0.0), lz1) + Vector3(0, 0.02, 0)
		var pR1 := _terr_vertex(half + _trail_wob(lz1, 47.0), lz1) + Vector3(0, 0.02, 0)
		st.set_uv(Vector2(0, v0)); st.add_vertex(pL0)
		st.set_uv(Vector2(1, v0)); st.add_vertex(pR0)
		st.set_uv(Vector2(1, v1)); st.add_vertex(pR1)
		st.set_uv(Vector2(0, v0)); st.add_vertex(pL0)
		st.set_uv(Vector2(1, v1)); st.add_vertex(pR1)
		st.set_uv(Vector2(0, v1)); st.add_vertex(pL1)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = "Trail"
	mi.mesh = st.commit()
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(trail["albedo"])
	m.roughness = 1.0
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	_world_root.add_child(mi)

# terrain: a wooden plank walk along one shoulder (frontier: right). Rides the hills.
# terrain R2b: a single weathered plank strip on the RIGHT shoulder in front of
# one building at depth z. Parented to scenery_root so the curve/scroll/despawn
# system handles it exactly like a building: spawn x = the base lateral lane (NO
# bend), spawn y = a tiny ground-lift; _apply_path_curve stores those as lane_x/
# lane_y meta on first frame and then re-adds the path bend + hill_y(d) each frame,
# and the scenery scroll loop advances z and queue_frees it off-screen.
func _spawn_boardwalk_segment(z: float) -> void:
	if scenery_root == null:
		return
	var theme: Dictionary = TerrainThemes.get_theme(_level_def.terrain if _level_def != null else "frontier")
	var bw: Variant = theme.get("boardwalk", null)
	if bw == null or String(bw["side"]) != "right":
		return
	var trail: Variant = theme.get("trail", null)
	var lip: float = float(trail["half_width"]) if trail != null else 2.6
	var base_w: float = float(bw["width"])
	# Irregular per-segment width + length. Width sits between the trail lip and the
	# building band; length runs along z (a few planks' worth, varied).
	var seg_w: float = base_w * _rng.randf_range(0.82, 1.12)
	var seg_len: float = _rng.randf_range(5.0, 8.5)
	var x0: float = lip + _rng.randf_range(0.3, 0.7)
	# Center the strip between the lip and the building band, on the right (+x).
	var cx: float = x0 + seg_w * 0.5
	var mi := MeshInstance3D.new()
	mi.name = "BoardwalkSeg"
	var qm := QuadMesh.new()
	qm.size = Vector2(seg_w, seg_len)
	qm.orientation = PlaneMesh.FACE_Y
	mi.mesh = qm
	var m := StandardMaterial3D.new()
	if ResourceLoader.exists(String(bw["albedo"])):
		m.albedo_texture = load(bw["albedo"])
	# Weathered brown-grey tint with per-segment variation (sun-bleached planks).
	var g: float = _rng.randf_range(0.46, 0.62)
	m.albedo_color = Color(g * 1.05, g * 0.94, g * 0.80, 1.0)
	m.roughness = 1.0
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	# Repeat the plank texture along the length so longer segments tile.
	m.uv1_scale = Vector3(1.0, maxf(1.0, seg_len / 2.2), 1.0)
	mi.material_override = m
	# Base lateral lane WITHOUT bend (the curve system adds the bend each frame).
	# A small +y lift so it reads as sitting on top of the dirt, not z-fighting.
	mi.position = Vector3(cx, 0.07, z)
	# Slight random skew so the strip isn't perfectly road-aligned (irregular).
	mi.rotation.y = deg_to_rad(_rng.randf_range(-4.0, 4.0))
	scenery_root.add_child(mi)

# iter432: per-cell scatter clumping factor (0..~1.8), varied per slug phase, so
# different stretches of the level read denser/sparser — intra-level variety.
func _scatter_clump(cell: int, slug: String) -> float:
	var w: float = float(cell) * 0.6 + float(hash(slug) % 97) * 0.13
	return clampf(0.5 + 0.9 * sin(w) + 0.4 * sin(w * 0.37 + 1.3), 0.0, 1.8)

# terrain: MultiMesh scatter (grass/scrub/rocks/cactus/etc) on the shoulders, placed
# deterministically per z-cell so the wrapping world is stable; fog hides far ones, so
# no per-frame cull is needed. Reads the theme's scatter list. Non-colliding decor.
func _build_scatter() -> void:
	if _world_root == null:
		return
	var theme: Dictionary = TerrainThemes.get_theme(_level_def.terrain if _level_def != null else "frontier")
	var sets: Array = theme.get("scatter", [])
	var x_lo: float = 3.4    # just past the trail lip
	var x_hi: float = 22.0   # out past the screen edges
	var z_lo: float = TERR_Z_AHEAD + 2.0
	var z_hi: float = TERR_Z_BEHIND - 2.0
	var cell_dz: float = 6.0
	var cells: int = int((z_hi - z_lo) / cell_dz)
	for s in sets:
		var slug: String = String(s["slug"])
		var tex_path: String = "res://assets/sprites/props/%s.png" % slug
		if not ResourceLoader.exists(tex_path):
			continue
		var tex: Texture2D = load(tex_path)
		var side: String = String(s.get("side", "both"))
		var sc: Array = s.get("scale", [0.6, 1.0])
		var dens: float = float(s["density"])
		var xforms: Array = []
		for c in range(cells):
			var z0: float = z_lo + float(c) * cell_dz
			var z1: float = z0 + cell_dz
			# iter432: vary density per cell so the level CLUMPS into lush patches and
			# bare stretches (different phase per slug) instead of a uniform carpet —
			# adds variety as you progress through the level.
			var n: int = int(round(dens * 2.0 * _scatter_clump(c, slug)))
			for p in TerrainThemes.scatter_positions(hash(slug), c, n, -z1, -z0, x_lo, x_hi):
				var px: float = p.x
				if side == "right" and px < 0.0: px = -px
				if side == "left" and px > 0.0: px = -px
				var lz: float = p.y
				var pos: Vector3 = _terr_vertex(px, lz)
				var rng := RandomNumberGenerator.new(); rng.seed = hash([slug, c, int(px * 100.0)])
				var scl: float = lerpf(sc[0], sc[1], rng.randf())
				var b := Basis.IDENTITY.scaled(Vector3(scl, scl, scl))
				xforms.append(Transform3D(b, pos + Vector3(0, scl * 0.5, 0)))
		if xforms.is_empty():
			continue
		var quad := QuadMesh.new(); quad.size = Vector2(1.0, 1.0)
		var m := StandardMaterial3D.new()
		m.albedo_texture = tex
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		m.alpha_scissor_threshold = 0.5
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		m.billboard_keep_scale = true
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		quad.material = m
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = quad
		mm.instance_count = xforms.size()
		for i in range(xforms.size()):
			mm.set_instance_transform(i, xforms[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Scatter_%s" % slug
		mmi.multimesh = mm
		_world_root.add_child(mmi)

# terrain: a receding haze/void plane below the cliff lip so the mountain left-drop
# reads as a gorge into cloud, not a hole.
func _build_cliff_void() -> void:
	if _world_root == null:
		return
	var theme: Dictionary = TerrainThemes.get_theme(_level_def.terrain if _level_def != null else "frontier")
	var cliff: Variant = theme.get("cliff", null)
	if cliff == null:
		return
	var depth: float = float(cliff["depth"])
	var is_left: bool = String(cliff["side"]) == "left"
	var lip: float = -2.6 if is_left else 2.6
	var pm := PlaneMesh.new()
	pm.size = Vector2(depth, absf(TERR_Z_AHEAD - TERR_Z_BEHIND))
	var mi := MeshInstance3D.new()
	mi.name = "CliffVoid"
	mi.mesh = pm
	mi.rotation_degrees = Vector3(0, 0, -80 if is_left else 80)
	mi.position = Vector3(lip - (depth * 0.5) * (1.0 if is_left else -1.0),
		-depth * 0.5, (TERR_Z_AHEAD + TERR_Z_BEHIND) * 0.5)
	var m := StandardMaterial3D.new()
	# Dark rocky gorge fading to the fog haze at the bottom (a vertical gradient), so
	# the drop reads as a deep fall-to-death chasm, not a flat white wall.
	var grad := Gradient.new()
	grad.set_color(0, Color(0.12, 0.13, 0.18))                       # near the lip: dark rock
	grad.set_color(1, theme.get("fog_color", Color(0.80, 0.84, 0.92)))  # far below: misty haze
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill_from = Vector2(0.5, 0.0)
	gt.fill_to = Vector2(0.5, 1.0)
	m.albedo_texture = gt
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	_world_root.add_child(mi)

func _grab_ground_texture() -> Texture2D:
	var flat := get_node_or_null("Terrain3D/SubViewport/Ground")
	if flat is MeshInstance3D:
		var m = (flat as MeshInstance3D).material_override
		if m is StandardMaterial3D and (m as StandardMaterial3D).albedo_texture != null:
			return (m as StandardMaterial3D).albedo_texture
	if ResourceLoader.exists("res://assets/textures/dirt_path_2k.png"):
		return load("res://assets/textures/dirt_path_2k.png")
	return null

# iter418: a visible pit decal — dark rectangle on the terrain at an authored
# hole. World-anchored (placed via _terr_vertex) so it scrolls + follows hills
# like the puddles and stays aligned with the gameplay kill-zone.
# winflow: deterministic fill assignment per authored hole. Cycles
# fudge / honey / soda across the _HOLES entries (index-based), offset by the
# current level so different levels lead with a different candy.
const _PIT_FILLS: Array = ["fudge", "honey", "soda"]
# Splash tint per fill — drives both the splash particles and a faint pit accent.
const _PIT_TINTS: Dictionary = {
	"fudge": Color(0.42, 0.24, 0.12),   # brown gloop
	"honey": Color(0.95, 0.66, 0.10),   # golden
	"soda":  Color(0.95, 0.95, 0.98),   # white foam
}

func _pit_fill_for(hole_index: int) -> String:
	var lvl: int = 1
	if get_node_or_null("/root/GameState") != null:
		lvl = int(GameState.current_level)
	return _PIT_FILLS[(hole_index + lvl) % _PIT_FILLS.size()]

# winflow: a visible DEEP candy pit decal at an authored hole. World-anchored
# (placed via _terr_vertex) so it scrolls + follows hills like the puddles and
# stays aligned with the gameplay kill-zone. `fill` ∈ {fudge,honey,soda} picks
# the deep-pit art res://assets/sprites/ui/winflow/pit_<fill>.png.
func _make_pit(d: float, gx: float, x_half: float, z_half: float, fill: String = "fudge") -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(x_half * 2.0, z_half * 2.0)
	qm.orientation = PlaneMesh.FACE_Y
	mi.mesh = qm
	var pos: Vector3 = _terr_vertex(gx, -d)
	mi.position = Vector3(pos.x, pos.y + 0.05, pos.z)
	mi.set_meta("pit_fill", fill)
	var mat := StandardMaterial3D.new()
	var tex_path: String = "res://assets/sprites/ui/winflow/pit_%s.png" % fill
	if ResourceLoader.exists(tex_path):
		mat.albedo_texture = load(tex_path)
	elif ResourceLoader.exists("res://assets/sprites/props/pit_hole.png"):
		mat.albedo_texture = load("res://assets/sprites/props/pit_hole.png")
	mat.albedo_color = Color(1.0, 1.0, 1.0, 1.0)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = mat
	return mi

# iter434: true if (wx,wz) world-pos is over any cached frozen puddle (slip zone).
func _over_ice(wx: float, wz: float) -> bool:
	if _world_root == null or _ice_puddles.is_empty():
		return false
	var ox: float = _world_root.position.x
	var oz: float = _world_root.position.z
	for c in _ice_puddles:
		if not is_instance_valid(c):
			continue
		var r: float = float((c as Node3D).get_meta("ice_radius", 1.0))
		if absf(wx - ((c as Node3D).position.x + ox)) < r and absf(wz - ((c as Node3D).position.z + oz)) < r:
			return true
	return false

# iter434: a small translucent spinning ice cube floating over a slipping entity.
func _spawn_ice_cube(parent: Node3D) -> Node3D:
	var box := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.5, 0.5, 0.5)
	box.mesh = bm
	var mt := StandardMaterial3D.new()
	mt.albedo_color = Color(0.62, 0.86, 1.0, 0.55)
	mt.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mt.metallic = 0.3
	mt.roughness = 0.08
	box.material_override = mt
	box.position = Vector3(0, 1.5, 0)
	box.rotation = Vector3(0.4, 0.4, 0.0)
	parent.add_child(box)
	box.create_tween().set_loops().tween_property(box, "rotation:y", box.rotation.y + TAU, 2.0)
	return box

func _make_puddle(d: float, gx: float, radius: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(radius * 2.0, radius * 2.0)
	qm.orientation = PlaneMesh.FACE_Y
	mi.mesh = qm
	var pos: Vector3 = _terr_vertex(gx, -d)
	mi.position = Vector3(pos.x, pos.y + 0.04, pos.z)
	var mat := StandardMaterial3D.new()
	# iter402: soft radial water texture (was a hard flat blue rectangle).
	if ResourceLoader.exists("res://assets/sprites/fx/puddle.png"):
		mat.albedo_texture = load("res://assets/sprites/fx/puddle.png")
	mat.albedo_color = Color(1, 1, 1, 0.85)
	mat.metallic = 0.5
	mat.roughness = 0.12
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# terrain: mountain puddles are FROZEN ICE — frosty pale-cyan, mostly opaque, matte.
	var _pt: Dictionary = TerrainThemes.get_theme(_level_def.terrain if _level_def != null else "frontier")
	if String(_pt.get("puddle_style", "water")) == "ice":
		mat.albedo_color = Color(0.82, 0.92, 0.98, 0.95)
		mat.metallic = 0.15
		mat.roughness = 0.55
		mi.set_meta("is_ice", true)            # iter434: slip trigger
		mi.set_meta("ice_radius", radius)
	mi.material_override = mat
	return mi

# Advance the posse through the static world: translate WorldRoot by the inverse of
# the path motion (z = distance recedes the world; x = -path_lateral keeps the curve
# centred under the fixed camera). z wraps by the period so the world is endless.
# The posse rides the hills via y.
func _update_world_root() -> void:
	if _world_root == null:
		return
	_world_root.position = Vector3(
		-_path_lateral(_level_distance), 0.0, fposmod(_level_distance, PATH_PATTERN_LEN))
	var hy: float = _hill_y(_level_distance)
	if cowboy_3d != null:
		cowboy_3d.position.y = POSSE_BASE_Y + hy
	for f in _followers:
		if is_instance_valid(f) and not f.get_meta("falling", false):
			f.position.y = POSSE_BASE_Y + hy
	_check_puddle_splash()

# Posse members that stray over an authored pit (the hole passing under the posse)
# fall in — a two-way hazard once outlaws are placed in the world too.
func _check_authored_holes(delta: float) -> void:
	# iter401: the posse is a crowd now (no per-follower nodes), so losing members to
	# a hole = decrementing the count while the leader's lane overlaps the pit. The
	# mob shrinks to match; lose ~2/sec so a brush with a hole costs a few members.
	if _level_state != LevelState.PLAYING or _posse_count_3d <= 1:
		return
	var dd: float = fposmod(_level_distance, PATH_PATTERN_LEN)
	var over: bool = false
	var hx0: float = 0.0
	var hx1: float = 0.0
	var hfill: String = "fudge"
	for hi in range(_HOLES.size()):
		var h: Dictionary = _HOLES[hi]
		# A pit "covers" the crowd when the crowd's x-span (leader ± COWBOY_X_BOUND)
		# overlaps the pit's x-range while the pit is at the posse's distance.
		var crowd_l: float = cowboy_3d.position.x - COWBOY_X_BOUND
		var crowd_r: float = cowboy_3d.position.x + COWBOY_X_BOUND
		if dd >= h["d0"] and dd <= h["d1"] \
		and crowd_r >= float(h["x0"]) and crowd_l <= float(h["x1"]):
			over = true
			hx0 = float(h["x0"]); hx1 = float(h["x1"])
			hfill = _pit_fill_for(hi)
			break
	if not over:
		_hole_lose_accum = 0.0
		_over_hole = false
		_hole_dropped_this_visit = 0
		return
	# winflow: IMMEDIATE fall-on-contact. The posse is a COUNT spread evenly across
	# the crowd x-span (leader ± COWBOY_X_BOUND, so span = 2*COWBOY_X_BOUND). The
	# fraction of that span overlapping the pit = the fraction of members standing
	# over the hole RIGHT NOW. We drop floor(frac * count) members the instant they
	# overlap — so walking the whole crowd into a pit dumps nearly the whole crowd
	# within a frame or two, not a slow 2/sec drip. _hole_dropped_this_visit tracks
	# the cumulative drop for this visit so each frame only sheds the *new* increment
	# as the crowd shifts deeper in.
	if not _over_hole:
		_over_hole = true
		_hole_dropped_this_visit = 0
		if get_node_or_null("/root/AudioBus") and AudioBus.has_method("play_sfx"):
			AudioBus.play_sfx("hole_fall")
	var span: float = 2.0 * COWBOY_X_BOUND
	var crowd_l2: float = cowboy_3d.position.x - COWBOY_X_BOUND
	var crowd_r2: float = cowboy_3d.position.x + COWBOY_X_BOUND
	var overlap: float = minf(crowd_r2, hx1) - maxf(crowd_l2, hx0)
	var frac: float = clampf(overlap / span, 0.0, 1.0)
	# Total members the pit should have swallowed by now (cap to leave the leader).
	var present: int = _posse_count_3d + _hole_dropped_this_visit
	var target_dropped: int = mini(present - 1, int(floor(frac * float(present))))
	var drop_now: int = maxi(0, target_dropped - _hole_dropped_this_visit)
	if drop_now <= 0:
		return
	drop_now = mini(drop_now, _posse_count_3d - 1)   # never drop the leader
	if drop_now <= 0:
		return
	_posse_count_3d = maxi(0, _posse_count_3d - drop_now)
	_hole_dropped_this_visit += drop_now
	_sync_followers_to_count(_posse_count_3d)
	DebugLog.add("pit[%s]: dropped %d members (frac=%.2f, posse→%d)" % [hfill, drop_now, frac, _posse_count_3d])
	# Cap the number of spawned falling sprites + splashes per frame (perf): show a
	# representative sample, not one node per dropped member.
	var visible: int = mini(drop_now, 12)
	for i in range(visible):
		var fx: float = _rng.randf_range(maxf(crowd_l2, hx0), minf(crowd_r2, hx1))
		var fz: float = cowboy_3d.position.z + _rng.randf_range(-0.6, 0.6)
		_spawn_falling_cowboy(Vector3(fx, cowboy_3d.position.y, fz))
		_spawn_pit_splash(Vector3(fx, cowboy_3d.position.y, fz), hfill)
	_refresh_hud()
	if _posse_count_3d <= 0:
		_show_fail()

# A posse member tumbling into a pit (visual; the whistle plays once on pit entry).
func _spawn_falling_cowboy(pos: Vector3) -> void:
	var c := Sprite3D.new()
	c.texture = COWBOY_TEXTURE_LVL3D
	c.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	c.shaded = false
	c.pixel_size = COWBOY_PIXEL_SIZE
	c.position = Vector3(pos.x, pos.y + 0.3, pos.z)   # start slightly raised
	c.scale = Vector3.ONE * 1.15                        # pop bigger, then shrink as it drops
	popups_root.add_child(c)
	var t := c.create_tween()
	t.set_parallel(true)
	# Drop deep into the dark pit over ~0.8s so the tumble is clearly visible.
	t.tween_property(c, "position:y", pos.y - 7.0, 0.8).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.tween_property(c, "scale", Vector3.ONE * 0.15, 0.8)
	# Hold opacity, then fade only in the final stretch (was fading immediately).
	t.tween_property(c, "modulate:a", 0.0, 0.3).set_delay(0.5)
	t.chain().tween_callback(c.queue_free)

# winflow: a quick fall-in SPLASH at the pit entry, tinted to the candy fill.
#   fudge = brown gloopy blobs (slow, heavy, little spread)
#   honey = golden droplets/strings (taller, slower fall, stringy)
#   soda  = white foam + fizz (fast, wide, light)
# Cheap CPUParticles3D one-shot, capped low; auto-frees after its lifetime.
const _PIT_SPLASH_LIFETIME: float = 0.7
func _spawn_pit_splash(pos: Vector3, fill: String) -> void:
	var tint: Color = _PIT_TINTS.get(fill, Color(0.5, 0.4, 0.3))
	var p := CPUParticles3D.new()
	p.position = Vector3(pos.x, pos.y + 0.1, pos.z)
	p.emitting = true
	p.one_shot = true
	p.explosiveness = 1.0
	p.lifetime = _PIT_SPLASH_LIFETIME
	p.local_coords = false
	p.direction = Vector3(0, 1, 0)
	p.gravity = Vector3(0, -9.0, 0)
	p.mesh = SphereMesh.new()
	p.color = tint
	# Per-fill flavour.
	match fill:
		"honey":
			p.amount = 10
			p.initial_velocity_min = 1.6
			p.initial_velocity_max = 3.0
			p.spread = 18.0
			p.scale_amount_min = 0.12
			p.scale_amount_max = 0.22
			p.gravity = Vector3(0, -6.0, 0)   # honey falls slow / stringy
		"soda":
			p.amount = 16
			p.initial_velocity_min = 2.6
			p.initial_velocity_max = 4.8
			p.spread = 42.0                    # wide foamy fizz
			p.scale_amount_min = 0.06
			p.scale_amount_max = 0.14
		_:  # fudge (default)
			p.amount = 12
			p.initial_velocity_min = 1.2
			p.initial_velocity_max = 2.6
			p.spread = 24.0
			p.scale_amount_min = 0.14
			p.scale_amount_max = 0.26
			p.gravity = Vector3(0, -11.0, 0)   # heavy gloop drops fast
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = tint
	(p.mesh as SphereMesh).material = mat
	popups_root.add_child(p)
	var ft := p.create_tween()
	ft.tween_interval(_PIT_SPLASH_LIFETIME + 0.2)
	ft.tween_callback(p.queue_free)

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

# iter410: per-frame bull behavior. Charges toward the posse (faster than other
# obstacles); on contact it gores a chunk of the posse. When confused (a red gate
# flipped blue) it veers off the track via its curve-lane base and despawns.
func _update_bull(bull: Node3D, motion_delta: float, delta: float) -> void:
	if bull.get_meta("confused", false):
		bull.position.z += OBSTACLE_SPEED * BULL_CONFUSED_FWD_MULT * motion_delta
		var dir: float = bull.get_meta("flee_dir", 1.0)
		# Drift the curve-lane base (not position.x directly) so the path offset,
		# re-applied each frame in _apply_path_curve, doesn't snap it back.
		var lx: float = bull.get_meta("lane_x", bull.position.x) + dir * BULL_DRIFT_SPEED * delta
		bull.set_meta("lane_x", lx)
		if absf(lx) > 13.0 or bull.position.z > OBSTACLE_DESPAWN_Z:
			bull.queue_free()
		return
	bull.position.z += OBSTACLE_SPEED * BULL_CHARGE_MULT * motion_delta
	if bull.position.z > cowboy_3d.position.z - 0.4:
		# Gore: rip a chunk out of the posse, then the bull is spent.
		_posse_count_3d = maxi(0, _posse_count_3d - BULL_CONTACT_POSSE_LOSS)
		_refresh_hud()
		_spawn_impact_blast(bull.position + Vector3(0, 1.0, 0))
		bull.queue_free()
		if _posse_count_3d <= 0:
			_show_fail()

func _confuse_all_bulls() -> void:
	for c in obstacles_root.get_children():
		if c is Node3D and c.get_meta("is_bull", false) and not c.get_meta("confused", false):
			c.set_meta("confused", true)
			c.set_meta("flee_dir", -1.0 if c.position.x < 0.0 else 1.0)  # toward nearer edge
			_spawn_popup_3d(c.position + Vector3(0, 1.4, 0), "SPOOKED!", Color(0.6, 0.9, 1.0, 1), 44)

# iter411: spawn a destructible chicken coop (decorative; bursts on destroy).
func _spawn_chicken_coop() -> void:
	var lane_x: float = _rng.randf_range(-COWBOY_X_BOUND * 0.8, COWBOY_X_BOUND * 0.8)
	var coop: MeshInstance3D = _obstacle_prop("chicken_coop", lane_x)
	coop.set_meta("is_coop", true)
	coop.set_meta("hp", COOP_HP)
	obstacles_root.add_child(coop)
	if get_node_or_null("/root/AudioBus") and AudioBus.has_method("play_sfx"):
		AudioBus.play_sfx("chicken_cluck")   # iter413: clucking as the coop arrives

# Bust: 8 chickens scatter outward + a cloud of tumbling feathers (the visual
# distraction). All in popups_root so they aren't treated as bullets/obstacles.
func _bust_coop(pos: Vector3) -> void:
	if get_node_or_null("/root/AudioBus") and AudioBus.has_method("play_sfx"):
		AudioBus.play_sfx("chicken_bust")
		AudioBus.play_sfx("feather_poof")   # iter413
	for i in range(8):
		var c := Sprite3D.new()
		c.texture = CHICKEN_TEX[_rng.randi() % CHICKEN_TEX.size()]
		c.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		c.shaded = false
		c.pixel_size = 0.9 / float(maxi(c.texture.get_height(), 1))   # ~0.9 units tall
		c.position = pos + Vector3(_rng.randf_range(-0.4, 0.4), 0.2, _rng.randf_range(-0.3, 0.3))
		if _rng.randf() < 0.5:
			c.flip_h = true
		popups_root.add_child(c)
		var ang: float = _rng.randf() * TAU
		var dist: float = _rng.randf_range(2.5, 5.5)
		var dest: Vector3 = c.position + Vector3(cos(ang) * dist, 0.0, sin(ang) * dist * 0.5)
		var run: float = _rng.randf_range(2.2, 3.2)
		var t := c.create_tween()
		t.set_parallel(true)
		t.tween_property(c, "position:x", dest.x, run).set_trans(Tween.TRANS_SINE)
		t.tween_property(c, "position:z", dest.z, run).set_trans(Tween.TRANS_SINE)
		# panicked hop
		var hop := c.create_tween().set_loops(int(run / 0.3))
		hop.tween_property(c, "position:y", c.position.y + 0.35, 0.15).set_trans(Tween.TRANS_SINE)
		hop.tween_property(c, "position:y", c.position.y, 0.15).set_trans(Tween.TRANS_SINE)
		var ft := c.create_tween()
		ft.tween_interval(run)
		ft.tween_property(c, "modulate:a", 0.0, 0.5)
		ft.tween_callback(c.queue_free)
	for i in range(16):
		var f := Sprite3D.new()
		f.texture = FEATHER_TEX[_rng.randi() % FEATHER_TEX.size()]
		# NOT billboarded — billboard rebuilds the basis each frame and would kill the
		# tumble. Face roughly toward the (down-tilted) camera + spin rotation.z.
		f.shaded = false
		f.no_depth_test = true
		f.rotation = Vector3(deg_to_rad(-35.0), 0.0, _rng.randf() * TAU)
		f.pixel_size = 0.55 / float(maxi(f.texture.get_height(), 1))
		f.position = pos + Vector3(0, 1.0, 0)
		popups_root.add_child(f)
		var ang2: float = _rng.randf() * TAU
		var up: float = _rng.randf_range(1.6, 3.2)
		var spread: float = _rng.randf_range(1.0, 3.0)
		var apex: Vector3 = f.position + Vector3(cos(ang2) * spread, up, sin(ang2) * spread * 0.6)
		var land: Vector3 = apex + Vector3(cos(ang2) * spread * 0.4, -up - 1.0, sin(ang2) * spread * 0.4)
		var fall := _rng.randf_range(1.6, 2.6)
		var t2 := f.create_tween()
		t2.tween_property(f, "position", apex, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		t2.tween_property(f, "position", land, fall).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		# Continuous tumble (rotation.z is in the sprite plane → reads as spinning).
		var spin := f.create_tween().set_loops()
		var dir: float = 1.0 if _rng.randf() < 0.5 else -1.0
		spin.tween_property(f, "rotation:z", f.rotation.z + dir * TAU, _rng.randf_range(0.7, 1.3))
		var fade := f.create_tween()
		fade.tween_interval(0.45 + fall - 0.5)
		fade.tween_property(f, "modulate:a", 0.0, 0.5)
		fade.tween_callback(f.queue_free)

func _spawn_obstacle() -> void:
	var lane_x: float = _rng.randf_range(-COWBOY_X_BOUND * 0.85,
		COWBOY_X_BOUND * 0.85)
	var pick: int = _rng.randi() % 4
	var obstacle: Node3D
	# Iter 334: all four obstacle types are now breathing sprites (barrel,
	# cactus, bull were crude CSG boxes/cylinders; tumbleweed was already a
	# sprite since iter 179). Sprites exist in assets/sprites/props.
	match pick:
		ObstacleType.BARREL:
			obstacle = _obstacle_prop("barrel", lane_x)
		ObstacleType.CACTUS:
			# Random cactus variant for shoulder variety.
			var cslug: String = ["cactus_saguaro", "cactus_barrel", "cactus_prickly"][_rng.randi() % 3]
			obstacle = _obstacle_prop(cslug, lane_x)
		ObstacleType.TUMBLEWEED:
			var tw: MeshInstance3D = _obstacle_prop("tumbleweed", lane_x)
			var tw_mat: ShaderMaterial = tw.material_override
			if tw_mat != null:
				tw_mat.set_shader_parameter("rotation_mode", 1)   # UV-spin = rolling
				tw_mat.set_shader_parameter("rotation_speed", 0.6)
			tw.position.y = 0.9  # ride a touch above ground so it reads as rolling
			obstacle = tw
		_:  # BULL
			# winflow R3: suppress bulls during the opening grace window so the
			# player reaches + crosses the first GATE (growing the posse) before
			# any bull charges. Without this a first-wave bull can gore a tiny
			# starting posse to zero on L2. During grace, substitute a harmless
			# barrel so the obstacle cadence/feel is unchanged.
			var _bull_grace: float = BULL_GRACE_LEVEL2 if _level_num == 2 else BULL_GRACE_DEFAULT
			if _level_elapsed < _bull_grace:
				obstacle = _obstacle_prop("barrel", lane_x)
			else:
				obstacle = _obstacle_prop("bull", lane_x)
				obstacle.set_meta("is_bull", true)   # iter410: charging hazard, not a static prop
				obstacle.set_meta("hp", BULL_HP)
				obstacle.set_meta("confused", false)
				if not _first_bull_logged:
					_first_bull_logged = true
					DebugLog.add("first bull spawn: level=%d t=%.1fs dist=%.1f (grace=%.1fs)"
						% [_level_num, _level_elapsed, _level_distance, _bull_grace])
				if get_node_or_null("/root/AudioBus") and AudioBus.has_method("play_sfx"):
					AudioBus.play_sfx("bull_snort")   # iter411: angry snort as it charges in
					AudioBus.play_sfx("bull_charge")  # iter413: galloping hooves
	obstacles_root.add_child(obstacle)

# Iter 334: build a registry-driven breathing-sprite obstacle, grounded so its
# bottom sits at y≈0 and placed at the far spawn line on the given lane.
func _obstacle_prop(slug: String, lane_x: float) -> MeshInstance3D:
	var entry: Dictionary = PROP_TEX_REGISTRY[slug]
	var prop: MeshInstance3D = _make_breathing_prop(
		_load_prop_tex(slug), entry.w, entry.h,
		entry.get("sway_amp", 0.0), 1.5, entry.get("bob_amp", 0.012), 2.2)
	prop.position = Vector3(lane_x, float(entry.h) * 0.5, OBSTACLE_SPAWN_Z)
	return prop

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

# Candy projectile sprites (baked — PROTOTYPE art, see memory
# project_candy_shader_licensing). Bullets are billboarded Sprite3Ds using
# these per fire mode instead of plain CSG spheres.
const _CANDY_DIR := "res://assets/sprites/candy/"
const CANDY_BULLET_TEX := {
	FireMode.CANDY: ["candy_red.png", "candy_green.png", "candy_blue.png", "candy_amber.png"],
	FireMode.RIFLE: ["candy_choc_stripe.png"],
	FireMode.FROSTBITE: ["candy_freezeray.png"],
	FireMode.FRENZY: ["candy_red.png", "candy_green.png", "candy_blue.png", "candy_amber.png",
		"candy_cotton.png", "candy_bomb.png", "candy_fireball.png", "candy_jawbreaker.png"],
	FireMode.RAINBOW: ["../props/candy_rainbow.png"],
}

# iter404: the chain-lightning overlay sits on the UI CanvasLayer, behind the HUD
# controls (added first) so bolts draw over the 3D view but under the HUD.
func _build_frost_bolts() -> void:
	var ui: Node = get_node_or_null("UI")
	if ui == null:
		return
	_frost_bolts = FrostBoltsScript.new()
	_frost_bolts.name = "FrostBolts"
	ui.add_child(_frost_bolts)
	ui.move_child(_frost_bolts, 0)

func _build_manga_fx() -> void:
	var ui: Node = get_node_or_null("UI")
	if ui == null:
		return
	_manga_fx = MangaFxScript.new()
	_manga_fx.name = "MangaFx"
	ui.add_child(_manga_fx)
	ui.move_child(_manga_fx, 0)

# Up to `n` live enemies in front of `from`, nearest first — the chain targets.
func _frost_chain_targets(from: Vector3, n: int) -> Array:
	var cand: Array = []
	for o in outlaws_root.get_children():
		if o is Node3D and not o.get_meta("falling", false) and not o.get_meta("dying", false) \
		and o.position.z < cowboy_3d.position.z:
			cand.append(o.position)
	for b in boss_root.get_children():
		if b is Node3D and b.position.z < cowboy_3d.position.z:
			cand.append((b as Node3D).position)
	cand.sort_custom(func(a, c): return from.distance_squared_to(a) < from.distance_squared_to(c))
	return cand.slice(0, n)

# Emit one frost chain from the leader's muzzle through the nearest enemies.
# iter431: every posse member is firing FROSTBITE, so the chain emits from the leader
# AND a bounded sample of crowd members (mirrors _emit_rainbow_chain), not just the leader.
func _emit_frost_chain() -> void:
	if _frost_bolts == null or camera == null or cowboy_3d == null:
		return
	_emit_frost_chain_from(cowboy_3d.position)
	if _posse_crowd != null:
		var origins: PackedVector3Array = _posse_crowd.call("member_origins")
		var n: int = mini(origins.size(), KIMMY_CHAIN_MEMBERS)
		for i in range(n):
			var o: Vector3 = origins[i]
			_emit_frost_chain_from(
				Vector3(_posse_crowd.position.x + o.x, 0.0, _posse_crowd.position.z + o.z))

func _emit_frost_chain_from(origin: Vector3) -> void:
	var muzzle: Vector3 = origin + Vector3(0, 0.95, 0)
	if camera.is_position_behind(muzzle):
		return
	var pts := PackedVector2Array()
	pts.append(camera.unproject_position(muzzle))
	var targets: Array = _frost_chain_targets(muzzle, 3)
	if targets.is_empty():
		var fwd := Vector3(origin.x, 0.95, _bullet_despawn_z)
		if not camera.is_position_behind(fwd):
			pts.append(camera.unproject_position(fwd))
	else:
		for t in targets:
			var tp: Vector3 = t + Vector3(0, 0.9, 0)
			if not camera.is_position_behind(tp):
				pts.append(camera.unproject_position(tp))
	if pts.size() >= 2:
		_frost_bolts.call("add_chain", pts, 1.0)

# kimmy: rainbow prism-chain overlay, mirrors _build_frost_bolts.
func _build_rainbow_bolts() -> void:
	var ui: Node = get_node_or_null("UI")
	if ui == null:
		return
	_rainbow_bolts = RainbowBoltsScript.new()
	_rainbow_bolts.name = "RainbowBolts"
	ui.add_child(_rainbow_bolts)
	ui.move_child(_rainbow_bolts, 0)

const VFX_RAINBOW_SHOCK := preload("res://assets/sprites/props/vfx_rainbow_shock.png")

# kimmy: every posse member is equipped with the Rainbow weapon, so the prism
# chain fires from the leader AND a bounded sample of crowd members — rainbow
# bolts crackle across the whole posse front, not just the leader.
const KIMMY_CHAIN_MEMBERS: int = 4   # extra crowd origins that emit a chain per shot
func _emit_rainbow_chain() -> void:
	if _rainbow_bolts == null or camera == null or cowboy_3d == null:
		return
	# Leader chain (carries the shock pops so they don't stack per member).
	_emit_rainbow_chain_from(cowboy_3d.position, true)
	if _posse_crowd != null:
		var origins: PackedVector3Array = _posse_crowd.call("member_origins")
		var n: int = mini(origins.size(), KIMMY_CHAIN_MEMBERS)
		for i in range(n):
			var o: Vector3 = origins[i]
			_emit_rainbow_chain_from(
				Vector3(_posse_crowd.position.x + o.x, 0.0, _posse_crowd.position.z + o.z), false)

# Emit one prism chain from `origin`'s muzzle through nearby enemies (reuses
# _frost_chain_targets). `with_shock` adds an additive Skittles shock pop per link.
func _emit_rainbow_chain_from(origin: Vector3, with_shock: bool) -> void:
	var muzzle: Vector3 = origin + Vector3(0, 0.95, 0)
	if camera.is_position_behind(muzzle):
		return
	var pts := PackedVector2Array()
	pts.append(camera.unproject_position(muzzle))
	var targets: Array = _frost_chain_targets(muzzle, 3)
	if targets.is_empty():
		var fwd := Vector3(origin.x, 0.95, _bullet_despawn_z)
		if not camera.is_position_behind(fwd):
			pts.append(camera.unproject_position(fwd))
	else:
		for t in targets:
			var tp: Vector3 = t + Vector3(0, 0.9, 0)
			if not camera.is_position_behind(tp):
				pts.append(camera.unproject_position(tp))
			if with_shock:
				_spawn_rainbow_shock(t + Vector3(0, 0.9, 0))
	if pts.size() >= 2:
		_rainbow_bolts.call("add_chain", pts, 1.0)

# kimmy: premium additive rainbow shockwave ring at an enemy hit (Skittles ring).
func _spawn_rainbow_shock(pos: Vector3) -> void:
	var s := Sprite3D.new()
	s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	s.shaded = false
	s.no_depth_test = true
	s.render_priority = 7
	s.pixel_size = 0.0020
	s.position = pos
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_texture = VFX_RAINBOW_SHOCK
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	s.material_override = mat
	popups_root.add_child(s)
	var t := create_tween().set_parallel(true)
	t.tween_property(s, "pixel_size", 0.0060, 0.28) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(s, "modulate:a", 0.0, 0.28)
	t.chain().tween_callback(s.queue_free)

# ============================================================================
# weapon fx: the 5 owner-approved fire-FX. Mobile-safe ONLY — additive 2D-canvas
# overlays, CPUParticles3D with a mesh + additive material, and additive Sprite3D
# billboards. NO custom spatial shaders (Android white-rects them). All FX are
# bounded (capped particle counts, short lifetimes, freed via a one-shot timer) so
# big-posse FPS holds, and they're fire-rate-gated by _spawn_bullet's cadence.
#
# Each FX is a reusable _emit_<fx>() called from _spawn_bullet. The assigned ones
# fire from the leader + a bounded crowd-member sample (mirrors _emit_rainbow_chain
# / KIMMY_CHAIN_MEMBERS) so the effect crackles across the posse front. The two
# unassigned (sparkle-swarm, confetti-cannon) are callable for future roster weapons.
# ============================================================================

# Candy palette shared by the new FX (gumdrop pellets, sparkles, confetti).
# (Not a const — a PackedColorArray() call isn't a constant expression in GDScript.)
var WFX_CANDY_COLORS: PackedColorArray = PackedColorArray([
	Color(1, 0.25, 0.25), Color(1, 0.82, 0.25), Color(0.35, 1, 0.42),
	Color(0.3, 0.65, 1), Color(0.78, 0.38, 1), Color(1, 0.55, 0.85)])
const WFX_CREW_SAMPLE: int = 4   # extra crowd origins that emit per shot (matches KIMMY_CHAIN_MEMBERS)

# Bounded crowd-origin sample (leader + up to WFX_CREW_SAMPLE members), as world
# positions. Mirrors the loop in _emit_rainbow_chain / _spawn_bullet.
func _wfx_emit_origins() -> PackedVector3Array:
	var out := PackedVector3Array()
	if cowboy_3d != null:
		out.append(cowboy_3d.position)
	if _posse_crowd != null:
		var origins: PackedVector3Array = _posse_crowd.call("member_origins")
		var n: int = mini(origins.size(), WFX_CREW_SAMPLE)
		for i in range(n):
			var o: Vector3 = origins[i]
			out.append(Vector3(_posse_crowd.position.x + o.x, 0.0, _posse_crowd.position.z + o.z))
	return out

# Build an additive, unshaded, billboarded glow material backed by the reusable
# soft-glow texture. Used as the mesh material for the new CPUParticles3D bursts.
# (A meshless CPUParticles3D renders NOTHING, so every burst gets a glow quad.)
func _wfx_glow_quad(size: float) -> QuadMesh:
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.albedo_texture = _kimmy_soft_glow()
	mat.vertex_color_use_as_albedo = true
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	quad.material = mat
	return quad

# Quick additive muzzle-bloom pop at a world position (small soft glow that pops
# in scale + fades). Reused by the buckshot scatter + gatling bloom.
func _wfx_muzzle_pop(pos: Vector3, tint: Color, start_px: float = 0.010, end_px: float = 0.026, dur: float = 0.18) -> void:
	var s := Sprite3D.new()
	s.texture = _kimmy_soft_glow()
	s.shaded = false
	s.no_depth_test = true
	s.render_priority = 7
	s.modulate = tint
	s.pixel_size = start_px
	s.position = pos
	var mat := StandardMaterial3D.new()
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_texture = _kimmy_soft_glow()
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	s.material_override = mat
	popups_root.add_child(s)
	var t := s.create_tween().set_parallel(true)
	t.tween_property(s, "pixel_size", end_px, dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(s, "modulate:a", 0.0, dur)
	t.chain().tween_callback(s.queue_free)

# --- FX 1: Gumdrop Buckshot Scatter (wired to FireMode.CANDY) ----------------
# One-shot cone/sphere burst of multicolor gumdrop pellets (additive glow quads,
# candy color_initial_ramp) + a quick additive muzzle-bloom pop at the muzzle.
func _emit_buckshot_scatter() -> void:
	if camera == null:
		return
	for origin in _wfx_emit_origins():
		_emit_buckshot_from(origin + Vector3(0, 0.95, 0))

func _emit_buckshot_from(muzzle: Vector3) -> void:
	_wfx_muzzle_pop(muzzle, Color(1.0, 0.85, 0.5, 1.0))
	var p := CPUParticles3D.new()
	p.position = muzzle
	p.amount = 14
	p.lifetime = 0.45
	p.one_shot = true
	p.explosiveness = 1.0
	p.spread = 38.0                      # forward cone toward the enemies
	p.direction = Vector3(0, 0.25, -1)   # downrange (−z) with a slight lift
	p.initial_velocity_min = 6.0
	p.initial_velocity_max = 11.0
	p.gravity = Vector3(0, -7.0, 0)
	p.damping_min = 0.5
	p.damping_max = 1.5
	p.scale_amount_min = 0.18
	p.scale_amount_max = 0.34
	var candy := Gradient.new()
	candy.offsets = PackedFloat32Array([0.0, 0.2, 0.4, 0.6, 0.8, 1.0])
	candy.colors = WFX_CANDY_COLORS
	p.color_initial_ramp = candy
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 1))
	fade.set_color(1, Color(1, 1, 1, 0))
	p.color_ramp = fade
	p.mesh = _wfx_glow_quad(0.4)
	popups_root.add_child(p)
	p.emitting = true
	get_tree().create_timer(1.0).timeout.connect(p.queue_free)

# --- FX 2: Rainbow Comet Trail (wired to FireMode.RIFLE) ---------------------
# Bright additive comet head + fading hue-scrolling ribbon launched downrange.
# Drawn as a 2D-canvas additive streak (comet_streak.gd) from screen-projected
# muzzle → target (or forward) points, mirroring the frost/rainbow overlays.
func _emit_comet_trail() -> void:
	if _comet_streak == null or camera == null:
		return
	for origin in _wfx_emit_origins():
		_emit_comet_from(origin + Vector3(0, 0.95, 0))

func _emit_comet_from(muzzle: Vector3) -> void:
	if camera.is_position_behind(muzzle):
		return
	var a: Vector2 = camera.unproject_position(muzzle)
	var tip3: Vector3
	var targets: Array = _frost_chain_targets(muzzle, 1)
	if targets.is_empty():
		tip3 = Vector3(muzzle.x, 0.95, _bullet_despawn_z)
	else:
		tip3 = (targets[0] as Vector3) + Vector3(0, 0.9, 0)
	if camera.is_position_behind(tip3):
		return
	var b: Vector2 = camera.unproject_position(tip3)
	_comet_streak.call("add_streak", a, b, _rng.randf())

# --- FX 3: Gumball Gatling Bloom (wired to FireMode.FRENZY) -------------------
# Stuttering additive muzzle-flash (rapid bloom pops) + a fast forward tracer jet
# of small additive particles.
func _emit_gatling_bloom() -> void:
	if camera == null:
		return
	for origin in _wfx_emit_origins():
		_emit_gatling_from(origin + Vector3(0, 0.95, 0))

func _emit_gatling_from(muzzle: Vector3) -> void:
	# Stuttering flash: 2 quick bloom pops at slightly different scales.
	_wfx_muzzle_pop(muzzle, Color(1.0, 0.7, 0.9, 1.0), 0.006, 0.016, 0.09)
	get_tree().create_timer(0.05).timeout.connect(
		_wfx_muzzle_pop.bind(muzzle, Color(1.0, 0.9, 0.6, 1.0), 0.008, 0.020, 0.10))
	# Fast forward tracer jet (small, short-lived, narrow cone).
	var p := CPUParticles3D.new()
	p.position = muzzle
	p.amount = 10
	p.lifetime = 0.30
	p.one_shot = true
	p.explosiveness = 0.85
	p.spread = 8.0
	p.direction = Vector3(0, 0.05, -1)
	p.initial_velocity_min = 16.0
	p.initial_velocity_max = 24.0
	p.gravity = Vector3.ZERO
	p.scale_amount_min = 0.12
	p.scale_amount_max = 0.22
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	ramp.colors = PackedColorArray([Color(1, 0.55, 0.85), Color(1, 0.85, 0.4), Color(0.5, 0.8, 1)])
	p.color_initial_ramp = ramp
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 1))
	fade.set_color(1, Color(1, 1, 1, 0))
	p.color_ramp = fade
	p.mesh = _wfx_glow_quad(0.3)
	popups_root.add_child(p)
	p.emitting = true
	get_tree().create_timer(0.8).timeout.connect(p.queue_free)

# --- FX 4: Homing Sparkle Swarm (reusable, UNASSIGNED) -----------------------
# TODO(roster): wire to a future homing-sparkle weapon FireMode. CPUParticles3D
# sparkles that spiral/curve toward the nearest enemy. CPUParticles3D has no true
# per-particle homing, so we approximate: aim the emission cone at the target,
# add a tangential (orbit) velocity for the spiral, and a gentle attractor-ish
# inward pull via gravity pointed at the target. Bounded + auto-freed.
func _emit_sparkle_swarm() -> void:
	if camera == null:
		return
	for origin in _wfx_emit_origins():
		_emit_sparkle_swarm_from(origin + Vector3(0, 0.95, 0))

func _emit_sparkle_swarm_from(muzzle: Vector3) -> void:
	var targets: Array = _frost_chain_targets(muzzle, 1)
	var target: Vector3
	if targets.is_empty():
		target = Vector3(muzzle.x, 0.95, _bullet_despawn_z)
	else:
		target = (targets[0] as Vector3) + Vector3(0, 0.9, 0)
	var to_t: Vector3 = (target - muzzle)
	var dir: Vector3 = to_t.normalized() if to_t.length() > 0.01 else Vector3(0, 0, -1)
	var p := CPUParticles3D.new()
	p.position = muzzle
	p.amount = 16
	p.lifetime = 0.6
	p.one_shot = true
	p.explosiveness = 0.7
	p.spread = 22.0
	p.direction = dir
	p.initial_velocity_min = 5.0
	p.initial_velocity_max = 9.0
	# Tangential velocity → orbit/spiral; gravity toward the target → curved homing pull.
	p.tangential_accel_min = 6.0
	p.tangential_accel_max = 12.0
	p.gravity = dir * 14.0
	p.scale_amount_min = 0.12
	p.scale_amount_max = 0.26
	var candy := Gradient.new()
	candy.offsets = PackedFloat32Array([0.0, 0.2, 0.4, 0.6, 0.8, 1.0])
	candy.colors = WFX_CANDY_COLORS
	p.color_initial_ramp = candy
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.7, 1.0])
	fade.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.8), Color(1, 1, 1, 0)])
	p.color_ramp = fade
	p.mesh = _wfx_glow_quad(0.3)
	popups_root.add_child(p)
	p.emitting = true
	get_tree().create_timer(1.2).timeout.connect(p.queue_free)

# --- FX 5: Confetti Cannon (reusable, UNASSIGNED) ----------------------------
# TODO(roster): wire to a future confetti-cannon weapon FireMode. Wide cone of
# flat spinning confetti quads with gravity + candy colors. Uses a plain (alpha)
# QuadMesh so the confetti reads as solid paper flakes rather than glow; particle
# angle/angular-velocity spins them. Bounded + auto-freed.
func _emit_confetti_cannon() -> void:
	if camera == null:
		return
	for origin in _wfx_emit_origins():
		_emit_confetti_from(origin + Vector3(0, 0.95, 0))

func _emit_confetti_from(muzzle: Vector3) -> void:
	var p := CPUParticles3D.new()
	p.position = muzzle
	p.amount = 22
	p.lifetime = 1.1
	p.one_shot = true
	p.explosiveness = 0.95
	p.spread = 55.0
	p.direction = Vector3(0, 0.6, -1)
	p.initial_velocity_min = 6.0
	p.initial_velocity_max = 12.0
	p.gravity = Vector3(0, -9.0, 0)
	p.damping_min = 0.5
	p.damping_max = 1.5
	# Spin the flakes.
	p.angle_min = 0.0
	p.angle_max = 360.0
	p.angular_velocity_min = -360.0
	p.angular_velocity_max = 360.0
	p.scale_amount_min = 0.16
	p.scale_amount_max = 0.30
	var candy := Gradient.new()
	candy.offsets = PackedFloat32Array([0.0, 0.2, 0.4, 0.6, 0.8, 1.0])
	candy.colors = WFX_CANDY_COLORS
	p.color_initial_ramp = candy
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.8, 1.0])
	fade.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	p.color_ramp = fade
	# Flat spinning paper flake — alpha (not additive) so confetti reads as solid.
	var quad := QuadMesh.new()
	quad.size = Vector2(0.28, 0.28)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1, 1, 1, 1)
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED   # flakes visible from both sides
	quad.material = mat
	p.mesh = quad
	popups_root.add_child(p)
	p.emitting = true
	get_tree().create_timer(1.6).timeout.connect(p.queue_free)

# weapon fx: RIFLE rainbow-comet trail overlay builder (mirrors _build_rainbow_bolts).
func _build_comet_streak() -> void:
	var ui: Node = get_node_or_null("UI")
	if ui == null:
		return
	_comet_streak = CometStreakScript.new()
	_comet_streak.name = "CometStreak"
	ui.add_child(_comet_streak)
	ui.move_child(_comet_streak, 0)

# iter409: impact blast on bullet -> gate/prop collision (was missing in gameplay;
# ported from the SP1 testbed). Billboard, draws on top, pops via pixel_size + fades.
const IMPACT_BLAST_TEX := preload("res://assets/sprites/ui/blast.png")
func _spawn_impact_blast(pos: Vector3) -> void:
	var s := Sprite3D.new()
	s.texture = IMPACT_BLAST_TEX
	s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	s.shaded = false
	s.no_depth_test = true
	s.render_priority = 6
	s.pixel_size = 0.0015
	s.position = pos
	popups_root.add_child(s)
	var t := create_tween().set_parallel(true)
	t.tween_property(s, "pixel_size", 0.0040, 0.22) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(s, "modulate:a", 0.0, 0.22)
	t.chain().tween_callback(s.queue_free)

func _spawn_bullet() -> void:
	# Iter 73: gunfire SFX. Single call so multi-dude firing doesn't
	# stack 5 layered samples per shot.
	if get_node_or_null("/root/AudioBus"):
		AudioBus.play_gunfire()
	# iter404: FROSTBITE fires chain lightning through nearby enemies.
	if _fire_mode == FireMode.FROSTBITE:
		_emit_frost_chain()
	# kimmy: RAINBOW fires a rainbow prism chain + additive shock pops.
	if _fire_mode == FireMode.RAINBOW:
		_emit_rainbow_chain()
	# weapon fx: the 3 newly-assigned signature fire-FX.
	if _fire_mode == FireMode.CANDY:
		_emit_buckshot_scatter()    # Gumdrop Buckshot Scatter
	elif _fire_mode == FireMode.RIFLE:
		_emit_comet_trail()         # Rainbow Comet Trail
	elif _fire_mode == FireMode.FRENZY:
		_emit_gatling_bloom()       # Gumball Gatling Bloom
	# iter406: firepower SCALES with the posse. We can't spawn 1000 bullet nodes per
	# shot, so a bounded sample of bullets fires and EACH carries the damage of the
	# members it represents (volley damage ≈ the whole posse's per-member fire). A
	# 1000-posse then tears through a 50-outlaw shield (10 HP each) almost instantly,
	# rather than a 1000-posse firing the same trickle as a 20-posse.
	var crowd_shots: int = 0
	var origins := PackedVector3Array()
	if _posse_crowd != null:
		origins = _posse_crowd.call("member_origins")
		crowd_shots = mini(origins.size(), 24)
	var total_bullets: int = 1 + crowd_shots
	_volley_dmg = maxi(1, int(round(float(_posse_count_3d) / float(total_bullets))))
	# Spawn one bullet at leader.
	_spawn_bullet_at(cowboy_3d.position.x, cowboy_3d.position.z)
	for i in range(crowd_shots):
		var o: Vector3 = origins[randi() % origins.size()]
		_spawn_bullet_at(_posse_crowd.position.x + o.x, _posse_crowd.position.z + o.z)

# Iter 73/88: per-position bullet spawner — bullet visual + size now
# depends on _fire_mode set by iter 88 bonus pickups.
func _spawn_bullet_at(world_x: float, world_z: float) -> void:
	# Billboarded candy sprite (per fire mode) instead of a plain CSG sphere.
	var size_mult: float = 1.4 if _fire_mode == FireMode.RIFLE else (
		1.1 if _fire_mode == FireMode.FROSTBITE else 1.0)
	var paths: Array = CANDY_BULLET_TEX.get(_fire_mode, CANDY_BULLET_TEX[FireMode.CANDY])
	# iter 331: candy art fills ~97-100% of its 512² cell (measured), so a
	# full-frame disk reads MUCH bigger than the old translucent sphere of the
	# same diameter — at 1.2× the bullet was ~65% of the cowboy's width. 0.6×
	# (~0.22 world units) makes it a clearly jelly-bean-sized projectile.
	var world_diam: float = BULLET_PIXEL_SIZE * 2.0 * size_mult * 0.85   # iter402: 0.6 → 0.85 (more visible)
	var bullet: Sprite3D = _make_candy_billboard(paths, world_diam)
	bullet.position = Vector3(world_x, BULLET_SPAWN_Y, world_z - 0.5)
	# iter402b: during the boss fight, guarantee bullets travel PAST the boss so a
	# short-range weapon (e.g. FROSTBITE range −6 == Pete's hold z) can still hit him.
	# iter417: dust/snow weather trims sight range — shorten the despawn distance
	# (less negative). Applied here so it tracks the current weapon's range.
	var despawn: float = _bullet_despawn_z * _weather_range_mult
	if _pete_spawned and boss_root.get_child_count() > 0:
		# Reach the boss wherever he is on his approach, not just at his hold z.
		var bz: float = (boss_root.get_child(0) as Node3D).position.z
		despawn = minf(despawn, bz - 2.0)
	bullet.set_meta("despawn_z", despawn)
	bullet.set_meta("dmg", _volley_dmg)   # iter406: posse-scaled damage
	bullet.set_meta("rainbow", _fire_mode == FireMode.RAINBOW)
	bullets_root.add_child(bullet)

# Shared candy-sprite factory: a camera-facing Sprite3D sized to world_diam,
# picking a random texture from `paths` (filenames under _CANDY_DIR).
func _make_candy_billboard(paths: Array, world_diam: float) -> Sprite3D:
	var tex: Texture2D = load(_CANDY_DIR + str(paths[_rng.randi() % paths.size()]))
	var spr := Sprite3D.new()
	if tex:
		spr.texture = tex
		spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		spr.shaded = false
		spr.pixel_size = world_diam / float(maxi(tex.get_width(), 1))
	return spr

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
