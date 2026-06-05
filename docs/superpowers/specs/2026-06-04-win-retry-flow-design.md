# Win / Retry Flow — Design Spec

**Date:** 2026-06-04
**Status:** Approved design (pre-implementation)
**Goal:** Replace the bare win/fail overlays with a polished, Candy-Crush-style end-of-level experience — bounce-in modals, a candy star-rating, heart-cookie lives with personality, and a celebratory return to the level-select map — with no IAP.

---

## 1. Scope & vocabulary

This feature covers everything from the moment a level ends until the player is back on the map with progress shown. It is one cohesive experience built from these units:

- **Win modal** — shown when the level's goal is met.
- **Fail modal** — shown when the posse hits zero.
- **StarRating** — the candy star-rating widget (candies-on-a-dish) shared by the modals and the map orbs.
- **HeartCookieRow** — heart-cookie lives display with dancing / lonely personality + regen pop, shared by main menu, modals, and in-level HUD.
- **Level data + persistence** — per-level star thresholds and saved best results; progression handoff to the map.
- **Map celebration** — on returning after a win, the next orb lights up (gold dust) and the cowboy walks to it.

Out of scope (explicitly): any in-app purchase, buying lives/gold, leaderboards, and animated cut-scenes beyond the modal/map polish described here.

---

## 2. Star rating (StarRating widget)

**Concept:** a rating of 1–3 **star-shaped candies seated in a top-down oval boat dish**. The candy *type* is chosen by the level's difficulty band; the *count* is the stars earned.

**Difficulty → candy mapping** (LevelDef.difficulty 1–4):

| Difficulty | Candy sprite |
|---|---|
| 1 Peppermint (Easy) | Peppermint spiral star |
| 2 Fireball (Medium) | Gold swirl star |
| 3 Jellybean (Hard) | Cherry gummy star |
| 4 Liquorice (Extreme) | Día de los Muertos sugar star |

**Layout:** the oval boat dish is a single sprite drawn top-down (no front/back occlusion needed). 1/2/3 candies rest in the well at fixed slot positions (1 → centre; 2 → left+right; 3 → left+centre+right with the centre slightly larger). Each candy has a soft elliptical **contact shadow** beneath it (a separate dim ellipse sprite) so it reads as seated, not floating.

**Earned vs unearned:** earned candies are the full candy sprite and **breathe** (gentle scale pulse ~1.0↔1.06, ~1.9 s, staggered per slot). An unearned slot shows a faint "ghost" star (low-opacity outline) in that position.

**Earning rule — per-level bounty thresholds.** Each level defines three ascending bounty cutoffs `[t1, t2, t3]`. Final stars = number of cutoffs the run's bounty meets or exceeds (0 cutoffs met is impossible on a win — winning always grants ≥1 star, so `t1` should be reachable by simply finishing). The win modal also shows progress toward the next threshold.

**Where used:** the win modal (animated reveal), and each completed level's map orb (static, showing best-earned stars).

---

## 3. Heart-cookie lives (HeartCookieRow)

Replaces the current vector-drawn `HeartRow` (procedural `_draw_heart`) with a sprite-based, animated row.

**Sprites:** full = a frosted red/pink **heart cookie**; empty = a plain **dough heart cookie**. Current/max drives how many are full (left-aligned full, remainder empty), same contract as today's `set_hearts(current, maximum)`.

**Personality:**
- **2+ full hearts → dancing together.** Each full heart-cookie does a gentle hop + tilt sway with squash-stretch on landing, staggered per heart so the row ripples like dance partners. Calm tempo (~2.2 s cycle) so it is charming background motion, not distracting. Empty dough cookies do **not** dance.
- **Exactly 1 full heart → lonely.** The single heart slumps, sways slowly and sadly, is slightly desaturated/dimmed, with an occasional small shiver.

