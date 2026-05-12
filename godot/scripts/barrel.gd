extends Node2D

# A wooden barrel barricade — scrolls down toward the cowboy at scroll_speed,
# takes max_hp shots before being destroyed. HP label on top updates per hit.
# Added to "barrels" group so level.gd's collision pass can find it.
#
# Power-up variant: if bonus_type is set in the scene editor (or via
# code), a small "BONUS" letter floats above the barrel and a Bonus
# pickup is spawned at the barrel's position when it's shot to pieces.
# The cowboy auto-equips on collision — no UI prompt. See bonus.gd.

signal destroyed(barrel_x: float)

const BonusScene = preload("res://scenes/bonus.tscn")
const BonusScript = preload("res://scripts/bonus.gd")
const DamagePopup = preload("res://scripts/damage_popup.gd")

@export var max_hp: int = 4
@export var scroll_speed: float = 220.0
# Non-empty means this barrel carries a power-up. The Bonus spawned on
# destruction inherits this string. Recognized values are defined in
# level.gd's _equip_bonus(): "fast_fire", "extra_dude", "rifle".
@export var bonus_type: String = ""

const SIZE: Vector2 = Vector2(140, 140)

var hp: int
var _destroyed: bool = false

@onready var hp_label: Label = $HpLabel
@onready var hp_bar: Control = $HpBar
@onready var sparkles: CPUParticles2D = $Sparkles

func _ready() -> void:
	hp = max_hp
	_refresh_hp_label()
	if hp_bar:
		hp_bar.init(max_hp)
	add_to_group("barrels")
	# If this is a power-up barrel, telegraph it with an indicator label
	# above the barrel body so the player can decide BEFORE shooting
	# whether they want what's inside. Genuine strategic choice — the
	# core design intent for bonuses.
	if bonus_type != "":
		_add_bonus_indicator()

func _process(delta: float) -> void:
	if _destroyed:
		return
	position.y += scroll_speed * delta
	# Despawn if it scrolled past the bottom — safety net so unfought
	# barrels don't accumulate forever.
	if position.y > 2200.0:
		queue_free()

# Called by level.gd's collision pass when a bullet hits this barrel.
# Returns true if the barrel was destroyed by this shot.
func take_damage(amount: int = 1) -> bool:
	if _destroyed:
		return false
	DamagePopup.spawn(get_parent(), global_position, amount)
	hp -= amount
	_refresh_hp_label()
	if hp_bar:
		hp_bar.set_hp(hp)
	# Subtle hit reaction so the player FEELS the impact.
	_hit_flash()
	if hp <= 0:
		_destroyed = true
		destroyed.emit(position.x)
		# Spawn the bonus pickup BEFORE the destroy animation starts so
		# the pickup inherits the live position. The animation tween
		# scales/fades this node — by that point the bonus is already a
		# sibling under the level and continues scrolling independently.
		if bonus_type != "":
			_spawn_bonus_drop()
		_play_destroy_animation()
		return true
	return false

func _refresh_hp_label() -> void:
	if hp_label:
		hp_label.text = str(maxi(hp, 0))

func _hit_flash() -> void:
	# Quick white tint then back to normal — like Subway Surfers / Vampire
	# Survivors hit feedback.
	modulate = Color(1.6, 1.4, 1.2, 1.0)
	var tween := create_tween()
	tween.tween_property(self, "modulate", Color(1, 1, 1, 1), 0.10)

func _play_destroy_animation() -> void:
	if sparkles:
		sparkles.emitting = true
	var tween := create_tween().set_parallel(true)
	tween.tween_property(self, "modulate:a", 0.0, 0.35)
	tween.tween_property(self, "scale", Vector2(1.25, 1.25), 0.35) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await tween.finished
	queue_free()

# Adds a glowing "BONUS / <letter>" indicator floating just above the
# barrel body. The letter is whatever bonus.gd::letter_for() returns for
# this bonus_type, so the visual stays consistent with the dropped icon.
func _add_bonus_indicator() -> void:
	var label := Label.new()
	label.text = "BONUS " + BonusScript.letter_for(bonus_type)
	# Hover above the barrel (body top is at y=-70, leave a 30px gap).
	label.position = Vector2(-90, -150)
	label.size = Vector2(180, 50)
	label.add_theme_font_size_override("font_size", 28)
	label.add_theme_color_override("font_color", Color(1, 0.9, 0.45, 1))
	label.add_theme_color_override("font_outline_color", Color(0.18, 0.1, 0.03, 1))
	label.add_theme_constant_override("outline_size", 6)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)

# Instantiates a Bonus pickup at this barrel's position and parents it
# to the level (the barrel's parent). The bonus inherits scrolling
# behavior from bonus.gd and will despawn off-bottom or be auto-equipped
# on cowboy contact (handled by level.gd's collision pass).
func _spawn_bonus_drop() -> void:
	var level := get_parent()
	if not level:
		return
	var bonus := BonusScene.instantiate()
	bonus.bonus_type = bonus_type
	bonus.position = position
	level.add_child(bonus)
