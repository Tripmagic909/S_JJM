; ============================================================
; Ninja Jajamaru-kun SG-1000 port - M0: minimal boot smoke test
; Initializes the TMS9918 VDP in Graphics I mode and fills the
; screen with a solid color, to verify the toolchain (pasmo +
; MAME sg1000 headless run) end to end.
; ============================================================

VDP_DATA        equ 0xbe
VDP_CTRL        equ 0xbf

        org 0x0000
        di
        im 1
        ld sp,0xdff0
        jp start

        org 0x0038              ; IM1 interrupt vector
        ei
        reti

        org 0x0066               ; NMI vector (pause button)
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

        ; pattern for character 0: solid 8x8 block
        ld hl,0x0000
        call vram_set_addr_write
        ld b,8
        ld a,0xff
patt_loop:
        out (VDP_DATA),a
        djnz patt_loop

        ; color table entry covering char codes 0-7: fg=medium red(8), bg=black(1)
        ld hl,0x2000
        call vram_set_addr_write
        ld a,0x81
        out (VDP_DATA),a

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
        db 0x00                  ; R0: Graphics I mode
        db 0x80                  ; R1: 16K=1, display off during init
        db 0x0e                  ; R2: name table base = 0x3800
        db 0x80                  ; R3: color table base = 0x2000
        db 0x00                  ; R4: pattern table base = 0x0000
        db 0x76                  ; R5: sprite attribute table base = 0x3b00
        db 0x00                  ; R6: sprite pattern table base = 0x0000
        db 0x01                  ; R7: backdrop color = black
vdp_init_table_end:

        ds 0x2000-$,0xff         ; pad to 8KB
