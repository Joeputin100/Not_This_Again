#!/usr/bin/env bash
#
# tools/veo_render.sh — call Veo 3.1 via Vertex AI to generate a single
# animation clip from a starting image + prompt. Optionally pin the last
# frame to the same image for a seamless loop.
#
# Output: MP4 (Veo's only format) → automatically converted to OGV
# (Godot's native video format) and placed in the supplied --out-dir.
#
# Auth: uses Application Default Credentials. Run `gcloud auth login`
# first (interactive) or `gcloud auth application-default login`.
# CI/server use: service-account auth via gcloud.
#
# Usage:
#   tools/veo_render.sh \
#     --image godot/raw\ spritesheets/prospector.png \
#     --prompt "walks forward, swinging pickaxe; seamless loop" \
#     --loop \
#     --out-name forward \
#     --out-dir godot/assets/videos/prospector
#
# Cost (Veo 3.1 fast, ~$0.15/sec × 4s):
#   ~$0.60 per render. Total for 6 animations: ~$3.60.
set -euo pipefail

# ---- defaults ----
PROJECT="static-webbing-461904-c4"
LOCATION="us-central1"
MODEL="veo-3.1-fast-generate-001"
ASPECT="9:16"
DURATION=4
RESOLUTION="720p"
IMAGE=""
PROMPT=""
LOOP=false
OUT_NAME=""
OUT_DIR=""
KEEP_MP4=false
POLL_INTERVAL=8

# ---- parse args ----
while [[ $# -gt 0 ]]; do
	case $1 in
		--image)        IMAGE="$2"; shift 2 ;;
		--prompt)       PROMPT="$2"; shift 2 ;;
		--loop)         LOOP=true; shift ;;
		--out-name)     OUT_NAME="$2"; shift 2 ;;
		--out-dir)      OUT_DIR="$2"; shift 2 ;;
		--duration)     DURATION="$2"; shift 2 ;;
		--keep-mp4)     KEEP_MP4=true; shift ;;
		--model)        MODEL="$2"; shift 2 ;;
		*)              echo "Unknown arg: $1"; exit 2 ;;
	esac
done

if [[ -z "$IMAGE" || -z "$PROMPT" || -z "$OUT_NAME" || -z "$OUT_DIR" ]]; then
	echo "Usage: $0 --image PATH --prompt TEXT --out-name NAME --out-dir DIR [--loop] [--duration N] [--keep-mp4]"
	exit 2
fi

if [[ ! -f "$IMAGE" ]]; then
	echo "FATAL: image not found: $IMAGE"
	exit 2
fi

mkdir -p "$OUT_DIR"
WORK_DIR=$(mktemp -d)
trap "rm -rf $WORK_DIR" EXIT

# ---- build request ----
# Image base64 is 1-2 MB — too big for jq --arg (hits ARG_MAX). Write
# to a temp file and feed via --rawfile so the data goes through stdin,
# not argv.
B64_FILE="$WORK_DIR/img.b64"
base64 -w 0 "$IMAGE" > "$B64_FILE"
MIME_TYPE=$(file -b --mime-type "$IMAGE")

INSTANCE_JSON="$WORK_DIR/instance.json"
if $LOOP; then
	jq -n \
		--arg p "$PROMPT" \
		--rawfile b "$B64_FILE" \
		--arg m "$MIME_TYPE" \
		'{prompt: $p, image: {bytesBase64Encoded: $b, mimeType: $m}, lastFrame: {bytesBase64Encoded: $b, mimeType: $m}}' \
		> "$INSTANCE_JSON"
else
	jq -n \
		--arg p "$PROMPT" \
		--rawfile b "$B64_FILE" \
		--arg m "$MIME_TYPE" \
		'{prompt: $p, image: {bytesBase64Encoded: $b, mimeType: $m}}' \
		> "$INSTANCE_JSON"
fi

