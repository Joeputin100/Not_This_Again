#!/usr/bin/env bash
# Emulator smoke test driver invoked by .github/workflows/smoke-test.yml.
#
# Why a script file instead of inlining in the workflow YAML:
# reactivecircus/android-emulator-runner@v2 wraps each line of its
# 'script:' block in its own `sh -c`. Multi-line shell constructs like
# `if/then/fi` get split across invocations and fail with
# "Syntax error: end of file unexpected (expecting "fi")". Running one
# script file from the workflow keeps the whole sequence in a single
# shell, and we get `set -euo pipefail` reliability + readable code.

set -euo pipefail

PKG=app.notthisagain.run
APK=app-smoke.apk
WAIT_SECS=45  # main_menu boot + 2s auto-redirect timer + level_3d _ready

# Bump logcat buffer so we don't lose godot lines during the wait. The
# default 256K wrap can drop the breadcrumbs we need to assert against.
adb logcat -G 4M
adb logcat -c

echo "Installing APK..."
adb install -r "$APK"

echo "Launching $PKG via monkey..."
# 'am start -n pkg/activity' requires android:exported='true' on API 31+.
# Monkey emits a system-uid intent that bypasses the exported check.
adb shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 >/dev/null

echo "Waiting ${WAIT_SECS}s for main_menu boot + auto-redirect to level_3d..."
sleep "$WAIT_SECS"

echo "Dumping logcat..."
adb logcat -d > /tmp/logcat.txt

echo "===== filtered logcat (godot lines + ActivityTaskManager) ====="
grep -E "godot[[:space:]]+:|level_3d|main_menu|SMOKE|DebugLog|ActivityTaskManager.*$PKG|FATAL EXCEPTION" \
  /tmp/logcat.txt | tail -200 || true
echo "==============================================================="

# Assertion 1: main_menu boot (sanity — proves APK runs at all).
if ! grep -q "main_menu _ready" /tmp/logcat.txt; then
  echo "FAIL: main_menu _ready never appeared — APK didn't reach Godot."
  exit 2
fi
echo "OK: main_menu booted."

# Assertion 2: SMOKE auto-redirect scheduled.
if ! grep -q "SMOKE: auto-loading level_3d" /tmp/logcat.txt; then
  echo "FAIL: SMOKE auto-redirect was never scheduled — BuildInfo.SMOKE_TEST may not be stamped to true."
  exit 3
fi
echo "OK: SMOKE auto-redirect scheduled."

# Assertion 3: SMOKE change_scene actually fired.
if ! grep -q "SMOKE: change_scene" /tmp/logcat.txt; then
  echo "FAIL: SMOKE change_scene callback never fired — 2s timer didn't tick or scene tree blocked."
  echo "Last 30 godot lines:"
  grep "godot[[:space:]]\+:" /tmp/logcat.txt | tail -30 || true
  exit 4
fi
echo "OK: SMOKE change_scene fired."

# Assertion 4: THE BUG WE'RE HUNTING. If level_3d.gd's _init runs, the
# script attached at runtime and the iter 95-99 bug is gone. If not,
# the bug reproduces in CI and we can iterate on it 6-8 minutes/round.
if ! grep -q "level_3d.gd _init" /tmp/logcat.txt; then
  echo "FAIL: level_3d.gd _init NEVER FIRED — script did not attach at runtime."
  echo "This is the iter 95-99 bug reproducing in CI. Last 40 godot lines:"
  grep "godot[[:space:]]\+:" /tmp/logcat.txt | tail -40 || true
  exit 5
fi
echo "PASS: level_3d.gd _init fired — script attached successfully."

# Bonus assertions (don't fail the build, just report).
for marker in "_enter_tree" "_ready start" "containers added" "cowboy_3d added"; do
  if grep -q "level_3d.*$marker\|level_3d $marker" /tmp/logcat.txt; then
    echo "OK:  level_3d $marker"
  else
    echo "MISS: level_3d $marker (didn't fire — see logcat above)"
  fi
done
