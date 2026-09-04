; ============================================================
; "Screen 1.5" proof-of-concept for the SG-1000 port.
;
; Graphics II mode (M3=1) with the pattern/color table base
; registers' low bits forcing all three name-table "thirds" onto
; the SAME single 2KB bank (R4 bits0-1 = 0, R3 bits5-6 = 0).
; This gives:
;   - Only 2KB pattern table + 2KB color table (like Graphics I's
;     memory footprint / like having 256 unique tiles, not tripled)
;   - But a full 8-byte color table entry PER CHARACTER, i.e. an
;     independent fg/bg color pair for EACH of the 8 pixel rows of
;     a tile -- something Graphics I cannot do (it shares one
;     fg/bg pair across a whole group of 8 characters).
;
; This test fills the whole screen with character 0, whose pattern
; is a solid 8x8 block, and whose color table entry gives each of
; its 8 pixel rows a different foreground color -- producing 8px
; tall horizontal rainbow stripes across the entire 256x192 screen.
; That effect is only possible with the Graphics II per-line color
; table, proving the hybrid mode is configured correctly.
; ============================================================

VDP_DATA        equ 0xbe
VDP_CTRL        equ 0xbf

        org 0x0000
        di
        im 1
        ld sp,0xdff0
        jp start

        org 0x0038
        ei
        reti

        org 0x0066
        retn

        org 0x0100
start:
        ld hl,vdp_init_table
        ld b,vdp_init_table_end-vdp_init_table
        ld c,0x80
vdp_reg_loop:
        ld a,(hl)
        out (VDP_CTRL),a
        ld a,c
        out (VDP_CTRL),a
        inc hl
        inc c
        djnz vdp_reg_loop

        ; clear all 16KB of VRAM
        ld hl,0x0000
        call vram_set_addr_write
        ld bc,0x4000
clear_loop:
        xor a
        out (VDP_DATA),a
        dec bc
        ld a,b
        or c
        jr nz,clear_loop

        ; pattern for character 0: solid 8x8 block (all bits on)
        ld hl,0x0000
        call vram_set_addr_write
        ld b,8
        ld a,0xff
patt_loop:
        out (VDP_DATA),a
        djnz patt_loop

        ; color table entry for character 0: one fg/bg byte per pixel row,
        ; using a different foreground color on each of the 8 rows
        ld hl,0x2000
        call vram_set_addr_write
        ld hl,stripe_colors
        ld b,8
stripe_loop:
        ld a,(hl)
        out (VDP_DATA),a
        inc hl
        djnz stripe_loop

        ; fill the whole 32x24 name table with character 0
        ld hl,0x1800
        call vram_set_addr_write
        ld bc,32*24
name_loop:
        xor a
        out (VDP_DATA),a
        dec bc
        ld a,b
        or c
        jr nz,name_loop

        ; enable display (R1: 16K=1, BLANK=1)
        ld a,0xc0
        out (VDP_CTRL),a
        ld a,0x81
        out (VDP_CTRL),a

hang:
        halt
        jr hang

; hl = VRAM address to set up for writing via VDP_DATA
vram_set_addr_write:
        ld a,l
        out (VDP_CTRL),a
        ld a,h
        or 0x40
        out (VDP_CTRL),a
        ret

vdp_init_table:
        db 0x02                  ; R0: M3=1 (Graphics II mode select)
        db 0x80                  ; R1: 16K=1, display off during init
        db 0x06                  ; R2: name table base = 0x1800
        db 0x80                  ; R3: color table base=0x2000, bits5-6=0 -> collapsed to 1 bank
        db 0x00                  ; R4: pattern table base=0x0000, bits0-1=0 -> collapsed to 1 bank
        db 0x36                  ; R5: sprite attribute table base = 0x1b00 (unused in this test)
        db 0x00                  ; R6: sprite pattern table base = 0x0000 (unused)
        db 0x01                  ; R7: backdrop color = black
vdp_init_table_end:

; fg(high nibble)/bg=1(low nibble) per pixel row -- 8 distinct hues
stripe_colors:
        db 0x21, 0x31, 0x41, 0x51, 0x61, 0x71, 0x81, 0xa1

        ds 0x2000-$,0xff         ; pad to 8KB
