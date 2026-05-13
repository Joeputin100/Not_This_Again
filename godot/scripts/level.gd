extends Node2D

# Phase 1 level: 3 math gates scroll toward the cowboy. Posse count
# updates per gate. When all gates have fired, the WinOverlay slides in
# with the final bounty, an AGAIN button replays the level. Back gesture
# returns to menu mid-run or post-win.

const MovementBounds = preload("res://scripts/movement_bounds.gd")
const GateHelper = preload("res://scripts/gate_helper.gd")
const LevelProgressScript = preload("res://scripts/level_progress.gd")
const ScreenShakeScript = preload("res://scripts/screen_shake.gd")
const CombosCounterScript = preload("res://scripts/combos_counter.gd")
const Collision2D = preload("res://scripts/collision_2d.gd")
const BulletScene = preload("res://scenes/bullet.tscn")
const BulletScript = preload("res://scripts/bullet.gd")
const BarrelScript = preload("res://scripts/barrel.gd")
const TumbleweedScript = preload("res://scripts/tumbleweed.gd")
const CactusScript = preload("res://scripts/cactus.gd")
const BarricadeScript = preload("res://scripts/barricade.gd")
const ChickenCoopScript = preload("res://scripts/chicken_coop.gd")
const ChickenScript = preload("res://scripts/chicken.gd")
const BullScript = preload("res://scripts/bull.gd")
const OutlawScript = preload("res://scripts/outlaw.gd")
const OutlawBulletScript = preload("res://scripts/outlaw_bullet.gd")
const ProspectorScript = preload("res://scripts/prospector.gd")
const GunScript = preload("res://scripts/gun.gd")
const GunStateScript = preload("res://scripts/gun_state.gd")
const PosseRendererScript = preload("res://scripts/posse_renderer.gd")
const BonusScript = preload("res://scripts/bonus.gd")
const WeatherScript = preload("res://scripts/weather.gd")
const WeatherManagerScript = preload("res://scripts/weather_manager.gd")
const MuzzleFlashScene = preload("res://scenes/muzzle_flash.tscn")
const FlourishBanner = preload("res://scripts/flourish_banner.gd")
const DamagePopup = preload("res://scripts/damage_popup.gd")
const WeaponFactoryScript = preload("res://scripts/weapons.gd")

const FOLLOW_SPEED: float = 12.0
const STARTING_POSSE: int = 5

# Iter 22d: weather chosen per-level. Simplest activation — designer sets
# this in the scene tree (or leave default). Future: random per run, or
# tied to level number. Default DUST_STORM so the very first sideload
# after iter 22d ships shows the new feature on screen without any
# tweaking.
@export var weather_type: String = "DUST_STORM"

# Bullets spawn this far above the cowboy each shot.
const BULLET_SPAWN_Y_OFFSET: float = -120.0
# Iter 31: muzzle flash anchors to the cowboy's gun HAND in the
# posse_idle_00 sprite — not above the head where the bullets spawn.
# Visually reads as "the flash is at the barrel."
const DUDE_MUZZLE_OFFSET: Vector2 = Vector2(28, -60)

# Approximate cowboy hit box for barrel collision detection.
const COWBOY_SIZE: Vector2 = Vector2(120, 200)

@onready var cowboy: Node2D = $Cowboy
@onready var posse_renderer: Node2D = $PosseRenderer
@onready var camera: Camera2D = $Camera
@onready var posse_label: Label = $UI/PosseCount
@onready var ammo_label: Label = $UI/AmmoLabel
@onready var debug_label: Label = $UI/DebugInfo
@onready var in_level_menu_button: Button = $UI/InLevelMenuButton
@onready var win_overlay: CanvasLayer = $WinOverlay
@onready var win_panel: Control = $WinOverlay/WinPanel
@onready var win_subtitle: Label = $WinOverlay/WinPanel/WinSubtitle
@onready var again_button: Button = $WinOverlay/WinPanel/PlayAgainButton
@onready var menu_button: Button = $WinOverlay/WinPanel/MenuButton
# Iter 40c: posse-wipe fail modal. Mirrors WinOverlay structure.
@onready var fail_overlay: CanvasLayer = $FailOverlay
@onready var fail_panel: Control = $FailOverlay/FailPanel
@onready var fail_retry_button: Button = $FailOverlay/FailPanel/RetryButton
@onready var fail_menu_button: Button = $FailOverlay/FailPanel/MenuButton
@onready var weather_manager: Node2D = $WeatherManager

var target_x: float
var _input_event_count: int = 0
var _process_run_count: int = 0
var _last_input_type: String = "(none yet)"
var _last_event_class: String = "(none)"

# Posse gun & per-shooter state. Iter 21+: each posse member will own
# their own GunState; for now the cowboy is the only shooter. Gun is a
# Resource (data); GunState is RefCounted (per-shooter runtime). The
# starting gun is a Six-Shooter — see scripts/gun.gd for stats.
var _gun: Resource
var _gun_state: RefCounted
var _bullets_fired: int = 0
var _barrels_destroyed: int = 0

# When false, _spawn_bullet() is a no-op. Set to false on win so we don't
# keep showering the (now-decorative) screen with bullets during the
# victory overlay.
var _shooting_active: bool = true

# Iter 41: Sugar Rush ("Jelly Bean Frenzy"). When _frenzy_active is true,
# _spawn_bullet emits three bullets in a ±15° fan instead of one straight
# bullet. _frenzy_timer counts down in _process; on hitting 0 the flag
# clears. Activation comes from picking up a "jelly_frenzy" bonus barrel
# (see _equip_bonus). 5-second burst, no overlap (a second pickup during
# an active frenzy just refreshes the timer to 5).
var _frenzy_active: bool = false
var _frenzy_timer: float = 0.0
const FRENZY_DURATION: float = 5.0
const FRENZY_FAN_ANGLE_DEG: float = 15.0
const FRENZY_FAN_SHOTS: int = 3

# Iter 41: kill-streak tracking for JUICY (3 kills in 2s) and RAMPAGE
# (5 in 5s). Banner emission is rate-limited so successive streaks
# don't spam the screen. Timestamps are seconds since process start.
var _kill_timestamps: Array[float] = []
var _last_juicy_time: float = -10.0
var _last_rampage_time: float = -10.0
const JUICY_WINDOW: float = 2.0
const JUICY_THRESHOLD: int = 3
const JUICY_COOLDOWN: float = 3.0
const RAMPAGE_WINDOW: float = 5.0
const RAMPAGE_THRESHOLD: int = 5
const RAMPAGE_COOLDOWN: float = 6.0

# Iter 40c: latches true when posse_count hits 0 mid-level. Triggers the
# fail modal + spends a heart. Independent of the win path — once
# _failed is true, win conditions are short-circuited too (no
# simultaneous WIN+FAIL flashes).
var _failed: bool = false

# Iter 37: level-end is gated on TWO conditions instead of just gates-done.
#   _gates_complete  — last gate has fired
#   _boss_defeated   — Slippery Pete (or any 'bosses' group member)
#                      destroyed
# Both true → _show_win. Until then, gameplay continues so the player
# can actually fight the boss with the posse they have left.
var _gates_complete: bool = false
var _boss_defeated: bool = false

# Iter 22d weather state. WeatherManager.apply_weather() mutates these
# at level start. Defaults are identity values (no effect) so a level
# without weather behaves exactly like pre-iter-22d.
#
#   steering_speed_mult — multiplied into FOLLOW_SPEED in the cowboy
#                         lerp. DUST_STORM drops this to 0.7.
#   cowboy_wind_drift_x — px/sec added to target_x each frame regardless
#                         of player input. WIND_STORM sets this to ±25.
#   bullet_velocity_mult, bullet_lateral_drift — passed to spawned
#                         bullets in _spawn_bullet().
var steering_speed_mult: float = 1.0
var cowboy_wind_drift_x: float = 0.0
var bullet_velocity_mult: float = 1.0
var bullet_lateral_drift: float = 0.0

# Run-local state. Resets each level.
# Iter 40c: posse is mortal now. The setter clamps to 0 (was 1 — the
# leader cowboy used to be immortal). When posse_count transitions to
# 0, fail the level: deduct a heart and pop the fail modal.
var posse_count: int = STARTING_POSSE:
	set(value):
		posse_count = maxi(0, value)
		_refresh_posse_label()
		# Push count to the renderer so trapezoid grows/shrinks in sync
		# with gameplay. Guarded — setter can fire before _ready resolves
		# the @onready var (e.g. during scene-load defaults).
		if posse_renderer:
			posse_renderer.posse_count = posse_count
		# Iter 40c: catch the death moment. _failed latch prevents
		# re-triggering if more damage lands in the same frame.
		# Iter 46: skip the fail flow entirely in test range mode so
		# the user can stress-test weapons + posse without restarts.
		if posse_count == 0 and not _failed and not _test_range_mode:
			_failed = true
			_show_fail()

var progress: RefCounted
var shake: RefCounted
var combos: RefCounted

func _ready() -> void:
	DebugLog.add("level _ready start")
	# Belt-and-suspenders: also disable quit-on-go-back at runtime in case
	# the project.godot setting doesn't reach Android's Activity layer.
	get_tree().set_quit_on_go_back(false)
	# Third route: also connect to the Window's go_back_requested signal
	# directly. Godot emits this in parallel with NOTIFICATION_WM_GO_BACK_
	# REQUEST, so if one path is intercepted at the Java layer, the other
	# might still fire. Each handler logs to DebugLog so the user's COPY
	# button output reveals which (if either) actually ran.
	get_window().go_back_requested.connect(_on_back_requested_signal)
	DebugLog.add("level: quit_on_go_back=%s" % str(get_tree().is_quit_on_go_back()))
	target_x = cowboy.position.x
	# Iter 54: load per-level resource based on GameState.current_level.
	# Falls back to the @export defaults if the resource is missing
	# (handles first-launch + dev-time scene execution).
	_load_level_def()
	# Iter 42b: reset world scroll speed to neutral on each level entry,
	# so the player's finger position from the previous level/menu doesn't
	# carry over and a fresh level starts at the documented baseline.
	WorldSpeed.reset()
	progress = LevelProgressScript.new()
	shake = ScreenShakeScript.new()
	combos = CombosCounterScript.new()
	_gun = GunScript.new()
	_gun_state = GunStateScript.new(_gun)

	# Seed the posse renderer with the starting count so followers appear
	# on frame 0 (before the first gate trigger). PosseRenderer is a
	# sibling Node2D placed BEFORE Cowboy in the scene tree, so followers
	# draw behind the leader (cleaner Z-order, leader visually in front).
	if posse_renderer:
		posse_renderer.posse_count = posse_count

	# Iter 22d: weather is applied AFTER the gun exists (it may mutate
	# _gun.range_px) and AFTER the cowboy is positioned. WeatherManager
	# is a Node2D child placed in the scene tree (level.tscn); see
	# weather_manager.gd for the full mutation list.
	if weather_manager:
		weather_manager.apply_weather(weather_type, self)

	# Iter 37: hook the boss's destroyed signal so the level only ends
	# AFTER both gates pass AND Pete (or any boss) is dead. If no boss
	# is in the scene, _boss_defeated starts true so old levels behave
	# unchanged (gates-only win condition).
	var bosses: Array = get_tree().get_nodes_in_group("bosses")
	if bosses.is_empty():
		_boss_defeated = true
	else:
		for boss in bosses:
			if boss.has_signal("destroyed"):
				boss.destroyed.connect(_on_boss_destroyed)
			# Iter 40c: stop terrain scroll when boss reaches STAY mode.
			# The showdown is an event — no more "running forward" until
			# the duel resolves. Only Pete has the `engaged` signal so
			# far; future bosses can opt in by emitting it.
			if boss.has_signal("engaged"):
				boss.engaged.connect(_on_boss_engaged)

	# Discover all gates by group instead of hand-listing — adding a 4th
	# gate to the scene tree later won't require code changes here.
	var gates := _gather_gates()
	progress.reset(gates.size())
	for gate in gates:
		gate.triggered.connect(_on_gate_triggered.bind(gate))
		gate.direction_flipped.connect(_on_gate_direction_flipped)

	again_button.pressed.connect(_on_again_pressed)
	menu_button.pressed.connect(_on_menu_pressed)
	# Iter 40c: fail-modal buttons. Same RETRY/MENU dichotomy as win flow.
	if fail_retry_button:
		fail_retry_button.pressed.connect(_on_fail_retry_pressed)
	if fail_menu_button:
		fail_menu_button.pressed.connect(_on_fail_menu_pressed)
	# Pivot for the fail panel scale-in animation (same dims as win panel).
	if fail_panel:
		fail_panel.pivot_offset = Vector2(440, 280)
	# In-level MENU button (top-left corner). Workaround for the back-
	# gesture-still-exits-app bug — gives the player a reliable way to
	# leave a level without quitting the whole app.
	if in_level_menu_button:
		in_level_menu_button.pressed.connect(_on_in_level_menu_pressed)
	# Pivot for the win panel scale-in animation
	win_panel.pivot_offset = Vector2(440, 280)
	# Iter 45-46: debug-menu preview — if the menu set a pending rush,
	# sugar rush, or test_range flag before changing scene here, honor
	# it now. Test range strips all gates/enemies and rebuilds the scene
	# as a stationary 6×6 cactus field for weapon/posse experimentation.
	if get_node_or_null("/root/DebugPreview") and DebugPreview.has_pending():
		if DebugPreview.pending_test_range:
			_test_range_mode = true
			DebugPreview.clear()
			DebugLog.add("debug preview: TEST RANGE (cactus field)")
			call_deferred("_setup_test_range")
		elif DebugPreview.pending_rush != "":
			_debug_override_rush = DebugPreview.pending_rush
			DebugLog.add("debug preview: rush %s" % _debug_override_rush)
			DebugPreview.clear()
			# Suppress normal gate/boss flow — go straight to win.
			_gates_complete = true
			_boss_defeated = true
			call_deferred("_show_win")
		elif DebugPreview.pending_sugar_rush:
			DebugPreview.clear()
			DebugLog.add("debug preview: sugar rush")
			# Brief delay so the level visibly starts before frenzy kicks in
			call_deferred("_deferred_debug_sugar_rush")
	# Iter 41: subscribe to every killable entity's `destroyed` signal so
	# we can run kill-streak detection (JUICY/RAMPAGE banners) from one
	# place. Group memberships were registered in each entity's _ready,
	# which runs BEFORE level.gd's _ready in Godot's scene-tree order —
	# so by the time we reach this line, every pre-placed enemy is
	# already in its group. Dynamically-spawned ones (chicken_coop's
	# chickens) don't fire destroyed signals so they're not tracked.
	for group_name in ["barrels", "bulls", "outlaws", "prospectors",
			"tumbleweeds", "cacti"]:
		for node in get_tree().get_nodes_in_group(group_name):
			if node.has_signal("destroyed"):
				node.destroyed.connect(_on_kill_tracked)
	_refresh_posse_label()
	# Diagnostic: mark that _ready completed end-to-end.
	if debug_label:
		debug_label.text = "READY OK (process not yet ticked)"
	DebugLog.add("level _ready end (gates=%d, cowboy=%s)" % [
		_gather_gates().size(),
		"ok" if cowboy != null else "NULL",
	])

func _gather_gates() -> Array[Node]:
	var gates: Array[Node] = []
	for child in get_children():
		if child.has_signal("triggered") and child.has_method("_format_left"):
			gates.append(child)
	return gates

