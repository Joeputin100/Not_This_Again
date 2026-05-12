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
var posse_count: int = STARTING_POSSE:
	set(value):
		posse_count = maxi(1, value)
		_refresh_posse_label()
		# Push count to the renderer so trapezoid grows/shrinks in sync
		# with gameplay. Guarded — setter can fire before _ready resolves
		# the @onready var (e.g. during scene-load defaults).
		if posse_renderer:
			posse_renderer.posse_count = posse_count

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

	# Discover all gates by group instead of hand-listing — adding a 4th
	# gate to the scene tree later won't require code changes here.
	var gates := _gather_gates()
	progress.reset(gates.size())
	for gate in gates:
		gate.triggered.connect(_on_gate_triggered.bind(gate))
		gate.direction_flipped.connect(_on_gate_direction_flipped)

	again_button.pressed.connect(_on_again_pressed)
	menu_button.pressed.connect(_on_menu_pressed)
	# In-level MENU button (top-left corner). Workaround for the back-
	# gesture-still-exits-app bug — gives the player a reliable way to
	# leave a level without quitting the whole app.
	if in_level_menu_button:
		in_level_menu_button.pressed.connect(_on_in_level_menu_pressed)
	# Pivot for the win panel scale-in animation
	win_panel.pivot_offset = Vector2(440, 280)
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

	var bullet := BulletScene.instantiate()
	bullet.position = cowboy.position + Vector2(0, BULLET_SPAWN_Y_OFFSET)
	# max_range and damage are set BEFORE add_child so bullet._ready can
	# capture the values via the now-set var defaults. Property assignment
	# on the script var sticks regardless of _ready order.
	bullet.max_range = _gun.range_px
	bullet.damage = _gun.caliber
	# Iter 22d weather: bullets pick up per-spawn modifiers from the
	# level's current weather state. RAIN slows them; WIND_STORM curves
	# them. Defaults (1.0, 0.0) are no-effect.
	bullet.velocity_mult = bullet_velocity_mult
	bullet.lateral_drift = bullet_lateral_drift
	add_child(bullet)
	_bullets_fired += 1

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
				var was_destroyed: bool = barrel.take_damage(bullet.damage)
				if was_destroyed:
					_barrels_destroyed += 1
					shake.add_trauma(0.4)
				# Bullet is consumed on hit. Remove from group so the
				# next iteration of this pass doesn't see it again.
				bullet.remove_from_group("bullets")
				bullet.queue_free()
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
					bullet.remove_from_group("bullets")
					bullet.queue_free()
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
				var consumed: bool = obstacle.take_bullet_hit(bullet.damage)
				if consumed:
					bullet.remove_from_group("bullets")
					bullet.queue_free()
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
		posse_count = maxi(1, posse_count - damage)
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
			posse_count = maxi(1, posse_count - OutlawBulletScript.POSSE_DAMAGE)
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
			posse_count = maxi(1, posse_count - OutlawBulletScript.POSSE_DAMAGE)
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
			posse_count = maxi(1, posse_count - ProspectorScript.SWING_DAMAGE)
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
			posse_count = maxi(1, posse_count - damage)
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
			DebugLog.add("bonus equipped: UNKNOWN type=%s" % type)

func _input(event: InputEvent) -> void:
	# Track ALL inputs to verify _input is being called at all, not just
	# touch-flavored ones.
	_last_event_class = event.get_class()
	var new_x := -1.0
	if event is InputEventScreenDrag:
		new_x = (event as InputEventScreenDrag).position.x
		_last_input_type = "DRAG"
		_input_event_count += 1
	elif event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed:
		new_x = (event as InputEventScreenTouch).position.x
		_last_input_type = "TOUCH"
		_input_event_count += 1
	elif event is InputEventMouseMotion and ((event as InputEventMouseMotion).button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		new_x = (event as InputEventMouseMotion).position.x
		_last_input_type = "MOUSE_MOTION"
		_input_event_count += 1
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			new_x = mb.position.x
			_last_input_type = "MOUSE_BUTTON"
			_input_event_count += 1
	if new_x >= 0.0:
		target_x = MovementBounds.clamp_x(new_x)

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
		_spawn_combo_banner(combo_label)

	progress.record_pass()
	if progress.is_complete():
		_show_win()

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
	win_overlay.visible = true
	win_panel.scale = Vector2(0.55, 0.55)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(win_panel, "scale", Vector2.ONE, 0.32) \
		.set_trans(Tween.TRANS_BACK) \
		.set_ease(Tween.EASE_OUT)

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
