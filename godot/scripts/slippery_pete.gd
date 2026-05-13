extends Node2D

# Slippery Pete — Level 1 boss. Iter 32+: animated via VideoStreamPlayer
# with chromakey shader instead of the static Sprite2D iter 30 used.
# Five animations provided by the user (4s each, 720×1280, 24fps,
# H.264 → re-encoded to WebM/VP9 for Godot 4 native playback):
#
#   idle               → taps_foot_idle.webm
#   forward            → steps_forward.webm
#   strafe (one-way)   → strafe_right_to_left.webm (flipped for L→R)
#   shoot              → shoots_at_player.webm
#   hit                → hit_by_gunfire.webm
#
# Still to come from user: death, celebration, shouting abuse. For now
# death is the existing scale/rotation tween; celebration not used yet.
# Abuse dialog (iter 32+) will be wired separately through Text.random().
#
# State machine: BASE state (idle/forward) determined by Pete's
# position/scrolling. OVERLAY states (shoot, hit) override the base
# briefly via _override_timer, then revert. Avoids spammy state changes
# when Pete fires + gets hit on the same frame.

const OutlawBulletScene := preload("res://scenes/outlaw_bullet.tscn")
const OutlawBulletScript := preload("res://scripts/outlaw_bullet.gd")
const MuzzleFlashScene := preload("res://scenes/muzzle_flash.tscn")
const DamagePopup := preload("res://scripts/damage_popup.gd")

const STREAM_IDLE := preload("res://assets/videos/pete/taps_foot_idle.ogv")
const STREAM_FORWARD := preload("res://assets/videos/pete/steps_forward.ogv")
const STREAM_STRAFE := preload("res://assets/videos/pete/strafe_right_to_left.ogv")
const STREAM_SHOOT := preload("res://assets/videos/pete/shoots_at_player.ogv")
const STREAM_HIT := preload("res://assets/videos/pete/hit_by_gunfire.ogv")
const STREAM_DEATH := preload("res://assets/videos/pete/death.ogv")
const STREAM_CELEBRATE := preload("res://assets/videos/pete/celebrate.ogv")
const STREAM_SHOUTS := preload("res://assets/videos/pete/shouts.ogv")
const STREAM_COMPLAINS := preload("res://assets/videos/pete/complains.ogv")

const DeathPolish := preload("res://scripts/death_polish.gd")

# Death video duration. Pete's death is 8s (longer than the other 4s
# animations — dramatic boss exit). Used to await the video's end
# before applying the universal freeze-strobe polish.
const DEATH_DURATION: float = 8.0
# Celebrate is also 8s but we don't let it play full length — Pete
# should mostly be aggressing, not gloating. Truncate via overlay timer
# so the most expressive opening seconds of the animation play and then
# we return to forward/shoot pressure.
const CELEBRATE_OVERLAY_DURATION: float = 2.5

signal destroyed(x: float)
# Iter 40c: fired ONCE the first time Pete enters STAY mode (i.e. the
# moment the cowboy actually reaches him for the boss fight). Level.gd
# listens and uses this to stop terrain scroll — the showdown is an
# event, not a continued chase, so the world stops moving while the
# duel plays out.
signal engaged

const MAX_HP: int = 40
const SCROLL_SPEED: float = 200.0
const STAY_SCROLL_SPEED: float = 18.0
const STAY_DISTANCE_Y: float = 300.0
const TRACK_SPEED: float = 1.0
# Iter 37: tripled hitbox to match the 3x-scaled video display (690×1230
# px on screen vs vagrant's 150×270). Pete now genuinely looms over
# the posse — boss-tier silhouette readable from the moment he enters
# the screen.
const SIZE: Vector2 = Vector2(540, 840)
const COWBOY_DAMAGE: int = 30
const FIRE_INTERVAL: float = 0.7
const LEFT_GUN_X_OFFSET: float = 45.0
const BULLET_SPAWN_Y_OFFSET: float = 30.0
const ON_SCREEN_Y: float = 0.0

