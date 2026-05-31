extends Node2D

# Candy Crush-style world map. A winding path of level nodes sits on the
# 3D terrain plane (terrain_3d_level_select.tscn) — the path itself is
# baked into the dirt texture, so it renders with the camera's
# perspective as part of the ground.
#
# Iter 158: the level nodes are "bound to the terrain". Perspective
# scaling shrinks + haze-fades distant (far-up) nodes, and a soft contact
# shadow under each node grounds it on the dirt. Drag-to-pan was removed
# (all eight nodes fit one screen). Level 2 — boss The Candy Rustler — is
# playable alongside level 1.
#
# Iter 159: Professor Humbug stands at the lower-left as the trailhead
# guide. Tapping him sparks a flourish + a TIP (speech bubble + voice) or,
# now and then, a THOUGHT (thought bubble + harp + voice). Monsieur
# Canard — the gold duck-head on his cane — has his own tap zone and
# quacks. (Flourishes are procedural tweens: a tip-bow, a thought-lean
# and a Canard-wiggle — the three "movements" for Humbug and Canard.
# Veo video flourishes would need the Veo pipeline + credentials, which
# aren't available in this build environment.)

const BuildInfo = preload("res://scripts/build_info.gd")
const GAME_THEME := preload("res://assets/theme.tres")
const HARP_SFX := preload("res://assets/sfx/harp_thought.wav")
# Iter 168: Veo flourish clips, played on tap via a chroma-keyed
# VideoStreamPlayer overlaid on Humbug.
const FLOURISH_CLIPS: Dictionary = {
	"tip": "res://assets/videos/humbug/tip.ogv",
	"thought": "res://assets/videos/humbug/thought.ogv",
	"canard": "res://assets/videos/humbug/canard.ogv",
}
const CHROMAKEY_SHADER := preload("res://shaders/chromakey.gdshader")
# Iter 169: tap-area + grid debug overlay — off now that placements are
# dialed in. Flip to true to re-enable for pixel-precise nudge feedback.
const SHOW_TAP_OVERLAY: bool = false

@onready var level_1_button: Button = $LevelNode1
@onready var level_2_button: Button = $LevelNode2
@onready var back_button: Button = $UI/BackButton
@onready var humbug: TextureButton = $Humbug
@onready var canard_zone: Control = $Humbug/CanardZone

# Perspective scaling for the path tiles. Nodes near TILE_PERSP_HORIZON_Y
# (far up the screen = distant) shrink toward HORIZON_SCALE; nodes near
# FOREGROUND_Y (near the camera) stay full size.
const TILE_PERSP_HORIZON_Y: float = 250.0
const TILE_PERSP_HORIZON_SCALE: float = 0.45
const TILE_PERSP_FOREGROUND_Y: float = 1750.0
const PERSP_TILE_NAMES: Array[String] = [
	"LevelNode1", "DiffLabel1", "Glyph1Hat",
	"LevelNode2", "DiffLabel2", "Glyph2Pickaxe",
	"LevelNode3Locked", "DiffLabel3", "Glyph3Boot",
	"LevelNode4Locked", "DiffLabel4", "Glyph4Wagon",
	"LevelNode5Locked", "LevelNode6Locked",
	"LevelNode7Locked", "LevelNode8Locked",
	"Cowboy",
]
# The tappable level-node buttons — these get a contact shadow.
const LEVEL_NODE_NAMES: Array[String] = [
	"LevelNode1", "LevelNode2",
	"LevelNode3Locked", "LevelNode4Locked",
	"LevelNode5Locked", "LevelNode6Locked",
	"LevelNode7Locked", "LevelNode8Locked",
]

# Iter 339: orbs sit ON the 3D terrain. Each level tile is anchored to a
# plane-LOCAL (x, z) point on the hilly map; _place_orbs_on_terrain() projects
# it through the SubViewport camera so the tiles ride the terrain (and will
# pan/snap with it). Index 0 = level 1 (near), index 7 = level 8 (far). This
# is the general "terrain-anchored object" system props/characters reuse later
# (see memory project_level_select_decoration).
# The level path is a procedural serpentine that recedes toward a vanishing
# point (impression of infinite levels). Orbs are sampled along it; the trail
# is sampled densely so it reads as a smooth CURVE, and runs PAST the last orb
# toward the horizon (fading) for the infinite feel. _path_screen(u) maps
# u (0 = near/bottom .. 1 = horizon) to a screen point; setup ray-casts those
# onto the ground to get terrain anchors, which then pan/snap with the map.
const ORB_COUNT: int = 8
const TRAIL_SAMPLES: int = 72
const ORB_START_S: float = 1.5   # arc length (world units) of level 1 from the path's near end
const ORB_GAP_S: float = 7.0     # world spacing between levels along the path (~10 orb widths)
const PATH_Z_NEAR: float = 4.0   # plane-local z of the path's near end (level 1)
const PATH_Z_FAR: float = -54.0  # ...and its far end (the trail runs off-screen; you swipe to it)
const PATH_AMP: float = 7.0      # switchback half-width
const PATH_SWITCHBACKS: float = 5.0
const VIEW_FOCUS_Z: float = -2.0 # world z where the focused (cowboy's) level sits — near the bottom
var _orb_anchors: Array[Vector2] = []   # plane-local (x, z) per orb
var _trail_anchors: Array[Vector2] = [] # plane-local (x, z) densely along the path
var _path_pts: Array[Vector2] = []      # dense path samples for arc-length lookup
var _path_cum: PackedFloat32Array = PackedFloat32Array()
var _path_s: float = 0.0                # current focus position along the path (arc length)
var _s_min: float = 0.0
var _s_max: float = 0.0
var _drag_dist: float = 0.0             # accumulated drag (px) — tells a pan from a tap
var _focus_level: int = 0               # level the view snaps back to (the cowboy's)
var pan_speed: float = 0.021            # arc-length per drag pixel (tuned on-device)
var snap_dur: float = 1.60              # drift-back tween seconds (tuned on-device)
var snap_delay: float = 5.0             # idle seconds after a gesture before the view drifts back
var _snap_timer: Timer                  # one-shot; fires the drift-back after snap_delay of no input
var _snap_tween: Tween                  # the running drift-back (killed if the user grabs again)
var _touches: Dictionary = {}           # active finger index -> position (1 = pan, 2 = pinch)
var _pinch_base: float = 0.0
var _was_pinch: bool = false
var _zoom: float = 1.0
var _base_fov: float = 70.0
var _humbug_base_scale: Vector2 = Vector2.ONE
const _BREATHING_SHADER: Shader = preload("res://shaders/breathing_prop.gdshader")
const _CREAK_SFX: AudioStream = preload("res://assets/sfx/sign_creak.ogg")
var _props: Array = []                  # [{node, anchor, h}] — swaying, tappable props
var _prop_player: AudioStreamPlayer
var _cowboy_sprite: AnimatedSprite2D    # idle-looping marker on the cowboy's level
var _cowboy_s: float = 0.0              # the cowboy's arc-length position along the path
var _walking: bool = false              # true while the cowboy strides to a selected orb
var _cowboy_half_h: float = 128.0       # half the idle texture height (for grounding his feet)
const COWBOY_SIDE: float = -1.9         # he stands this far to the side of the path/orb
# Iter 344: tap the cowboy → a random one of 6 warm Murderbot reactions; after
# COWBOY_QUICK_TAPS taps inside COWBOY_QUICK_WINDOW he gets abrasively annoyed.
var _cowboy_vo_player: AudioStreamPlayer
var _cowboy_tap_stamps: Array[float] = []
const COWBOY_TAP_LINES: int = 6
const COWBOY_ANNOYED_LINES: int = 6
const COWBOY_QUICK_TAPS: int = 8
const COWBOY_QUICK_WINDOW: float = 2.5
const ORB_NODE_NAMES: Array[String] = [
	"LevelNode1", "LevelNode2", "LevelNode3Locked", "LevelNode4Locked",
	"LevelNode5Locked", "LevelNode6Locked", "LevelNode7Locked", "LevelNode8Locked",
]
const ORB_NEAR_DIST: float = 4.0  # camera distance at which a tile is full-size
const ORB_SIZE_MULT: float = 2.0  # iter339: orbs much bigger (×3 overlapped)
# Iter 339: rendered (Imagen) orb art per level. L1-4 are dual-themed
# (difficulty × terrain); L5-8 share the locked orb.
const ORB_TEX := {1: "orb_l1", 2: "orb_l2", 3: "orb_l3", 4: "orb_l4"}
# Old fixed-position 2D level decorations, retired by the 3D orbs + floating numbers.
const ORB_OLD_DECOR: Array[String] = [
	"DiffLabel1", "DiffLabel2", "DiffLabel3", "DiffLabel4",
	"Glyph1Hat", "Glyph2Pickaxe", "Glyph3Boot", "Glyph4Wagon",
]
const _RYE_FONT := preload("res://assets/fonts/Rye-Regular.ttf")

# Iter 159: Humbug / Canard interaction.
const HUMBUG_TIP_LINES: int = 6      # humbug.tips → humbug_tip_N.mp3
const HUMBUG_THOUGHT_LINES: int = 5  # humbug.thoughts → humbug_thought_N.mp3
const CANARD_QUACKS: int = 3         # canard_quack_0..2.mp3
const HUMBUG_THOUGHT_CHANCE: float = 0.32
const BUBBLE_POS := Vector2(120.0, 920.0)
const BUBBLE_SIZE := Vector2(720.0, 340.0)  # iter 172: enlarged so tip text fits