**Regen pop + cheer.** When `GameState` regenerates a heart (an empty slot becomes full), that slot plays a one-shot: the dough cookie fades out and the frosted heart **pops in** with a scale-overshoot bounce and a **sugar-sparkle burst**, accompanied by a short **cheer SFX** (new ElevenLabs effect, e.g. a warm "yee-haw"/celebration ~0.8 s). This fires wherever the row is visible when regen occurs (and at minimum on the main menu / map where the player waits for hearts).

**Where used:** main menu (2D splash), win/fail modals, and the in-level HUD — all swap to `HeartCookieRow`.

**In-level placement (changed).** The lives are currently drawn on the bottom **Quake bar**. They move OFF the Quake bar to a dedicated **organic candy cutout** badge anchored in the **top-left of the gameplay viewport** — a **wrapped-taffy** frame (twist-ended caramel/cream candy with a flat center panel) that the heart cookies sit and dance inside. The cutout is a fixed UI sprite on the HUD `CanvasLayer`; the `HeartCookieRow` is parented inside it. Remove the Quake-bar hearts entirely.

---

## 4. Win modal

A panel that **bounces in** (scale-overshoot from ~0.2 → 1.0 with an elastic ease) over a dimmed, blurred freeze of the gameplay behind it.

**Contents, top to bottom:**
1. **"LEVEL COMPLETE!"** ribbon banner (candy pink).
2. **StarRating** widget. Reveal sequence: dish drops in, then earned candies pop onto the dish one at a time (small bounce + a sparkle + a soft "ding" per star), escalating pitch per star.
3. **Bounty** label + an **animated count-up** number (rolls from 0 to the run's bounty over ~1 s with a ticking sound) and a **progress bar** toward the next star threshold ("2,050 more for 3 stars"; hidden if already 3 stars).
4. **HeartCookieRow** showing current lives.
5. Primary **CONTINUE** button (green) → go to the level-select map (triggers the map celebration, §7).
6. Secondary row: **REPLAY** (re-enter the same level — costs a heart, same rule as Retry) and **MAP** (go to map without the celebration walk, e.g. if replaying earlier levels).

**On show:** play the existing `win_fanfare` SFX; keep the existing Gold-Rush salute ceremony that already precedes the win banner (the modal replaces the old `WinOverlay` ColorRect, appearing after the salute).

**Persistence on win:** increment `GameState.current_level` (unlock next), compute stars, and persist the level's **best** stars and **best** bounty (max with any previous). Set a one-shot `GameState.just_won_level` handoff so the map knows to celebrate.

---

## 5. Fail modal

Same bounce-in panel, muted palette.

**Contents:**
1. **"POSSE SCATTERED!"** ribbon (cool purple).
2. A sad candy-Western motif (e.g. a lone tumble-candy) — static art, no new rig.
3. **Bounty reached** label + value (no count-up needed; static).
4. **HeartCookieRow** showing current lives.
5. Primary **RETRY** button (orange) — **costs 1 heart**: on press, eat one heart-cookie (a quick "chomp"/crumble animation on the right-most full cookie + a crunch SFX), then reload the level. If the player has **0 hearts**, RETRY is disabled and shows a regen countdown ("full in 24:31"); the only action is MAP.
6. Secondary **MAP** button → level-select (no celebration).

**Heart accounting (reconciliation).** Today `_show_fail()` calls `GameState.spend_heart()` immediately on death. This moves to the **RETRY press** instead, so: entering a level is free, dying just shows the modal, and the heart is spent (with the chomp animation) only when the player chooses to retry. `_show_fail()` no longer spends a heart.

---

## 6. Level data + persistence

**LevelDef** gains:
- `@export var star_thresholds: Array[int] = [0, 0, 0]` — ascending bounty cutoffs for 1/2/3 stars. Levels 1–4 get hand-tuned starter values; `t1` reachable by finishing.

**GameState** gains/changes:
- Persist `current_level` to `gamestate.cfg` (currently only hearts + bounty are saved — winning must survive an app restart).
- `level_best: Dictionary` mapping level number → `{stars:int, bounty:int}`, persisted; updated with the max on each win. Drives the map orbs' displayed stars.
- `just_won_level: int = 0` — transient (not persisted) handoff so `level_select` knows to play the celebration on its next `_ready`.
- A signal or existing `hearts_changed` hook the `HeartCookieRow` uses to detect a regen (current increased) and fire the pop+cheer.

---

## 7. Map celebration (level_select)

Reuses the map's existing walk machinery (`_walking`, `_walk_step`, `_cowboy_s`, `_focus_level`, and the orb visuals).

**On `level_select._ready`,** if `GameState.just_won_level > 0`:
1. Start the cowboy standing on the **just-completed** orb (the old focus), not the new one.
2. The **newly-unlocked** orb animates active: a **gold-dust burst** + the orb "lights up" (its existing breathe/glow turned on), with a small chime.
3. The cowboy **walks along the path** from the completed orb to the new current orb (existing `_walk_step` pan+stride), arriving as the orb finishes lighting.
4. Clear `just_won_level` so it plays once.

If `just_won_level == 0` (normal entry), behaviour is unchanged (focus snaps to the current orb).

**Star count on completed orbs.** Every completed level's candy orb on the map shows its **best earned star count** from `GameState.level_best` — a small static StarRating (the difficulty's candies on the boat dish, 1–3 filled) tucked under/over the orb. Uncompleted/locked orbs show no stars. After a win celebration, the just-completed orb updates to its new best.

