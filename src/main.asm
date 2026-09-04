; ============================================================
; Ninja Jajamaru-kun SG-1000 port - M4: platformer movement
; (gravity/jump/ground collision) + makibishi throw. VDP runs in
; "Screen 1.5" (Graphics II with pattern/color tables collapsed to
; a single 2KB bank each, see docs/tech_notes/screen1_5.md).
; Per-frame update is driven by the VBlank interrupt (IM1, fixed
; vector 0x0038), mirroring the H.TIMI-hook-driven architecture
; found in the MSX original (docs/msx_analysis/structure.md).
; Player/enemy/tile graphics are the candidates approved in M3
; (assets/jajamaru_final_16x16.png, assets/enemies/*_fc.png,
; assets/tiles/tile_brick_fc.png -- background tiles here still
; use the M2 placeholder ground strip pending M4/M5 level work).
;
; Known hardware limitation: TMS9918 sprites cannot be flipped
; horizontally, so jajamaru's sprite always faces the same way
; regardless of movement direction; only the makibishi's throw
; direction tracks facing.
; ============================================================

VDP_DATA        equ 0xbe
VDP_CTRL        equ 0xbf
PAD1_PORT       equ 0xdc

; work RAM (mirrored 1KB at 0xC000-0xC3FF)
PLAYER_X        equ 0xc000
PLAYER_Y        equ 0xc001
PLAYER_VY       equ 0xc002      ; signed, pixels/frame
PLAYER_ONGROUND equ 0xc003
PLAYER_FACING   equ 0xc004      ; 0 = right, 1 = left
PAD_PREV        equ 0xc005      ; previous frame's pad bits, for edge detection
MAKI_ACTIVE     equ 0xc006
MAKI_X          equ 0xc007
MAKI_Y          equ 0xc008
MAKI_DIR        equ 0xc009

; enemy 1 = frog (16x16, ground-walking patrol)
ENEMY1_X        equ 0xc00a
ENEMY1_DIR      equ 0xc00b      ; 0 = right, 1 = left
ENEMY1_ACTIVE   equ 0xc00c
ENEMY1_TIMER    equ 0xc00d      ; respawn countdown while inactive

; enemy 2 = ghost (16x8, floats above the ground, patrols)
ENEMY2_X        equ 0xc00e
ENEMY2_DIR      equ 0xc00f
ENEMY2_ACTIVE   equ 0xc010
ENEMY2_TIMER    equ 0xc011

SPRITE_ATTR_BASE equ 0x1b00

PLAYER_X_MAX    equ 239   ; 256 - 16 (sprite width) - 1
PLAYER_START_X  equ 112
GROUND_Y        equ 160   ; 176 (ground tile top) - 16 (sprite height)
JUMP_VY         equ 0xf6   ; -10 as two's complement
GRAVITY         equ 1
MAX_FALL_VY     equ 4
MAKI_SPEED      equ 3
MAKI_X_MIN      equ 0
MAKI_X_MAX      equ 248

ENEMY1_START_X  equ 40
ENEMY1_MIN_X    equ 40
ENEMY1_MAX_X    equ 200
ENEMY1_Y        equ 160          ; walks on the ground, same Y as the player
ENEMY_SPEED     equ 1
RESPAWN_FRAMES  equ 120

ENEMY2_START_X  equ 180
ENEMY2_MIN_X    equ 60
ENEMY2_MAX_X    equ 220
ENEMY2_Y        equ 144          ; floats 16px above the ground

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

        ; initial player/state
        ld a,PLAYER_START_X
        ld (PLAYER_X),a
        ld a,GROUND_Y
        ld (PLAYER_Y),a
        xor a
        ld (PLAYER_VY),a
        ld (PLAYER_FACING),a
        ld (PAD_PREV),a
        ld (MAKI_ACTIVE),a
        ld a,1
        ld (PLAYER_ONGROUND),a

        ld a,ENEMY1_START_X
        ld (ENEMY1_X),a
        xor a
        ld (ENEMY1_DIR),a
        ld a,1
        ld (ENEMY1_ACTIVE),a

        ld a,ENEMY2_START_X
        ld (ENEMY2_X),a
        ld a,1
        ld (ENEMY2_DIR),a
        ld a,1
        ld (ENEMY2_ACTIVE),a

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
        ld c,a                  ; c = this frame's pad bits (active low)

        bit 2,c                 ; Left
        jr nz,chk_right
        ld a,(PLAYER_X)
        or a
        jr z,chk_right
        dec a
        ld (PLAYER_X),a
        ld a,1
        ld (PLAYER_FACING),a
chk_right:
        bit 3,c                 ; Right
        jr nz,chk_jump
        ld a,(PLAYER_X)
        cp PLAYER_X_MAX
        jr nc,chk_jump
        inc a
        ld (PLAYER_X),a
        xor a
        ld (PLAYER_FACING),a
chk_jump:
        ; Jump on Button1 (bit4) rising edge, only while on ground
        ld a,(PAD_PREV)
        bit 4,a
        jr z,chk_throw          ; was already held last frame -> not a new press
        bit 4,c
        jr nz,chk_throw         ; not held now either
        ld a,(PLAYER_ONGROUND)
        or a
        jr z,chk_throw
        ld a,JUMP_VY
        ld (PLAYER_VY),a
        xor a
        ld (PLAYER_ONGROUND),a
chk_throw:
        ; Throw makibishi on Button2 (bit5) rising edge, only if none in flight
        ld a,(PAD_PREV)
        bit 5,a
        jr z,apply_gravity
        bit 5,c
        jr nz,apply_gravity
        ld a,(MAKI_ACTIVE)
        or a
        jr nz,apply_gravity
        call spawn_makibishi
apply_gravity:
        ld a,(PLAYER_ONGROUND)
        or a
        jr nz,update_maki       ; already resting on the ground -- nothing to do
        ld a,(PLAYER_VY)
        add a,GRAVITY
        cp MAX_FALL_VY+1
        jr nz,vy_stored
        ld a,MAX_FALL_VY
vy_stored:
        ld (PLAYER_VY),a
        ld e,a
        ld a,(PLAYER_Y)
        add a,e
        ld (PLAYER_Y),a
        cp GROUND_Y+1
        jr c,update_maki        ; still airborne
        ld a,GROUND_Y
        ld (PLAYER_Y),a
        xor a
        ld (PLAYER_VY),a
        ld a,1
        ld (PLAYER_ONGROUND),a
update_maki:
        call update_makibishi
        call update_enemies
        call check_collisions

        ld a,c
        ld (PAD_PREV),a
        call update_sprite_attr
        ret

; ------------------------------------------------------------
; Launch a makibishi from the player's position, in the direction
; jajamaru is currently facing.
; ------------------------------------------------------------
spawn_makibishi:
        ld a,1
        ld (MAKI_ACTIVE),a
        ld a,(PLAYER_FACING)
        ld (MAKI_DIR),a
        ld a,(PLAYER_Y)
        add a,4
        ld (MAKI_Y),a
        ld a,(MAKI_DIR)
        or a
        jr nz,spawn_left
        ld a,(PLAYER_X)
        add a,16
        ld (MAKI_X),a
        ret
spawn_left:
        ld a,(PLAYER_X)
        sub 8
        ld (MAKI_X),a
        ret

; ------------------------------------------------------------
; Move the in-flight makibishi (if any); deactivate it once it
; flies off either edge of the screen.
; ------------------------------------------------------------
update_makibishi:
        ld a,(MAKI_ACTIVE)
        or a
        ret z
        ld a,(MAKI_DIR)
        or a
        jr nz,maki_move_left
        ld a,(MAKI_X)
        add a,MAKI_SPEED
        ld (MAKI_X),a
        cp MAKI_X_MAX
        jr c,maki_done
        xor a
        ld (MAKI_ACTIVE),a
        ret
maki_move_left:
        ld a,(MAKI_X)
        sub MAKI_SPEED
        ld (MAKI_X),a
        cp MAKI_X_MIN
        jr nc,maki_done
        xor a
        ld (MAKI_ACTIVE),a
maki_done:
        ret

; ------------------------------------------------------------
; Patrol AI for the two enemies: walk back and forth between their
; min/max X, reversing direction at the bounds. While inactive
; (just defeated), count down a respawn timer instead.
; ------------------------------------------------------------
update_enemies:
        ld a,(ENEMY1_ACTIVE)
        or a
        jr z,e1_respawn_wait
        ld a,(ENEMY1_DIR)
        or a
        jr nz,e1_move_left
        ld a,(ENEMY1_X)
        add a,ENEMY_SPEED
        ld (ENEMY1_X),a
        cp ENEMY1_MAX_X
        jr c,e2_start
        ld a,1
        ld (ENEMY1_DIR),a
        jr e2_start
e1_move_left:
        ld a,(ENEMY1_X)
        sub ENEMY_SPEED
        ld (ENEMY1_X),a
        cp ENEMY1_MIN_X
        jr nc,e2_start
        xor a
        ld (ENEMY1_DIR),a
        jr e2_start
e1_respawn_wait:
        ld a,(ENEMY1_TIMER)
        or a
        jr z,e1_respawn_now
        dec a
        ld (ENEMY1_TIMER),a
        jr e2_start
e1_respawn_now:
        ld a,ENEMY1_START_X
        ld (ENEMY1_X),a
        ld a,1
        ld (ENEMY1_ACTIVE),a
e2_start:
        ld a,(ENEMY2_ACTIVE)
        or a
        jr z,e2_respawn_wait
        ld a,(ENEMY2_DIR)
        or a
        jr nz,e2_move_left
        ld a,(ENEMY2_X)
        add a,ENEMY_SPEED
        ld (ENEMY2_X),a
        cp ENEMY2_MAX_X
        jr c,update_enemies_done
        ld a,1
        ld (ENEMY2_DIR),a
        jr update_enemies_done
e2_move_left:
        ld a,(ENEMY2_X)
        sub ENEMY_SPEED
        ld (ENEMY2_X),a
        cp ENEMY2_MIN_X
        jr nc,update_enemies_done
        xor a
        ld (ENEMY2_DIR),a
        jr update_enemies_done
e2_respawn_wait:
        ld a,(ENEMY2_TIMER)
        or a
        jr z,e2_respawn_now
        dec a
        ld (ENEMY2_TIMER),a
        jr update_enemies_done
e2_respawn_now:
        ld a,ENEMY2_START_X
        ld (ENEMY2_X),a
        ld a,1
        ld (ENEMY2_ACTIVE),a
update_enemies_done:
        ret

; ------------------------------------------------------------
; a = X1, b = X2 -> returns with carry set if |X1-X2| < 16
; (used for both the X and Y axes of the 16x16 overlap test)
; ------------------------------------------------------------
overlap16:
        sub b
        jp p,ov_abs_done
        neg
ov_abs_done:
        cp 16
        ret

; ------------------------------------------------------------
; Makibishi-vs-enemy (defeats the enemy, starts its respawn timer)
; and player-vs-enemy (knocks the player back to the start) checks.
; ------------------------------------------------------------
check_collisions:
        ld a,(MAKI_ACTIVE)
        or a
        jr z,mvse2
        ld a,(ENEMY1_ACTIVE)
        or a
        jr z,mvse2
        ld a,(MAKI_X)
        ld b,a
        ld a,(ENEMY1_X)
        call overlap16
        jr nc,mvse2
        ld a,(MAKI_Y)
        ld b,a
        ld a,ENEMY1_Y
        call overlap16
        jr nc,mvse2
        xor a
        ld (ENEMY1_ACTIVE),a
        ld (MAKI_ACTIVE),a
        ld a,RESPAWN_FRAMES
        ld (ENEMY1_TIMER),a
mvse2:
        ld a,(MAKI_ACTIVE)
        or a
        jr z,pvse1
        ld a,(ENEMY2_ACTIVE)
        or a
        jr z,pvse1
        ld a,(MAKI_X)
        ld b,a
        ld a,(ENEMY2_X)
        call overlap16
        jr nc,pvse1
        ld a,(MAKI_Y)
        ld b,a
        ld a,ENEMY2_Y
        call overlap16
        jr nc,pvse1
        xor a
        ld (ENEMY2_ACTIVE),a
        ld (MAKI_ACTIVE),a
        ld a,RESPAWN_FRAMES
        ld (ENEMY2_TIMER),a
pvse1:
        ld a,(ENEMY1_ACTIVE)
        or a
        jr z,pvse2
        ld a,(PLAYER_X)
        ld b,a
        ld a,(ENEMY1_X)
        call overlap16
        jr nc,pvse2
        ld a,(PLAYER_Y)
        ld b,a
        ld a,ENEMY1_Y
        call overlap16
        jr nc,pvse2
        call player_hit
pvse2:
        ld a,(ENEMY2_ACTIVE)
        or a
        ret z
        ld a,(PLAYER_X)
        ld b,a
        ld a,(ENEMY2_X)
        call overlap16
        ret nc
        ld a,(PLAYER_Y)
        ld b,a
        ld a,ENEMY2_Y
        call overlap16
        ret nc
        call player_hit
        ret

; ------------------------------------------------------------
; Player got hit by an enemy: knock back to the start position.
; (No lives/health UI yet -- that's tracked for a later milestone.)
; ------------------------------------------------------------
player_hit:
        ld a,PLAYER_START_X
        ld (PLAYER_X),a
        ld a,GROUND_Y
        ld (PLAYER_Y),a
        xor a
        ld (PLAYER_VY),a
        ld a,1
        ld (PLAYER_ONGROUND),a
        ret

; ------------------------------------------------------------
; Write sprite attribute entries: jajamaru (red+white layers),
; then the makibishi if in flight, then a terminator.
; ------------------------------------------------------------
update_sprite_attr:
        ld hl,SPRITE_ATTR_BASE
        call vram_set_addr_write
        ; sprite 0: red layer (pattern 0-3)
        ld a,(PLAYER_Y)
        out (VDP_DATA),a
        ld a,(PLAYER_X)
        out (VDP_DATA),a
        xor a
        out (VDP_DATA),a        ; pattern number 0 (red quadrants 0-3)
        ld a,0x08
        out (VDP_DATA),a        ; color 8 = medium red
        ; sprite 1: white layer (pattern 4-7), same position
        ld a,(PLAYER_Y)
        out (VDP_DATA),a
        ld a,(PLAYER_X)
        out (VDP_DATA),a
        ld a,4
        out (VDP_DATA),a        ; pattern number 4 (white quadrants 0-3)
        ld a,0x0f
        out (VDP_DATA),a        ; color 15 = white

        ld a,(MAKI_ACTIVE)
        or a
        jr z,no_maki
        ld a,(MAKI_Y)
        out (VDP_DATA),a
        ld a,(MAKI_X)
        out (VDP_DATA),a
        ld a,8
        out (VDP_DATA),a        ; pattern number 8 (makibishi)
        ld a,0x0e
        out (VDP_DATA),a        ; color 14 = gray
no_maki:
        ld a,(ENEMY1_ACTIVE)
        or a
        jr z,no_enemy1
        ld a,ENEMY1_Y
        out (VDP_DATA),a
        ld a,(ENEMY1_X)
        out (VDP_DATA),a
        ld a,12
        out (VDP_DATA),a        ; pattern number 12 (frog quadrants 0-3)
        ld a,0x02
        out (VDP_DATA),a        ; color 2 = medium green
no_enemy1:
        ld a,(ENEMY2_ACTIVE)
        or a
        jr z,no_enemy2
        ld a,ENEMY2_Y
        out (VDP_DATA),a
        ld a,(ENEMY2_X)
        out (VDP_DATA),a
        ld a,16
        out (VDP_DATA),a        ; pattern number 16 (ghost quadrants 0-3)
        ld a,0x0d
        out (VDP_DATA),a        ; color 13 = magenta
no_enemy2:
        ld a,0xd0               ; terminator
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
; Sprite patterns: jajamaru (16x16, red+white layers built from
; two overlapping single-color sprites -- TMS9918 sprites are
; always one flat color each) plus a small makibishi projectile.
; Black/cutout areas are simply 0 bits in both layers, showing the
; background through (per the reference art: red+white, black=cutout).
; ------------------------------------------------------------
load_sprite_pattern:
        ld hl,0x0800
        call vram_set_addr_write
        ld hl,sprite_gfx
        ld b,sprite_gfx_end-sprite_gfx
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

; Sprite patterns. Because R1's SI bit selects 16x16 sprites for the
; *whole* VDP, every sprite here -- even visually 8x8/16x8 ones --
; occupies a full quadruple of 4 consecutive pattern numbers (TL,BL,
; TR,BR); unused quadrants are left as zero (blank/transparent) and
; explicitly zero-padded below so later entries land on the next
; multiple of 4.
;
; jajamaru 16x16 (patterns 0-3 red layer, 4-7 white layer). Derived
; from assets/jajamaru_final_16x16.png (see tools/sprite_to_asm.py).
; makibishi caltrop (8-11, only TL used). frog enemy 16x16 (12-15,
; from assets/enemies/enemy_frog_fc.png). ghost enemy (16-19, only
; TL/TR used, from assets/enemies/enemy_ghost_fc.png).
sprite_gfx:
        ; -- red layer (patterns 0-3) --
        db 0x03,0x1f,0x3f,0x20,0x20,0x20,0xe0,0xff   ; top-left
        db 0xff,0x7f,0x3f,0x00,0x1f,0x1e,0x00,0x00   ; bottom-left
        db 0xe0,0xf8,0xfe,0x7c,0x38,0x38,0x38,0xf0   ; top-right
        db 0xf8,0xfc,0xfc,0x08,0xf8,0x78,0x00,0x00   ; bottom-right
        ; -- white layer (patterns 4-7) --
        db 0x00,0x00,0x00,0x04,0x44,0xdf,0x1f,0x00   ; top-left
        db 0x00,0x00,0x00,0x07,0x00,0x00,0x3e,0x00   ; bottom-left
        db 0x00,0x00,0x00,0x80,0xc0,0xc0,0xc0,0x00   ; top-right
        db 0x00,0x03,0x02,0xf0,0x04,0x04,0x1c,0x00   ; bottom-right
        ; -- makibishi (patterns 8-11, only TL=8 used) --
        db 0x18,0x3c,0x7e,0xff,0xff,0x7e,0x3c,0x18   ; TL
        db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00   ; BL (unused)
        db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00   ; TR (unused)
        db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00   ; BR (unused)
        ; -- frog enemy (patterns 12-15) --
        db 0x07,0x0f,0x0f,0x1f,0x3f,0x0f,0xf3,0xfc   ; top-left
        db 0x00,0x00,0x00,0x70,0x3c,0x79,0xf0,0xf9   ; bottom-left
        db 0x70,0x98,0x98,0x9e,0xfc,0xfe,0xff,0xff   ; top-right
        db 0x00,0x00,0x00,0x00,0x00,0x00,0x80,0xc0   ; bottom-right
        ; -- ghost enemy (patterns 16-19, only TL=16/TR=18 used) --
        db 0x06,0x0d,0x1b,0x07,0x06,0x07,0x1b,0x10   ; TL (left tile)
        db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00   ; BL (unused)
        db 0xe0,0xf8,0xf8,0xfc,0x1c,0xfc,0x78,0x38   ; TR (right tile)
        db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00   ; BR (unused)
sprite_gfx_end:

        ds 0x2000-$,0xff         ; pad to 8KB
