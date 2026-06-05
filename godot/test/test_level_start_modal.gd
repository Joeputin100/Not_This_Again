extends GutTest

# Instance-check for the Soda-Crush level-start modal: load the scene, call
# show_level, assert the nodes resolve + the title/goal land, and that the
# PLAY/X buttons fire the right signals (like the win-modal pattern).

const MODAL_SCENE := preload("res://scenes/ui/level_start_modal.tscn")
const LevelDefScript = preload("res://scripts/level_def.gd")

var modal

func before_each():
	modal = MODAL_SCENE.instantiate()
	add_child_autofree(modal)

func test_show_level_sets_title_and_goal():
	modal.show_level(2, "MINE SHAFT MAYHEM", "Clear 60 outlaws, then defeat The Candy Rustler!")
	assert_true(modal.visible, "modal should be visible after show_level")
	assert_eq(modal._header_label.text, "LEVEL 2")
	assert_eq(modal._subtitle_label.text, "MINE SHAFT MAYHEM")
	assert_eq(modal._goal_label.text, "Clear 60 outlaws, then defeat The Candy Rustler!")

func test_play_button_emits_play_pressed():
	watch_signals(modal)
	modal._on_play()
	assert_signal_emitted(modal, "play_pressed")

func test_close_button_emits_close_pressed():
	watch_signals(modal)
	modal._on_close()
	assert_signal_emitted(modal, "close_pressed")

func test_nodes_resolve():
	modal.show_level(1, "X", "Y")
	assert_not_null(modal.get_node_or_null("Panel/HeaderPill/HeaderLabel"))
	assert_not_null(modal.get_node_or_null("Panel/GoalViewer/GoalLabel"))
	assert_not_null(modal.get_node_or_null("Panel/PlayButton"))
	assert_not_null(modal.get_node_or_null("Panel/CloseButton"))

func test_goal_text_defeat_boss_rustler():
	var def = LevelDefScript.new()
	def.goal = LevelDefScript.Goal.DEFEAT_BOSS
	def.outlaw_quota = 60
	assert_eq(LevelDefScript.goal_text(def, 2),
		"Clear 60 outlaws, then defeat The Candy Rustler!")

func test_goal_text_defeat_boss_pete():
	var def = LevelDefScript.new()
	def.goal = LevelDefScript.Goal.DEFEAT_BOSS
	def.outlaw_quota = 40
	assert_eq(LevelDefScript.goal_text(def, 1),
		"Clear 40 outlaws, then defeat Slippery Pete!")

func test_goal_text_reach_end():
	var def = LevelDefScript.new()
	def.goal = LevelDefScript.Goal.REACH_END
	assert_eq(LevelDefScript.goal_text(def, 3), "Reach the end of the trail!")

func test_goal_text_survive():
	var def = LevelDefScript.new()
	def.goal = LevelDefScript.Goal.SURVIVE
	def.goal_param = 90.0
	assert_eq(LevelDefScript.goal_text(def, 5), "Survive 90 seconds!")
