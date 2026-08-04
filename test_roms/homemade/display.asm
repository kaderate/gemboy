; display.asm - Affiche un "H" sur l'écran via le PPU Game Boy
; Assemblage: rgbasm display.asm -o display.o && rgblink -o display.gb display.o
;
; Opcodes utilisés:
;   0xC3  JP a16         — déjà implémenté
;   0x21  LD HL, d16     — déjà implémenté
;   0x11  LD DE, d16     — déjà implémenté
;   0x3E  LD A, d8       — déjà implémenté
;   0x7E  LD A, (HL)     — déjà implémenté
;   0x12  LD (DE), A     — déjà implémenté
;   0x23  INC HL         — déjà implémenté
;   0x13  INC DE         — déjà implémenté
;   0x20  JR NZ, r8      — déjà implémenté
;   0x18  JR r8          — déjà implémenté
;   0x06  LD B, d8       — À IMPLÉMENTER
;   0x05  DEC B          — À IMPLÉMENTER  (affecte Z, N, H — contrairement à DEC BC)
;   0xEA  LD (a16), A    — À IMPLÉMENTER  (écriture à adresse 16-bit absolue)

SECTION "Header", ROM0[$0100]
    jp start

SECTION "Main", ROM0[$0150]

start:
    ; ── Étape 1 : copier les données de tuile vers VRAM ──────────────────
    ; La tuile 0 se situe à 0x8000 en VRAM (16 octets).
    ; Le fond de carte (tilemap) à 0x9800 est initialisé à 0 par l'émulateur,
    ; donc toutes les cases pointent déjà vers la tuile 0.
    ld hl, tile_data    ; 0x21 — source : données en ROM
    ld de, $8000        ; 0x11 — destination : tuile 0 en VRAM
    ld b, 16            ; 0x06 — compteur : 16 octets par tuile
.copy_tile:
    ld a, [hl]          ; 0x7E — lire un octet depuis la ROM
    ld [de], a          ; 0x12 — l'écrire en VRAM
    inc hl              ; 0x23
    inc de              ; 0x13
    dec b               ; 0x05 — décrémente B, met le flag Z si B == 0
    jr nz, .copy_tile   ; 0x20 — continue tant que B != 0

    ; ── Étape 2 : activer le LCD via le registre LCDC (0xFF40) ───────────
    ; Valeur 0x91 = 1001 0001 :
    ;   bit 7 = 1  LCD activé
    ;   bit 4 = 1  données des tuiles à 0x8000 (adressage non signé)
    ;   bit 0 = 1  fond de carte (BG) activé
    ld a, $91           ; 0x3E
    ld [$FF40], a       ; 0xEA — écriture directe à l'adresse LCDC

.loop:
    jr .loop            ; 0x18 0xFE — boucle infinie

; ── Données de la tuile 0 : lettre "H" ───────────────────────────────────
; Format 2bpp Game Boy : 2 octets par ligne de 8 pixels.
;   octet 1 = plan bas (bit de poids faible de chaque pixel)
;   octet 2 = plan haut (bit de poids fort de chaque pixel)
; Couleur pixel i = (bit_i plan_haut) << 1 | (bit_i plan_bas)
;   couleur 0 = blanc, couleur 3 = noir
; Les deux plans sont identiques ici → pixels allumés = couleur 3 (noir).
;
;  Pixels :  ##...##   = 11000110 = 0xC6
;            ##...##
;            ##...##
;            #######   = 11111110 = 0xFE
;            ##...##
;            ##...##
;            ##...##
;            .......   = 00000000 = 0x00
tile_data:
    db $C6, $C6
    db $C6, $C6
    db $C6, $C6
    db $FE, $FE
    db $C6, $C6
    db $C6, $C6
    db $C6, $C6
    db $00, $00
