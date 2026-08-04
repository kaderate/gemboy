# ROMs de test (Blargg)

Suites de test de [Blargg](https://github.com/retrio/gb-test-roms), utilisées pour
valider la correction de l'émulateur indépendamment de tout jeu commercial. Chaque
ROM affiche `Passed`/`Failed` à l'écran et via le port série.

## homemade

Fait maison, principalement pour tester le PPU. Les roms sont écrites en assembleur.
Elles peuvent être compilés en `.gb` avec `make`.

## cpu_instrs/

Teste la correction fonctionnelle de chaque instruction du CPU (résultats, flags).
`cpu_instrs.gb` est la suite combinée (01 à 11 enchaînés) ; chaque `NN-*.gb` est un
sous-test isolable individuellement.

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

Certaines (dmg_sound, mem_timing-2...) nécessitent le MBC1 (implémenté) ; les autres
tournent en ROM ONLY simple. Lancement interactif (fenêtre SDL) :

```
bundle exec ruby lib/emugb.rb test_roms/<suite>/<rom>.gb
```

## run_test.rb

Lance une ROM headless (sans SDL/audio), détecte automatiquement la fin du test
("Passed"/"Failed" sur le port série, ou piège `JR $` de fin de test), et exporte
le framebuffer final en PNG :

```
bundle exec ruby test_roms/run_test.rb test_roms/dmg_sound/rom_singles/01-registers.gb
```
