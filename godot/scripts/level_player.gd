class_name LevelPlayer
extends RefCounted

# SP2: plays a level's timeline. Holds events sorted by distance and, as the
# world's scrolled `distance` advances, returns the events newly crossed (each
# exactly once). Pure logic — gameplay feeds the distance + dispatches the
# returned events to the existing _spawn_* functions.
var _events: Array = []
var _cursor: int = 0
var distance: float = 0.0

func _init(events: Array = []) -> void:
	_events = events.duplicate()
	_events.sort_custom(func(a, b): return a.distance < b.distance)

# Advance to an absolute distance; return the events crossed since the last call.
func advance(to_distance: float) -> Array:
	distance = to_distance
	var due: Array = []
	while _cursor < _events.size() and _events[_cursor].distance <= to_distance:
		due.append(_events[_cursor])
		_cursor += 1
	return due
