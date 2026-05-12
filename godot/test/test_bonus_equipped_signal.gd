extends GutTest

# Verifies the Bonus.equipped(type) signal contract — emitted by
# bonus.equip(), with the bonus_type string as the argument, and the
# bonus queue_frees itself afterwards so a single bonus can't be
# equipped twice.

const BonusScene = preload("res://scenes/bonus.tscn")

var bonus: Node2D

func before_each():
	bonus = BonusScene.instantiate()
	# add_child_autofree is safe even when equip() queue_frees early —
	# Godot's queue_free is idempotent on already-queued nodes.
	add_child_autofree(bonus)
	await get_tree().process_frame

# ---------- signal emission ----------

func test_equip_emits_equipped_signal():
	bonus.bonus_type = "fast_fire"
	watch_signals(bonus)
	bonus.equip()
	assert_signal_emitted(bonus, "equipped",
		"equip() should emit equipped()")

func test_equip_emits_with_bonus_type_param():
	bonus.bonus_type = "rifle"
	watch_signals(bonus)
	bonus.equip()
	assert_signal_emitted_with_parameters(bonus, "equipped", ["rifle"],
		"equipped() should carry the bonus_type string")

func test_equip_emits_extra_dude_type():
	bonus.bonus_type = "extra_dude"
	watch_signals(bonus)
	bonus.equip()
	assert_signal_emitted_with_parameters(bonus, "equipped", ["extra_dude"])

func test_equip_emits_empty_type_for_uninitialized_bonus():
	# A bonus without a type still emits — the listener will treat it as
	# unknown and log. We just verify the signal fires with the empty
	# string, not that the level reacts to it.
	watch_signals(bonus)
	bonus.equip()
	assert_signal_emitted_with_parameters(bonus, "equipped", [""])

# ---------- queue_free behavior ----------

func test_equip_queues_bonus_for_free():
	bonus.bonus_type = "fast_fire"
	bonus.equip()
	# queue_free() flags the node — is_queued_for_deletion goes true
	# immediately, the actual free happens after this frame.
	assert_true(bonus.is_queued_for_deletion(),
		"equip() should queue the bonus for deletion")
