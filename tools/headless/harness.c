/*
 * Headless SG-1000 test harness for verifying ROM builds without a
 * display. Executes a .sg ROM image with the z80ex CPU emulator and a
 * minimal TMS9918 (VDP) model covering Graphics I / Graphics II modes
 * and sprites, then dumps the rendered screen as a raw 256x192 RGB24
 * buffer for conversion to PNG.
 *
 * Usage: headless <rom.sg> <tstates_to_run> <out.rgb>
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <z80ex/z80ex.h>

static unsigned char mem[0x10000];
static unsigned char vram[0x4000];
static unsigned char vdpreg[8];
static unsigned char vdp_status;

static unsigned short vdp_addr;
static int vdp_ctrl_second_byte;
static unsigned char vdp_ctrl_first_byte;
static unsigned char vdp_read_buffer;

static unsigned char pad1, pad2;

static Z80EX_BYTE mem_read(Z80EX_CONTEXT *cpu, Z80EX_WORD addr, int m1_state, void *user_data) {
    (void)cpu; (void)m1_state; (void)user_data;
    if (addr >= 0xC000) {
        return mem[0xC000 + (addr & 0x03FF)];
    }
    return mem[addr];
}

static void mem_write(Z80EX_CONTEXT *cpu, Z80EX_WORD addr, Z80EX_BYTE value, void *user_data) {
    (void)cpu; (void)user_data;
    /* SG-1000: ROM is read-only below 0xC000; RAM is 1KB at 0xC000-0xC3FF mirrored to 0xFFFF */
    if (addr >= 0xC000) {
        mem[0xC000 + (addr & 0x03FF)] = value;
    }
}

static Z80EX_BYTE port_read(Z80EX_CONTEXT *cpu, Z80EX_WORD port, void *user_data) {
    (void)cpu; (void)user_data;
    unsigned char p = port & 0xFF;
    if (p == 0xBE) {
        unsigned char v = vdp_read_buffer;
        vdp_read_buffer = vram[vdp_addr];
        vdp_addr = (vdp_addr + 1) & 0x3FFF;
        vdp_ctrl_second_byte = 0;
        return v;
    } else if (p == 0xBF) {
        unsigned char v = vdp_status;
        vdp_status &= 0x1F; /* clear vblank flag (bit7) and others on read */
        vdp_ctrl_second_byte = 0;
        return v;
    } else if (p == 0xDC) {
        return pad1;
    } else if (p == 0xDD) {
        return pad2;
    }
    return 0xFF;
}

static void port_write(Z80EX_CONTEXT *cpu, Z80EX_WORD port, Z80EX_BYTE value, void *user_data) {
    (void)cpu; (void)user_data;
    unsigned char p = port & 0xFF;
    if (p == 0xBE) {
        vram[vdp_addr] = value;
        vdp_addr = (vdp_addr + 1) & 0x3FFF;
        vdp_read_buffer = value;
        vdp_ctrl_second_byte = 0;
    } else if (p == 0xBF) {
        if (!vdp_ctrl_second_byte) {
            vdp_ctrl_first_byte = value;
            vdp_ctrl_second_byte = 1;
        } else {
            vdp_ctrl_second_byte = 0;
            if (value & 0x80) {
                /* register write */
                unsigned char reg = value & 0x07;
                vdpreg[reg] = vdp_ctrl_first_byte;
            } else {
                /* set VRAM address; bits6-7 of second byte = mode (01=write,00=read) */
                vdp_addr = ((unsigned short)(value & 0x3F) << 8) | vdp_ctrl_first_byte;
                if ((value & 0xC0) == 0x00) {
                    vdp_read_buffer = vram[vdp_addr];
                    vdp_addr = (vdp_addr + 1) & 0x3FFF;
                }
            }
        }
    }
    /* PSG (0x7F) and others: ignored for graphics smoke tests */
}