---

## 8. Assets

Locked source art (green-screen renders) is staged at `docs/superpowers/assets/winflow_2026-06-04/`:
`g_pepper, g_hard, g_gummy, g_sugar` (star candies), `td_oval` (dish), `heart_full`, `heart_empty`, `cutout_taffy` (top-left hearts frame).

Production pipeline: green-key each (the keyer used in brainstorm: greenness `G − max(R,B)` with despill + alpha feather), autocrop, export to `godot/assets/sprites/ui/winflow/` as clean transparent PNGs, and add Godot `.import` sidecars. A small contact-shadow ellipse sprite is authored (or drawn at runtime). The dish needs **no** back/front split (top-down). One new SFX (`heart_regen_cheer`) via the ElevenLabs pipeline into `godot/assets/sfx/creatures/`.

---

## 9. Testing & verification

- **GUT (pure logic):** star computation from bounty vs thresholds (0/below-t1 → handled, ≥t1/t2/t3 → 1/2/3); `level_best` max-merge; `current_level` + `level_best` persistence round-trip through `gamestate.cfg`; heart spend-on-retry accounting; regen detection (current increased).
- **sp1-screenshot stills:** win modal, fail modal, and the map mid-celebration — via the temporary force-state debug hooks, removed before commit. Confirms layout, seated candies, heart row, ghost star.
- **Device:** the motion-dependent parts — bounce-in, star reveal, count-up, dancing/lonely hearts, regen pop+cheer, and the cowboy's celebration walk — verified on a sideload.

---

## 10. Component boundaries (for the plan)

- `StarRating` (new scene/script): input = difficulty + earned + (optional) reveal-animate flag; no game-state knowledge.
- `HeartCookieRow` (new scene/script, replaces `HeartRow`): input = `set_hearts(current, max)` + a `play_regen(slot)` call; owns dance/lonely/pop animations.
- `WinModal` / `FailModal` (new scenes/scripts): compose StarRating + HeartCookieRow + buttons; emit `continue/replay/retry/map` signals. No direct scene-changes inside the widget — the level owns transitions.
- `level_3d`: builds the modal, feeds it data, handles the button signals (scene changes, heart spend, persistence writes).
- `level_select`: reads `just_won_level` and plays the celebration; reads `level_best` for orb stars.
- `LevelDef` / `GameState`: data + persistence only.
