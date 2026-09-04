#!/usr/bin/env python3
"""Convert a 16x16 RGBA sprite PNG (transparent/red/white pixels) into
TMS9918 16x16 sprite pattern bytes (two 32-byte single-color layers,
since TMS9918 sprites are always one flat color each).

Usage: sprite_to_asm.py <sprite.png>
Prints Z80 `db` lines for the red and white layers, in the quadrant
order (top-left, bottom-left, top-right, bottom-right) that the
game's load_sprite_pattern routine expects.
"""
import sys
from PIL import Image

RED = (252, 85, 84)
WHITE = (255, 255, 255)


def to_quadrants(bits16):
    tl = [(bits16[y] >> 8) & 0xFF for y in range(8)]
    bl = [(bits16[y] >> 8) & 0xFF for y in range(8, 16)]
    tr = [bits16[y] & 0xFF for y in range(8)]
    br = [bits16[y] & 0xFF for y in range(8, 16)]
    return tl + bl + tr + br


def fmt(bytelist):
    return ",".join(f"0x{b:02x}" for b in bytelist)


def main(path):
    im = Image.open(path).convert("RGBA")
    assert im.size == (16, 16), f"expected 16x16, got {im.size}"
    red_bits, white_bits = [], []
    for y in range(16):
        rrow = wrow = 0
        for x in range(16):
            r, g, b, a = im.getpixel((x, y))
            if a > 0:
                if (r, g, b) == RED:
                    rrow |= 1 << (15 - x)
                elif (r, g, b) == WHITE:
                    wrow |= 1 << (15 - x)
        red_bits.append(rrow)
        white_bits.append(wrow)
    print("; red layer")
    print("db " + fmt(to_quadrants(red_bits)))
    print("; white layer")
    print("db " + fmt(to_quadrants(white_bits)))


if __name__ == "__main__":
    main(sys.argv[1])