func _process(delta: float) -> void:
	_process_run_count += 1
	# Iter 41: tick the Jelly Bean Frenzy timer. When it expires the
	# burst ends and _spawn_bullet reverts to single-shot. No banner on
	# expiry — the visible end-of-fan stream is its own readable signal.
	if _frenzy_active:
		_frenzy_timer -= delta
		if _frenzy_timer <= 0.0:
			_frenzy_active = false
			DebugLog.add("jelly frenzy ended")
	# Wind drift — push target_x sideways every frame, even when the
	# player isn't dragging. Player input still overrides instantly via
	# _input() setting target_x to the new touch position; the wind just
	# keeps nudging in between drags. Clamp to playable bounds so we
	# don't overshoot past the lane guides.
	if cowboy_wind_drift_x != 0.0:
		target_x = MovementBounds.clamp_x(target_x + cowboy_wind_drift_x * delta)
	# Steering lerp scaled by weather (DUST_STORM = 0.7×, default 1.0).
	cowboy.position.x = lerpf(cowboy.position.x, target_x, FOLLOW_SPEED * steering_speed_mult * delta)
	# Drive screen shake. CanvasLayer-rooted UI is unaffected; only
	# world-space nodes (background, lane guides, gates, cowboy) shake.
	camera.offset = shake.tick(delta)

	# Auto-fire driven by gun_state. tick() advances cooldown + reload
	# timers; while can_fire() is true we burst out as many shots as the
	# accumulated delta allows (typically 0 or 1 per frame at 60fps).
	# Iter 37: gate the entire firing loop on _shooting_active. When the
	# level ends, we don't want the gun to keep ticking down its reload
	# timer and visually refill the ammo bar — the firefight is over.
	if _shooting_active:
		_gun_state.tick(delta)
		while _gun_state.can_fire():
			_gun_state.fire()
			_spawn_bullet()

	# Anchor the posse renderer to the leader BEFORE collision passes.
	# Followers don't have hit boxes — only the cowboy node does — so
	# this is purely a visual update. Cheap (single position assignment).
	if posse_renderer:
		posse_renderer.set_leader_position(cowboy.position)

	# Bullet ↔ obstacle / gate collision passes. O(bullets × obstacles)
	# per frame, trivial at this scale.
	_resolve_bullet_barrel_collisions()
	_resolve_bullet_gate_collisions()
	_resolve_bullet_obstacle_collisions("tumbleweeds", TumbleweedScript.SIZE)
	_resolve_bullet_obstacle_collisions("cacti", CactusScript.SIZE)
	_resolve_bullet_obstacle_collisions("barricades", BarricadeScript.SIZE)
	_resolve_bullet_obstacle_collisions("chicken_coops", ChickenCoopScript.SIZE)
	_resolve_bullet_obstacle_collisions("chickens", ChickenScript.SIZE)
	_resolve_bullet_obstacle_collisions("bulls", BullScript.SIZE)
	_resolve_bullet_obstacle_collisions("outlaws", OutlawScript.SIZE)
	_resolve_bullet_obstacle_collisions("prospectors", ProspectorScript.SIZE)
	# Cowboy ↔ obstacle collision passes (posse damage).
	_resolve_barrel_cowboy_collisions()
	_resolve_obstacle_cowboy_collisions("tumbleweeds", TumbleweedScript.SIZE)
	_resolve_obstacle_cowboy_collisions("cacti", CactusScript.SIZE)
	_resolve_obstacle_cowboy_collisions("barricades", BarricadeScript.SIZE)
	_resolve_obstacle_cowboy_collisions("bulls", BullScript.SIZE)
	# Outlaws + prospectors are NOT in the generic cowboy-collision pass
	# (which one-shot-destroys obstacles on contact). They need to
	# survive contact and keep crowding the posse — handled separately
	# below. Their ranged + melee damage paths run independently.
	# Iter 31: outlaw bullets do per-dude collision (cowboy + each
	# follower), each hit kills ONE specific dude (POSSE_DAMAGE=1).
	_resolve_outlaw_bullet_dude_collisions()
	# Iter 31: prospectors swing pickaxes at melee range, dealing
	# SWING_DAMAGE per swing on a SWING_INTERVAL cadence while in
	# contact with the cowboy.
	_resolve_prospector_melee_collisions()
	# chicken_coops and chickens have get_cowboy_damage() == 0, so we
	# skip them in the cowboy-collision pass (no point processing).
	# Bonuses are auto-equipped on cowboy contact (no tap-to-take prompt).
	_resolve_bonus_cowboy_collisions()

	_refresh_ammo_label()
	# Diagnostic — fallback to get_node in case @onready ref is stale.
	var dbg := debug_label if debug_label != null else get_node_or_null("UI/DebugInfo") as Label
	if dbg:
		var ammo_str: String = ("RLD %.0f%%" % (_gun_state.reload_progress() * 100.0)) \
			if _gun_state.is_reloading() else ("%d/%d" % [_gun_state.ammo(), _gun.clip_size])
		dbg.text = "proc:%d input:%d type:%s\ntarget_x:%.0f cowboy_x:%.0f bullets:%d ammo:%s barrels_dead:%d" % [
			_process_run_count, _input_event_count, _last_input_type,
			target_x, cowboy.position.x,
			_bullets_fired, ammo_str, _barrels_destroyed,
		]

func _spawn_bullet() -> void:
	if not _shooting_active:
		return
	# Iter 41: Jelly Bean Frenzy fans bullets out at ±FRENZY_FAN_ANGLE_DEG.
	# Three projectiles total: one straight, one angled left, one angled
	# right. Bullets use velocity to move (their lateral_drift property
	# already supports per-frame x-drift); we set initial drifts derived
	# from the fan angle so they spread visibly as they travel upward.
	if _frenzy_active:
		_spawn_frenzy_fan()
		return
	# Muzzle flash burst — leader gets a flash as a CHILD anchored at
	# the cowboy's gun-hand (DUDE_MUZZLE_OFFSET) so the flash reads at
	# the barrel rather than floating above the head. Followers each
	# get a flash at THEIR world position + the same hand offset.
	# Iter 31: flash size is 1/3 of iter 23 (muzzle_flash.tscn scale
	# 0.5 → 0.17), so 5-dude posse fire bursts read as small chest-
	# height pops instead of head-sized blasts.
	var leader_flash := MuzzleFlashScene.instantiate()
	leader_flash.position = DUDE_MUZZLE_OFFSET
	cowboy.add_child(leader_flash)
	if posse_renderer:
		for follower_pos in posse_renderer.get_dude_world_positions():
			var ff := MuzzleFlashScene.instantiate()
			ff.position = follower_pos + DUDE_MUZZLE_OFFSET
			add_child(ff)

	# Iter 37: gunshot SFX. Fires once per posse bullet — rapid fire
	# rolls through AudioBus's 6-player gunfire pool so the shots stack
	# instead of cutting each other off.
	AudioBus.play_gunfire()
	# Iter 56: multi-bullet weapons (bullets_per_shot > 1) spawn a fan of
	# bullets per fire trigger. Single-shot weapons hit this loop once.
	#
	# Iter 61: EVERY dude in the posse fires, not just the leader. Build
	# the list of firing positions (leader + every active follower); the
	# fan-spread inner loop runs PER POSITION. Followers fan-fire too —
	# Jelly Bean Frenzy still applies to all of them.
	var fire_positions: Array[Vector2] = [cowboy.position]
	if posse_renderer:
		for follower_pos in posse_renderer.get_dude_world_positions():
			fire_positions.append(follower_pos)
	var shots: int = maxi(_gun.bullets_per_shot, 1)
	var spread: float = _gun.spread_radians
	for fire_pos in fire_positions:
		for s in range(shots):
			var bullet := BulletScene.instantiate()
			bullet.position = fire_pos + Vector2(0, BULLET_SPAWN_Y_OFFSET)
			bullet.max_range = _gun.range_px
			bullet.damage = _gun.caliber
			bullet.velocity_mult = bullet_velocity_mult
			var off: float = 0.0
			if shots > 1:
				off = lerpf(-spread, spread, float(s) / float(shots - 1))
			bullet.lateral_drift = bullet_lateral_drift + tan(off) * BulletScript.SPEED
			bullet.pierce_remaining = _gun.pierce_count
			bullet.aoe_radius = _gun.aoe_radius
			bullet.freeze_duration_s = _gun.freeze_duration_s
			bullet.slow_duration_s = _gun.slow_duration_s
			add_child(bullet)
			_bullets_fired += 1

# Iter 41: Jelly Bean Frenzy multi-shot. Spawns FRENZY_FAN_SHOTS bullets
# in a fan, each with a lateral_drift derived from its angle off-axis.
# Skips the muzzle flash duplication (single center flash is plenty
# read; three flashes would just blow out the visual).
func _spawn_frenzy_fan() -> void:
	var leader_flash := MuzzleFlashScene.instantiate()
	leader_flash.position = DUDE_MUZZLE_OFFSET
	cowboy.add_child(leader_flash)
	AudioBus.play_gunfire()
	var center: int = (FRENZY_FAN_SHOTS - 1) / 2  # 0,1,2 → center index 1
	for i in range(FRENZY_FAN_SHOTS):
		var bullet := BulletScene.instantiate()
		bullet.position = cowboy.position + Vector2(0, BULLET_SPAWN_Y_OFFSET)
		bullet.max_range = _gun.range_px
		bullet.damage = _gun.caliber
		bullet.velocity_mult = bullet_velocity_mult
		# Convert the fan offset into a lateral drift. Outer bullets
		# (i=0, i=2) drift sideways at ±tan(15°) × bullet vertical speed.
		# Center bullet (i=1) gets the level's normal drift only.
		var off: int = i - center
		var angle_rad: float = deg_to_rad(FRENZY_FAN_ANGLE_DEG) * float(off)
		bullet.lateral_drift = bullet_lateral_drift + tan(angle_rad) * BulletScript.SPEED
		add_child(bullet)
		_bullets_fired += 1

# Iter 41: invoked from each entity's `destroyed` signal (connected in
# _ready). Maintains _kill_timestamps + checks streak thresholds for
# JUICY (3 in 2s) and RAMPAGE (5 in 5s). Each banner has its own
# cooldown so successive bursts of kills don't spam the screen.
func _on_kill_tracked(_x: float) -> void:
	var now: float = Time.get_ticks_msec() / 1000.0
	_kill_timestamps.append(now)
	# Prune anything older than RAMPAGE_WINDOW; we never need older
	# timestamps and the array bloats over a long level otherwise.
	var cutoff: float = now - RAMPAGE_WINDOW
	while not _kill_timestamps.is_empty() and _kill_timestamps[0] < cutoff:
		_kill_timestamps.pop_front()
	# RAMPAGE check first (higher tier) — if it fires, suppress JUICY
	# this same frame so the player doesn't read two banners stacking.
	if _kill_timestamps.size() >= RAMPAGE_THRESHOLD \
			and (now - _last_rampage_time) > RAMPAGE_COOLDOWN:
		_last_rampage_time = now
		FlourishBanner.spawn($UI, "RAMPAGE!", self)
		return
	var recent_juicy: int = 0
	var juicy_cutoff: float = now - JUICY_WINDOW
	for t in _kill_timestamps:
		if t >= juicy_cutoff:
			recent_juicy += 1
	if recent_juicy >= JUICY_THRESHOLD \
			and (now - _last_juicy_time) > JUICY_COOLDOWN:
		_last_juicy_time = now
		FlourishBanner.spawn($UI, "JUICY!", self)

func _resolve_bullet_barrel_collisions() -> void:
	var bullets := get_tree().get_nodes_in_group("bullets")
	var barrels := get_tree().get_nodes_in_group("barrels")
	if bullets.is_empty() or barrels.is_empty():
		return
	for bullet in bullets:
		for barrel in barrels:
			if Collision2D.rects_overlap(
					bullet.position, BulletScript.SIZE,
					barrel.position, BarrelScript.SIZE):
				# Iter 56: pierce_remaining > 0 means the bullet survives this
				# hit and continues. Decrement; bullet only despawns when
				# pierce hits 0 in the despawn site below.
				var was_destroyed: bool = barrel.take_damage(bullet.damage)
				if was_destroyed:
					_barrels_destroyed += 1
					# Iter 42a: TASTY!/ACCEPTABLE. flourish on the loot
					# reveal — only barrels carrying a bonus trigger this,
					# so it reads as "good shot, payoff appearing." Plain
					# (no-bonus) barrels stay on the kill-streak path.
					if barrel.bonus_type != "":
						FlourishBanner.spawn($UI, "TASTY!", self)
					shake.add_trauma(0.4)
				# Iter 57: route through _consume_bullet so pierce+AOE
				# weapons compose. Returns true if the bullet was truly
				# despawned; false if it pierced through and survives.
				if _consume_bullet(bullet, bullet.position):
					break  # this bullet is done; move to next bullet

func _resolve_bullet_gate_collisions() -> void:
	# Discover gates via _gather_gates (same duck-type check used in
	# _ready). Then for each unfired gate, check overlap with each
	# bullet — additive gates bump their values, mult gates just
	# absorb. Either way the bullet is consumed.
	var bullets := get_tree().get_nodes_in_group("bullets")
	if bullets.is_empty():
		return
	var gates := _gather_gates()
	if gates.is_empty():
		return
	for bullet in bullets:
		for gate in gates:
			if Collision2D.rects_overlap(
					bullet.position, BulletScript.SIZE,
					gate.position, gate.SIZE):
				# Iter 25+: bullet hits only the door it actually overlaps.
				# Side from bullet.x vs gate.x — left door if bullet.x is
				# left of gate center, right door otherwise. Fixes the bug
				# where shooting the right door also incremented left.
				var side: int = GateHelper.SIDE_LEFT if bullet.position.x < gate.position.x else GateHelper.SIDE_RIGHT
				var consumed: bool = gate.take_bullet_hit(bullet.damage, side)
				if consumed:
					if _consume_bullet(bullet, bullet.position):
						break

func _resolve_bullet_obstacle_collisions(group_name: String, obstacle_size: Vector2) -> void:
	# Generic bullet-vs-group collision pass. Each obstacle (tumbleweed,
	# cactus, barricade) defines take_bullet_hit() returning whether the
	# bullet is consumed. We call it on overlap and free the bullet.
	var bullets := get_tree().get_nodes_in_group("bullets")
	if bullets.is_empty():
		return
	var obstacles := get_tree().get_nodes_in_group(group_name)
	if obstacles.is_empty():
		return
	for bullet in bullets:
		for obstacle in obstacles:
			if Collision2D.rects_overlap(
					bullet.position, BulletScript.SIZE,
					obstacle.position, obstacle_size):
				var hit: bool = obstacle.take_bullet_hit(bullet.damage)
				if hit:
					# Iter 57: same pierce/AOE composition as barrel pass.
					if _consume_bullet(bullet, bullet.position):
						break  # this bullet is done

func _resolve_obstacle_cowboy_collisions(group_name: String, obstacle_size: Vector2) -> void:
	# Cowboy-vs-group collision pass. On contact: posse takes the
	# obstacle's declared damage, obstacle is destroyed (if destructible)
	# or just persists (barricade) — we free non-destructible ones too
	# so they don't keep colliding frame after frame.
	for obstacle in get_tree().get_nodes_in_group(group_name):
		if obstacle.get("_destroyed") == true:
			continue
		if not Collision2D.rects_overlap(
				obstacle.position, obstacle_size,
				cowboy.position, COWBOY_SIZE):
			continue
		var damage: int = obstacle.get_cowboy_damage()
		DebugLog.add("%s hit cowboy → posse -%d" % [group_name, damage])
		posse_count = maxi(0, posse_count - damage)
		_pulse_posse_label()
		shake.add_trauma(minf(0.4 + damage * 0.05, 0.95))
		# Destroy destructibles via take_damage if available, otherwise
		# queue_free directly (barricades don't have take_damage).
		if obstacle.has_method("take_damage"):
			obstacle.take_damage(99999)  # overkill
		else:
			obstacle.queue_free()

