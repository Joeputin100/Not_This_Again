extends Control

# iter362: opening splash cinematic. Plays the baked Veo intro — the full ~48s
# "Peppermint Showdown" on first launch, the 6s rear-up clip on every launch
# after — then match-cuts to the 2D title (main_menu). Tap/click/key skips.
#
# Music: the cinematic OGV carries only Veo's SFX (hoof-crunch, whinny, wind);
# Peppermint Rodeo is owned by the MusicPlayer autoload and cued at the Shot-7
# mark (t=34s) so it flows seamlessly into the title with no restart. On a skip
# (or the short intro) the track simply starts now.

const FULL_INTRO: String = "res://assets/videos/splash/intro_full.ogv"
const SHORT_INTRO: String = "res://assets/videos/splash/intro_short.ogv"
const TITLE_SCENE: String = "res://scenes/main_menu.tscn"
const MUSIC_CUE_S: float = 34.0   # Peppermint Rodeo enters at Shot 7 of the full intro
const CFG_PATH: String = "user://splash.cfg"

var _player: VideoStreamPlayer = null
var _full: bool = false
var _music_cued: bool = false
var _done: bool = false
# iter363: the first-time (full) cinematic needs 3 taps to skip (so a stray tap
# doesn't rob a first-time player of the intro); a candy chip appears after tap 1
# and flashes on each tap. The 6s repeat intro keeps single-tap skip.
var _tap_count: int = 0
var _skip_chip: Panel = null
const TAPS_TO_SKIP: int = 3

func _ready() -> void:
	_full = not _full_intro_seen()
	_mark_full_intro_seen()
	var path: String = FULL_INTRO if _full else SHORT_INTRO
	if not ResourceLoader.exists(path):
		# Asset missing (e.g. not yet imported) — don't strand the player on a
		# black screen; go straight to the title.
		_go_to_title()
		return
	_player = VideoStreamPlayer.new()
	_player.set_anchors_preset(Control.PRESET_FULL_RECT)
	_player.expand = true
	_player.stream = load(path)
	_player.finished.connect(_go_to_title)
	add_child(_player)
	_player.play()
	if not _full:
		_start_music()  # repeat intro is short — start the track immediately
	else:
		_skip_chip = _build_skip_chip()
		add_child(_skip_chip)

func _process(_delta: float) -> void:
	# Cue Peppermint Rodeo at the Shot-7 mark of the full intro.
	if _full and not _music_cued and _player != null and _player.is_playing() \
			and _player.stream_position >= MUSIC_CUE_S:
		_music_cued = true
		_start_music()

func _unhandled_input(event: InputEvent) -> void:
	var skip: bool = (event is InputEventScreenTouch and event.pressed) \
		or (event is InputEventMouseButton and event.pressed) \
		or (event is InputEventKey and event.pressed)
	if not skip:
		return
	# Short repeat intro: one tap skips. Full first-time intro: needs 3 taps,
	# with the candy chip revealing on tap 1 and flashing on each tap.
	if not _full:
		_go_to_title()
		return
	_tap_count += 1
	_flash_chip()
	if _tap_count >= TAPS_TO_SKIP:
		_go_to_title()

func _start_music() -> void:
	if get_node_or_null("/root/MusicPlayer") != null:
		MusicPlayer.play_splash()

func _go_to_title() -> void:
	if _done:
		return
	_done = true
	_start_music()  # ensure the track is playing if the player skipped before the cue
	get_tree().change_scene_to_file(TITLE_SCENE)

# ---- first-launch flag (persisted in user://) -------------------------------
func _full_intro_seen() -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(CFG_PATH) == OK:
		return bool(cfg.get_value("splash", "full_intro_seen", false))
	return false

func _mark_full_intro_seen() -> void:
	var cfg := ConfigFile.new()
	cfg.load(CFG_PATH)  # ignore error; fresh file if absent
	cfg.set_value("splash", "full_intro_seen", true)
	cfg.save(CFG_PATH)

# ---- triple-tap skip chip (full intro only) ---------------------------------
# A candy-pink rounded chip near the bottom reading "tap 3× to skip". Hidden
# until the first tap; _flash_chip reveals + pulses it on every tap.
func _build_skip_chip() -> Panel:
	var chip := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1.0, 0.45, 0.62, 0.95)      # candy pink
	sb.border_color = Color(1.0, 0.95, 0.85, 1.0)   # cream rim
	sb.set_border_width_all(5)
	sb.set_corner_radius_all(44)
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = 8
	chip.add_theme_stylebox_override("panel", sb)
	chip.anchor_left = 0.5
	chip.anchor_right = 0.5
	chip.anchor_top = 1.0
	chip.anchor_bottom = 1.0
	chip.offset_left = -240.0
	chip.offset_right = 240.0
	chip.offset_top = -210.0
	chip.offset_bottom = -120.0
	chip.pivot_offset = Vector2(240, 45)
	chip.modulate = Color(1, 1, 1, 0)               # hidden until first tap
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var lbl := Label.new()
	lbl.text = "tap 3× to skip"
	lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 42)
	lbl.add_theme_color_override("font_color", Color(0.35, 0.12, 0.10))
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(lbl)
	return chip

func _flash_chip() -> void:
	if _skip_chip == null:
		return
	# Pop the scale + a bright flash; settles fully visible.
	var pop := create_tween()
	pop.tween_property(_skip_chip, "scale", Vector2(1.18, 1.18), 0.08) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	pop.tween_property(_skip_chip, "scale", Vector2.ONE, 0.16) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var flash := create_tween()
	flash.tween_property(_skip_chip, "modulate", Color(1.5, 1.5, 1.5, 1.0), 0.06)
	flash.tween_property(_skip_chip, "modulate", Color(1, 1, 1, 1), 0.20)