# How long shoot/hit animations override the base state. Both source
# clips are 4s but Pete fires every 0.7s and gets hit far more often,
# so we clip the overlay duration to keep state changes snappy.
const SHOOT_OVERLAY_DURATION: float = 0.35
const HIT_OVERLAY_DURATION: float = 0.45

enum State { IDLE, FORWARD, STRAFE_LEFT, STRAFE_RIGHT, SHOOT, HIT, CELEBRATE, SHOUT, COMPLAIN }

var hp: int = MAX_HP
var _destroyed: bool = false
var _fire_timer: float = 0.0
var _cowboy: Node2D = null
var _state: int = State.IDLE
var _override_timer: float = 0.0
# Iter 34: Pete celebrates briefly each time the posse_count drops
# (i.e., one of his shots — or another enemy's — killed a dude). Cache
# the level's posse_count between frames so we can detect the drop.
var _level: Node = null
var _last_posse_count: int = -1
# Iter 40c: latches true on first STAY-mode entry so the `engaged`
# signal only fires once per boss (otherwise it would emit every
# frame while Pete is within STAY_DISTANCE_Y).
var _engaged: bool = false

# Iter 55: speech-bubble throttle. Stores the last time we spawned a
# bubble of each category so rapid-fire damage doesn't blanket the
# screen in stacked Pete one-liners.
var _last_bubble_unix_ms: int = 0
const BUBBLE_COOLDOWN_MS: int = 800

@onready var hp_label: Label = $HpLabel
@onready var hp_bar: Control = $HpBar
@onready var name_label: Label = $NameLabel
@onready var splinters: CPUParticles2D = $Splinters
@onready var video: VideoStreamPlayer = $Video

func _ready() -> void:
	hp = MAX_HP
	_refresh_hp_label()
	if hp_bar:
		hp_bar.init(MAX_HP)
	if name_label:
		name_label.text = Text.lookup("boss.slippery_pete_name") if Text else "SLIPPERY PETE"
	add_to_group("outlaws")
	add_to_group("bosses")
	_cowboy = _find_cowboy()
	_level = get_parent()
	if _level and "posse_count" in _level:
		_last_posse_count = _level.posse_count
	_switch_to(State.IDLE)

func _find_cowboy() -> Node2D:
	var level := get_parent()
	if level:
		var c := level.get_node_or_null("Cowboy")
		if c:
			return c as Node2D
	return get_tree().root.find_child("Cowboy", true, false) as Node2D

func _process(delta: float) -> void:
	if _destroyed:
		return
	# Iter 35: tightened to fire ONLY when the posse is effectively
	# defeated — i.e., posse_count transitions from > 1 down to 1
	# (level.gd clamps to a minimum of 1, so 1 is "everyone but the
	# leader is dead"). Iter 34's "celebrate on every kill" was too
	# noisy mid-battle. Now Pete only gloats at the decisive moment.
	if _level and "posse_count" in _level:
		var pc: int = _level.posse_count
		if _last_posse_count > 1 and pc <= 1:
			if _state != State.HIT:
				_switch_to(State.CELEBRATE)
				_override_timer = CELEBRATE_OVERLAY_DURATION
		_last_posse_count = pc
	# Update overlay timer for momentary states (shoot/hit/celebrate).
	# When it runs out, revert to the base state determined by movement.
	if _override_timer > 0.0:
		_override_timer -= delta
		if _override_timer <= 0.0:
			_apply_base_state()
	if _cowboy:
		position.x = lerpf(position.x, _cowboy.position.x, clampf(TRACK_SPEED * delta, 0.0, 1.0))
	var dy: float = (_cowboy.position.y - position.y) if _cowboy else 1000.0
	position.y += (SCROLL_SPEED if dy > STAY_DISTANCE_Y else STAY_SCROLL_SPEED) * WorldSpeed.mult * delta
	# Iter 40c: latch on first STAY entry → notify the level so terrain
	# scroll can stop. The cowboy and Pete are now eye-to-eye; no more
	# world motion until the firefight resolves.
	if not _engaged and dy <= STAY_DISTANCE_Y and _cowboy:
		_engaged = true
		engaged.emit()
	if position.y > 2200.0:
		queue_free()
		return
	# Update base state (skipped if overlay is active — overlay reverts
	# via the timer above, then base state is reapplied).
	if _override_timer <= 0.0:
		_apply_base_state()
	if position.y < ON_SCREEN_Y:
		return
	_fire_timer += delta
	if _fire_timer >= FIRE_INTERVAL:
		_fire_timer = 0.0
		_spawn_dual_bullets()

