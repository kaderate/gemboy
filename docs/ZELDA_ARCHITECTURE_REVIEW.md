# Zelda agent — revue d'architecture et de concept

Revue faite le 2026-09-07 sur la branche `claude/architecture-concept-review-4mkde0` (50 commits,
tout dans `lib/game_agents/`). Périmètre : concept général et architecture uniquement, pas de revue
de code. Destinée à l'agent qui reprend le chantier : lire ce fichier, puis `ZELDA_AGENT.md`
(le concept) et `ZELDA_BACKLOG.md` (le journal), dans cet ordre.

## Verdict

Le concept décrit dans `ZELDA_AGENT.md` est solide : exécution déterministe entre les décisions,
faits lus en RAM, LLM seulement aux points de décision, provenance traçable des faits. Le code de la
branche n'implémente pas ce concept. Il construit un robot cartographe aveugle qui :

1. lit le jeu par la mauvaise couche (PPU : OAM et VRAM) au lieu de l'état du jeu (RAM/HRAM) ;
2. ignore le levier principal d'un émulateur déterministe (snapshot/restore instantané) et explore
   comme un robot physique ;
3. poursuit un objectif que le concept ne demande pas (cartographier exhaustivement chaque case de
   chaque écran) à un coût structurel de 1,5 à 5 h par écran.

Après 3 jours : 4 écrans cartographiés dont 2 partiels, pas d'épée, house2 toujours pas entrée,
aucune boucle de décision. La valeur du projet (un LLM qui joue) n'a pas commencé.

## Ce qui tient et doit être conservé

- **Le document de conception** (`ZELDA_AGENT.md`) : découplage exécution/décision, déclencheurs
  détectés par code, pause-capture, split planner/executor, confiance par `verified_count`. Bon cadre.
