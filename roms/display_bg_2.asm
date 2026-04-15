SECTION "Header", ROM0[$0100]
    jp Start

    db $00

    db $ce, $ed, $66, $66, $cc, $0d, $00, $0b
    db $03, $73, $00, $83, $00, $0c, $00, $0d
    db $00, $08, $11, $1f, $88, $89, $00, $0e
    db $dc, $cc, $6e, $e6, $dd, $dd, $d9, $99
    db $bb, $bb, $67, $63, $6e, $0e, $ec, $cc
    db $dd, $dc, $99, $9f, $bb, $b9, $33, $3e

    db "DISPLAY_BG_2", 0, 0, 0

    db $00
    db $00, $00
    db $00
    db $00
    db $00
    db $00
    db $01
    db $00
    db $00

SECTION "Main", ROM0[$0150]

DEF LCDC EQU $FF40

Start:
    ; --- Copier Tile0 (blanc) en VRAM ---
    ld hl, Tile0
    ld de, $8000
    ld c, 16
CopyTile0:
    ld a, [hl]
    ld [de], a
    inc hl
    inc de
    dec c
    jr nz, CopyTile0

    ; --- Copier Tile1 (noir) en VRAM ---
    ld hl, Tile1
    ld de, $8010
    ld c, 16
CopyTile1:
    ld a, [hl]
    ld [de], a
    inc hl
    inc de
    dec c
    jr nz, CopyTile1

    ; --- Initialiser tilemap BG 32x32 damier ---
    ld hl, $9800
    xor a
    ld b, 32
FillMapY:
    ld d, 32
FillMapX:
    ld [hl], a
    inc hl
    xor 1
    dec d
    jr nz, FillMapX
    xor 1
    dec b
    jr nz, FillMapY

    ; --- Set palette: 0=blanc, 1=noir ---
    ld a, $E4
    ld [$FF47], a

    ; --- Activer BG ---
    ld a, $91
    ld [LCDC], a

MainLoop:
    jr MainLoop

; Tile 0 : blanc (tous les pixels = couleur 0)
Tile0:
    db $00,$00,$00,$00,$00,$00,$00,$00
    db $00,$00,$00,$00,$00,$00,$00,$00

; Tile 1 : noir uni (tous les pixels = couleur 3)
Tile1:
    db $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
    db $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