# Iter 31+: outlaw bullets do per-dude collision. Check against the
# leader (cowboy node) AND each active follower. On hit, kill that
# specific dude — POSSE_DAMAGE = 1 per bullet (single, one-shot).
# For the leader: cowboy node is the gameplay input target, so it
# can't visibly die without breaking input. Instead, when a bullet
# hits the leader hitbox, we decrement posse_count and let the renderer
# remove the rear-most follower (lore: "a dude in your posse took
# the hit and fell"). For followers: the SPECIFIC hit follower fades
# out via kill_specific_dude.
func _resolve_outlaw_bullet_dude_collisions() -> void:
	for bullet in get_tree().get_nodes_in_group("outlaw_bullets"):
		# 1) Leader (cowboy) hit?
		if Collision2D.rects_overlap(
				bullet.position, OutlawBulletScript.SIZE,
				cowboy.position, COWBOY_SIZE):
			DebugLog.add("outlaw bullet hit leader → posse -%d" % OutlawBulletScript.POSSE_DAMAGE)
			posse_count = maxi(0, posse_count - OutlawBulletScript.POSSE_DAMAGE)
			_pulse_posse_label()
			shake.add_trauma(0.25)
			bullet.queue_free()
			continue
		# 2) Follower hit? Check each active follower's world rect.
		if posse_renderer == null:
			continue
		var killed: bool = false
		for fr in posse_renderer.get_follower_world_rects():
			if not Collision2D.rects_overlap(
					bullet.position, OutlawBulletScript.SIZE,
					fr.position, fr.size):
				continue
			DebugLog.add("outlaw bullet hit follower → posse -%d (specific kill)" % OutlawBulletScript.POSSE_DAMAGE)
			posse_renderer.kill_specific_dude(fr.node)
			# Decrement posse_count AFTER kill_specific_dude so the
			# renderer's setter detects state alignment and skips rebuild.
			posse_count = maxi(0, posse_count - OutlawBulletScript.POSSE_DAMAGE)
			_pulse_posse_label()
			shake.add_trauma(0.25)
			bullet.queue_free()
			killed = true
			break
		if killed:
			continue

# Iter 31+: prospector melee. Each prospector that overlaps the cowboy
# (or a follower) gets to try_swing(). The prospector handles its own
# swing cooldown; on a successful swing we deduct SWING_DAMAGE.
func _resolve_prospector_melee_collisions() -> void:
	for p in get_tree().get_nodes_in_group("prospectors"):
		if p.get("_destroyed") == true:
			continue
		var in_range: bool = Collision2D.rects_overlap(
			p.position, ProspectorScript.SIZE,
			cowboy.position, COWBOY_SIZE)
		# Also count follower-range as "in melee" so prospectors can
		# pick off rear dudes too.
		if not in_range and posse_renderer:
			for fr in posse_renderer.get_follower_world_rects():
				if Collision2D.rects_overlap(p.position, ProspectorScript.SIZE, fr.position, fr.size):
					in_range = true
					break
		if not in_range:
			continue
		if p.try_swing():
			DebugLog.add("prospector pickaxe swing → posse -%d" % ProspectorScript.SWING_DAMAGE)
			posse_count = maxi(0, posse_count - ProspectorScript.SWING_DAMAGE)
			_pulse_posse_label()
			shake.add_trauma(0.4)

func _resolve_barrel_cowboy_collisions() -> void:
	# If a barrel reaches the cowboy intact, it slams into the posse:
	# damages posse_count by the barrel's remaining HP, destroys the barrel.
	# The barrel's destroy animation is reused; no separate "explosion".
	for barrel in get_tree().get_nodes_in_group("barrels"):
		if barrel._destroyed:
			continue
		if Collision2D.rects_overlap(
				barrel.position, BarrelScript.SIZE,
				cowboy.position, COWBOY_SIZE):
			var damage: int = barrel.hp
			DebugLog.add("barrel hit cowboy at hp=%d → posse -%d" % [damage, damage])
			posse_count = maxi(0, posse_count - damage)
			_pulse_posse_label()
			shake.add_trauma(0.65)
			# Force-destroy the barrel (overkill so take_damage returns true).
			# Note: this still triggers the bonus-spawn path in barrel.gd, so
			# the player can recover a power-up even if the barrel rams them.
			barrel.take_damage(barrel.hp)

func _resolve_bonus_cowboy_collisions() -> void:
	# Bonuses auto-equip on cowboy contact — no tap-to-take prompt.
	# Design intent: the choice was made when the player shot (or didn't
	# shoot) the power-up barrel. Walking into the dropped icon is just
	# the follow-through. Adding a confirm tap here would break pacing.
	for bonus in get_tree().get_nodes_in_group("bonuses"):
		if not Collision2D.rects_overlap(
				bonus.position, BonusScript.SIZE,
				cowboy.position, COWBOY_SIZE):
			continue
		# Wire up the signal just-in-time so the test suite can observe
		# equipped() firing without the level having to pre-scan for
		# every spawned bonus. bonus.equip() emits then queue_frees.
		if not bonus.equipped.is_connected(_on_bonus_equipped):
			bonus.equipped.connect(_on_bonus_equipped)
		bonus.equip()

func _on_bonus_equipped(type: String) -> void:
	# Bridge from the bonus's signal to our actual stat-mutation logic.
	# Keeping the dispatch in _equip_bonus means tests can call it
	# directly without spinning up a Bonus node.
	_equip_bonus(type)

# Applies the effect of a bonus to the player's run. Each branch is a
# permanent (run-local) change — no buff timers, no decay. The player
# accepted these effects when they chose to shoot the power-up barrel.
func _equip_bonus(type: String) -> void:
	match type:
		"fast_fire":
			# 30% faster fire rate. Multiplicative so stacking pickups
			# compound — but the gun resource is the SAME instance the
			# GunState reads on every fire, so the change applies on the
			# very next shot.
			_gun.fire_interval *= 0.7
			DebugLog.add("bonus equipped: fast_fire → fire_interval=%.3f" % _gun.fire_interval)
		"extra_dude":
			# +2 posse members. posse_count setter clamps to >= 1 and
			# refreshes the on-screen label.
			posse_count += 2
			_pulse_posse_label()
			DebugLog.add("bonus equipped: extra_dude → posse_count=%d" % posse_count)
		"jelly_frenzy":
			# Iter 41: Sugar Rush equivalent. 5-second burst of rainbow
			# triple-stream bullets. Banner pops on activation;
			# _spawn_bullet observes _frenzy_active to fan out shots.
			# Refreshes (not stacks) if picked up during an active burst.
			_frenzy_active = true
			_frenzy_timer = FRENZY_DURATION
			FlourishBanner.spawn($UI, "JELLY_FRENZY", self)
			DebugLog.add("bonus equipped: jelly_frenzy → %ss burst" % FRENZY_DURATION)
		"marshmallow_sheriff":
			# Iter 59: hero unlock. Sheriff joins as a special posse
			# member (+2 dudes), cowboy swaps to the Marshmallow Cannon.
			posse_count += 2
			_gun = WeaponFactoryScript.gun_for_slug("marshmallow_cannon")
			if _gun:
				_gun_state = GunStateScript.new(_gun)
			_spawn_hero_marker("MARSHMALLOW SHERIFF",
				Color(1.0, 1.0, 0.95, 1.0),
				Color(0.95, 0.55, 0.20, 1.0))
			FlourishBanner.spawn($UI, "MEGA!", self)
			DebugLog.add("bonus equipped: marshmallow_sheriff → Marshmallow Cannon")
		"laughing_horse":
			# Iter 60: hero unlock. Horse joins (+1 dude), cowboy swaps to
			# the Stun Whinny (caliber 0, 2s freeze on hit, rainbow tint).
			# Rainbow-mane marker with whinny SFX (audible giddyup).
			posse_count += 1
			_gun = WeaponFactoryScript.gun_for_slug("stun_whinny")
			if _gun:
				_gun_state = GunStateScript.new(_gun)
			_spawn_hero_marker("LAUGHING HORSE",
				Color(0.85, 0.55, 0.25, 1.0),
				Color(1.0, 0.55, 0.85, 1.0))
			_spawn_rainbow_mane()
			FlourishBanner.spawn($UI, "MEGA!", self)
			DebugLog.add("bonus equipped: laughing_horse → Stun Whinny")
		"scarecrow":
			# Iter 60: hero unlock. Scarecrow joins as a 200%-size posse
			# member with melee-only attack. No weapon swap — the cowboy
			# keeps current gun. Scarecrow contributes via melee range.
			# Visual marker uses tan + dark green palette (straw + jacket).
			posse_count += 1
			_spawn_hero_marker("SCARECROW",
				Color(0.85, 0.72, 0.45, 1.0),
				Color(0.18, 0.45, 0.22, 1.0))
			FlourishBanner.spawn($UI, "MEGA!", self)
			DebugLog.add("bonus equipped: scarecrow → melee dude")
		"rifle":
			# Tradeoff weapon: caliber 3 (triple damage), 900px range
			# (50% longer), but only 4 rounds, 1.3s reload, 0.30s
			# fire_interval (slower). Genuine player choice — not a
			# strict upgrade. Construct in code; .tres-based gun library
			# arrives in a later iter.
			var rifle: Resource = GunScript.new()
			rifle.display_name = "Rifle"
			rifle.caliber = 3
			rifle.range_px = 900.0
			rifle.fire_interval = 0.30
			rifle.clip_size = 4
			rifle.reload_time = 1.3
			_gun = rifle
			# Reset gun state so the new clip is full immediately. The
			# old state's cooldown/reload are intentionally discarded —
			# picking up a rifle shouldn't carry over a half-reload.
			_gun_state = GunStateScript.new(_gun)
			DebugLog.add("bonus equipped: rifle → caliber=%d range=%.0f" % [_gun.caliber, _gun.range_px])
		_:
			# Iter 56+: try the weapon factory for catalog slugs. If the
			# slug matches a known weapon, swap the active gun. Unknown
			# slugs fall through to the original UNKNOWN log.
			var gun_from_slug: Resource = WeaponFactoryScript.gun_for_slug(type)
			if gun_from_slug:
				_gun = gun_from_slug
				_gun_state = GunStateScript.new(_gun)
				DebugLog.add("bonus equipped: weapon=%s" % _gun.display_name)
			else:
				DebugLog.add("bonus equipped: UNKNOWN type=%s" % type)

