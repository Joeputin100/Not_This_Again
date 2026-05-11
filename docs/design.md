# Not This Again — Plan

## Context

The Android ads for **Evony: The King's Return**, **Last Z: Survival**, **Timeline Up**, and **Top War: Battle Game** all promise a crisp casual minigame, then drop you into a strategy/city-builder grind, often pay-to-win and ad-saturated. The intended outcome is a single Android title that delivers **only** the crowd-runner minigame those ads keep promising, **free, ad-free, never pay-to-win**, with a Candy Crush–style hearts loop so casual sessions feel paced rather than infinite. v1 ships offline, with procedural levels, in a Western theme — a fresh aesthetic compared to the eras/military/zombie skins used by the games being riffed on. The artifact in this repo is greenfield: no existing code to preserve.

## Decided constraints

| Decision | Value |
|---|---|
| Genre | Crowd / gate runner (Timeline Up-style) |
| Theme | **Western** (posse, saloon doors, outlaw bosses) |
| Levels | Procedurally generated from segment templates, seed-based |
| Online | **Offline-only in v1**. Architect cleanly so a Ktor backend can be added later. |
| Monetization v1 | Free, no IAP, **no ads ever** |
| Monetization later | IAP only: heart refills, booster packs, cosmetic skins. No P2W. |
| Engine | **Godot 4.6.1** (fallback 4.5.2 if 4.6.x bugs surface) |
| Language | GDScript |
| Renderer | **Mobile (Vulkan)** |
| minSdk / targetSdk | **24 / 36** (bumped from 21 to enable Vulkan) |
| Orientation | Portrait-primary, landscape letterboxed |
| Display | Edge-to-edge, safe-area aware |
| Build pipeline | **GitHub Actions only** — `firebelley/godot-export@v7.0.0` |
| Output | Signed `.aab` for Play Store |
| Crash reporting | Firebase Crashlytics OR Play Console native debug symbols (decide phase 0) |
| Target outcome | Play Store editorial featured quality |

## A. Gameplay design

### Per-level loop (60-90 seconds)

```
        ┌───────────────────────┐
        │   POSSE START (×5)    │
        │     ▼  ▼  ▼           │
        │    ╱      ╲           │
        │  ┌────┐  ┌────┐       │  ← saloon-door gates
        │  │ +5 │  │ ×2 │       │     swipe to pick lane
        │  └────┘  └────┘       │
        │     ╲      ╱          │
        │      ▼▼▼▼▼            │
        │   ▓▓▓▓▓▓▓▓▓▓          │  ← wooden barricade
        │      ▼▼▼▼             │     posse auto-fires
        │  ┌────┐  ┌────┐       │
        │  │ ÷2 │  │+10 │       │
        │  └────┘  └────┘       │
        │     ▼▼▼▼▼▼▼           │
        │  ╔═══════════════╗    │
        │  ║   OUTLAW HP   ║    │  ← boss showdown
        │  ╚═══════════════╝    │
        └───────────────────────┘
```

- **Input**: drag/swipe to steer the posse left-right across 2-3 lanes. No buttons mid-level.
- **Gates**: saloon doors with painted math operators. Buff lanes (+N, ×N) and punish lanes (−N, ÷N). 6-10 gates per level.
- **Barricades**: wooden fences / wagon-wheel walls. Posse auto-fires; smaller posse = slower break = front-rank casualties. 1-3 per level.
- **Boss**: dueling firing line vs an outlaw, sheriff, stagecoach, or train. Whichever side reaches 0 first loses. HP scales with level number.
- **Win**: defeat boss with ≥1 posse member remaining.
- **Lose**: posse hits 0, or 90s timeout. Costs 1 heart.

### Western theming map

