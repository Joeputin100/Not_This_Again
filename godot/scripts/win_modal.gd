class_name WinModal
extends Control

# Bounce-in win panel: star rating reveal + bounty count-up + hearts, with
# CONTINUE / REPLAY / MAP buttons. Emits signals; the level owns transitions.

signal continue_pressed
signal replay_pressed
signal map_pressed

@onready var _panel: Control = $Panel
@onready var _stars: StarRating = $Panel/StarRating
@onready var _score: Label = $Panel/Score
@onready var _next: Label = $Panel/NextLabel
@onready var _hearts: HeartCookieRow = $Panel/HeartCookieRow

# difficulty: LevelDef.difficulty; run_bounty: this level's bounty; stars: 1..3;
# next_needed: bounty for the next star (0 = already maxed); hearts/max: lives.
func show_win(difficulty: int, run_bounty: int, stars: int, next_needed: int,
		hearts: int, hearts_max: int) -> void:
	visible = true
	_hearts.set_hearts(hearts, hearts_max)
	_next.text = "" if next_needed <= 0 else "%d more for the next star" % next_needed
	_stars.set_rating(difficulty, stars, true)
	_bounce_in()
	_count_up(run_bounty)

func _bounce_in() -> void:
	_panel.scale = Vector2(0.2, 0.2)
	_panel.pivot_offset = _panel.size * 0.5
	var t := _panel.create_tween()
	t.tween_property(_panel, "scale", Vector2.ONE, 0.6) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _count_up(target: int) -> void:
	_score.text = "0"
	var t := create_tween()
	t.tween_method(func(v): _score.text = "%d" % int(v), 0.0, float(target), 1.0)

func _on_continue() -> void: emit_signal("continue_pressed")
func _on_replay() -> void: emit_signal("replay_pressed")
func _on_map() -> void: emit_signal("map_pressed")
