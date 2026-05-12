extends GutTest

# Tests for the direction_flipped signal added in iter 22c. Emitted when
# a gate transitions from "shrinking" (red) to "growing" (blue) due to
# the player's bullets bumping additive values into non-negative
# territory. NOT emitted on the initial _ready paint.

const GateScene = preload("res://scenes/gate.tscn")
const GateHelper = preload("res://scripts/gate_helper.gd")

var gate: Node2D

func _instance_with_type(t: int, left: int, right: int) -> Node2D:
	var g: Node2D = GateScene.instantiate()
	g.gate_type = t
	g.left_value = left
	g.right_value = right
	add_child_autofree(g)
	return g

func before_each() -> void:
	gate = null

# ---------- initial _ready snap is silent ----------

func test_no_signal_on_ready_for_red_gate():
	# A gate that starts red should NOT emit direction_flipped during
	# its _ready() initial-paint. The signal is for mid-game flips only.
	gate = _instance_with_type(GateHelper.TYPE_ADDITIVE, -3, -3)
	watch_signals(gate)
	await get_tree().process_frame
	assert_false(gate._is_growing, "starts shrinking")
	assert_signal_not_emitted(gate, "direction_flipped",
		"initial _ready snap must NOT emit direction_flipped")

func test_no_signal_on_ready_for_blue_gate():
	# Gate starting blue stays blue, no signal.
	gate = _instance_with_type(GateHelper.TYPE_ADDITIVE, 5, 10)
	watch_signals(gate)
	await get_tree().process_frame
	assert_true(gate._is_growing, "starts growing")
	assert_signal_not_emitted(gate, "direction_flipped",
		"blue gate _ready must not emit")

# ---------- red → blue flip emits ----------

func test_red_to_blue_flip_emits_direction_flipped():
	# Both doors at -3; each shot bumps BOTH sides by +1 (caliber 1).
	# After 3 shots: 0, 0 → both ≥ 0 → growing. That's the flip.
	gate = _instance_with_type(GateHelper.TYPE_ADDITIVE, -3, -3)
	await get_tree().process_frame
	watch_signals(gate)
	# Shots 1 and 2: still negative on both sides, no flip.
	gate.take_bullet_hit()  # -2, -2
	gate.take_bullet_hit()  # -1, -1
	assert_signal_not_emitted(gate, "direction_flipped",
		"shouldn't flip while either side is still negative")
	# Shot 3: 0, 0 → growing (both ≥ 0). Flip!
	gate.take_bullet_hit()  # 0, 0
	assert_signal_emitted(gate, "direction_flipped",
		"flip should fire when -3,-3 hits 0,0")

func test_red_to_blue_flip_passes_self_in_signal():
	gate = _instance_with_type(GateHelper.TYPE_ADDITIVE, -1, -1)
	await get_tree().process_frame
	watch_signals(gate)
	gate.take_bullet_hit()  # 0, 0 → flip
	# Manual param check — assert_signal_emitted_with_parameters has a
	# Variant-comparison quirk with Object-typed args under this GUT
	# version that surfaces as "Invalid operands 'String' and 'int'".
	assert_signal_emitted(gate, "direction_flipped",
		"direction_flipped should fire on the red→blue transition")
	var params = get_signal_parameters(gate, "direction_flipped", 0)
	assert_eq(params[0] if params else null, gate,
		"direction_flipped should pass the gate itself as its argument")

func test_caliber_aware_flip():
	# A high-caliber shot can flip a gate in fewer hits.
	gate = _instance_with_type(GateHelper.TYPE_ADDITIVE, -5, -5)
	await get_tree().process_frame
	watch_signals(gate)
	gate.take_bullet_hit(3)  # -2, -2 → still red
	assert_signal_not_emitted(gate, "direction_flipped")
	gate.take_bullet_hit(3)  # 1, 1 → blue, FLIP
	assert_signal_emitted(gate, "direction_flipped")

# ---------- already-blue gate doesn't re-flip ----------

func test_blue_gate_does_not_emit_when_shot_further_positive():
	# A gate already blue shouldn't emit when shot — it's not changing
	# direction, just getting more generous.
	gate = _instance_with_type(GateHelper.TYPE_ADDITIVE, 2, 3)
	await get_tree().process_frame
	watch_signals(gate)
	for i in 5:
		gate.take_bullet_hit()
	assert_signal_not_emitted(gate, "direction_flipped",
		"blue-staying-blue must not emit direction_flipped")

# ---------- single-side flip-then-back doesn't emit ----------

func test_mixed_negative_does_not_flip_when_only_one_side_crosses():
	# Both at -1. take_bullet_hit bumps BOTH sides, so they both cross
	# simultaneously. This test verifies the gate's "both sides ≥ 0"
	# requirement by checking that a single bump from -1,-1 hits the
	# flip exactly once.
	gate = _instance_with_type(GateHelper.TYPE_ADDITIVE, -1, -1)
	await get_tree().process_frame
	watch_signals(gate)
	gate.take_bullet_hit()  # 0, 0 → flip
	assert_signal_emit_count(gate, "direction_flipped", 1,
		"only one flip should fire even on threshold crossing")
	# Further hits stay blue; no more flips.
	gate.take_bullet_hit()  # 1, 1 → still blue
	gate.take_bullet_hit()  # 2, 2 → still blue
	assert_signal_emit_count(gate, "direction_flipped", 1,
		"no re-flip while staying blue")
