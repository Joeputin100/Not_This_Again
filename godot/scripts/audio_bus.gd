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

var _tap_player: AudioStreamPlayer
var _gate_pass_player: AudioStreamPlayer

func _ready() -> void:
	_tap_player = _make_player(TAP_SOUND)
	_gate_pass_player = _make_player(GATE_PASS_SOUND)

func _make_player(stream: AudioStream) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.bus = "Master"
	add_child(p)
	return p

func play_tap() -> void:
	# `play()` restarts from start even if already playing — desired
	# for rapid taps so the sound feels responsive.
	_tap_player.play()

func play_gate_pass() -> void:
	_gate_pass_player.play()
