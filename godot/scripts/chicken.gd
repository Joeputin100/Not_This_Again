extends Node2D

# A loose chicken — released when a chicken_coop is destroyed.
# Moves chaotically: picks a random heading every CHANGE_DIR_INTERVAL
# seconds, runs at MOVE_SPEED. 1-3 HP (randomized at spawn).
# No collision damage to cowboy — pure visual chaos / vision blocker.
# Bullets still kill it. Despawns when shot, off-screen, or after LIFESPAN.

const MOVE_SPEED: float = 240.0
const CHANGE_DIR_INTERVAL: float = 0.65
const LIFESPAN: float = 5.5
const SIZE: Vector2 = Vector2(60, 60)
const FLAP_FREQ_HZ: float = 14.0

var hp: int = 2
var _heading: Vector2 = Vector2.RIGHT
var _change_dir_timer: float = 0.0
var _life_timer: float = 0.0
var _flap_phase: float = 0.0

@onready var body: Polygon2D = $Body

func _ready() -> void:
	add_to_group("chickens")
	# Randomized HP 1-3 per chicken so a few die instantly while
	# others take a moment — feels like a real flock.
	hp = randi_range(1, 3)
	_pick_new_heading()

func _process(delta: float) -> void:
	_life_timer += delta
	if _life_timer > LIFESPAN:
		queue_free()
		return
	# Chaotic direction changes.
	_change_dir_timer += delta
	if _change_dir_timer >= CHANGE_DIR_INTERVAL:
		_change_dir_timer = 0.0
		_pick_new_heading()
	position += _heading * MOVE_SPEED * delta
	# Despawn if it leaves the playfield.
	if position.x < -120 or position.x > 1200 or position.y < -120 or position.y > 2080:
		queue_free()
		return
	# Flap animation — scale oscillation. Suggests wing-beats without
	# requiring sprite sheets.
	_flap_phase += delta * FLAP_FREQ_HZ
	var flap := 1.0 + 0.18 * sin(_flap_phase * TAU)
	if body:
		body.scale = Vector2(1.0, flap)

func take_bullet_hit(damage: int = 1) -> bool:
	hp -= damage
	if hp <= 0:
		_play_death()
	return true  # bullet consumed

# Chickens don't damage the cowboy — vision-blocker only.
func get_cowboy_damage() -> int:
	return 0

func _pick_new_heading() -> void:
	_heading = Vector2.RIGHT.rotated(randf() * TAU)

func _play_death() -> void:
	if has_node("Feathers"):
		var feathers: CPUParticles2D = $Feathers
		feathers.emitting = true
	var tween := create_tween().set_parallel(true)
	tween.tween_property(self, "modulate:a", 0.0, 0.25)
	tween.tween_property(self, "scale", Vector2(1.4, 1.4), 0.25) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await tween.finished
	queue_free()