func _input(event: InputEvent) -> void:
	# Track ALL inputs to verify _input is being called at all, not just
	# touch-flavored ones.
	_last_event_class = event.get_class()
	var new_x := -1.0
	var new_y := -1.0
	if event is InputEventScreenDrag:
		new_x = (event as InputEventScreenDrag).position.x
		new_y = (event as InputEventScreenDrag).position.y
		_last_input_type = "DRAG"
		_input_event_count += 1
	elif event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed:
		new_x = (event as InputEventScreenTouch).position.x
		new_y = (event as InputEventScreenTouch).position.y
		_last_input_type = "TOUCH"
		_input_event_count += 1
	elif event is InputEventScreenTouch and not (event as InputEventScreenTouch).pressed:
		# Iter 42b: finger lifted — drift speed back to neutral. Tests
		# that hold a touch (sprint mode) shouldn't be stuck there once
		# the touch ends.
		WorldSpeed.set_target(WorldSpeed.NEUTRAL_MULT)
	elif event is InputEventMouseMotion and ((event as InputEventMouseMotion).button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		new_x = (event as InputEventMouseMotion).position.x
		new_y = (event as InputEventMouseMotion).position.y
		_last_input_type = "MOUSE_MOTION"
		_input_event_count += 1
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			new_x = mb.position.x
			new_y = mb.position.y
			_last_input_type = "MOUSE_BUTTON"
			_input_event_count += 1
		elif mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
			WorldSpeed.set_target(WorldSpeed.NEUTRAL_MULT)
	if new_x >= 0.0:
		target_x = MovementBounds.clamp_x(new_x)
	# Iter 42b: vertical finger position controls the world's forward
	# scroll speed. Top of screen = sprint, bottom = slow crawl, middle =
	# neutral. WorldSpeed.set_target lerps from current mult to this
	# target over ~150ms so mid-drag adjustments don't snap-feel jittery.
	# Screen height is the viewport height, hardcoded to match project's
	# 1080×1920 base; if the project later supports landscape this needs
	# to read from get_viewport_rect() instead.
	if new_y >= 0.0:
		WorldSpeed.set_target(WorldSpeed.target_from_touch_y(new_y, 1920.0))

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		# Also handled via go_back_requested signal in _ready. Both can fire;
		# we route the same way regardless of which arrived.
		DebugLog.add("level NOTIFICATION_WM_GO_BACK_REQUEST → menu")
		_go_back_to_menu()
	elif what == NOTIFICATION_WM_CLOSE_REQUEST:
		DebugLog.add("level NOTIFICATION_WM_CLOSE_REQUEST → quit")
		get_tree().quit()

func _on_back_requested_signal() -> void:
	DebugLog.add("level go_back_requested SIGNAL → menu")
	_go_back_to_menu()

# Idempotent — calling twice from both routes is safe; change_scene_to_file
# bails fast if scene is already changing.
func _go_back_to_menu() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

func _on_gate_triggered(gate_center_x: float, gate: Node) -> void:
	# Iter 42a: snapshot posse_count BEFORE the gate fires so we can
	# detect SWEET! (gate passed at full STARTING_POSSE) cleanly. The
	# apply_effect below changes posse_count immediately, so a post-
	# check would see the new value, not the pre-gate state.
	var posse_was_full: bool = (posse_count >= STARTING_POSSE)
	# Combo escalates per consecutive gate. Particle amount and screen
	# trauma both scale via CombosCounter's curves; over combo 3 we get
	# the "MEGA!" floating banner (Candy-Crush-style escalation).
	#
	# Explicit `: int` annotation on the step() call result is REQUIRED:
	# `combos` is typed as base RefCounted (since CombosCounter has no
	# class_name), so the parser can't infer `combos.step()`'s return
	# type. Without this annotation, the whole script fails to load at
	# runtime — manifesting as level.gd not attached, _ready/_process/
	# _input "nonexistent." Found via test_level_integration.gd in iter 14.
	var combo: int = combos.step()
	DebugLog.add("gate triggered combo=%d cowboy_x=%.0f" % [combo, cowboy.position.x])

	# Boost gate's particle amount BEFORE its _play_pass_animation runs.
	# Signal emission is synchronous, so this lands before emitting=true.
	var mult: float = CombosCounterScript.particle_multiplier(combo)
	if gate.has_node("Sparkles"):
		var sparkles := gate.get_node("Sparkles") as CPUParticles2D
		sparkles.amount = int(28.0 * mult)

	var side := GateHelper.which_side(cowboy.position.x, gate_center_x)
	posse_count = GateHelper.apply_effect(posse_count, side, gate.left_value, gate.right_value, gate.gate_type)
	AudioBus.play_gate_pass()
	shake.add_trauma(CombosCounterScript.trauma_for(combo))
	_pulse_posse_label()

	var combo_label := CombosCounterScript.label_for(combo)
	if combo_label != "":
		FlourishBanner.spawn($UI, combo_label, self)
	# Iter 41: extra YEEHAW! flourish on multiplier gates regardless of
	# combo state — × gates are the high-value swings and deserve their
	# own ego cookie. Fires AFTER the DOUBLE/MEGA banner if both apply
	# (banners stack visually, which reads as "double cookie" not bug).
	if gate.gate_type == GateHelper.TYPE_MULTIPLICATIVE:
		FlourishBanner.spawn($UI, "YEEHAW!", self)

	# Iter 42a: SWEET! ("ADEQUATE.") when a gate is cleared with a full
	# starting posse. The narrator weighing in on "you didn't lose anyone
	# yet, fine." Only fires while posse_count was still maxed BEFORE the
	# gate applied — once you've taken a hit, this stays silent.
	if posse_was_full and posse_count >= STARTING_POSSE:
		FlourishBanner.spawn($UI, "SWEET!", self)

	progress.record_pass()
	if progress.is_complete():
		_gates_complete = true
		DebugLog.add("gates done — waiting for boss to fall")
		# Iter 42a: FLAWLESS! ("RELUCTANTLY COMPETENT.") when ALL gates
		# clear with the starting posse intact. Murderbot is grudgingly
		# acknowledging "no casualties at the math part." Bigger banner,
		# longer text — the rarest flourish in the game.
		if posse_count >= STARTING_POSSE:
			FlourishBanner.spawn($UI, "FLAWLESS!", self)
		_maybe_show_win()

# Iter 37: boss-defeated handler. When the SlipperyPete (or any
# 'bosses' group member) fires its destroyed signal, mark the boss
# down and check win conditions. Players who shoot the boss before
# the last gate fires still need to pass the last gate to win.
func _on_boss_destroyed(_x: float) -> void:
	_boss_defeated = true
	DebugLog.add("boss defeated — checking win conditions")
	_maybe_show_win()

# Iter 40c: boss reached STAY mode (cowboy caught up to boss). Stop the
# terrain scroll so the world stops moving — the showdown is an event,
# not a continued chase. This is fired ONCE per boss via the `engaged`
# signal (slippery_pete.gd:_engaged latch).
func _on_boss_engaged() -> void:
	DebugLog.add("boss engaged — stopping terrain scroll")
	var terrain := get_node_or_null("Terrain3D")
	if terrain and terrain.has_method("set_scroll_active"):
		terrain.set_scroll_active(false)

# Two conditions to trigger _show_win: gates done AND boss dead. Until
# both, the firefight continues — player keeps firing, boss keeps
# crowding, vagrants/prospectors keep coming. Iter 40c: short-circuit
# if the level has already failed (posse wiped) — fail modal owns the
# end-of-level frame, can't double-pop a WIN over it.
func _maybe_show_win() -> void:
	if _failed:
		return
	if _gates_complete and _boss_defeated:
		_show_win()

# Iter 40c: posse-wipe handler. Triggered from the posse_count setter
# when count transitions to 0. Mirrors _show_win flow:
#   1) Stop bullet fire (no posthumous shooting)
#   2) Switch any remaining renderers to idle (they're already gone, but
#      defensive — the leader sprite needs to disappear too)
#   3) Deduct a heart via GameState — affects the main_menu PLAY gate
#   4) Pop the FailOverlay with a back-in scale tween
func _show_fail() -> void:
	DebugLog.add("FAIL: posse wiped out — last dude went down")
	_shooting_active = false
	# Hide the leader cowboy sprite — they're dead too. (Followers are
	# already gone via PosseRenderer's despawn flow.)
	if cowboy:
		cowboy.visible = false
	# Heart cost. GameState is autoloaded; .spend_heart() returns false
	# if hearts were already 0 (e.g. cheat path), but we don't have a
	# special branch for that here — failing again at 0 just shows the
	# same modal. Guard with get_node_or_null because GUT tests may
	# instantiate level.gd without the full autoload chain.
	if get_node_or_null("/root/GameState"):
		GameState.spend_heart()
	# Brief beat so the death frame registers before the modal slides in.
	await get_tree().create_timer(0.4).timeout
	# Guard the overlay refs too — tests sometimes load a partial scene
	# without the FailOverlay subtree. In real gameplay these are wired
	# by the @onready vars.
	if fail_overlay == null or fail_panel == null:
		return
	fail_overlay.visible = true
	fail_panel.scale = Vector2(0.55, 0.55)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(fail_panel, "scale", Vector2.ONE, 0.32) \
		.set_trans(Tween.TRANS_BACK) \
		.set_ease(Tween.EASE_OUT)

func _on_fail_retry_pressed() -> void:
	AudioBus.play_tap()
	fail_retry_button.disabled = true
	fail_menu_button.disabled = true
	var t := create_tween()
	t.tween_property(fail_retry_button, "scale", Vector2(0.92, 0.92), 0.06)
	t.tween_property(fail_retry_button, "scale", Vector2.ONE, 0.16) \
		.set_trans(Tween.TRANS_BACK) \
		.set_ease(Tween.EASE_OUT)
	await t.finished
	get_tree().reload_current_scene()

func _on_fail_menu_pressed() -> void:
	AudioBus.play_tap()
	fail_retry_button.disabled = true
	fail_menu_button.disabled = true
	var t := create_tween()
	t.tween_property(fail_menu_button, "scale", Vector2(0.92, 0.92), 0.06)
	t.tween_property(fail_menu_button, "scale", Vector2.ONE, 0.16) \
		.set_trans(Tween.TRANS_BACK) \
		.set_ease(Tween.EASE_OUT)
	await t.finished
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

# A gate transitioned from red (shrinking) to blue (growing) mid-game.
# All bulls currently on-screen are confused by the visual change —
# they slow, drift sideways, and eventually walk off the track at a
# 60° angle. See bull.gd for the state machine.
func _on_gate_direction_flipped(_gate) -> void:
	var bulls := get_tree().get_nodes_in_group("bulls")
	DebugLog.add("gate flipped red→blue → confusing %d bull(s)" % bulls.size())
	for bull in bulls:
		bull.confuse()

# Floating combo banner ("DOUBLE!" / "MEGA!") added to the UI canvas
# layer so screen shake doesn't jitter it. Scales in with a bounce,
# floats upward, fades out, queue_frees.
func _spawn_combo_banner(text: String) -> void:
	var ui := $UI as CanvasLayer
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE  # don't block touch input
	label.theme = preload("res://assets/theme.tres")
	label.add_theme_font_size_override("font_size", 156)
	label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.5, 1))
	label.add_theme_color_override("font_outline_color", Color(0.18, 0.1, 0.03, 1))
	label.add_theme_constant_override("outline_size", 14)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.size_flags_horizontal = Control.SIZE_FILL
	label.anchor_left = 0.0
	label.anchor_right = 1.0
	label.anchor_top = 0.5
	label.anchor_bottom = 0.5
	label.offset_left = 0.0
	label.offset_right = 0.0
	label.offset_top = -90.0
	label.offset_bottom = 90.0
	ui.add_child(label)
	label.pivot_offset = Vector2(540.0, 90.0)
	label.scale = Vector2(0.4, 0.4)
	label.modulate.a = 0.0

	var pop := create_tween().set_parallel(true)
	pop.tween_property(label, "scale", Vector2.ONE, 0.22) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	pop.tween_property(label, "modulate:a", 1.0, 0.12)
	pop.tween_property(label, "offset_top", -290.0, 0.9) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	pop.tween_property(label, "offset_bottom", -110.0, 0.9) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await get_tree().create_timer(0.55).timeout
	var fade := create_tween()
	fade.tween_property(label, "modulate:a", 0.0, 0.35)
	await fade.finished
	label.queue_free()

func _refresh_posse_label() -> void:
	if posse_label:
		posse_label.text = "POSSE: %d" % posse_count

# Updates the on-screen ammo readout. ▰/▱ pips show ready/spent rounds;
# during reload, the bar fills back up in reload_progress order and
# colors shift to a warm orange so the player notices the pause.
func _refresh_ammo_label() -> void:
	if not ammo_label or _gun_state == null:
		return
	var clip: int = _gun.clip_size
	if _gun_state.is_reloading():
		var filled: int = int(round(float(clip) * _gun_state.reload_progress()))
		filled = clampi(filled, 0, clip)
		ammo_label.text = "RELOADING " + "▰".repeat(filled) + "▱".repeat(clip - filled)
		ammo_label.modulate = Color(1.0, 0.55, 0.25, 1)
	else:
		var ammo: int = _gun_state.ammo()
		ammo_label.text = "AMMO " + "▰".repeat(ammo) + "▱".repeat(clip - ammo)
		ammo_label.modulate = Color(1.0, 0.92, 0.55, 1)

func _pulse_posse_label() -> void:
	if not posse_label:
		return
	posse_label.pivot_offset = posse_label.size / 2.0
	var tween := create_tween()
	tween.tween_property(posse_label, "scale", Vector2(1.25, 1.25), 0.12) \
		.set_trans(Tween.TRANS_BACK) \
		.set_ease(Tween.EASE_OUT)
	tween.tween_property(posse_label, "scale", Vector2.ONE, 0.18) \
		.set_trans(Tween.TRANS_SINE) \
		.set_ease(Tween.EASE_IN_OUT)

# ---------- Win flow ----------

func _show_win() -> void:
	# Iter 25 fix for "bounty appears before level is completed":
	# Keep firing for POST_GATE_RUNWAY_S after the last gate so the
	# level decompresses naturally — bull rolls past, last barrels
	# clear, bullets fly into the distance. Only THEN stop shooting +
	# pop the overlay. The 4s window covers a bull at 320 px/sec
	# travelling 1280 px, plenty to scroll off the top.
	const POST_GATE_RUNWAY_S: float = 4.0
	DebugLog.add("WIN: gates done, runway %.1fs before bounty" % POST_GATE_RUNWAY_S)
	await get_tree().create_timer(POST_GATE_RUNWAY_S).timeout
	_shooting_active = false
	DebugLog.add("WIN: bullets stopped, %d posse remaining" % posse_count)
	# Switch every dude (leader + followers) from run_shoot → idle so
	# the crowd visibly stops running once the level is over. Was a
	# polish bug — dudes kept sprinting under the bounty banner.
	_switch_posse_to_idle()
	win_subtitle.text = "%d posse members made it.
whatever that's worth." % posse_count
	# Short additional beat after stopping fire so the gunfire silence
	# registers before the overlay covers everything.
	await get_tree().create_timer(0.55).timeout
	# Iter 43b: Gold Rush ceremony. Dispatches by level difficulty —
	# only level 1 (Easy/Peppermint) is currently wired, plays the
	# Six-Shooter Salute (A). Medium/Hard/Extreme implementations
	# deferred to future iters; they no-op to the existing flow.
	await _play_gold_rush()
	win_overlay.visible = true
	win_panel.scale = Vector2(0.55, 0.55)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(win_panel, "scale", Vector2.ONE, 0.32) \
		.set_trans(Tween.TRANS_BACK) \
		.set_ease(Tween.EASE_OUT)

# Iter 44: Gold Rush dispatch by (difficulty, terrain). The two axes are
# independent — see project_level_themes_and_gold_rush memory. Difficulty
# determines intensity (bounty per beat, chain length); terrain determines
# which mechanic plays. Stubs fall through to A for now.
#
# Difficulty levels: 1=Easy(Peppermint), 2=Medium(Fireball),
#                    3=Hard(Jellybean), 4=Extreme(Liquorice)
# Terrains: "frontier", "mine", "farm", "mountain"
#
# Currently @export so the level scene can override; future per-level
# .tres resources will feed these from level_select.
@export var level_difficulty: int = 1
@export var level_terrain: String = "frontier"

# Iter 54: optional per-level definition resource. If assigned, overrides
# the @export defaults above. Loaded in _ready from GameState.current_level
# → "res://resources/levels/level_{n}.tres". Allows the same level.tscn
# to drive every level with only the resource swapping.
@export var level_def: LevelDef

# Dispatch table per the memory's matrix. Returns the rush ID to play.
# "A"/"B"/"D"/"E"/"F"/"G"/"H" map to _gold_rush_* methods below.
# Iter 46: when true, this scene is running as a TEST RANGE — posse
# is invulnerable (no fail trigger), normal gates/enemies are stripped,
# and a stationary 6×6 cactus grid is spawned for weapon/posse testing.
# Set via debug menu's OPEN TEST RANGE button.
var _test_range_mode: bool = false

# Iter 45: debug-menu override. If non-empty, _gold_rush_for() returns
# this directly, bypassing the difficulty/terrain matrix. Set by
# DebugPreview when launching from the debug menu's "Preview Rush X"
# buttons. Cleared after first use.
var _debug_override_rush: String = ""

# Iter 54: load level definition based on GameState.current_level. The
# resource file maps level # → {difficulty, terrain, display_name, seed}.
# Falls back gracefully when the resource doesn't exist yet (e.g., a
# level number with no .tres committed).
func _load_level_def() -> void:
	if get_node_or_null("/root/GameState") == null:
		return
	var n: int = GameState.current_level
	var path := "res://resources/levels/level_%d.tres" % n
	if not ResourceLoader.exists(path):
		DebugLog.add("level %d: no resource at %s — using @export defaults" % [n, path])
		return
	var def: Resource = ResourceLoader.load(path)
	if def == null:
		return
	# Copy resource fields onto the scene's runtime properties so
	# everything downstream (_gold_rush_for, banners, etc.) reads from
	# the same flat fields.
	if "difficulty" in def:
		level_difficulty = def.difficulty
	if "terrain" in def:
		level_terrain = def.terrain
	DebugLog.add("level %d: loaded def difficulty=%d terrain=%s" % [
		n, level_difficulty, level_terrain,
	])

func _gold_rush_for(difficulty: int, terrain: String) -> String:
	# Iter 45: debug-menu override wins over the matrix.
	if _debug_override_rush != "":
		return _debug_override_rush
	# Extreme (4) — chain-reaction-heavy rushes
	if difficulty == 4:
		match terrain:
			"frontier": return "E"   # Candy Cart Chain Reaction
			"mine":     return "F"   # Liquorice Locomotive
			"farm":     return "B"   # Jelly Jar Cascade (no Extreme farm rush — borrows Hard's)
			"mountain": return "G"   # Avalanche Bonanza
	# Hard (3) — moderate complexity
	if difficulty == 3:
		match terrain:
			"frontier": return "E"
			"mine":     return "B"
			"farm":     return "B"
			"mountain": return "H"
	# Medium (2) — slight skill demand
	if difficulty == 2:
		match terrain:
			"mine":     return "D"
			"farm":     return "D"
			"mountain": return "G"   # lite version
			_:          return "A"
	# Easy (1) and any fallback → A (Six-Shooter Salute, Frontier default)
	if terrain == "farm":
		return "D"
	if terrain == "mountain":
		return "G"
	return "A"

# Top-level dispatcher. Awaitable so the caller (_show_win) can chain
# `await _play_gold_rush()` before showing the win modal.
func _play_gold_rush() -> void:
	var rush_id: String = _gold_rush_for(level_difficulty, level_terrain)
	DebugLog.add("gold rush: %s (diff=%d terrain=%s)" % [rush_id, level_difficulty, level_terrain])
	match rush_id:
		"A":
			await _gold_rush_six_shooter_salute()
		"B":
			await _gold_rush_jelly_jar_cascade()
		"D":
			await _gold_rush_tumbleweed_roll()
		"E":
			await _gold_rush_candy_cart_chain()
		"F":
			await _gold_rush_liquorice_locomotive()
		"G":
			await _gold_rush_avalanche_bonanza()
		"H":
			await _gold_rush_gumball_runaway()
		_:
			# Unknown rush id — fall through to the safe A path.
			await _gold_rush_six_shooter_salute()

# ── B/D/E/F/G/H stubs ─────────────────────────────────────────────────
# Iter 44: stub functions for the 6 not-yet-built rushes. Each pops a
# preview banner naming the rush + plays the A salute mechanically so
# the player gets SOMETHING on a non-Frontier-Easy level. Real mechanics
# land in iters 45+. The dispatch architecture is in place; only the
# innards need filling in per rush.
# Iter 45: deferred-call wrapper that activates Jelly Bean Frenzy after
# a short delay so the player can see the level briefly before the burst
# kicks in. Used by debug-menu preview only.
func _deferred_debug_sugar_rush() -> void:
	await get_tree().create_timer(1.0).timeout
	_equip_bonus("jelly_frenzy")

