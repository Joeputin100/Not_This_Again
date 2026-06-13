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
	"A": "Perfect Volley — Six-Shooter Salute (Easy)",
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

# Iter 128: bonus weapon slugs + display names. Each routes through
# DebugPreview.pending_weapon to level_3d's _preview_weapon_3d ceremony.
const WEAPON_SLUGS: Array[String] = [
	"jelly_six_shooter",
	"marshmallow_cannon",
	"liquorice_whip",
	"frostbite_rifle",
	"sugar_mortar",
	"gumdrop_grenade",
	"peppermint_shotgun",
	"caramel_lasso",
]
const WEAPON_NAMES: Dictionary = {
	"jelly_six_shooter":  "JELLY SIX-SHOOTER (default)",
	"marshmallow_cannon": "MARSHMALLOW CANNON",
	"liquorice_whip":     "LIQUORICE WHIP",
	"frostbite_rifle":    "FROSTBITE RIFLE",
	"sugar_mortar":       "SUGAR MORTAR",
	"gumdrop_grenade":    "GUMDROP GRENADE",
	"peppermint_shotgun": "PEPPERMINT SHOTGUN",
	"caramel_lasso":      "CARAMEL LASSO",
}

# Iter 129: bonus hero slugs + display names.
const HERO_SLUGS: Array[String] = [
	"marshmallow_sheriff",
	"laughing_horse",
	"scarecrow",
	"chocolate_outlaw",
	"sugar_doc",
	"taffy_kid",
]
const HERO_NAMES: Dictionary = {
	"marshmallow_sheriff": "MARSHMALLOW SHERIFF (badge + double-action)",
	"laughing_horse":      "LAUGHING HORSE (mount, faster swerve)",
	"scarecrow":           "SCARECROW (sticks + straw + spin attack)",
	"chocolate_outlaw":    "CHOCOLATE OUTLAW (dual jelly pistols)",
	"sugar_doc":           "SUGAR DOC (heals 1 posse / 5s)",
	"taffy_kid":           "TAFFY KID (sticky bullets slow enemies)",
}

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
	# Iter 182 / SP1: rendering-rebuild tier. SP1 is the sprite-sheet
	# animation system (this preview is live); SP2 and SP3 are reserved
	# for future rendering work and are shown as disabled placeholders so
	# the section is discoverable before they exist.
	_add_section_header("RENDERING REBUILD")
	var sp1_btn := _make_button("SP1 — SPRITE-SHEET ANIMATION (crowd viewer)")
	sp1_btn.pressed.connect(_on_open_sp1_crowd_viewer)
	content.add_child(sp1_btn)
	var sp2_btn := _make_button("SP2 — (reserved)")
	sp2_btn.disabled = true
	content.add_child(sp2_btn)
	var sp3_btn := _make_button("SP3 — (reserved)")
	sp3_btn.disabled = true
	content.add_child(sp3_btn)

	_add_section_header("SPLASH")
	var reset_splash_btn := _make_button("RESET FULL SPLASH CINEMATIC")
	reset_splash_btn.pressed.connect(_on_reset_splash)
	content.add_child(reset_splash_btn)

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

	# Iter 128: bonus weapon previews. Each button sets
	# DebugPreview.pending_weapon and routes to the 3D level which
	# plays a short demo-fire ceremony for that weapon.
	_add_section_header("BONUS WEAPONS")
	for w in WEAPON_SLUGS:
		var btn := _make_button(WEAPON_NAMES.get(w, w))
		btn.pressed.connect(_on_preview_weapon.bind(w))
		content.add_child(btn)

	# Iter 129: bonus hero previews. Each button sets
	# DebugPreview.pending_posse_unlock and routes to the 3D level.
	_add_section_header("BONUS HEROES")
	for h in HERO_SLUGS:
		var btn := _make_button(HERO_NAMES.get(h, h))
		btn.pressed.connect(_on_preview_hero.bind(h))
		content.add_child(btn)

	# Iter 132: glitz/spin picker — pick the visual treatment for each
	# bonus pickup type via live 3D preview, saved automatically.
	_add_section_header("GLITZ PICKER")
	var glitz_btn := _make_button("PICK BONUS GLITZ + SPIN PRESETS")
	glitz_btn.pressed.connect(_on_open_glitz_picker)
	content.add_child(glitz_btn)

	# Iter 148: prop-sway profile picker — compare 5 puppet sway styles.
	_add_section_header("SWAY PICKER")
	var sway_btn := _make_button("PICK PROP SWAY MOTION")
	sway_btn.pressed.connect(_on_open_sway_picker)
	content.add_child(sway_btn)

	# Iter 153: Candy Rustler jointed-puppet rig preview.
	_add_section_header("CANDY RUSTLER")
	var rustler_btn := _make_button("PREVIEW CANDY RUSTLER RIG")
	rustler_btn.pressed.connect(_on_open_rustler_rig)
	content.add_child(rustler_btn)
	# Iter 157: play level 2 (Candy Rustler is the level-2 boss). iter 158
	# will add this as a proper node on the level selector.
	var rustler_lvl_btn := _make_button("PLAY LEVEL 2 — CANDY RUSTLER BOSS")
	rustler_lvl_btn.pressed.connect(_on_play_level_2)
	content.add_child(rustler_lvl_btn)

	# Iter 133: captive hero rescue previews. Heroes trapped in containers
	# the player must shoot to free. Basic static version (no pushers).
	_add_section_header("CAPTIVE HEROES (basic)")
	for h in HERO_SLUGS:
		for c in ["wagon_covered", "mining_cart", "barrel"]:
			var btn := _make_button("%s in %s" % [HERO_NAMES.get(h, h), c.replace("_", " ").to_upper()])
			btn.pressed.connect(_on_preview_captive.bind(h, c))
			content.add_child(btn)

	# Iter 134: pushed-wagon previews — 10/25/50/100 beagle pusher counts
	# for the sheriff in a covered wagon. Tests the mob mechanic.
	_add_section_header("PUSHED WAGONS (beagle mob)")
	for n in [10, 25, 50, 100]:
		var btn := _make_button("SHERIFF in WAGON with %d PUSHERS" % n)
		btn.pressed.connect(_on_preview_pushed_wagon.bind("marshmallow_sheriff", "wagon_covered", n))
		content.add_child(btn)

	# kimmy: Rainbow Kimmy rescue + sugar rush. Equips the RAINBOW weapon and
	# drops her rock-candy cage so the full crack → transform → screen-clear plays.
	_add_section_header("RAINBOW KIMMY")
	var kimmy_btn := _make_button("RAINBOW KIMMY — RESCUE + SUGAR RUSH")
	kimmy_btn.pressed.connect(_on_preview_kimmy)
	content.add_child(kimmy_btn)

	# Level-6 sing minigames: jump straight in for swipe/mic testing.
	_add_section_header("LEVEL 6 — SING DUEL")
	var queen_btn := _make_button("QUEEN SING-DUEL (L6 BOSS)")
	queen_btn.pressed.connect(_on_preview_queen_duel)
	content.add_child(queen_btn)
	var papa_btn := _make_button("PAPAGENO DUET (L6 TUTORIAL)")
	papa_btn.pressed.connect(_on_preview_papageno_duet)
	content.add_child(papa_btn)

	_add_section_header("LEVEL 4 — JAWBREAKER")
	var jaw_btn := _make_button("JAWBREAKER (L4 BOSS)")
	jaw_btn.pressed.connect(_on_preview_jawbreaker)
	content.add_child(jaw_btn)

	# iter620 device pass (#90): jump straight into ANY level (the map only
	# unlocks via progression) + the chicken minigame, which the map gated
	# behind Granny's once-a-day popup. L7 has no level_7.tres yet, so its
	# button only appears once that resource exists.
	_add_section_header("PLAY ANY LEVEL")
	for n in range(1, 8):
		if not ResourceLoader.exists("res://resources/levels/level_%d.tres" % n):
			continue
		var lbl := "LEVEL %d" % n
		var def: LevelDef = load("res://resources/levels/level_%d.tres" % n)
		if def != null and def.display_name != "":
			lbl = "LEVEL %d — %s" % [n, def.display_name]
		var lvl_btn := _make_button(lbl)
		lvl_btn.pressed.connect(_on_play_level.bind(n))
		content.add_child(lvl_btn)
	var chicken_btn := _make_button("🐔 GRANNY'S CHICKEN CHASE")
	chicken_btn.pressed.connect(_on_play_chicken_chase)
	content.add_child(chicken_btn)

	_add_section_header("TEST RANGE")
	var range_btn := _make_button("OPEN CACTUS FIELD (weapon + posse test)")
	range_btn.pressed.connect(_on_open_test_range)
	content.add_child(range_btn)
	# iter435: the "PREVIEW 3D LEVEL" button (which actually loaded the LEGACY 2D
	# level.tscn) was removed — the 3D level is canonical; the dead 2D path is gone.

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

