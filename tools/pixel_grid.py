#!/usr/bin/env python3
"""Shared helper: render an ASCII pixel-grid sprite/tile design (list of
equal-length strings) to a PNG using the TMS9918 16-color palette, plus an
upscaled checkerboard preview. Used for M3+ art candidates before wiring
them into VRAM pattern/color data.
"""
from PIL import Image

TMS9918_PALETTE = {
    0: (0, 0, 0, 0),
    1: (0, 0, 0, 255),
    2: (33, 200, 66, 255),
    3: (94, 220, 120, 255),
    4: (84, 85, 237, 255),
    5: (125, 118, 252, 255),
    6: (212, 82, 77, 255),
    7: (66, 235, 245, 255),
    8: (252, 85, 84, 255),
    9: (255, 121, 120, 255),
    10: (212, 193, 84, 255),
    11: (230, 206, 128, 255),
    12: (33, 176, 59, 255),
    13: (201, 91, 186, 255),
    14: (204, 204, 204, 255),
    15: (255, 255, 255, 255),
}


def render(rows, charmap, out_path):
    h = len(rows)
    w = len(rows[0])
    im = Image.new("RGBA", (w, h))
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            im.putpixel((x, y), charmap.get(ch, (0, 0, 0, 0)))
    im.save(out_path)
    return im


def preview(path, scale, bg=(60, 60, 60, 255), bg2=(40, 40, 40, 255)):
    im = Image.open(path).convert("RGBA")
    W, H = im.width * scale, im.height * scale
    canvas = Image.new("RGBA", (W, H), bg)
    px = canvas.load()
    for y in range(H):
        for x in range(W):
            if ((x // scale) + (y // scale)) % 2 == 0:
                px[x, y] = bg2
    up = im.resize((W, H), Image.NEAREST)
    canvas.alpha_composite(up)
    out = path.replace(".png", "_preview.png")
    canvas.convert("RGB").save(out)
    return out
