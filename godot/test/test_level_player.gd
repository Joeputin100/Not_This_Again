extends GutTest

# SP2 slice 1 — the data-driven level spine: LevelEvent (timeline entry),
# LevelPlayer (fires events as the scrolled distance crosses them), and the
# LevelDef goal/events additions.

const LevelEvent = preload("res://scripts/level_event.gd")
const LevelPlayer = preload("res://scripts/level_player.gd")
const LevelDef = preload("res://scripts/level_def.gd")

func _ev(dist: float, kind: int) -> LevelEvent:
	var e := LevelEvent.new()
	e.distance = dist
	e.kind = kind
	return e

func test_level_event_holds_fields():
	var e := LevelEvent.new()
	e.distance = 75.0
	e.kind = LevelEvent.EventKind.BOSS
	e.params = {"boss": "pete"}
	assert_eq(e.distance, 75.0)
	assert_eq(e.kind, LevelEvent.EventKind.BOSS)
	assert_eq(e.params.get("boss"), "pete")

func test_fires_due_events_sorted_once_only():
	# input intentionally out of distance order
	var p := LevelPlayer.new([_ev(75.0, LevelEvent.EventKind.BOSS), _ev(10.0, LevelEvent.EventKind.OUTLAW)])
	assert_eq(p.advance(5.0).size(), 0, "nothing before the first event")
	var due := p.advance(12.0)
	assert_eq(due.size(), 1, "one event crossed at 12")
	assert_eq(due[0].kind, LevelEvent.EventKind.OUTLAW, "earliest fires first")
	due = p.advance(80.0)
	assert_eq(due.size(), 1, "boss crossed at 80")
	assert_eq(due[0].kind, LevelEvent.EventKind.BOSS)
	assert_eq(p.advance(999.0).size(), 0, "no event re-fires")

func test_multiple_cross_in_one_advance():
	var p := LevelPlayer.new([_ev(10.0, LevelEvent.EventKind.OUTLAW), _ev(20.0, LevelEvent.EventKind.GATE)])
	var due := p.advance(50.0)
	assert_eq(due.size(), 2, "both crossed in one jump")
	assert_eq(due[0].distance, 10.0, "returned in distance order")

func test_leveldef_has_events_and_goal():
	var d := LevelDef.new()
	d.goal = LevelDef.Goal.DEFEAT_BOSS
	d.events = [_ev(75.0, LevelEvent.EventKind.BOSS)]
	assert_eq(d.goal, LevelDef.Goal.DEFEAT_BOSS)
	assert_eq(d.events.size(), 1)
