#!/usr/bin/env python3
"""Generate 3 breed start frames for chicken burst spectacle (SP1 Task 4).

Each breed: 720x1280 portrait, chroma-green background (0,177,64),
panicked cartoon chicken centred at ~50% of frame height.

Uses Gemini gemini-3.1-flash-image-preview for image generation, key
pulled from GSM secret GEMINI_API_KEY.

Run: python3 tools/gen_chicken_frames.py
Outputs:
  godot/assets/sprites/props/chicken_rir.png
  godot/assets/sprites/props/chicken_leghorn.png
  godot/assets/sprites/props/chicken_silkie.png
"""
import base64
import json
import os
import subprocess
import sys
import urllib.request
from PIL import Image
import io

API_URL = (
    "https://generativelanguage.googleapis.com/v1beta/models/"
    "gemini-3.1-flash-image-preview:generateContent"
)

CANVAS = (720, 1280)
# Veo chroma-green (matches project spec)
GREEN = (0, 177, 64)
OUT_DIR = "godot/assets/sprites/props"

BREEDS = {
    "rir": (
        "A cartoon Rhode Island Red chicken on a flat solid chroma-green background "
        "(hex #00B140). The chicken is centred in the frame, occupying roughly half "
        "the image height. It is visibly panicked: wings spread wide, eyes wide and "
        "alarmed, beak open. Deep red-brown plumage, bright red comb and wattles. "
        "The chicken faces slightly left of camera. Full body visible — head to feet. "
        "No other elements. Flat colourful cartoon style."
    ),
    "leghorn": (
        "A cartoon White Leghorn chicken on a flat solid chroma-green background "
        "(hex #00B140). The chicken is centred in the frame, occupying roughly half "
        "the image height. It is visibly panicked: wings spread wide, eyes wide and "
        "alarmed, beak open. Pure white plumage, bright red comb and wattles. "
        "The chicken faces slightly left of camera. Full body visible — head to feet. "
        "No other elements. Flat colourful cartoon style."
    ),
    "silkie": (
        "A cartoon Silkie chicken on a flat solid chroma-green background "
        "(hex #00B140). The chicken is centred in the frame, occupying roughly half "
        "the image height. It is visibly panicked: wings spread wide, eyes wide and "
        "alarmed, beak open. Fluffy white plumage with black speckles, distinctive "
        "fluffy crest on head, small dark beak. The chicken faces slightly left of camera. "
        "Full body visible — head to feet. No other elements. Flat colourful cartoon style."
    ),
}


def get_api_key() -> str:
    result = subprocess.run(
        ["gcloud", "secrets", "versions", "access", "latest", "--secret=GEMINI_API_KEY"],
        capture_output=True, text=True, check=True
    )
    return result.stdout.strip()


def generate_image(prompt: str, api_key: str) -> bytes:
    """Call Gemini image-gen API and return raw PNG bytes."""
    body = json.dumps({
        "contents": [{"parts": [{"text": prompt}]}],
        "generationConfig": {"responseModalities": ["IMAGE"]}
    }).encode()

    req = urllib.request.Request(
        API_URL,
        data=body,
        headers={
            "Content-Type": "application/json",
            "x-goog-api-key": api_key,
        },
        method="POST"
    )
    with urllib.request.urlopen(req, timeout=120) as resp:
        data = json.loads(resp.read())

    # Walk candidates[0].content.parts to find inlineData
    parts = data["candidates"][0]["content"]["parts"]
    for part in parts:
        if "inlineData" in part:
            b64 = part["inlineData"]["data"]
            return base64.b64decode(b64)

    raise RuntimeError(f"No inlineData in response: {json.dumps(data)[:500]}")


def place_on_green_canvas(img_bytes: bytes) -> Image.Image:
    """Composite the Gemini image onto the 720x1280 chroma-green canvas.

    The generated image may already have a green background — this step
    ensures the canvas is exactly 720x1280 with the correct green value
    and the chicken occupies ~50% of the frame height (640 px).
    """
    src = Image.open(io.BytesIO(img_bytes)).convert("RGBA")

    target_h = 640  # ~50% of 1280
    ar = src.width / src.height
    target_w = round(target_h * ar)
    src = src.resize((target_w, target_h), Image.Resampling.LANCZOS)

    canvas = Image.new("RGB", CANVAS, GREEN)
    x = (CANVAS[0] - target_w) // 2
    # Vertical centre, slight offset toward bottom for natural grounding
    y = (CANVAS[1] - target_h) // 2 + 80
    canvas.paste(src, (x, y), src)
    return canvas


def main() -> None:
    os.makedirs(OUT_DIR, exist_ok=True)
    api_key = get_api_key()
    print(f"API key fetched ({len(api_key)} chars)")

    for breed, prompt in BREEDS.items():
        out_path = f"{OUT_DIR}/chicken_{breed}.png"
        print(f"\n==> Generating {breed} start frame ...")
        print(f"    Prompt (first 100): {prompt[:100]}...")

        img_bytes = generate_image(prompt, api_key)
        print(f"    Got {len(img_bytes)} bytes from Gemini")

        canvas = place_on_green_canvas(img_bytes)
        canvas.save(out_path)
        w, h = canvas.size
        print(f"    Saved {out_path}  ({w}x{h})")

    print("\nDone — 3 breed start frames written.")


if __name__ == "__main__":
    main()
