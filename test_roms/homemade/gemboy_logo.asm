; gemboy_logo.asm - "GEM BOY" boot animation (CGB only).
;
; Step 1: draw the static logo, white on black.
;
; The 6 letters are stored as 16x16 pixel bitmaps, one row per source line,
; two bytes per row (left half, right half). That layout is readable but it
; is NOT the layout the PPU wants, so DecodeLetters below re-shuffles it.

SECTION "Header", ROM0[$0100]
    nop
    jp Start

    ; Nintendo Logo ($0104-$0133)
    db $ce, $ed, $66, $66, $cc, $0d, $00, $0b
    db $03, $73, $00, $83, $00, $0c, $00, $0d
    db $00, $08, $11, $1f, $88, $89, $00, $0e
    db $dc, $cc, $6e, $e6, $dd, $dd, $d9, $99
    db $bb, $bb, $67, $63, $6e, $0e, $ec, $cc
    db $dd, $dc, $99, $9f, $bb, $b9, $33, $3e

    db "GEMBOY"         ; Title ($0134-$013E)

    ds $0143 - @, 0     ; pad up to the CGB flag (manufacturer code, unused)
    db $C0              ; $0143 = CGB flag: CGB only, no DMG fallback
    ds $0150 - @, 0

; The VBlank interrupt only has to exist for `halt` to wake up: the work is
; done in the main loop, right after the CPU resumes.
SECTION "VBlankInt", ROM0[$0040]
    reti


