extends Node

# Autoloaded singleton holding state for cross-scene debug previews.
# The debug menu sets one of these fields, then changes scene to the
# level. Level.gd's _ready reads the field, fires the requested effect,
# and clears the field so a subsequent normal-launch isn't affected.
#
# Available ONLY when OS.has_feature("debug") is true — release builds
# don't expose the debug menu UI that sets these, so the autoload is
# inert but harmless. Cheaper to leave it always-mounted than to
# conditionally register.

# Set to a rush ID ("A","B","D","E","F","G","H") to fire that rush
# immediately on level load. Empty string = no debug preview pending,
# normal gameplay flow.
var pending_rush: String = ""

# Set true to activate Jelly Bean Frenzy (Sugar Rush) immediately on
# level load — same effect as picking up the jelly_frenzy bonus barrel.
var pending_sugar_rush: bool = false

# Future: set to a weapon slug to start the level with that weapon
# already equipped. Empty = default Jelly Bean Six-Shooter.
var pending_weapon: String = ""

# Future: set to a posse member slug to spawn that special dude in
# the level immediately. Empty = no special unlock.
var pending_posse_unlock: String = ""

# Iter 46: when true, level.gd clears all gates/barrels/enemies and
# replaces them with a stationary 6×6 cactus grid for weapon testing.
# Adds a side-panel of debug buttons (EQUIP RIFLE, +/-1 DUDE) so the
# user can iterate weapon-feel + posse-formation tests in isolation.
# Posse is made invulnerable to keep the test loop running.
var pending_test_range: bool = false

# Iter 133/134: pending captive hero + pushed-wagon previews. The
# debug-menu wagon button was logging but the scene was crashing
# silently because these fields weren't declared on the autoload —
# debug_menu.gd set them as dynamic properties (succeeds), but
# level_3d._ready's read raised 'Invalid get index' and bounced the
# user back to main_menu. Declaring them here fixes the read path.
var pending_captive_hero: String = ""
var pending_captive_container: String = ""
var pending_pushed_count: int = 0
# kimmy: preview the Rainbow Kimmy rescue + sugar rush (equips RAINBOW + spawns her cage).
var pending_kimmy: bool = false
# Level-6 sing minigames: jump straight to the Queen sing-duel (mode modal
# included) or the Papageno tutorial duet, skipping the canyon run-up.
var pending_queen_duel: bool = false
var pending_papageno_duet: bool = false

# Called by level.gd after consuming a pending field so back-to-back
# debug launches don't leak state across scenes.
func clear() -> void:
	pending_rush = ""
	pending_sugar_rush = false
	pending_weapon = ""
	pending_posse_unlock = ""
	pending_test_range = false
	pending_captive_hero = ""
	pending_captive_container = ""
	pending_pushed_count = 0
	pending_kimmy = false
	pending_queen_duel = false
	pending_papageno_duet = false

# True if any preview is pending. Level.gd can short-circuit normal
# gate/boss spawning when this is true (so the rush plays in an
# uncluttered scene).
func has_pending() -> bool:
	return pending_rush != "" or pending_sugar_rush or \
		pending_weapon != "" or pending_posse_unlock != "" or \
		pending_test_range or pending_captive_hero != "" or pending_kimmy or \
		pending_queen_duel or pending_papageno_duet
