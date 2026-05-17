extends Control

# Debug menu — preview each Gold Rush / Sugar Rush / flourish in
# isolation, plus reset GameState fields. Accessed from main_menu via a
# DEBUG button shown ONLY in OS.has_feature("debug") builds. Release
# builds never expose this UI; the scene + script ship but are unreachable.
#
# Architecture: each "Preview Rush X" button sets DebugPreview.pending_rush
# and changes scene to level.tscn. Level.gd's _ready inspects
# DebugPreview, suppresses normal gate/boss spawning, and fires the
# requested rush immediately. Flourish previews fire LOCALLY (no scene
# change needed) since FlourishBanner.spawn() just needs a CanvasLayer.

const FlourishBanner = preload("res://scripts/flourish_banner.gd")

# All Gold Rush IDs the player can preview. Order = display order in UI.
const RUSH_IDS: Array[String] = ["A", "B", "D", "E", "F", "G", "H"]
const RUSH_NAMES: Dictionary = {
	"A": "Six-Shooter Salute (Easy)",
	"B": "Jelly Jar Cascade (Hard, Mine)",
	"D": "Tumbleweed Bonus Roll (Medium, Farm)",
	"E": "Candy Cart Chain (Extreme, Frontier)",
	"F": "Liquorice Locomotive (Extreme, Mine)",
	"G": "Avalanche Bonanza (Extreme, Mountain)",
	"H": "Gumball Runaway (Extreme, Mountain alt)",
}

# Flourish presets the player can preview locally (no scene change).
const FLOURISH_KEYS: Array[String] = [
	"DOUBLE!", "MEGA!", "TASTY!", "JUICY!", "SWEET!", "FLAWLESS!",
	"YEEHAW!", "RAMPAGE!",
]

@onready var ui_layer: CanvasLayer = $UI
@onready var scroll: ScrollContainer = $UI/Scroll
@onready var content: VBoxContainer = $UI/Scroll/Content
@onready var back_button: Button = $UI/BackButton

func _ready() -> void:
	get_tree().set_quit_on_go_back(false)
	get_window().go_back_requested.connect(_on_back_pressed)
	back_button.pressed.connect(_on_back_pressed)
	_build_sections()

func _build_sections() -> void:
	_add_section_header("GOLD RUSH PREVIEWS")
	for rush_id in RUSH_IDS:
		var btn := _make_button(
			"%s — %s" % [rush_id, RUSH_NAMES.get(rush_id, "?")])
		btn.pressed.connect(_on_preview_rush.bind(rush_id))
		content.add_child(btn)

	_add_section_header("SUGAR RUSH")
	var sugar_btn := _make_button("JELLY BEAN FRENZY (mid-level activate)")
	sugar_btn.pressed.connect(_on_preview_sugar_rush)
	content.add_child(sugar_btn)

	_add_section_header("TEST RANGE")
	var range_btn := _make_button("OPEN CACTUS FIELD (weapon + posse test)")
	range_btn.pressed.connect(_on_open_test_range)
	content.add_child(range_btn)
	# Iter 64: 3D level prototype preview.
	var level3d_btn := _make_button("PREVIEW 3D LEVEL (iter 64 prototype)")
	level3d_btn.pressed.connect(_on_open_level_3d)
	content.add_child(level3d_btn)

	_add_section_header("FLOURISH PREVIEWS (in-place)")
	for key in FLOURISH_KEYS:
		var btn := _make_button(key)
		btn.pressed.connect(_on_preview_flourish.bind(key))
		content.add_child(btn)

	_add_section_header("STATE RESETS")
	var reset_hearts := _make_button("RESET HEARTS → MAX")
	reset_hearts.pressed.connect(_on_reset_hearts)
	content.add_child(reset_hearts)
	var reset_bounty := _make_button("RESET BOUNTY → 0")
	reset_bounty.pressed.connect(_on_reset_bounty)
	content.add_child(reset_bounty)

func _add_section_header(text: String) -> void:
	var sep := Label.new()
	sep.custom_minimum_size = Vector2(0, 30)
	content.add_child(sep)
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 36)
	label.add_theme_color_override("font_color", Color(0.95, 0.78, 0.35, 1))
	content.add_child(label)

func _make_button(text: String) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(0, 88)
	btn.add_theme_font_size_override("font_size", 30)
	return btn

# Rush previews: set DebugPreview state + load level scene. Level.gd
# observes the autoload in _ready and fires the requested rush.
func _on_preview_rush(rush_id: String) -> void:
	AudioBus.play_tap()
	DebugPreview.pending_rush = rush_id
	DebugLog.add("debug: preview rush %s (3D)" % rush_id)
	# Iter 125: rush previews now route to the 3D level. Each rush is
	# implemented as a 3D ceremony in level_3d.gd; the 2D versions
	# (level.gd) stay around as the legacy path but are not used here.
	get_tree().change_scene_to_file("res://scenes/level_3d.tscn")

func _on_preview_sugar_rush() -> void:
	AudioBus.play_tap()
	DebugPreview.pending_sugar_rush = true
	DebugLog.add("debug: preview sugar rush (3D)")
	get_tree().change_scene_to_file("res://scenes/level_3d.tscn")

func _on_open_test_range() -> void:
	AudioBus.play_tap()
	DebugPreview.pending_test_range = true
	# Iter 123: cactus test range now routes to the 3D level. The pending_
	# test_range flag is still set, but level_3d.gd will need to honor it
	# to spawn the cactus field (currently only level.gd reads it). Until
	# that wires up, the test range opens the standard 3D level — better
	# than the legacy 2D version since gameplay is now 3D-canonical.
	DebugLog.add("debug: open test range (3D)")
	get_tree().change_scene_to_file("res://scenes/level_3d.tscn")

func _on_open_level_3d() -> void:
	AudioBus.play_tap()
	# Iter 123: button label says '3D PREVIEW' but the underlying scene
	# this opens is now the LEGACY 2D gameplay. Swap is intentional —
	# the 3D level is canonical (via PLAY + test-range buttons); this
	# button preserves access to the 2D version for comparison/debugging.
	DebugLog.add("debug: open legacy 2D level (button labeled 3D PREVIEW)")
	get_tree().change_scene_to_file("res://scenes/level.tscn")

# Flourish previews: fire on the local CanvasLayer immediately. No scene
# change. Banner appears centered, plays its animation, frees itself.
func _on_preview_flourish(preset_key: String) -> void:
	AudioBus.play_tap()
	FlourishBanner.spawn(ui_layer, preset_key, null)

func _on_reset_hearts() -> void:
	AudioBus.play_tap()
	GameState.hearts = GameState.MAX_HEARTS
	DebugLog.add("debug: hearts reset to %d" % GameState.hearts)

func _on_reset_bounty() -> void:
	AudioBus.play_tap()
	GameState.bounty = 0
	DebugLog.add("debug: bounty reset to 0")

func _on_back_pressed() -> void:
	AudioBus.play_tap()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
