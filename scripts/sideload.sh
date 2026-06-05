#!/usr/bin/env bash
# Build an installable sideload APK from the GitHub Actions "Android Debug
# Build" run, with a consistent name + location and automatic cleanup of old
# artifacts. Run it right after pushing — it waits for the build if needed.
#
#   scripts/sideload.sh                    # latest Android build; iter parsed from latest commit
#   scripts/sideload.sh 340                # force the iter number
#   scripts/sideload.sh 340 26681483788    # a specific workflow run id
#
# Output:  /tmp/nta_sideload/nta_iterNNN.apk   (debug-signed, universal, installable)
# The /tmp/nta_sideload dir is WIPED on every run so only the current APK is present.
set -euo pipefail

REPO="Joeputin100/Not_This_Again"
WORKFLOW="Android Debug Build"
ARTIFACT="app-debug-aab"
BUNDLETOOL="$HOME/.local/bin/bundletool-all.jar"
OUT_DIR="/tmp/nta_sideload"

cd "$(dirname "$0")/.."   # repo root (this script lives in <repo>/scripts)

ITER="${1:-$(git log -1 --format=%s | grep -oiE 'iter[0-9]+' | head -1 | grep -oE '[0-9]+')}"
[ -n "$ITER" ] || { echo "FATAL: could not determine iter number — pass it, e.g. scripts/sideload.sh 340"; exit 1; }

RUN_ID="${2:-$(gh run list -R "$REPO" --workflow "$WORKFLOW" --limit 1 --json databaseId --jq '.[0].databaseId')}"
[ -n "$RUN_ID" ] || { echo "FATAL: no '$WORKFLOW' run found"; exit 1; }

OUT="$OUT_DIR/nta_iter${ITER}.apk"
echo "==> iter $ITER · run $RUN_ID -> $OUT"

echo "==> waiting for build (returns immediately if already done) ..."
gh run watch "$RUN_ID" -R "$REPO" --exit-status || { echo "FATAL: build run $RUN_ID did not succeed"; exit 1; }

echo "==> cleaning old artifacts in $OUT_DIR ..."
rm -rf "$OUT_DIR"
STAGE="$OUT_DIR/.stage"
mkdir -p "$STAGE"

# `gh run download` intermittently HANGS on these ~430MB artifacts (iter352),
# so fetch the artifact zip straight from the REST API instead — fast + reliable.
echo "==> downloading $ARTIFACT (direct API) ..."
ART_ID="$(gh api "repos/$REPO/actions/runs/$RUN_ID/artifacts" \
	--jq ".artifacts[] | select(.name==\"$ARTIFACT\") | .id" 2>/dev/null | head -1)"
[ -n "$ART_ID" ] || { echo "FATAL: artifact $ARTIFACT not found on run $RUN_ID"; exit 1; }
gh api "repos/$REPO/actions/artifacts/$ART_ID/zip" > "$STAGE/art.zip"
[ "$(stat -c%s "$STAGE/art.zip" 2>/dev/null || echo 0)" -gt 1000000 ] || { echo "FATAL: artifact download failed"; exit 1; }
unzip -o "$STAGE/art.zip" -d "$STAGE" >/dev/null
AAB="$(find "$STAGE" -name '*.aab' | head -1)"
[ -n "$AAB" ] || { echo "FATAL: no .aab inside the artifact"; exit 1; }

echo "==> bundletool -> universal APK ..."
# -Djava.io.tmpdir keeps bundletool's scratch (AutoValue_BuildApksCommand*, ApkSigner*,
# uncompressed.zip — ~1.5GB/run) inside $STAGE so it's wiped with $OUT_DIR each run,
# instead of piling up in the system /tmp forever and filling the disk.
java -Djava.io.tmpdir="$STAGE" -jar "$BUNDLETOOL" build-apks --mode=universal --bundle="$AAB" --output="$STAGE/nta.apks" --overwrite >/dev/null
unzip -o "$STAGE/nta.apks" universal.apk -d "$STAGE" >/dev/null
mv "$STAGE/universal.apk" "$OUT"
rm -rf "$STAGE"

echo "==> DONE: $OUT  ($(du -h "$OUT" | cut -f1))"