# Iter 46: TEST RANGE setup. Strips the level scene of its gates/enemies/
# obstacles and replaces them with a stationary 6×6 cactus grid for
# weapon-feel + posse-formation testing. Mounts a sidebar of debug
# buttons on the UI CanvasLayer (EQUIP RIFLE / EQUIP DEFAULT / +1 DUDE /
# -1 DUDE / RESET CACTI). Halts world scroll so cacti stay put — there's
# no boss to confront, no gate to clear, no win condition.
const _TEST_RANGE_GROUPS: Array[String] = [
	"barrels", "bulls", "outlaws", "prospectors", "tumbleweeds", "cacti",
	"bosses", "bonuses",
]
const _TEST_RANGE_GRID_ROWS: int = 6
const _TEST_RANGE_GRID_COLS: int = 6
const _TEST_RANGE_GRID_START_X: float = 180.0
const _TEST_RANGE_GRID_STEP_X: float = 145.0
const _TEST_RANGE_GRID_START_Y: float = 350.0
const _TEST_RANGE_GRID_STEP_Y: float = 180.0
const _TEST_RANGE_CACTUS_SCENE := preload("res://scenes/cactus.tscn")

func _setup_test_range() -> void:
	# 1) Strip existing obstacles/enemies. Each group's members get
	#    queue_free'd; surviving in-flight bullets are also cleared.
	for group_name in _TEST_RANGE_GROUPS:
		for node in get_tree().get_nodes_in_group(group_name):
			node.queue_free()
	for bullet in get_tree().get_nodes_in_group("bullets"):
		bullet.queue_free()
	# 2) Stop world scroll so the new cacti stay where we placed them.
	WorldSpeed.set_mult(0.0)
	# Hide the LevelLabel + WinOverlay + FailOverlay clutter.
	if win_overlay:
		win_overlay.visible = false
	if fail_overlay:
		fail_overlay.visible = false
	# 3) Spawn the 6×6 cactus grid. Each cactus's per-process scroll is
	#    multiplied by WorldSpeed.mult, which we just set to 0 — they
	#    stay put forever. Stagger Y slightly per column for visual
	#    interest (so the grid doesn't read as a perfectly square block).
	var rng := RandomNumberGenerator.new()
	rng.seed = 4646  # deterministic placement for repeatable tests
	for row in range(_TEST_RANGE_GRID_ROWS):
		for col in range(_TEST_RANGE_GRID_COLS):
			var c: Node2D = _TEST_RANGE_CACTUS_SCENE.instantiate()
			var x: float = _TEST_RANGE_GRID_START_X + float(col) * _TEST_RANGE_GRID_STEP_X
			x += rng.randf_range(-15.0, 15.0)
			var y: float = _TEST_RANGE_GRID_START_Y + float(row) * _TEST_RANGE_GRID_STEP_Y
			y += rng.randf_range(-12.0, 12.0)
			c.position = Vector2(x, y)
			add_child(c)
	# 4) Mount the debug sidebar — EQUIP/POSSE buttons. Vertical column
	#    on the right edge of the UI CanvasLayer.
	_mount_test_range_sidebar()
	DebugLog.add("test range: %d cacti spawned" % (_TEST_RANGE_GRID_ROWS * _TEST_RANGE_GRID_COLS))

# Iter 46: builds a vertical column of debug buttons on the UI. Each
# button drives a one-shot action via _on_test_*. Buttons appear on
# the right edge so they don't overlap with the LEVEL label / posse
# count / ammo bar on the left.
func _mount_test_range_sidebar() -> void:
	var ui_layer: CanvasLayer = $UI
	var panel := VBoxContainer.new()
	panel.position = Vector2(840, 460)
	panel.custom_minimum_size = Vector2(220, 0)
	panel.add_theme_constant_override("separation", 14)
	ui_layer.add_child(panel)

	var actions: Array = [
		["EQUIP RIFLE",         "_on_test_equip_rifle"],
		["EQUIP DEFAULT",       "_on_test_equip_default"],
		["LIQUORICE WHIP",      "_on_test_equip_liquorice_whip"],
		["JAWBREAKERS",         "_on_test_equip_jawbreaker"],
		["COTTON CANDY RIFLE",  "_on_test_equip_cotton_candy_rifle"],
		["GUMDROP GATLING",     "_on_test_equip_gatling"],
		["MARSHMALLOW SHERIFF", "_on_test_equip_marshmallow_sheriff"],
		["LAUGHING HORSE",      "_on_test_equip_laughing_horse"],
		["SCARECROW",           "_on_test_equip_scarecrow"],
		["JELLY FRENZY",        "_on_test_jelly_frenzy"],
		["+1 DUDE",             "_on_test_add_dude"],
		["−1 DUDE",             "_on_test_remove_dude"],
		["RESET CACTI",         "_on_test_reset_cacti"],
		["EXIT RANGE",          "_on_test_exit"],
	]
	for entry in actions:
		var btn := Button.new()
		btn.text = entry[0]
		btn.custom_minimum_size = Vector2(220, 70)
		btn.add_theme_font_size_override("font_size", 26)
		btn.pressed.connect(Callable(self, entry[1]))
		panel.add_child(btn)

func _on_test_equip_rifle() -> void:
	_equip_bonus("rifle")
	DebugLog.add("test range: equipped rifle")

func _on_test_equip_default() -> void:
	_gun = GunScript.new()
	_gun_state = GunStateScript.new(_gun)
	DebugLog.add("test range: equipped default Jelly Bean Six-Shooter")

func _on_test_jelly_frenzy() -> void:
	_equip_bonus("jelly_frenzy")

func _on_test_add_dude() -> void:
	posse_count = mini(posse_count + 1, 20)
	DebugLog.add("test range: posse=%d" % posse_count)

func _on_test_remove_dude() -> void:
	# Iter 46: test range keeps posse alive even at 0 (no fail trigger);
	# still clamp to 1 here so the leader stays renderable.
	posse_count = maxi(posse_count - 1, 1)
	DebugLog.add("test range: posse=%d" % posse_count)

# Iter 57: bullet consumption helper. Centralizes the "what happens
# when a bullet's existing collision passes detect a hit" logic so
# AOE + pierce behaviors compose with existing per-enemy hit handlers.
# Returns true if the bullet was consumed (caller should `break`);
# false if the bullet survives (pierce_remaining > 0, caller continues).
#
# Order of operations:
#   1. AOE splash: damage all enemies within bullet.aoe_radius of hit_pos
#   2. AOE flash visual
#   3. Pierce check: if remaining > 0, decrement and survive
#   4. Otherwise: remove from group + queue_free
const _AOE_GROUPS: Array[String] = [
	"barrels", "bulls", "outlaws", "prospectors", "tumbleweeds", "cacti",
]

func _consume_bullet(bullet: Node, hit_pos: Vector2) -> bool:
	if not is_instance_valid(bullet):
		return true
	# AOE splash + flash, but only ON the consuming hit (so pierce-shots
	# don't repeatedly splash at every passthrough).
	var pierce: int = bullet.pierce_remaining if "pierce_remaining" in bullet else 0
	var aoe_r: float = bullet.aoe_radius if "aoe_radius" in bullet else 0.0
	var bdmg: int = bullet.damage if "damage" in bullet else 1
	var freeze_s: float = bullet.freeze_duration_s if "freeze_duration_s" in bullet else 0.0
	var slow_s: float = bullet.slow_duration_s if "slow_duration_s" in bullet else 0.0
	# Iter 58: apply freeze/slow debuffs to the hit-position-nearby enemies
	# (single radius for both effects; same as AOE radius if present, else 80px).
	if freeze_s > 0.0 or slow_s > 0.0:
		var debuff_r: float = aoe_r if aoe_r > 0.0 else 80.0
		_apply_debuff_to_nearby(hit_pos, debuff_r, freeze_s, slow_s)
	if pierce > 0:
		bullet.pierce_remaining = pierce - 1
		return false  # survives
	if aoe_r > 0.0:
		_aoe_splash(hit_pos, aoe_r, bdmg)
		_spawn_aoe_flash(hit_pos, aoe_r)
	bullet.remove_from_group("bullets")
	bullet.queue_free()
	return true

# Iter 58: apply freeze/slow debuffs to nearby enemies. Each enemy needs
# to support a `freeze_until_ms` / `slow_until_ms` meta field — read by
# its _process to halve/zero its scroll velocity. Set via Object.set_meta
# so no schema changes to barrel/bull/etc.gd required.
func _apply_debuff_to_nearby(center: Vector2, radius: float, freeze_s: float, slow_s: float) -> void:
	var r2: float = radius * radius
	var now_ms: int = int(Time.get_ticks_msec())
	var freeze_until: int = now_ms + int(freeze_s * 1000.0)
	var slow_until: int = now_ms + int(slow_s * 1000.0)
	for group_name in _AOE_GROUPS:
		for enemy in get_tree().get_nodes_in_group(group_name):
			if not is_instance_valid(enemy):
				continue
			if enemy.position.distance_squared_to(center) > r2:
				continue
			if freeze_s > 0.0:
				enemy.set_meta("freeze_until_ms", freeze_until)
				# Visual tint: cyan flash + slowly fade back
				if "modulate" in enemy:
					enemy.modulate = Color(0.55, 0.85, 1.20, 1.0)
					var t := create_tween()
					t.tween_property(enemy, "modulate", Color(1, 1, 1, 1), freeze_s) \
						.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			if slow_s > 0.0:
				enemy.set_meta("slow_until_ms", slow_until)
				if "modulate" in enemy:
					enemy.modulate = Color(0.85, 0.95, 1.10, 1.0)
					var t := create_tween()
					t.tween_property(enemy, "modulate", Color(1, 1, 1, 1), slow_s) \
						.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

# Splash AOE damage to every enemy within radius of center. Skips the
# enemy that triggered the consume (caller already damaged it directly).
func _aoe_splash(center: Vector2, radius: float, damage: int) -> void:
	var r2: float = radius * radius
	for group_name in _AOE_GROUPS:
		for enemy in get_tree().get_nodes_in_group(group_name):
			if not is_instance_valid(enemy):
				continue
			if enemy.position.distance_squared_to(center) > r2:
				continue
			if enemy.has_method("take_bullet_hit"):
				enemy.take_bullet_hit(damage)
			elif enemy.has_method("take_damage"):
				enemy.take_damage(damage)

# Visual flash for AOE splashes — short-lived expanding ring polygon.
func _spawn_aoe_flash(center: Vector2, radius: float) -> void:
	var flash := Polygon2D.new()
	flash.color = Color(1.0, 0.78, 0.30, 0.55)
	var pts: PackedVector2Array = PackedVector2Array()
	for i in range(24):
		var a: float = float(i) / 24.0 * TAU
		pts.append(Vector2(cos(a), sin(a)) * radius)
	flash.polygon = pts
	flash.position = center
	flash.z_index = 50
	add_child(flash)
	var t: Tween = create_tween().set_parallel(true)
	t.tween_property(flash, "scale", Vector2(1.35, 1.35), 0.32) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(flash, "modulate:a", 0.0, 0.32) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.chain().tween_callback(flash.queue_free)

# Iter 56: test-range weapon equip helpers. Each calls _equip_bonus
# with the matching slug so the weapon factory dispatches normally.
func _on_test_equip_liquorice_whip() -> void:
	_equip_bonus("liquorice_whip")

func _on_test_equip_jawbreaker() -> void:
	_equip_bonus("jawbreaker_grenades")

func _on_test_equip_cotton_candy_rifle() -> void:
	_equip_bonus("cotton_candy_rifle")

func _on_test_equip_gatling() -> void:
	_equip_bonus("gumdrop_gatling")

# Iter 59-60: hero spawn helpers + visual marker. The hero marker is a
# simple Polygon2D group floating above the leader cowboy as a "this is
# special" tag. Stays visible for the rest of the level. Body color +
# accent color picked per hero.
func _spawn_hero_marker(hero_name: String, body_color: Color, accent_color: Color) -> void:
	if cowboy == null:
		return
	var marker := Node2D.new()
	marker.position = Vector2(0, -260)  # above cowboy's head
	cowboy.add_child(marker)
	# Hero body: chunky rounded blob (Polygon2D circle approximation)
	var body := Polygon2D.new()
	body.color = body_color
	var pts := PackedVector2Array()
	for i in range(16):
		var a: float = float(i) / 16.0 * TAU
		pts.append(Vector2(cos(a), sin(a)) * 36.0)
	body.polygon = pts
	marker.add_child(body)
	# Accent ring (sheriff badge / mane stripe)
	var accent := Polygon2D.new()
	accent.color = accent_color
	var accent_pts := PackedVector2Array()
	for i in range(16):
		var a: float = float(i) / 16.0 * TAU
		accent_pts.append(Vector2(cos(a), sin(a)) * 28.0)
		accent_pts.append(Vector2(cos(a), sin(a)) * 32.0)
	accent.polygon = accent_pts
	marker.add_child(accent)
	# Hero name label below the body
	var label := Label.new()
	label.text = hero_name
	label.position = Vector2(-100, 40)
	label.custom_minimum_size = Vector2(200, 40)
	label.add_theme_color_override("font_color", accent_color)
	label.add_theme_color_override("font_outline_color", Color(0.08, 0.05, 0.05, 1))
	label.add_theme_constant_override("outline_size", 6)
	label.add_theme_font_size_override("font_size", 24)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	marker.add_child(label)
	# Pop-in tween
	marker.scale = Vector2(0.2, 0.2)
	var t := create_tween().set_parallel(true)
	t.tween_property(marker, "scale", Vector2.ONE, 0.4) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _on_test_equip_marshmallow_sheriff() -> void:
	_equip_bonus("marshmallow_sheriff")

func _on_test_equip_laughing_horse() -> void:
	_equip_bonus("laughing_horse")

func _on_test_equip_scarecrow() -> void:
	_equip_bonus("scarecrow")

# Iter 60: rainbow-mane accent for the Laughing Horse hero. Spawns 6 small
# rainbow stripes that fan out behind the leader cowboy + slowly cycle hue
# via a continuous tween. Hero marker (the orb above head) is shared with
# Sheriff; this is the horse-specific add-on visual.
func _spawn_rainbow_mane() -> void:
	if cowboy == null:
		return
	var mane := Node2D.new()
	mane.position = Vector2(0, -80)
	cowboy.add_child(mane)
	for i in range(6):
		var stripe := Polygon2D.new()
		stripe.color = Color.from_hsv(float(i) / 6.0, 0.85, 1.0, 0.85)
		var angle: float = lerpf(-PI * 0.45, PI * 0.45, float(i) / 5.0)
		stripe.rotation = angle + PI * 0.5  # fan upward
		stripe.polygon = PackedVector2Array([
			Vector2(-6, 0), Vector2(6, 0),
			Vector2(8, -50), Vector2(-8, -50),
		])
		mane.add_child(stripe)
	# Subtle bobbing tween — gives the mane life.
	var bob := create_tween().set_loops()
	bob.tween_property(mane, "position:y", -86.0, 0.9) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	bob.tween_property(mane, "position:y", -74.0, 0.9) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func _on_test_reset_cacti() -> void:
	# Tear down current cacti + spawn a fresh grid (use case: stress-test
	# AOE / pierce after destroying the first wave).
	for c in get_tree().get_nodes_in_group("cacti"):
		c.queue_free()
	# Wait one frame for queue_free to settle, then re-spawn.
	await get_tree().process_frame
	var rng := RandomNumberGenerator.new()
	rng.seed = Time.get_ticks_msec()  # vary placement across resets
	for row in range(_TEST_RANGE_GRID_ROWS):
		for col in range(_TEST_RANGE_GRID_COLS):
			var c: Node2D = _TEST_RANGE_CACTUS_SCENE.instantiate()
			var x: float = _TEST_RANGE_GRID_START_X + float(col) * _TEST_RANGE_GRID_STEP_X
			x += rng.randf_range(-15.0, 15.0)
			var y: float = _TEST_RANGE_GRID_START_Y + float(row) * _TEST_RANGE_GRID_STEP_Y
			y += rng.randf_range(-12.0, 12.0)
			c.position = Vector2(x, y)
			add_child(c)
	DebugLog.add("test range: cacti reset")

