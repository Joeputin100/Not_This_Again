extends Node

# Autoloaded singleton holding the world's forward-scroll multiplier.
# Iter 42b: the original NTA loop was always-running (constant SCROLL_SPEED
# per entity). New design: the player's vertical finger position controls
# how fast the world comes toward them — top of screen = sprint, middle =
# normal, bottom = slow crawl.
#
# Each scrolling entity (barrels, gates, bull, tumbleweed, etc.) reads
# WorldSpeed.mult on every _process tick and multiplies its per-frame
# velocity by it. Default mult=1.0 means "no change", so tests that
# instantiate entities without level scaffolding behave exactly as
# before (multiplying anything by 1.0 is a no-op).
#
# The mult value is set externally — level.gd's _input + _process compute
# a target based on finger position and lerp toward it for smoothing
# (instant snap would feel jerky on touch).

# Current scroll multiplier read by every scrolling entity.
var mult: float = 1.0

# Where mult is heading. level.gd's _input writes this; _process in this
# autoload lerps mult toward it for smooth transitions.
var target_mult: float = 1.0

# Bounds the target stays within. Sprinting too hard makes obstacles
# unreachable visually; crawling too slow makes the level feel stalled.
const MIN_MULT: float = 0.25
const MAX_MULT: float = 1.7
const NEUTRAL_MULT: float = 1.0

# Lerp speed toward target. Higher = snappier, lower = smoother. 6.0
# gives ~150ms to reach a new target — fast enough to feel responsive,
# slow enough that mid-drag adjustments don't strobe.
const LERP_SPEED: float = 6.0

# Pre-iter-42b call sites can still set mult directly (used by some tests
# + the win/fail flow when scrolling is suspended entirely).
func set_mult(value: float) -> void:
	mult = clampf(value, MIN_MULT, MAX_MULT)
	target_mult = mult

# Set the target the lerp will gradually move mult toward. Called from
# level.gd's _input as the finger moves up/down.
func set_target(value: float) -> void:
	target_mult = clampf(value, MIN_MULT, MAX_MULT)

# Map a touch Y position (0=top, screen_height=bottom) to a mult target.
# Top = MAX_MULT (sprint), bottom = MIN_MULT (slow), middle = NEUTRAL.
# Used by level.gd; kept here so the mapping curve is in one place.
func target_from_touch_y(touch_y: float, screen_height: float) -> float:
	if screen_height <= 0.0:
		return NEUTRAL_MULT
	# 0 → MAX_MULT, screen_height → MIN_MULT, linear in between.
	var t: float = clampf(touch_y / screen_height, 0.0, 1.0)
	return lerpf(MAX_MULT, MIN_MULT, t)

func _process(delta: float) -> void:
	# Smooth approach to target. Frame-rate independent thanks to delta.
	mult = lerpf(mult, target_mult, clampf(LERP_SPEED * delta, 0.0, 1.0))

# Reset to neutral on level scene transitions so a new level starts at
# normal speed regardless of where the player's finger was when the
# previous level ended.
func reset() -> void:
	mult = NEUTRAL_MULT
	target_mult = NEUTRAL_MULT
