extends RefCounted

# Pure-function utility for clamping the cowboy's X position to playable
# lane bounds. Lives in its own class so the clamping logic is testable
# without spinning up a scene tree.

const MARGIN_X: float = 80.0
const VIEWPORT_WIDTH: float = 1080.0

# Clamp an X position into [MARGIN_X, VIEWPORT_WIDTH - MARGIN_X]. Keeps
# the cowboy from clipping into screen edges.
static func clamp_x(x: float) -> float:
	return clampf(x, MARGIN_X, VIEWPORT_WIDTH - MARGIN_X)

# Normalize an X position to a [0..1] lane offset. Useful for future
# lane-snap logic; not currently called by gameplay but tested so the
# helper is ready when needed.
static func normalize_x(x: float) -> float:
	var inner_width: float = VIEWPORT_WIDTH - 2.0 * MARGIN_X
	return clampf((x - MARGIN_X) / inner_width, 0.0, 1.0)
