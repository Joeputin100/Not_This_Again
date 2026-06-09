# Level 6 — "The Magic Flute" / Queen of the Night — Design Spec

**Date:** 2026-06-08
**Status:** Design approved in chat (niche, answer-input, setting, Papageno role, audio approach all signed off). Concept art in progress. Ready for spec review → writing-plans.
**Related:** [[project_queen_of_the_night_boss]], [Raisin Kidd boss](2026-06-06-raisin-kidd-boss-design.md), [Rainbow Kimmy set-piece](2026-06-04-rainbow-kimmy-design.md), [[project_level_themes_and_gold_rush]], [[project_candy_theme]].

---

## 1. Concept

Level 6 is a full **Mozart *Die Zauberflöte* (The Magic Flute)** candy level. You run a **starlit licorice canyon** — Papageno the bird-catcher's domain, alive with colorful candy songbirds — toward a showdown with the **Queen of the Night**, fought as an **operatic call-and-response sing-duel** riding her vengeance aria *Der Hölle Rache*. The comic **Papageno/Papagena "Pa-pa-pa" duet** appears mid-canyon as a gentle tutorial for the duel mechanic.

The Queen fills a combat niche none of the other five bosses occupy:

| Boss | Level | Niche |
|------|-------|-------|
| Pete | 1 | stationary ranged duel |
| Candy Rustler | 2 | fast contact melee |
| Cotton Candy trio | 3 | sticky crowd-control |
| Jawbreaker | 4 | slow brute + AOE |
| Raisin Kidd | 5 | deflect-and-counter timing |
| **Queen of the Night** | **6** | **musical call-and-response gesture duel** |

She is the showcase boss: the only fight built entirely around **music ↔ gameplay coupling.**

---

## 2. Setting — Starlit Licorice Canyon (`canyon` terrain theme)

A new nocturnal terrain theme: glossy **licorice-black** canyon cliffs, a sky full of **candy-star constellations** and **gumdrop moons**, ribbons of **aurora-syrup** light. Magical and eerie-pretty. The run-up leads to the **Queen's cliff-stage arena** under the stars (terrain stops on boss engagement, like the other bosses).

- **New terrain theme `canyon`** in `terrain_themes.gd` (alongside frontier/mine/farm/mountain/badlands): dark licorice albedo+normal, deep cool fog, star-speckled backdrop; **cliff** on one side (reuse the mountain cliff system); **scatter** = candy-cacti silhouettes, rock-candy spires, glowing gumdrop bushes.
- **Weather:** a starry night sky (reuse the prerendered-sky tech) and/or drifting candy-stardust; wired through the per-level weather system.
- **LevelDef** `godot/resources/levels/level_6.tres`: `terrain="canyon"`, weather, `star_thresholds`, `outlaw_quota`, boss event `{"boss": "queen"}`, difficulty 6, tuned one step past Level 5.

---

## 3. The colorful birds — Level-6 creature cast (no guns)

Candy **songbirds** populate the canyon — Papageno's flock. Like the farm/badlands rosters, **two visually-distinct tint types** (same model, two colors), family-friendly and gunless:

| Type | Tint | Behavior |
|------|------|----------|
| **Flit-finch** | bright warm (orange/yellow) | darts erratically across lanes, light harasser |
| **Peck-jay** | cool (blue/teal) | swoops down to peck the posse on a cooldown |

- Spawn-weighted via the `outlaw_kind` system (mirrors `BADLANDS_OUTLAW_WEIGHTS` / `_pick_outlaw_kind`), e.g. `{flit_finch: 55, peck_jay: 45}`.
- Both drain via the existing `_outlaw_drain_posse()` (special follower soaks first). Rendered as sprite/flipbook billboards (cheap; cf. the chicken-chase hens). No video billboards for the flock (many on screen).

---

## 4. Papageno & Papagena — comic tutorial duet (mid-canyon set-piece)

A bright, silly **set-piece** in the canyon mid-run (the Rainbow-Kimmy set-piece pattern): the candy-bird couple **Papageno** (greenish, gumdrop-feathered, little pan-flute) and **Papagena** (pinks) do their giddy stuttering **"Pa-pa-pa-pa-Papagena!"** call-and-response.