# Iter 160: easter eggs.
const HUMBUG_EGG_TAPS: int = 6         # accepted taps inside the window → jokes
const HUMBUG_EGG_WINDOW: float = 60.0
const CANARD_EGG_TAPS: int = 8         # iter338: 14 → 8 (more reachable; explosion wasn't triggering)
const POOF_SFX := preload("res://assets/sfx/poof.wav")
const CANARD_HEAD_REGION := Rect2(241.0, 410.0, 100.0, 105.0)  # duck-head in the Humbug PNG (iter 163: tracked the CanardZone nudge)
# Candy-Crush-style short reactions: single tap → one-syllable non-verbal
# (no-repeat); rapid spam (ANNOYED_TAPS / ANNOYED_WINDOW) escalates to the
# full verbal tip/thought. The 6-tap/60s joke + 14-tap canard explosion
# easter eggs are unchanged.
var CANARD_QUACK_STREAMS: Array = [
	preload("res://assets/audio/characters/canard_react_quack.mp3"),
	preload("res://assets/audio/characters/canard_react_giggle.mp3"),
	preload("res://assets/audio/characters/canard_react_squeak.mp3"),
	preload("res://assets/audio/characters/canard_react_honk.mp3"),
	preload("res://assets/audio/characters/canard_react_chitter.mp3"),
]
const HUMBUG_REACTS := ["harumph", "snort", "hmm", "huff", "tut"]
const REACT_FLOURISH := {
	"harumph": "tip", "huff": "tip", "hmm": "thought",
	"snort": "thought", "tut": "canard",
}
const ANNOYED_TAPS: int = 5
const ANNOYED_WINDOW: float = 2.0
const REACT_DEBOUNCE: float = 0.2
var _react_tap_times: Array[float] = []
var _humbug_last_react_at: float = 0.0
var _last_humbug_react: String = ""

var _humbug_base_pos: Vector2
var _humbug_tapped_at: float = 0.0
var _humbug_flourish: Tween
var _humbug_bubble: Control = null
var _harp_player: AudioStreamPlayer
# Tap bookkeeping the iter-160 easter eggs build on.
var _humbug_tap_times: Array[float] = []
var _canard_tap_count: int = 0
# Iter 160 easter-egg state.
var _humbug_joke_idx: int = 0
var _canard_player: AudioStreamPlayer
var _canard_new_head: Sprite2D = null
var _flourish_video: VideoStreamPlayer = null  # iter 168: Veo flourish playback

func _ready() -> void:
	get_tree().set_quit_on_go_back(false)
	get_window().go_back_requested.connect(_on_back_requested)
	DebugLog.add("level_select _ready (build=%s)" % BuildInfo.SHA)
	level_1_button.pressed.connect(_on_level_1_pressed)
	level_2_button.pressed.connect(_on_level_2_pressed)
	back_button.pressed.connect(_on_back_pressed)
	_ground_level_nodes()
	_setup_humbug()
	_build_debug_overlay()
	_build_sky()
	_setup_orb_anchors()
	var terr := get_node_or_null("Terrain3D")
	if terr != null:
		var prop_av := PackedVector2Array()
		for d in PROP_DATA:
			prop_av.append(_prop_local(d[1], d[2]))
		# weed just the candy centre so grass grows over the dirt shoulder + trail edge (overlapping it), + a clear patch around each prop
		terr.call("build_grass", PackedVector2Array(_trail_anchors), 0.95, prop_av, 2.8)
	_build_trail_mesh()
	_build_orb_visuals()
	_place_props()
	_place_cowboy()
	_focus_on(_focus_level)  # default view = the cowboy's (highest completed) level
	_prop_player = AudioStreamPlayer.new()
	_prop_player.bus = "Master"
	add_child(_prop_player)
	_cowboy_vo_player = AudioStreamPlayer.new()
	_cowboy_vo_player.bus = "Master"
	add_child(_cowboy_vo_player)
	var _cam := get_node_or_null("Terrain3D/SubViewport/Camera3D") as Camera3D
	if _cam != null:
		_base_fov = _cam.fov
	_build_tuning_sliders()
	_snap_timer = Timer.new()
	_snap_timer.one_shot = true
	_snap_timer.timeout.connect(_snap_to_focus)
	add_child(_snap_timer)

# Iter 336: same self-building sky as gameplay — sun/moon + clouds + candy
# mountains in the level-select terrain SubViewport. Time of day follows the
# system clock; weather reflects the player's current level.
func _build_sky() -> void:
	var sv: SubViewport = get_node_or_null("Terrain3D/SubViewport")
	if sv == null:
		return
	var cam: Camera3D = sv.get_node_or_null("Camera3D")
	var sky := SkyBodies.new()
	sky.name = "SkyBodies"
	sv.add_child(sky)
	if cam != null:
		sky.bind_camera(cam)
	var weather: String = "overcast" if (get_node_or_null("/root/GameState") \
		and GameState.current_level == 2) else "fair"
	sky.apply_preset(SkyBodies.make_sky_preset(SkyBodies.tod_from_clock(), weather),
		Vector3(-0.5, 0.0, 1.0))

# Iter 158: bind the path tiles to the terrain — perspective scale + a
# haze fade with distance, plus a contact shadow per level node.
func _ground_level_nodes() -> void:
	var span: float = TILE_PERSP_FOREGROUND_Y - TILE_PERSP_HORIZON_Y
	for n in PERSP_TILE_NAMES:
		var node: Node = get_node_or_null(NodePath(n))
		if node == null:
			continue
		var y: float = 0.0
		if node is Control:
			var c := node as Control
			c.pivot_offset = c.size * 0.5  # scale about the centre, in place
			y = c.offset_top
		elif node is Node2D:
			y = (node as Node2D).position.y
		else:
			continue
		var t: float = clampf((y - TILE_PERSP_HORIZON_Y) / span, 0.0, 1.0)
		var s: float = lerpf(TILE_PERSP_HORIZON_SCALE, 1.0, t)
		# scale/modulate via get/set so one loop covers Control + Node2D.
		if not node.has_meta("base_scale"):
			node.set_meta("base_scale", node.get("scale"))
		node.set("scale", (node.get_meta("base_scale") as Vector2) * s)
		var mod: Color = node.get("modulate")
		mod.a = lerpf(0.80, 1.0, t)  # distant nodes sit back in the dust
		node.set("modulate", mod)
	for node_name in LEVEL_NODE_NAMES:
		var btn: Control = get_node_or_null(NodePath(node_name)) as Control
		if btn == null or btn.has_node("ContactShadow"):
			continue
		var shadow := _make_contact_shadow(btn.size)
		btn.add_child(shadow)
		btn.move_child(shadow, 0)  # behind the candy disc + its decorations

# A soft dark ellipse pooled at a node's base — sells "planted on dirt"
# rather than "pasted on top". show_behind_parent draws it under the disc.
func _make_contact_shadow(node_size: Vector2) -> Polygon2D:
	var shadow := Polygon2D.new()
	shadow.name = "ContactShadow"
	var w: float = node_size.x * 0.96
	var h: float = node_size.x * 0.28
	var pts := PackedVector2Array()
	var seg: int = 22
	for i in seg:
		var a: float = TAU * float(i) / float(seg)
		pts.append(Vector2(cos(a) * w * 0.5, sin(a) * h * 0.5))
	shadow.polygon = pts
	shadow.color = Color(0.0, 0.0, 0.0, 0.30)
	shadow.show_behind_parent = true
	shadow.position = Vector2(node_size.x * 0.5, node_size.y * 0.97)
	return shadow

# Iter 339: derive each tile's terrain anchor by ray-casting its designed
# screen position onto the ground plane (y = 0). Stored once; thereafter the
# tiles are driven by re-projecting these anchors, so they ride the terrain.
func _setup_orb_anchors() -> void:
	# Dense samples of the world-space serpentine — used for the ribbon, for
	# arc-length orb spacing, and for arc-length panning.
	_path_pts.clear()
	_path_cum = PackedFloat32Array()
	var n: int = 200
	for s in range(n + 1):
		var w: Vector2 = _path_world(float(s) / float(n) * 1.04)
		_path_pts.append(w)
		_path_cum.append(0.0 if s == 0 else _path_cum[s - 1] + w.distance_to(_path_pts[s - 1]))
	_trail_anchors = _path_pts
	# Orbs spaced by fixed WORLD distance (~10 orb widths) along the path.
	_orb_anchors.clear()
	for k in ORB_COUNT:
		_orb_anchors.append(_path_point_at_length(ORB_START_S + float(k) * ORB_GAP_S, _path_pts, _path_cum))
	_s_min = ORB_START_S
	_s_max = ORB_START_S + float(ORB_COUNT - 1) * ORB_GAP_S

# Walk the cumulative arc-length table to the path point at world distance s.
func _path_point_at_length(s: float, pts: Array[Vector2], cum: PackedFloat32Array) -> Vector2:
	s = clampf(s, 0.0, cum[cum.size() - 1])
	for i in range(1, cum.size()):
		if cum[i] >= s:
			var seg: float = maxf(cum[i] - cum[i - 1], 0.0001)
			return pts[i - 1].lerp(pts[i], (s - cum[i - 1]) / seg)
	return pts[pts.size() - 1]

