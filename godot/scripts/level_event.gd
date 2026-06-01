class_name LevelEvent
extends Resource

# SP2: one entry on a level's distance-indexed timeline. `kind` selects which
# gameplay piece to spawn/trigger as the scrolled distance crosses `distance`;
# `params` carries the kind-specific args (see the SP2 spec). Plain data —
# gameplay (level_3d._dispatch_level_event) dispatches on it.
enum EventKind { OUTLAW, GATE, PROP, BONUS, PUSHED_WAGON, BOSS, GOLD_RUSH, PACING, APPROACH_ZONE, HOLE }

@export var distance: float = 0.0           # world distance from level start at which it fires
@export var kind: int = EventKind.OUTLAW
@export var params: Dictionary = {}
