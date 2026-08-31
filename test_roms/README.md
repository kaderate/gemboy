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

## dmg-acid2.gb et expected/

`dmg-acid2.gb` ([mattcurrie/dmg-acid2](https://github.com/mattcurrie/dmg-acid2)) ne dit
rien sur le port série : son résultat *est* l'image affichée. Le verdict vient donc d'une
comparaison pixel à pixel entre le framebuffer final et `expected/dmg-acid2.png`, l'image
de référence du dépôt amont (capturée sur DMG). Une seule différence suffit à faire échouer
le test ; le PNG exporté par le run montre alors ce qui a changé.

Toute ROM dont le résultat est visuel peut suivre le même chemin : déposer sa référence
dans `expected/` et l'ajouter à `REFERENCES` dans `run_all.rb`. Le format attendu est celui
que `PngReader` sait lire : PNG 160x144, niveaux de gris 2 bits, non entrelacé.

## cgb-acid2.gbc et expected/

L'équivalent CGB de `dmg-acid2.gb`, même auteur, même méthode
([mattcurrie/cgb-acid2](https://github.com/mattcurrie/cgb-acid2)) : le verdict *est* l'image.
Contrairement à `dmg-acid2`, sa référence est en **couleur** (PNG truecolor, colortype 2), que
`PngReader` ne sait pas encore lire (il ne gère que le niveaux de gris 2 bits). Elle tourne donc
dans `run_all.rb` (screenshot manuel), mais n'est **pas encore** branchée sur `REFERENCES` — la
comparaison automatique attend que `PngReader` gagne le colortype 2.

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

Avec une image de référence en troisième argument, le résultat est tranché par comparaison
plutôt que par le port série :

```
bundle exec ruby test_roms/run_test.rb test_roms/dmg-acid2.gb /tmp/acid2.png test_roms/expected/dmg-acid2.png
```
