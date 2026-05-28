extends Node2D

# Bullet fired by an outlaw or boss. Iter 31+: travels along an
# arbitrary velocity vector set by the shooter (instead of straight
# down), enabling aimed shots at the posse. Default velocity is
# (0, SPEED) for backward compatibility with any caller that doesn't
# bother setting it.
#
# On overlap with cowboy OR a posse follower (handled in level.gd's
# collision pass), the bullet kills ONE dude — POSSE_DAMAGE was bumped
# down from 2 to 1 in iter 31 so the per-dude semantics are clean:
# one bullet, one death.

const SPEED: float = 700.0
const SIZE: Vector2 = Vector2(10, 28)
const DESPAWN_X_LEFT: float = -100.0
const DESPAWN_X_RIGHT: float = 1180.0
const DESPAWN_Y_TOP: float = -300.0
const DESPAWN_Y_BOTTOM: float = 2080.0
const POSSE_DAMAGE: int = 1

# Velocity vector — overridden by the shooter to aim at the cowboy.
var velocity: Vector2 = Vector2(0, SPEED)

const SOUR_TEX := "res://assets/sprites/candy/candy_sour.png"
const SOUR_PX := 38.0

func _ready() -> void:
	add_to_group("outlaw_bullets")
	# Reskin: enemy shots are sour candy (distinct acid-green so incoming
	# danger reads clearly). PROTOTYPE art — see project_candy_shader_licensing.
	var tex: Texture2D = load(SOUR_TEX)
	if tex:
		for n in ["Body", "Glow"]:
			var rect: ColorRect = get_node_or_null(n) as ColorRect
			if rect:
				rect.visible = false
		var spr := Sprite2D.new()
		spr.texture = tex
		var s: float = SOUR_PX / float(maxi(tex.get_width(), 1))
		spr.scale = Vector2(s, s)
		add_child(spr)

func _process(delta: float) -> void:
	position += velocity * delta
	if position.y > DESPAWN_Y_BOTTOM \
			or position.y < DESPAWN_Y_TOP \
			or position.x < DESPAWN_X_LEFT \
			or position.x > DESPAWN_X_RIGHT:
		queue_free()