# Focus the view on a level (by its arc length along the path) — this is both
# the default view and the snap-back target.
func _focus_on(idx: int) -> void:
	_focus_level = clampi(idx, 0, ORB_COUNT - 1)
	_set_focus_s(ORB_START_S + float(_focus_level) * ORB_GAP_S)

# Slide the ground so the path point at arc-length s sits at the focus (screen
# centre, near the bottom). Centres BOTH x and z, so switchback orbs don't fall
# off the side when scrolled near.
func _set_focus_s(s: float) -> void:
	_path_s = clampf(s, _s_min, _s_max)
	var gnd: Node3D = get_node_or_null("Terrain3D/SubViewport/Ground")
	if gnd == null:
		return
	var pp: Vector2 = _path_point_at_length(_path_s, _path_pts, _path_cum)
	gnd.position = Vector3(-pp.x, 0.0, VIEW_FOCUS_Z - pp.y)
	_place_orbs_on_terrain()
	var sky := get_node_or_null("Terrain3D/SubViewport/SkyBodies")
	if sky != null and sky.has_method("set_mountain_pan"):
		sky.set_mountain_pan(_path_s * 0.012)  # slight horizon parallax as you pan

# --- Swipe-to-pan along the trail, snapping back to the cowboy's level --------
# Reset the drag accumulator on every press (in _input so it always fires, even
# when the press lands on an orb button).
# Unified gesture handler: 1 finger = pan the trail, 2 fingers = pinch-zoom, a
# tap = prop bounce. Non-consuming, so the orb buttons still get taps (the
# _drag_dist guard in _start_level stops a drag from loading a level).
func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_cancel_snap()  # grabbing interrupts any pending/running drift-back
			_touches[event.index] = event.position
			if _touches.size() == 1:
				_drag_dist = 0.0
				_was_pinch = false
			elif _touches.size() == 2:
				_was_pinch = true
				_pinch_base = _two_dist()
		else:
			var pos: Vector2 = event.position
			_touches.erase(event.index)
			if _touches.is_empty():
				if _was_pinch:
					_snap_zoom()
				elif _drag_dist <= 30.0:
					if not _try_tap_cowboy(pos):
						_try_tap_prop(pos)
				_arm_snap()  # let it settle, then drift back to the cowboy
	elif event is InputEventScreenDrag:
		_touches[event.index] = event.position
		if _touches.size() >= 2:
			_apply_pinch()
		else:
			_pan(event.relative.y)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_cancel_snap()
			_drag_dist = 0.0
		else:
			if _drag_dist <= 30.0:
				if not _try_tap_cowboy(event.position):
					_try_tap_prop(event.position)
			_arm_snap()
	elif event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		_pan(event.relative.y)

func _pan(dy: float) -> void:
	_cancel_snap()
	_drag_dist += absf(dy)  # drag DOWN reveals levels further up the trail
	_set_focus_s(_path_s + dy * pan_speed)

# Wait snap_delay seconds of no input (so a 2nd/3rd swipe can chain), then drift.
func _arm_snap() -> void:
	if _snap_timer != null:
		_snap_timer.start(snap_delay)

func _cancel_snap() -> void:
	if _snap_timer != null:
		_snap_timer.stop()
	if _snap_tween != null and _snap_tween.is_valid():
		_snap_tween.kill()
		_snap_tween = null

# Drift back to the cowboy's level: starts slow, accelerates into the snap (EASE_IN).
func _snap_to_focus() -> void:
	var target: float = ORB_START_S + float(_focus_level) * ORB_GAP_S
	if _snap_tween != null and _snap_tween.is_valid():
		_snap_tween.kill()
	_snap_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_snap_tween.tween_method(_set_focus_s, _path_s, target, snap_dur)

# --- Pinch-zoom (two-finger), snaps back to default on release --------------
func _two_dist() -> float:
	var pts: Array = _touches.values()
	return pts[0].distance_to(pts[1]) if pts.size() >= 2 else 0.0

func _apply_pinch() -> void:
	var d: float = _two_dist()
	if _pinch_base <= 0.0:
		_pinch_base = d
		return
	_zoom = clampf(_zoom * (d / _pinch_base), 0.6, 2.5)
	_pinch_base = d
	_set_zoom()

func _set_zoom() -> void:
	var cam: Camera3D = get_node_or_null("Terrain3D/SubViewport/Camera3D")
	if cam != null:
		cam.fov = clampf(_base_fov / _zoom, 32.0, 95.0)
		_place_orbs_on_terrain()  # re-scales the cowboy by _fov_mag too
		if humbug != null:
			humbug.scale = _humbug_base_scale * _fov_mag()  # 2D guide + canard track the zoom

# Magnification a camera-FOV zoom applies to on-screen size, so 2D overlays
# (cowboy, Humbug) match the 3D billboards that zoom through the projection.
func _fov_mag() -> float:
	var cam := get_node_or_null("Terrain3D/SubViewport/Camera3D") as Camera3D
	if cam == null:
		return 1.0
	return tan(deg_to_rad(_base_fov) * 0.5) / tan(deg_to_rad(cam.fov) * 0.5)

func _snap_zoom() -> void:
	var tw := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_method(func(z: float): _zoom = z; _set_zoom(), _zoom, 1.0, snap_dur)