**Purpose = teach the sing-duel mechanic** (§5) safely: Papageno sings a short, easy contour; a friendly response window invites the player to **swipe it back**; success = hearts + a joyous duet beat; there is **no penalty** for missing (it's a tutorial). A few escalating "pa-pa-pa" rounds ramp the player from one simple arc to a short run, so they arrive at the Queen already fluent. Pure comedy — the bright counterweight to the Queen's darkness.

---

## 5. Boss — Queen of the Night — the Sing-Duel

On engagement the terrain stops at the cliff-stage arena. The fight reuses the existing `_process_rustler` / `_spawn_*` boss loop (boss HP, special-follower soak, rig dismantle / WIN-FAIL flow) with the signature **call-and-response** layer:

### 5.1 The duel loop
1. **She sings.** The Queen belts a phrase (an AI-performed vocal stinger, §6); its **melodic contour** is drawn as a bold glowing shape across a "duel band" in front of her — note-dots light up left-to-right in rhythm. Phrase shapes are legible: a **rising run** = upward sweep, a **staccato** = sharp zig-zag, an **arc** = a curve.
2. **Your turn.** A **response window** opens on the beat (a metronome pulse). The player **swipes to trace the contour back.**
3. **Resolve.** A clean, on-time trace = your posse **out-sings** her → she takes a chunk of damage + recoils. A sloppy or late trace = she **belts a high note** → drains the posse (special followers soak first). Accuracy = path-following + timing (both scored; partial credit for a near-miss).

### 5.2 Escalation + phases
- Phrases ride **Der Hölle Rache** and **escalate**: gentle arcs → rising runs → the **staccato high-F finale** (a fast zig-zag, the hardest trace, worth the most damage).
- **Phase 2 at 50% HP:** full vengeance — phrases get faster, longer, and more jagged; the backing track intensifies; her glare reddens. No new mechanic, just intensity.

### 5.3 Posse still fires
The posse **auto-fires** at the Queen for **chip damage** throughout (keeps the *Not This Again* identity), but the **duel is where the fight is won or lost** — out-sings are the real damage; botched answers are the real danger.

### 5.4 Win / lose
- **Win:** out-sing her through the finale → standard boss rig-dismantle + WIN flow (stars, hearts, level-select progression).
- **Lose:** posse wiped → she holds a triumphant high note over the standard Fail modal (a Queen-of-the-Night lose flourish, lighter-weight than Raisin's Five-Point cinematic).

---

## 6. Audio — hybrid (the fight is built on it)

- **Instrumental candy backing track** (music-box / bells / synth arrangement of the public-domain melodies) underscores the canyon and the boss; it carries the **beat grid** that the swipe windows snap to.
- **AI-performed vocal stingers** (ElevenLabs, the boss-VO pipeline) for the moments that must read as *singing*: the Queen's individual sung phrases, her taunts, and the **Pa-pa-pa duet**.
- Mozart's melodies are **public-domain**; we perform/synthesize **our own** candy-styled versions — no recording-licensing issue. Coloratura quality is a build-time tuning concern (fall back to stylized vocal SFX for the hardest runs if needed).

---

## 7. Her look (concept art)

A towering **candy opera diva**. Direction options being concepted (NB Pro): a **licorice night-sky gown studded with candy-star constellations + a spiked starburst tiara** (lead), a translucent **sugar-glass/rock-candy** variant, and a **dark-chocolate-and-gold baroque** variant. Glittering, severe, a touch villainous but candy-cute. Owner picks the look; animations via Veo claymation green-screen billboard (the boss pattern); VO via ElevenLabs.

---

## 8. Mobile-safe build approach

Only techniques proven on the Android renderer — **no custom spatial shaders**.

- **Queen = chroma-key video billboard** via `_make_video_billboard` (the Pete/Rustler/Raisin approach; green-screen seed → Veo → key).
- **The sing-duel = additive 2D-canvas overlay** (the `frost_bolts.gd` / `manga_fx.gd` tech): draws the glowing contour, the note-dots, the metronome pulse, the player's swipe trail, and the out-sing / high-note hit FX. The swipe is captured as `InputEventScreenDrag` points and scored against the contour.
- **Birds = sprite/flipbook billboards** (cheap, many on screen).
- **Papageno set-piece** reuses the Rainbow-Kimmy set-piece pattern.
- **Fight logic** extends the existing boss loop + WIN/FAIL flow in `level_3d.gd`. The duel's pure scoring (contour-match accuracy, timing window, damage/drain resolution) should live in a **unit-testable RefCounted** (the `RaisinKiddState` pattern) so it runs in GUT on CI.

---

## 9. Out of scope (YAGNI)

Free-form singing / pitch detection; a full rhythm-game engine; per-note microtiming beyond the contour+window scoring; the Queen on any level but 6; licensed recordings. **One canyon, one tutorial duet, one escalating sing-duel.**

---

## 10. Build-time TODOs

- Concept art → owner pick → Veo green-screen billboard clips (idle / sing / vengeance) + the two bird types + Papageno/Papagena.
- Hybrid audio: candy instrumental backing + AI-performed vocal stingers (Queen phrases, Pa-pa-pa duet); a beat-grid the duel reads.
- The contour library (a set of legible phrase shapes per difficulty tier) + the swipe-scoring (accuracy + timing).
- New `canyon` terrain theme textures + starry-night sky.
- Device tuning: response-window length, accuracy tolerance, damage/drain per answer, phrase cadence, phase-2 intensity, bird weights, L6 quota/stars.
- ElevenLabs voice for the Queen (operatic) + Papageno/Papagena.