func _on_preview_weapon(slug: String) -> void:
	AudioBus.play_tap()
	DebugPreview.pending_weapon = slug
	DebugLog.add("debug: preview weapon %s" % slug)
	get_tree().change_scene_to_file("res://scenes/level_3d.tscn")

func _on_preview_hero(slug: String) -> void:
	AudioBus.play_tap()
	DebugPreview.pending_posse_unlock = slug
	DebugLog.add("debug: preview hero %s" % slug)
	get_tree().change_scene_to_file("res://scenes/level_3d.tscn")

func _on_open_sway_picker() -> void:
	AudioBus.play_tap()
	DebugLog.add("debug: open sway picker")
	get_tree().change_scene_to_file("res://scenes/sway_picker.tscn")

func _on_open_rustler_rig() -> void:
	AudioBus.play_tap()
	DebugLog.add("debug: open candy rustler rig preview")
	get_tree().change_scene_to_file("res://scenes/candy_rustler_rig_preview.tscn")

func _on_open_sp1_crowd_viewer() -> void:
	AudioBus.play_tap()
	DebugLog.add("debug: open SP1 crowd viewer")
	get_tree().change_scene_to_file("res://scenes/sp1_crowd_viewer.tscn")

func _on_play_level_2() -> void:
	AudioBus.play_tap()
	GameState.current_level = 2
	DebugLog.add("debug: play level 2 (Candy Rustler boss)")
	get_tree().change_scene_to_file("res://scenes/level_3d.tscn")

