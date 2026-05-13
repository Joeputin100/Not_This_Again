extends Node

# Autoloaded singleton. Centralizes SFX playback so callers say
# `AudioBus.play_tap()` rather than instantiating their own players.
# Pre-creates one AudioStreamPlayer per sound so play() doesn't pay
# instantiation cost on the fingertip-to-sound path.
#
# Per Godot 4 mobile audio guidance + risks.md: short SFX should use
# `AudioStreamPlayer` (not 2D/3D variants), and we tune
# `audio/driver/output_latency` to 15ms in project.godot.

const TAP_SOUND := preload("res://assets/sfx/tap.ogg")
const GATE_PASS_SOUND := preload("res://assets/sfx/gate_pass.ogg")
const GUNFIRE_SOUND := preload("res://assets/sfx/gunfire.wav")

# Multiple gunfire players so rapid posse fire doesn't truncate each
# other's playback. AudioStreamPlayer.play() restarts the current sound
# even if it's mid-playback — bad for a multi-bullet salvo. Round-robin
# through a small pool so consecutive shots stack instead of clipping.
const GUNFIRE_POOL_SIZE: int = 6

var _tap_player: AudioStreamPlayer
var _gate_pass_player: AudioStreamPlayer
var _gunfire_players: Array[AudioStreamPlayer] = []
var _gunfire_index: int = 0

func _ready() -> void:
	_tap_player = _make_player(TAP_SOUND)
	_gate_pass_player = _make_player(GATE_PASS_SOUND)
	for i in GUNFIRE_POOL_SIZE:
		_gunfire_players.append(_make_player(GUNFIRE_SOUND))

func _make_player(stream: AudioStream) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.bus = "Master"
	# +6dB headroom because phone speakers + casual play environments
	# tend to swallow short SFX. Source files are already near peak
	# amplitude; this is a safety margin, not a substitute for content.
	p.volume_db = 6.0
	add_child(p)
	return p

func play_tap() -> void:
	# `play()` restarts from start even if already playing — desired
	# for rapid taps so the sound feels responsive.
	_tap_player.play()

func play_gate_pass() -> void:
	_gate_pass_player.play()

func play_gunfire() -> void:
	# Round-robin through the pool — each posse bullet gets its own
	# AudioStreamPlayer so rapid fire stacks naturally without one
	# shot's playback cutting off the previous one.
	_gunfire_players[_gunfire_index].play()
	_gunfire_index = (_gunfire_index + 1) % GUNFIRE_POOL_SIZE

# Iter 63: stop every gunfire player in the pool. Called from level.gd's
# _show_win / _show_fail so lingering pool samples don't keep playing
# after the firefight ends (user reported continuous gunshot SFX after
# posse stopped firing in iter 62 testing).
func stop_gunfire() -> void:
	for p in _gunfire_players:
		if p and p.playing:
			p.stop()
