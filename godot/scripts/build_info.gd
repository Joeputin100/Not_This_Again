extends Object

# Build identifier values. Overwritten in CI by a step that injects the
# current git short SHA and commit timestamp before each Godot export.
# These placeholder values are what you see when running outside CI
# (or if the CI injection step ever fails to run).

const SHA: String = "local-dev"
const SHORT_DATE: String = "0000-00-00"
# Iter 63: hardcoded ITER as a string. CI stamp step still overwrites
# this with `git log --oneline | wc -l`, but if that ever fails, we
# fall back to this manually-maintained value rather than showing "?".
# Bumped per-iter as part of commit hygiene.
const ITER: String = "116"

# Iter 100: CI smoke-test flag. The android-debug.yml stamp step keeps
# this false (production sideloading); the new smoke-test.yml workflow
# stamps it true so main_menu auto-redirects to level_3d.tscn after a
# short delay. That lets the emulator + Firebase Test Lab smoke jobs
# exercise the 3D PREVIEW scene WITHOUT scripting any UI taps.
const SMOKE_TEST: bool = false