| Generic term | Western expression in this game |
|---|---|
| Crowd / runners | **Posse** — white hats, **bow-legged** walk/run cycle |
| Posse weapon | **Six-shooter revolvers**, visible reload animation |
| Gate | **Saloon doors** with painted math operators (+/×/−/÷) |
| Wall | **Wooden barricades** / wagon-wheel fences |
| Env. obstacle (lane) | **Cacti** — clipping one damages back-rank posse |
| Env. hazard (cross-traffic) | **Tumbleweeds** rolling perpendicular across lanes |
| Boss types | **Outlaws** (early), **Sheriffs** (mid — flipped: the sheriff is the antagonist because the posse is the outlaw crew), **Buffalo stampede** (mid), **Train Heist** (late, multi-phase) |
| Enemy identity | **Black hats** — outlaws and bosses both |
| Mount (mid-game unlock) | **Horseback** — posse rides in on white horses after a progression milestone. Faster swerve, heavier wall-impact, wider lane footprint. |
| Coins / currency | **Bounty / gold** |
| XP / progress | **Notoriety** (wanted-poster aesthetic) |
| Biomes | Plains → Ranch → Mining Town → Ghost Town → Canyon → Train Tracks |
| SFX bed | Harmonica, banjo, hoofbeats, gunshots, spurs, tumbleweed rustle |
| Palette | Dusty orange / brown / sunset / sky teal |

### Tone bible

The voice splits across two characters: a **deadpan narrator** and **histrionic enemies**. Both run snark through them at different temperatures. The contrast is the joke.

- **Narrator / UI voice — Murderbot Diaries lean**: dry, world-weary, mildly annoyed at having to explain anything. Refuses to be patronizing or hand-holdy.
  - Tutorial pop-up: *"Drag to swerve. Or don't. Your call."*
  - Win screen: *"Congratulations. The bandits are all dead. You earned 47 bounty. Whatever that's worth."*
  - Lose screen: *"Your posse is dead. All of them. Try again, I guess."*
  - Heart-out screen: *"You've run out of posse members. Take a break. Or pay to skip the break. Or don't. I'm not your manager."*

- **Enemies & bosses — Yosemite Sam lean**: loud, blustering, sputter-cursing, slapstick-prone, easily frustrated. They lose with melodrama.
  - Boss intro: *"WAAAAGH! YOU LILY-LIVERED SADDLE-TRAMPS! GIT OFF MY TRAIN!"*
  - Boss mid-fight: *"RAA-SSAA-FRACKIN'..."*
  - Boss death: *"DAGNABBIT!"* + cartoon explosion + hat tumbles off.

- **Achievement names — dry, faintly insulting**: *"Statistical Improbability," "Adequate Posse Leader," "Concerning Body Count," "Reluctantly Competent," "Made It Out Alive (Barely)."*

### Genre shape: arcade-primary with puzzle bonus rounds

Candy Crush's main loop is **turn-based puzzle** with **occasional arcade bonus levels** (timed candy collect, jelly-fish bonus, etc.) as pacing variety. **We invert this**: our main loop is **arcade action** (the crowd runner), with **occasional turn-based puzzle bonus levels** as pacing variety.

Cadence target: one puzzle bonus per ~5 arcade levels, OR anchored to milestones (e.g., every biome boss defeated unlocks one, every Sunday is a fresh daily puzzle).

Western-themed puzzle archetypes that fit the bonus slot:

| Puzzle | Mechanic | Theme hook |
|---|---|---|
| **Bank vault combination** | Sliding-tile or rotate-the-dial logic puzzle | "Crack open the safe" — earned after a successful train heist |
| **Bounty board prioritization** | Resource management: pick which 3 outlaws to chase given travel cost + payout matrix | "Most wanted" — meta layer over arcade levels |
| **Train heist routing** | Graph/maze puzzle: path through linked train cars to reach the loot | "Route through the train" |
| **Showdown** | Chess-problem-style: position your guns to win in N moves | "High noon" — alternate final-boss flavor |
| **Wanted poster match-3** | Three-in-a-row of outlaw faces | Direct homage to Candy Crush — the inversion winks at itself |
| **Powder keg stacking** | Pack barrels into a cart, Tetris-style | Mining-town biome |

Ships as a separate `puzzle.tscn` scene type sharing project-wide `GameState`, theme, and font. **Not phase 1 scope.** Added 2026-05-11 as future content direction; revisit when phase 1 arcade-primary is fun on its own.

### Polish bar

The premise (bow-legged cowboys mathematically multiplying through saloon doors to outshoot a buffalo stampede) is **deliberately ridiculous**. The execution must be **reverent** — the Candy Crush move: take a silly mechanic seriously enough that the polish makes it feel premium.

