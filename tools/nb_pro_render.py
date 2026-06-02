#!/usr/bin/env python3
"""Generate one image via Nano Banana Pro (Gemini 3 Pro Image) on Vertex AI,
optionally conditioned on one or more REFERENCE images (image-to-image).

This is the sibling of imagen_render.py, but NB Pro accepts reference images
(imagen_render is text-only) — so it can put *our* cowboy on *the* peppermint
horse by passing both as references.

Usage:
  python3 tools/nb_pro_render.py \
      --prompt "..." --out path/to/file.png \
      --ref godot/.../cowboy.png --ref /tmp/.../horse.png \
      --aspect 1:1

  # text-only (no --ref) also works.

Auth: gcloud application-default credentials (same as imagen_render / veo_render).
Project: static-webbing-461904-c4. Default location: global (NB Pro lives there;
pass --location us-central1 to try the regional endpoint).

On HTTP error the full response body is printed so the model id / endpoint /
modality can be diagnosed and adjusted.
"""
import argparse
import base64
import json
import mimetypes
import subprocess
import sys
from pathlib import Path

PROJECT = "static-webbing-461904-c4"
DEFAULT_LOCATION = "global"
DEFAULT_MODEL = "gemini-3-pro-image-preview"  # Nano Banana Pro


def gcloud_token() -> str:
    r = subprocess.run(
        ["gcloud", "auth", "print-access-token"],
        capture_output=True, text=True, check=True,
    )
    return r.stdout.strip()


def _ref_part(path: Path) -> dict:
    mime = mimetypes.guess_type(str(path))[0] or "image/png"
    data = base64.b64encode(path.read_bytes()).decode("ascii")
    return {"inlineData": {"mimeType": mime, "data": data}}


def generate(prompt: str, out: Path, refs: list[Path], aspect: str,
             model: str, location: str) -> None:
    import requests

    host = ("aiplatform.googleapis.com" if location == "global"
            else f"{location}-aiplatform.googleapis.com")
    endpoint = (
        f"https://{host}/v1/projects/{PROJECT}/locations/{location}"
        f"/publishers/google/models/{model}:generateContent"
    )

    parts: list[dict] = [{"text": prompt}]
    for r in refs:
        parts.append(_ref_part(r))

    payload = {
        "contents": [{"role": "user", "parts": parts}],
        "generationConfig": {
            "responseModalities": ["TEXT", "IMAGE"],
            "imageConfig": {"aspectRatio": aspect},
        },
    }

    resp = requests.post(
        endpoint,
        headers={
            "Authorization": f"Bearer {gcloud_token()}",
            "Content-Type": "application/json",
        },
        data=json.dumps(payload),
        timeout=300,
    )
    if resp.status_code != 200:
        print(f"HTTP {resp.status_code} from {endpoint}", file=sys.stderr)
        print(resp.text[:4000], file=sys.stderr)
        sys.exit(2)

    body = resp.json()
    cands = body.get("candidates", [])
    if not cands:
        print("No candidates in response:", file=sys.stderr)
        print(json.dumps(body)[:4000], file=sys.stderr)
        sys.exit(3)

    saved = False
    for part in cands[0].get("content", {}).get("parts", []):
        inline = part.get("inlineData") or part.get("inline_data")
        if inline and inline.get("data"):
            out.parent.mkdir(parents=True, exist_ok=True)
            out.write_bytes(base64.b64decode(inline["data"]))
            saved = True
            print(f"wrote {out} ({out.stat().st_size} bytes)")
            break
        if part.get("text"):
            print(f"[model text] {part['text'][:500]}", file=sys.stderr)
    if not saved:
        print("No image part returned. Full response:", file=sys.stderr)
        print(json.dumps(body)[:4000], file=sys.stderr)
        sys.exit(4)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--prompt", required=True)
    ap.add_argument("--out", required=True, type=Path)
    ap.add_argument("--ref", action="append", default=[], type=Path,
                    help="reference image (repeatable)")
    ap.add_argument("--aspect", default="1:1",
                    help="1:1 | 16:9 | 9:16 | 4:3 | 3:4")
    ap.add_argument("--model", default=DEFAULT_MODEL)
    ap.add_argument("--location", default=DEFAULT_LOCATION)
    a = ap.parse_args()
    for r in a.ref:
        if not r.exists():
            print(f"reference not found: {r}", file=sys.stderr)
            sys.exit(1)
    generate(a.prompt, a.out, a.ref, a.aspect, a.model, a.location)


if __name__ == "__main__":
    main()
