#!/usr/bin/env python3
"""Generate one image via Vertex AI Imagen 4 (Fast).

Usage:
  python3 tools/imagen_render.py --prompt "..." --out path/to/file.png
  python3 tools/imagen_render.py --prompt "..." --out path/to/file.png \
      --aspect 1:1 --candidates 1

Auth: gcloud application-default credentials. Same auth as Veo render.
Project: static-webbing-461904-c4, location: us-central1.

Cost: Imagen 4 Fast ~$0.02/image. We generate one candidate by default;
pass --candidates N for variation comparison.
"""
import argparse
import base64
import json
import subprocess
import sys
from pathlib import Path

PROJECT = "static-webbing-461904-c4"
LOCATION = "us-central1"
MODEL = "imagen-4.0-fast-generate-001"


def gcloud_token() -> str:
    r = subprocess.run(
        ["gcloud", "auth", "print-access-token"],
        capture_output=True, text=True, check=True,
    )
    return r.stdout.strip()


def generate(prompt: str, out: Path, aspect: str, candidates: int) -> None:
    import requests
    endpoint = (
        f"https://{LOCATION}-aiplatform.googleapis.com/v1/projects/"
        f"{PROJECT}/locations/{LOCATION}/publishers/google/models/{MODEL}:predict"
    )
    payload = {
        "instances": [{"prompt": prompt}],
        "parameters": {
            "sampleCount": candidates,
            "aspectRatio": aspect,
            "safetySetting": "block_only_high",
            "personGeneration": "dont_allow",
        },
    }
    r = requests.post(
        endpoint,
        headers={
            "Authorization": f"Bearer {gcloud_token()}",
            "Content-Type": "application/json",
        },
        json=payload,
        timeout=180,
    )
    if not r.ok:
        sys.exit(f"Imagen API error {r.status_code}: {r.text[:400]}")
    data = r.json()
    preds = data.get("predictions", [])
    if not preds:
        sys.exit(f"no predictions in response: {json.dumps(data)[:400]}")
    out.parent.mkdir(parents=True, exist_ok=True)
    for i, p in enumerate(preds):
        b64 = p.get("bytesBase64Encoded")
        if not b64:
            print(f"prediction {i}: no image bytes; skipping", file=sys.stderr)
            continue
        suffix = "" if candidates == 1 else f"_{i}"
        target = out.with_name(out.stem + suffix + out.suffix)
        target.write_bytes(base64.b64decode(b64))
        print(f"wrote {target} ({target.stat().st_size} bytes)")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--prompt", required=True)
    ap.add_argument("--out", required=True, type=Path)
    ap.add_argument("--aspect", default="1:1",
                    choices=["1:1", "9:16", "16:9", "4:3", "3:4"])
    ap.add_argument("--candidates", type=int, default=1)
    a = ap.parse_args()
    generate(a.prompt, a.out, a.aspect, a.candidates)


if __name__ == "__main__":
    main()