- Every gate selection: satisfying *kachunk* SFX + camera nudge + brief slow-mo at multiplier gates
- Every wall break: particle burst (splinters), half-frame slow-mo, screen shake scaled to wall HP
- Every boss defeat: 1.5s celebration — screen tilt, confetti / dust, sting cue, posse fires hats into the air
- Hearts heal with a **visible animation** (heart drops into the meter), not a silent number change
- Horseback unlock is a **5-second cinematic**: Hollywood Western intro, posse silhouetted against sunset, dust kick, harmonica sting, name card ("WANTED: Your Posse")

Polish budget for this game is intentionally **higher than the gameplay budget** by a meaningful ratio. Mechanics ship in phase 1; polish is the entire point of phase 3 and is what makes the difference between a Play Store also-ran and a featured title.

### Future hazards & content (deferred — not phase 1)

Captured here so they don't get lost. Each lands in a later phase when the baseline gameplay loop has been verified.

#### Bull stampede hazard (random event tied to red gates)
- **Trigger**: low-probability random event whenever a *red gate* is on-screen. A gate is "red" when its current values would SHRINK the posse (see "Gate direction & color" below).
- **Behavior**: bull with large horns enters from off-screen at very high speed, runs through, exits off-screen on the opposite side. Does NOT track or fight the player.
- **Stats**: HP 500–1000 (effectively impossible to kill with normal bullet rate); high cowboy collision damage; will destroy any red gate it passes through.
- **Color-flip deflection**: if the red gate the bull is targeting flips to BLUE while the bull is still on-screen (because the player shot it enough to convert "-3" → "+1", etc.), the bull slows down, looks confused (visual animation), and walks off the LEFT or RIGHT side of the track instead of completing its line. The flip rewards aggressive shooting of dangerous gates.
- **Implementation sketch**: new `bull.gd` joining a "bulls" group. Spawned by a `BullSpawner` that watches active "shrinking" gates and rolls a probability check each frame they're on-screen. Bull movement uses a fixed direction (left→right or right→left), Vector2.RIGHT × speed × delta. Each frame, bull checks if its target gate is still red — if it flipped to blue, switch to the "confused → veer off" state.
- **Visual**: side-profile bull silhouette with prominent horns, dust trail behind it. When confused: head shake, slowdown, dust cloud, then exit.

#### Gate direction & color (SHIPPED in iter 19)
- Already implemented (`GateHelper.gate_is_growing`): a gate is BLUE if both doors leave the posse at-least-as-large (additive ≥ 0, multiplicative ≥ 1); otherwise RED.
- Color tweens on threshold cross when the player shoots additive gates enough to flip them. This is the trigger for the bull-deflection above when that future feature ships.

#### Chicken coop (destructible, releases chickens)
- **Trigger**: standard destructible obstacle. Medium HP (TBD — probably 8–12). Joins an "obstacles"-like group like the other shootable scenery.
- **Death payload**: when destroyed, spawns a *cloud* of 6–10 chickens at the coop's position. Each chicken has 1–3 HP (randomized per spawn).
- **Chicken behavior**: chaotic. Pick a random heading every ~0.8s, move at moderate speed, flap-and-flail animation (sprite swap or rapid scale/rotation oscillation). Visible bedlam.
- **Lifespan**: chickens despawn when shot, when they exit the screen, or after ~5s timeout (whichever first).
- **Gameplay effect (resolved)**: **vision blocker + visual chaos, NO posse damage**. Chickens fill the screen with flapping bodies, briefly making it harder to read gates/obstacles. Cowboy contact is harmless. Bullets still kill chickens on contact. Pure disruption — the player's strategy choice is "shoot the coop and accept the chaos" vs "shoot around it / avoid it."
- **Visual**: small white squarish bodies with red comb dots, flappy wing motion. Splinter-style particle on death (feathers).

#### Atmospheric weather effects
- **Dust storm**: gusts reduce visibility (full-screen ColorRect with low alpha that pulses), cause light periodic damage to posse.
- **Rain**: reduced visibility (full-screen overlay with falling line-particles), no damage.
- **Wind storm**: directional gust forces nudge the cowboy off course (additive X velocity on top of touch input). Visible by tilted dust streaks moving sideways across the screen.
- Implementation: each as an autoload-style "weather director" node added to the level scene that runs for a duration and affects both visuals (CanvasLayer overlay) and gameplay (input modifier or periodic damage).
- These are level-wide modifiers, not per-obstacle, so they belong in the procgen segment-template system once that lands.

