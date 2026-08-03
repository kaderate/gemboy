# ROMs de test (Blargg)

Suites de test de [Blargg](https://github.com/retrio/gb-test-roms), utilisées pour
valider la correction de l'émulateur indépendamment de tout jeu commercial. Chaque
ROM affiche `Passed`/`Failed` à l'écran et via le port série.

## cpu_instrs/

Teste la correction fonctionnelle de chaque instruction du CPU (résultats, flags).
`cpu_instrs.gb` est la suite combinée (01 à 11 enchaînés) ; chaque `NN-*.gb` est un
sous-test isolable individuellement.

| ROM | Couvre |
|---|---|
| `01-special.gb` | `DAA`, `CPL`, `SCF`, `CCF` |
| `02-interrupts.gb` | `EI`/`DI`, timing des interruptions |
| `03-op sp,hl.gb` | Instructions liées à `SP`/`HL` (`ADD SP,r8`, `LD HL,SP+r8`, `LD SP,HL`...) |
| `04-op r,imm.gb` | Opérations ALU avec opérande immédiat (`ADD A,d8`, etc.) |
| `05-op rp.gb` | Opérations sur paires de registres 16-bit |
| `06-ld r,r.gb` | `LD r8,r8` |
| `07-jr,jp,call,ret,rst.gb` | Sauts, appels, retours |
| `08-misc instrs.gb` | `PUSH`/`POP`, divers |
| `09-op r,r.gb` | Opérations ALU registre-registre |
| `10-bit ops.gb` | `BIT`/`RES`/`SET` sur registres (préfixe CB) |
| `11-op a,(hl).gb` | Opérations ALU/CB via `(HL)` |

## instr_timing/

`instr_timing.gb` — vérifie le nombre exact de cycles (T-states) consommés par
chaque instruction, mesuré via le timer. Complémentaire à `cpu_instrs` qui ne teste
que le résultat, pas la durée.

## mem_timing/

`mem_timing.gb` et `mem_timing-2.gb` — vérifient *quand* précisément un accès
mémoire a lieu à l'intérieur du cycle d'une instruction (plus pointu que
`instr_timing`).

## halt_bug/

`halt_bug.gb` — teste le bug matériel connu de `HALT` : si `IME=0` et qu'une
interruption est en attente au moment du `HALT`, l'instruction suivante est
exécutée deux fois.

## dmg_sound/

`dmg_sound.gb` — teste le comportement de l'APU (4 canaux, enveloppe de volume,
sweep de fréquence, length timer, DAC). Seule suite Blargg pertinente pour la
partie audio du projet.

## oam_bug/

`oam_bug.gb` — teste un bug matériel obscur de corruption de l'OAM propre au DMG
(incréments/décréments de certains registres 16-bit pendant le mode 2 du PPU).
Faible priorité : peu de jeux en dépendent.

## interrupt_time/

`interrupt_time.gb` — teste le timing précis de prise en compte d'une interruption
après son déclenchement.

## Utiliser ces ROMs

Ces ROMs n'ont pas de header standard nécessitant un MBC (ROM ONLY, 32-64KB) : elles
tournent directement avec `bundle exec ruby lib/emugb.rb roms/tests/<suite>/<rom>.gb`.
