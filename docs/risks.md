# Known risks & issues

Live tracker for engine / SDK / tooling pitfalls that could derail "Play Store featured quality." Mirror of the risk register in the plan; updated as we encounter issues in practice.

## High severity

### Audio latency (OpenSL ES, 200–500ms on mid-range Android)
- **Source**: Godot 4.x uses OpenSL ES on Android; Oboe/AAudio migration proposed in [godot-proposals #2358](https://github.com/godotengine/godot-proposals/issues/2358) but not landed.
- **Reports**: [Godot #85442](https://github.com/godotengine/godot/issues/85442), [#95528](https://github.com/godotengine/godot/issues/95528).
- **Impact**: Crowd runner has frequent gate/wall/hit SFX. Mushy audio = ugly feel.
- **Mitigation**: `AudioStreamPlayer` Sample mode (default in 4.3+). `audio/driver/output_latency=15` in project.godot. Pre-trigger SFX slightly ahead of visual cue. **Prototype audio in phase 1 before investing in full audio bed.**
- **Plan B**: Defold engine if latency is unfixable.

### Godot #118153 — stretch mode misbehaves on Android in 4.5.2–4.6.2
- **Source**: [Godot #118153](https://github.com/godotengine/godot/issues/118153)
- **Impact**: `canvas_items + expand` stretch on Android. We use `canvas_items + keep` (letterboxed in landscape per design), which may dodge the bug — verify in phase 0.
- **Mitigation**: Test on real Android 14+ device in **phase 0** before locking UI architecture. Track upstream issue.

## Medium severity

### Mali GPU cosmetic bugs (mipmaps darker, [Godot #43342](https://github.com/godotengine/godot/issues/43342))
- **Impact**: Affects GLES3 Compatibility renderer. We chose Mobile/Vulkan renderer, which avoids these.
- **Mitigation**: Test on a real Mali-equipped device anyway. If we ever fall back to Compatibility, expect cosmetic drift.

### Lifecycle bug [Godot #85265](https://github.com/godotengine/godot/issues/85265) — pause/resume fires twice
- **Impact**: Heart-regen could double-tick if not idempotent. IAP (phase 4) must dedupe.
- **Mitigation**: Heart-regen timer must be idempotent (write tests). Save/load purchases must dedupe by transaction ID.

### Predictive back gesture (Android 16 / targetSdk 36 requirement)
- **Source**: Required by Play Store for new submissions at targetSdk 36.
- **Mitigation**: `AndroidManifest` override `android:enableOnBackInvokedCallback="true"` + `NOTIFICATION_WM_GO_BACK_REQUEST` handler in `scripts/platform/android.gd`. Requires custom build template (deferred from initial scaffolding).

### Featured-quality crash triage requires native debug symbols
- **Impact**: Without symbolicated crashes, Play Console can't help you diagnose featured-app issues.
- **Mitigation**: Wire **Firebase Crashlytics** (reusing existing Firebase project from adjacent app) in phase 0. Upload native debug symbols to Play Console as part of release workflow.

### gcloud Secret Manager binary stdout corruption
- **Source**: Discovered 2026-05-11 during phase 0 setup with gcloud SDK 560.0.0.
- **Impact**: `gcloud secrets versions access ... > keystore.p12` produces a 1.75× larger corrupted file because Python's text-mode stdout substitutes non-UTF-8 bytes with U+FFFD (`EF BF BD`).
- **Mitigation**: **Always use the URL-safe base64 JSON path** for binary secrets — see `.github/workflows/android-release.yml` step "Fetch release keystore from Secret Manager (binary-safe)".

## Low severity

### Godot Android export "absolute paths only" footgun
- **Impact**: Godot fails on relative keystore paths (`~/.android/...`).
- **Mitigation**: Always write keystores to `$RUNNER_TEMP/release.p12` (absolute) in CI.

### Audio backend may switch to Oboe/AAudio mid-development
- **Source**: [godot-proposals #2358](https://github.com/godotengine/godot-proposals/issues/2358)
- **Impact**: If it lands during our development, audio settings need re-baselining.
- **Mitigation**: Pin Godot version. Re-test audio if we voluntarily upgrade.

### `godot-sdk-integrations/godot-google-play-billing` signals reportedly flaky on 4.6.1
- **Scope**: Phase 4 (IAP) only.
- **Mitigation**: Budget 2–3 days for IAP integration. `AndroidIAPP` plugin as fallback.

## Resolved

_(none yet)_

## Active deferrals

### Phase 0 ships APK, not AAB (target: AAB by phase 3)
- **Source**: Discovered 2026-05-11 on first CI run. Godot rejected AAB output because `gradle_build/use_gradle_build=false`. AAB requires the custom Android build template, which only the Godot Editor's "Project → Install Android Build Template" menu can install — there is no CLI flag in Godot 4.6.1.
- **Current state**: `gradle_build/export_format=0` (APK), `use_gradle_build=false`. Godot ships its prebuilt APK template with `targetSdk=35`, `minSdk=21` defaults. We accept those for phase 0.
- **What we lose in the interim**:
  - APK instead of AAB (fine for sideloading; not acceptable for Play Store)
  - `targetSdk=35` instead of 36 (fine for sideloading; will be Play-Store-blocking by 2026 cutoff)
  - `minSdk=21` instead of 24 (devices we'd lose with 24 are already supported here; cosmetic)
- **Path to AAB**:
  - Commit a Godot 4.6.1 custom Android build template into `android/build/` — files come from Godot's editor binary at install-template time
  - Flip `use_gradle_build=true`, `export_format=1`, restore min/target sdk overrides
  - Re-run CI; verify AAB output
- **Owner**: tracked as task #22 (added 2026-05-11)
