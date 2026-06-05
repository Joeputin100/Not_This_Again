# Rainbow Kimmy Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A missable, high-effort rescue set-piece on Level 3 — free the caged peppermint stallion with a new Rainbow weapon; on rescue she becomes Rainbow Kimmy and unleashes a Skittles screen-clear + guitar riff.

**Architecture:** New content on three existing systems in `level_3d.gd`: the **FireMode weapon** system (a new `RAINBOW` mode + a designer-placed crate), the **captive-hero/`_cart_encounter`** mechanic (the cage that halts the scroll + has HP), and the **Gold-Rush flourish** system (`_rush_kimmy` + `FlourishBanner`). The three GUT-testable rules (cage Rainbow-only damage, rescue outcome, screen-clear target selection) are extracted as pure static helpers; everything else is integration verified by screenshot + device.

**Tech Stack:** Godot 4.6.1, GDScript, GUT (`addons/gut/gut_cmdln.gd`), NB-Pro art (staged at `docs/superpowers/assets/kimmy_2026-06-05/`), ElevenLabs SFX.

---

## Conventions

- **Run all GUT:**
  ```bash
  cd godot && xvfb-run -a "$HOME/.local/bin/godot" --headless --path . \
    -s res://addons/gut/gut_cmdln.gd -gconfig=res://.gutconfig.json -gexit 2>&1 | tail -20
  ```
  Success: `All tests passed!`, exit 0. The `-gtest=` flag is IGNORED here; to run one file use `-gdir=res://test -gprefix=test_<prefix>`. `RID allocations ... leaked at exit` lines are pre-existing noise.
- **Screenshot a scene:** `.claude/skills/sp1-screenshot/capture.sh res://scenes/<scene>.tscn /tmp/<name>.png` then Read the PNG.
- **GDScript edits:** Edit-tool tab matching is unreliable here; use a Python `str.replace` script asserting `count==1` (GDScript uses TABS).
- Branch: work on `kimmy` (created before Task 1). Commit after each task with the shown message.

---

## File Structure

**Create:**
- `tools/kimmy_assets.py` — one-shot green-key of the 4 staged kimmy PNGs into `godot/assets/sprites/props/`.
- `godot/assets/sprites/props/{kimmy_caged,kimmy_rainbow,bonus_crate_rainbow,candy_rainbow}.png` (+ `.import`).
- `godot/test/test_kimmy_rules.gd` — GUT for the 3 pure rules.

**Modify:**
- `godot/scripts/level_3d.gd` — `FireMode.RAINBOW` + per-mode maps; `_collect_bonus` rainbow case; typed-crate spawn; rainbow-bullet meta; the 3 pure helpers + their wiring; `_spawn_kimmy_cage`, the rescue timer/outcome, `_rush_kimmy`; the level-event dispatch for the Kimmy event; DebugPreview hook.
- `godot/scripts/level_event.gd` — (if needed) reuse `PUSHED_WAGON` with a `kimmy` param, else add `EventKind.KIMMY`.
- `godot/resources/levels/level_3.tres` — the Rainbow crate event + the Kimmy cage event.
- `tools/gen_creature_sfx.py` — `kimmy_riff` SFX.
- `godot/scripts/debug_preview.gd` (autoload `DebugPreview`) — a `pending_kimmy` flag.

---

## Phase 0 — Assets

### Task 1: Green-key the Kimmy art into game sprites

**Files:** Create `tools/kimmy_assets.py`; output the 4 PNGs.

