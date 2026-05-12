extends RefCounted

# Universal "freeze last frame, then strobe-disappear" polish applied to
# every enemy's death sequence. Iter 33+: consistent visual end-state
# across vagrants, prospectors, Pete, and any future boss — the player
# always reads "this enemy is dead and gone" the same way.
#
# Usage (in any enemy's _play_destroy_animation):
#   await get_tree().create_timer(DEATH_VIDEO_DURATION).timeout
#   await DeathPolish.play(self)
#   queue_free()
#
# Freeze duration lets the death animation's final frame sit visible
# long enough to register. Strobe pulses visibility 4× (8 toggles) over
# STROBE_DURATION, ending invisible — classic "dissolving away" feel.

const FREEZE_DURATION: float = 0.5
const STROBE_DURATION: float = 0.5
const STROBE_FLASHES: int = 4

static func play(target: Node2D) -> void:
	if target == null or not is_instance_valid(target):
		return
	var tree: SceneTree = target.get_tree()
	if tree == null:
		return
	# Phase 1: freeze on whatever frame the death animation ended on.
	# Caller is responsible for stopping its video / freezing tween.
	await tree.create_timer(FREEZE_DURATION).timeout
	if not is_instance_valid(target):
		return
	# Phase 2: strobe-disappear. Each "flash" = one off→on cycle.
	var flash_t: float = STROBE_DURATION / float(STROBE_FLASHES * 2)
	for i in STROBE_FLASHES:
		if not is_instance_valid(target):
			return
		target.visible = false
		await tree.create_timer(flash_t).timeout
		if not is_instance_valid(target):
			return
		target.visible = true
		await tree.create_timer(flash_t).timeout
	# End invisible — caller can queue_free immediately after the await.
	if is_instance_valid(target):
		target.visible = false
