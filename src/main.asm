; ============================================================
; Ninja Jajamaru-kun SG-1000 port - M2: minimal moving-character
; skeleton. VDP runs in "Screen 1.5" (Graphics II with pattern/
; color tables collapsed to a single 2KB bank each, see
; docs/tech_notes/screen1_5.md). Per-frame update is driven by
; the VBlank interrupt (IM1, fixed vector 0x0038), mirroring the
; H.TIMI-hook-driven architecture found in the MSX original
; (docs/msx_analysis/structure.md). Graphics here are placeholder
; programmer art -- final art is decided in M3.
; ============================================================

VDP_DATA        equ 0xbe
VDP_CTRL        equ 0xbf
PAD1_PORT       equ 0xdc

; work RAM (mirrored 1KB at 0xC000-0xC3FF)
PLAYER_X        equ 0xc000
PLAYER_Y        equ 0xc001

SPRITE_ATTR_BASE equ 0x1b00

PLAYER_X_MAX    equ 239   ; 256 - 16 (sprite width) - 1
PLAYER_Y_MAX    equ 175   ; 192 - 16 (sprite height) - 1

        org 0x0000
        di
        im 1
        ld sp,0xdff0
        jp start

        org 0x0038              ; VBlank interrupt (IM1 fixed vector)
        call frame_update
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

        call load_bg_tiles
        call load_name_table
        call load_sprite_pattern

        ; initial player position
        ld a,112
        ld (PLAYER_X),a
        ld a,80
        ld (PLAYER_Y),a
        call update_sprite_attr

        ; enable display + VBlank interrupt (R1: 16K=1,BLANK=1,IE=1,SI=1)
        ld a,0xe2
        out (VDP_CTRL),a
        ld a,0x81
        out (VDP_CTRL),a
        ei

hang:
        halt
        jr hang

; ------------------------------------------------------------
; Per-frame update, called from the VBlank interrupt handler.
; ------------------------------------------------------------
frame_update:
        in a,(PAD1_PORT)
        ld c,a                  ; c = pad bits (active low)

        bit 0,c                 ; Up
        jr nz,chk_down
        ld a,(PLAYER_Y)
        or a
        jr z,chk_down
        dec a
        ld (PLAYER_Y),a
chk_down:
        bit 1,c                 ; Down
        jr nz,chk_left
        ld a,(PLAYER_Y)
        cp PLAYER_Y_MAX
        jr nc,chk_left
        inc a
        ld (PLAYER_Y),a
chk_left:
        bit 2,c                 ; Left
        jr nz,chk_right
        ld a,(PLAYER_X)
        or a
        jr z,chk_right
        dec a
        ld (PLAYER_X),a
chk_right:
        bit 3,c                 ; Right
        jr nz,frame_update_done
        ld a,(PLAYER_X)
        cp PLAYER_X_MAX
        jr nc,frame_update_done
        inc a
        ld (PLAYER_X),a
frame_update_done:
        call update_sprite_attr
        ret

; ------------------------------------------------------------
; Write the player's sprite attribute entry (Y,X,pattern,color)
; ------------------------------------------------------------
update_sprite_attr:
        ld hl,SPRITE_ATTR_BASE
        call vram_set_addr_write
        ld a,(PLAYER_Y)
        out (VDP_DATA),a
        ld a,(PLAYER_X)
        out (VDP_DATA),a
        xor a
        out (VDP_DATA),a        ; pattern number 0 (quadrants 0-3)
        ld a,0x04
        out (VDP_DATA),a        ; color 4 = dark blue
        ld a,0xd0               ; terminator for sprite 1 (stop list)
        out (VDP_DATA),a
        ret

; ------------------------------------------------------------
; Background tiles: char 0 = sky, char 1 = ground (2-tone strip,
; using Screen 1.5's per-scanline color to fake a grass/dirt look)
; ------------------------------------------------------------
load_bg_tiles:
        ld hl,0x0000            ; pattern table, char 0 (sky: blank)
        call vram_set_addr_write
        ld b,8
        xor a
sky_patt_loop:
        out (VDP_DATA),a
        djnz sky_patt_loop

        ld hl,0x0008            ; pattern table, char 1 (ground: solid)
        call vram_set_addr_write
        ld b,8
        ld a,0xff
ground_patt_loop:
        out (VDP_DATA),a
        djnz ground_patt_loop

        ld hl,0x2000            ; color table, char 0 (sky = cyan)
        call vram_set_addr_write
        ld b,8
        ld a,0x71                ; fg=7 cyan, bg=1 black
sky_col_loop:
        out (VDP_DATA),a
        djnz sky_col_loop

        ld hl,0x2008            ; color table, char 1 (ground)
        call vram_set_addr_write
        ld a,0x32               ; row0: fg=3 light green, bg=2 dark green
        out (VDP_DATA),a
        ld a,0x32
        out (VDP_DATA),a
        ld a,0xa6               ; row2: fg=10 dark yellow, bg=6 dark red
        out (VDP_DATA),a
        ld a,0xa6
        out (VDP_DATA),a
        ld a,0xa6
        out (VDP_DATA),a
        ld a,0xa6
        out (VDP_DATA),a
        ld a,0xa6
        out (VDP_DATA),a
        ld a,0xa6
        out (VDP_DATA),a
        ret

; ------------------------------------------------------------
; Name table: bottom 2 rows = ground, rest = sky
; ------------------------------------------------------------
load_name_table:
        ld hl,0x1800
        call vram_set_addr_write
        ld bc,32*22              ; 704: needs a 16-bit counter, doesn't fit in B alone
nt_sky_loop:
        xor a
        out (VDP_DATA),a
        dec bc
        ld a,b
        or c
        jr nz,nt_sky_loop
        ld b,32*2
        ld a,1
nt_ground_loop:
        out (VDP_DATA),a
        djnz nt_ground_loop
        ret

; ------------------------------------------------------------
; Sprite pattern: a 16x16 placeholder character (4 quadrants at
; pattern numbers 0-3 in the sprite pattern table, base 0x0800)
; ------------------------------------------------------------
load_sprite_pattern:
        ld hl,0x0800
        call vram_set_addr_write
        ld hl,sprite_gfx
        ld b,32
sprite_gfx_loop:
        ld a,(hl)
        out (VDP_DATA),a
        inc hl
        djnz sprite_gfx_loop
        ret

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
        db 0x80                  ; R3: color table base=0x2000, collapsed (Screen 1.5)
        db 0x00                  ; R4: pattern table base=0x0000, collapsed (Screen 1.5)
        db 0x36                  ; R5: sprite attribute table base = 0x1b00
        db 0x01                  ; R6: sprite pattern table base = 0x0800
        db 0x07                  ; R7: backdrop color = cyan
vdp_init_table_end:

; 16x16 placeholder player sprite, 4 quadrants (top-left, bottom-left,
; top-right, bottom-right -- TMS9918 16x16 sprite pattern order)
sprite_gfx:
        db 0x0F,0x1F,0x1F,0x1F,0x1F,0x0F,0x1F,0x3F   ; top-left
        db 0x3F,0x3F,0x3F,0x3F,0x3C,0x3C,0x3C,0x7C   ; bottom-left
        db 0xC0,0xE0,0xE0,0xE0,0xE0,0xC0,0xE0,0xF0   ; top-right
        db 0xF0,0xF0,0xF0,0xF0,0x30,0x30,0x30,0x3E   ; bottom-right

        ds 0x2000-$,0xff         ; pad to 8KB