SECTION "Vars", WRAM0[$C000]
FallPos:  ds 2       ; SCY as 8.8 fixed point: high byte = whole pixels
FallVel:  ds 2       ; same format, signed (two's complement)
State:     ds 1      ; 0 = falling, 1 = shining, 2 = done
ShinePos:  ds 2      ; index into ShineRamp, 8.8 fixed point
ShineVel:  ds 2      ; entries per frame, 8.8 fixed point
ChimeDelay: ds 1    ; frames left before the second stroke, 0 = idle
PrevStart: ds 1      ; last frame's raw Start bit, for edge detection


SECTION "Main", ROM0[$0150]

DEF LCDC EQU $FF40
DEF SCY  EQU $FF42
DEF SCX  EQU $FF43
DEF LY   EQU $FF44
DEF VBK  EQU $FF4F      ; CGB: selects VRAM bank 0 (tiles+map) or 1 (attributes)
DEF BCPS EQU $FF68      ; CGB: BG palette index (bit 7 = auto-increment)
DEF BCPD EQU $FF69      ; CGB: BG palette data
DEF IFLAG   EQU $FF0F   ; `IF` and `IE` are reserved words in rgbasm
DEF IENABLE EQU $FFFF
DEF P1   EQU $FF00      ; joypad: write the row to scan, read the buttons back

DEF NR10 EQU $FF10      ; channel 1: sweep, duty/length, envelope, frequency
DEF NR11 EQU $FF11
DEF NR12 EQU $FF12
DEF NR13 EQU $FF13
DEF NR14 EQU $FF14
DEF NR21 EQU $FF16      ; channel 2: same, minus the sweep unit
DEF NR22 EQU $FF17
DEF NR23 EQU $FF18
DEF NR24 EQU $FF19
DEF NR50 EQU $FF24      ; master volume
DEF NR51 EQU $FF25      ; per-channel stereo routing
DEF NR52 EQU $FF26      ; master power

DEF LOGO_ROW EQU 8      ; logo sits on BG map rows 8-9...
DEF LOGO_COL EQU 3      ; ...columns 3-15, which centers it on screen

DEF FALL_START EQU 100  ; starting SCY: far enough up to hide the logo
DEF GRAVITY    EQU $0020 ; 0.125 px per frame, per frame

DEF SHINE_SUB   EQU 8    ; ShineRamp entries per letter
DEF SHINE_START EQU 96   ; two full gradient periods of travel
DEF SHINE_VEL0  EQU $0040 ; 0.25 entry per frame to start with
DEF SHINE_ACCEL EQU $0008 ; speeds up over the first half, brakes over the second

; Period registers, not frequencies: the hardware plays 131072 / (2048 - x) Hz.
; Two strokes a fifth wide, the second one an octave above the first.
DEF CHIME1_LOW  EQU 1899 ; A5,  880 Hz
DEF CHIME1_HIGH EQU 1949 ; E6, 1319 Hz
DEF CHIME2_LOW  EQU 1974 ; A6, 1760 Hz
DEF CHIME2_HIGH EQU 1998 ; E7, 2637 Hz
DEF CHIME_GAP   EQU 14   ; frames between the two strokes

Start:
    di
    ld sp, $FFFE

    ; VRAM can only be written while the PPU is not drawing. The boot ROM
    ; leaves the LCD on, so wait for VBlank and switch it off completely.
.wait_vblank:
    ldh a, [LY]
    cp 144
    jr c, .wait_vblank
    xor a
    ldh [LCDC], a

    ; Bank 1 holds the BG map attributes (palette, flips). It powers up with
    ; garbage, so clear both banks before anything is displayed.
    ld a, 1
    ldh [VBK], a
    call ClearVRAM
    xor a
    ldh [VBK], a
    call ClearVRAM

    call DecodeLetters
    call DrawLogo
    call LoadPalette
    call LoadAttributes

    ld a, -5            ; the drawn glyphs span 102 px, not a whole number
    ldh [SCX], a        ; of tiles: nudge the whole map right to center them
    ld a, $08
    ld [PrevStart], a   ; Start reads high (released) until proven otherwise
    call ResetAnim

    ld a, $91           ; LCD on, BG on, tile data at $8000
    ldh [LCDC], a

    ld a, 1             ; enable the VBlank interrupt only
    ldh [IENABLE], a
    xor a
    ldh [IFLAG], a         ; drop anything already pending
    ei
    jp MainLoop         ; the helpers below sit in the way, jump over them

; Put the animation back on its first frame. Safe to call from the main loop
; because that only runs during VBlank, when the palettes are writable.
ResetAnim:
    call LoadPalette    ; back to the resting gradient
    xor a
    ld [FallPos], a
    ld [FallVel], a
    ld [FallVel + 1], a
    ld [State], a
    ld [ShinePos], a
    ld [ShineVel + 1], a
    ld a, SHINE_START
    ld [ShinePos + 1], a
    ld a, LOW(SHINE_VEL0)
    ld [ShineVel], a
    xor a
    ld [ChimeDelay], a
    ld a, FALL_START
    ld [FallPos + 1], a
    ldh [SCY], a
    ret


; Returns the raw Start bit in a: 0 when the button is down, since the joypad
; is active low. Selecting a row takes a moment to settle on real hardware,
; hence the throwaway reads before the real one.
ReadStart:
    ld a, $10           ; drive P15 low: scan the button row, not the d-pad
    ldh [P1], a
    ldh a, [P1]
    ldh a, [P1]
    and $08             ; bit 3 = Start
    ret


MainLoop:
    halt                ; sleep until VBlank; wakes up inside the safe window

    ; Restart on a fresh press of Start: react to the transition, not to the
    ; button being held, or the logo would stay pinned off-screen.
    call ReadStart
    ld b, a
    ld hl, PrevStart
    ld a, [hl]
    ld [hl], b
    or a
    jr z, .animate      ; already down last frame, nothing new
    ld a, b
    or a
    jr nz, .animate     ; still up
    call ResetAnim
    jr MainLoop
.animate:
    call StepChime
    ld a, [FallPos + 1]
    ldh [SCY], a
    ld a, [State]
    cp 1
    jr c, .fall
    jr z, .shine
    jr MainLoop         ; settled: nothing left to animate
.fall:
    call StepFall
    jr MainLoop
.shine:
    call StepShine
    jr MainLoop


; Slide the whole gradient towards the start of the table. Same 8.8 integrator
; as the fall, but the acceleration flips sign at the halfway mark, so the
; sweep speeds up out of a drift and coasts back down to one on arrival.
StepShine:
    ld a, [ShinePos + 1]    ; whole entries only
    ld l, a
    ld h, 0
    add hl, hl              ; two bytes per color
    ld de, ShineRamp
    add hl, de
    call WritePalettes

    ld a, [ShineVel]        ; vel += accel
    ld l, a
    ld a, [ShineVel + 1]
    ld h, a
    ld de, SHINE_ACCEL
    ld a, [ShinePos + 1]
    cp SHINE_START / 2
    jr nc, .integrate
    ld de, -SHINE_ACCEL ; past halfway: brake, mirroring the ramp-up exactly
.integrate:
    add hl, de
    ld a, l
    ld [ShineVel], a
    ld a, h
    ld [ShineVel + 1], a

    xor a                   ; de = -vel, the table is walked backwards
    sub l
    ld e, a
    ld a, 0                 ; again, `xor a` would wipe the borrow
    sbc h
    ld d, a

    ld a, [ShinePos]        ; pos += -vel
    ld l, a
    ld a, [ShinePos + 1]
    ld h, a
    add hl, de
    jr c, .store            ; carry set means pos stayed >= 0
    ld hl, 0                ; walked past the start: rest on the gradient
    ld a, 2
    ld [State], a
.store:
    ld a, l
    ld [ShinePos], a
    ld a, h
    ld [ShinePos + 1], a
    ret


; One frame of ballistics, in 8.8 fixed point. The low byte holds 1/256th of
; a pixel, which is what makes a slow start possible: a velocity of $0020 is
; an eighth of a pixel per frame, unrepresentable in plain integers.
StepFall:
    ; vel += gravity. Gravity is negative because the logo comes down by
    ; *shrinking* SCY, and two's complement makes `add` do subtraction.
    ld a, [FallVel]
    ld l, a
    ld a, [FallVel + 1]
    ld h, a
    ld de, -GRAVITY
    add hl, de
    ld d, h
    ld e, l             ; de = new velocity

    ; pos += vel
    ld a, [FallPos]
    ld l, a
    ld a, [FallPos + 1]
    ld h, a
    bit 7, d            ; sign of the velocity...
    add hl, de          ; ...survives the addition: add hl,rr leaves Z alone
    jr z, .store        ; moving up, the floor is out of reach
    jr c, .store        ; carry set means pos + vel stayed >= 0

    ; Hit the floor: clamp, then bounce back at half the speed.
    ld hl, 0
    xor a
    sub e               ; negate the velocity, 16 bits, low half first
    ld e, a
    ld a, 0             ; not `xor a` here: it would wipe the borrow
    sbc d
    ld d, a
    srl d               ; halve it, carrying bit 0 of d into e
    rr e
    ld a, d
    or a
    jr nz, .store       ; d != 0 means at least one whole pixel per frame
    ld de, 0            ; too slow to bounce again: settle for good
    ld a, 1
    ld [State], a
    push hl             ; PlayChime clobbers bc, de and hl, and neither the
    push de             ; position nor the velocity is stored yet
    call StrikeFirst
    pop de
    pop hl

.store:
    ld a, l
    ld [FallPos], a
    ld a, h
    ld [FallPos + 1], a
    ld a, e
    ld [FallVel], a
    ld a, d
    ld [FallVel + 1], a
    ret


; Two square waves a fifth apart, struck together and left to ring out on
; their own envelopes. Nothing polls or stops them: the APU decays the volume
; by itself, so the note fades without a single cycle of CPU time.
;
;   b  = envelope byte for both channels
;   de = channel 1 period
;   hl = channel 2 period
PlayChime:
    ld a, $80
    ldh [NR52], a       ; power on -- every other APU register ignores writes
    ld a, $77           ; while this bit is clear
    ldh [NR50], a       ; full volume, both sides
    ld a, $33
    ldh [NR51], a       ; channels 1 and 2 to both speakers

    xor a
    ldh [NR10], a       ; no frequency sweep
    ld a, $80           ; 50% duty
    ldh [NR11], a
    ld a, b
    ldh [NR12], a
    ld a, e
    ldh [NR13], a
    ld a, d
    or $80
    ldh [NR14], a       ; bit 7 triggers the channel: this is the note-on

    ld a, $00           ; 12.5% duty, thinner, sits on top of the other one
    ldh [NR21], a
    ld a, b
    ldh [NR22], a
    ld a, l
    ldh [NR23], a
    ld a, h
    or $80
    ldh [NR24], a
    ret


; First stroke, on the low pair, with a short envelope so it has faded by the
; time the second one lands. Arms the countdown on its way out.
StrikeFirst:
    ld b, $F2           ; volume 15, decreasing fast: one step every 2/64 s
    ld de, CHIME1_LOW
    ld hl, CHIME1_HIGH
    call PlayChime
    ld a, CHIME_GAP
    ld [ChimeDelay], a
    ret


; Called every frame; fires the octave above once the countdown runs out.
StepChime:
    ld a, [ChimeDelay]
    or a
    ret z               ; nothing pending
    dec a
    ld [ChimeDelay], a
    ret nz              ; still counting
    ld b, $F7           ; slowest decay: this one rings for about 1.6 s
    ld de, CHIME2_LOW
    ld hl, CHIME2_HIGH
    jp PlayChime        ; tail call: PlayChime's ret returns to the caller


; Fill $8000-$9FFF of the current bank with zeroes.
ClearVRAM:
    ld hl, $8000
    ld bc, $2000
.next:
    xor a
    ld [hl+], a
    dec bc
    ld a, b
    or c
    jr nz, .next
    ret


; Turn the 16x16 bitmaps into PPU tiles, starting at tile 1 ($8010).
;
; A tile is 8x8, so each letter becomes four of them, and the PPU expects
; them in this order: top-left, top-right, bottom-left, bottom-right.
; In the source, rows 0-7 (16 bytes) hold the two top tiles interleaved
; (left byte, right byte, left byte, ...) and rows 8-15 the two bottom ones.
; So each 16-byte block yields two tiles: the even bytes, then the odd ones.
DecodeLetters:
    ld hl, LetterData
    ld de, $8010
    ld b, 12            ; 6 letters x 2 blocks of 8 rows
.block:
    push hl
    call EmitTile       ; even bytes -> left tile
    pop hl
    inc hl
    call EmitTile       ; odd bytes -> right tile
    dec hl              ; EmitTile stopped one byte past the block
    dec b
    jr nz, .block
    ret

; hl = first source byte, read every other byte, 8 rows -> 16 bytes at de.
;
; Tiles are 2bpp: each row is two bytes, one per bit plane, and the two bits
; of a pixel select a color 0-3. Writing the pattern in the low plane and 0
; in the high plane paints every lit pixel with color 1.
EmitTile:
    ld c, 8
.row:
    ld a, [hl]
    ld [de], a
    inc de
    xor a
    ld [de], a
    inc de
    inc hl
    inc hl
    dec c
    jr nz, .row
    ret


; Write the two rows of tile indices into the BG map at $9800.
DrawLogo:
    ld hl, $9800 + LOGO_ROW * 32 + LOGO_COL
    ld de, LogoTop
    call CopyRow
    ld hl, $9800 + (LOGO_ROW + 1) * 32 + LOGO_COL
    ld de, LogoBottom
    ; falls through
CopyRow:
    ld b, 13
.next:
    ld a, [de]
    ld [hl+], a
    inc de
    dec b
    jr nz, .next
    ret


; CGB BG attributes live in VRAM bank 1, at the very same addresses as the
; tile map: one byte per map cell. Bits 0-2 pick one of the 8 BG palettes,
; bit 3 the tile bank, bits 5-6 the flips, bit 7 the priority.
; Giving each letter its own palette is what lets us recolor the word later
; without ever touching a pixel.
LoadAttributes:
    ld a, 1
    ldh [VBK], a
    ld hl, $9800 + LOGO_ROW * 32 + LOGO_COL
    ld de, LogoAttrs
    call CopyRow
    ld hl, $9800 + (LOGO_ROW + 1) * 32 + LOGO_COL
    ld de, LogoAttrs
    call CopyRow
    xor a
    ldh [VBK], a
    ret


; CGB palettes are not in the address space: they sit in a separate 64-byte
; area reached through an index register. BCPS selects the byte, BCPD reads
; or writes it, and bit 7 of BCPS makes the index auto-increment, so the
; whole set can be written in one burst.
;
; Each color is 16 bits little-endian, 5 bits per channel: -bbbbbgg gggrrrrr.
; Only colors 0 and 1 are ever drawn here, but a palette is always 4 colors
; wide, so the last two are padded to keep the auto-increment in step.
LoadPalette:
    ld hl, ShineRamp
    ; falls through

; hl = six colors to install as color 1 of palettes 0-5.
WritePalettes:
    ld a, $80           ; auto-increment, start at palette 0, color 0
    ldh [BCPS], a
    ld c, 6
.palette:
    xor a
    ldh [BCPD], a       ; color 0 = black, the background behind every letter
    ldh [BCPD], a
    ld a, [hl+]
    ldh [BCPD], a       ; color 1 = this letter's own color
    ld a, [hl+]
    ldh [BCPD], a
    xor a
    ld b, 4
.pad:
    ldh [BCPD], a
    dec b
    jr nz, .pad
    ld de, (SHINE_SUB - 1) * 2
    add hl, de          ; step to the matching slot of the next letter
    dec c
    jr nz, .palette
    ret

; The animation table. It holds SHINE_SUB entries per letter, so the sweep can
; move in eighth-of-a-letter steps instead of jumping a whole letter at a time.
; Entry k is the resting gradient smoothly interpolated at position k /
; SHINE_SUB, brightened by a raised-cosine bump centered on index 56 -- halfway
; down the run, so the flare enters the word at full speed and leaves it while
; the sweep is already braking. Letter i always reads entry
; ShinePos + i * SHINE_SUB, so walking ShinePos down from 96 to 0 drags the
; bump across the word from left to right and lands back on the untouched
; gradient (the table repeats every 48 entries).
ShineRamp:
    dw $7FEC          ;   0
    dw $7FEC          ;   1
    dw $7FCB          ;   2
    dw $7FAA          ;   3
    dw $7F89          ;   4
    dw $7F48          ;   5
    dw $7F27          ;   6
    dw $7F06          ;   7
    dw $7F06          ;   8
    dw $7EE6          ;   9
    dw $7EC6          ;  10
    dw $7E87          ;  11
    dw $7E47          ;  12
    dw $7E07          ;  13
    dw $7DC8          ;  14
    dw $7DA8          ;  15
    dw $7D88          ;  16
    dw $7D88          ;  17
    dw $7D6A          ;  18
    dw $7D4B          ;  19
    dw $7D2D          ;  20
    dw $7D0F          ;  21
    dw $7CF0          ;  22
    dw $7CD2          ;  23
    dw $7CD2          ;  24
    dw $7CD2          ;  25
    dw $78D4          ;  26
    dw $74D5          ;  27
    dw $70D7          ;  28
    dw $70D9          ;  29
    dw $6CDA          ;  30
    dw $68DC          ;  31
    dw $68DC          ;  32
    dw $68DC          ;  33
    dw $64FC          ;  34
    dw $5D1D          ;  35
    dw $593E          ;  36
    dw $555E          ;  37
    dw $4D7F          ;  38
    dw $499F          ;  39
    dw $499F          ;  40
    dw $4DBE          ;  41
    dw $521C          ;  42
    dw $5E79          ;  43
    dw $66F7          ;  44
    dw $7355          ;  45
    dw $7BB4          ;  46
    dw $7FF4          ;  47
    dw $7FF6          ;  48
    dw $7FF7          ;  49
    dw $7FF9          ;  50
    dw $7FFA          ;  51
    dw $7FDC          ;  52
    dw $7FFD          ;  53
    dw $7FFE          ;  54
    dw $7FFF          ;  55
    dw $7FFF          ;  56
    dw $7FFF          ;  57
    dw $7FFE          ;  58
    dw $7FDD          ;  59
    dw $7FBB          ;  60
    dw $7F9A          ;  61
    dw $7F58          ;  62
    dw $7F16          ;  63
    dw $7ED4          ;  64
    dw $7E72          ;  65
    dw $7E30          ;  66
    dw $7DF0          ;  67
    dw $7D90          ;  68
    dw $7D50          ;  69
    dw $7D11          ;  70
    dw $7CD2          ;  71
    dw $7CD2          ;  72
    dw $7CD2          ;  73
    dw $78D4          ;  74
    dw $74D5          ;  75
    dw $70D7          ;  76
    dw $70D9          ;  77
    dw $6CDA          ;  78
    dw $68DC          ;  79
    dw $68DC          ;  80
    dw $68DC          ;  81
    dw $64FC          ;  82
    dw $5D1D          ;  83
    dw $593E          ;  84
    dw $555E          ;  85
    dw $4D7F          ;  86
    dw $499F          ;  87
    dw $499F          ;  88
    dw $4DBE          ;  89
    dw $51FC          ;  90
    dw $5A59          ;  91
    dw $62D6          ;  92
    dw $6F32          ;  93
    dw $778F          ;  94
    dw $7BCD          ;  95
    dw $7FEC          ;  96
    dw $7FEC          ;  97
    dw $7FCB          ;  98
    dw $7FAA          ;  99
    dw $7F89          ; 100
    dw $7F48          ; 101
    dw $7F27          ; 102
    dw $7F06          ; 103
    dw $7F06          ; 104
    dw $7EE6          ; 105
    dw $7EC6          ; 106
    dw $7E87          ; 107
    dw $7E47          ; 108
    dw $7E07          ; 109
    dw $7DC8          ; 110
    dw $7DA8          ; 111
    dw $7D88          ; 112
    dw $7D88          ; 113
    dw $7D6A          ; 114
    dw $7D4B          ; 115
    dw $7D2D          ; 116
    dw $7D0F          ; 117
    dw $7CF0          ; 118
    dw $7CD2          ; 119
    dw $7CD2          ; 120
    dw $7CD2          ; 121
    dw $78D4          ; 122
    dw $74D5          ; 123
    dw $70D7          ; 124
    dw $70D9          ; 125
    dw $6CDA          ; 126
    dw $68DC          ; 127
    dw $68DC          ; 128
    dw $68DC          ; 129
    dw $64FC          ; 130
    dw $5D1D          ; 131
    dw $593E          ; 132
    dw $555E          ; 133
    dw $4D7F          ; 134
    dw $499F          ; 135
    dw $499F          ; 136
    dw $4DBE          ; 137
    dw $51FC          ; 138
    dw $5A59          ; 139
    dw $62D6          ; 140
    dw $6F32          ; 141
    dw $778F          ; 142
    dw $7BCD          ; 143

; Tile 0 is blank (VRAM was cleared), letters start at tile 1, four tiles each.
LogoTop:
    db  1,  2,  5,  6,  9, 10,  0, 13, 14, 17, 18, 21, 22
LogoBottom:
    db  3,  4,  7,  8, 11, 12,  0, 15, 16, 19, 20, 23, 24
; One palette per letter; the blank tile in the middle can use any of them.
LogoAttrs:
    db  0,  0,  1,  1,  2,  2,  0,  3,  3,  4,  4,  5,  5


LetterData:
; G
    db %00111111,%11111100
    db %01111111,%11111100
    db %11111111,%11111100
    db %11100000,%00000000
    db %11100000,%00000000
    db %11100000,%00000000
    db %11100000,%00000000
    db %11100001,%11111100
    db %11100001,%11111100
    db %11100000,%00011100
    db %11100000,%00011100
    db %11100000,%00011100
    db %11100000,%00011100
    db %11111111,%11111100
    db %01111111,%11111100
    db %00111111,%11111100
; E
    db %11111111,%11111100
    db %11111111,%11111100
    db %11111111,%11111100
    db %11100000,%00000000
    db %11100000,%00000000
    db %11100000,%00000000
    db %11100000,%00000000
    db %11111111,%11100000
    db %11111111,%11100000
    db %11100000,%00000000
    db %11100000,%00000000
    db %11100000,%00000000
    db %11100000,%00000000
    db %11111111,%11111100
    db %11111111,%11111100
    db %11111111,%11111100
; M
    db %11111111,%11111100
    db %11111111,%11111100
    db %11111111,%11111100
    db %11100011,%10011100
    db %11100011,%10011100
    db %11100011,%10011100
    db %11100011,%10011100
    db %11100011,%10011100
    db %11100011,%10011100
    db %11100000,%00011100
    db %11100000,%00011100
    db %11100000,%00011100
    db %11100000,%00011100
    db %11100000,%00011100
    db %11100000,%00011100
    db %11100000,%00011100
; B
    db %11111111,%11110000
    db %11111111,%11110000
    db %11111111,%11110000
    db %11100000,%00011100
    db %11100000,%00011100
    db %11100000,%00011100
    db %11111111,%11110000
    db %11111111,%11110000
    db %11111111,%11110000
    db %11100000,%00011100
    db %11100000,%00011100
    db %11100000,%00011100
    db %11100000,%00011100
    db %11111111,%11110000
    db %11111111,%11110000
    db %11111111,%11110000
; O
    db %00011111,%11100000
    db %01111111,%11111000
    db %11111111,%11111100
    db %11100000,%00011100
    db %11100000,%00011100
    db %11100000,%00011100
    db %11100000,%00011100
    db %11100000,%00011100
    db %11100000,%00011100
    db %11100000,%00011100
    db %11100000,%00011100
    db %11100000,%00011100
    db %11100000,%00011100
    db %11111111,%11111100
    db %01111111,%11111000
    db %00011111,%11100000
; Y
    db %11100000,%00011100
    db %11100000,%00011100
    db %11100000,%00011100
    db %01110000,%00111000
    db %00111000,%01110000
    db %00011100,%11100000
    db %00001111,%11000000
    db %00000111,%10000000
    db %00000111,%10000000
    db %00000111,%10000000
    db %00000111,%10000000
    db %00000111,%10000000
    db %00000111,%10000000
    db %00000111,%10000000
    db %00000111,%10000000
    db %00000111,%10000000