- [ ] **Step 1: Write the pipeline** `tools/kimmy_assets.py`:
```python
# tools/kimmy_assets.py — one-shot. Green-keys the staged kimmy art into sprites.
#   python3 tools/kimmy_assets.py
import numpy as np
from PIL import Image, ImageFilter
from pathlib import Path

SRC = Path("docs/superpowers/assets/kimmy_2026-06-05")
DST = Path("godot/assets/sprites/props")
MAP = {"kimmy_caged": "kimmy_caged", "kimmy_rainbow": "kimmy_rainbow",
       "crate_rainbow": "bonus_crate_rainbow", "bullet_rainbow": "candy_rainbow"}

def greenkey(src, low=14, high=52):
    a = np.array(Image.open(src).convert("RGBA")).astype(np.float32)
    R, G, B = a[:, :, 0], a[:, :, 1], a[:, :, 2]
    g = G - np.maximum(R, B)
    alpha = np.clip((high - g) / (high - low), 0, 1) * 255.0
    G2 = G - np.maximum(0, G - np.maximum(R, B)) * 0.9  # despill
    out = a.copy(); out[:, :, 1] = G2; out[:, :, 3] = alpha
    out = np.clip(out, 0, 255).astype(np.uint8)
    al = Image.fromarray(out[:, :, 3]).filter(ImageFilter.GaussianBlur(0.7))
    out[:, :, 3] = np.array(al)
    im = Image.fromarray(out); bb = im.getbbox()
    return im.crop(bb) if bb else im

for stem, name in MAP.items():
    src = SRC / f"{stem}.png"
    if not src.exists(): raise SystemExit(f"missing {src}")
    greenkey(src).save(DST / f"{name}.png"); print("wrote", DST / f"{name}.png")
```

- [ ] **Step 2: Run it + import.**
Run: `cd /home/projects/Not_This_Again && python3 tools/kimmy_assets.py` (expect 4 `wrote` lines), then
`cd godot && xvfb-run -a "$HOME/.local/bin/godot" --headless --path . --import 2>&1 | tail -3`.
Verify the 4 `.png` + `.png.import` exist. Programmatically assert each PNG is RGBA with `alpha.min()==0` and `alpha.max()>200` and dims > 40px. View `kimmy_rainbow.png` composited over a dark bg (Read tool) — confirm clean edges, no green fringe.

- [ ] **Step 3: Commit.**
```bash
git add tools/kimmy_assets.py godot/assets/sprites/props/kimmy_caged.png godot/assets/sprites/props/kimmy_rainbow.png godot/assets/sprites/props/bonus_crate_rainbow.png godot/assets/sprites/props/candy_rainbow.png godot/assets/sprites/props/*kimmy*.import godot/assets/sprites/props/bonus_crate_rainbow.png.import godot/assets/sprites/props/candy_rainbow.png.import
git commit -m "kimmy: green-key art into prop sprites"
```

### Task 2: Add the kimmy_riff SFX

**Files:** Modify `tools/gen_creature_sfx.py`; output `godot/assets/sfx/creatures/kimmy_riff.mp3`.

- [ ] **Step 1:** Add to the `SFX` dict in `tools/gen_creature_sfx.py`:
```python
    "kimmy_riff": (
        "a triumphant 3-second crescendo electric rock guitar riff, building to a "
        "big rockstar power-chord finish, celebratory, energetic",
        3.0,
    ),
```
- [ ] **Step 2: Generate.** `cd /home/projects/Not_This_Again && /home/projects/roguelike/.venv-eleven/bin/python tools/gen_creature_sfx.py 2>&1 | tail -5` (existing slugs skip). Verify `godot/assets/sfx/creatures/kimmy_riff.mp3` is non-empty.
- [ ] **Step 3: Commit.**
```bash
git add tools/gen_creature_sfx.py godot/assets/sfx/creatures/kimmy_riff.mp3
git commit -m "kimmy: add kimmy_riff SFX"
```

---

## Phase 1 — Pure rules (GUT, TDD)

These three static helpers hold the only branchy logic; they go on `level_3d.gd` (no scene deps) and are unit-tested. Wiring them into the live loops is Phases 2–3.

### Task 3: The three Kimmy rules + tests

**Files:** Modify `godot/scripts/level_3d.gd`; create `godot/test/test_kimmy_rules.gd`.

