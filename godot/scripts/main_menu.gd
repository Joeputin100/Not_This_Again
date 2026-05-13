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

const BuildInfo = preload("res://scripts/build_info.gd")

@onready var play_button: Button = $UI/PlayButton
@onready var title_label: Label = $UI/Title
@onready var subtitle_label: Label = $UI/Subtitle
@onready var build_id_label: Label = $UI/BuildId
@onready var copy_button: Button = $UI/CopyButton
@onready var copy_toast: Label = $UI/CopyToast
# Iter 40c: hearts row — 5 slots, each ♥ when full, faded for spent.
# Subscribes to GameState.hearts_changed in _ready and re-renders.
@onready var hearts_label: Label = $UI/Hearts
# Iter 45: DEBUG button — visible only in debug builds. _ready toggles
# its visibility from OS.has_feature("debug").
@onready var debug_button: Button = $UI/DebugButton

# Captured after initial layout so idle_ended can restore exact positions.
var _subtitle_base_y: float = 0.0

# Debug-only triple-tap on BuildId triggers OS.crash() so Crashlytics
# round-trip can be verified end-to-end. _crash_tap_count resets if more
# than CRASH_TAP_WINDOW seconds pass between taps. Release builds skip
# the input handler wiring entirely.
const CRASH_TAP_WINDOW: float = 1.5
var _crash_tap_count: int = 0
var _crash_last_tap_time: float = 0.0

# Track idle-fidget tweens so we can kill them on input or scene exit.
var _button_idle_tween: Tween
var _title_idle_tween: Tween
var _subtitle_idle_tween: Tween

func _ready() -> void:
	# Belt-and-suspenders runtime call; project.godot also sets this to false.
	get_tree().set_quit_on_go_back(false)
	# Third route: hook the Window's signal directly in addition to the
	# _notification path. From the main menu we still quit on back, but
	# logging from both paths reveals which one actually fires on the
	# user's Android 16.
	get_window().go_back_requested.connect(_on_back_requested_signal)
	DebugLog.add("main_menu _ready (build=%s) quit_on_go_back=%s" % [
		BuildInfo.SHA, str(get_tree().is_quit_on_go_back()),
	])
	play_button.pressed.connect(_on_play_pressed)
	IdleNudge.idle_started.connect(_on_idle_started)
	IdleNudge.idle_ended.connect(_on_idle_ended)
	copy_button.pressed.connect(_on_copy_pressed)
	# Iter 40c: hearts subscription. Re-render on every change so a fail
	# in a level (which calls GameState.spend_heart()) updates the menu
	# next time it's shown. Also re-render now so the row reflects the
	# current state on entry (e.g. after losing a level + returning).
	GameState.hearts_changed.connect(_refresh_hearts)
	# Iter 55: lazy heart regen — check on menu entry. If enough time
	# has passed since the last spend, hearts will tick up.
	GameState.apply_regen()
	_refresh_hearts(GameState.hearts)
	# Iter 45/61: DEBUG button. Originally gated on OS.has_feature("debug")
	# but firebelley/godot-export defaults to release-mode even from the
	# "debug" workflow, so the feature flag is false in sideload builds.
	# Until v1 ships to Play Store, always show — the user IS the only
	# sideloader and needs the debug tools to test rushes/weapons/heroes.
	if debug_button:
		debug_button.visible = true
		debug_button.pressed.connect(_on_debug_pressed)
	# Build identifier in the bottom-right corner — proves which build is
	# actually installed when sideloading repeatedly.
	# Iter 61: omit iter portion when CI didn't successfully stamp it
	# (BuildInfo.ITER == "?" placeholder). SHA + date alone is enough to
	# identify the build for sideload bug reports.
	if BuildInfo.ITER == "?" or BuildInfo.ITER == "":
		build_id_label.text = "%s  ·  %s" % [BuildInfo.SHA, BuildInfo.SHORT_DATE]
	else:
		build_id_label.text = "%s  %s  iter %s" % [BuildInfo.SHA, BuildInfo.SHORT_DATE, BuildInfo.ITER]
	# Debug-build-only triple-tap-to-crash gesture on the BuildId label,
	# for verifying Crashlytics integration on first sideload. Release
	# builds never wire this up — OS.crash() is a no-op there anyway,
	# but skipping the connect saves us from any input-flooding risk.
	# Iter 31 fix: the .tscn says mouse_filter=0 (STOP, receive input)
	# but Label's constructor in Godot 4 overrides to MOUSE_FILTER_IGNORE
	# (2) after the scene loads. User's iter 30 log confirmed mouse_filter
	# read 2 at _ready time → input never reached our handler. Force-set
	# at runtime so the .tscn value sticks.
	build_id_label.mouse_filter = Control.MOUSE_FILTER_STOP
	build_id_label.gui_input.connect(_on_build_id_tap)
	DebugLog.add("crash-gesture: handler connected; has_feature(debug)=%s mouse_filter=%d" % [
		str(OS.has_feature("debug")),
		build_id_label.mouse_filter,
	])
	# Defer pivot capture so Godot's layout pass has run and sizes are real.
	call_deferred("_finalize_setup")

func _on_debug_pressed() -> void:
	AudioBus.play_tap()
	DebugLog.add("DEBUG button pressed → loading debug_menu")
	get_tree().change_scene_to_file("res://scenes/debug_menu.tscn")