func _on_test_exit() -> void:
	AudioBus.play_tap()
	get_tree().change_scene_to_file("res://scenes/debug_menu.tscn")

func _gold_rush_jelly_jar_cascade() -> void:
	# Iter 48: Color-Bomb-style cascade. N glass jars (one per remaining
	# posse member) tumble from the top, shatter on contact with the
	# ground, and spawn 8 bouncing jelly beans each. Player passively
	# collects beans by walking the cowboy over them. After ~3.5s of
	# bouncing, the SUGAR CASCADE banner fires and any uncollected beans
	# fly to the cowboy as a chain-reaction sweep (auto-collect bonus).
	_shooting_active = false
	const JAR_COUNT_MAX: int = 5
	const BEANS_PER_JAR: int = 8
	const PER_BEAN_BONUS: int = 25
	const CASCADE_BONUS: int = 800
	const GROUND_Y: float = 1500.0
	const COWBOY_COLLECT_RADIUS_SQ: float = 110.0 * 110.0
	var jar_count: int = mini(maxi(posse_count, 1), JAR_COUNT_MAX)
	# 1) Spawn N jars tumbling from above the screen at varied x positions.
	#    Each jar is a tall amber rectangle + lid; falls under gravity.
	var jars: Array[Node2D] = []
	for i in range(jar_count):
		var jar := Node2D.new()
		var spawn_x: float = lerpf(180.0, 900.0, float(i) / float(maxi(jar_count - 1, 1)))
		jar.position = Vector2(spawn_x, -200.0 - float(i) * 90.0)
		add_child(jar)
		var body := Polygon2D.new()
		body.color = Color(0.92, 0.78, 0.30, 0.85)  # amber glass
		body.polygon = PackedVector2Array([
			Vector2(-40, -60), Vector2(40, -60),
			Vector2(50, 60), Vector2(-50, 60),
		])
		jar.add_child(body)
		var lid := Polygon2D.new()
		lid.color = Color(0.55, 0.35, 0.18, 1.0)
		lid.polygon = PackedVector2Array([
			Vector2(-44, -75), Vector2(44, -75),
			Vector2(44, -55), Vector2(-44, -55),
		])
		jar.add_child(lid)
		jars.append(jar)
	# 2) Tween each jar falling to GROUND_Y, stagger spawn arrivals so they
	#    don't all shatter on the same frame.
	for i in range(jars.size()):
		var j := jars[i]
		var t := create_tween()
		t.tween_interval(float(i) * 0.18)
		t.tween_property(j, "position:y", GROUND_Y, 0.95) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await get_tree().create_timer(0.95 + float(jar_count) * 0.18).timeout
	# 3) Shatter each jar: free the body Polygon2Ds, spawn BEANS_PER_JAR
	#    jelly beans with random velocity vectors. Track each bean.
	var beans: Array[Dictionary] = []
	for j in jars:
		if not is_instance_valid(j):
			continue
		var burst_pos: Vector2 = j.position
		AudioBus.play_gunfire()  # placeholder shatter SFX
		if shake and shake.has_method("add_trauma"):
			shake.add_trauma(0.35)
		for k in range(BEANS_PER_JAR):
			var bean := Polygon2D.new()
			bean.color = Color.from_hsv(randf(), 0.85, 1.0, 1.0)
			var pts: PackedVector2Array = PackedVector2Array()
			for v in range(8):
				var a: float = float(v) / 8.0 * TAU
				pts.append(Vector2(cos(a), sin(a)) * 12.0)
			bean.polygon = pts
			bean.position = burst_pos
			add_child(bean)
			var angle: float = randf() * TAU
			var speed: float = randf_range(180.0, 380.0)
			beans.append({
				"node": bean,
				"vel": Vector2(cos(angle), sin(angle)) * speed,
				"collected": false,
			})
		j.queue_free()
	# 4) Bouncing-bean loop: gravity + ground bounce + cowboy proximity.
	const BEAN_GRAVITY: float = 600.0
	const BEAN_FRICTION: float = 0.78
	var bounce_time: float = 3.2
	while bounce_time > 0.0 and is_inside_tree():
		var dt: float = get_process_delta_time()
		bounce_time -= dt
		for b in beans:
			if b.collected:
				continue
			var bn: Polygon2D = b.node
			if not is_instance_valid(bn):
				b.collected = true
				continue
			# Update velocity (gravity) + position
			b.vel.y += BEAN_GRAVITY * dt
			bn.position += b.vel * dt
			# Ground bounce
			if bn.position.y >= GROUND_Y and b.vel.y > 0:
				bn.position.y = GROUND_Y
				b.vel.y *= -BEAN_FRICTION
				b.vel.x *= 0.9
			# Cowboy collect (walk over to grab)
			if cowboy and bn.position.distance_squared_to(cowboy.position) < COWBOY_COLLECT_RADIUS_SQ:
				b.collected = true
				if get_node_or_null("/root/GameState"):
					GameState.bounty += PER_BEAN_BONUS
				DamagePopup.spawn_bounty(self, bn.position, PER_BEAN_BONUS)
				# Quick pop-fade then free
				var t := create_tween().set_parallel(true)
				t.tween_property(bn, "scale", Vector2(1.6, 1.6), 0.18)
				t.tween_property(bn, "modulate:a", 0.0, 0.18)
				t.chain().tween_callback(bn.queue_free)
		await get_tree().process_frame
	# 5) Chain reaction: any uncollected beans sweep toward the cowboy and
	#    auto-collect at +PER_BEAN_BONUS. SUGAR_CASCADE banner + bonus.
	FlourishBanner.spawn($UI, "SUGAR_CASCADE", self)
	for b in beans:
		if b.collected:
			continue
		var bn: Polygon2D = b.node
		if not is_instance_valid(bn):
			continue
		var t := create_tween().set_parallel(true)
		t.tween_property(bn, "position", cowboy.position, 0.4) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		t.tween_property(bn, "modulate:a", 0.0, 0.4)
		t.chain().tween_callback(bn.queue_free)
		if get_node_or_null("/root/GameState"):
			GameState.bounty += PER_BEAN_BONUS
	if get_node_or_null("/root/GameState"):
		GameState.bounty += CASCADE_BONUS
	DamagePopup.spawn_bounty(self, cowboy.position, CASCADE_BONUS)
	await get_tree().create_timer(0.6).timeout

func _gold_rush_tumbleweed_roll() -> void:
	# Iter 47: Coconut-Wheel-style ceremony. A jeweled rainbow tumbleweed
	# rolls across the screen. Player can shoot it (re-enables firing).
	# Each hit extends lifespan + gives +200 BOUNTY. On expiration, the
	# tumbleweed bursts into 8 candy fragments — the chain reaction.
	_shooting_active = true
	# Build the tumbleweed inline — a Node2D with star + rainbow stripes.
	var tw := Node2D.new()
	tw.position = Vector2(-160, 700)
	add_child(tw)
	# Outer 12-pointed star (alternating outer/inner radii for spikes).
	var star := Polygon2D.new()
	star.color = Color(0.96, 0.78, 0.30, 1.0)
	var star_verts := PackedVector2Array()
	for i in range(24):
		var a: float = float(i) / 24.0 * TAU
		var r: float = 84.0 if i % 2 == 0 else 54.0
		star_verts.append(Vector2(cos(a), sin(a)) * r)
	star.polygon = star_verts
	tw.add_child(star)
	# Three rainbow stripes through the middle.
	for j in range(3):
		var stripe := Polygon2D.new()
		stripe.color = Color.from_hsv(float(j) / 3.0, 0.85, 1.0, 0.7)
		stripe.rotation = float(j) * PI / 3.0
		stripe.polygon = PackedVector2Array([
			Vector2(-58, -12), Vector2(58, -12),
			Vector2(58, 12), Vector2(-58, 12),
		])
		tw.add_child(stripe)
	# Roll parameters: lifespan scales with posse_count so a full posse
	# gets more time to score hits than a barely-alive one-dude survivor.
	var lifespan: float = 3.5 + 0.4 * float(maxi(posse_count, 1))
	var velocity := Vector2(320, 0)  # rolls right
	var rot_speed: float = 5.0       # rad/s
	const HIT_RADIUS_SQ: float = 110.0 * 110.0
	const BONUS_PER_HIT: int = 200
	const LIFESPAN_EXTENSION: float = 0.35
	var hit_count: int = 0
	# Per-frame loop: move + rotate + check bullet collisions.
	# Exit early if off-screen.
	while lifespan > 0.0 and is_inside_tree() and tw.position.x < 1240:
		var dt: float = get_process_delta_time()
		tw.position += velocity * dt
		tw.rotation += rot_speed * dt
		lifespan -= dt
		for bullet in get_tree().get_nodes_in_group("bullets"):
			if bullet.position.distance_squared_to(tw.position) < HIT_RADIUS_SQ:
				bullet.queue_free()
				hit_count += 1
				if get_node_or_null("/root/GameState"):
					GameState.bounty += BONUS_PER_HIT
				DamagePopup.spawn_bounty(self, tw.position, BONUS_PER_HIT)
				if shake and shake.has_method("add_trauma"):
					shake.add_trauma(0.18)
				lifespan += LIFESPAN_EXTENSION
		await get_tree().process_frame
	# Cascade: ROLLED banner + spawn 8 candy fragments bursting outward
	# from the tumbleweed's final position. Each fragment is +75 BOUNTY,
	# so the chain reaction totals 600 base regardless of hit count.
	_shooting_active = false
	const CASCADE_FRAGMENT_BONUS: int = 75
	const CASCADE_FRAGMENT_COUNT: int = 8
	var burst_pos: Vector2 = tw.position
	FlourishBanner.spawn($UI, "ROLLED", self)
	for i in range(CASCADE_FRAGMENT_COUNT):
		var frag := Polygon2D.new()
		frag.color = Color.from_hsv(float(i) / float(CASCADE_FRAGMENT_COUNT), 0.85, 1.0, 1.0)
		frag.polygon = PackedVector2Array([
			Vector2(-14, -8), Vector2(14, -8), Vector2(14, 8), Vector2(-14, 8),
		])
		frag.position = burst_pos
		add_child(frag)
		var dir: Vector2 = Vector2.UP.rotated(float(i) / float(CASCADE_FRAGMENT_COUNT) * TAU)
		var t: Tween = create_tween().set_parallel(true)
		t.tween_property(frag, "position", burst_pos + dir * 560.0, 0.7) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		t.tween_property(frag, "rotation", dir.angle(), 0.7)
		t.tween_property(frag, "modulate:a", 0.0, 0.7) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		t.chain().tween_callback(frag.queue_free)
		if get_node_or_null("/root/GameState"):
			GameState.bounty += CASCADE_FRAGMENT_BONUS
	DamagePopup.spawn_bounty(self, burst_pos,
		CASCADE_FRAGMENT_BONUS * CASCADE_FRAGMENT_COUNT)
	tw.queue_free()
	DebugLog.add("rush D done: %d hits, total ~%d bounty" % [
		hit_count, hit_count * BONUS_PER_HIT + CASCADE_FRAGMENT_BONUS * CASCADE_FRAGMENT_COUNT,
	])
	await get_tree().create_timer(0.8).timeout

