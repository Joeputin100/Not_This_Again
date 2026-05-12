extends AnimatedSprite2D

# One-shot muzzle flash. Plays the "fire" animation once at 30fps (6
# frames = ~200ms), then queue_frees itself. Spawned by level.gd per
# bullet, parented to the cowboy so the flash follows the shooter if
# the cowboy moves during the flash's brief lifetime.
#
# Animation order in the SpriteFrames: peak burst first (the BIG
# star at the moment of firing), then dissipating smoke clouds, ending
# on a small fading spark. Matches real-world muzzle physics — the
# flash is brightest at trigger pull, fades to smoke wisps.

func _ready() -> void:
	# Disconnect the AnimatedSprite2D's default animation_finished
	# behavior (none) and add ours: queue_free when the flash completes.
	animation_finished.connect(_on_finished)
	# autoplay in the .tscn handles the initial play() — but if a future
	# caller instantiates without autoplay, this ensures play happens.
	if not is_playing():
		play("fire")

func _on_finished() -> void:
	queue_free()
