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

# Called by level.gd after consuming a pending field so back-to-back
# debug launches don't leak state across scenes.
func clear() -> void:
	pending_rush = ""
	pending_sugar_rush = false
	pending_weapon = ""
	pending_posse_unlock = ""

# True if any preview is pending. Level.gd can short-circuit normal
# gate/boss spawning when this is true (so the rush plays in an
# uncluttered scene).
func has_pending() -> bool:
	return pending_rush != "" or pending_sugar_rush or \
		pending_weapon != "" or pending_posse_unlock != ""