static Z80EX_BYTE int_read(Z80EX_CONTEXT *cpu, void *user_data) {
    (void)cpu; (void)user_data;
    return 0xFF; /* IM1 ignores this value */
}

/* Standard TMS9918 16-color palette (approximate RGB values) */
static const unsigned char palette[16][3] = {
    {0,0,0}, {0,0,0}, {33,200,66}, {94,220,120},
    {84,85,237}, {125,118,252}, {212,82,77}, {66,235,245},
    {252,85,84}, {255,121,120}, {212,193,84}, {230,206,128},
    {33,176,59}, {201,91,186}, {204,204,204}, {255,255,255}
};

static unsigned char fb[192][256][3];

static void put_pixel(int x, int y, const unsigned char *rgb) {
    if (x < 0 || x >= 256 || y < 0 || y >= 192) return;
    fb[y][x][0] = rgb[0]; fb[y][x][1] = rgb[1]; fb[y][x][2] = rgb[2];
}

static void render_screen(void) {
    unsigned char m1 = (vdpreg[1] >> 4) & 1; /* text mode bit */
    unsigned char m2 = (vdpreg[1] >> 3) & 1; /* multicolor bit */
    unsigned char m3 = (vdpreg[0] >> 1) & 1; /* graphics II bit */
    int name_base = (vdpreg[2] & 0x0F) << 10;
    int color_base_g1 = vdpreg[3] << 6;
    int pattern_base_g1 = (vdpreg[4] & 0x07) << 11;

    const unsigned char *bg = palette[vdpreg[7] & 0x0F];
    for (int y = 0; y < 192; y++)
        for (int x = 0; x < 256; x++)
            put_pixel(x, y, bg);

    if (!m1 && !m2 && !m3) {
        /* Graphics I */
        for (int row = 0; row < 24; row++) {
            for (int col = 0; col < 32; col++) {
                unsigned char code = vram[name_base + row * 32 + col];
                int pat_addr = pattern_base_g1 + code * 8;
                int col_addr = color_base_g1 + (code >> 3);
                unsigned char colbyte = vram[col_addr & 0x3FFF];
                unsigned char fgc = (colbyte >> 4) & 0x0F;
                unsigned char bgc = colbyte & 0x0F;
                if (fgc == 0) fgc = vdpreg[7] & 0x0F;
                if (bgc == 0) bgc = vdpreg[7] & 0x0F;
                for (int line = 0; line < 8; line++) {
                    unsigned char patbyte = vram[(pat_addr + line) & 0x3FFF];
                    for (int bit = 0; bit < 8; bit++) {
                        int on = (patbyte >> (7 - bit)) & 1;
                        put_pixel(col * 8 + bit, row * 8 + line, palette[on ? fgc : bgc]);
                    }
                }
            }
        }
    } else if (m3 && !m1 && !m2) {
        /* Graphics II (also covers the "Screen 1.5" hybrid: R3/R4 low-bit
         * masks can collapse the 3 name-table thirds onto a single 2KB
         * pattern/color bank, giving Graphics-I-sized tables with
         * Graphics-II per-scanline color resolution). Formula verified
         * against the vrEmuTms9918 reference emulator implementation. */
        int pattern_base = (vdpreg[4] & 0x04) << 11;
        int color_base = (vdpreg[3] & 0x80) << 6;
        for (int row = 0; row < 24; row++) {
            int third = (row >> 3) & (vdpreg[4] & 0x03);      /* masked by R4 bits0-1 */
            int patt_off = third << 11;
            int color_off = patt_off & ((vdpreg[3] & 0x60) << 6); /* masked by R3 bits5-6 */
            for (int col = 0; col < 32; col++) {
                unsigned char code = vram[name_base + row * 32 + col];
                int pat_addr = (pattern_base + patt_off + code * 8) & 0x3FFF;
                int col_addr = (color_base + color_off + code * 8) & 0x3FFF;
                for (int line = 0; line < 8; line++) {
                    unsigned char patbyte = vram[(pat_addr + line) & 0x3FFF];
                    unsigned char colbyte = vram[(col_addr + line) & 0x3FFF];
                    unsigned char fgc = (colbyte >> 4) & 0x0F;
                    unsigned char bgc = colbyte & 0x0F;
                    if (fgc == 0) fgc = vdpreg[7] & 0x0F;
                    if (bgc == 0) bgc = vdpreg[7] & 0x0F;
                    for (int bit = 0; bit < 8; bit++) {
                        int on = (patbyte >> (7 - bit)) & 1;
                        put_pixel(col * 8 + bit, row * 8 + line, palette[on ? fgc : bgc]);
                    }
                }
            }
        }
    }

    /* Sprites (8x8 or 16x16, non-magnified), drawn for both graphics modes */
    {
        int sprite_attr_base = (vdpreg[5] & 0x7F) << 7;
        int sprite_pat_base = (vdpreg[6] & 0x07) << 11;
        int size16 = (vdpreg[1] >> 1) & 1;
        int dim = size16 ? 16 : 8;
        for (int s = 0; s < 32; s++) {
            int a = sprite_attr_base + s * 4;
            unsigned char sy = vram[a & 0x3FFF];
            if (sy == 0xD0) break; /* terminator */
            unsigned char sx = vram[(a + 1) & 0x3FFF];
            unsigned char scode = vram[(a + 2) & 0x3FFF];
            unsigned char scolor = vram[(a + 3) & 0x3FFF] & 0x0F;
            if (scolor == 0) continue; /* color 0 = transparent, sprite not drawn */
            if (size16) scode &= 0xFC;
            int pat_addr = sprite_pat_base + scode * 8;
            for (int line = 0; line < dim; line++) {
                int byte_off = (line < 8) ? line : (line + 8);
                unsigned char patbyte = vram[(pat_addr + byte_off) & 0x3FFF];
                for (int bit = 0; bit < 8; bit++) {
                    if ((patbyte >> (7 - bit)) & 1) {
                        put_pixel(sx + bit, sy + 1 + line, palette[scolor]);
                    }
                }
            }
        }
    }
}

