extends Node2D

# Bull — heavy boss-tier hazard. Charges down the lane faster than other
# obstacles, with massive HP and devastating cowboy damage. Slow enough
# to react to (visible far ahead), but a wall of bullets is needed to
# bring it down with a six-shooter (50 hits at caliber 1; ~17 with a
# caliber-3 rifle from iter 22b's gun upgrade).
#
# Special interaction: math gates have a direction. When a red gate
# (shrinking — values still negative/<1) FLIPS to blue (player shot it
# enough to push values into "growing" territory), every bull on screen
# gets confused: slows down, drifts sideways, then walks off the track
# at a 60° angle. Designed so the gate-flip moment feels powerful — a
# reward for the player committing to a shooting strategy.

signal destroyed(bull_x: float)

const SIZE: Vector2 = Vector2(280, 180)

# 50 HP at caliber 1 = 50 trigger pulls. Boss-tier, but a caliber-3
# rifle from iter 22b knocks that down to ~17 hits — genuinely
# defeatable once the player has upgraded.
const MAX_HP: int = 50

# 320 px/sec — noticeably faster than the 220 of other obstacles.
# Gives the bull a "charging" feel; the player has less time to react.
const CHARGING_SPEED: float = 320.0

# 80 px/sec while confused (much slower than CHARGING_SPEED). The bull
# is dazed and easy to avoid.
const CONFUSED_SPEED: float = 80.0

# Devastating contact damage. Barricades hit for 10, this is 2x.
const COWBOY_DAMAGE_CHARGING: int = 20

# Confused bulls still hurt if they brush the posse, but much less.
const COWBOY_DAMAGE_CONFUSED: int = 5

# How long the bull stays in the slow "drifting" sub-phase before
# committing to a 60° escape vector toward the nearest screen edge.
const CONFUSED_DURATION: float = 1.5

# Screen geometry for "nearest edge" choice — the playfield is 1080
# wide, so 540 is dead center.
const SCREEN_CENTER_X: float = 540.0

# 60° escape angle. sin(60°) ≈ 0.866 horizontal, cos(60°) ≈ 0.5 vertical.
# Magnitude tuned so the bull leaves screen at a brisk pace.
const ESCAPE_SPEED: float = 280.0

const STATE_CHARGING: int = 0
const STATE_CONFUSED: int = 1

var hp: int
var _state: int = STATE_CHARGING
var _confused_timer: float = 0.0
# Active velocity vector while CONFUSED. Set in confuse() (drift phase)
# and overwritten when the drift timer expires (escape phase).
var _drift_velocity: Vector2 = Vector2.ZERO
# Set true the first time hp reaches 0. Used so the destroy animation
# isn't re-triggered by stray bullets in the brief window between the
# fatal shot and the eventual queue_free at the end of the tween.
var _destroyed: bool = false

@onready var hp_label: Label = $HpLabel
@onready var hp_bar: Control = $HpBar
@onready var splinters: CPUParticles2D = $Splinters

func _ready() -> void:
	hp = MAX_HP
	_refresh_hp_label()
	if hp_bar:
		hp_bar.init(MAX_HP)
	add_to_group("bulls")

func _process(delta: float) -> void:
	if _state == STATE_CHARGING:
		position.y += CHARGING_SPEED * delta
		# Despawn if scrolled past the bottom.
		if position.y > 2200.0:
			queue_free()
	else:  # STATE_CONFUSED
		position += _drift_velocity * delta
		_confused_timer -= delta
		if _confused_timer <= 0.0:
			# Drift phase finished — commit to 60° escape vector toward
			# the nearest screen edge. Recompute side at THIS moment so
			# any drift during the confused phase is accounted for.
			_commit_escape_vector()
		# Despawn when fully off either side or below the screen.
		if position.x < -200.0 or position.x > 1280.0 or position.y > 2200.0:
			queue_free()

# Trigger the confusion state. Picks an immediate sideways drift based
# on which half of the screen the bull is on, slows forward motion.
# Idempotent: a second confuse() while already confused just resets the
# timer (gates flip independently — multiple gates flipping in sequence
# can keep the bull dazed for longer).
func confuse() -> void:
	_state = STATE_CONFUSED
	_confused_timer = CONFUSED_DURATION
	var drift_sign: float = -1.0 if position.x < SCREEN_CENTER_X else 1.0
	# During drift: slow forward + small sideways drift (40 px/sec).
	_drift_velocity = Vector2(drift_sign * 40.0, CONFUSED_SPEED)

# After CONFUSED_DURATION expires, switch to a steeper 60° escape
# heading toward the nearest screen edge. Picks side again based on
# current X (might differ from confuse() time if drift was significant).
func _commit_escape_vector() -> void:
	var dir_sign: float = -1.0 if position.x < SCREEN_CENTER_X else 1.0
	# 60° from horizontal (down-and-out). sin(60°) ≈ 0.866 horizontal.
	_drift_velocity = Vector2(dir_sign * ESCAPE_SPEED * 0.866, ESCAPE_SPEED * 0.5)
	# Stop timer ticking further by parking it at a large negative.
	_confused_timer = -999.0

# Called from level.gd's collision pass. `damage` honors gun caliber.
# Returns true unconditionally (until destroyed) — the bullet is always
# consumed by the bull's bulk, even when it doesn't kill (matches
# barrel/chicken_coop semantics established in iter 21).
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

# Damage the bull deals to the posse on contact. Charging is full-bore
# devastating; a dazed bull still hurts but is survivable.
func get_cowboy_damage() -> int:
	if _state == STATE_CONFUSED:
		return COWBOY_DAMAGE_CONFUSED
	return COWBOY_DAMAGE_CHARGING

func _refresh_hp_label() -> void:
	if hp_label:
		hp_label.text = str(maxi(hp, 0))

func _emit_splinter() -> void:
	if splinters:
		splinters.restart()
		splinters.emitting = true

func _play_destroy_animation() -> void:
	if splinters:
		splinters.amount = 60
		splinters.restart()
	var tween := create_tween().set_parallel(true)
	tween.tween_property(self, "modulate:a", 0.0, 0.4)
	tween.tween_property(self, "scale", Vector2(1.3, 1.3), 0.4) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await tween.finished
	queue_free()
