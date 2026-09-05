#!/usr/bin/env python3
"""FC (NES)版CHR-ROMタイルの抽出・着色ツール。

重要: NESのスプライトはピクセル値0(2bppの2枚のプレーンが両方0)が常にハード
ウェア的に透明。パレットバイトの $0F (黒) は「値1/2/3が偶然黒である」場合に
限り出現し、それは抜き色ではなく実際に描画される黒である。
このツールは両者を混同しない(indexは常に透明、パレット値$0Fは常に不透明黒)。

Usage:
    python3 fc_chr_tool.py <rom_path> <out_dir>
"""
import sys
from PIL import Image

NES_PALETTE_RGB = {
    0x0F: (0, 0, 0),
    0x00: (102, 102, 102),
    0x30: (236, 238, 236),
    0x16: (152, 34, 32),
    0x1A: (0, 168, 68),
    0x25: (216, 0, 120),
    0x37: (188, 176, 0),
    0x20: (238, 238, 238),
    0x22: (0, 88, 248),
    0x28: (172, 124, 0),
    0x12: (0, 0, 252),
    0x26: (248, 120, 88),
}

# SPR0 = 0F 30 16 0F -> 透明/白/暗赤/黒(不透明)
PAL_SPR0 = (0x0F, 0x30, 0x16, 0x0F)
# SPR1 = 0F 30 0F 1A -> 透明/白/黒(不透明)/緑
PAL_SPR1 = (0x0F, 0x30, 0x0F, 0x1A)
# SPR2 = 0F 25 37 0F -> 透明/ピンク/タン/黒(不透明)
PAL_SPR2 = (0x0F, 0x25, 0x37, 0x0F)


def load_chr_banks(rom_path):
    with open(rom_path, "rb") as f:
        data = f.read()
    prg_units = data[4]
    chr_units = data[5]
    header_size = 16
    prg_size = prg_units * 16384
    chr_start = header_size + prg_size
    chr_data = data[chr_start:chr_start + chr_units * 8192]
    bank0 = chr_data[0:8192]
    bank1 = chr_data[8192:16384]
    return bank0, bank1


def palette_to_colors(pal_bytes):
    """index0は常に透明(RGBA alpha=0)。index1-3はパレットバイトのRGBで不透明。"""
    colors = [(0, 0, 0, 0)]
    for b in pal_bytes[1:]:
        rgb = NES_PALETTE_RGB.get(b, (255, 0, 255))
        colors.append(rgb + (255,))
    return colors


def get_tile_pixels(bank, tile_idx):
    """8x8タイルのピクセル値(0-3)を2次元リストで返す。"""
    off = tile_idx * 16
    plane0 = bank[off:off + 8]
    plane1 = bank[off + 8:off + 16]
    rows = []
    for y in range(8):
        p0 = plane0[y]
        p1 = plane1[y]
        row = []
        for x in range(8):
            bit = 7 - x
            v = ((p0 >> bit) & 1) | (((p1 >> bit) & 1) << 1)
            row.append(v)
        rows.append(row)
    return rows


def draw_tile(img, bank, tile_idx, colors, ox, oy, scale=1):
    rows = get_tile_pixels(bank, tile_idx)
    for y in range(8):
        for x in range(8):
            c = colors[rows[y][x]]
            if scale == 1:
                img.putpixel((ox + x, oy + y), c)
            else:
                for dy in range(scale):
                    for dx in range(scale):
                        img.putpixel((ox + x * scale + dx, oy + y * scale + dy), c)


def render_char_4tile(bank, base_idx, colors, scale=4):
    """1体=4連続タイル(左上,左下,右上,右下)を16x16として合成。"""
    img = Image.new("RGBA", (16 * scale, 16 * scale), (0, 0, 0, 0))
    draw_tile(img, bank, base_idx + 0, colors, 0, 0, scale)
    draw_tile(img, bank, base_idx + 1, colors, 0, 8 * scale, scale)
    draw_tile(img, bank, base_idx + 2, colors, 8 * scale, 0, scale)
    draw_tile(img, bank, base_idx + 3, colors, 8 * scale, 8 * scale, scale)
    return img


def render_char_row(bank, base_indices, colors, scale=4, bg=(160, 160, 160, 255), gap=4):
    """複数キャラを横に並べたシート。base_indicesは各キャラの開始タイル番号のリスト。"""
    n = len(base_indices)
    w = n * (16 * scale + gap) + gap
    h = 16 * scale + gap * 2
    sheet = Image.new("RGBA", (w, h), bg)
    for i, base in enumerate(base_indices):
        ch = render_char_4tile(bank, base, colors, scale)
        sheet.alpha_composite(ch, (gap + i * (16 * scale + gap), gap))
    return sheet


