class_name JawbreakerState
extends RefCounted

# Pure combat logic for the Level-4 Jawbreaker boss (Boulder-Brute): the
# ~10s charge->blast cycle, phase escalation at 50% HP, shell-shed thresholds,
# and the phase-based blast payload. No nodes — unit-testable headless on CI
# (the RaisinKiddState / QueenDuelState pattern).
# Spec: docs/superpowers/specs/2026-06-05-jawbreaker-boss-design.md (§4b, §11.3).
#
# level_3d.gd drives rendering/VO/posse-drain from the events:
#   tick(delta)        -> ["charge_start", "blast"]
#   apply_damage(n)    -> ["shed", "phase2", "defeat"]
#   blast_payload(p)   -> {freeze: secs, loss: followers}

const MAX_HP := 400
const BLAST_INTERVAL := 10.0       # phase-1 cycle length
const BLAST_INTERVAL_P2 := 7.5     # phase-2 cycles faster
const CHARGE_T := 1.8              # telegraph window before release
const PHASE2_FRAC := 0.5
const SHED_FRACS: Array = [0.75, 0.5, 0.25]   # shell cracks off at these HP fracs
const P1_FREEZE := 1.5
const P1_LOSS := 3
const P2_FREEZE := 0.8
const P2_LOSS_FRAC := 0.12
const P2_LOSS_MIN := 4

var hp: int = MAX_HP
var phase: int = 1
var charging: bool = false

var _blast_t: float = BLAST_INTERVAL
var _sheds_done: int = 0
var _defeated: bool = false

func is_over() -> bool:
	return _defeated

func blast_interval() -> float:
	return BLAST_INTERVAL_P2 if phase == 2 else BLAST_INTERVAL

# Advance the charge->blast cycle. Returns events for the driver.
func tick(delta: float) -> Array:
	if _defeated:
		return []
	var events: Array = []
	_blast_t -= delta
	if not charging and _blast_t <= CHARGE_T:
		charging = true
		events.append("charge_start")
	if _blast_t <= 0.0:
		charging = false
		_blast_t = blast_interval()
		events.append("blast")
	return events

# What this phase's blast does to a posse of `posse_count`.
func blast_payload(posse_count: int) -> Dictionary:
	if phase == 2:
		return {"freeze": P2_FREEZE,
			"loss": maxi(P2_LOSS_MIN, int(posse_count * P2_LOSS_FRAC))}
	return {"freeze": P1_FREEZE, "loss": P1_LOSS}

# Apply bullet damage. Emits shed (once per threshold), phase2 (once),
# defeat (once).
func apply_damage(amount: int) -> Array:
	if _defeated:
		return []
	var events: Array = []
	var before: int = hp
	hp = maxi(0, hp - amount)
	while _sheds_done < SHED_FRACS.size() \
			and before > int(MAX_HP * SHED_FRACS[_sheds_done]) \
			and hp <= int(MAX_HP * SHED_FRACS[_sheds_done]):
		_sheds_done += 1
		if not events.has("shed"):
			events.append("shed")
	if phase == 1 and hp <= int(MAX_HP * PHASE2_FRAC):
		phase = 2
		events.append("phase2")
	if hp <= 0:
		_defeated = true
		events.append("defeat")
	return events