func _on_copy_pressed() -> void:
	AudioBus.play_tap()
	# Bundle build identifier + recent debug log into the clipboard so a
	# bug report includes both "what's running" and "what happened so far."
	var text := "%s\n\n--- recent log (%d lines) ---\n%s" % [
		build_id_label.text,
		DebugLog.line_count(),
		DebugLog.get_text(),
	]
	DisplayServer.clipboard_set(text)
	DebugLog.add("clipboard: copied %d chars" % text.length())
	# Visual feedback — fade the COPIED toast in then out.
	copy_toast.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(copy_toast, "modulate:a", 1.0, 0.15)
	tween.tween_interval(0.9)
	tween.tween_property(copy_toast, "modulate:a", 0.0, 0.35)

func _finalize_setup() -> void:
	play_button.pivot_offset = play_button.size / 2.0
	title_label.pivot_offset = title_label.size / 2.0
	subtitle_label.pivot_offset = subtitle_label.size / 2.0
	_subtitle_base_y = subtitle_label.position.y

func _exit_tree() -> void:
	_kill_idle_tweens()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		DebugLog.add("main_menu NOTIFICATION_WM_GO_BACK_REQUEST → quit")
		get_tree().quit()
	elif what == NOTIFICATION_WM_CLOSE_REQUEST:
		DebugLog.add("main_menu NOTIFICATION_WM_CLOSE_REQUEST → quit")
		get_tree().quit()

func _on_back_requested_signal() -> void:
	DebugLog.add("main_menu go_back_requested SIGNAL → quit")
	get_tree().quit()

# Iter 40c: render the hearts row. Two characters: ♥ for remaining (kept
# bright red), · for spent (dim). Player can read "I have 3 left" at a
# glance without doing arithmetic. Also locks/unlocks PLAY based on
# whether there's a heart to spend on a fresh run.
func _refresh_hearts(current_hearts: int) -> void:
	if hearts_label == null:
		return
	var max_h: int = GameState.MAX_HEARTS
	var parts: PackedStringArray = []
	for i in range(max_h):
		parts.append("♥" if i < current_hearts else "·")
	hearts_label.text = " ".join(parts)
	# Lock PLAY when out of hearts. Standard Candy Crush behavior: dim
	# the primary CTA + change the label to make the gate obvious. (Heart
	# regen is deferred to a separate iter; cold app launches reset to
	# MAX_HEARTS, which is the workaround for v1 sideload testing.)
	if play_button:
		play_button.disabled = current_hearts <= 0
		play_button.text = "OUT OF POSSE" if current_hearts <= 0 else "PLAY"

func _on_play_pressed() -> void:
	# Candy-Crush press feedback: tap SFX + squish + bounce back + scene change.
	# Iter 40: PLAY now routes to level_select (Candy Crush world map) instead
	# of jumping straight into level 1. Even though level 1 is the only
	# playable node so far, the world map sets up the meta-progression read
	# for the player ("there are more levels ahead, this is one of many").
	DebugLog.add("PLAY pressed → loading level_select")
	AudioBus.play_tap()
	play_button.disabled = true
	_kill_idle_tweens()  # don't let fidget fight the press animation
	var tween := create_tween()
	tween.tween_property(play_button, "scale", Vector2(0.92, 0.92), 0.06)
	tween.tween_property(play_button, "scale", Vector2(1.0, 1.0), 0.18) \
		.set_trans(Tween.TRANS_BACK) \
		.set_ease(Tween.EASE_OUT)
	await tween.finished
	get_tree().change_scene_to_file("res://scenes/level_select.tscn")

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

# Triple-tap on BuildId in a debug build = deliberate SIGSEGV via
# OS.crash, used to verify Firebase Crashlytics is wired up correctly.
# Crashlytics NDK installs signal handlers at app start (via Firebase's
# auto-init ContentProvider), captures the crash, queues a report. The
# report uploads the NEXT time the app launches.
func _on_build_id_tap(event: InputEvent) -> void:
	# Iter 26 diagnostics: log EVERY gui_input event we receive so we
	# can see in the COPY-button log whether the handler is firing at
	# all. If we get nothing, the issue is upstream (mouse_filter, focus,
	# Z-order). If we get TOUCH/MOUSE_MOTION but no presses, we're
	# filtering too aggressively.
	DebugLog.add("crash-gesture event: %s pressed=%s" % [
		event.get_class(),
		str(event.is_pressed()) if event.has_method("is_pressed") else "n/a",
	])
	var is_press: bool = false
	if event is InputEventScreenTouch:
		is_press = (event as InputEventScreenTouch).pressed
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		is_press = mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed
	if not is_press:
		return

	var now: float = Time.get_unix_time_from_system()
	if now - _crash_last_tap_time > CRASH_TAP_WINDOW:
		_crash_tap_count = 1
	else:
		_crash_tap_count += 1
	_crash_last_tap_time = now

	DebugLog.add("crash-gesture tap %d/3" % _crash_tap_count)
	if _crash_tap_count >= 3:
		DebugLog.add("crash-gesture: triggering OS.crash for Crashlytics test")
		OS.crash("Not_This_Again debug crash-gesture (Crashlytics test)")

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
