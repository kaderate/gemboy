SECTION "Header", ROM0[$0100]
    jp Start
    db $00
    db $CE,$ED,$66,$66,$CC,$0D,$00,$0B
    db $03,$73,$00,$83,$00,$0C,$00,$0D
    db $00,$08,$11,$1F,$88,$89,$00,$0E
    db $DC,$CC,$6E,$E6,$DD,$DD,$D9,$99
    db $BB,$BB,$67,$63,$6E,$0E,$EC,$CC
    db $DD,$DC,$99,$9F,$BB,$B9,$33,$3E
    db "DISPLAY_SPR_1  "
    db $00
    db $00, $00
    db $00
    db $00
    db $00
    db $00
    db $01
    db $33
    db $01
    db $00
    db $00, $00

SECTION "WRAM", WRAM0[$C000]
SpriteX: ds 1
SpriteY: ds 1
SpriteDX: ds 1   ; direction X : 1 = droite, $FF = gauche
SpriteDY: ds 1   ; direction Y : 1 = bas,    $FF = haut

SECTION "Main", ROM0[$0150]

DEF LCDC EQU $FF40
DEF SCY  EQU $FF42
DEF SCX  EQU $FF43
DEF LY   EQU $FF44
DEF BGP  EQU $FF47
DEF OBP0 EQU $FF48

Start:
    ; ── Copier les tiles BG + sprite (9 tiles = 144 octets) ──────────────────
    ld hl, TileData
    ld de, $8000
    ld bc, TileDataEnd - TileData
CopyTiles:
    ld a, [hl+]
    ld [de], a
    inc de
    dec bc
    ld a, b
    or c
    jr nz, CopyTiles

    ; ── Copier la tilemap BG (1024 octets) en VRAM $9800 ─────────────────────
    ld hl, TilemapData
    ld de, $9800
    ld bc, $0400
CopyTilemap:
    ld a, [hl+]
    ld [de], a
    inc de
    dec bc
    ld a, b
    or c
    jr nz, CopyTilemap

    ; ── Palettes ──────────────────────────────────────────────────────────────
    ld a, $E4
    ldh [BGP], a
    ldh [OBP0], a

    ; ── Scroll initial ────────────────────────────────────────────────────────
    xor a
    ldh [SCY], a
    ldh [SCX], a

    ; ── Position initiale du sprite (centre écran) ────────────────────────────
    ld a, 72          ; screen Y = 72
    ld [SpriteY], a
    ld a, 76          ; screen X = 76
    ld [SpriteX], a
    ld a, 1
    ld [SpriteDX], a
    ld [SpriteDY], a

    ; ── Écrire le sprite dans OAM ─────────────────────────────────────────────
    call UpdateOAM

    ; ── Activer LCD : bit7=LCD, bit4=tiles@8000, bit1=OBJ, bit0=BG ───────────
    ld a, $93
    ldh [LCDC], a

MainLoop:
WaitNotVBlank:
    ldh a, [LY]
    cp 144
    jr nc, WaitNotVBlank

WaitVBlank:
    ldh a, [LY]
    cp 144
    jr nz, WaitVBlank

    ; ── Scroll BG diagonal lent ───────────────────────────────────────────────
    ldh a, [SCX]
    inc a
    ldh [SCX], a
    ldh a, [SCY]
    inc a
    ldh [SCY], a

    ; ── Déplacer le sprite ────────────────────────────────────────────────────
    ; X
    ld a, [SpriteX]
    ld b, a
    ld a, [SpriteDX]
    add a, b
    ld [SpriteX], a

    cp 153            ; rebond bord droit (screen X max = 152)
    jr nc, .bounce_right
    cp 0
    jr z, .bounce_left
    jr .move_y
.bounce_right:
    ld a, $FF         ; direction = gauche
    ld [SpriteDX], a
    jr .move_y
.bounce_left:
    ld a, 1           ; direction = droite
    ld [SpriteDX], a

.move_y:
    ; Y
    ld a, [SpriteY]
    ld b, a
    ld a, [SpriteDY]
    add a, b
    ld [SpriteY], a

    cp 137            ; rebond bord bas (screen Y max = 136)
    jr nc, .bounce_down
    cp 0
    jr z, .bounce_up
    jr .done_move
.bounce_down:
    ld a, $FF
    ld [SpriteDY], a
    jr .done_move
.bounce_up:
    ld a, 1
    ld [SpriteDY], a

.done_move:
    call UpdateOAM

    jr MainLoop

; ── Met à jour l'entrée OAM[0] avec SpriteX/SpriteY ──────────────────────────
; OAM Y = screen_y + 16, OAM X = screen_x + 8
UpdateOAM:
    ld hl, $FE00
    ld a, [SpriteY]
    add a, 16
    ld [hl+], a       ; Y
    ld a, [SpriteX]
    add a, 8
    ld [hl+], a       ; X
    ld a, 8           ; tile index 8 = sprite smiley
    ld [hl+], a
    ld a, $00         ; pas de flip, priorité 0, palette OBP0
    ld [hl], a
    ret

; =============================================================================
; Tile data : 8 tiles BG (index 0-7) + 1 tile sprite (index 8)
; =============================================================================
TileData:

; Tile 0 : blanc
REPT 8
    db $00, $00
ENDR

; Tile 1 : noir
REPT 8
    db $FF, $FF
ENDR

; Tile 2 : gris clair
REPT 8
    db $FF, $00
ENDR

; Tile 3 : gris foncé
REPT 8
    db $00, $FF
ENDR

; Tile 4 : damier
REPT 2
    db $CC, $33
    db $CC, $33
    db $33, $CC
    db $33, $CC
ENDR

; Tile 5 : diamant
    db $00, $00
    db $18, $18
    db $3C, $3C
    db $7E, $7E
    db $3C, $3C
    db $18, $18
    db $00, $00
    db $00, $00

; Tile 6 : croix
    db $18, $18
    db $18, $18
    db $18, $18
    db $FF, $FF
    db $FF, $FF
    db $18, $18
    db $18, $18
    db $18, $18

; Tile 7 : dégradé
REPT 8
    db $33, $0F
ENDR

; Tile 8 : sprite smiley (8×8, couleur 3 = noir sur fond transparent=0)
;  .######.  = 01111110 = $7E
;  #......#  = 10000001 = $81
;  #.##.##.  = 10110110 = $B6  (yeux)
;  #......#
;  #.#...#.  = 10100010 = $A2  (bouche)
;  #..###..  = 10011100 = $9C
;  #......#
;  .######.
    db $7E, $7E
    db $81, $81
    db $B6, $B6
    db $81, $81
    db $A2, $A2
    db $9C, $9C
    db $81, $81
    db $7E, $7E

TileDataEnd:

; =============================================================================
; Tilemap BG : 32×32 = 1024 octets (reprise de display_bg_4)
; =============================================================================
TilemapData:

REPT 4
    REPT 16
        db 0, 4
    ENDR
ENDR

REPT 4
    REPT 16
        db 5, 2
    ENDR
ENDR

REPT 4
    REPT 16
        db 6, 3
    ENDR
ENDR

REPT 4
    REPT 16
        db 7, 1
    ENDR
ENDR

REPT 4
    REPT 16
        db 0, 4
    ENDR
ENDR

REPT 4
    REPT 16
        db 5, 2
    ENDR
ENDR

REPT 4
    REPT 16
        db 6, 3
    ENDR
ENDR

REPT 4
    REPT 16
        db 7, 1
    ENDR
ENDR
