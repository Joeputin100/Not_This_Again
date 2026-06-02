extends Node

# iter361: persistent background-music player. Lives as an AUTOLOAD so the track
# survives scene changes — Peppermint Rodeo starts on the splash (main_menu) and
# keeps playing into the level selector WITHOUT restarting (per the user's ask).
# Per-level tracks swap in when a gameplay scene starts.
#
# Why an autoload: a scene-local AudioStreamPlayer is freed by
# change_scene_to_file(), which would cut + restart the music on every hop. An
# autoload node persists, so the splash -> selector hand-off is seamless.

# Music plays at ~50% amplitude ("50% sound effect volume") so it sits under the
# SFX. Tunable in one place; -6 dB ≈ half linear volume.
const MUSIC_LINEAR: float = 0.5

# Peppermint Rodeo — splash screen + level selector (shared, continuous).
const SPLASH_TRACK: AudioStream = preload("res://assets/audio/music/peppermint_rodeo.ogg")

# Per-level gameplay music, keyed by GameState.current_level. Any level without
# its own entry falls back to the splash track.
const LEVEL_TRACKS: Dictionary = {
	1: preload("res://assets/audio/music/running_from_the_clock.ogg"),
	2: preload("res://assets/audio/music/high_noon_at_the_glass_saloon.ogg"),
}

var _player: AudioStreamPlayer = null

func _ready() -> void:
	_player = AudioStreamPlayer.new()
	_player.name = "MusicStream"
	_player.bus = "Master"
	_player.volume_db = linear_to_db(MUSIC_LINEAR)
	add_child(_player)

# Play `stream` (looping by default). If this exact stream is ALREADY the one
# playing, do nothing — so re-entering a scene that wants the same track never
# restarts it (the splash -> selector continuity, and seamless level retries).
func play(stream: AudioStream, loop: bool = true) -> void:
	if stream == null or _player == null:
		return
	if _player.stream == stream and _player.playing:
		return
	if "loop" in stream:
		stream.loop = loop
	_player.stream = stream
	_player.play()

# Peppermint Rodeo for the splash + level selector.
func play_splash() -> void:
	play(SPLASH_TRACK)

# The track for `level` (GameState.current_level), splash track as fallback.
func play_level(level: int) -> void:
	play(LEVEL_TRACKS.get(level, SPLASH_TRACK))

func stop() -> void:
	if _player != null:
		_player.stop()

# Runtime volume override (0..1 linear), kept for a future audio-settings screen.
func set_music_linear(linear: float) -> void:
	if _player != null:
		_player.volume_db = linear_to_db(clampf(linear, 0.0, 1.0))