func _on_play_level(n: int) -> void:
	AudioBus.play_tap()
	GameState.current_level = n
	DebugLog.add("debug: play level %d" % n)
	get_tree().change_scene_to_file("res://scenes/level_3d.tscn")

func _on_play_chicken_chase() -> void:
	AudioBus.play_tap()
	DebugLog.add("debug: play chicken chase minigame")
	get_tree().change_scene_to_file("res://scenes/chicken_chase.tscn")

func _on_open_glitz_picker() -> void:
	AudioBus.play_tap()
	DebugLog.add("debug: open glitz picker")
	get_tree().change_scene_to_file("res://scenes/glitz_picker.tscn")

func _on_preview_captive(hero_slug: String, container_slug: String) -> void:
	# Iter 135: extra DebugLog at entry so the COPY log will prove the
	# tap is reaching this handler (user reported buttons seemed unwired).
	DebugLog.add("CAPTIVE BUTTON pressed: hero=%s container=%s" % [hero_slug, container_slug])
	AudioBus.play_tap()
	DebugPreview.pending_captive_hero = hero_slug
	DebugPreview.pending_captive_container = container_slug
	get_tree().change_scene_to_file("res://scenes/level_3d.tscn")

func _on_preview_pushed_wagon(hero_slug: String, container_slug: String, n_pushers: int) -> void:
	DebugLog.add("PUSHED WAGON BUTTON pressed: hero=%s container=%s count=%d" % [hero_slug, container_slug, n_pushers])
	AudioBus.play_tap()
	DebugPreview.pending_captive_hero = hero_slug
	DebugPreview.pending_captive_container = container_slug
	DebugPreview.pending_pushed_count = n_pushers
	get_tree().change_scene_to_file("res://scenes/level_3d.tscn")

func _on_preview_kimmy() -> void:
	DebugLog.add("KIMMY BUTTON pressed")
	AudioBus.play_tap()
	DebugPreview.pending_kimmy = true
	get_tree().change_scene_to_file("res://scenes/level_3d.tscn")

func _on_preview_queen_duel() -> void:
	AudioBus.play_tap()
	GameState.current_level = 6   # canyon terrain + L6 music + queen assets
	DebugPreview.pending_queen_duel = true
	get_tree().change_scene_to_file("res://scenes/level_3d.tscn")

func _on_preview_papageno_duet() -> void:
	AudioBus.play_tap()
	GameState.current_level = 6
	DebugPreview.pending_papageno_duet = true
	get_tree().change_scene_to_file("res://scenes/level_3d.tscn")

func _on_preview_jawbreaker() -> void:
	AudioBus.play_tap()
	GameState.current_level = 4   # mountain terrain + snow + jawbreaker assets
	DebugPreview.pending_jawbreaker = true
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

func _on_reset_splash() -> void:
	if get_node_or_null("/root/AudioBus"):
		AudioBus.play_tap()
	# Clear the persisted "full intro seen" flag so the full ~48s cinematic
	# plays again on next launch (splash.gd reads user://splash.cfg).
	var cfg := ConfigFile.new()
	cfg.load("user://splash.cfg")
	cfg.set_value("splash", "full_intro_seen", false)
	cfg.save("user://splash.cfg")
	DebugLog.add("debug: reset full splash cinematic — plays on next launch")

func _on_back_pressed() -> void:
	AudioBus.play_tap()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
