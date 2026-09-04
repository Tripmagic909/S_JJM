#!/bin/sh
# Assembles src/main.asm into build/jajamaru.sg using pasmo, builds the
# headless verification harness, runs it, and writes build/frame.png.
set -e
mkdir -p build
pasmo src/main.asm build/jajamaru.sg
gcc -O2 -Wall -o build/headless tools/headless/harness.c -lz80ex
./build/headless build/jajamaru.sg 2000000 build/frame.rgb
python3 tools/rgb_to_png.py build/frame.rgb build/frame.png
ls -l build/jajamaru.sg build/frame.png
