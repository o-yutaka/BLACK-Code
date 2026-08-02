#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import sys
from pathlib import Path

EXPECTED_SIZE = (1536, 2288)
FRAME_SIZE = (192, 208)
EXPECTED_SHA256 = "f7a5a2cf2d1995590720024d1738bb916fc80255dbea8be4e058fa249c6a7ed3"
MAX_BYTES = 20 * 1024 * 1024


def main() -> int:
    root = Path(__file__).resolve().parent
    try:
        from PIL import Image
    except ImportError:
        print("Pillow is required: python -m pip install -r requirements.txt", file=sys.stderr)
        return 2

    manifest = json.loads((root / "pet.json").read_text(encoding="utf-8"))
    expected = {
        "id": "black-sentinel",
        "displayName": "BLACK Sentinel",
        "spriteVersionNumber": 2,
        "spritesheetPath": "spritesheet.png",
    }
    for key, value in expected.items():
        if manifest.get(key) != value:
            raise AssertionError(f"manifest {key}={manifest.get(key)!r}, expected {value!r}")

    sprite = root / manifest["spritesheetPath"]
    payload = sprite.read_bytes()
    digest = hashlib.sha256(payload).hexdigest()

    if len(payload) > MAX_BYTES:
        raise AssertionError(f"spritesheet is {len(payload)} bytes; limit is {MAX_BYTES}")
    if digest != EXPECTED_SHA256:
        raise AssertionError(f"sha256={digest}, expected {EXPECTED_SHA256}")

    with Image.open(sprite) as image:
        image.load()
        if image.format != "PNG":
            raise AssertionError(f"format={image.format}, expected PNG")
        if image.size != EXPECTED_SIZE:
            raise AssertionError(f"size={image.size}, expected {EXPECTED_SIZE}")
        rgba = image.convert("RGBA")
        alpha = rgba.getchannel("A")
        occupied = 0
        for row in range(11):
            for col in range(8):
                left = col * FRAME_SIZE[0]
                top = row * FRAME_SIZE[1]
                cell = alpha.crop((left, top, left + FRAME_SIZE[0], top + FRAME_SIZE[1]))
                if cell.getbbox() is None:
                    raise AssertionError(f"empty frame at row={row}, col={col}")
                occupied += 1

    print(json.dumps({
        "verdict": "PASS",
        "id": manifest["id"],
        "atlas": "1536x2288",
        "grid": "8x11",
        "frames": occupied,
        "bytes": len(payload),
        "sha256": digest,
    }, indent=2))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(json.dumps({"verdict": "FAIL", "error": str(exc)}, indent=2), file=sys.stderr)
        raise
