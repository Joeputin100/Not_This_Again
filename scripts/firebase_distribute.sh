#!/usr/bin/env bash
# Distribute an APK to Firebase App Distribution (App Tester) via the REST API +
# the gcloud access token — no firebase CLI / npm needed. Replaces the old
# sideload→SendUserFile flow: builds land on the tester's phone via App Tester.
#
#   scripts/firebase_distribute.sh /path/to/app.apk "release notes"
#
# App: Not This Again (android). Project static-webbing-461904-c4.
set -euo pipefail

APK="${1:?usage: firebase_distribute.sh APK [notes]}"
NOTES="${2:-}"
APP_ID="1:403450695023:android:0081db662840f9143f2c9a"
PROJECT_NUM="403450695023"
PROJECT_ID="static-webbing-461904-c4"   # quota project for the user-cred ADC
TESTERS="joeputin100@gmail.com"
API="https://firebaseappdistribution.googleapis.com"

[ -f "$APK" ] || { echo "FATAL: APK not found: $APK"; exit 2; }
TOKEN="$(gcloud auth print-access-token)"
QUOTA="X-Goog-User-Project: ${PROJECT_ID}"   # required, else PERMISSION_DENIED

echo "==> uploading $(basename "$APK") ($(du -h "$APK" | cut -f1)) to App Distribution ..."
UP="$(curl -sS -X POST \
  -H "Authorization: Bearer $TOKEN" \
  -H "$QUOTA" \
  -H "X-Goog-Upload-Protocol: raw" \
  -H "X-Goog-Upload-File-Name: $(basename "$APK")" \
  -H "Content-Type: application/octet-stream" \
  --data-binary "@$APK" \
  "${API}/upload/v1/projects/${PROJECT_NUM}/apps/${APP_ID}/releases:upload")"
OP="$(echo "$UP" | python3 -c "import sys,json; print(json.load(sys.stdin)['name'])" 2>/dev/null || true)"
[ -n "$OP" ] || { echo "FATAL: upload failed:"; echo "$UP" | head -c 1500; exit 3; }
echo "    operation: $OP"

REL=""
for _ in $(seq 1 80); do
  R="$(curl -sS -H "Authorization: Bearer $TOKEN" -H "$QUOTA" "${API}/v1/${OP}")"
  if echo "$R" | python3 -c "import sys,json; sys.exit(0 if json.load(sys.stdin).get('done') else 1)" 2>/dev/null; then
    REL="$(echo "$R" | python3 -c "import sys,json; print(json.load(sys.stdin)['response']['release']['name'])" 2>/dev/null || true)"
    break
  fi
  sleep 3
done
[ -n "$REL" ] || { echo "FATAL: upload did not finish / no release:"; echo "$R" | head -c 1500; exit 4; }
echo "    release: $REL"

# Release notes (optional).
if [ -n "$NOTES" ]; then
  curl -sS -X PATCH -H "Authorization: Bearer $TOKEN" -H "$QUOTA" -H "Content-Type: application/json" \
    -d "$(python3 -c "import json,sys; print(json.dumps({'releaseNotes':{'text':sys.argv[1]}}))" "$NOTES")" \
    "${API}/v1/${REL}?updateMask=release_notes.text" >/dev/null || true
fi

echo "==> distributing to: $TESTERS"
curl -sS -X POST -H "Authorization: Bearer $TOKEN" -H "$QUOTA" -H "Content-Type: application/json" \
  -d "{\"testerEmails\":[\"${TESTERS}\"]}" \
  "${API}/v1/${REL}:distribute" | head -c 500
echo
echo "==> DONE — available in the Firebase App Tester app for $TESTERS"
