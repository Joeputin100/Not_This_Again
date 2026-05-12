class_name GunState
extends RefCounted

# Per-shooter runtime state for a Gun resource. Owned by the level (one
# state per posse member, once multi-dude lands). Driven by tick(delta).
#
# Lifecycle:
#   has ammo + cooldown <= 0 → can_fire() true → fire() consumes 1 round
#   ammo hits 0 → reloading=true, reload_timer counts down
#   reload_timer <= 0 → ammo refilled, reloading=false
#
# Cooldown after each shot enforces the gun's fire_interval (so a single
# shooter can't empty the clip in one frame).

var gun: Resource
var _ammo: int
var _fire_cooldown: float = 0.0
var _reload_timer: float = 0.0
var _reloading: bool = false

func _init(g: Resource) -> void:
	gun = g
	_ammo = gun.clip_size

func can_fire() -> bool:
	return not _reloading and _ammo > 0 and _fire_cooldown <= 0.0

func fire() -> bool:
	if not can_fire():
		return false
	_ammo -= 1
	_fire_cooldown = gun.fire_interval
	if _ammo <= 0:
		_reloading = true
		_reload_timer = gun.reload_time
	return true

func tick(delta: float) -> void:
	if _fire_cooldown > 0.0:
		_fire_cooldown -= delta
	if _reloading:
		_reload_timer -= delta
		if _reload_timer <= 0.0:
			_reloading = false
			_ammo = gun.clip_size

func ammo() -> int:
	return _ammo

func is_reloading() -> bool:
	return _reloading

# 0.0–1.0 progress through the current reload. Useful for UI bars.
func reload_progress() -> float:
	if not _reloading or gun.reload_time <= 0.0:
		return 0.0
	return 1.0 - (_reload_timer / gun.reload_time)