def render_single_tile_row(bank, indices, colors, scale=4, bg=(160, 160, 160, 255), gap=4):
    """1チップ(8x8)アイテム等を横に並べたシート。"""
    n = len(indices)
    w = n * (8 * scale + gap) + gap
    h = 8 * scale + gap * 2
    sheet = Image.new("RGBA", (w, h), bg)
    for i, idx in enumerate(indices):
        img = Image.new("RGBA", (8 * scale, 8 * scale), (0, 0, 0, 0))
        draw_tile(img, bank, idx, colors, 0, 0, scale)
        sheet.alpha_composite(img, (gap + i * (8 * scale + gap), gap))
    return sheet


def render_indexed_atlas(bank, colors, cols=16, scale=3, bg=(160, 160, 160, 255)):
    """バンク全体(通常512タイル)をグリッド+インデックス番号付きで書き出す(デバッグ/手動確認用)。"""
    from PIL import ImageDraw
    n_tiles = len(bank) // 16
    rows = (n_tiles + cols - 1) // cols
    cell = 8 * scale
    label_h = 10
    w = cols * cell
    h = rows * (cell + label_h)
    sheet = Image.new("RGBA", (w, h), bg)
    draw = ImageDraw.Draw(sheet)
    for idx in range(n_tiles):
        col = idx % cols
        row = idx // cols
        ox = col * cell
        oy = row * (cell + label_h)
        tile_img = Image.new("RGBA", (8 * scale, 8 * scale), (0, 0, 0, 0))
        draw_tile(tile_img, bank, idx, colors, 0, 0, scale)
        sheet.alpha_composite(tile_img, (ox, oy))
        draw.text((ox + 1, oy + cell), str(idx), fill=(0, 0, 0, 255))
    return sheet


def render_atlas_plain(bank, colors, cols=16, scale=3):
    """ラベル無し・隙間無しのタイトなアトラス(インタラクティブツールでのdrawImage
    クロップ用)。"""
    n_tiles = len(bank) // 16
    rows = (n_tiles + cols - 1) // cols
    cell = 8 * scale
    sheet = Image.new("RGBA", (cols * cell, rows * cell), (0, 0, 0, 0))
    for idx in range(n_tiles):
        col = idx % cols
        row = idx // cols
        draw_tile(sheet, bank, idx, colors, col * cell, row * cell, scale)
    return sheet


if __name__ == "__main__":
    rom_path = sys.argv[1]
    out_dir = sys.argv[2] if len(sys.argv) > 2 else "/tmp"
    bank0, bank1 = load_chr_banks(rom_path)
    colors_spr0 = palette_to_colors(PAL_SPR0)

    # ブロック1-5: 敵20体 (タイル0-79)
    enemy_bases = list(range(0, 80, 4))
    render_char_row(bank0, enemy_bases, colors_spr0).save(f"{out_dir}/blocks1_5_fixed.png")

    # ブロック6-7: アイテム32種 (タイル80-111)
    item_indices = list(range(80, 112))
    render_single_tile_row(bank0, item_indices, colors_spr0).save(f"{out_dir}/blocks6_7_fixed.png")

    # ブロック8-10: じゃじゃ丸12ポーズ (タイル112-159)
    jaja_bases = list(range(112, 160, 4))
    render_char_row(bank0, jaja_bases, colors_spr0).save(f"{out_dir}/blocks8_10_fixed.png")

    # ブロック11+: 追加敵+破片データ (タイル160-511)
    more_bases = list(range(160, 512, 4))
    # 1行に詰め込みすぎないよう分割
    chunk = 22
    for i in range(0, len(more_bases), chunk):
        part = more_bases[i:i + chunk]
        render_char_row(bank0, part, colors_spr0).save(f"{out_dir}/blocks11plus_fixed_{i // chunk}.png")

    # インデックス付き全体アトラス(bank0, bank1)
    render_indexed_atlas(bank0, colors_spr0).save(f"{out_dir}/bank0_indexed_atlas.png")
    render_indexed_atlas(bank1, colors_spr0).save(f"{out_dir}/bank1_indexed_atlas.png")

    render_atlas_plain(bank0, colors_spr0, scale=3).save(f"{out_dir}/bank0_plain_atlas.png")
    render_atlas_plain(bank1, colors_spr0, scale=3).save(f"{out_dir}/bank1_plain_atlas.png")

    print("done")
