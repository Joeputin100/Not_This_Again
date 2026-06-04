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

# Iter 139: ElevenLabs voice-overs for FlourishBanner.spawn() — Matilda
# (free-tier "Knowledgable, Professional, upbeat") as a placeholder for
# Bill for Books (8Es4...) which needs paid-tier API. Lazy-loaded so
# we don't pay 21 stream preload costs at boot — each slug warms its
# own AudioStreamPlayer on first play, reuses it after.
var _flourish_players: Dictionary = {}  # slug:String -> AudioStreamPlayer

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

# Iter 139: play a flourish voice clip by slug — matches the .mp3 filename
# without extension or 'flourish_' prefix. Eg slug='sugar_cascade' →
# res://assets/audio/flourishes/flourish_sugar_cascade.mp3. Silently no-ops
# if the file is missing (so a typo in spawn() doesn't crash a level).
func play_flourish(slug: String) -> void:
	# Iter 141: louder per user request (+8 → +12 dB). Bill voice is rich
	# and rolls into the mix at +8 too quietly when gunfire is firing.
	_play_lazy_voice(_flourish_players, slug,
		"res://assets/audio/flourishes/flourish_%s.mp3" % slug, 12.0)

# iter411: generic creature/impact SFX by slug → res://assets/sfx/creatures/<slug>.mp3
# (ElevenLabs-generated, committed offline). Lazy-loaded; silent no-op if missing.
var _sfx_players: Dictionary = {}
func play_sfx(slug: String) -> void:
	_play_lazy_voice(_sfx_players, slug, "res://assets/sfx/creatures/%s.mp3" % slug, 8.0)

# Iter 140: same pattern for character banter (Pete + heroes). Slug
# matches the .mp3 filename: 'pete_intro', 'marshmallow_sheriff_rescue',
# etc. Each character is voiced by a different ElevenLabs premade voice
# (see [[project_flourish_voiceover]] for the assignment map).
var _character_players: Dictionary = {}

# Iter 153: true if ANY character-line clip is currently playing. The
# per-slug guard in play_character_line only blocks restarting the SAME
# clip; different slugs use different players and overlap. The menu-tap
# Humbug banter needs to block ALL overlap (user: "tapping humbug more
# than once in succession overlaps the audio").
func any_character_line_playing() -> bool:
	for slug in _character_players.keys():
		var p: AudioStreamPlayer = _character_players[slug]
		if p != null and p.playing:
			return true
	return false

func play_character_line(slug: String) -> void:
	# Iter 147: don't restart a character line that's still playing. These
	# clips are multi-second; Pete's taunt fires every 3rd shot, which was
	# cutting his voice off before any sentence finished (user: "Pete's
	# audio keeps interrupting itself"). A flourish restart is fine — those
	# are <1s — but dialogue should play through.
	if _character_players.has(slug):
		var existing: AudioStreamPlayer = _character_players[slug]
		if existing != null and existing.playing:
			return
	_play_lazy_voice(_character_players, slug,
		"res://assets/audio/characters/%s.mp3" % slug, 6.0)

# Shared lazy-load + cache pattern for voice clips. Stores one
# AudioStreamPlayer per slug in the provided dict; reuses on repeat
# play so we don't reload the stream every trigger.
func _play_lazy_voice(cache: Dictionary, slug: String, path: String, volume_db: float) -> void:
	if not cache.has(slug):
		if not ResourceLoader.exists(path):
			push_warning("voice missing: %s" % path)
			cache[slug] = null
			return
		var stream: AudioStream = load(path)
		if stream == null:
			cache[slug] = null
			return
		var p := AudioStreamPlayer.new()
		p.stream = stream
		p.bus = "Master"
		p.volume_db = volume_db
		add_child(p)
		cache[slug] = p
	var player: AudioStreamPlayer = cache[slug]
	if player != null:
		player.play()