func _apply_base_state() -> void:
	# Off-screen: foot-tap IDLE (Pete is waiting his turn to enter).
	# Approaching: FORWARD steps.
	# Crawl phase (in the posse's face): SHOUT — Yosemite-Sam-style
	# threats, picked over the silent foot-tap because once Pete is
	# close enough to crowd the posse he should be VERY LOUD.
	if position.y < ON_SCREEN_Y:
		_switch_to(State.IDLE)
	elif _cowboy and (_cowboy.position.y - position.y) > STAY_DISTANCE_Y:
		_switch_to(State.FORWARD)
	else:
		_switch_to(State.SHOUT)

func _switch_to(new_state: int) -> void:
	if new_state == _state:
		return
	_state = new_state
	if video == null:
		return
	match new_state:
		State.IDLE: video.stream = STREAM_IDLE
		State.FORWARD: video.stream = STREAM_FORWARD
		State.STRAFE_LEFT:
			video.stream = STREAM_STRAFE
			video.scale.x = absf(video.scale.x) * -1.0  # flip for L direction
		State.STRAFE_RIGHT:
			video.stream = STREAM_STRAFE
			video.scale.x = absf(video.scale.x)
		State.SHOOT: video.stream = STREAM_SHOOT
		State.HIT: video.stream = STREAM_HIT
		State.CELEBRATE: video.stream = STREAM_CELEBRATE
		State.SHOUT: video.stream = STREAM_SHOUTS
		State.COMPLAIN: video.stream = STREAM_COMPLAINS
	video.play()

func _spawn_dual_bullets() -> void:
	var level := get_parent()
	if not level:
		return
	# Switch to SHOOT animation briefly. Even if HIT is also queued,
	# SHOOT takes precedence because firing is something we initiated;
	# HIT can re-fire on the next take_bullet_hit and override again.
	_switch_to(State.SHOOT)
	_override_timer = SHOOT_OVERLAY_DURATION
	for offset_x in [-LEFT_GUN_X_OFFSET, LEFT_GUN_X_OFFSET]:
		var spawn_pos: Vector2 = position + Vector2(offset_x, BULLET_SPAWN_Y_OFFSET)
		var bullet := OutlawBulletScene.instantiate()
		bullet.position = spawn_pos
		if _cowboy:
			var dir: Vector2 = (_cowboy.position - spawn_pos).normalized()
			bullet.velocity = dir * OutlawBulletScript.SPEED
		level.add_child(bullet)
		var flash := MuzzleFlashScene.instantiate()
		flash.position = Vector2(offset_x, BULLET_SPAWN_Y_OFFSET)
		add_child(flash)

