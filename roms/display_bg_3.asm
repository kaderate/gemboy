SECTION "Header", ROM0[$0100]
    jp Start

    db $00

    db $CE,$ED,$66,$66,$CC,$0D,$00,$0B
    db $03,$73,$00,$83,$00,$0C,$00,$0D
    db $00,$08,$11,$1F,$88,$89,$00,$0E
    db $DC,$CC,$6E,$E6,$DD,$DD,$D9,$99
    db $BB,$BB,$67,$63,$6E,$0E,$EC,$CC
    db $DD,$DC,$99,$9F,$BB,$B9,$33,$3E

    db "DISPLAY_BG_3   "  ; 15 octets
    db $00                ; CGB flag
    db $00, $00           ; licensee
    db $00                ; SGB
    db $00                ; type
    db $00                ; ROM size
    db $00                ; RAM size
    db $01                ; destination
    db $33                ; old licensee
    db $01                ; version
    db $00                ; header checksum (fixé par rgbfix)
    db $00, $00           ; global checksum (fixé par rgbfix)

SECTION "Main", ROM0[$0150]

DEF LCDC EQU $FF40
DEF SCY  EQU $FF42
DEF SCX  EQU $FF43
DEF LY   EQU $FF44
DEF BGP  EQU $FF47

Start:
    ; Copier la tile grille en VRAM $8000
    ld hl, GridTile
    ld de, $8000
    ld c, 16
CopyTile:
    ld a, [hl+]
    ld [de], a
    inc de
    dec c
    jr nz, CopyTile

    ; Remplir la tilemap $9800 avec tile 0 (1024 entrées, 4 pages de 256)
    ld hl, $9800
FillOuter:
    ld c, 0
    xor a
FillInner:
    ld [hl+], a
    dec c
    jr nz, FillInner
    inc h
    ld a, h
    cp $9C
    jr nz, FillOuter

    ; Palette, scroll initial, LCD
    ld a, $E4
    ldh [BGP], a
    xor a
    ldh [SCY], a
    ldh [SCX], a
    ld a, $91         ; LCD on, BG on, tile data $8000, tilemap $9800
    ldh [LCDC], a

MainLoop:
    ; Attendre la fin d'un éventuel VBlank en cours
WaitNotVBlank:
    ldh a, [LY]
    cp 144
    jr nc, WaitNotVBlank  ; LY >= 144 : encore en VBlank, attendre

    ; Attendre le début du VBlank
WaitVBlank:
    ldh a, [LY]
    cp 144
    jr nz, WaitVBlank     ; LY != 144 : pas encore, attendre

    ; SCX +1 par frame (scroll horizontal)
    ldh a, [SCX]
    inc a
    ldh [SCX], a

    ; SCY +1 par frame (scroll vertical)
    ldh a, [SCY]
    inc a
    ldh [SCY], a

    jr MainLoop

; Tile grille : ligne haute noire + colonne gauche noire
; Crée un quadrillage visible quand la tilemap est remplie de ce tile
GridTile:
    db $FF, $FF   ; ligne 0 : tous noirs (couleur 3)
    db $80, $80   ; lignes 1-7 : pixel gauche noir, reste blanc (couleur 0)
    db $80, $80
    db $80, $80
    db $80, $80
    db $80, $80
    db $80, $80
    db $80, $80