## B. Procedural generation

Seed-based **segment template composition**, not raw procedural geometry (which produces unfair levels).

```
Level N → seed(N) → difficulty_score(N)
                       │
                       ▼
              [segment library]
                ┌──────────────┐
                │ Tutorial seg │  ← weighted pick
                │ Gate+/+      │  ← 4-6 segments per level
                │ Gate+/−      │
                │ Wall light   │
                │ Wall heavy   │
                │ Boss outlaw  │
                │ Boss sheriff │
                │ Boss train   │
                └──────────────┘
                       │
                       ▼
              Compose into track,
              shuffle gate values
              within difficulty bounds
```

- **~20 segment templates** in v1, stored as Godot `.tres` resource files.
- Each segment carries: difficulty rating, biome tag, gate value bounds, lane count.
- Level seed = `hash(level_number, player_salt)` → deterministic, reproducible.
- Difficulty curve: levels 1-10 tutorial subset; 11-30 negative gates; 31-60 tighter walls; 61+ full pool.
- Pause/close mid-level → resume same layout (seed re-derives the level).
- Future "daily challenge" trivially supported: same seed for everyone on a given date.

## C. Progression, hearts, deferred IAP

### v1 (offline, no IAP, no ads)

- **Hearts**: max 5, regen 1 per 30 min from a **local monotonic clock** (no server check, no anti-cheat in v1). 1 lose = 1 heart.
- **Bounty (coins)**: earned per level by (boss-defeat bonus + remaining posse × multiplier). Spent on cosmetics only.
- **Notoriety (XP)**: visual progress meter, unlocks new posse skins and trail FX at thresholds.
- **Daily login**: small bounty bonus + 1 free booster.
- **Boosters** (free, 1 starter pack per day): extra starting posse, head-start lane, double-bounty modifier.
- **Cosmetic unlocks**: 5 starter skins (cowboy, cowgirl, prospector, ranger, outlaw), ~10 trail FX (dust cloud, smoke, sparks, hoofprints).
- **Horseback unlock** (phase 3 polish milestone): meta-progression reward triggered by first Canyon-biome boss defeat OR reaching level 30, whichever comes first. Visually and mechanically transforms the posse: white horses, faster swerve, heavier wall-impact, wider lane footprint. Custom 5-second cinematic on first unlock; subsequent runs all feature the mounted posse. **This is the game's primary "wow" milestone** — the equivalent of unlocking a new game mode in Candy Crush. One-time celebration per account.

### Later (phase 4+)

- IAP for: heart refills (single or 24h unlimited), bounty packs, booster bundles, premium cosmetic skins.
- No P2W: no IAP-only stat bonuses, no IAP-only levels, no IAP that unbalances PvP-style metrics.
- No rewarded video ads — explicit "no ads, ever" stance.

## D. Tech stack (validated)