func _gold_rush_candy_cart_chain() -> void:
	# Iter 49: Striped+Wrapped combo. Covered wagon parked center. N cargo
	# crates appear sequentially; player TAPS each to load it onto the
	# cart (+50 BOUNTY per load). After all loaded + 1.2s countdown, the
	# cart detonates in cascading line clears — each crate fires fireworks
	# across one screen-row (+500 per crate). CHAIN banner.
	_shooting_active = false
	const PER_LOAD_BONUS: int = 50
	const PER_LINE_BONUS: int = 500
	const COUNTDOWN_S: float = 1.2
	const MAX_CRATES: int = 5
	var crate_count: int = mini(maxi(posse_count, 1), MAX_CRATES)
	# 1) Build the wagon: brown rectangle + arched canopy + 2 wheels.
	var wagon := Node2D.new()
	wagon.position = Vector2(540, 1100)
	add_child(wagon)
	var body := Polygon2D.new()
	body.color = Color(0.55, 0.32, 0.16, 1.0)
	body.polygon = PackedVector2Array([
		Vector2(-160, -40), Vector2(160, -40),
		Vector2(160, 40), Vector2(-160, 40),
	])
	wagon.add_child(body)
	var canopy := Polygon2D.new()
	canopy.color = Color(0.96, 0.88, 0.74, 1.0)
	var canopy_pts := PackedVector2Array()
	for i in range(13):
		var t: float = float(i) / 12.0
		var x: float = lerpf(-160.0, 160.0, t)
		var y: float = -40.0 - sin(t * PI) * 60.0
		canopy_pts.append(Vector2(x, y))
	canopy_pts.append(Vector2(160, -40))
	canopy_pts.append(Vector2(-160, -40))
	canopy.polygon = canopy_pts
	wagon.add_child(canopy)
	for wx in [-120, 120]:
		var wheel := Polygon2D.new()
		wheel.color = Color(0.32, 0.18, 0.08, 1.0)
		var wpts := PackedVector2Array()
		for v in range(12):
			var a: float = float(v) / 12.0 * TAU
			wpts.append(Vector2(cos(a), sin(a)) * 30.0)
		wheel.polygon = wpts
		wheel.position = Vector2(float(wx), 55)
		wagon.add_child(wheel)
	# 2) Spawn cargo crates around the wagon at varied positions.
	#    Each is a Button (tap-target) styled as a brown crate. Tapping
	#    loads it: tween into the wagon, count up bonus, free the button.
	var loaded_count: int = 0
	var crates: Array[Button] = []
	for i in range(crate_count):
		var crate := Button.new()
		crate.custom_minimum_size = Vector2(110, 110)
		crate.size = Vector2(110, 110)
		# Style: solid brown box with stripe overlay via stylebox.
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.78, 0.55, 0.28, 1)
		sb.border_color = Color(0.42, 0.26, 0.13, 1)
		sb.border_width_left = 6
		sb.border_width_top = 6
		sb.border_width_right = 6
		sb.border_width_bottom = 6
		sb.corner_radius_top_left = 8
		sb.corner_radius_top_right = 8
		sb.corner_radius_bottom_right = 8
		sb.corner_radius_bottom_left = 8
		crate.add_theme_stylebox_override("normal", sb)
		crate.add_theme_stylebox_override("hover", sb)
		crate.add_theme_stylebox_override("pressed", sb)
		crate.text = "🍬"
		crate.add_theme_font_size_override("font_size", 48)
		# Arrange in a horizontal row above + below the wagon.
		var spread_x: float = lerpf(220.0, 860.0, float(i) / float(maxi(crate_count - 1, 1)))
		crate.position = Vector2(spread_x - 55.0, 1240.0 if i % 2 == 0 else 950.0)
		add_child(crate)
		crates.append(crate)
		# Pop-in tween
		crate.scale = Vector2(0.2, 0.2)
		var t_in := create_tween()
		t_in.tween_interval(float(i) * 0.18)
		t_in.tween_property(crate, "scale", Vector2.ONE, 0.22) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		# Closure for the tap handler — Godot 4 lambdas capture vars.
		crate.pressed.connect(func():
			if not is_instance_valid(crate):
				return
			loaded_count += 1
			if get_node_or_null("/root/GameState"):
				GameState.bounty += PER_LOAD_BONUS
			DamagePopup.spawn_bounty(self, crate.global_position
				+ crate.size * 0.5, PER_LOAD_BONUS)
			# Animate the crate tweening into the wagon center then queue_free.
			crate.disabled = true
			var t_load := create_tween().set_parallel(true)
			t_load.tween_property(crate, "global_position",
				wagon.global_position - crate.size * 0.5, 0.35) \
				.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
			t_load.tween_property(crate, "scale", Vector2(0.4, 0.4), 0.35)
			t_load.tween_property(crate, "modulate:a", 0.0, 0.35)
			t_load.chain().tween_callback(crate.queue_free))
	# 3) Wait for player to load crates. Cap wait at 5 seconds OR all
	#    crates loaded, whichever comes first.
	var wait_time: float = 5.0
	while loaded_count < crate_count and wait_time > 0.0:
		await get_tree().process_frame
		wait_time -= get_process_delta_time()
	# Any unloaded crates: auto-collect at half rate (showing the tactical
	# loss of slow tapping).
	for c in crates:
		if is_instance_valid(c) and not c.disabled:
			c.disabled = true
			var t := create_tween()
			t.tween_property(c, "modulate:a", 0.0, 0.3)
			t.chain().tween_callback(c.queue_free)
	# 4) Countdown then detonate. Wagon flashes red, then explodes outward.
	wagon.modulate = Color(1.0, 0.4, 0.4, 1.0)
	await get_tree().create_timer(COUNTDOWN_S).timeout
	# 5) Chain reaction: each loaded crate fires fireworks across one row.
	const NUM_ROWS: int = 5
	var actual_lines: int = mini(loaded_count, NUM_ROWS)
	for row in range(actual_lines):
		var row_y: float = lerpf(300.0, 1100.0, float(row) / float(maxi(NUM_ROWS - 1, 1)))
		# Two fireworks per row sweeping outward from center.
		for dir_sign in [-1, 1]:
			var fw := Polygon2D.new()
			fw.color = Color.from_hsv(float(row) / float(NUM_ROWS), 0.9, 1.0, 0.95)
			fw.polygon = PackedVector2Array([
				Vector2(-30, -10), Vector2(30, -10),
				Vector2(30, 10), Vector2(-30, 10),
			])
			fw.position = wagon.position + Vector2(0, row_y - wagon.position.y)
			add_child(fw)
			var end_x: float = (1240.0 if dir_sign > 0 else -160.0)
			var t := create_tween().set_parallel(true)
			t.tween_property(fw, "position:x", end_x, 0.5) \
				.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			t.tween_property(fw, "modulate:a", 0.0, 0.5)
			t.chain().tween_callback(fw.queue_free)
		if shake and shake.has_method("add_trauma"):
			shake.add_trauma(0.30)
		if get_node_or_null("/root/GameState"):
			GameState.bounty += PER_LINE_BONUS
		DamagePopup.spawn_bounty(self, wagon.position
			+ Vector2(0, row_y - wagon.position.y), PER_LINE_BONUS)
		await get_tree().create_timer(0.18).timeout
	FlourishBanner.spawn($UI, "CHAIN", self)
	# Fade wagon out
	var fade := create_tween()
	fade.tween_property(wagon, "modulate:a", 0.0, 0.6)
	fade.chain().tween_callback(wagon.queue_free)
	await get_tree().create_timer(0.8).timeout

func _gold_rush_liquorice_locomotive() -> void:
	# Iter 51: Color Bomb chain. A black liquorice steam train chuffs
	# across the bottom of the screen pulling N candy cars (one per
	# remaining posse member). Player taps each car as it passes through
	# the tap zone. Tapping in sequence builds a multiplier (×2,×3,×4).
	# Last car (caboose) tap triggers the LOCOMOTIVE finale with all
	# previous multiplier value compounded.
	_shooting_active = false
	const PER_CAR_BONUS: int = 200
	const LAST_CAR_FINALE: int = 1500
	const TRAIN_Y: float = 1380.0
	const MAX_CARS: int = 5
	var car_count: int = mini(maxi(posse_count, 1), MAX_CARS)
	# Train assembly: engine + N cars. All move together left→right.
	var train := Node2D.new()
	train.position = Vector2(-380.0, TRAIN_Y)  # off-screen left
	add_child(train)
	# Engine (steam locomotive — black with red wheels + smokestack)
	var engine_body := Polygon2D.new()
	engine_body.color = Color(0.08, 0.06, 0.05, 1.0)
	engine_body.polygon = PackedVector2Array([
		Vector2(0, -60), Vector2(140, -60),
		Vector2(140, 30), Vector2(0, 30),
	])
	train.add_child(engine_body)
	var stack := Polygon2D.new()
	stack.color = Color(0.18, 0.14, 0.10, 1.0)
	stack.polygon = PackedVector2Array([
		Vector2(20, -100), Vector2(60, -100),
		Vector2(60, -60), Vector2(20, -60),
	])
	train.add_child(stack)
	for wx in [20, 80, 130]:
		var w := Polygon2D.new()
		w.color = Color(0.78, 0.18, 0.18, 1.0)
		var pts := PackedVector2Array()
		for v in range(10):
			var a: float = float(v) / 10.0 * TAU
			pts.append(Vector2(cos(a), sin(a)) * 24.0)
		w.polygon = pts
		w.position = Vector2(float(wx), 40)
		train.add_child(w)
	# Cars — Buttons (tap targets) following the engine.
	var cars: Array[Button] = []
	for i in range(car_count):
		var car := Button.new()
		car.custom_minimum_size = Vector2(140, 95)
		car.size = Vector2(140, 95)
		car.position = Vector2(170.0 + float(i) * 155.0, -55.0)
		# Candy-themed colors per car, cycling rainbow
		var hue: float = float(i) / float(car_count)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color.from_hsv(hue, 0.85, 0.95, 1.0)
		sb.border_color = Color(0.18, 0.05, 0.10, 1.0)
		sb.border_width_left = 5
		sb.border_width_top = 5
		sb.border_width_right = 5
		sb.border_width_bottom = 5
		sb.corner_radius_top_left = 12
		sb.corner_radius_top_right = 12
		sb.corner_radius_bottom_right = 12
		sb.corner_radius_bottom_left = 12
		car.add_theme_stylebox_override("normal", sb)
		car.add_theme_stylebox_override("hover", sb)
		car.add_theme_stylebox_override("pressed", sb)
		car.text = "🍭" if i < car_count - 1 else "🎆"
		car.add_theme_font_size_override("font_size", 44)
		train.add_child(car)
		cars.append(car)
	# Connector polygons between cars (visual coupling).
	for i in range(car_count):
		var conn := Polygon2D.new()
		conn.color = Color(0.12, 0.08, 0.06, 1.0)
		conn.polygon = PackedVector2Array([
			Vector2(150.0 + float(i) * 155.0, -8),
			Vector2(170.0 + float(i) * 155.0, -8),
			Vector2(170.0 + float(i) * 155.0, 8),
			Vector2(150.0 + float(i) * 155.0, 8),
		])
		train.add_child(conn)
	# Counters
	var taps: int = 0
	var current_multi: int = 1
	# Wire each car's pressed signal (closure captures i + car).
	for i in range(car_count):
		var car := cars[i]
		var car_index: int = i
		car.pressed.connect(func():
			if not is_instance_valid(car) or car.disabled:
				return
			car.disabled = true
			taps += 1
			# Building chain — multiplier grows for sequential taps
			current_multi = mini(taps + 1, 4)
			var car_bonus: int = PER_CAR_BONUS * current_multi
			if get_node_or_null("/root/GameState"):
				GameState.bounty += car_bonus
			# Tap visual: car flashes white + +bounty popup at car center
			var center: Vector2 = car.global_position + car.size * 0.5
			DamagePopup.spawn_bounty(self, center, car_bonus)
			var flash := create_tween()
			flash.tween_property(car, "modulate", Color(2.0, 2.0, 2.0, 1.0), 0.06)
			flash.tween_property(car, "modulate", Color(1, 1, 1, 0.2), 0.45)
			if shake and shake.has_method("add_trauma"):
				shake.add_trauma(0.25))
	# Slide the train across the screen over ~4 seconds.
	const TRAIN_TRAVEL_S: float = 4.0
	var slide := create_tween()
	slide.tween_property(train, "position:x", 1400.0, TRAIN_TRAVEL_S) \
		.set_trans(Tween.TRANS_LINEAR)
	# Wait for the slide to complete OR all cars tapped, whichever first.
	var elapsed: float = 0.0
	while elapsed < TRAIN_TRAVEL_S and taps < car_count and is_inside_tree():
		await get_tree().process_frame
		elapsed += get_process_delta_time()
	# Cascade: finale. If the player tapped the caboose (last car), give
	# the full LAST_CAR_FINALE bonus + screen-clearing fireworks. Even
	# without finale tap, fire the LOCOMOTIVE banner so the rush ends
	# cleanly.
	if taps >= car_count and get_node_or_null("/root/GameState"):
		GameState.bounty += LAST_CAR_FINALE
		var finale_center := Vector2(540, 1100)
		DamagePopup.spawn_bounty(self, finale_center, LAST_CAR_FINALE)
		# Burst rainbow rays from the caboose position
		for i in range(16):
			var ray := Polygon2D.new()
			ray.color = Color.from_hsv(float(i) / 16.0, 0.9, 1.0, 1.0)
			ray.polygon = PackedVector2Array([
				Vector2(-20, -5), Vector2(20, -5),
				Vector2(20, 5), Vector2(-20, 5),
			])
			ray.position = finale_center
			add_child(ray)
			var dir: Vector2 = Vector2.RIGHT.rotated(float(i) / 16.0 * TAU)
			var t := create_tween().set_parallel(true)
			t.tween_property(ray, "position", finale_center + dir * 800.0, 0.7) \
				.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			t.tween_property(ray, "rotation", dir.angle(), 0.7)
			t.tween_property(ray, "modulate:a", 0.0, 0.7)
			t.chain().tween_callback(ray.queue_free)
		if shake and shake.has_method("add_trauma"):
			shake.add_trauma(0.95)
	FlourishBanner.spawn($UI, "LOCOMOTIVE", self)
	# Fade train out
	var fade := create_tween()
	fade.tween_property(train, "modulate:a", 0.0, 0.6)
	fade.chain().tween_callback(train.queue_free)
	DebugLog.add("rush F done: %d/%d cars tapped, multi=%d" % [taps, car_count, current_multi])
	await get_tree().create_timer(0.8).timeout

func _gold_rush_avalanche_bonanza() -> void:
	# Iter 50: Cascading combos. Liquorice boulders + giant jelly beans
	# rain from the top of the screen. Player shoots them. Each hit:
	# +100 BOUNTY × multiplier (starts ×1, increments ×1 per consecutive
	# hit, caps at ×5). Miss any boulder reaching the cowboy → multiplier
	# resets to ×1. After 5s of raining, the final boulder bursts into
	# screen-shake chain explosion → AVALANCHE banner + +1200 bonus.
	_shooting_active = true
	const RUSH_DURATION: float = 5.0
	const SPAWN_INTERVAL: float = 0.30
	const BASE_HIT_BONUS: int = 100
	const MULTI_CAP: int = 5
	const CASCADE_BONUS: int = 1200
	const BOULDER_GRAVITY: float = 380.0
	const HIT_RADIUS_SQ: float = 80.0 * 80.0
	const COWBOY_ZONE_Y: float = 1620.0  # below this = "reached cowboy" = miss
	# Boulder pool: each entry is {node, vel, hp}
	var boulders: Array[Dictionary] = []
	var spawn_timer: float = 0.0
	var rush_timer: float = RUSH_DURATION
	var multi: int = 1
	var rng := RandomNumberGenerator.new()
	rng.seed = 5050
	var hit_total_count: int = 0
	while rush_timer > 0.0 and is_inside_tree():
		var dt: float = get_process_delta_time()
		rush_timer -= dt
		spawn_timer -= dt
		# Spawn a new boulder
		if spawn_timer <= 0.0:
			spawn_timer = SPAWN_INTERVAL
			var b := Polygon2D.new()
			# Mix liquorice (black) and jelly bean (random hue) boulders
			if rng.randf() < 0.5:
				b.color = Color(0.10, 0.07, 0.06, 1.0)
			else:
				b.color = Color.from_hsv(rng.randf(), 0.85, 1.0, 1.0)
			var pts: PackedVector2Array = PackedVector2Array()
			var sides: int = 6 + rng.randi() % 3  # 6-8 sided
			for k in range(sides):
				var a: float = float(k) / float(sides) * TAU
				var r: float = rng.randf_range(34.0, 52.0)
				pts.append(Vector2(cos(a), sin(a)) * r)
			b.polygon = pts
			b.position = Vector2(rng.randf_range(120.0, 960.0), -80.0)
			add_child(b)
			boulders.append({
				"node": b,
				"vel": Vector2(0, rng.randf_range(280.0, 380.0)),
				"hp": 1,
			})
		# Update each boulder
		for i in range(boulders.size() - 1, -1, -1):
			var entry: Dictionary = boulders[i]
			var node: Polygon2D = entry.node
			if not is_instance_valid(node):
				boulders.remove_at(i)
				continue
			entry.vel.y += BOULDER_GRAVITY * dt
			node.position += entry.vel * dt
			node.rotation += 1.5 * dt
			# Bullet hit check
			var was_hit: bool = false
			for bullet in get_tree().get_nodes_in_group("bullets"):
				if bullet.position.distance_squared_to(node.position) < HIT_RADIUS_SQ:
					bullet.queue_free()
					was_hit = true
					break
			if was_hit:
				hit_total_count += 1
				var bonus: int = BASE_HIT_BONUS * multi
				if get_node_or_null("/root/GameState"):
					GameState.bounty += bonus
				DamagePopup.spawn_bounty(self, node.position, bonus)
				multi = mini(multi + 1, MULTI_CAP)
				if shake and shake.has_method("add_trauma"):
					shake.add_trauma(0.20)
				# Burst the boulder
				var burst := create_tween().set_parallel(true)
				burst.tween_property(node, "scale", Vector2(1.8, 1.8), 0.2)
				burst.tween_property(node, "modulate:a", 0.0, 0.2)
				burst.chain().tween_callback(node.queue_free)
				boulders.remove_at(i)
				continue
			# Reached cowboy zone = miss → reset multiplier
			if node.position.y > COWBOY_ZONE_Y:
				multi = 1
				node.queue_free()
				boulders.remove_at(i)
		await get_tree().process_frame
	# Chain reaction: cascade finale. Big rainbow explosion at center +
	# AVALANCHE banner + flat bonus.
	_shooting_active = false
	const FINALE_RAY_COUNT: int = 12
	var finale_center := Vector2(540, 900)
	for i in range(FINALE_RAY_COUNT):
		var ray := Polygon2D.new()
		ray.color = Color.from_hsv(float(i) / float(FINALE_RAY_COUNT), 0.9, 1.0, 1.0)
		ray.polygon = PackedVector2Array([
			Vector2(-22, -6), Vector2(22, -6),
			Vector2(22, 6), Vector2(-22, 6),
		])
		ray.position = finale_center
		add_child(ray)
		var dir: Vector2 = Vector2.RIGHT.rotated(float(i) / float(FINALE_RAY_COUNT) * TAU)
		var t := create_tween().set_parallel(true)
		t.tween_property(ray, "position", finale_center + dir * 700.0, 0.65) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		t.tween_property(ray, "rotation", dir.angle(), 0.65)
		t.tween_property(ray, "modulate:a", 0.0, 0.65)
		t.chain().tween_callback(ray.queue_free)
	if shake and shake.has_method("add_trauma"):
		shake.add_trauma(0.95)
	if get_node_or_null("/root/GameState"):
		GameState.bounty += CASCADE_BONUS
	FlourishBanner.spawn($UI, "AVALANCHE", self)
	DamagePopup.spawn_bounty(self, finale_center, CASCADE_BONUS)
	DebugLog.add("rush G done: %d hits, final multi=%d" % [hit_total_count, multi])
	await get_tree().create_timer(0.85).timeout