- **`Zelda::Checkpoint`** (Marshal de tout l'état émulateur, 0,03 s dump / 0,05 s load) et le
  chaînage de `Zelda::Scenarios`. Meilleure idée technique de la branche, socle de tout le reste.
- **La discipline de validation** : cross-validation entre deux outils, données suspectes jetées
  plutôt que commitées, fixes revalidés en live. La découverte de la contamination du catalogue par
  le coin `[3,3]` de starting_house (backlog, section "quatrième finding") est un vrai résultat.
- **Deux trouvailles durables** : le scratch-buffer de tuiles pour le texte des dialogues
  (`0xD0-0xEF`, décoder par bitmap jamais par ID), et le modèle de mouvement verrouillé sur la tuile
  (un appui d'une frame commet ~14 px ou un rebond, en ~24-28 frames).
- **`TilemapReader`** : lecture BG correcte, calquée sur l'adressage du PPU, avec le piège DMG/CGB
  identifié.

## Problème de fond 1 — la couche d'observation

Le concept dit "RAM, pas vision". L'implémentation a glissé vers "PPU, pas RAM" :

| Fait | Lu aujourd'hui via | Fragilité observée |
|---|---|---|
| Position de Link | OAM (`find_link`, tuile 0/2, exclusion de positions) | slot réassigné, pose idle non reconnue, Tarin pris pour Link, villageois errant |
| Changement d'écran | SCX/SCY, avant ça une distance en px | caméra qui pan sur screen3, faux `:exit` sur starting_house |
| Terrain | tilemap VRAM, hash 8×8 + palette | même motif de sol partagé entre cases au comportement différent |
| HUD | window layer | reconfiguré dynamiquement pendant un dialogue |

L'OAM et la VRAM sont la *vue* du jeu, pas son *modèle*. Toute la machinerie de `TileClassifier`
(cell_for, dérive de coin, `:lost`, `clear_entry_lock!`, budgets de retries) compense l'absence de
trois faits présents en mémoire : coordonnées réelles de Link, identifiant de salle, collision.

**Hypothèse à vérifier en priorité.** Les deux chasses par diff mémoire du backlog n'ont scanné que
la WRAM (`0xC000-0xDFFF`). De mémoire, le désassemblage communautaire de LADX place la position de
Link en **HRAM** (`hLinkPositionX` vers `$FF98`, `hLinkPositionY` vers `$FF99`), la direction vers
`$FF9E`, l'identifiant de salle (`hMapRoom`) vers `$FFF6` et l'identifiant de carte vers `$FFF7`.
Ce sont des souvenirs, pas des faits : à traiter comme des hypothèses `ram_read_hypothesis` et à
promouvoir par la méthode déjà éprouvée (delta constant sur 4 appuis, inversion de signe
gauche/droite, axe orthogonal stable). Protocole : depuis un checkpoint, diff sur **tout** l'espace
`0x0000-0xFFFF` (HRAM incluse) avant/après un `move_tiles`, quatre fois dans la même direction.

**Même remarque pour la collision.** Le jeu décode chaque salle en une grille d'objets 16×16
(10×8 par écran) en WRAM, et lit la physique de chaque type d'objet dans une table ROM. Le catalogue
de tuiles reconstruit empiriquement, à 8×8 et par hash de pixels, une information que le jeu stocke
explicitement au bon niveau de granularité. Le fait que `TileCatalog` ait besoin que les 4 tuiles
d'une cellule soient d'accord est déjà une approximation de l'objet 16×16 du jeu.

## Problème de fond 2 — le déterminisme n'est pas exploité

L'émulateur est déterministe et la restauration coûte 0,046 s. Pourtant `ScreenMap.build` explore
comme un robot physique : marcher jusqu'à la case, tester une direction, *revenir à pied*
(`walk_back_to_cell!`), budget de récupération par direction, re-navigation depuis le spawn après
chaque `reset`. Conséquences documentées dans le backlog : dérive, "creep", contamination par
l'ordre des directions (`up` d'abord change le résultat de `down`), garde `live_probed`,
`MAX_RECOVERIES_PER_CELL`, cellules `SKIPPED`, RSS à 1,4 Go après 1,75 h de rechargements de
fichier.

Avec un snapshot **en mémoire** par case (Marshal vers une String, pas vers un fichier) :

- chaque direction se teste depuis un état strictement identique, puis on restaure ;
- plus de marche-retour, plus de dérive, plus d'effet d'ordre : `DIRECTIONS` cesse d'être un
  paramètre ;
- le quirk de coin de `[3,3]` devient une propriété déterministe de l'état, testable et
  reproductible, plus un accident d'historique ;
- `live_probed`, les budgets de récupération et la moitié de `screen_map.rb` disparaissent ;
- le coût d'une direction tombe à ~30 frames émulées + une restauration.

## Problème de fond 3 — cartographie exhaustive ou navigation à la demande

Le concept dit qu'Explore est "entièrement scripté, sans jugement", pas "exhaustif". La branche a
choisi l'exhaustif sans le décider explicitement. Le coût :

| Mesure | Valeur |
|---|---|
| Écrans cartographiés en 3 jours | 4, dont 2 partiels |
| Coût d'un écran (`ScreenMap.build`) | 1,5 à 5 h |
| Plafond du taux de skip imposé par `live_probed` | 75 % (une sonde live par case minimum) |
| Meilleur taux observé | 71 % (starting_house) |
| Écrans d'overworld dans le jeu | environ 256, hors donjons et intérieurs |

Le garde `live_probed` contredit la promesse du catalogue ("tendre vers zéro test live"). Un joueur
humain ne sonde pas 40 cases, il regarde l'écran et marche. `ScreenSnapshot` est le seul composant
qui "regarde" vraiment, et il n'est branché sur aucune navigation. Décision à prendre par le
propriétaire : cartographier ce que le prochain objectif exige (recommandé), ou tout cartographier.

## Architecture

**Frontière émulateur/agent inexistante.** Les primitives sont des fonctions globales définies sur
`main` (`find_link`, `move_tiles`, `tap_key`), l'agent boote via `profiling/utils.rb`
(`build_emulator`, `run_steps`), `Checkpoint` pique des ivars privées de l'APU et du CPU. Le
5-uplet `[cpu, ppu, apu, mmu, keys]` traverse chaque signature (offenses `ParameterLists`
tolérées) et se fait réassigner à chaque reset. Il manque un objet **session headless côté gemboy**
: avancer de N frames, presser/relâcher, lire une adresse, snapshot/restore en mémoire. `Motherboard`
et `debug/headless_emulator.rb` en sont déjà deux tiers. Il servirait aussi `test_roms/` et
`profiling/`.

**Placement dans le dépôt.** Un sous-arbre spécifique à une ROM, avec ~100 Ko de JSON et des
scripts d'expérience, vit dans `lib/`, hors d'`ARCHITECTURE.md`, avec **zéro spec** alors que
l'émulateur en a 1237, des offenses rubocop tolérées, et des commentaires-essais contraires aux
conventions de `CLAUDE.md` (quasi aucun commentaire, une ligne, en anglais). Soit c'est un spike et
il sort de `lib/`, soit c'est un composant et il a les mêmes exigences que le reste. Une gem ou un
dépôt séparé dépendant de gemboy forcerait l'API de session à exister.

**Le temps est compté en instructions.** `run_steps(60_000_000)` pour attendre le boot,
`hold: 100_000` pour un appui, mélangés à `TRIGGER_FRAMES * FRAME_CYCLES`. Le jeu échantillonne par
frame ; l'agent devrait ne parler qu'en frames. Mieux : attendre une **condition** d'état (ce que le
concept appelle un déclencheur) au lieu d'un compteur. Les scénarios sont des minuteries en boucle
ouverte, fragiles au moindre changement de timing de l'émulateur, qui est exactement ce que le
dépôt principal fait évoluer. Le checkpoint `villager_screen` sauvé mi-scroll en est un symptôme.