- [ ] **Step 1: Write the failing test** `godot/test/test_kimmy_rules.gd`:
```gdscript
extends GutTest

const L3D = preload("res://scripts/level_3d.gd")

# --- cage damage: Kimmy's cage only takes damage from rainbow bullets ---
func test_cage_takes_rainbow_damage():
	assert_eq(L3D.kimmy_cage_damage(true, true, 5), 5)   # is_kimmy, bullet_rainbow, base
func test_cage_ignores_nonrainbow_on_kimmy():
	assert_eq(L3D.kimmy_cage_damage(true, false, 5), 0)
func test_noncage_captive_takes_any_damage():
	assert_eq(L3D.kimmy_cage_damage(false, false, 5), 5)  # a normal captive is unaffected by the rule

# --- rescue outcome: cracked vs timed_out vs ongoing ---
func test_rescue_cracked_when_hp_zero():
	assert_eq(L3D.kimmy_rescue_outcome(0, 4.0), "cracked")
func test_rescue_timed_out_when_window_elapsed():
	assert_eq(L3D.kimmy_rescue_outcome(50, 0.0), "timed_out")
func test_rescue_ongoing():
	assert_eq(L3D.kimmy_rescue_outcome(50, 4.0), "ongoing")
func test_rescue_cracked_beats_timeout():
	assert_eq(L3D.kimmy_rescue_outcome(0, 0.0), "cracked")  # freeing at the buzzer still counts

# --- screen-clear targets: outlaws + destructible obstacles incl bulls, never the cage ---
func test_clear_includes_outlaw_and_bull():
	assert_true(L3D.kimmy_clears_node({"is_outlaw": true}))
	assert_true(L3D.kimmy_clears_node({"is_bull": true}))
	assert_true(L3D.kimmy_clears_node({}))   # a plain destructible obstacle (no special meta)
func test_clear_excludes_cage_and_captive():
	assert_false(L3D.kimmy_clears_node({"is_captive": true}))
	assert_false(L3D.kimmy_clears_node({"is_kimmy": true}))
	assert_false(L3D.kimmy_clears_node({"dying": true}))
```

- [ ] **Step 2: Run it — expect FAIL.** `-gdir=res://test -gprefix=test_kimmy_rules` (functions not defined).

- [ ] **Step 3: Implement the 3 static helpers** in `level_3d.gd` (near the other statics):
```gdscript
# Rainbow Kimmy: her cage only takes damage from rainbow bullets; non-Kimmy
# captives are unaffected by this rule (base damage passes through).
static func kimmy_cage_damage(is_kimmy: bool, bullet_rainbow: bool, base: int) -> int:
	if is_kimmy and not bullet_rainbow:
		return 0
	return base

# Rainbow Kimmy: rescue resolves to "cracked" (freed) the instant cage HP hits
# 0 (even at the buzzer); else "timed_out" when the window is spent; else "ongoing".
static func kimmy_rescue_outcome(cage_hp: int, window_left: float) -> String:
	if cage_hp <= 0:
		return "cracked"
	if window_left <= 0.0:
		return "timed_out"
	return "ongoing"

# Rainbow Kimmy sugar rush: destroy outlaws + destructible obstacles (incl. bulls);
# never the cage/captive (Kimmy) or already-dying nodes. `meta` = the node's flags.
static func kimmy_clears_node(meta: Dictionary) -> bool:
	if meta.get("is_captive", false) or meta.get("is_kimmy", false) or meta.get("dying", false):
		return false
	return true
```

- [ ] **Step 4: Run it — expect PASS** (10/10). Then full suite — `All tests passed!`.

- [ ] **Step 5: Commit.**
```bash
git add godot/scripts/level_3d.gd godot/test/test_kimmy_rules.gd
git commit -m "kimmy: pure rules (cage rainbow-only dmg, rescue outcome, screen-clear targets) + tests"
```

---

## Phase 2 — Rainbow weapon

### Task 4: FireMode.RAINBOW + per-mode maps + collect

**Files:** Modify `godot/scripts/level_3d.gd`.

- [ ] **Step 1: Add the mode + map entries.** READ each map first, then add a `RAINBOW` entry to EACH of these (match the existing dict style):
  - `enum FireMode { CANDY, RIFLE, FROSTBITE, FRENZY }` → add `, RAINBOW`.
  - `CANDY_BULLET_TEX` → `FireMode.RAINBOW: ["candy_rainbow.png"]` (match the existing value shape — it maps to an Array of filenames under `_CANDY_DIR`; confirm `_CANDY_DIR` and put `candy_rainbow.png` there, or use the props path the others use).
  - `FIRE_INTERVAL_BY_MODE` → `FireMode.RAINBOW: 0.10` · `RANGE_Z_BY_MODE` → `FireMode.RAINBOW: -20.0` · `CLIP_BY_MODE` → `FireMode.RAINBOW: 7`.
  - `WEAPON_NAMES` → `FireMode.RAINBOW: "RAINBOW"` · `WEAPON_ICONS` → `FireMode.RAINBOW: "candy_rainbow.png"` · `WEAPON_COLORS` → `FireMode.RAINBOW: Color(0.7, 0.5, 1.0, 1)`.
  - `WEAPON_HERO` → `FireMode.RAINBOW: "res://assets/sprites/props/weapon_six_shooter.png"` (reuse the six-shooter hero).
  - `BONUS_COLORS` → `"rainbow": Color(0.7, 0.5, 1.0, 1)` · `BONUS_LABELS` → `"rainbow": "★"`.
  *(Confirm the `_CANDY_DIR` base path by reading `_make_candy_billboard`; if `candy_rainbow.png` lives in `assets/sprites/props/`, ensure `CANDY_BULLET_TEX[RAINBOW]` resolves there the way the other modes resolve their files.)*

