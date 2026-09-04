#!/usr/bin/env python3
"""Reconstruct approximate MSX SCREEN2 (Graphics II) tile/screen mockups
from statically-extracted LDIRVM call parameters, for internal reference
during the SG-1000 port's art design (M1/M3). Not for redistribution --
output images are working references only.
"""
import sys
import struct
import zlib

ROM_PATH = sys.argv[1] if len(sys.argv) > 1 else None
ROM_BASE = 0x4000

PALETTE = [
    (0, 0, 0), (0, 0, 0), (33, 200, 66), (94, 220, 120),
    (84, 85, 237), (125, 118, 252), (212, 82, 77), (66, 235, 245),
    (252, 85, 84), (255, 121, 120), (212, 193, 84), (230, 206, 128),
    (33, 176, 59), (201, 91, 186), (204, 204, 204), (255, 255, 255),
]


def write_png(path, w, h, rgb):
    def chunk(tag, data):
        c = tag + data
        return struct.pack(">I", len(data)) + c + struct.pack(">I", zlib.crc32(c) & 0xffffffff)
    raw = bytearray()
    stride = w * 3
    for y in range(h):
        raw.append(0)
        raw += rgb[y * stride:(y + 1) * stride]
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n")
        f.write(chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)))
        f.write(chunk(b"IDAT", zlib.compress(bytes(raw), 9)))
        f.write(chunk(b"IEND", b""))


def load_rom(path):
    with open(path, "rb") as f:
        return f.read()


def apply_writes(vram, rom, writes):
    for w in writes:
        src, dst, length = w["src"], w["dst"], w["len"]
        if src is None or dst is None or length is None:
            continue
        off = src - ROM_BASE
        if off < 0 or off + length > len(rom):
            continue
        vram[dst:dst + length] = rom[off:off + length]


def render_screen(vram, out_path):
    W, H = 256, 192
    fb = bytearray(W * H * 3)

    def put(x, y, rgb):
        if 0 <= x < W and 0 <= y < H:
            i = (y * W + x) * 3
            fb[i:i + 3] = bytes(rgb)

    name_base = 0x3800
    for row in range(24):
        third = row // 8
        block = third * 0x800
        for col in range(32):
            code = vram[name_base + row * 32 + col]
            pat_addr = (block + code * 8) & 0x3FFF
            col_addr = (0x2000 + block + code * 8) & 0x3FFF
            for line in range(8):
                patbyte = vram[(pat_addr + line) & 0x3FFF]
                colbyte = vram[(col_addr + line) & 0x3FFF]
                fg = (colbyte >> 4) & 0x0F
                bg = colbyte & 0x0F
                for bit in range(8):
                    on = (patbyte >> (7 - bit)) & 1
                    put(col * 8 + bit, row * 8 + line, PALETTE[fg if on else bg])
    write_png(out_path, W, H, fb)


def render_tileset(vram, out_path, bank):
    """Render all 256 characters of one pattern/color bank as a 16x16 tile sheet."""
    block = bank * 0x800
    cols, rows = 16, 16
    W, H = cols * 8, rows * 8
    fb = bytearray(W * H * 3)

    def put(x, y, rgb):
        if 0 <= x < W and 0 <= y < H:
            i = (y * W + x) * 3
            fb[i:i + 3] = bytes(rgb)

    for code in range(256):
        pat_addr = (block + code * 8) & 0x3FFF
        col_addr = (0x2000 + block + code * 8) & 0x3FFF
        tx, ty = (code % cols) * 8, (code // cols) * 8
        for line in range(8):
            patbyte = vram[(pat_addr + line) & 0x3FFF]
            colbyte = vram[(col_addr + line) & 0x3FFF]
            fg = (colbyte >> 4) & 0x0F
            bg = colbyte & 0x0F
            for bit in range(8):
                on = (patbyte >> (7 - bit)) & 1
                put(tx + bit, ty + line, PALETTE[fg if on else bg])
    write_png(out_path, W, H, fb)


if __name__ == "__main__":
    import json
    rom = load_rom(ROM_PATH)
    calls = json.load(open(sys.argv[2]))
    by_addr = {c["call_addr"]: c for c in calls}

    def pick(*addrs):
        return [by_addr[a] for a in addrs if a in by_addr]

    # Cluster A: early "common" tileset (title / shared UI+sprites), loaded once at boot
    clusterA = pick(0x497c, 0x4987, 0x4991, 0x49a2, 0x49ad, 0x49b7,
                     0x49cf, 0x49da, 0x49e4, 0x49f4, 0x49fe, 0x4a0b, 0x4a16, 0x4a20)
    vramA = bytearray(0x4000)
    apply_writes(vramA, rom, clusterA)
    render_tileset(vramA, "build/msx_tileset_A.png", bank=0)

    # Add a level name table on top of cluster A tileset for a screen mockup
    vramA_screen = bytearray(vramA)
    apply_writes(vramA_screen, rom, pick(0x520d))
    render_screen(vramA_screen, "build/msx_screen_A.png")

    # Cluster B: secondary tileset used later (0xb001-0xb06f region)
    clusterB = pick(0xb001, 0xb012, 0xb01d, 0xb027, 0xb033, 0xb03f, 0xb04b, 0xb057, 0xb063, 0xb06f)
    vramB = bytearray(0x4000)
    apply_writes(vramB, rom, clusterB)
    render_tileset(vramB, "build/msx_tileset_B.png", bank=0)
    render_screen(vramB, "build/msx_screen_B.png")

    print("done")