**Trois générations de mappers, quatre repères.** `Navigator` (grille statique + greedy pixel,
obsolète), `RoomMap::Recorder` (nœuds pixel snappés à `SNAP_RADIUS`), `ScreenGrid` (cellules 16 px
depuis les pieds OAM), plus `world_model.json.map_graph` écrit à la main. Aucun repère canonique,
aucune coordonnée monde : les écrans s'appellent "screen2" par ordre de découverte, les arêtes
`:exit` de `ScreenGrid` ne relient rien. Un identifiant de salle lu en RAM donne la clé et le graphe
monde gratuitement. Garder `RoomMap` uniquement comme outil de cross-check archivé, supprimer
`Navigator`.

**Le modèle de données n'existe qu'en doc.** `ram_registry.json` a deux vraies entrées ;
`world_model.json` est édité à la main avec de la prose dedans, alors que le concept prévoit une mise
à jour mécanique par lecture RAM ; pas d'action log. La connaissance vit dans un backlog narratif
de 816 lignes et dans des commentaires, pas dans des specs ni des données.

**DMG ou CGB, décision implicite.** La ROM DX tourne en DMG faute de `--cgb`, découvert "en
passant" dans `TilemapReader`. Le contenu DX (donjon des couleurs, photographe) est verrouillé
derrière le mode CGB, et le catalogue (hash incluant la palette) comme les checkpoints sont
spécifiques au mode. À trancher maintenant, avant que la dette ne grossisse.

**Politique sur la connaissance pré-entraînée.** L'anti-triche (`puzzle_validator.rb`) vise à
juste titre le savoir de *jeu* (où est l'épée, qui est Marin). Il est appliqué implicitement au
savoir d'*ingénierie* (carte mémoire du jeu), ce qui a coûté des jours. Rendre la frontière
explicite : la carte mémoire du désassemblage est une source d'**hypothèses à vérifier**, ce qui
est exactement le modèle de provenance de `ZELDA_AGENT.md`. Le savoir de jeu reste interdit.

## Plan recommandé, dans l'ordre

1. **Diff mémoire complet, HRAM incluse**, pour trouver position et salle (protocole ci-dessus).
   Une demi-journée. Si l'hypothèse tient, `find_link`, `cell_for`, la détection de scroll et
   `clear_entry_lock!` deviennent inutiles. Consigner le résultat dans `ram_registry.json`, promu
   ou réfuté.
2. **Objet session headless dans gemboy** (`lib/`, pas dans l'agent) : frames comme seule unité,
   presses, lecture mémoire, snapshot/restore en mémoire, `Motherboard` dessous. Migrer l'agent et
   supprimer la dépendance à `profiling/utils.rb`. Écrire ses specs.
3. **Réécrire la sonde sur snapshot-par-case** au lieu de marche-retour. Supprimer `live_probed`,
   les budgets de récupération, `walk_back_to_cell!`, `Navigator`. Reconstruire les 4 écrans avec le
   nouvel outil pour valider contre les grilles commitées (elles servent d'oracle une fois, puis on
   les remplace).
4. **Trancher deux décisions produit** : exhaustif contre à-la-demande, et DMG contre CGB. Les
   deux changent ce qu'on garde des données déjà commitées.
5. **Seulement ensuite**, la boucle de décision du concept : déclencheurs sur état RAM, planner,
   executor, action log JSONL. C'est là que la valeur du projet est censée être.

## Chantiers ouverts du backlog, relus à la lumière de ce qui précède

- `[6,7]` d'overworld_screen3 (villageois errant suspecté) : disparaît avec la position RAM et le
  snapshot par case (on peut attendre que le PNJ dégage, ou lire sa position).
- house2_interior (ressort par la porte dès qu'on bouge) : disparaît avec l'identifiant de salle et
  une case de porte marquée depuis la RAM, pas devinée.
- Croissance mémoire de `ScreenMap.build` : cesse d'être un sujet sans rechargement de fichier par
  reset.
- OCR des dialogues : reste à faire, mais après la boucle de décision, pas avant.
- Épée et `cut_grass` : objectif de jeu, à traiter par le planner, pas par un script.
