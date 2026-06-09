#!/usr/bin/env bash
# Assert Godot boot breadcrumbs from a Firebase Test Lab run's logcat.
#
# Replaces the retired GH-hosted-emulator smoke job: that emulator's software
# GPU cannot run Godot 4.6 by EITHER path (Vulkan: QueuePresentKHR error 5 on
# present; GLES3 fallback: shader compile fails -> render target fails -> app
# dies). FTL's virtual devices render the game fine, and FTL stores the full
# device logcat in our results bucket, so the same breadcrumb assertions run
# against a phone that actually represents player hardware.
#
# Inputs (env):
#   RESULTS_BUCKET  e.g. ftl-results-static-webbing-461904-c4
#   RESULTS_DIR     e.g. smoke-<github run id>  (passed as --results-dir)
#
# The SA already has roles/storage.objectAdmin on the bucket (see the
# smoke-test.yml comment where the bucket was created).

set -euo pipefail

: "${RESULTS_BUCKET:?RESULTS_BUCKET not set}"
: "${RESULTS_DIR:?RESULTS_DIR not set}"

echo "Locating logcat under gs://${RESULTS_BUCKET}/${RESULTS_DIR}/ ..."
# One device => one logcat; '**' tolerates the device-named subdir
# (e.g. MediumPhone.arm-33-en-portrait/logcat).
LOGCAT_URI=$(gsutil ls "gs://${RESULTS_BUCKET}/${RESULTS_DIR}/**/logcat" | head -1)
if [ -z "$LOGCAT_URI" ]; then
  echo "FAIL: no logcat found in the FTL results dir."
  gsutil ls -r "gs://${RESULTS_BUCKET}/${RESULTS_DIR}/" || true
  exit 1
fi
echo "Found: $LOGCAT_URI"
gsutil cp "$LOGCAT_URI" /tmp/logcat.txt

echo "===== filtered logcat (godot lines) ====="
grep -E "godot[[:space:]]+:|level_3d|main_menu|SMOKE|FATAL EXCEPTION" \
  /tmp/logcat.txt | tail -200 || true
echo "========================================="

# Assertion 1: main_menu boot (sanity — proves the APK runs at all).
if ! grep -q "main_menu _ready" /tmp/logcat.txt; then
  echo "FAIL: main_menu _ready never appeared — APK didn't reach Godot."
  exit 2
fi
echo "OK: main_menu booted."

# Assertion 2: SMOKE deferred-load scheduled (BuildInfo.SMOKE_TEST stamped).
if ! grep -qE "SMOKE: (deferring|auto-loading) level_3d" /tmp/logcat.txt; then
  echo "FAIL: SMOKE redirect was never scheduled — BuildInfo.SMOKE_TEST may not be stamped to true."
  exit 3
fi
echo "OK: SMOKE redirect scheduled."

# Assertion 3: SMOKE change_scene actually fired.
if ! grep -q "SMOKE: change_scene" /tmp/logcat.txt; then
  echo "FAIL: SMOKE change_scene callback never fired."
  exit 4
fi
echo "OK: SMOKE change_scene fired."

# Assertion 4: the iter 95-99 class of bug — the gameplay script attached.
if ! grep -q "level_3d.gd _init" /tmp/logcat.txt; then
  echo "FAIL: level_3d.gd _init NEVER FIRED — script did not attach at runtime."
  grep "godot[[:space:]]\+:" /tmp/logcat.txt | tail -40 || true
  exit 5
fi
echo "PASS: level_3d.gd _init fired — script attached successfully."

# Bonus markers (report-only).
for marker in "_enter_tree" "_ready start" "containers added" "cowboy_3d added"; do
  if grep -q "level_3d.*$marker\|level_3d $marker" /tmp/logcat.txt; then
    echo "OK:  level_3d $marker"
  else
    echo "MISS: level_3d $marker (didn't fire — see logcat above)"
  fi
done