REQUEST_JSON="$WORK_DIR/request.json"
# --slurpfile reads INSTANCE_JSON via stdin-style I/O (no argv length
# limit). It produces an array containing the parsed file, so we index
# with [0] to get back the instance object.
jq -n \
	--slurpfile insts "$INSTANCE_JSON" \
	--arg ar "$ASPECT" \
	--argjson dur "$DURATION" \
	--arg res "$RESOLUTION" \
	'{instances: $insts, parameters: {aspectRatio: $ar, durationSeconds: $dur, sampleCount: 1, resolution: $res, personGeneration: "allow_all"}}' \
	> "$REQUEST_JSON"

ENDPOINT="https://${LOCATION}-aiplatform.googleapis.com/v1/projects/${PROJECT}/locations/${LOCATION}/publishers/google/models/${MODEL}:predictLongRunning"

echo "==> Submitting Veo render: $OUT_NAME"
echo "    Model:    $MODEL"
echo "    Image:    $IMAGE ($MIME_TYPE)"
echo "    Loop:     $LOOP"
echo "    Duration: ${DURATION}s @ $RESOLUTION ($ASPECT)"
echo "    Prompt:   ${PROMPT:0:80}..."

TOKEN=$(gcloud auth print-access-token)
SUBMIT=$(curl -sS -X POST \
	-H "Authorization: Bearer $TOKEN" \
	-H "Content-Type: application/json" \
	-d @"$REQUEST_JSON" \
	"$ENDPOINT")

OP_NAME=$(echo "$SUBMIT" | jq -r '.name // empty')
if [[ -z "$OP_NAME" ]]; then
	echo "FATAL: no operation name in response:"
	echo "$SUBMIT" | jq .
	exit 1
fi

echo "==> Operation: $OP_NAME"

# ---- poll ----
START_TIME=$(date +%s)
POLL_URL="https://${LOCATION}-aiplatform.googleapis.com/v1/${OP_NAME}"
while true; do
	# Refresh token in case the wait is long enough to expire it.
	TOKEN=$(gcloud auth print-access-token)
	STATUS=$(curl -sS -X POST \
		-H "Authorization: Bearer $TOKEN" \
		-H "Content-Type: application/json" \
		-d "{\"operationName\": \"$OP_NAME\"}" \
		"https://${LOCATION}-aiplatform.googleapis.com/v1/projects/${PROJECT}/locations/${LOCATION}/publishers/google/models/${MODEL}:fetchPredictOperation")
	DONE=$(echo "$STATUS" | jq -r '.done // false')
	ERROR=$(echo "$STATUS" | jq -r '.error.message // empty')
	if [[ -n "$ERROR" ]]; then
		echo "FATAL: Veo operation failed:"
		echo "$STATUS" | jq .
		exit 1
	fi
	if [[ "$DONE" == "true" ]]; then
		break
	fi
	ELAPSED=$(($(date +%s) - START_TIME))
	echo "    (${ELAPSED}s) still rendering..."
	sleep "$POLL_INTERVAL"
done

# ---- extract video ----
VIDEO_B64=$(echo "$STATUS" | jq -r '.response.videos[0].bytesBase64Encoded // empty')
GCS_URI=$(echo "$STATUS" | jq -r '.response.videos[0].gcsUri // empty')

MP4="$WORK_DIR/$OUT_NAME.mp4"
if [[ -n "$VIDEO_B64" ]]; then
	echo "$VIDEO_B64" | base64 -d > "$MP4"
elif [[ -n "$GCS_URI" ]]; then
	gcloud storage cp "$GCS_URI" "$MP4"
else
	echo "FATAL: no video in Veo response:"
	echo "$STATUS" | jq .
	exit 1
fi

ELAPSED=$(($(date +%s) - START_TIME))
echo "==> Got MP4 in ${ELAPSED}s ($(du -h "$MP4" | cut -f1))"

# ---- convert to OGV ----
OGV="$OUT_DIR/$OUT_NAME.ogv"
ffmpeg -y -i "$MP4" -c:v libtheora -q:v 7 -an "$OGV" 2>&1 | tail -1
echo "==> Wrote $OGV ($(du -h "$OGV" | cut -f1))"

if $KEEP_MP4; then
	cp "$MP4" "$OUT_DIR/$OUT_NAME.mp4"
	echo "==> Also kept MP4: $OUT_DIR/$OUT_NAME.mp4"
fi