- [ ] **Step 2: Collect → RAINBOW.** In `_collect_bonus`, add to the `match t:` block:
```gdscript
		"rainbow":   _fire_mode = FireMode.RAINBOW
```
And ensure `BONUS_COLORS[t]`/`BONUS_LABELS[t]` lookups won't KeyError for "rainbow" (covered by Step 1).

- [ ] **Step 3: Verify.** Full GUT suite — `All tests passed!` (no parse error; new enum/map entries load). Confirm `BONUS_TYPES` was NOT modified (rainbow must stay out of the random rotation): `grep -n "const BONUS_TYPES" godot/scripts/level_3d.gd` still shows `["rifle", "frostbite", "frenzy"]`.

- [ ] **Step 4: Commit.**
```bash
git add godot/scripts/level_3d.gd
git commit -m "kimmy: FireMode.RAINBOW weapon + per-mode maps + collect (not in random rotation)"
```

### Task 5: Designer-placed Rainbow crate + rainbow-bullet meta

**Files:** Modify `godot/scripts/level_3d.gd`, `godot/scripts/level_event.gd` (only if BONUS isn't dispatched yet).

- [ ] **Step 1: Typed crate spawn.** `_spawn_bonus()` picks a RANDOM type. Refactor so a specific type can be requested: extract the body into `func _spawn_bonus_typed(t: String) -> void` (everything after the `var t :=` line, using the passed `t`), and make `_spawn_bonus()` call `_spawn_bonus_typed(BONUS_TYPES[_rng.randi() % BONUS_TYPES.size()])`. (READ `_spawn_bonus` first; preserve all the glitz/aura/label logic.)

- [ ] **Step 2: BONUS event dispatch.** In `_dispatch_level_event(ev)` (the `match ev.kind:` block), add/confirm a case:
```gdscript
		LevelEvent.EventKind.BONUS:
			_spawn_bonus_typed(String(ev.params.get("type", "frenzy")))
```
(If a `BONUS` case already exists, make it honor `ev.params["type"]`. This is how the designer places a specific `"rainbow"` crate.)

- [ ] **Step 3: Rainbow-bullet meta.** In `_spawn_bullet_at(world_x, world_z)`, after the bullet node is created, tag rainbow shots so only they damage the cage:
```gdscript
	bullet.set_meta("rainbow", _fire_mode == FireMode.RAINBOW)
```
(READ `_spawn_bullet_at`; add next to the existing `bullet.set_meta("dmg", _volley_dmg)`.)

- [ ] **Step 4: Verify.** Full GUT — `All tests passed!`. The crate visuals + pickup are device/screenshot-verified later.

- [ ] **Step 5: Commit.**
```bash
git add godot/scripts/level_3d.gd godot/scripts/level_event.gd
git commit -m "kimmy: designer-placed Rainbow BONUS crate (typed spawn) + rainbow-bullet meta"
```

---

## Phase 3 — Cage rescue + sugar rush

### Task 6: Wire the cage Rainbow-only damage rule

**Files:** Modify `godot/scripts/level_3d.gd`.

- [ ] **Step 1: Gate `_captive_take_damage`.** READ `_captive_take_damage(captive, bullet_pos)` and the bullet↔captive collision call site (the bullet loop branch where `captive.get_meta("is_captive")` is true — it currently calls `_captive_take_damage`). The collision must pass whether the hitting bullet was rainbow. Change the call site to read the bullet's meta and pass it, and change `_captive_take_damage` to apply the rule:
  - Signature → `func _captive_take_damage(captive: Node3D, bullet_pos: Vector3, bullet_rainbow: bool = false) -> void`.
  - At the top, compute the effective damage via the helper:
    ```gdscript
    var is_kimmy: bool = captive.get_meta("is_kimmy", false)
    var dmg: int = kimmy_cage_damage(is_kimmy, bullet_rainbow, _volley_dmg)
    if dmg <= 0:
        if is_kimmy:
            _kimmy_rainbow_only_cue(bullet_pos)   # Step 2
        return
    ```
  - Then subtract `dmg` from the captive's `hp` meta (replace whatever fixed decrement it used so it respects `dmg`).
  - At the collision call site, pass `bullet.get_meta("rainbow", false)`.

- [ ] **Step 2: The "RAINBOW ONLY" cue (once).** Add:
```gdscript
func _kimmy_rainbow_only_cue(pos: Vector3) -> void:
	if _kimmy_cue_shown:
		return
	_kimmy_cue_shown = true
	_spawn_popup_3d(pos + Vector3(0, 1.5, 0), "RAINBOW ONLY!", Color(0.7, 0.5, 1.0, 1), 56)
```
and a member `var _kimmy_cue_shown: bool = false` (reset when a Kimmy cage spawns).

- [ ] **Step 3: Verify.** Full GUT — `All tests passed!` (the rule itself is already unit-tested in Task 3; this is wiring).

- [ ] **Step 4: Commit.**
```bash
git add godot/scripts/level_3d.gd
git commit -m "kimmy: cage takes damage only from rainbow bullets (+ RAINBOW ONLY cue)"
```

### Task 7: Spawn the Kimmy cage + rescue timer/outcome

**Files:** Modify `godot/scripts/level_3d.gd`, `godot/scripts/level_event.gd`, `godot/resources/levels/level_3.tres` (placement is Task 9; here just the spawn + loop).

- [ ] **Step 1: Constants + state.** Add near the other consts/vars:
```gdscript
const KIMMY_CAGE_HP: int = 600          # high — a sustained Rainbow-fire crack
const KIMMY_RESCUE_WINDOW: float = 16.0 # seconds before the pushers haul her off
var _kimmy_captive: Node3D = null
var _kimmy_window_left: float = 0.0
```

- [ ] **Step 2: Spawn helper.** Reuse `_spawn_captive_hero` (READ its signature `(container_slug, hero_slug, ...)` and how it sets `is_captive`/`hp`/`hp_label` + whether it sets `_cart_encounter` to halt the scroll). Add:
```gdscript
func _spawn_kimmy_cage() -> void:
	_kimmy_cue_shown = false
	# container = the cage-wagon art; hero = the plain caged stallion.
	_kimmy_captive = _spawn_captive_hero("kimmy_cage", "kimmy_caged", KIMMY_CAGE_HP)
	if _kimmy_captive != null:
		_kimmy_captive.set_meta("is_kimmy", true)
	_kimmy_window_left = KIMMY_RESCUE_WINDOW
	# Ensure the world scroll halts while she blocks the path. If _spawn_captive_hero
	# already sets _cart_encounter (the captive/cart mechanic), this is a no-op;
	# otherwise set it here:
	_cart_encounter = true
	if terrain_3d_node != null and terrain_3d_node.has_method("set_scroll_active"):
		terrain_3d_node.set_scroll_active(false)
```
*(READ `_spawn_captive_hero` to confirm the `hero_slug`→sprite path so "kimmy_caged"/"kimmy_cage" resolve to the new PNGs; if the container art slug differs, reuse an existing wagon container slug and set the caged stallion as the hero.)*

- [ ] **Step 3: Per-frame rescue resolution.** In `_process` (where captives/cart are updated), while `_kimmy_captive` is valid:
```gdscript
	if is_instance_valid(_kimmy_captive):
		_kimmy_window_left -= delta
		var hp: int = int(_kimmy_captive.get_meta("hp", 0))
		match kimmy_rescue_outcome(hp, _kimmy_window_left):
			"cracked":
				var freed := _kimmy_captive
				_kimmy_captive = null
				_rush_kimmy(freed)          # Task 8
			"timed_out":
				var lost := _kimmy_captive
				_kimmy_captive = null
				_kimmy_haul_away(lost)
			_:
				pass
```

- [ ] **Step 4: Haul-away (miss, no soft-lock).** Add:
```gdscript
func _kimmy_haul_away(captive: Node3D) -> void:
	var ui: Node = get_node_or_null("UI")
	if ui != null:
		FlourishBanner.spawn(ui, "SHE GOT AWAY")
	if is_instance_valid(captive):
		# slide the cage off to the side and free it
		var t := captive.create_tween()
		t.tween_property(captive, "position:x", captive.position.x - 12.0, 1.0)
		t.tween_callback(captive.queue_free)
	_kimmy_resume_scroll()

func _kimmy_resume_scroll() -> void:
	_cart_encounter = false
	if terrain_3d_node != null and terrain_3d_node.has_method("set_scroll_active"):
		terrain_3d_node.set_scroll_active(true)
```
*(If `FlourishBanner` has no "SHE GOT AWAY" preset, use the plain-text spawn path the other banners use, or add the preset; READ `FlourishBanner` first.)*

- [ ] **Step 5: Verify.** Full GUT — `All tests passed!` (outcome logic unit-tested in Task 3). The encounter is device-verified.

- [ ] **Step 6: Commit.**
```bash
git add godot/scripts/level_3d.gd
git commit -m "kimmy: cage spawn + blocks scroll + rescue timer/outcome + miss haul-away"
```

### Task 8: The sugar rush `_rush_kimmy()`

**Files:** Modify `godot/scripts/level_3d.gd`.

- [ ] **Step 1: Implement.**
```gdscript
func _rush_kimmy(freed_captive: Node3D) -> void:
	# Transform: swap the caged stallion's hero sprite to Rainbow Kimmy + pop.
	if is_instance_valid(freed_captive):
		var hs = freed_captive.get_meta("hero_sprite", null)
		if hs is Sprite3D:
			(hs as Sprite3D).texture = load("res://assets/sprites/props/kimmy_rainbow.png")
			var pop := (hs as Sprite3D).create_tween()
			pop.tween_property(hs, "scale", (hs as Sprite3D).scale * 1.4, 0.25) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# Audio + banner.
	if get_node_or_null("/root/AudioBus") and AudioBus.has_method("play_sfx"):
		AudioBus.play_sfx("kimmy_riff")
	var ui: Node = get_node_or_null("UI")
	if ui != null:
		FlourishBanner.spawn(ui, "RAINBOW KIMMY")
	# Skittles screen-clear: outlaws + destructible obstacles (incl bulls), never the cage/posse.
	_kimmy_skittles_burst()
	for o in outlaws_root.get_children():
		if o is Node3D and kimmy_clears_node(_node_meta_flags(o)):
			_kimmy_zap(o)
	for ob in obstacles_root.get_children():
		if ob is Node3D and kimmy_clears_node(_node_meta_flags(ob)):
			_kimmy_zap(ob)
	# Resolve: free the cage + resume after the riff.
	await get_tree().create_timer(3.0).timeout
	if is_instance_valid(freed_captive):
		freed_captive.queue_free()
	_kimmy_resume_scroll()

# Collect the flags kimmy_clears_node() checks from a live node's meta.
func _node_meta_flags(n: Node) -> Dictionary:
	return {
		"is_outlaw": n.get_meta("is_outlaw", false),
		"is_bull": n.get_meta("is_bull", false),
		"is_captive": n.get_meta("is_captive", false),
		"is_kimmy": n.get_meta("is_kimmy", false),
		"dying": n.get_meta("dying", false),
	}

# Destroy one target with a rainbow burst + bounty, routing outlaws through the
# existing quota chokepoint so the count stays correct.
func _kimmy_zap(n: Node3D) -> void:
	_kimmy_skittles_burst_at(n.position)
	_add_bounty(50)
	if n.get_meta("is_outlaw", false):
		_outlaw_left_field(n)   # decrements _outlaws_remaining via the existing path
	n.queue_free()
```

- [ ] **Step 2: The rainbow particle burst.** Add a cheap in-engine burst (no shaders), used both as a screen-wide wave and per-target:
```gdscript
func _kimmy_skittles_burst() -> void:
	_kimmy_skittles_burst_at(Vector3(0.0, 1.0, COWBOY_Z - 4.0))

func _kimmy_skittles_burst_at(pos: Vector3) -> void:
	var p := CPUParticles3D.new()
	p.position = pos
	p.amount = 24
	p.lifetime = 0.8
	p.one_shot = true
	p.explosiveness = 0.9
	p.emitting = true
	p.direction = Vector3(0, 1, 0)
	p.spread = 80.0
	p.initial_velocity_min = 3.0
	p.initial_velocity_max = 8.0
	p.gravity = Vector3(0, -6, 0)
	p.scale_amount_min = 0.2
	p.scale_amount_max = 0.5
	# rainbow color ramp
	var ramp := Gradient.new()
	ramp.colors = PackedColorArray([Color(1,0.2,0.2), Color(1,0.8,0.2), Color(0.3,1,0.3), Color(0.3,0.6,1), Color(0.7,0.3,1)])
	var gt := GradientTexture1D.new(); gt.gradient = ramp
	p.color_ramp = gt
	popups_root.add_child(p)
	get_tree().create_timer(1.2).timeout.connect(p.queue_free)
```
*(Confirm `COWBOY_Z`/`popups_root` names by reading the file; adjust if different.)*

- [ ] **Step 3: Verify.** Full GUT — `All tests passed!` (target selection unit-tested in Task 3; this is wiring). Visual is device/screenshot-verified.

- [ ] **Step 4: Commit.**
```bash
git add godot/scripts/level_3d.gd
git commit -m "kimmy: _rush_kimmy — transform + Skittles screen-clear (incl bulls) + burst + riff + banner"
```

---

## Phase 4 — Data + preview

### Task 9: Place the encounter in Level 3

**Files:** Modify `godot/scripts/level_event.gd` (only if a new EventKind is needed), `godot/resources/levels/level_3.tres`.

- [ ] **Step 1: Decide the Kimmy event.** READ `level_event.gd` (`EventKind` enum) and `_dispatch_level_event`. Reuse `PUSHED_WAGON` with a `kimmy: true` param if `PUSHED_WAGON` is dispatched; otherwise add `KIMMY` to the enum and a dispatch case:
```gdscript
		LevelEvent.EventKind.KIMMY:
			_spawn_kimmy_cage()
```
(If reusing `PUSHED_WAGON`: in that case branch, `if ev.params.get("kimmy", false): _spawn_kimmy_cage(); return`.)

- [ ] **Step 2: Place events in `level_3.tres`.** READ the existing `level_3.tres` event format (the `SubResource` LevelEvent entries + the `events = Array[...]` line). Add TWO events to its `events` array, BEFORE the boss event's distance:
  - A Rainbow crate: a `BONUS` LevelEvent at an early `distance` (e.g. 30.0) with `params = {"type": "rainbow"}`.
  - The Kimmy cage: the Kimmy event (KIMMY, or PUSHED_WAGON+`{"kimmy": true}`) at a later `distance` (e.g. 55.0) — after the crate, before the boss (boss is at distance 75.0 in level_3.tres).

- [ ] **Step 3: Verify it loads.** Full GUT — `All tests passed!` (no .tres parse error). `grep` confirms the two new events + the boss event are all present.

- [ ] **Step 4: Commit.**
```bash
git add godot/scripts/level_event.gd godot/resources/levels/level_3.tres
git commit -m "kimmy: place Rainbow crate + Kimmy cage in level_3 (before the boss)"
```

### Task 10: DebugPreview hook

**Files:** Modify `godot/scripts/debug_preview.gd`, `godot/scripts/level_3d.gd` (the DebugPreview `_ready` block), and the debug menu if it lists previews.

- [ ] **Step 1: Add the flag.** In `debug_preview.gd` add `var pending_kimmy: bool = false`.
- [ ] **Step 2: Honor it.** In `level_3d.gd` `_ready`, in the `if get_node_or_null("/root/DebugPreview") != null:` block (where `pending_rush`/`pending_captive_hero` are honored), add:
```gdscript
		elif DebugPreview.pending_kimmy:
			DebugPreview.pending_kimmy = false
			_fire_mode = FireMode.RAINBOW   # give the preview the weapon
			_update_weapon_label()
			call_deferred("_spawn_kimmy_cage")
			DebugLog.add("level_3d: kimmy preview")
```
- [ ] **Step 3:** If the debug menu (`debug_menu.gd`/scene) lists preview buttons, add a "Rainbow Kimmy" button that sets `DebugPreview.pending_kimmy = true` then loads `level_3d` (mirror an existing preview button).
- [ ] **Step 4: Verify + screenshot.** Full GUT — `All tests passed!`. Then screenshot via the preview: set the flag through the debug path (or a temporary `_DEBUG` hook calling `_spawn_kimmy_cage()` deferred in `_ready`), capture `res://scenes/level_3d.tscn`, Read the PNG — confirm the caged plain stallion + cage HP bar appear. Remove any temp hook before commit.
- [ ] **Step 5: Commit.**
```bash
git add godot/scripts/debug_preview.gd godot/scripts/level_3d.gd godot/scenes/debug_menu.tscn godot/scripts/debug_menu.gd
git commit -m "kimmy: DebugPreview hook to preview the rescue + rush"
```

---

## Phase 5 — Device pass

### Task 11: Sideload + verify on Level 3

**Files:** none (verification only).

- [ ] **Step 1: Build + distribute.** Commit/push, then:
```bash
git push origin kimmy
scripts/sideload.sh <iterN> && scripts/firebase_distribute.sh /tmp/nta_sideload/nta_iter<N>.apk "kimmy: Rainbow Kimmy rescue + sugar rush on Level 3"
```
- [ ] **Step 2: Verify on device (manual).** On Level 3: the Rainbow crate appears early → equips the Skittles weapon; the cage blocks the path; only Rainbow dents it (others show "RAINBOW ONLY"); cracking it before the timer transforms the stallion into Rainbow Kimmy and fires the Skittles screen-clear (outlaws + barrels + cacti + bulls vanish) with the riff + banner, then the path resumes. Also verify the MISS path: ignore/lack the weapon → she's hauled away, no rush, path still resumes (no soft-lock). Also preview via the debug menu.

---

## Self-Review

**Spec coverage:**
- §2a Rainbow weapon (FireMode + crate + bullet + only-damages-cage) → Tasks 4, 5, 6. ✓
- §2b Cage rescue (captive reuse, high HP + bar, blocks scroll, Rainbow-only dmg + cue, timer, miss→haul-away) → Tasks 6, 7. ✓
- §2c Sugar rush (transform, screen-clear incl bulls, bounty, particles, riff, banner, quota decrement) → Task 8. ✓
- §3 Placement (Level 3 only, crate before cage) → Task 9. ✓
- §4 Assets (4 sprites + riff) → Tasks 1, 2. ✓
- §5 Verification (GUT pure rules, DebugPreview, screenshot, device) → Tasks 3, 10, 11 + per-task. ✓
- §6 Out of scope respected (rainbow NOT in `BONUS_TYPES`; Level 3 only) → Tasks 4 (Step 3 check), 9. ✓

**Placeholder scan:** The integration tasks (5–10) say "READ X first" for the exact call sites (`_captive_take_damage` collision site, `_spawn_captive_hero` slug→sprite path, the BONUS/PUSHED_WAGON dispatch, `FlourishBanner` presets, `COWBOY_Z`/`popups_root` names) — these are real lookups in a 6000-line file, not vague "handle it" placeholders; each names the exact symbol to find and what to do. The three pure rules (the only branchy logic) have complete code + tests.

**Type consistency:** `kimmy_cage_damage(is_kimmy, bullet_rainbow, base)`, `kimmy_rescue_outcome(cage_hp, window_left)`, `kimmy_clears_node(meta)` signatures match between Task 3 (def + tests) and Tasks 6/7/8 (callers). `is_kimmy` meta set in Task 7, read in Tasks 6/8. `rainbow` bullet meta set in Task 5, read in Task 6. `_spawn_bonus_typed(t)` defined Task 5, called Tasks 5/10-context. `_spawn_kimmy_cage`/`_rush_kimmy`/`_kimmy_resume_scroll`/`_kimmy_haul_away`/`_kimmy_skittles_burst_at` consistent across Tasks 7/8/10.
