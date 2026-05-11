extends Node2D

# Main menu. Phase 1 introduces:
#   - A PLAY button with Candy-Crush-style tap-pop animation
#   - Candy-Crush-style idle fidgets: when the user hasn't touched the
#     screen for IDLE_THRESHOLD seconds, the PLAY button pulses, the
#     title sways like a saloon sign in a breeze, and the subtitle
#     drifts vertically. Stops the moment any input arrives.
#
# Tone (per design.md "Tone bible"): the narrator/UI voice is Murderbot
# Diaries — dry, deadpan, mildly annoyed at having to explain anything.

@onready var play_button: Button = $UI/PlayButton
@onready var title_label: Label = $UI/Title
@onready var subtitle_label: Label = $UI/Subtitle

# Captured after initial layout so idle_ended can restore exact positions.
var _subtitle_base_y: float = 0.0

# Track idle-fidget tweens so we can kill them on input or scene exit.
var _button_idle_tween: Tween
var _title_idle_tween: Tween
var _subtitle_idle_tween: Tween

func _ready() -> void:
	play_button.pressed.connect(_on_play_pressed)
	IdleNudge.idle_started.connect(_on_idle_started)
	IdleNudge.idle_ended.connect(_on_idle_ended)
	# Defer pivot capture so Godot's layout pass has run and sizes are real.
	call_deferred("_finalize_setup")

func _finalize_setup() -> void:
	play_button.pivot_offset = play_button.size / 2.0
	title_label.pivot_offset = title_label.size / 2.0
	subtitle_label.pivot_offset = subtitle_label.size / 2.0
	_subtitle_base_y = subtitle_label.position.y

func _exit_tree() -> void:
	_kill_idle_tweens()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST or what == NOTIFICATION_WM_CLOSE_REQUEST:
		get_tree().quit()

func _on_play_pressed() -> void:
	# Candy-Crush press feedback: squish, bounce back, then scene change.
	play_button.disabled = true
	_kill_idle_tweens()  # don't let fidget fight the press animation
	var tween := create_tween()
	tween.tween_property(play_button, "scale", Vector2(0.92, 0.92), 0.06)
	tween.tween_property(play_button, "scale", Vector2(1.0, 1.0), 0.18) \
		.set_trans(Tween.TRANS_BACK) \
		.set_ease(Tween.EASE_OUT)
	await tween.finished
	get_tree().change_scene_to_file("res://scenes/level.tscn")

# ---------- Idle fidgets ----------

func _on_idle_started() -> void:
	_kill_idle_tweens()
	# PLAY button: slow scale pulse. Eye-catching but not seizure-inducing.
	_button_idle_tween = create_tween().set_loops()
	_button_idle_tween.tween_property(play_button, "scale", Vector2(1.06, 1.06), 0.55) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_button_idle_tween.tween_property(play_button, "scale", Vector2(1.0, 1.0), 0.55) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	# Title: rotation sway, like a saloon sign in a breeze.
	# tween_interval staggers start so elements don't fidget in lockstep.
	_title_idle_tween = create_tween().set_loops()
	_title_idle_tween.tween_interval(0.25)
	_title_idle_tween.tween_property(title_label, "rotation_degrees", 1.5, 1.4) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_title_idle_tween.tween_property(title_label, "rotation_degrees", -1.5, 1.4) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	# Subtitle: subtle vertical drift, like dust catching the wind.
	_subtitle_idle_tween = create_tween().set_loops()
	_subtitle_idle_tween.tween_interval(0.4)
	_subtitle_idle_tween.tween_property(subtitle_label, "position:y", _subtitle_base_y + 6.0, 1.7) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_subtitle_idle_tween.tween_property(subtitle_label, "position:y", _subtitle_base_y - 6.0, 1.7) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func _on_idle_ended() -> void:
	_kill_idle_tweens()
	# Snap everything back to rest in parallel — quick but not jarring.
	var t := create_tween().set_parallel(true)
	t.tween_property(play_button, "scale", Vector2.ONE, 0.18)
	t.tween_property(title_label, "rotation_degrees", 0.0, 0.18)
	t.tween_property(subtitle_label, "position:y", _subtitle_base_y, 0.18)

func _kill_idle_tweens() -> void:
	if _button_idle_tween:
		_button_idle_tween.kill()
		_button_idle_tween = null
	if _title_idle_tween:
		_title_idle_tween.kill()
		_title_idle_tween = null
	if _subtitle_idle_tween:
		_subtitle_idle_tween.kill()
		_subtitle_idle_tween = null