# A fat circular grabber texture so the sliders are thumb-draggable on a phone.
func _slider_grabber() -> ImageTexture:
	var r: int = 30
	var img := Image.create(r * 2, r * 2, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in r * 2:
		for x in r * 2:
			var d: float = Vector2(x - r, y - r).length()
			if d <= r:
				img.set_pixel(x, y, Color(1.0, 0.85, 0.35) if d < r - 4 else Color(0.2, 0.1, 0.05))
	return ImageTexture.create_from_image(img)

# Debug-only sliders to live-tune pan speed + snap duration on-device. Dark
# bottom panel, large readable values, tall full-width sliders + fat grabbers.
func _build_tuning_sliders() -> void:
	if not OS.has_feature("debug"):
		return
	var parent: Node = get_node_or_null("UI")
	if parent == null:
		parent = self
	var bg := ColorRect.new()
	bg.name = "TuningSliders"
	bg.color = Color(0.06, 0.05, 0.10, 0.9)
	bg.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bg.offset_top = -480.0
	parent.add_child(bg)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 50.0
	box.offset_right = -50.0
	box.offset_top = 24.0
	box.offset_bottom = -24.0
	box.add_theme_constant_override("separation", 14)
	bg.add_child(box)
	var grab := _slider_grabber()
	for spec in [
			{"name": "pan_speed", "min": 0.004, "max": 0.06, "step": 0.001, "val": pan_speed, "fmt": "%.3f"},
			{"name": "snap_dur", "min": 0.1, "max": 2.5, "step": 0.05, "val": snap_dur, "fmt": "%.2f"},
			{"name": "snap_delay", "min": 0.0, "max": 10.0, "step": 0.5, "val": snap_delay, "fmt": "%.1f"}]:
		var lbl := Label.new()
		lbl.add_theme_font_size_override("font_size", 44)
		lbl.add_theme_color_override("font_color", Color(1, 1, 0.85))
		lbl.text = "%s  %s" % [spec["name"], spec["fmt"] % spec["val"]]
		var sl := HSlider.new()
		sl.min_value = spec["min"]
		sl.max_value = spec["max"]
		sl.step = spec["step"]
		sl.value = spec["val"]
		sl.custom_minimum_size = Vector2(0, 70)
		sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sl.add_theme_icon_override("grabber", grab)
		sl.add_theme_icon_override("grabber_highlight", grab)
		var nm: String = spec["name"]
		var fmt: String = spec["fmt"]
		sl.value_changed.connect(func(v: float):
			if nm == "pan_speed":
				pan_speed = v
			elif nm == "snap_dur":
				snap_dur = v
			else:
				snap_delay = v
			lbl.text = "%s  %s" % [nm, fmt % v])
		box.add_child(lbl)
		box.add_child(sl)

# Procedural level path in plane-LOCAL (x, z) world space. p: 0 = near (level
# 1) .. 1 = far. A serpentine running far up the (long) terrain — most of it is
# off-screen; you swipe to pan along it. World-space (not screen-space) so it
# can extend well beyond a single view.
func _path_world(p: float) -> Vector2:
	var z: float = lerpf(PATH_Z_NEAR, PATH_Z_FAR, clampf(p, -0.25, 1.2))  # p<0 extends toward the camera
	var x: float = PATH_AMP * sin(p * PI * PATH_SWITCHBACKS)
	return Vector2(x, z)

# Iter 339: project each level tile's terrain anchor to the screen so the orbs
# sit ON the hilly map. Tiles behind the camera are hidden; the rest are scaled
# by camera distance for perspective and centred on their projected point.
func _place_orbs_on_terrain() -> void:
	var cam: Camera3D = get_node_or_null("Terrain3D/SubViewport/Camera3D")
	var terrain = get_node_or_null("Terrain3D")
	var gnd: Node3D = get_node_or_null("Terrain3D/SubViewport/Ground")
	if cam == null or terrain == null or gnd == null or _orb_anchors.size() < ORB_NODE_NAMES.size():
		return
	for i in ORB_NODE_NAMES.size():
		var btn: Control = get_node_or_null(NodePath(ORB_NODE_NAMES[i])) as Control
		if btn == null:
			continue
		var a: Vector2 = _orb_anchors[i]
		var hy: float = terrain.call("height_at", a.x, a.y)
		var world: Vector3 = gnd.global_transform * Vector3(a.x, hy, a.y)
		if cam.is_position_behind(world):
			btn.visible = false
			continue
		btn.visible = true
		var center: Vector2 = cam.unproject_position(world)
		var base: Vector2 = btn.get_meta("base_scale", Vector2.ONE)
		var dist: float = cam.global_position.distance_to(world)
		btn.scale = base * clampf(ORB_NEAR_DIST / dist, 0.3, 1.05) * ORB_SIZE_MULT * _fov_mag()
		btn.position = center - btn.size * 0.5
	_place_cowboy_marker(cam, terrain, gnd)

# Iter 339: the welcome sign + larger-than-life Western props, dotted along the
# trail. Each is a swaying breathing-shader billboard on the terrain (child of
# Ground so it pans with the map) and is tappable for a bounce + creak.
# [texture, arc-length along the path, side offset (+ right / - left), width, sway]
const PROP_DATA: Array = [
	["res://assets/sprites/props/sign_candy_west.png", 7.5, 3.7, 2.6, 0.035],
	["res://assets/sprites/props/cactus_saguaro.png", 10.0, -3.0, 1.9, 0.05],
	["res://assets/sprites/props/wagon_covered.png", 17.0, 3.4, 3.2, 0.03],
	["res://assets/sprites/props/rock_large.png", 24.0, -3.0, 2.2, 0.02],
	["res://assets/sprites/props/cactus_prickly.png", 31.0, 3.0, 1.7, 0.05],
	["res://assets/sprites/props/tumbleweed.png", 38.0, -2.8, 1.4, 0.09],
	["res://assets/sprites/props/rock_small.png", 45.0, 3.0, 1.3, 0.02],
]

func _place_props() -> void:
	for d in PROP_DATA:
		_add_prop(d[0], d[1], d[2], d[3], d[4])

# The cowboy — a larger, idle-looping marker standing on the highest completed
# (current) level. A 2D animated sprite (so it draws over the orb), driven each
# frame by that orb's projection in _place_cowboy_marker().
func _place_cowboy() -> void:
	if get_node_or_null("/root/GameState"):
		_focus_level = clampi(GameState.current_level - 1, 0, ORB_COUNT - 1)
	_cowboy_s = ORB_START_S + float(_focus_level) * ORB_GAP_S
	var old := get_node_or_null("Cowboy")
	if old != null:
		old.set("visible", false)  # retire the tiny fixed 2D cowboy
	var frames := SpriteFrames.new()
	frames.set_animation_loop("default", true)
	frames.set_animation_speed("default", 2.5)
	var f0: Texture2D = load("res://assets/sprites/posse_idle_00.png")
	_cowboy_half_h = float(f0.get_height()) * 0.5
	frames.add_frame("default", f0)
	frames.add_frame("default", load("res://assets/sprites/posse_idle_01.png"))
	_cowboy_sprite = AnimatedSprite2D.new()
	_cowboy_sprite.name = "CowboyMarker"
	_cowboy_sprite.sprite_frames = frames
	_cowboy_sprite.centered = true
	add_child(_cowboy_sprite)
	_cowboy_sprite.play("default")

func _place_cowboy_marker(cam: Camera3D, terrain, gnd: Node3D) -> void:
	if _cowboy_sprite == null:
		return
	var a: Vector2 = _prop_local(_cowboy_s, COWBOY_SIDE)  # beside the path/orb, not on it
	var world: Vector3 = gnd.global_transform * Vector3(a.x, float(terrain.call("height_at", a.x, a.y)), a.y)
	if cam.is_position_behind(world):
		_cowboy_sprite.visible = false
		return
	_cowboy_sprite.visible = true
	var c: Vector2 = cam.unproject_position(world)
	var sc: float = clampf(ORB_NEAR_DIST / cam.global_position.distance_to(world), 0.3, 1.05) * ORB_SIZE_MULT * 0.62 * _fov_mag()
	_cowboy_sprite.scale = Vector2(sc, sc)
	_cowboy_sprite.position = c - Vector2(0.0, _cowboy_half_h * sc)  # feet on the ground

# Iter 339: rendered orbs as 3D breathing billboards on the terrain (depth-sort
# with the sign/props — fixes the old 2D-orb-over-3D-sign layering), each with a
# stylized level number floating + breathing above it. The original level
# buttons are kept invisible as tap-targets (still projected by _place_orbs).
func _build_orb_visuals() -> void:
	var gnd: Node3D = get_node_or_null("Terrain3D/SubViewport/Ground")
	var terrain = get_node_or_null("Terrain3D")
	if gnd == null or terrain == null:
		return
	for i in ORB_COUNT:
		var level: int = i + 1
		var tex: Texture2D = load("res://assets/sprites/props/%s.png" % ORB_TEX.get(level, "orb_locked"))
		var a: Vector2 = _orb_anchors[i]
		var gy: float = float(terrain.call("height_at", a.x, a.y))
		var w: float = 1.1
		var h: float = w * float(tex.get_height()) / float(tex.get_width())
		var orb := _make_prop(tex, w, h, 0.04)  # gentle breathe via breathing_prop
		orb.position = Vector3(a.x, gy + h * 0.5, a.y)
		gnd.add_child(orb)
		# stylized level number floating above, breathing on a looping tween
		var num := Label3D.new()
		num.text = str(level)
		num.font = _RYE_FONT
		num.font_size = 180
		num.outline_size = 36
		num.modulate = Color(1.0, 0.97, 0.85)
		num.outline_modulate = Color(0.25, 0.10, 0.05)
		num.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		num.pixel_size = 0.0040
		num.position = Vector3(a.x, gy + h + 0.25, a.y)
		gnd.add_child(num)
		var bt := create_tween().set_loops()
		bt.tween_property(num, "scale", Vector3.ONE * 1.14, 1.0).set_trans(Tween.TRANS_SINE)
		bt.tween_property(num, "scale", Vector3.ONE, 1.0).set_trans(Tween.TRANS_SINE)
		var btn := get_node_or_null(NodePath(ORB_NODE_NAMES[i])) as Control
		if btn != null:
			btn.modulate.a = 0.0  # invisible visual; still catches taps
	for nm in ORB_OLD_DECOR:
		var node := get_node_or_null(NodePath(nm))
		if node != null:
			node.set("visible", false)

# Plane-local (x, z) a perpendicular `side` distance off the path at arc-length
# `arc_s` — so props sit just beside the trail and stay on-screen when scrolled to.
func _prop_local(arc_s: float, side: float) -> Vector2:
	var pp: Vector2 = _path_point_at_length(arc_s, _path_pts, _path_cum)
	var pp2: Vector2 = _path_point_at_length(arc_s + 0.6, _path_pts, _path_cum)
	var tang: Vector2 = pp2 - pp
	if tang.length() < 0.001:
		tang = Vector2(0, -1)
	tang = tang.normalized()
	return pp + Vector2(tang.y, -tang.x) * side

# Build one swaying billboard prop beside the path, drop it on the terrain as a
# Ground child, and register it as tappable.
func _add_prop(tex_path: String, arc_s: float, side: float, w: float, sway_amp: float) -> void:
	var gnd: Node3D = get_node_or_null("Terrain3D/SubViewport/Ground")
	var terrain = get_node_or_null("Terrain3D")
	if gnd == null or terrain == null:
		return
	var tex: Texture2D = load(tex_path)
	if tex == null:
		return
	var local: Vector2 = _prop_local(arc_s, side)
	var h: float = w * float(tex.get_height()) / float(tex.get_width())
	var prop := _make_prop(tex, w, h, sway_amp)
	prop.position = Vector3(local.x, float(terrain.call("height_at", local.x, local.y)) + h * 0.5, local.y)
	gnd.add_child(prop)
	_props.append({"node": prop, "anchor": local, "h": h, "kind": _prop_kind(tex_path)})

func _make_prop(tex: Texture2D, w: float, h: float, sway_amp: float) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(w, h)
	plane.subdivide_width = 5
	plane.subdivide_depth = 7
	plane.orientation = 2  # FACE_Z — vertical plane the billboard shader expects
	mesh.mesh = plane
	var mat := ShaderMaterial.new()
	mat.shader = _BREATHING_SHADER
	mat.set_shader_parameter("albedo_tex", tex)
	mat.set_shader_parameter("modulate", Color(1, 1, 1, 1))
	mat.set_shader_parameter("sway_amp", sway_amp)
	mat.set_shader_parameter("sway_freq", 1.4)
	mat.set_shader_parameter("bob_amp", 0.012)
	mat.set_shader_parameter("bob_freq", 2.0)
	mat.set_shader_parameter("time_offset", randf() * 6.28)
	if get_node_or_null("/root/SwayPrefs"):
		mat.set_shader_parameter("sway_profile", SwayPrefs.get_profile())
	mat.set_shader_parameter("sway_intensity", sway_amp / 0.06)
	mat.set_shader_parameter("mesh_height", h)
	mesh.material_override = mat
	return mesh

# A tap on a prop (not on an orb/Humbug — those are GUI) bounces it + creaks.
func _try_tap_prop(pos: Vector2) -> void:
	var cam: Camera3D = get_node_or_null("Terrain3D/SubViewport/Camera3D")
	if cam == null:
		return
	for p in _props:
		var node: MeshInstance3D = p["node"]
		var world: Vector3 = node.global_transform.origin
		if cam.is_position_behind(world):
			continue
		var c: Vector2 = cam.unproject_position(world)
		var top: Vector2 = cam.unproject_position(world + Vector3(0, p["h"] * 0.5, 0))
		if pos.distance_to(c) < maxf(c.distance_to(top), 55.0):
			_bounce_prop(node, p.get("kind", "sign"))
			return

# Per-prop tap reactions — each kind moves + sounds differently. Sounds fall
# back to the sign creak until the per-prop SFX are generated (iter344).
const _PROP_SFX := {
	"sign": "res://assets/sfx/sign_creak.ogg",
	"cactus": "res://assets/sfx/prop_cactus.ogg",
	"wagon": "res://assets/sfx/prop_wagon.ogg",
	"rock": "res://assets/sfx/prop_rock.ogg",
	"tumbleweed": "res://assets/sfx/prop_tumbleweed.ogg",
}

func _prop_kind(tex_path: String) -> String:
	var f: String = tex_path.get_file()
	for k in ["sign", "wagon", "rock", "tumbleweed", "cactus"]:
		if f.begins_with(k):
			return k
	return "sign"

func _bounce_prop(node: MeshInstance3D, kind: String) -> void:
	var mat: ShaderMaterial = node.material_override
	if mat == null:
		return
	if _prop_player != null:
		var path: String = _PROP_SFX.get(kind, "")
		var s: AudioStream = load(path) if (path != "" and ResourceLoader.exists(path)) else _CREAK_SFX
		_prop_player.stream = s
		_prop_player.pitch_scale = randf_range(0.94, 1.07)  # subtle per-tap variation
		_prop_player.play()
	var tw := create_tween()
	match kind:
		"cactus":  # stiff & rigid — a small quick quiver + spine shudder
			tw.tween_method(_set_bonk.bind(mat), 1.0, 0.90, 0.05)
			tw.tween_method(_set_bonk.bind(mat), 0.90, 1.04, 0.08).set_trans(Tween.TRANS_BACK)
			tw.tween_method(_set_bonk.bind(mat), 1.04, 1.0, 0.14).set_ease(Tween.EASE_OUT)
			_damage_pulse(mat, 0.5)
		"wagon":  # heavy — a big slow squash + a rattling shake
			tw.tween_method(_set_bonk.bind(mat), 1.0, 0.80, 0.10)
			tw.tween_method(_set_bonk.bind(mat), 0.80, 1.07, 0.16).set_trans(Tween.TRANS_BACK)
			tw.tween_method(_set_bonk.bind(mat), 1.07, 1.0, 0.26).set_ease(Tween.EASE_OUT)
			_damage_pulse(mat, 0.85)
		"rock":  # barely budges — a tiny dull nudge
			tw.tween_method(_set_bonk.bind(mat), 1.0, 0.93, 0.05)
			tw.tween_method(_set_bonk.bind(mat), 0.93, 1.0, 0.12).set_ease(Tween.EASE_OUT)
		"tumbleweed":  # light & springy — a big bouncy overshoot
			tw.tween_method(_set_bonk.bind(mat), 1.0, 0.55, 0.06)
			tw.tween_method(_set_bonk.bind(mat), 0.55, 1.25, 0.14).set_trans(Tween.TRANS_BACK)
			tw.tween_method(_set_bonk.bind(mat), 1.25, 0.92, 0.12).set_trans(Tween.TRANS_SINE)
			tw.tween_method(_set_bonk.bind(mat), 0.92, 1.0, 0.16).set_ease(Tween.EASE_OUT)
		_:  # sign — the original gentle swing-bonk
			tw.tween_method(_set_bonk.bind(mat), 1.0, 0.62, 0.07)
			tw.tween_method(_set_bonk.bind(mat), 0.62, 1.12, 0.12).set_trans(Tween.TRANS_BACK)
			tw.tween_method(_set_bonk.bind(mat), 1.12, 1.0, 0.20).set_ease(Tween.EASE_OUT)

func _damage_pulse(mat: ShaderMaterial, strength: float) -> void:
	# quick crinkle/shake via the breathing shader's damage_strength uniform
	var dt := create_tween()
	dt.tween_method(func(v: float): mat.set_shader_parameter("damage_strength", v), strength, 0.0, 0.35)

func _set_bonk(v: float, mat: ShaderMaterial) -> void:
	mat.set_shader_parameter("bonk_squash", v)

# Tap the cowboy → a reaction. Returns true if the tap hit him (so the caller
# doesn't also fall through to a prop tap).
func _try_tap_cowboy(pos: Vector2) -> bool:
	if _cowboy_sprite == null or not _cowboy_sprite.visible or _walking:
		return false
	var frames := _cowboy_sprite.sprite_frames
	if frames == null:
		return false
	var tex := frames.get_frame_texture("default", 0)
	if tex == null:
		return false
	var sz: Vector2 = tex.get_size() * _cowboy_sprite.scale
	var rect := Rect2(_cowboy_sprite.position - sz * 0.5, sz)  # centered sprite
	if not rect.has_point(pos):
		return false
	_react_cowboy()
	return true

func _react_cowboy() -> void:
	var now: float = Time.get_ticks_msec() / 1000.0
	_cowboy_tap_stamps.append(now)
	_cowboy_tap_stamps = _cowboy_tap_stamps.filter(func(t: float) -> bool: return now - t <= COWBOY_QUICK_WINDOW)
	var annoyed: bool = _cowboy_tap_stamps.size() >= COWBOY_QUICK_TAPS
	if _cowboy_vo_player != null:
		var n: int = COWBOY_ANNOYED_LINES if annoyed else COWBOY_TAP_LINES
		var path: String = "res://assets/sfx/cowboy_%s_%d.ogg" % ["annoyed" if annoyed else "tap", randi() % n]
		if ResourceLoader.exists(path):
			_cowboy_vo_player.stream = load(path)
			_cowboy_vo_player.play()
	if annoyed:
		_cowboy_anim_annoyed()
		_cowboy_tap_stamps.clear()  # reset so the next burst can re-trigger
	else:
		_cowboy_anim(randi() % 6)

# Six procedural tap pops on the 2D cowboy sprite (centered → pivots at his
# middle). Each self-resets to rest, so a pan's re-projection isn't fought.
func _cowboy_anim(i: int) -> void:
	var s := _cowboy_sprite
	if s == null:
		return
	var bs: Vector2 = s.scale
	var bp: Vector2 = s.position
	var t := create_tween()
	match i:
		0:  # tip-hat nod forward
			t.tween_property(s, "rotation", -0.14, 0.10)
			t.tween_property(s, "rotation", 0.0, 0.24).set_trans(Tween.TRANS_BACK)
		1:  # little jump + land squash
			t.tween_property(s, "position", bp + Vector2(0, -34), 0.13).set_trans(Tween.TRANS_SINE)
			t.parallel().tween_property(s, "scale", bs * Vector2(0.94, 1.08), 0.13)
			t.tween_property(s, "position", bp, 0.15).set_ease(Tween.EASE_IN)
			t.tween_property(s, "scale", bs * Vector2(1.1, 0.86), 0.05)
			t.tween_property(s, "scale", bs, 0.14).set_trans(Tween.TRANS_BACK)
		2:  # squash & spring
			t.tween_property(s, "scale", bs * Vector2(1.16, 0.84), 0.07)
			t.tween_property(s, "scale", bs * Vector2(0.93, 1.10), 0.10).set_trans(Tween.TRANS_BACK)
			t.tween_property(s, "scale", bs, 0.14).set_ease(Tween.EASE_OUT)
		3:  # lean back
			t.tween_property(s, "rotation", 0.16, 0.12)
			t.tween_property(s, "rotation", 0.0, 0.26).set_trans(Tween.TRANS_BACK)
		4:  # double-take pop
			t.tween_property(s, "scale", bs * 1.12, 0.06)
			t.tween_property(s, "scale", bs, 0.08)
			t.tween_property(s, "scale", bs * 1.08, 0.06)
			t.tween_property(s, "scale", bs, 0.10).set_trans(Tween.TRANS_BACK)
		_:  # wiggle
			t.tween_property(s, "rotation", -0.10, 0.07)
			t.tween_property(s, "rotation", 0.10, 0.10)
			t.tween_property(s, "rotation", 0.0, 0.12).set_trans(Tween.TRANS_BACK)

func _cowboy_anim_annoyed() -> void:
	var s := _cowboy_sprite
	if s == null:
		return
	var bs: Vector2 = s.scale
	var t := create_tween()
	t.tween_property(s, "scale", bs * Vector2(0.9, 1.12), 0.05)  # sharp recoil
	t.tween_property(s, "scale", bs, 0.10)
	for k in 4:  # irritated shake
		t.tween_property(s, "rotation", 0.09 if k % 2 == 0 else -0.09, 0.045)
	t.tween_property(s, "rotation", 0.0, 0.08).set_trans(Tween.TRANS_BACK)

# Iter 339: the candy path ribbon. A Line2D drawn under the orb tiles (above
# the terrain), tapering with distance via its width_curve. Inserted right
# after Terrain3D in the tree so it draws over the ground but under the tiles.
# Iter 339: the candy path as a 3D ribbon laid on the terrain (child of Ground,
# so it drapes over the hills, depth-sorts with the grass, and pans with the
# map). Built once. UV.v runs along the path so the candy texture tiles; the
# far tail fades via vertex alpha for the "infinite levels" haze.
func _build_trail_mesh() -> void:
	var terrain = get_node_or_null("Terrain3D")
	var gnd: Node3D = get_node_or_null("Terrain3D/SubViewport/Ground")
	if terrain == null or gnd == null or _trail_anchors.size() < 2:
		return
	var eps: float = 0.06
	var tile_len: float = 3.6
	# Extend the ribbon toward the camera (off the bottom of the screen) so the
	# near end runs off-screen instead of stopping with a hard cap.
	var anchors: Array[Vector2] = []
	for p in [-0.18, -0.12, -0.06]:
		anchors.append(_path_world(p))
	anchors.append_array(_trail_anchors)
	var n: int = anchors.size()
	var ctr: Array[Vector3] = []
	for a in anchors:
		ctr.append(Vector3(a.x, float(terrain.call("height_at", a.x, a.y)) + eps, a.y))
	var run := PackedFloat32Array()
	run.append(0.0)
	for i in range(1, n):
		run.append(run[i - 1] + Vector2(ctr[i].x, ctr[i].z).distance_to(Vector2(ctr[i - 1].x, ctr[i - 1].z)))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(n - 1):
		var lr0: Array = _trail_rail(terrain, ctr, i, eps)
		var lr1: Array = _trail_rail(terrain, ctr, i + 1, eps)
		var v0: float = run[i] / tile_len
		var v1: float = run[i + 1] / tile_len
		var a0: float = _trail_alpha(i, n)
		var a1: float = _trail_alpha(i + 1, n)
		_tv(st, lr0[0], Vector2(0, v0), a0); _tv(st, lr0[1], Vector2(1, v0), a0); _tv(st, lr1[1], Vector2(1, v1), a1)
		_tv(st, lr0[0], Vector2(0, v0), a0); _tv(st, lr1[1], Vector2(1, v1), a1); _tv(st, lr1[0], Vector2(0, v1), a1)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = "CandyTrail3D"
	mi.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = preload("res://assets/sprites/props/candy_path.png")
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	# Draw the path BEFORE the grass so foreground tufts (nearer than the path's
	# near edge) paint over it. Its alpha depth-prepass still writes depth, so
	# grass BEHIND the path is depth-culled — only the in-front tufts overlap.
	mat.render_priority = -1
	mi.material_override = mat
	gnd.add_child(mi)

const TRAIL_WIDTH: float = 3.8

# Left/right rail points at sample i — offset perpendicular to the path in XZ,
# re-dropped onto the terrain so the ribbon hugs the hills across its width.
func _trail_rail(terrain, ctr: Array, i: int, eps: float) -> Array:
	var n: int = ctr.size()
	var tang: Vector3
	if i == 0:
		tang = ctr[1] - ctr[0]
	elif i == n - 1:
		tang = ctr[n - 1] - ctr[n - 2]
	else:
		tang = ctr[i + 1] - ctr[i - 1]
	tang.y = 0.0
	if tang.length() < 0.001:
		tang = Vector3(0, 0, -1)
	tang = tang.normalized()
	var perp := Vector3(tang.z, 0.0, -tang.x)
	var lp: Vector3 = ctr[i] - perp * (TRAIL_WIDTH * 0.5)
	var rp: Vector3 = ctr[i] + perp * (TRAIL_WIDTH * 0.5)
	lp.y = float(terrain.call("height_at", lp.x, lp.z)) + eps
	rp.y = float(terrain.call("height_at", rp.x, rp.z)) + eps
	return [lp, rp]

func _trail_alpha(i: int, n: int) -> float:
	# Samples run to u≈1.1; orbs only reach u≈0.88, so keep the ribbon solid
	# under every orb and fade only the tail beyond it into the haze.
	var u: float = float(i) / float(n - 1) * 1.10
	return 1.0 if u <= 0.9 else clampf((1.08 - u) / 0.18, 0.0, 1.0)

func _tv(st: SurfaceTool, p: Vector3, uv: Vector2, a: float) -> void:
	st.set_color(Color(1, 1, 1, a))
	st.set_uv(uv)
	st.add_vertex(p)

# ---------------------------------------------------------------------------
# Iter 159: Professor Humbug + Monsieur Canard
# ---------------------------------------------------------------------------

func _setup_humbug() -> void:
	humbug.pivot_offset = humbug.size * 0.5  # flourishes scale/rotate in place
	_humbug_base_scale = humbug.scale
	_humbug_base_pos = humbug.position
	humbug.pressed.connect(_on_humbug_pressed)
	canard_zone.mouse_filter = Control.MOUSE_FILTER_STOP
	canard_zone.gui_input.connect(_on_canard_tap)
	_harp_player = AudioStreamPlayer.new()
	_harp_player.stream = HARP_SFX
	_harp_player.bus = "Master"
	_harp_player.volume_db = -4.0
	add_child(_harp_player)
	_canard_player = AudioStreamPlayer.new()
	_canard_player.bus = "Master"
	add_child(_canard_player)
	# Iter 168: chroma-keyed VideoStreamPlayer for the Veo flourish clips.
	# Sized so the clip's Humbug overlays the static TextureButton; shown
	# only while a flourish plays, hidden again on `finished`.
	_flourish_video = VideoStreamPlayer.new()
	_flourish_video.position = Vector2(-75.0, 1276.0)
	_flourish_video.size = Vector2(370.0, 658.0)
	_flourish_video.expand = true
	_flourish_video.loop = false
	_flourish_video.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ck := ShaderMaterial.new()
	ck.shader = CHROMAKEY_SHADER
	ck.set_shader_parameter("chroma_color", Color(0, 1, 0))
	ck.set_shader_parameter("similarity", 0.35)
	ck.set_shader_parameter("blend_amount", 0.12)
	ck.set_shader_parameter("black_threshold", 0.0)  # clips are full-frame, no letterbox
	_flourish_video.material = ck
	_flourish_video.visible = false
	_flourish_video.finished.connect(_on_flourish_finished)
	add_child(_flourish_video)

# Tap Humbug → a flourish + mostly a tip (speech bubble), now and then a
# thought (thought bubble + harp). Canard chimes in with a quack.
func _on_humbug_pressed() -> void:
	var now: float = Time.get_unix_time_from_system()
	# Snappy debounce for reactions (the verbal path keeps its own 1s guard).
	if now - _humbug_last_react_at < REACT_DEBOUNCE:
		return
	_humbug_last_react_at = now
	# Long-window joke easter egg bookkeeping (unchanged behaviour).
	_humbug_tap_times.append(now)
	var cutoff: float = now - HUMBUG_EGG_WINDOW
	while not _humbug_tap_times.is_empty() and _humbug_tap_times[0] < cutoff:
		_humbug_tap_times.remove_at(0)
	if _humbug_tap_times.size() >= HUMBUG_EGG_TAPS:
		_react_tap_times.clear()
		_humbug_joke()
		return
	# Rolling 2s window for the annoyed escalation.
	_react_tap_times = _react_tap_times.filter(func(t): return now - t < ANNOYED_WINDOW)
	_react_tap_times.append(now)
	if _react_tap_times.size() >= ANNOYED_TAPS:
		_react_tap_times.clear()
		_humbug_verbal()
		return
	# Single tap → short reaction + a flourish video as the matching motion.
	var react := _pick_no_repeat(HUMBUG_REACTS, "_last_humbug_react")
	if get_node_or_null("/root/AudioBus") and AudioBus.has_method("play_character_line"):
		AudioBus.play_character_line("humbug_react_%s" % react)
	var vid: String = REACT_FLOURISH.get(react, "tip")
	if not _play_flourish(vid):
		_humbug_tip_flourish()

func _pick_no_repeat(pool: Array, last_var: String) -> String:
	var choices := pool.filter(func(v): return v != get(last_var))
	var chosen: String = choices[randi() % choices.size()]
	set(last_var, chosen)
	return chosen

# The original tip/thought verbal behaviour — now the "annoyed" response
# when the player spams taps. Respects the 1s talk-over guard.
func _humbug_verbal() -> void:
	if not _humbug_tap_accepted():
		return
	if randf() < HUMBUG_THOUGHT_CHANCE:
		if not _play_flourish("thought"):
			_humbug_thought_flourish()
		var ti: int = randi() % HUMBUG_THOUGHT_LINES
		_show_humbug_bubble(Text.lookup("humbug.thoughts.%d" % ti), true)
		_speak_humbug("humbug_thought_%d" % ti)
		if _harp_player != null:
			_harp_player.play()
	else:
		if not _play_flourish("tip"):
			_humbug_tip_flourish()
		var pi: int = randi() % HUMBUG_TIP_LINES
		_show_humbug_bubble(Text.lookup("humbug.tips.%d" % pi), false)
		_speak_humbug("humbug_tip_%d" % pi)
	_canard_chime()

# Debounce (1s) + don't let him talk over himself. Records the accepted
# tap time — the iter-160 "still touching me?" easter egg reads this.
func _humbug_tap_accepted() -> bool:
	var now: float = Time.get_unix_time_from_system()
	if now - _humbug_tapped_at < 1.0:
		return false
	if get_node_or_null("/root/AudioBus") and AudioBus.has_method("any_character_line_playing"):
		if AudioBus.any_character_line_playing():
			return false
	_humbug_tapped_at = now
	# Note: _humbug_tap_times (joke-egg window) is now maintained in
	# _on_humbug_pressed so every tap counts, not just verbal ones.
	return true

# Tap Canard (the duck-head cane handle) → a quack + a quick wiggle.
# accept_event() keeps the tap from also firing Humbug's tip.
func _on_canard_tap(event: InputEvent) -> void:
	var is_press: bool = false
	if event is InputEventScreenTouch:
		is_press = (event as InputEventScreenTouch).pressed
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		is_press = mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed
	if not is_press:
		return
	canard_zone.accept_event()
	_canard_tap_count += 1
	# Iter 160: the CANARD_EGG_TAPS-th tap is the last straw — Canard
	# bursts, then a fresh duck-head springs from the cane.
	if _canard_tap_count >= CANARD_EGG_TAPS:
		_canard_tap_count = 0
		_canard_explode()
		return
	# Increasingly annoyed: quacks climb in pitch + volume and the wiggle
	# sharpens the more he is pestered.
	var heat: float = float(_canard_tap_count) / float(CANARD_EGG_TAPS)
	if not _play_flourish("canard"):
		_canard_wiggle(1.0 + heat * 1.7)
	if _canard_player != null:
		_canard_player.stream = CANARD_QUACK_STREAMS[randi() % CANARD_QUACK_STREAMS.size()]
		_canard_player.pitch_scale = 1.0 + heat * 0.6
		_canard_player.volume_db = -3.0 + heat * 4.0
		_canard_player.play()

# Iter 172: a beat after Humbug acts, Monsieur Canard sometimes quacks —
# keeps the tap lively without a Humbug voice line that wouldn't match
# the bubble's tip/thought text.
func _canard_chime() -> void:
	if randf() > 0.55:
		return
	get_tree().create_timer(0.6).timeout.connect(func() -> void:
		if _canard_player != null:
			_canard_player.stream = CANARD_QUACK_STREAMS[randi() % CANARD_QUACK_STREAMS.size()]
			_canard_player.pitch_scale = 1.0
			_canard_player.volume_db = -3.0
			_canard_player.play())

# Iter 176: play Humbug's matched VO clip for a bubble line — slug is
# humbug_tip_N / humbug_thought_N / humbug_joke_N, generated by
# tools/gen_humbug_vo.py from the same en.json text the bubble shows.
func _speak_humbug(slug: String) -> void:
	if get_node_or_null("/root/AudioBus") and AudioBus.has_method("play_character_line"):
		AudioBus.play_character_line(slug)

# Three procedural flourishes. Each resets Humbug to rest first so rapid
# taps can't compound the transform.
func _reset_humbug_transform() -> void:
	if _humbug_flourish != null:
		_humbug_flourish.kill()
	humbug.position = _humbug_base_pos
	humbug.scale = Vector2.ONE
	humbug.rotation = 0.0

func _humbug_tip_flourish() -> void:
	_reset_humbug_transform()
	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(humbug, "scale", Vector2(1.06, 0.90), 0.12) \
		.set_trans(Tween.TRANS_QUAD)
	t.tween_property(humbug, "position", _humbug_base_pos + Vector2(0, 14), 0.12) \
		.set_trans(Tween.TRANS_QUAD)
	t.chain().tween_property(humbug, "scale", Vector2.ONE, 0.32) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(humbug, "position", _humbug_base_pos, 0.32) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_humbug_flourish = t

func _humbug_thought_flourish() -> void:
	_reset_humbug_transform()
	var t := create_tween()
	t.tween_property(humbug, "rotation", -0.055, 0.5) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t.tween_interval(0.45)
	t.tween_property(humbug, "rotation", 0.0, 0.7) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_humbug_flourish = t

func _canard_wiggle(intensity: float = 1.0) -> void:
	_reset_humbug_transform()
	var a: float = 0.05 * intensity
	var t := create_tween()
	t.tween_property(humbug, "rotation", a, 0.09).set_trans(Tween.TRANS_SINE)
	t.tween_property(humbug, "rotation", -a * 0.82, 0.12).set_trans(Tween.TRANS_SINE)
	t.tween_property(humbug, "rotation", 0.0, 0.13) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_humbug_flourish = t

# Iter 168: play a Veo flourish clip (chroma-keyed video) over Humbug.
# Returns false if the clip is unavailable, so the caller can fall back
# to the procedural tween flourish.
func _play_flourish(kind: String) -> bool:
	if _flourish_video == null:
		return false
	var path: String = FLOURISH_CLIPS.get(kind, "")
	if path == "" or not ResourceLoader.exists(path):
		return false
	_flourish_video.stream = load(path)
	_flourish_video.visible = true
	_flourish_video.play()
	humbug.visible = false  # iter 172: hide the static PNG so it doesn't double the video
	return true

func _on_flourish_finished() -> void:
	if _flourish_video != null:
		_flourish_video.visible = false
	humbug.visible = true  # iter 172: restore the static PNG after the flourish

# Pop a speech/thought bubble above Humbug; auto-dismiss after a beat.
func _show_humbug_bubble(text: String, is_thought: bool) -> void:
	if _humbug_bubble != null and is_instance_valid(_humbug_bubble):
		_humbug_bubble.queue_free()
	var bubble := _build_bubble(text, is_thought)
	add_child(bubble)
	_humbug_bubble = bubble
	bubble.pivot_offset = BUBBLE_SIZE * 0.5
	bubble.scale = Vector2.ZERO
	var t := create_tween()
	t.tween_property(bubble, "scale", Vector2.ONE, 0.30) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_interval(3.6)
	t.tween_property(bubble, "modulate:a", 0.0, 0.45)
	t.tween_callback(bubble.queue_free)

func _build_bubble(text: String, is_thought: bool) -> Control:
	var root := Control.new()
	root.theme = GAME_THEME
	root.position = BUBBLE_POS
	root.size = BUBBLE_SIZE
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if is_thought:
		_add_thought_dots(root)
	else:
		_add_speech_tail(root)
	var panel := Panel.new()
	panel.size = BUBBLE_SIZE
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.90, 0.93, 0.99, 1) if is_thought else Color(0.98, 0.95, 0.86, 1)
	sb.border_color = Color(0.45, 0.50, 0.62, 1) if is_thought else Color(0.42, 0.26, 0.13, 1)
	sb.set_border_width_all(7)
	sb.set_corner_radius_all(46)
	sb.shadow_color = Color(0.0, 0.0, 0.0, 0.28)
	sb.shadow_size = 10
	sb.shadow_offset = Vector2(0, 6)
	panel.add_theme_stylebox_override("panel", sb)
	root.add_child(panel)
	var label := Label.new()
	label.text = text
	label.position = Vector2(38, 28)
	label.size = BUBBLE_SIZE - Vector2(76, 56)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", 29)
	label.add_theme_color_override("font_color", Color(0.16, 0.10, 0.04, 1))
	# Iter 172: kill the theme's text outline — it doubled every stroke,
	# so the bubble copy read as bold-applied-twice and muddy.
	label.add_theme_constant_override("outline_size", 0)
	root.add_child(label)
	return root