func take_bullet_hit(damage: int = 1) -> bool:
	if _destroyed:
		return false
	# Iter 55: speech bubble — random 1-line shout from the en.json
	# corpus when Pete gets hit. Visible for ~1.5s above his head.
	# Throttled so rapid fire doesn't spawn a stream of overlapping
	# bubbles; only 1 per second max.
	_maybe_spawn_dialog_bubble("when_hit")
	DamagePopup.spawn(get_parent(), global_position, damage)
	hp -= damage
	_refresh_hp_label()
	if hp_bar:
		hp_bar.set_hp(hp)
	_emit_splinter()
	# Trigger HIT overlay. If currently in SHOOT, replace it — getting
	# shot is the more immediate event for the player to feel.
	# Iter 36: 50/50 pick between physical-reaction HIT and verbal
	# COMPLAIN. Player sees varied hit responses instead of always
	# seeing the same flinch.
	_switch_to(State.HIT if randf() < 0.5 else State.COMPLAIN)
	_override_timer = HIT_OVERLAY_DURATION
	if hp <= 0:
		_destroyed = true
		destroyed.emit(position.x)
		_play_destroy_animation()
	return true

func get_cowboy_damage() -> int:
	return COWBOY_DAMAGE

# Iter 55: spawns a floating speech bubble above Pete's head with a
# random line from the named Text corpus. Categories from en.json:
#   "taunts"  — boss intro / mid-fight ambient (not auto-fired here)
#   "when_hit"— player just shot Pete (1/sec throttle in take_bullet_hit)
#   "dying"   — health critical / on destroyed
# Bubble = simple Label with theme override, tweens up + fades.
func _maybe_spawn_dialog_bubble(category: String) -> void:
	var now_ms: int = int(Time.get_ticks_msec())
	if now_ms - _last_bubble_unix_ms < BUBBLE_COOLDOWN_MS:
		return
	_last_bubble_unix_ms = now_ms
	if get_node_or_null("/root/Text") == null:
		return
	var key: String = "boss.slippery_pete_dialog_%s" % category
	var line: String = Text.random(key)
	if line == "" or line == key:
		return  # corpus missing
	var bubble := Label.new()
	bubble.text = line
	bubble.add_theme_color_override("font_color", Color(1, 0.92, 0.55, 1))
	bubble.add_theme_color_override("font_outline_color", Color(0.18, 0.05, 0.05, 1))
	bubble.add_theme_constant_override("outline_size", 10)
	bubble.add_theme_font_size_override("font_size", 44)
	bubble.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bubble.custom_minimum_size = Vector2(680, 0)
	bubble.z_index = 200
	# Anchor above Pete's head (he's huge; offset accordingly).
	bubble.position = Vector2(-340, -1400)
	add_child(bubble)
	# Pop + fade tween
	bubble.scale = Vector2(0.5, 0.5)
	bubble.modulate.a = 0.0
	var pop := create_tween().set_parallel(true)
	pop.tween_property(bubble, "scale", Vector2.ONE, 0.20) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	pop.tween_property(bubble, "modulate:a", 1.0, 0.12)
	pop.tween_property(bubble, "position:y", bubble.position.y - 80.0, 1.5) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await get_tree().create_timer(1.2).timeout
	if not is_instance_valid(bubble):
		return
	var fade := create_tween()
	fade.tween_property(bubble, "modulate:a", 0.0, 0.30)
	await fade.finished
	if is_instance_valid(bubble):
		bubble.queue_free()

func _refresh_hp_label() -> void:
	if hp_label:
		hp_label.text = str(maxi(hp, 0))

func _emit_splinter() -> void:
	if splinters:
		splinters.restart()
		splinters.emitting = true

func _play_destroy_animation() -> void:
	if splinters:
		splinters.amount = 80
		splinters.restart()
	# Iter 33+: play the user-provided death video and let it carry the
	# visual instead of the old scale/rotation/fade tween. Set loop=false
	# so the player stops on the last frame. After DEATH_DURATION, the
	# universal DeathPolish runs (freeze 0.5s, strobe-disappear 0.5s).
	if video:
		video.loop = false
		video.stream = STREAM_DEATH
		video.play()
		await get_tree().create_timer(DEATH_DURATION).timeout
	await DeathPolish.play(self)
	queue_free()