static void write_rgb(const char *path) {
    FILE *f = fopen(path, "wb");
    if (!f) { perror("fopen"); exit(1); }
    fwrite(fb, 1, sizeof(fb), f);
    fclose(f);
}

int main(int argc, char **argv) {
    if (argc < 4) {
        fprintf(stderr, "usage: %s <rom.sg> <tstates> <out.rgb>\n", argv[0]);
        return 1;
    }
    FILE *rf = fopen(argv[1], "rb");
    if (!rf) { perror("fopen rom"); return 1; }
    size_t n = fread(mem, 1, sizeof(mem), rf);
    fclose(rf);
    fprintf(stderr, "loaded %zu bytes\n", n);

    long tstates_target = atol(argv[2]);

    Z80EX_CONTEXT *cpu = z80ex_create(mem_read, NULL, mem_write, NULL,
                                       port_read, NULL, port_write, NULL,
                                       int_read, NULL);
    z80ex_reset(cpu);

    long total = 0;
    long last_vblank = 0;
    const long frame_tstates = 59736; /* ~ NTSC Z80 T-states per frame at 3.579545MHz/59.92Hz */
    while (total < tstates_target) {
        total += z80ex_step(cpu);
        if (total - last_vblank >= frame_tstates) {
            last_vblank += frame_tstates;
            vdp_status |= 0x80;
            if (vdpreg[1] & 0x20) {
                z80ex_int(cpu);
            }
        }
    }

    render_screen();
    write_rgb(argv[3]);

    fprintf(stderr, "done. PC=%04X VDP regs:", z80ex_get_reg(cpu, regPC));
    for (int i = 0; i < 8; i++) fprintf(stderr, " %02X", vdpreg[i]);
    fprintf(stderr, "\n");

    z80ex_destroy(cpu);
    return 0;
}