# Speech bubble: a filled triangle tail pointing down-left at Humbug.
func _add_speech_tail(root: Control) -> void:
	var tail := Polygon2D.new()
	tail.color = Color(0.98, 0.95, 0.86, 1)
	tail.polygon = PackedVector2Array([
		Vector2(55, BUBBLE_SIZE.y - 8),
		Vector2(160, BUBBLE_SIZE.y - 8),
		Vector2(5, BUBBLE_SIZE.y + 100),
	])
	root.add_child(tail)

# Thought bubble: three shrinking puffs trailing down-left at Humbug.
func _add_thought_dots(root: Control) -> void:
	var fill := Color(0.90, 0.93, 0.99, 1)
	var specs := [
		[Vector2(95, BUBBLE_SIZE.y + 12), 24.0],
		[Vector2(55, BUBBLE_SIZE.y + 58), 16.0],
		[Vector2(22, BUBBLE_SIZE.y + 96), 10.0],
	]
	for spec in specs:
		var dot := Polygon2D.new()
		dot.color = fill
		dot.polygon = _circle_points(spec[1])
		dot.position = spec[0]
		root.add_child(dot)

func _circle_points(r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 16:
		var a: float = TAU * float(i) / 16.0
		pts.append(Vector2(cos(a) * r, sin(a) * r))
	return pts

# --- Iter 160: easter eggs -------------------------------------------------

# Humbug, pestered past HUMBUG_EGG_TAPS in the window, drops the tips and
# snips a joke. The three lines cycle (annoyed → giggling → dismissive).
func _humbug_joke() -> void:
	_humbug_annoyed_flourish()
	_show_humbug_bubble(Text.lookup("humbug.easter_jokes.%d" % _humbug_joke_idx), false)
	_speak_humbug("humbug_joke_%d" % _humbug_joke_idx)
	_humbug_joke_idx = (_humbug_joke_idx + 1) % 3
	_canard_chime()

# A brisk "no-no-no" head-shake — the pestered/annoyed flourish.
func _humbug_annoyed_flourish() -> void:
	_reset_humbug_transform()
	var t := create_tween()
	for _i in 3:
		t.tween_property(humbug, "rotation", 0.085, 0.07).set_trans(Tween.TRANS_SINE)
		t.tween_property(humbug, "rotation", -0.085, 0.07).set_trans(Tween.TRANS_SINE)
	t.tween_property(humbug, "rotation", 0.0, 0.10) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_humbug_flourish = t

# The CANARD_EGG_TAPS-th tap: a poof, a candy-shrapnel burst, and a fresh
# duck-head that springs out of the licorice cane a beat later.
func _canard_explode() -> void:
	var origin: Vector2 = _humbug_base_pos + canard_zone.position + canard_zone.size * 0.5
	if _canard_player != null:
		_canard_player.stream = POOF_SFX
		_canard_player.pitch_scale = 0.6   # iter338: pitch down → a deeper BOOM
		_canard_player.volume_db = 7.0      # and louder
		_canard_player.play()
	_humbug_annoyed_flourish()
	_spawn_explosion_fx(origin)
	_screen_shake(26.0, 0.45)              # iter338: it's an explosion now
	get_tree().create_timer(0.45).timeout.connect(_spawn_new_canard_head.bind(origin))

# Brief decaying positional shake of the whole scene (Node2D root).
func _screen_shake(amp: float, dur: float) -> void:
	var t := create_tween()
	var steps: int = maxi(int(dur / 0.035), 1)
	for i in steps:
		var f: float = 1.0 - float(i) / float(steps)   # decay to 0
		t.tween_property(self, "position",
			Vector2(randf_range(-amp, amp), randf_range(-amp, amp)) * f, 0.035)
	t.tween_property(self, "position", Vector2.ZERO, 0.05)

func _spawn_explosion_fx(origin: Vector2) -> void:
	# iter338: bigger two-layer fireball — white-hot core over an orange bloom.
	for layer in [{"col": Color(1.0, 0.55, 0.10, 0.95), "r": 95.0, "to": 5.2, "t": 0.45},
			{"col": Color(1.0, 0.97, 0.78, 0.98), "r": 60.0, "to": 4.0, "t": 0.32}]:
		var flash := Polygon2D.new()
		flash.color = layer["col"]
		flash.polygon = _circle_points(layer["r"])
		flash.position = origin
		add_child(flash)
		var ft := create_tween()
		ft.set_parallel(true)
		ft.tween_property(flash, "scale", Vector2(layer["to"], layer["to"]), layer["t"]) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		ft.tween_property(flash, "modulate:a", 0.0, layer["t"])
		ft.chain().tween_callback(flash.queue_free)
	var burst := CPUParticles2D.new()
	burst.position = origin
	burst.emitting = false
	burst.one_shot = true
	burst.explosiveness = 1.0
	burst.amount = 60
	burst.lifetime = 0.9
	burst.direction = Vector2(0, -1)
	burst.spread = 180.0
	burst.initial_velocity_min = 300.0
	burst.initial_velocity_max = 760.0
	burst.gravity = Vector2(0, 950)
	burst.scale_amount_min = 7.0
	burst.scale_amount_max = 16.0
	burst.color = Color(1.0, 0.82, 0.25, 1)
	add_child(burst)
	burst.emitting = true
	get_tree().create_timer(1.9).timeout.connect(burst.queue_free)

# A fresh Monsieur Canard springs from the cane, bounces onto the
# cane-top (covering the burst original), and quacks his debut.
func _spawn_new_canard_head(origin: Vector2) -> void:
	if _canard_new_head != null and is_instance_valid(_canard_new_head):
		_canard_new_head.queue_free()
	var head := Sprite2D.new()
	var at := AtlasTexture.new()
	at.atlas = humbug.texture_normal
	at.region = CANARD_HEAD_REGION
	head.texture = at
	head.position = origin
	head.scale = Vector2.ZERO
	add_child(head)
	_canard_new_head = head
	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(head, "scale", Vector2(0.95, 0.95), 0.30) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(head, "position", origin + Vector2(0, -56), 0.30) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.chain()
	t.tween_property(head, "position", origin, 0.24) \
		.set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(head, "scale", Vector2(0.85, 0.85), 0.24)
	get_tree().create_timer(0.34).timeout.connect(func() -> void:
		if _canard_player != null:
			_canard_player.stream = CANARD_QUACK_STREAMS[0]
			_canard_player.pitch_scale = 1.06
			_canard_player.volume_db = -2.0
			_canard_player.play())

# ---------------------------------------------------------------------------

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		DebugLog.add("level_select NOTIFICATION_WM_GO_BACK_REQUEST → main menu")
		_to_main_menu()
	elif what == NOTIFICATION_WM_CLOSE_REQUEST:
		_to_main_menu()

func _on_back_requested() -> void:
	DebugLog.add("level_select go_back_requested SIGNAL → main menu")
	_to_main_menu()

func _on_back_pressed() -> void:
	AudioBus.play_tap()
	_to_main_menu()

func _on_level_1_pressed() -> void:
	_start_level(level_1_button, 1)

func _on_level_2_pressed() -> void:
	_start_level(level_2_button, 2)

# Shared level-start flow: lock the button, set the level (this drives
# the boss dispatch in level_3d — level 2 spawns The Candy Rustler), play
# a brief Candy-Crush squish, then enter the 3D level. The squish tweens
# around the node's CURRENT (perspective-scaled) scale so it doesn't snap
# back to full size.
func _start_level(btn: Button, level_num: int) -> void:
	if _drag_dist > 30.0:
		return  # this press was the tail of a pan-drag, not a tap
	if _walking:
		return
	DebugLog.add("LEVEL %d selected from level_select" % level_num)
	AudioBus.play_tap()
	# Candy-Crush flow: the cowboy strides along the path to the chosen orb (the
	# view following), then the level loads.
	_walking = true
	var target_s: float = ORB_START_S + float(level_num - 1) * ORB_GAP_S
	var dur: float = clampf(absf(target_s - _cowboy_s) / 14.0, 0.25, 1.6)  # ~14 arc units/sec
	var walk := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	walk.tween_method(_set_cowboy_s, _cowboy_s, target_s, dur)
	await walk.finished
	GameState.current_level = level_num
	btn.disabled = true
	var cur: Vector2 = btn.scale
	var tween := create_tween()
	tween.tween_property(btn, "scale", cur * 0.92, 0.06)
	tween.tween_property(btn, "scale", cur, 0.18) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await tween.finished
	get_tree().change_scene_to_file("res://scenes/level_3d.tscn")

# One step of the cowboy's walk: advance his arc-length and pan the view to
# follow (which also repositions his marker via _place_cowboy_marker).
func _set_cowboy_s(s: float) -> void:
	_cowboy_s = s
	_set_focus_s(s)

func _to_main_menu() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

# ---------------------------------------------------------------------------
# Iter 161: debug-build-only tap-area + coordinate-grid overlay.
# ---------------------------------------------------------------------------

# Build the overlay (debug builds only — release never shows it). Captures
# each tap area's resting on-screen quad and hands them to the overlay,
# which draws a 100px grid + outlined polygons + (x,y) readouts.
func _build_debug_overlay() -> void:
	if not SHOW_TAP_OVERLAY or not OS.has_feature("debug"):
		return
	var overlay = preload("res://scripts/debug_tap_overlay.gd").new()
	var t: Array = []
	t.append({"name": "Humbug", "color": Color(1.0, 0.30, 0.55),
		"quad": _control_screen_quad(humbug)})
	t.append({"name": "CanardZone", "color": Color(0.25, 0.85, 1.0),
		"quad": _control_screen_quad(canard_zone)})
	t.append({"name": "BackButton", "color": Color(1.0, 0.70, 0.20),
		"quad": _control_screen_quad(back_button)})
	# The speech/thought bubble's resting rect (it only exists on tap).
	t.append({"name": "HumbugBubble", "color": Color(0.80, 0.55, 1.0),
		"quad": PackedVector2Array([
			BUBBLE_POS,
			BUBBLE_POS + Vector2(BUBBLE_SIZE.x, 0.0),
			BUBBLE_POS + BUBBLE_SIZE,
			BUBBLE_POS + Vector2(0.0, BUBBLE_SIZE.y),
		])})
	for nm in LEVEL_NODE_NAMES:
		var node: Control = get_node_or_null(NodePath(nm)) as Control
		if node != null:
			t.append({"name": nm, "color": Color(0.45, 1.0, 0.45),
				"quad": _control_screen_quad(node)})
	overlay.targets = t
	var layer := CanvasLayer.new()
	layer.layer = 128  # above the UI layer — grid sits on top of everything
	layer.add_child(overlay)
	add_child(layer)
	DebugLog.add("level_select: debug tap+grid overlay built (%d targets)" % t.size())

# A control's true on-screen quad — the four corners of its local rect run
# through the global transform, so scale / rotation / pivot are honored
# (get_global_rect() would miss the perspective scaling on level nodes).
func _control_screen_quad(c: Control) -> PackedVector2Array:
	var xf: Transform2D = c.get_global_transform()
	var s: Vector2 = c.size
	return PackedVector2Array([
		xf * Vector2(0.0, 0.0),
		xf * Vector2(s.x, 0.0),
		xf * Vector2(s.x, s.y),
		xf * Vector2(0.0, s.y),
	])
