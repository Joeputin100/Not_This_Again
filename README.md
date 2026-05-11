# Not This Again

A snarky Western-themed crowd-runner Android game. **No ads. No pay-to-win. No city-builder.** Just the dang minigame those other ads keep promising.

Built with **Godot 4.6.1 + GDScript**. Offline-only in v1. Builds entirely in GitHub Actions — no local Gradle.

## Status

Phase 0 scaffolding. Not yet playable.

## Project layout

```
.github/workflows/   GitHub Actions CI (debug + release)
android/             Android build template + keystore setup walkthrough
docs/                Design spec, risk register
godot/               Godot 4 project (open this folder in Godot Editor if needed)
  ├── scenes/        .tscn scene files
  ├── scripts/       GDScript source
  ├── assets/        sprites, sounds, fonts
  └── shaders/       optional polish
```

## Building

**Local builds are not supported by design.** All builds happen in GitHub Actions:

- Push to any branch / open PR → `android-debug.yml` produces a debug `.aab` as a workflow artifact (good for sideloading)
- Push a tag `v*.*.*` → `android-release.yml` pulls the release keystore from Google Secret Manager and produces a signed release `.aab`

See `android/README.md` for the one-time setup (signing keystore, Workload Identity Federation, GitHub repo secrets).

## Design references

- `docs/design.md` — full design spec (the plan)
- `docs/risks.md` — known engine/SDK issues we're tracking
- `.claude/plans/this-is-a-new-keen-eclipse.md` (in user's Claude state) — original plan source of truth

## Tone

Narrator / UI voice — **deadpan, world-weary**:
> *"Your posse is dead. All of them. Try again, I guess."*

Bosses & enemies — **histrionic, sputter-cursing**:
> *"DAGNABBIT! YOU LILY-LIVERED SADDLE-TRAMPS!"*

If you write copy that sounds like a Disneyland park sign, delete it.

## License

TBD.
