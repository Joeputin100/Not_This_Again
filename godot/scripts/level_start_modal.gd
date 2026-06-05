class_name LevelStartModal
extends Control

# Soda-Crush-style pre-level popup: a tinted header pill with the LEVEL TITLE
# (Rye font), the level GOAL beneath, a reserved (empty) booster band with a
# faint "Boosters coming soon" placeholder, and a chunky green PLAY! button.
# An X in the top-right backs out to the map. The panel bounces in (scale
# 0.2 -> 1, TRANS_BACK), exactly like the win modal. Emits signals; the map
# owns the actual scene transition.

signal play_pressed
signal close_pressed

@onready var _panel: Control = $Panel
@onready var _header_pill: TextureRect = $Panel/HeaderPill
@onready var _header_label: Label = $Panel/HeaderPill/HeaderLabel
@onready var _goal_label: Label = $Panel/GoalLabel

# title: e.g. "MINE SHAFT MAYHEM"; goal_text: e.g.
# "Clear 60 outlaws, then defeat The Candy Rustler!"
func show_level(title: String, goal_text: String) -> void:
	_header_label.text = title
	_goal_label.text = goal_text
	visible = true
	if get_node_or_null("/root/AudioBus") and AudioBus.has_method("play_tap"):
		AudioBus.play_tap()
	_bounce_in()

func _bounce_in() -> void:
	_panel.scale = Vector2(0.2, 0.2)
	_panel.pivot_offset = _panel.size * 0.5
	var t := _panel.create_tween()
	t.tween_property(_panel, "scale", Vector2.ONE, 0.6) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _on_play() -> void: emit_signal("play_pressed")
func _on_close() -> void: emit_signal("close_pressed")
