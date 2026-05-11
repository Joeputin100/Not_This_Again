extends GutTest

# Tests for gate.take_bullet_hit() — the new bullet-on-gate interaction.
# Loads the gate.tscn so the @onready label refs resolve, then exercises
# the additive-vs-multiplicative behavior.

const GateScene = preload("res://scenes/gate.tscn")
const GateHelper = preload("res://scripts/gate_helper.gd")

var gate: Node2D

func _instance_with_type(t: int, left: int, right: int) -> Node2D:
	var g: Node2D = GateScene.instantiate()
	g.gate_type = t
	g.left_value = left
	g.right_value = right
	add_child_autofree(g)
	# _ready needs to run so labels exist; await a frame so they do.
	return g

func before_each() -> void:
	gate = null

# ---------- ADDITIVE ----------

func test_additive_hit_bumps_left_value_by_1():
	gate = _instance_with_type(GateHelper.TYPE_ADDITIVE, -3, 10)
	await get_tree().process_frame
	gate.take_bullet_hit()
	assert_eq(gate.left_value, -2, "additive left bumps -3 → -2")

func test_additive_hit_bumps_right_value_by_1():
	gate = _instance_with_type(GateHelper.TYPE_ADDITIVE, -3, 10)
	await get_tree().process_frame
	gate.take_bullet_hit()
	assert_eq(gate.right_value, 11, "additive right bumps 10 → 11")

func test_additive_multiple_hits_accumulate():
	gate = _instance_with_type(GateHelper.TYPE_ADDITIVE, -3, 10)
	await get_tree().process_frame
	for i in 5:
		gate.take_bullet_hit()
	assert_eq(gate.left_value, 2, "5 hits brings -3 → 2")
	assert_eq(gate.right_value, 15, "5 hits brings 10 → 15")

func test_additive_hit_returns_true_consumed():
	gate = _instance_with_type(GateHelper.TYPE_ADDITIVE, -3, 10)
	await get_tree().process_frame
	assert_true(gate.take_bullet_hit(), "additive gate consumes bullet")

func test_additive_hit_updates_label_text():
	gate = _instance_with_type(GateHelper.TYPE_ADDITIVE, -3, 10)
	await get_tree().process_frame
	gate.take_bullet_hit()
	var left_label: Label = gate.get_node("LeftDoor/LeftLabel")
	var right_label: Label = gate.get_node("RightDoor/RightLabel")
	assert_eq(left_label.text, "-2", "left label updates")
	assert_eq(right_label.text, "+11", "right label updates")

# ---------- MULTIPLICATIVE ----------

func test_multiplicative_hit_does_not_change_values():
	gate = _instance_with_type(GateHelper.TYPE_MULTIPLICATIVE, 2, 3)
	await get_tree().process_frame
	gate.take_bullet_hit()
	assert_eq(gate.left_value, 2, "mult left unchanged")
	assert_eq(gate.right_value, 3, "mult right unchanged")

func test_multiplicative_hit_returns_true_still_consumed():
	gate = _instance_with_type(GateHelper.TYPE_MULTIPLICATIVE, 2, 3)
	await get_tree().process_frame
	assert_true(gate.take_bullet_hit(),
		"mult gate still consumes bullets (just doesn't change values)")

func test_multiplicative_many_hits_no_drift():
	gate = _instance_with_type(GateHelper.TYPE_MULTIPLICATIVE, 2, 3)
	await get_tree().process_frame
	for i in 20:
		gate.take_bullet_hit()
	assert_eq(gate.left_value, 2)
	assert_eq(gate.right_value, 3)

# ---------- label format ----------

func test_additive_label_format():
	gate = _instance_with_type(GateHelper.TYPE_ADDITIVE, -3, 10)
	await get_tree().process_frame
	var left_label: Label = gate.get_node("LeftDoor/LeftLabel")
	var right_label: Label = gate.get_node("RightDoor/RightLabel")
	assert_eq(left_label.text, "-3")
	assert_eq(right_label.text, "+10")

func test_multiplicative_label_format():
	gate = _instance_with_type(GateHelper.TYPE_MULTIPLICATIVE, 2, 3)
	await get_tree().process_frame
	var left_label: Label = gate.get_node("LeftDoor/LeftLabel")
	var right_label: Label = gate.get_node("RightDoor/RightLabel")
	assert_eq(left_label.text, "x2")
	assert_eq(right_label.text, "x3")

# ---------- already-fired gates ----------

func test_fired_gate_ignores_bullet():
	# Once a gate has fired (cowboy passed through), bullets should NOT
	# bump it. Set _fired=true directly and verify.
	gate = _instance_with_type(GateHelper.TYPE_ADDITIVE, -3, 10)
	await get_tree().process_frame
	gate._fired = true
	var consumed: bool = gate.take_bullet_hit()
	assert_false(consumed, "fired gate doesn't consume bullets")
	assert_eq(gate.left_value, -3, "no value change after fire")

# ---------- color reflects gate direction ----------

func test_additive_with_negative_starts_shrinking():
	gate = _instance_with_type(GateHelper.TYPE_ADDITIVE, -3, 10)
	await get_tree().process_frame
	assert_false(gate._is_growing,
		"-3/+10 has a negative door → should be SHRINKING (red) at start")

func test_additive_all_positive_starts_growing():
	gate = _instance_with_type(GateHelper.TYPE_ADDITIVE, 5, 10)
	await get_tree().process_frame
	assert_true(gate._is_growing,
		"+5/+10 → SHOULD be growing (blue) at start")

func test_shooting_flips_red_to_blue():
	# -3/+10 starts red. After 3 hits: 0/+13 → still growing (≥ 0 = growing).
	# Wait, 0 counts as growing. So after 3 hits we flip to blue.
	gate = _instance_with_type(GateHelper.TYPE_ADDITIVE, -3, 10)
	await get_tree().process_frame
	assert_false(gate._is_growing, "starts red")
	gate.take_bullet_hit()  # -2 / 11
	gate.take_bullet_hit()  # -1 / 12
	assert_false(gate._is_growing, "still red after 2 hits")
	gate.take_bullet_hit()  # 0 / 13 → blue
	assert_true(gate._is_growing, "FLIPPED to blue after 3rd hit")

func test_shooting_blue_gate_stays_blue():
	gate = _instance_with_type(GateHelper.TYPE_ADDITIVE, 5, 10)
	await get_tree().process_frame
	assert_true(gate._is_growing)
	gate.take_bullet_hit()
	gate.take_bullet_hit()
	assert_true(gate._is_growing, "stays blue when shot from positive baseline")

func test_multiplicative_gate_with_zero_is_red():
	gate = _instance_with_type(GateHelper.TYPE_MULTIPLICATIVE, 0, 3)
	await get_tree().process_frame
	assert_false(gate._is_growing,
		"x0 zeroes the posse → SHRINKING (red)")
