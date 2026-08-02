#!/usr/bin/env python3
"""Generate the BLACK Sentinel Codex V2 sprite atlas.

Contract:
- transparent PNG
- 1536 x 2288
- 8 columns x 11 rows
- 192 x 208 per frame
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

WIDTH, HEIGHT = 1536, 2288
CELL_W, CELL_H = 192, 208
SCALE = 3
STATES = [
    "idle",
    "running-right",
    "running-left",
    "waving",
    "jumping",
    "failed",
    "waiting",
    "running",
    "review",
]
P = {
    "ink": (8, 12, 20, 255),
    "shell": (18, 25, 38, 255),
    "shell2": (29, 40, 58, 255),
    "edge": (76, 105, 140, 255),
    "cyan": (55, 225, 255, 255),
    "blue": (42, 112, 255, 255),
    "violet": (138, 87, 255, 255),
    "white": (224, 248, 255, 255),
    "red": (255, 75, 92, 255),
}


def s(value: float) -> int:
    return int(round(value * SCALE))


def points(values):
    return [(s(x), s(y)) for x, y in values]


def ellipse(draw, box, fill, outline=None, width=1):
    draw.ellipse(tuple(s(v) for v in box), fill=fill, outline=outline, width=s(width))


def rounded(draw, box, radius, fill, outline=None, width=1):
    draw.rounded_rectangle(
        tuple(s(v) for v in box),
        radius=s(radius),
        fill=fill,
        outline=outline,
        width=s(width),
    )


def line(draw, values, fill, width=1):
    draw.line(points(values), fill=fill, width=s(width), joint="curve")


def polygon(draw, values, fill, outline=None):
    draw.polygon(points(values), fill=fill)
    if outline:
        draw.line(points(values + [values[0]]), fill=outline, width=s(1), joint="curve")


def glow(base, paint, radius=6):
    layer = Image.new("RGBA", base.size, (0, 0, 0, 0))
    paint(ImageDraw.Draw(layer))
    base.alpha_composite(layer.filter(ImageFilter.GaussianBlur(s(radius))))


def draw_pet(state: str, frame: int, look_angle: float | None = None) -> Image.Image:
    image = Image.new("RGBA", (CELL_W * SCALE, CELL_H * SCALE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    phase = frame / 8 * 2 * math.pi
    bob = math.sin(phase) * 2
    xoff, yoff, lean, wave, jump = 0.0, bob, 0.0, 0.0, 0.0
    core = P["cyan"]
    visor = P["cyan"]

    if state == "running-right":
        xoff, yoff, lean = math.sin(phase) * 2, abs(math.sin(phase)) * 2, 6
    elif state == "running-left":
        xoff, yoff, lean = -math.sin(phase) * 2, abs(math.sin(phase)) * 2, -6
    elif state == "waving":
        wave, bob = math.sin(phase) * 18, bob * 0.6
    elif state == "jumping":
        jump = -42 * math.sin(math.pi * frame / 7)
        yoff = jump
    elif state == "failed":
        yoff, lean, core, visor = 10 + min(frame, 4) * 1.2, -8, P["red"], P["red"]
    elif state == "waiting":
        yoff = 4 + math.sin(phase)
    elif state == "running":
        yoff = math.sin(phase * 2) * 1.5
    elif state == "review":
        yoff, lean = math.sin(phase), math.sin(phase) * 2

    cx, cy = 96 + xoff, 112 + yoff

    if state in ("running-right", "running-left"):
        direction = -1 if state == "running-right" else 1
        for k in range(3):
            yy = 74 + k * 24 + (frame * 7 + k * 9) % 12
            x1 = cx + direction * (50 + k * 12)
            line(draw, [(x1, yy), (x1 + direction * (25 + k * 7), yy)], (55, 225, 255, 110), 2)

    if state == "failed":
        for k in range(6):
            angle = (frame * 0.7 + k) * 1.7
            px = cx + math.cos(angle) * (35 + k * 3)
            py = cy - 28 + math.sin(angle) * (24 + k * 2)
            polygon(draw, [(px - 2, py - 2), (px + 3, py - 1), (px + 1, py + 3)], (255, 75, 92, 160))

    if state == "waiting":
        hx, hy = cx + 48, cy - 50
        glow(image, lambda g: g.ellipse((s(hx - 14), s(hy - 14), s(hx + 14), s(hy + 14)), fill=(55, 225, 255, 120)), 8)
        ellipse(draw, (hx - 16, hy - 16, hx + 16, hy + 16), (10, 26, 40, 150), (55, 225, 255, 180))
        line(draw, [(hx - 7, hy - 7), (hx + 7, hy - 7), (hx - 5, hy + 7), (hx + 5, hy + 7), (hx - 7, hy - 7)], P["cyan"])
        for k in range(3):
            angle = phase + k * 2 * math.pi / 3
            ox, oy = hx + math.cos(angle) * 22, hy + math.sin(angle) * 22
            ellipse(draw, (ox - 2, oy - 2, ox + 2, oy + 2), (55, 225, 255, 180))

    if state == "running":
        panel_y = 165
        glow(image, lambda g: g.rounded_rectangle((s(43), s(panel_y - 8), s(149), s(panel_y + 20)), radius=s(5), fill=(42, 112, 255, 100)), 6)
        rounded(draw, (43, panel_y - 8, 149, panel_y + 20), 5, (9, 23, 42, 165), (55, 225, 255, 130))
        for k in range(4):
            yy = panel_y - 1 + k * 5
            length = 22 + ((frame * 13 + k * 17) % 46)
            line(draw, [(57, yy), (57 + length, yy)], (55, 225, 255, 150))

    if state == "review":
        mx, my = cx + 50, cy - 46
        glow(image, lambda g: g.ellipse((s(mx - 18), s(my - 18), s(mx + 18), s(my + 18)), fill=(138, 87, 255, 100)), 7)
        ellipse(draw, (mx - 18, my - 18, mx + 18, my + 18), (12, 20, 40, 145), P["violet"], 2)
        line(draw, [(mx + 12, my + 12), (mx + 25, my + 25)], P["violet"], 4)
        for k in range(3):
            line(draw, [(mx - 8, my - 7 + k * 7), (mx + 7 + (frame + k) % 5, my - 7 + k * 7)], (224, 248, 255, 150))

    if state != "jumping" or jump > -28:
        alpha = int(80 * (1 - max(0, -jump) / 55))
        ellipse(draw, (cx - 43, 176, cx + 43, 185), (15, 110, 160, alpha))
    glow(image, lambda g: g.ellipse((s(cx - 22), s(cy + 5), s(cx + 22), s(cy + 49)), fill=(42, 112, 255, 100)), 10)

    tail_direction = -1 if state == "running-left" else 1
    sway = math.sin(phase) * 8
    tx0, ty0 = cx + tail_direction * 23, cy + 29
    tail = []
    for index in range(5):
        t = index / 4
        tail.append((
            tx0 + tail_direction * (18 + 30 * t) + math.sin(t * math.pi) * tail_direction * 10,
            ty0 + 12 * t + sway * t,
        ))
    line(draw, tail, P["edge"], 10)
    line(draw, tail, P["shell2"], 6)
    ellipse(draw, (tail[-1][0] - 5, tail[-1][1] - 5, tail[-1][0] + 5, tail[-1][1] + 5), P["cyan"])

    if state in ("running-right", "running-left"):
        stride = math.sin(phase)
        legs = ((cx - 15 + stride * 10, cy + 48 + abs(stride) * 2), (cx + 15 - stride * 10, cy + 48 + abs(stride) * 2))
    elif state == "jumping":
        tuck = 8 + 8 * math.sin(math.pi * frame / 7)
        legs = ((cx - 16, cy + 42 - tuck), (cx + 16, cy + 42 - tuck))
    elif state == "failed":
        legs = ((cx - 23, cy + 47), (cx + 10, cy + 52))
    else:
        legs = ((cx - 16, cy + 49), (cx + 16, cy + 49))
    for lx, ly in legs:
        line(draw, [(lx, ly - 12), (lx, ly + 7)], P["edge"], 8)
        line(draw, [(lx, ly - 12), (lx, ly + 7)], P["shell2"], 5)
        rounded(draw, (lx - 10, ly + 4, lx + 10, ly + 10), 4, P["ink"], P["cyan"])

    polygon(draw, [(cx - 33 + lean * .2, cy - 5), (cx - 28 + lean * .2, cy + 40), (cx, cy + 55), (cx + 28 + lean * .2, cy + 40), (cx + 33 + lean * .2, cy - 5)], P["shell"], P["edge"])
    rounded(draw, (cx - 25 + lean * .2, cy + 2, cx + 25 + lean * .2, cy + 44), 16, P["shell2"])
    polygon(draw, [(cx - 31, cy + 6), (cx - 47, cy + 18), (cx - 30, cy + 25)], P["ink"], P["blue"])
    polygon(draw, [(cx + 31, cy + 6), (cx + 47, cy + 18), (cx + 30, cy + 25)], P["ink"], P["blue"])

    core_radius = 8 + 2 * math.sin(phase)
    glow(image, lambda g: g.ellipse((s(cx - core_radius - 4), s(cy + 19 - core_radius - 4), s(cx + core_radius + 4), s(cy + 19 + core_radius + 4)), fill=core[:3] + (130,)), 7)
    ellipse(draw, (cx - core_radius, cy + 19 - core_radius, cx + core_radius, cy + 19 + core_radius), core)
    ellipse(draw, (cx - 3, cy + 16, cx + 3, cy + 22), P["white"])

    if state == "waving":
        line(draw, [(cx - 27, cy + 9), (cx - 42, cy + 26), (cx - 37, cy + 40)], P["shell2"], 5)
        handx, handy = cx + 43 + wave * .15, cy - 18 - wave
        line(draw, [(cx + 27, cy + 9), (cx + 42, cy - 2), (handx, handy)], P["edge"], 8)
        line(draw, [(cx + 27, cy + 9), (cx + 42, cy - 2), (handx, handy)], P["shell2"], 5)
        ellipse(draw, (handx - 6, handy - 6, handx + 6, handy + 6), P["cyan"])
    elif state == "running":
        typing = math.sin(phase * 2)
        for side in (-1, 1):
            handx, handy = cx + side * (25 + typing * 3), cy + 48 + side * typing * 3
            line(draw, [(cx + side * 26, cy + 7), (cx + side * 35, cy + 26), (handx, handy)], P["shell2"], 5)
            ellipse(draw, (handx - 4, handy - 4, handx + 4, handy + 4), P["cyan"])
    elif state == "failed":
        line(draw, [(cx - 28, cy + 9), (cx - 42, cy + 34), (cx - 47, cy + 45)], P["shell2"], 6)
        line(draw, [(cx + 28, cy + 9), (cx + 35, cy + 37), (cx + 33, cy + 49)], P["shell2"], 6)
    elif state == "review":
        handx, handy = cx + 37, cy - 11
        line(draw, [(cx + 27, cy + 8), (cx + 39, cy + 4), (handx, handy)], P["shell2"], 5)
        ellipse(draw, (handx - 4, handy - 4, handx + 4, handy + 4), P["violet"])
        line(draw, [(cx - 27, cy + 9), (cx - 40, cy + 25), (cx - 31, cy + 39)], P["shell2"], 5)
    else:
        for side in (-1, 1):
            swing = math.sin(phase) * side * 12 if state.startswith("running-") else 0
            handx, handy = cx + side * (40 + swing * .3), cy + 30 + swing
            line(draw, [(cx + side * 27, cy + 8), (cx + side * 38, cy + 20), (handx, handy)], P["shell2"], 5)
            ellipse(draw, (handx - 4, handy - 4, handx + 4, handy + 4), P["cyan"])

    rounded(draw, (cx - 11 + lean * .4, cy - 22, cx + 11 + lean * .4, cy + 4), 7, P["ink"], P["blue"])

    dx = dy = 0
    if look_angle is not None:
        radians = math.radians(look_angle - 90)
        dx, dy = math.cos(radians) * 5, math.sin(radians) * 4
    hx, hy = cx + lean, cy - 53
    ear_y = hy - 30
    polygon(draw, [(hx - 31, hy - 14), (hx - 20, ear_y - 5), (hx - 7, hy - 17)], P["shell2"], P["edge"])
    polygon(draw, [(hx + 31, hy - 14), (hx + 20, ear_y - 5), (hx + 7, hy - 17)], P["shell2"], P["edge"])
    polygon(draw, [(hx - 25, hy - 17), (hx - 20, ear_y + 2), (hx - 12, hy - 18)], P["blue"])
    polygon(draw, [(hx + 25, hy - 17), (hx + 20, ear_y + 2), (hx + 12, hy - 18)], P["blue"])
    polygon(draw, [(hx - 35, hy - 15), (hx - 26, hy + 22), (hx, hy + 35), (hx + 26, hy + 22), (hx + 35, hy - 15), (hx + 20, hy - 30), (hx - 20, hy - 30)], P["shell"], P["edge"])
    rounded(draw, (hx - 27, hy - 19, hx + 27, hy + 23), 14, P["shell2"])

    blink = state == "idle" and frame in (3, 4)
    visor_x, visor_y = hx + dx, hy + dy - 2
    if blink:
        line(draw, [(visor_x - 18, visor_y), (visor_x + 18, visor_y)], (55, 225, 255, 140), 2)
    else:
        glow(image, lambda g: g.rounded_rectangle((s(visor_x - 24), s(visor_y - 6), s(visor_x + 24), s(visor_y + 6)), radius=s(4), fill=visor[:3] + (120,)), 5)
        rounded(draw, (visor_x - 25, visor_y - 7, visor_x + 25, visor_y + 7), 5, (7, 18, 31, 255), visor)
        ellipse(draw, (visor_x - 7, visor_y - 3, visor_x - 1, visor_y + 3), P["white"])
        ellipse(draw, (visor_x + 2, visor_y - 3, visor_x + 8, visor_y + 3), P["white"])

    ellipse(draw, (hx - 4, hy - 25, hx + 4, hy - 17), P["violet"])
    rounded(draw, (hx - 12, hy + 22, hx + 12, hy + 30), 4, P["ink"], P["blue"])
    return image.resize((CELL_W, CELL_H), Image.Resampling.LANCZOS)


def build(output: Path) -> dict:
    atlas = Image.new("RGBA", (WIDTH, HEIGHT), (0, 0, 0, 0))
    for row, state in enumerate(STATES):
        for frame in range(8):
            atlas.alpha_composite(draw_pet(state, frame), (frame * CELL_W, row * CELL_H))

    for index in range(16):
        row, column = 9 + index // 8, index % 8
        atlas.alpha_composite(
            draw_pet("idle", index % 8, index * 22.5),
            (column * CELL_W, row * CELL_H),
        )

    quantized = atlas.quantize(colors=256, method=Image.Quantize.FASTOCTREE, dither=Image.Dither.NONE)
    output.parent.mkdir(parents=True, exist_ok=True)
    quantized.save(output, format="PNG", optimize=True)
    payload = output.read_bytes()
    return {
        "path": str(output),
        "bytes": len(payload),
        "sha256": hashlib.sha256(payload).hexdigest(),
        "size": [WIDTH, HEIGHT],
        "grid": [8, 11],
        "frames": 88,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, default=Path(__file__).resolve().parent / "spritesheet.png")
    args = parser.parse_args()
    print(json.dumps(build(args.output), indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
