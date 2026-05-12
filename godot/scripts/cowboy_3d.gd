extends Node2D

# 2.5D cowboy — a 3D Mixamo character rendered into a SubViewport,
# displayed on a Sprite2D inside the 2D playfield. Replaces the
# AnimatedSprite2D-with-frames approach from iter 23-25, which was
# motion-resolution-limited (6 idle frames / 8 run frames → choppy).
#
# Animation set comes from Mixamo: character.glb (rigged mesh, T-pose)
# + 4 animation-only .glb files (skeleton + single AnimationTrack each).
# At _ready we instance the character into the SubViewport, then load
# each animation .glb, extract its Animation resource, and add to a
# single AnimationLibrary that the character's AnimationPlayer references.
#
# Caller uses play_anim("idle"/"run"/"shoot"/"die"). All animations
# auto-loop except "die" (one-shot, freezes on final dead-frame pose).

const CHARACTER_GLB := preload("res://assets/3d/cowboy/character.glb")

# Mapping of in-game animation name → Mixamo-named source .glb. Mixamo
# names every animation "mixamo.com" inside the file, so we rename on
# import via the dictionary key.
const ANIM_GLBS: Dictionary = {
	"idle": preload("res://assets/3d/cowboy/Old_Man_Idle.glb"),
	"run": preload("res://assets/3d/cowboy/Running.glb"),
	"shoot": preload("res://assets/3d/cowboy/Shoot_Rifle.glb"),
	"die": preload("res://assets/3d/cowboy/Dying.glb"),
}

# SubViewport dimensions in pixels — sized to match the 2D sprite slot
# the leader cowboy used to occupy (~100×200 visible) but rendered at
# 2× for clean sampling under the Sprite2D's 0.5 scale.
const VIEWPORT_SIZE: Vector2i = Vector2i(256, 512)

# Camera framing — looking at the cowboy's chest from slightly above
# and behind. Tuned so a ~1.8m Mixamo human fills the viewport at this
# FOV without head-cropping or hat-clipping. Tweak FOV if cowboy
# appears too small/large on device.
const CAMERA_POSITION: Vector3 = Vector3(0, 1.0, 2.6)
const CAMERA_LOOK_TARGET: Vector3 = Vector3(0, 0.9, 0)
const CAMERA_FOV_DEG: float = 35.0

@onready var sub_viewport: SubViewport = $SubViewport
@onready var sprite_2d: Sprite2D = $Sprite

var _character_instance: Node3D
var _animation_player: AnimationPlayer
var _current_anim: String = ""

func _ready() -> void:
	_setup_3d_scene()
	# Default to "run" — gameplay always starts with the cowboy auto-firing
	# while running. _switch_posse_to_idle() in level.gd swaps on win.
	play_anim("run")

func _setup_3d_scene() -> void:
	# Instance the rigged character into the SubViewport's 3D world.
	_character_instance = CHARACTER_GLB.instantiate() as Node3D
	if _character_instance == null:
		push_error("cowboy_3d: character.glb did not instance as Node3D")
		return
	sub_viewport.add_child(_character_instance)

	# Find the AnimationPlayer Mixamo / FBX2glTF generated. character.glb
	# ("with skin" export) ships mesh+skeleton ONLY — no animations, so
	# no AnimationPlayer is created during import. Create one and attach
	# it to the character root so we have a target for the library.
	_animation_player = _character_instance.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if _animation_player == null:
		_animation_player = AnimationPlayer.new()
		_animation_player.name = "AnimationPlayer"
		_character_instance.add_child(_animation_player)

	# Build a single AnimationLibrary from the 4 animation-only .glb files.
	# Each one has its own AnimationPlayer with one animation; we extract
	# them and rename via our gameplay-friendly key.
	var lib := AnimationLibrary.new()
	for anim_name in ANIM_GLBS:
		var packed: PackedScene = ANIM_GLBS[anim_name]
		var anim_scene: Node = packed.instantiate()
		var ap: AnimationPlayer = anim_scene.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if ap == null:
			push_warning("cowboy_3d: %s missing AnimationPlayer; skipped" % anim_name)
			anim_scene.queue_free()
			continue
		# Mixamo exports every animation under the literal name "mixamo.com".
		# Grab the first animation and remap to our key.
		var source_names: PackedStringArray = ap.get_animation_list()
		if source_names.is_empty():
			anim_scene.queue_free()
			continue
		var src_anim: Animation = ap.get_animation(source_names[0])
		if src_anim:
			# Die is one-shot — every other animation loops.
			src_anim.loop_mode = Animation.LOOP_NONE if anim_name == "die" else Animation.LOOP_LINEAR
			lib.add_animation(anim_name, src_anim)
		anim_scene.queue_free()
	_animation_player.add_animation_library("posse", lib)
	# Wire the SubViewport's render target into the Sprite2D's texture.
	# Set in code rather than the .tscn because ViewportTexture needs the
	# SubViewport to exist before the texture is bound — easier to do
	# after both nodes are @ready.
	sprite_2d.texture = sub_viewport.get_texture()
	# Apply camera transform here so the scene file stays light. Camera
	# was added to the SubViewport in the .tscn but with default transform.
	var cam: Camera3D = sub_viewport.find_child("Camera3D", false, false) as Camera3D
	if cam:
		cam.position = CAMERA_POSITION
		cam.look_at(CAMERA_LOOK_TARGET)
		cam.fov = CAMERA_FOV_DEG

# play_anim — switch to the named animation. Idempotent (returns early
# if already playing). "idle"/"run"/"shoot"/"die" are the supported
# keys, matching the gameplay states callers in level.gd care about.
func play_anim(anim_name: String) -> void:
	if _animation_player == null:
		return
	if anim_name == _current_anim:
		return
	var full_name := "posse/%s" % anim_name
	if not _animation_player.has_animation(full_name):
		push_warning("cowboy_3d: no animation named %s" % full_name)
		return
	_current_anim = anim_name
	_animation_player.play(full_name)
