extends Control

# Floating HP bar attached above HP-bearing enemies. Iter 31:
#   - 1 pixel per HP, max bar width 100px
#   - Color gradient: green > 60% / yellow > 30% / red below
#   - Background dark gray frame so the bar reads against dust storm /
#     dark playfield without competing with sprite colors
#
# Iter 32+: multi-color cycles for bosses with >100 HP. Each "cycle"
# represents one 100-HP tier; bar fills and resets through cycles in
# different colors so the player can read "this thing has been hit a
# lot" at a glance.
#
# Caller sets max_hp once at _ready and current_hp on each take_bullet_hit.

const BAR_WIDTH_MAX: float = 100.0
const BAR_HEIGHT: float = 8.0
const COLOR_HIGH: Color = Color(0.35, 0.85, 0.32, 0.95)
const COLOR_MID: Color = Color(0.95, 0.85, 0.25, 0.95)
const COLOR_LOW: Color = Color(0.95, 0.25, 0.25, 0.95)
const COLOR_BG: Color = Color(0.05, 0.05, 0.05, 0.7)

@onready var _bg: ColorRect = $Background
@onready var _fg: ColorRect = $Foreground

# Track the values as plain vars; expose set_hp() for callers so the
# property syntax doesn't fight with @onready ordering on scene load.
var _max_hp: int = 10
var _current_hp: int = 10

func _ready() -> void:
	if _bg:
		_bg.color = COLOR_BG
	_redraw()

# Initialize the bar with a max HP value. Call once after instancing.
func init(max_hp: int) -> void:
	_max_hp = maxi(1, max_hp)
	_current_hp = _max_hp
	_redraw()

# Update the bar to the current HP value. Call from take_bullet_hit.
func set_hp(current_hp: int) -> void:
	_current_hp = clampi(current_hp, 0, _max_hp)
	_redraw()

func _redraw() -> void:
	if _bg == null or _fg == null:
		return
	var capped_max: float = minf(float(_max_hp), BAR_WIDTH_MAX)
	_bg.size = Vector2(capped_max, BAR_HEIGHT)
	var pct: float = float(_current_hp) / float(_max_hp)
	_fg.size = Vector2(capped_max * pct, BAR_HEIGHT)
	if pct > 0.6:
		_fg.color = COLOR_HIGH
	elif pct > 0.3:
		_fg.color = COLOR_MID
	else:
		_fg.color = COLOR_LOW
