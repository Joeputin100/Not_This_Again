extends Node2D

# Prospector — melee-only enemy. Tracks the posse like a vagrant but
# instead of ranged fire he closes to swing range and swings a pickaxe
# every SWING_INTERVAL seconds while in contact. Crowds the posse until
# killed; does NOT pass by.
#
# Iter 31. AI mirrors outlaw.gd's tracking but with no _spawn_bullet,
# no fire timer. Adds:
#   - SWING_INTERVAL: time between consecutive pickaxe hits while in
#     melee range.
#   - SWING_DAMAGE: posse loss per landed swing.
#   - try_swing(): called by level.gd from the melee collision pass.
#     Returns true and resets the swing cooldown if the prospector is
#     off-cooldown; false otherwise.
#   - _play_swing_animation(): brief rotation tween so the player sees
#     the pickaxe lunge on each landed swing.

const MuzzleFlashScene := preload("res://scenes/muzzle_flash.tscn")  # not used directly but kept for parity

signal destroyed(x: float)

const MAX_HP: int = 20
const SCROLL_SPEED: float = 220.0
const STAY_SCROLL_SPEED: float = 30.0
# Prospectors close to true melee range — much closer than outlaws.
# Pickaxe is short-reach, has to actually touch the posse to hit.
const STAY_DISTANCE_Y: float = 180.0
const TRACK_SPEED: float = 1.6
const SIZE: Vector2 = Vector2(140, 220)
# Contact damage if the prospector reaches the cowboy and hits — applied
# per SWING_INTERVAL via try_swing(). 5 per swing × ~1 swing/sec means
# 30 damage over 6 seconds of close contact if the player doesn't kill
# the prospector quickly.
const SWING_DAMAGE: int = 5
const SWING_INTERVAL: float = 0.8
const ON_SCREEN_Y: float = 0.0

var hp: int = MAX_HP
var _destroyed: bool = false
var _swing_cooldown_timer: float = 0.0
var _cowboy: Node2D = null

@onready var hp_label: Label = $HpLabel
@onready var hp_bar: Control = $HpBar
@onready var splinters: CPUParticles2D = $Splinters

func _ready() -> void:
	hp = MAX_HP
	_refresh_hp_label()
	if hp_bar:
		hp_bar.init(MAX_HP)
	add_to_group("prospectors")
	_cowboy = _find_cowboy()

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
	_swing_cooldown_timer = maxf(0.0, _swing_cooldown_timer - delta)
	if _cowboy:
		position.x = lerpf(position.x, _cowboy.position.x, clampf(TRACK_SPEED * delta, 0.0, 1.0))
	var dy: float = (_cowboy.position.y - position.y) if _cowboy else 1000.0
	position.y += (SCROLL_SPEED if dy > STAY_DISTANCE_Y else STAY_SCROLL_SPEED) * delta
	if position.y > 2200.0:
		queue_free()
		return

# Returns true and resets the swing cooldown if off-cooldown; false
# otherwise. Called by level.gd's melee collision pass when this
# prospector overlaps the cowboy or a posse follower.
func try_swing() -> bool:
	if _swing_cooldown_timer > 0.0:
		return false
	_swing_cooldown_timer = SWING_INTERVAL
	_play_swing_animation()
	return true

func _play_swing_animation() -> void:
	# Quick rotation tween — pickaxe lunge. The prospector's pickaxe is
	# held to the left in the source art, so the swing reads as
	# counter-clockwise.
	var tween := create_tween()
	tween.tween_property(self, "rotation_degrees", -18.0, 0.08) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "rotation_degrees", 0.0, 0.18) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func take_bullet_hit(damage: int = 1) -> bool:
	if _destroyed:
		return false
	hp -= damage
	_refresh_hp_label()
	if hp_bar:
		hp_bar.set_hp(hp)
	_emit_splinter()
	if hp <= 0:
		_destroyed = true
		destroyed.emit(position.x)
		_play_destroy_animation()
	return true

func get_cowboy_damage() -> int:
	# Used by the generic obstacle-cowboy pass as a fallback; primary
	# damage path is via try_swing() from the dedicated melee collision
	# resolver in level.gd. Returning SWING_DAMAGE keeps the generic
	# pass meaningful in case the melee pass misses an edge case.
	return SWING_DAMAGE

func _refresh_hp_label() -> void:
	if hp_label:
		hp_label.text = str(maxi(hp, 0))

func _emit_splinter() -> void:
	if splinters:
		splinters.restart()
		splinters.emitting = true

func _play_destroy_animation() -> void:
	if splinters:
		splinters.amount = 50
		splinters.restart()
	var tween := create_tween().set_parallel(true)
	tween.tween_property(self, "modulate:a", 0.0, 0.5)
	tween.tween_property(self, "scale", Vector2(1.4, 1.4), 0.5) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# Pickaxe drop — prospector keels over sideways.
	tween.tween_property(self, "rotation_degrees", 60.0, 0.5) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await tween.finished
	queue_free()
