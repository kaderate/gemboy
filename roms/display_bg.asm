SECTION "Header", ROM0[$0100]
    ; Entry Point ($0100-$0102)
    jp Start

    ; Padding ($0103)
    db $00

    ; Nintendo Logo ($0104-$0133)
    db $ce, $ed, $66, $66, $cc, $0d, $00, $0b
    db $03, $73, $00, $83, $00, $0c, $00, $0d
    db $00, $08, $11, $1f, $88, $89, $00, $0e
    db $dc, $cc, $6e, $e6, $dd, $dd, $d9, $99
    db $bb, $bb, $67, $63, $6e, $0e, $ec, $cc
    db $dd, $dc, $99, $9f, $bb, $b9, $33, $3e

    ; Title ($0134-$0143)
    db "DISPLAY_BG", 0, 0, 0, 0, 0, 0

    ; CGB Flag ($0144)
    db $00

    ; New Licensee Code ($0145-$0146)
    db $00, $00

    ; SGB Flag ($0147)
    db $00

    ; Cartridge Type ($0148) - ROM only
    db $00

    ; ROM Size ($0149) - 32KB
    db $00

    ; RAM Size ($014A) - No RAM
    db $00

    ; Destination Code ($014B)
    db $01

    ; Old Licensee Code ($014C)
    db $00

    ; ROM Version ($014D)
    db $00

SECTION "Main", ROM0[$0150]

DEF LCDC EQU $FF40

Start:
    ; --- Copier Tile0 en VRAM ---
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

    ; --- Copier Tile1 en VRAM ---
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
    ld b,32
FillMapY:
    ld d,32
FillMapX:
    ld [hl], a
    inc hl
    xor 1  ; Alterne entre 0 et 1
    dec d
    jr nz, FillMapX
    xor 1  ; Alterne aussi au début de la prochaine ligne
    dec b
    jr nz, FillMapY

    ; --- Set palette ---
    ld a, $E4
    ld [$FF47], a

    ; --- Activer BG ---
    ld a, $91
    ld [LCDC], a

MainLoop:
    jr MainLoop

; Tile 0 : vide
Tile0:
    ds 16

; Tile 1 : damier simple
Tile1:
    db $AA,$55,$AA,$55,$AA,$55,$AA,$55
    db $55,$AA,$55,$AA,$55,$AA,$55,$AA
