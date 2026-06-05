class_name WinModal
extends Control

# Soda-Crush candy win panel: tinted achievement-header pill, spinning gold
# sunburst behind a big star rating, bounty count-up + next-star progress,
# heart cookies, and chunky CONTINUE / REPLAY / MAP buttons. Emits signals;
# the level owns the actual transitions.

signal continue_pressed
signal replay_pressed
signal map_pressed

@onready var _panel: Control = $Panel
@onready var _header_pill: TextureRect = $Panel/HeaderPill
@onready var _header_label: Label = $Panel/HeaderPill/HeaderLabel
@onready var _sunburst: TextureRect = $Panel/Sunburst
@onready var _stars: StarRating = $Panel/StarRating
@onready var _score: Label = $Panel/Score
@onready var _next: Label = $Panel/NextLabel
@onready var _progress: ProgressBar = $Panel/NextProgress
@onready var _hearts: HeartCookieRow = $Panel/HeartCookieRow
@onready var _cowboy: TextureRect = $Panel/Cowboy

# difficulty: LevelDef.difficulty; run_bounty: this level's bounty; stars: 1..3;
# next_needed: bounty for the next star (0 = already maxed); hearts/max: lives;
# header: {"text": String, "color": Color} from GameState.win_header.
func show_win(difficulty: int, run_bounty: int, stars: int, next_needed: int,
		hearts: int, hearts_max: int, header: Dictionary = {}) -> void:
	visible = true
	if get_node_or_null("/root/AudioBus") and AudioBus.has_method("play_sfx"):
		AudioBus.play_sfx("win_fanfare_candy")
	# Header banner pill, tinted by achievement colour.
	var htext: String = header.get("text", "SWEET SHOT!")
	var hcolor: Color = header.get("color", Color(1.0, 0.62, 0.17))
	_header_label.text = htext
	_header_pill.modulate = hcolor
	_hearts.set_hearts(hearts, hearts_max)
	# Next-star progress + label.
	if next_needed <= 0:
		_next.text = "★ TOP RATING ★"
		_progress.visible = false
	else:
		_next.text = "%d more for the next star" % next_needed
		_progress.visible = true
		_progress.max_value = run_bounty + next_needed
		_progress.value = 0
	_stars.set_rating(difficulty, stars, true)
	_spin_sunburst()
	_bounce_in()
	_cowboy_pop_in()
	_count_up(run_bounty, next_needed)

func _cowboy_pop_in() -> void:
	if _cowboy == null:
		return
	_cowboy.pivot_offset = _cowboy.size * Vector2(0.5, 1.0)
	_cowboy.scale = Vector2(0.2, 0.2)
	var t := _cowboy.create_tween()
	t.tween_interval(0.25)
	t.tween_property(_cowboy, "scale", Vector2.ONE, 0.55) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _spin_sunburst() -> void:
	if _sunburst == null:
		return
	_sunburst.pivot_offset = _sunburst.size * 0.5
	var t := create_tween().set_loops()
	t.tween_property(_sunburst, "rotation", TAU, 18.0).from(0.0)

func _bounce_in() -> void:
	_panel.scale = Vector2(0.2, 0.2)
	_panel.pivot_offset = _panel.size * 0.5
	var t := _panel.create_tween()
	t.tween_property(_panel, "scale", Vector2.ONE, 0.6) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

var _count_next_needed: int = 0

func _count_up(target: int, next_needed: int) -> void:
	_count_next_needed = next_needed
	_score.text = "0"
	var t := create_tween()
	t.tween_method(_count_step, 0.0, float(target), 1.0)

func _count_step(v: float) -> void:
	if not is_instance_valid(_score):
		return
	_score.text = "%d" % int(v)
	if _count_next_needed > 0 and is_instance_valid(_progress):
		_progress.value = v

func _on_continue() -> void: emit_signal("continue_pressed")
func _on_replay() -> void: emit_signal("replay_pressed")
func _on_map() -> void: emit_signal("map_pressed")
