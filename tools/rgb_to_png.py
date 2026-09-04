#!/usr/bin/env python3
"""Convert a raw 256x192 RGB24 buffer (as produced by tools/headless) to PNG.
Pure stdlib (zlib) implementation, no Pillow dependency."""
import sys
import struct
import zlib

WIDTH = 256
HEIGHT = 192


def write_png(path, rgb_data):
    def chunk(tag, data):
        c = tag + data
        return struct.pack(">I", len(data)) + c + struct.pack(">I", zlib.crc32(c) & 0xffffffff)

    raw = bytearray()
    stride = WIDTH * 3
    for y in range(HEIGHT):
        raw.append(0)  # filter type 0 (none)
        raw += rgb_data[y * stride:(y + 1) * stride]

    sig = b"\x89PNG\r\n\x1a\n"
    ihdr = struct.pack(">IIBBBBB", WIDTH, HEIGHT, 8, 2, 0, 0, 0)
    idat = zlib.compress(bytes(raw), 9)
    with open(path, "wb") as f:
        f.write(sig)
        f.write(chunk(b"IHDR", ihdr))
        f.write(chunk(b"IDAT", idat))
        f.write(chunk(b"IEND", b""))


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print(f"usage: {sys.argv[0]} in.rgb out.png", file=sys.stderr)
        sys.exit(1)
    with open(sys.argv[1], "rb") as f:
        data = f.read()
    expected = WIDTH * HEIGHT * 3
    if len(data) != expected:
        print(f"warning: expected {expected} bytes, got {len(data)}", file=sys.stderr)
    write_png(sys.argv[2], data)
