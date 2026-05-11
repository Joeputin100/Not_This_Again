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

### Phase 0 ships APK, not AAB → **RESOLVED 2026-05-11**
- Originally deferred because the Godot Editor's "Install Android Build Template" menu has no CLI equivalent in 4.6.1.
- Discovery: `android_source.zip` is shipped *inside* `Godot_v4.6.1-stable_export_templates.tpz`. The CI workflow extracts it and reproduces the Editor's install side-effects manually:
  - Extract `android_source.zip` → `godot/android/build/`
  - Write `"4.6.1.stable"` → `godot/android/.build_version` (must be in `android/`, NOT `android/build/`; content must match `GODOT_VERSION_FULL_CONFIG` which drops the `.official` build suffix)
  - Touch empty `godot/android/build/.gdignore`
- Resolved by run 25662281555 (commit 245dda8). AAB + use_gradle_build=true + targetSdk 36 + minSdk 24 all working.
