extends Node

# Runtime mic capture for Sing Mode (Level-6 duel). Owns a dedicated MUTED
# "MicRecord" audio bus with an AudioEffectCapture, fed by an
# AudioStreamMicrophone player. Polls captured frames each _process into a
# MicPitchTracker (pure, GUT-tested). Inert (no-ops) when input is
# unavailable. Frames are processed and DISCARDED — nothing is stored or
# transmitted (privacy-policy stance).
#
# Requires: project.godot [audio] driver/enable_input=true and the Android
# RECORD_AUDIO permission (export_presets.cfg + runtime OS.request_permission;
# the level handles the permission flow before calling start()).

const MicPitchTrackerScript = preload("res://scripts/mic_pitch_tracker.gd")

var tracker = null

var _player: AudioStreamPlayer = null
var _capture: AudioEffectCapture = null
var _bus_idx: int = -1
var _active: bool = false

func start() -> bool:
	if _active:
		return true
	if _bus_idx < 0:
		_bus_idx = AudioServer.bus_count
		AudioServer.add_bus(_bus_idx)
		AudioServer.set_bus_name(_bus_idx, "MicRecord")
		AudioServer.set_bus_mute(_bus_idx, true)   # never echo the mic to speakers
		_capture = AudioEffectCapture.new()
		AudioServer.add_bus_effect(_bus_idx, _capture)
	tracker = MicPitchTrackerScript.new(AudioServer.get_mix_rate())
	if _player == null:
		_player = AudioStreamPlayer.new()
		_player.stream = AudioStreamMicrophone.new()
		_player.bus = "MicRecord"
		add_child(_player)
	_player.play()
	_capture.clear_buffer()
	_active = true
	return true

func stop() -> void:
	if _player != null and _player.playing:
		_player.stop()
	_active = false

func curve() -> Array:
	return tracker.curve() if tracker != null else []

func voiced() -> int:
	return tracker.voiced_frames if tracker != null else 0

func _process(_delta: float) -> void:
	if not _active or _capture == null:
		return
	var avail: int = _capture.get_frames_available()
	if avail <= 0:
		return
	var frames: PackedVector2Array = _capture.get_buffer(avail)
	var mono := PackedFloat32Array()
	mono.resize(frames.size())
	for i in range(frames.size()):
		mono[i] = (frames[i].x + frames[i].y) * 0.5
	tracker.push_samples(mono)
