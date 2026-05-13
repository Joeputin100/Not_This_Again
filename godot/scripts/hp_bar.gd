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
	# Iter 40: hide bar entirely while at full health — only revealed once
	# the entity has been damaged.
	visible = _current_hp < _max_hp
	var capped_max: float = minf(float(_max_hp), BAR_WIDTH_MAX)
	_bg.size = Vector2(capped_max, BAR_HEIGHT)
	# Iter 55: multi-color HP cycles for high-HP bosses. When _max_hp
	# exceeds BAR_WIDTH_MAX (100), the bar represents one "tier" — full
	# bar = 100 HP. As hp ticks down through each tier, the bar's color
	# cycles: gold (4th tier) → silver (3rd) → bronze (2nd) → red (1st).
	# Player reads "this thing has 3 more tiers to go" at a glance.
	var hp_per_tier: float = BAR_WIDTH_MAX  # 100 HP per fill
	if float(_max_hp) > hp_per_tier:
		var remaining: float = float(_current_hp)
		var tier_max: float = float(_max_hp)
		# Which tier we're in: tier 0 = final tier (red), highest = full HP.
		var tier_idx: int = int(floor((remaining - 1.0) / hp_per_tier))
		var tier_remainder: float = remaining - float(tier_idx) * hp_per_tier
		var pct: float = tier_remainder / hp_per_tier
		_fg.size = Vector2(hp_per_tier * pct, BAR_HEIGHT)
		# Tier colors — cycle for >100 HP bosses.
		var tier_colors: Array[Color] = [
			Color(0.95, 0.25, 0.25, 0.95),  # tier 0: red (final tier)
			Color(0.78, 0.45, 0.18, 0.95),  # tier 1: bronze
			Color(0.78, 0.78, 0.80, 0.95),  # tier 2: silver
			Color(0.95, 0.78, 0.30, 0.95),  # tier 3: gold
			Color(0.55, 0.85, 1.00, 0.95),  # tier 4: sapphire
			Color(0.85, 0.55, 1.00, 0.95),  # tier 5: amethyst
		]
		_fg.color = tier_colors[mini(tier_idx, tier_colors.size() - 1)]
		# Background sized to one full tier (not the entire _max_hp width).
		_bg.size = Vector2(hp_per_tier, BAR_HEIGHT)
	else:
		# Single-tier behavior — green/yellow/red gradient by percentage.
		var pct: float = float(_current_hp) / float(_max_hp)
		_fg.size = Vector2(capped_max * pct, BAR_HEIGHT)
		if pct > 0.6:
			_fg.color = COLOR_HIGH
		elif pct > 0.3:
			_fg.color = COLOR_MID
		else:
			_fg.color = COLOR_LOW
