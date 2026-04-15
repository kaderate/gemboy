SECTION "Header", ROM0[$0100]
    jp Start
    db $00
    db $CE,$ED,$66,$66,$CC,$0D,$00,$0B
    db $03,$73,$00,$83,$00,$0C,$00,$0D
    db $00,$08,$11,$1F,$88,$89,$00,$0E
    db $DC,$CC,$6E,$E6,$DD,$DD,$D9,$99
    db $BB,$BB,$67,$63,$6E,$0E,$EC,$CC
    db $DD,$DC,$99,$9F,$BB,$B9,$33,$3E
    db "DISPLAY_BG_4   "
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
FrameCounter: ds 1   ; compteur de frames (0-63)
SpeedIndex:   ds 1   ; index dans SpeedTable (0-3)

SECTION "Main", ROM0[$0150]

DEF LCDC EQU $FF40
DEF SCY  EQU $FF42
DEF SCX  EQU $FF43
DEF LY   EQU $FF44
DEF BGP  EQU $FF47

; Vitesses en pixels/frame : lent → rapide → très rapide → rapide → lent ...
SpeedTable:
    db 1, 4, 12, 24

Start:
    ; Copier les 8 tiles (128 octets) en VRAM $8000
    ld hl, TileData
    ld de, $8000
    ld bc, $0080
CopyTiles:
    ld a, [hl+]
    ld [de], a
    inc de
    dec bc
    ld a, b
    or c
    jr nz, CopyTiles

    ; Copier la tilemap (1024 octets) en VRAM $9800
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

    ; Palette, scroll initial, LCD
    ld a, $E4
    ldh [BGP], a
    xor a
    ldh [SCY], a
    ldh [SCX], a
    ; Init WRAM
    xor a
    ld [FrameCounter], a
    ld [SpeedIndex], a
    ld a, $91
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

    ; --- Mise à jour vitesse ---
    ld a, [FrameCounter]
    inc a
    ld [FrameCounter], a
    cp 64
    jr nz, ApplyScroll      ; pas encore 64 frames

    ; 64 frames écoulées : avancer SpeedIndex (mod 4) et reset FrameCounter
    xor a
    ld [FrameCounter], a
    ld a, [SpeedIndex]
    inc a
    and $03                 ; mod 4
    ld [SpeedIndex], a

    ; --- Appliquer le scroll ---
ApplyScroll:
    ld a, [SpeedIndex]
    ld hl, SpeedTable
    add a, l                ; hl += SpeedIndex (SpeedTable est alignée, pas de carry)
    ld l, a
    ld a, [hl]              ; a = vitesse courante

    ld b, a                 ; sauvegarder vitesse dans B

    ldh a, [SCX]
    add a, b
    ldh [SCX], a

    ldh a, [SCY]
    add a, b
    ldh [SCY], a

    jr MainLoop

; =============================================================================
; Tile data : 8 tiles × 16 octets = 128 octets
; Encodage 2BPP : color = (byte2_bit << 1) | byte1_bit
;   couleur 0 = blanc     : byte1=0, byte2=0
;   couleur 1 = gris clair: byte1=1, byte2=0
;   couleur 2 = gris foncé: byte1=0, byte2=1
;   couleur 3 = noir      : byte1=1, byte2=1
; =============================================================================
TileData:

; Tile 0 : blanc uni
REPT 8
    db $00, $00
ENDR

; Tile 1 : noir uni
REPT 8
    db $FF, $FF
ENDR

; Tile 2 : gris clair uni
REPT 8
    db $FF, $00
ENDR

; Tile 3 : gris foncé uni
REPT 8
    db $00, $FF
ENDR

; Tile 4 : damier gris clair / gris foncé (blocs 2×2)
; Rangées 0-1 : lgray lgray dgray dgray lgray lgray dgray dgray
;   byte1 : 11001100 = $CC, byte2 : 00110011 = $33
; Rangées 2-3 : dgray dgray lgray lgray ...
;   byte1 : 00110011 = $33, byte2 : 11001100 = $CC
REPT 2
    db $CC, $33
    db $CC, $33
    db $33, $CC
    db $33, $CC
ENDR

; Tile 5 : diamant noir sur fond blanc
db $00, $00
db $18, $18
db $3C, $3C
db $7E, $7E
db $3C, $3C
db $18, $18
db $00, $00
db $00, $00

; Tile 6 : croix (+) noire sur fond blanc
db $18, $18
db $18, $18
db $18, $18
db $FF, $FF
db $FF, $FF
db $18, $18
db $18, $18
db $18, $18

; Tile 7 : dégradé horizontal (blanc → gris clair → gris foncé → noir, 2px chacun)
; pixels : 0,0,1,1,2,2,3,3
;   byte1 : 00110011 = $33, byte2 : 00001111 = $0F
REPT 8
    db $33, $0F
ENDR

; =============================================================================
; Tilemap : 32×32 = 1024 octets
; 4 bandes de 4 rangées, répétées 2 fois
; =============================================================================
TilemapData:

; Bande 0 (rangées 0-3) : blanc / damier gris
REPT 4
    REPT 16
        db 0, 4
    ENDR
ENDR

; Bande 1 (rangées 4-7) : diamant / gris clair
REPT 4
    REPT 16
        db 5, 2
    ENDR
ENDR

; Bande 2 (rangées 8-11) : croix / gris foncé
REPT 4
    REPT 16
        db 6, 3
    ENDR
ENDR

; Bande 3 (rangées 12-15) : dégradé / noir
REPT 4
    REPT 16
        db 7, 1
    ENDR
ENDR

; Répétition bandes 0-3 pour rangées 16-31
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
