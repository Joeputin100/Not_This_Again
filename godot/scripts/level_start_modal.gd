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
@onready var _subtitle_label: Label = $Panel/SubtitleLabel
@onready var _goal_label: Label = $Panel/GoalViewer/GoalLabel
@onready var _play_button: Button = $Panel/PlayButton

# level_num: e.g. 2; title: e.g. "MINE SHAFT MAYHEM"; goal_text: e.g.
# "Clear 60 outlaws, then defeat The Candy Rustler!". The pill shows
# "LEVEL <n>" big (Candy-Crush-Soda style), the level name as a subtitle
# beneath it, and the goal inside the tinted goal viewer.
func show_level(level_num: int, title: String, goal_text: String) -> void:
	_header_label.text = "LEVEL %d" % level_num
	_subtitle_label.text = title
	_goal_label.text = goal_text
	visible = true
	if get_node_or_null("/root/AudioBus") and AudioBus.has_method("play_tap"):
		AudioBus.play_tap()
	_bounce_in()
	_start_play_breathing()

# Idle breathing pulse on the PLAY button (1.0 <-> 1.05, ~1.2s, TRANS_SINE,
# looping) so it invites a tap. Scales from its centre.
func _start_play_breathing() -> void:
	_play_button.pivot_offset = _play_button.size * 0.5
	var t := _play_button.create_tween().set_loops()
	t.tween_property(_play_button, "scale", Vector2(1.05, 1.05), 1.2) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_property(_play_button, "scale", Vector2.ONE, 1.2) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func _bounce_in() -> void:
	_panel.scale = Vector2(0.2, 0.2)
	_panel.pivot_offset = _panel.size * 0.5
	var t := _panel.create_tween()
	t.tween_property(_panel, "scale", Vector2.ONE, 0.6) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _on_play() -> void: emit_signal("play_pressed")
func _on_close() -> void: emit_signal("close_pressed")