func _gold_rush_gumball_runaway() -> void:
	# Iter 52: Coconut Wheel solo. Giant rainbow gumball (boulder-sized,
	# 180px radius) rolls DOWN the screen from y=200. Player shoots to
	# KEEP it rolling — each shot extends its lifespan + slows decay.
	# Without sustained fire, the gumball slows and stalls.
	# If it reaches y=1700 (cowboy zone) → STAMPEDE finale +1500.
	# If it stalls short → partial bonus proportional to distance traveled.
	_shooting_active = true
	const PER_HIT_BONUS: int = 75
	const FINALE_FULL_BONUS: int = 1500
	const START_Y: float = 200.0
	const TARGET_Y: float = 1700.0
	const HIT_RADIUS_SQ: float = 180.0 * 180.0
	const BASE_VELOCITY: float = 60.0   # natural roll speed (px/s) before shots
	const SHOT_BOOST: float = 130.0     # added to velocity per hit, decays
	const VELOCITY_DECAY: float = 0.85  # per-second toward BASE
	const STALL_THRESHOLD: float = 35.0 # if velocity drops below this for too long, stall
	# Build the gumball: outer big circle + 5 rainbow stripe wedges inside.
	var gumball := Node2D.new()
	gumball.position = Vector2(540.0, START_Y)
	add_child(gumball)
	var outer := Polygon2D.new()
	outer.color = Color(0.98, 0.96, 0.92, 1.0)
	var outer_pts := PackedVector2Array()
	for v in range(36):
		var a: float = float(v) / 36.0 * TAU
		outer_pts.append(Vector2(cos(a), sin(a)) * 180.0)
	outer.polygon = outer_pts
	gumball.add_child(outer)
	# Rainbow wedges — 6 pie slices in candy colors.
	for j in range(6):
		var slice := Polygon2D.new()
		slice.color = Color.from_hsv(float(j) / 6.0, 0.85, 1.0, 0.9)
		var slice_pts: PackedVector2Array = PackedVector2Array()
		slice_pts.append(Vector2.ZERO)
		var a0: float = float(j) / 6.0 * TAU
		var a1: float = float(j + 1) / 6.0 * TAU
		var steps: int = 6
		for s in range(steps + 1):
			var a: float = lerpf(a0, a1, float(s) / float(steps))
			slice_pts.append(Vector2(cos(a), sin(a)) * 160.0)
		slice.polygon = slice_pts
		gumball.add_child(slice)
	var velocity: float = BASE_VELOCITY
	var hit_count: int = 0
	var reached_target: bool = false
	while is_inside_tree() and not reached_target:
		var dt: float = get_process_delta_time()
		# Decay velocity toward BASE
		velocity = lerpf(velocity, BASE_VELOCITY, VELOCITY_DECAY * dt)
		# Move + rotate
		gumball.position.y += velocity * dt
		gumball.rotation += velocity * 0.012 * dt
		# Check bullet collisions
		for bullet in get_tree().get_nodes_in_group("bullets"):
			if bullet.position.distance_squared_to(gumball.position) < HIT_RADIUS_SQ:
				bullet.queue_free()
				hit_count += 1
				velocity += SHOT_BOOST
				if get_node_or_null("/root/GameState"):
					GameState.bounty += PER_HIT_BONUS
				DamagePopup.spawn_bounty(self, gumball.position, PER_HIT_BONUS)
				if shake and shake.has_method("add_trauma"):
					shake.add_trauma(0.18)
				# Scale-pop the gumball briefly for feedback
				var pop := create_tween()
				pop.tween_property(gumball, "scale", Vector2(1.1, 1.1), 0.08)
				pop.tween_property(gumball, "scale", Vector2.ONE, 0.15)
		# Reached cowboy zone?
		if gumball.position.y >= TARGET_Y:
			reached_target = true
			break
		# Stall check — if velocity stays under threshold, end early
		# (with partial bonus). Caller measures by distance traveled.
		if velocity < STALL_THRESHOLD and gumball.position.y > START_Y + 200.0:
			# Give the player ~1 more second to recover with shots
			var grace: float = 1.2
			while grace > 0.0 and velocity < STALL_THRESHOLD:
				var gdt: float = get_process_delta_time()
				grace -= gdt
				# Continue per-frame checks
				for bullet in get_tree().get_nodes_in_group("bullets"):
					if bullet.position.distance_squared_to(gumball.position) < HIT_RADIUS_SQ:
						bullet.queue_free()
						hit_count += 1
						velocity += SHOT_BOOST
						if get_node_or_null("/root/GameState"):
							GameState.bounty += PER_HIT_BONUS
						DamagePopup.spawn_bounty(self, gumball.position, PER_HIT_BONUS)
				await get_tree().process_frame
			if velocity < STALL_THRESHOLD:
				break  # stalled — end the rush early
		await get_tree().process_frame
	# Cascade phase: rainbow burst from gumball position, bonus scaled
	# by distance traveled. Reaching the target = full STAMPEDE finale.
	_shooting_active = false
	var distance_traveled: float = gumball.position.y - START_Y
	var distance_pct: float = clampf(distance_traveled
		/ (TARGET_Y - START_Y), 0.0, 1.0)
	var partial_bonus: int = int(float(FINALE_FULL_BONUS) * distance_pct)
	const FINALE_RAYS: int = 14
	for i in range(FINALE_RAYS):
		var ray := Polygon2D.new()
		ray.color = Color.from_hsv(float(i) / float(FINALE_RAYS), 0.9, 1.0, 1.0)
		ray.polygon = PackedVector2Array([
			Vector2(-22, -7), Vector2(22, -7),
			Vector2(22, 7), Vector2(-22, 7),
		])
		ray.position = gumball.position
		add_child(ray)
		var dir: Vector2 = Vector2.RIGHT.rotated(float(i) / float(FINALE_RAYS) * TAU)
		var t := create_tween().set_parallel(true)
		t.tween_property(ray, "position", gumball.position + dir * 720.0, 0.7) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		t.tween_property(ray, "rotation", dir.angle(), 0.7)
		t.tween_property(ray, "modulate:a", 0.0, 0.7)
		t.chain().tween_callback(ray.queue_free)
	if get_node_or_null("/root/GameState"):
		GameState.bounty += partial_bonus
	DamagePopup.spawn_bounty(self, gumball.position, partial_bonus)
	if shake and shake.has_method("add_trauma"):
		shake.add_trauma(0.6 + 0.35 * distance_pct)
	FlourishBanner.spawn($UI, "STAMPEDE", self)
	# Fade gumball
	var fade := create_tween()
	fade.tween_property(gumball, "modulate:a", 0.0, 0.6)
	fade.tween_property(gumball, "scale", Vector2(1.4, 1.4), 0.6)
	fade.chain().tween_callback(gumball.queue_free)
	DebugLog.add("rush H done: %d hits, %.0f%% distance, partial=%d" % [
		hit_count, distance_pct * 100.0, partial_bonus,
	])
	await get_tree().create_timer(0.8).timeout

# Gold Rush A — Six-Shooter Salute.
# Each remaining dude (leader cowboy + active followers) fires once into
# the sky, staggered 300ms apart. Each shot spawns:
#   - muzzle flash above their head
#   - gunfire SFX (rolls through the existing 6-player pool)
#   - +50 BOUNTY popup
#   - GameState.bounty incremented by 50
# Caller awaits this so the WinOverlay slides in AFTER the salute
# completes. Ceremony length ~ posse_count × 300ms (max 1.5s at 5 dudes).
const SALUTE_BONUS_PER_SHOT: int = 50
const SALUTE_STAGGER_S: float = 0.30
const SALUTE_END_HOLD_S: float = 0.35

func _gold_rush_six_shooter_salute() -> void:
	# Build the salute roster: leader's position + each follower.
	var positions: Array[Vector2] = []
	if cowboy:
		positions.append(cowboy.global_position)
	if posse_renderer:
		for follower_pos in posse_renderer.get_dude_world_positions():
			positions.append(follower_pos)
	DebugLog.add("gold rush: six-shooter salute, %d dudes" % positions.size())
	var total_earned: int = 0
	for i in range(positions.size()):
		await get_tree().create_timer(SALUTE_STAGGER_S).timeout
		if not is_inside_tree():
			return
		# Anchor effects ~100px above each dude's spawn point so the
		# shot reads as "fired upward into the air".
		var spot: Vector2 = positions[i] + Vector2(0, -110)
		var flash := MuzzleFlashScene.instantiate()
		flash.position = spot
		add_child(flash)
		AudioBus.play_gunfire()
		DamagePopup.spawn_bounty(self, spot, SALUTE_BONUS_PER_SHOT)
		total_earned += SALUTE_BONUS_PER_SHOT
		if get_node_or_null("/root/GameState"):
			GameState.bounty += SALUTE_BONUS_PER_SHOT
	# Final beat — the silence between the last shot and the modal sells
	# "ceremony complete." Shake camera once on the final shot for punch.
	if shake and shake.has_method("add_trauma"):
		shake.add_trauma(0.45)
	# Iter 44: Candy-Crush-style CASCADE finale. Each per-shot bounty
	# popup spawned a "coin" that we now sweep to screen center, fuse
	# together, and explode into a PERFECT VOLLEY! mega-pop. The
	# cascade trigger is the LAST salute shot; the effect is a chain
	# reaction across all the earned coins. Equivalent to Candy Crush
	# Striped + Wrapped combo's screen-clearing explosion.
	await _salute_cascade_finale(positions)
	await get_tree().create_timer(SALUTE_END_HOLD_S).timeout
	DebugLog.add("gold rush salute done, earned=%d" % total_earned)

# Iter 44: cascade finale. Spawns one gold "coin" Polygon2D per remaining
# dude, tweens them all converging toward screen center (~540, 700), then
# explodes into a PERFECT VOLLEY banner + a +500 bonus popup. The chain
# reaction is the whole point — each individual +50 was modest, the
# cascade is where the player goes "ohh that was worth it." Bonus magnitude
# scales with how many coins converged (more dudes = bigger finale).
const SALUTE_CASCADE_BONUS_BASE: int = 200
const SALUTE_CASCADE_BONUS_PER_COIN: int = 100
const SALUTE_CASCADE_TARGET: Vector2 = Vector2(540, 700)
const SALUTE_CASCADE_DURATION: float = 0.45

func _salute_cascade_finale(start_positions: Array[Vector2]) -> void:
	# Spawn coins at each starting position, tween toward center.
	var coins: Array[Polygon2D] = []
	for start_pos in start_positions:
		var coin: Polygon2D = Polygon2D.new()
		coin.color = Color(1.00, 0.92, 0.30, 1.0)
		# 12-vertex circle approximation, ~24px radius.
		var pts: PackedVector2Array = PackedVector2Array()
		for i in range(12):
			var a: float = float(i) / 12.0 * TAU
			pts.append(Vector2(cos(a), sin(a)) * 24.0)
		coin.polygon = pts
		coin.position = start_pos + Vector2(0, -80)  # above each dude's head
		add_child(coin)
		coins.append(coin)
	# Tween all coins toward center in parallel.
	for coin in coins:
		var t: Tween = create_tween().set_parallel(true)
		t.tween_property(coin, "position", SALUTE_CASCADE_TARGET, SALUTE_CASCADE_DURATION) \
			.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN)
		# Slight scale-up as they approach for "growing momentum" read.
		t.tween_property(coin, "scale", Vector2(1.6, 1.6), SALUTE_CASCADE_DURATION) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await get_tree().create_timer(SALUTE_CASCADE_DURATION).timeout
	# Coins converged — explode them away + fire the cascade banner.
	var bonus: int = SALUTE_CASCADE_BONUS_BASE + SALUTE_CASCADE_BONUS_PER_COIN * start_positions.size()
	FlourishBanner.spawn($UI, "PERFECT_VOLLEY", self)
	DamagePopup.spawn_bounty(self, SALUTE_CASCADE_TARGET, bonus)
	if get_node_or_null("/root/GameState"):
		GameState.bounty += bonus
	# Burst the coins outward as confetti — each tweens to a random
	# direction + fades to alpha 0 + queue_frees.
	for coin in coins:
		var dir: Vector2 = Vector2(randf_range(-1, 1), randf_range(-1, 1)).normalized()
		var t: Tween = create_tween().set_parallel(true)
		t.tween_property(coin, "position", coin.position + dir * 600.0, 0.55) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		t.tween_property(coin, "modulate:a", 0.0, 0.55)
		t.chain().tween_callback(coin.queue_free)

# Iter 25+: switch leader cowboy + every follower in PosseRenderer from
# run_shoot to idle. Called on win so the crowd visibly relaxes once
# the gates are done.
# Iter 27+: leader is now a Cowboy3D (Mixamo-rigged 3D model rendered
# via SubViewport). Old AnimatedSprite2D check kept as a fallback in
# case the 3D scene fails to load and we get the legacy sprite.
func _switch_posse_to_idle() -> void:
	var cowboy_3d: Node2D = cowboy.get_node_or_null("Cowboy3D") as Node2D
	if cowboy_3d and cowboy_3d.has_method("play_anim"):
		cowboy_3d.play_anim("idle")
	else:
		# Fallback: legacy 2D AnimatedSprite path (still used for followers).
		var cowboy_sprite: AnimatedSprite2D = cowboy.get_node_or_null("Sprite") as AnimatedSprite2D
		if cowboy_sprite and cowboy_sprite.sprite_frames and cowboy_sprite.sprite_frames.has_animation("idle"):
			cowboy_sprite.play("idle")
	if posse_renderer:
		posse_renderer.set_animation("idle")

func _on_again_pressed() -> void:
	AudioBus.play_tap()
	again_button.disabled = true
	menu_button.disabled = true
	var t := create_tween()
	t.tween_property(again_button, "scale", Vector2(0.92, 0.92), 0.06)
	t.tween_property(again_button, "scale", Vector2.ONE, 0.16) \
		.set_trans(Tween.TRANS_BACK) \
		.set_ease(Tween.EASE_OUT)
	await t.finished
	get_tree().reload_current_scene()

func _on_menu_pressed() -> void:
	AudioBus.play_tap()
	again_button.disabled = true
	menu_button.disabled = true
	var t := create_tween()
	t.tween_property(menu_button, "scale", Vector2(0.92, 0.92), 0.06)
	t.tween_property(menu_button, "scale", Vector2.ONE, 0.16) \
		.set_trans(Tween.TRANS_BACK) \
		.set_ease(Tween.EASE_OUT)
	await t.finished
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

# Iter 25+: in-level MENU button handler (top-left corner). Mid-game
# exit to main menu — works regardless of the back-gesture bug.
func _on_in_level_menu_pressed() -> void:
	AudioBus.play_tap()
	DebugLog.add("in-level MENU pressed → main_menu")
	_go_back_to_menu()
