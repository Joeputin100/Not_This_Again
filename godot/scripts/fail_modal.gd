class_name FailModal
extends Control

# Bounce-in fail panel. RETRY costs 1 heart on press (chomp the rightmost
# cookie, then emit). If hearts == 0, RETRY is disabled with a regen note.

signal retry_pressed
signal map_pressed

@onready var _panel: Control = $Panel
@onready var _score: Label = $Panel/Score
@onready var _hearts: HeartCookieRow = $Panel/HeartCookieRow
@onready var _retry: Button = $Panel/RetryButton
@onready var _cost: Label = $Panel/CostLabel

func show_fail(run_bounty: int, hearts: int, hearts_max: int, regen_text: String) -> void:
	visible = true
	_score.text = "%d" % run_bounty
	_hearts.set_hearts(hearts, hearts_max)
	if hearts <= 0:
		_retry.disabled = true
		_cost.text = "Out of lives — %s" % regen_text
	else:
		_retry.disabled = false
		_cost.text = "costs 1 ♥  ·  %d left" % hearts
	_bounce_in()

func _bounce_in() -> void:
	_panel.scale = Vector2(0.2, 0.2)
	_panel.pivot_offset = _panel.size * 0.5
	_panel.create_tween().tween_property(_panel, "scale", Vector2.ONE, 0.6) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _on_retry() -> void:
	emit_signal("retry_pressed")   # level spends the heart + reloads

func _on_map() -> void:
	emit_signal("map_pressed")
