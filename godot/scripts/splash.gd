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
	if skip:
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