| Layer | Pin |
|---|---|
| Engine | Godot **4.6.1** (or 4.5.2 fallback) |
| Renderer | Mobile / **Vulkan** |
| Language | GDScript |
| Stretch mode | `canvas_items`, expand aspect, base resolution 1080×1920 portrait |
| **Active bug to monitor** | **Godot #118153** — `canvas_items + expand` stretch on Android in 4.5.2-4.6.2. Test on real device before locking UI. |
| Android signing | Keystore base64 in GH Secrets, decoded to absolute path in CI (relative paths break Godot Android export) |
| IAP plugin (phase 4) | `godot-sdk-integrations/godot-google-play-billing` v3.2.0 primary, `AndroidIAPP` fallback |
| Crash reporting | Firebase Crashlytics integration via Godot Android plugin OR Play Console native debug symbols |
| Audio | OpenSL ES (Godot default), `AudioStreamPlayer` playback mode = **Sample** (low-latency), `audio/driver/output_latency` = 15ms |
| Predictive back | `AndroidManifest` override + `NOTIFICATION_WM_GO_BACK_REQUEST` handler (required at targetSdk 36) |
| Edge-to-edge | Export preset edge-to-edge flag (PR #107742, available in 4.5+) + `DisplayServer.get_display_safe_area()` for UI anchoring |

## E. Project structure

```
Not_This_Again/
├── .github/
│   └── workflows/
│       ├── android-debug.yml          # PR + main pushes
│       └── android-release.yml        # tag-triggered, signed .aab
├── godot/
│   ├── project.godot                  # Vulkan, portrait+landscape, stretch
│   ├── export_presets.cfg             # Android AAB preset (committed, no secrets)
│   ├── scenes/
│   │   ├── main_menu.tscn
│   │   ├── level.tscn
│   │   ├── boss.tscn
│   │   └── ui/
│   │       ├── hud.tscn               # bounty, posse count, level
│   │       ├── hearts.tscn
│   │       └── results.tscn           # win/lose screen
│   ├── scripts/
│   │   ├── posse.gd                   # crowd entity, movement, shooting
│   │   ├── gate.gd                    # gate effects (+/-/×/÷ painted on saloon door)
│   │   ├── barricade.gd               # wall HP, posse-vs-wall combat
│   │   ├── outlaw_boss.gd
│   │   ├── procgen/
│   │   │   ├── level_builder.gd       # composes segments
│   │   │   ├── segments/              # .tres segment templates
│   │   │   └── difficulty.gd          # curve function, seeded RNG
│   │   ├── save/
│   │   │   ├── save_data.gd           # seed + level + hearts + bounty + unlocks
│   │   │   └── heart_timer.gd         # local clock regen, handles app pause/resume
│   │   ├── input/
│   │   │   └── swerve.gd              # drag → posse steer
│   │   └── platform/
│   │       └── android.gd             # predictive back, safe-area, lifecycle
│   ├── assets/                        # sprites, sounds, fonts (Western)
│   └── shaders/                       # optional polish (dust, heat haze)
├── android/
│   ├── build/
│   │   ├── AndroidManifest.xml        # edge-to-edge, predictive back, targetSdk 36
│   │   └── gradle.properties          # custom gradle overrides for targetSdk 36
│   └── README.md                      # signing key setup, CI secrets walkthrough
├── docs/
│   ├── design.md                      # this plan, copied in for repo onboarding
│   └── risks.md                       # known-issue tracker (see Risk register)
└── README.md
```

## F. CI pipeline (GitHub Actions only)

Two workflows, both `ubuntu-latest`:

### `android-debug.yml` — every push + PR

```
- actions/checkout@v4
- actions/setup-java@v4 (JDK 17)
- android-actions/setup-android@v3
- Cache: Godot binary + export templates + Gradle
- firebelley/godot-export@v7.0.0
    godot_executable_download_url: 4.6.1-stable Linux headless
    godot_export_templates_download_url: 4.6.1-stable
    relative_export_path: godot/
    archive_output: false
    presets_to_export: "Android"
- Upload .aab as workflow artifact
```

Typical build time: **5-12 min** (first run slower due to cache miss).

### `android-release.yml` — git tag `v*.*.*`

Same pipeline as debug, plus:

- Authenticate to GCP via Workload Identity Federation (`google-github-actions/auth@v2`)
- Pull keystore from Secret Manager using **the binary-safe path** (see "Critical: gcloud binary stdout bug" below)
- Pull keystore password from Secret Manager (`android-keystore-password`)
- Write keystore to an **absolute** path in `$RUNNER_TEMP/release.p12` — Godot's Android export breaks on relative paths
- Pass keystore password + alias to export preset via env vars
- Optional: `r0adkll/upload-google-play@v1` to Internal Testing track (deferred — user is sideloading initially)

### Critical: gcloud binary stdout bug

`gcloud secrets versions access ... > keystore.p12` **produces a corrupt file** because Python's text-mode stdout substitutes non-UTF-8 bytes with `EF BF BD` (Unicode replacement character). Verified 2026-05-11 with gcloud SDK 560.0.0. The fix is to fetch via JSON payload + base64-decode, never via raw stdout:

```bash
gcloud secrets versions access latest --secret=android-release-keystore \
  --format='get(payload.data)' \
  | tr -d '\n' \
  | tr -- '-_' '+/' \
  | base64 -d > "$RUNNER_TEMP/release.p12"
```

The `tr '-_' '+/'` step is required because `get(payload.data)` returns **URL-safe** base64 (RFC 4648 §5), while `base64 -d` only accepts **standard** base64 (RFC 4648 §4).

### Auth pattern: Workload Identity Federation (no long-lived keys)

CI authenticates to GCP using GitHub's OIDC token exchanged for a short-lived GCP access token. **No service-account JSON key is stored in GitHub Secrets** — long-lived credentials are an avoidable attack surface.

One-time setup (user runs locally):

```bash
# Create workload identity pool
gcloud iam workload-identity-pools create github \
  --location=global --display-name="GitHub Actions"

# Create OIDC provider for GitHub
gcloud iam workload-identity-pools providers create-oidc github-provider \
  --location=global --workload-identity-pool=github \
  --display-name="GitHub Provider" \
  --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository" \
  --issuer-uri="https://token.actions.githubusercontent.com"

# Create service account with minimal permissions
gcloud iam service-accounts create gh-actions-keystore \
  --display-name="GH Actions keystore reader"

# Grant Secret Manager access only
gcloud secrets add-iam-policy-binding android-release-keystore \
  --member="serviceAccount:gh-actions-keystore@$PROJECT.iam.gserviceaccount.com" \
  --role="roles/secretmanager.secretAccessor"
gcloud secrets add-iam-policy-binding android-keystore-password \
  --member="serviceAccount:gh-actions-keystore@$PROJECT.iam.gserviceaccount.com" \
  --role="roles/secretmanager.secretAccessor"

# Bind workload identity to service account, restricted to the GH repo
gcloud iam service-accounts add-iam-policy-binding \
  gh-actions-keystore@$PROJECT.iam.gserviceaccount.com \
  --role="roles/iam.workloadIdentityUser" \
  --member="principalSet://iam.googleapis.com/projects/$PROJECT_NUMBER/locations/global/workloadIdentityPools/github/attribute.repository/<owner>/<repo>"
```

### Required GH Secrets

Only two — both are *pointer strings*, not secrets themselves:
- `GCP_WIF_PROVIDER` — full resource name of the OIDC provider (e.g., `projects/.../workloadIdentityPools/github/providers/github-provider`)
- `GCP_SERVICE_ACCOUNT` — email of the service account (`gh-actions-keystore@$PROJECT.iam.gserviceaccount.com`)

No keystore base64, no passwords, no JSON keys in GitHub.

## G. Risk register (from validation pass)

| Risk | Severity | Mitigation |
|---|---|---|
| **Audio latency (OpenSL ES, 200-500ms on mid-range)** | **High** | Prototype gate/hit SFX in **phase 1**, before investing in a full audio bed. Use `AudioStreamPlayer` Sample mode. Pre-trigger SFX slightly ahead of visual cue if needed. Defold is a Plan B if unfixable. |
| **Godot #118153 — stretch mode misbehaves on Android** | High | Test `canvas_items + expand` on real Android 14+ device in **phase 0**, before locking UI architecture. Track issue for resolution. |
| **Mali GPU cosmetic bugs (mipmaps, #43342)** | Medium | Mitigated by choosing Vulkan over GLES3, but test on real Mali device anyway. |
| **Lifecycle bug Godot #85265 — pause/resume fires twice** | Medium | Heart-regen timer must be idempotent. Save/load purchases (phase 4) must dedupe. |
| **Predictive back gesture at targetSdk 36** | Medium | Add `AndroidManifest` override + back handler in phase 0; required for compliance. |
| **firebelley/godot-export keystore footgun** | Low | Use absolute paths only; document in `android/README.md`. |
| **Audio backend may switch to Oboe/AAudio mid-development** | Low | godot-proposals #2358 is open. If it lands, re-baseline audio settings; otherwise no action. |
| **GodotGooglePlayBilling signals reportedly flaky on 4.6.1** | Low (phase 4) | Budget 2-3 days for IAP integration; have `AndroidIAPP` as fallback plugin. |
| **Featured-quality crash triage requires native symbols** | Medium | Wire Firebase Crashlytics OR Play Console native debug symbols in phase 0, not as an afterthought. |

## H. Roadmap

| Phase | Scope | Exit criterion |
|---|---|---|
| **0. Scaffolding** | Godot 4.6.1 project, project.godot settings, CI workflows (debug + release), keystore wiring, edge-to-edge AndroidManifest, predictive back handler, Crashlytics or native symbols, one device smoke test | Signed debug `.aab` lands in Play Internal Testing **and** launches on a real Android 14+ device with stretch mode #118153 verified |
| **1. Core loop** | One hand-built level: posse movement, swipe input, 1 gate type, 1 barricade, 1 outlaw boss, win/lose UI, hearts (no regen yet), audio SFX prototype | A blind playtester wants to retry without prompting. Audio latency feels acceptable. |
| **2. Procgen + economy** | Segment template library (~15-20 segments), seed-based composition, heart regen w/ local clock, bounty, save data, daily login bonus | 50 procgen levels feel distinct; heart pacing feels fair; resume mid-level produces same layout |
| **3. Polish + content** | Western art pass (sprites, palette, harmonica/banjo SFX bed), boss variants (sheriff, **buffalo stampede**, train), **cacti + tumbleweeds** as obstacles, **horseback unlock cinematic + on-horse animations**, biome progression, posse skin unlocks, trail FX, **bow-legged walk cycle**, juice/particles, achievement copy in Murderbot voice, boss banter in Yosemite Sam voice | Closed alpha on Play Console; demo video shows "featured-quality" feel; horseback unlock plays correctly with no rendering glitches |
| **4. IAP (deferred)** | GodotGooglePlayBilling integration, heart refill SKUs, bounty packs, booster bundles, cosmetic skin SKUs. **No P2W. No ads.** | One real tester completes IAP purchase end-to-end on a Play Store internal build |

## I. Verification

How to confirm the plan executes correctly:

### Phase 0 verification
1. `gh workflow run android-debug.yml` on a branch → artifact downloads, file is a valid `.aab`.
2. Push a git tag `v0.0.1-alpha` → `android-release.yml` produces a signed `.aab`.
3. Side-load that `.aab` (via `bundletool`) onto a real Android 14+ device → app launches edge-to-edge.
4. Rotate the device → no stretch-mode #118153 artifacts visible.
5. Press the back gesture from a sub-screen → predictive back animation works, not a hard close.
6. Force a deliberate crash → Crashlytics (or Play Console pre-launch report) captures it with symbolicated native frames.

### Phase 1 verification
1. Open level, swipe through gates, beat boss → win screen.
2. Time the audio: tap a gate, listen for SFX. Latency feels <100ms on at least one mid-range device.
3. Pause app mid-level, resume → posse position and posse count preserved.
4. Lose three runs → three hearts spent. No regen yet, so display "0 hearts" cleanly.

### Phase 2 verification
1. Play levels 1, 25, 50, 75 → each feels different. Level 1 is gentle; level 75 is hard.
2. Same level number played twice → identical layout (seed determinism).
3. Set system clock forward 30 min → exactly 1 heart regenerated. 90 min → exactly 3.
4. Kill app mid-regen, wait, relaunch → correct heart count based on real wall time.

### Phase 3 verification
1. Demo to 5 people who have never seen the game → ≥3 say "I'd download this."
2. Boss variants visually distinct.
3. Internal-testing review on Play Console passes pre-launch checks for ANRs, crashes, accessibility, edge-to-edge.

### Phase 4 verification
1. Internal testers complete an IAP heart-refill purchase. Receipt processed. Hearts granted. Survives app kill + relaunch.
2. Test all SKUs, including cosmetic-only ones.
3. Restore-purchases path works on fresh install.

## Critical files this plan produces

- `/home/projects/Not_This_Again/godot/project.godot` — Vulkan, stretch mode, orientation, audio settings
- `/home/projects/Not_This_Again/godot/export_presets.cfg` — Android AAB preset with keystore placeholders
- `/home/projects/Not_This_Again/android/build/AndroidManifest.xml` — edge-to-edge, predictive back, targetSdk 36
- `/home/projects/Not_This_Again/android/build/gradle.properties` — custom Gradle overrides
- `/home/projects/Not_This_Again/.github/workflows/android-debug.yml` — CI debug build
- `/home/projects/Not_This_Again/.github/workflows/android-release.yml` — CI signed release
- `/home/projects/Not_This_Again/godot/scripts/posse.gd` — core crowd entity
- `/home/projects/Not_This_Again/godot/scripts/procgen/level_builder.gd` — seed-based level composer
- `/home/projects/Not_This_Again/godot/scripts/save/save_data.gd` — local save format
- `/home/projects/Not_This_Again/godot/scripts/save/heart_timer.gd` — local-clock heart regen
