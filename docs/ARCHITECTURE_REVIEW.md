# Revue d'architecture et de concept du spike

Revue faite le 7 septembre 2026 sur le spike `lib/game_agents/` de gemboy, alors à 50 commits en
3 jours ; mise à jour le même jour après que la branche d'exploration a vérifié l'hypothèse HRAM
et cartographié trois écrans de plus. Périmètre : concept et architecture, pas de revue de code.
Le code revu est dans `legacy/`, le concept dans `docs/CONCEPT.md`, le journal dans
`docs/archive/EXPLORATION_LOG.md`.

## Verdict

Le concept est solide : exécution déterministe entre les décisions, faits lus en RAM, LLM
seulement aux points de décision, provenance traçable des faits. Le code du spike ne l'implémente
pas. Il construit un robot cartographe aveugle qui :

1. lit le jeu par la mauvaise couche (PPU : OAM et VRAM) au lieu de l'état du jeu (RAM/HRAM) ;
2. ignore le levier principal d'un émulateur déterministe (snapshot/restore instantané) et explore
   comme un robot physique ;
3. poursuit un objectif que le concept ne demande pas (cartographier exhaustivement chaque case de
   chaque écran) à un coût structurel de 1,5 à 5 h par écran.

Après 4 jours : 7 écrans cartographiés, 4 PNJ, pas d'épée, aucune boucle de décision. La valeur du
projet (un LLM qui joue) n'a pas commencé.

## Ce qui tient et a été gardé

- **Le document de conception** (`docs/CONCEPT.md`) : découplage exécution/décision, déclencheurs
  détectés par code, pause-capture, split planner/executor, confiance par `verified_count`.
- **`Zelda::Checkpoint`** (Marshal de tout l'état émulateur, 0,03 s dump / 0,05 s load) et le
  chaînage de `Zelda::Scenarios`. Meilleure idée technique du spike, socle de tout le reste. Les
  séquences d'entrée des scénarios encodent des heures d'exploration.
- **La discipline de validation** : cross-validation entre deux outils, données suspectes jetées
  plutôt que commitées, fixes revalidés en live. La découverte de la contamination du catalogue par
  le coin `[3,3]` de starting_house est un vrai résultat.
- **Trois trouvailles durables** : le scratch-buffer de tuiles pour le texte des dialogues
  (`0xD0-0xEF`, décoder par bitmap jamais par ID) ; le modèle de mouvement verrouillé sur la tuile
  (un appui d'une frame commet ~14 px ou un rebond, en ~24-28 frames) ; et, après la revue, la
  position et la salle en HRAM.
- **`TilemapReader`** : lecture BG correcte, calquée sur l'adressage du PPU, avec le piège DMG/CGB
  identifié. Utile pour "regarder l'écran" en cross-check.

## Problème de fond 1 — la couche d'observation

Le concept dit "RAM, pas vision". L'implémentation a glissé vers "PPU, pas RAM" :

| Fait | Lu par le spike via | Fragilité observée |
|---|---|---|
| Position de Link | OAM (`find_link`, tuile 0/2, exclusion de positions) | slot réassigné, pose idle non reconnue, Tarin pris pour Link, villageois errant |
| Changement d'écran | SCX/SCY, avant ça une distance en px | caméra qui pan sur screen3, faux `:exit` sur starting_house |
| Terrain | tilemap VRAM, hash 8×8 + palette | même motif de sol partagé entre cases au comportement différent |
| HUD | window layer | reconfiguré dynamiquement pendant un dialogue |

L'OAM et la VRAM sont la *vue* du jeu, pas son *modèle*. Toute la machinerie de `TileClassifier`
(cell_for, dérive de coin, `:lost`, `clear_entry_lock!`, budgets de retries) compense l'absence de
trois faits présents en mémoire : coordonnées réelles de Link, identifiant de salle, collision.

**Position et salle : confirmé.** Les deux chasses par diff mémoire du spike n'avaient scanné que
la WRAM. Un diff sur tout l'espace `0x0000-0xFFFF` a trouvé en une passe `0xFF98` (X), `0xFF99`
(Y), `0xFF9E` (direction), `0xFFF6` (salle) et `0xFFF7` (carte), en accord avec le désassemblage
communautaire de LADX. Détail dans `data/ram_registry.json`, décision D1.

**Collision : hypothèse suivante, même méthode.** Le jeu décode chaque salle en une grille
d'objets 16×16 (10×8 par écran) en WRAM, et lit la physique de chaque type d'objet dans une table
ROM. Le catalogue de tuiles reconstruit empiriquement, à 8×8 et par hash de pixels, une information
que le jeu stocke explicitement au bon niveau de granularité. Le fait que `TileCatalog` ait besoin
que les 4 tuiles d'une cellule soient d'accord est déjà une approximation de l'objet 16×16 du jeu.
C'est la prochaine question de `NEXT.md`.

## Problème de fond 2 — le déterminisme n'est pas exploité

L'émulateur est déterministe et la restauration coûte 0,046 s. Pourtant `ScreenMap.build` explore
comme un robot physique : marcher jusqu'à la case, tester une direction, *revenir à pied*
(`walk_back_to_cell!`), budget de récupération par direction, re-navigation depuis le spawn après
chaque `reset`. Conséquences documentées dans le journal : dérive, "creep", contamination par
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

C'est la décision D7.

## Problème de fond 3 — cartographie exhaustive ou navigation à la demande

Le concept dit qu'Explore est "entièrement scripté, sans jugement", pas "exhaustif". Le spike a
choisi l'exhaustif sans le décider explicitement. Le coût :

| Mesure | Valeur |
|---|---|
| Écrans cartographiés en 4 jours | 7 |
| Coût d'un écran (`ScreenMap.build`) | 1,5 à 5 h (house2_interior : 2 h 05 pour 27 cases) |
| Plafond du taux de skip imposé par `live_probed` | 75 % (une sonde live par case minimum) |
| Meilleur taux observé | 71 % (starting_house) |
| Écrans d'overworld dans le jeu | environ 256, hors donjons et intérieurs |

Le garde `live_probed` contredit la promesse du catalogue ("tendre vers zéro test live"). Un joueur
humain ne sonde pas 40 cases, il regarde l'écran et marche. Si la collision se lit en WRAM
(prochaine question), la sonde devient un cross-check et non la source. Décision D4, au
propriétaire.

## Architecture

**Frontière émulateur/agent inexistante.** Les primitives sont des fonctions globales définies sur
`main` (`find_link`, `move_tiles`, `tap_key`), l'agent boote via `profiling/utils.rb` de gemboy,
`Checkpoint` pique des ivars privées de l'APU et du CPU. Le 5-uplet `[cpu, ppu, apu, mmu, keys]`
traverse chaque signature et se fait réassigner à chaque reset. Il manque un objet **session
headless côté gemboy** : avancer de N frames, presser/relâcher, lire une adresse, snapshot/restore
en mémoire. `Motherboard` et `debug/headless_emulator.rb` en sont déjà deux tiers. Il servirait
aussi `test_roms/` et `profiling/`. Décision D6.

**Placement.** Un sous-arbre spécifique à une ROM vivait dans `lib/` de l'émulateur, hors de son
`ARCHITECTURE.md`, avec zéro spec alors que l'émulateur en a 1237, des offenses rubocop tolérées et
des commentaires-essais contraires à ses conventions. D'où ce dépôt, qui dépend de gemboy comme
d'une gem.

**Le temps est compté en instructions.** `run_steps(60_000_000)` pour attendre le boot,
`hold: 100_000` pour un appui, mélangés à `TRIGGER_FRAMES * FRAME_CYCLES`. Le jeu échantillonne par
frame ; l'agent doit ne parler qu'en frames. Mieux : attendre une **condition** d'état (ce que le
concept appelle un déclencheur) au lieu d'un compteur. Les scénarios sont des minuteries en boucle
ouverte, fragiles au moindre changement de timing de l'émulateur. Le checkpoint `villager_screen`
sauvé mi-scroll en est un symptôme.

**Trois générations de mappers, quatre repères.** `Navigator` (grille statique + greedy pixel),
`RoomMap::Recorder` (nœuds pixel snappés), `ScreenGrid` (cellules 16 px depuis les pieds OAM), plus
`world_model.json.map_graph` écrit à la main. Aucun repère canonique : les écrans s'appellent
"screen2" par ordre de découverte, les arêtes `:exit` ne relient rien. `0xFFF6` donne la clé et le
graphe monde gratuitement.

**Le modèle de données n'existe qu'en doc.** Le registre RAM vient de recevoir ses premières
vraies entrées ; `world_model.json` est édité à la main avec de la prose dedans, alors que le
concept prévoit une mise à jour mécanique par lecture RAM ; pas d'action log.

**DMG ou CGB, décision implicite.** Décision D3, au propriétaire.

**Politique sur la connaissance pré-entraînée.** L'anti-triche (`puzzle_validator.rb`) vise à
juste titre le savoir de *jeu*. Il a été appliqué implicitement au savoir d'*ingénierie*, ce qui a
coûté des jours : la carte mémoire du désassemblage était la bonne source d'hypothèses depuis le
début. Règle dans `AGENTS.md`.

## Plan, dans l'ordre

1. ~~Diff mémoire complet, HRAM incluse, pour position et salle.~~ Fait, D1.
2. **La collision se lit-elle en WRAM ?** Question de `NEXT.md`. Tranche D4 en pratique.
3. **API de session headless dans gemboy** (D6) : frames, touches, lecture mémoire,
   snapshot/restore en mémoire, specs. Save state comme fonctionnalité de l'émulateur.
4. **Nouvel outil de navigation sur snapshot** (D7) dans `lib/`, validé une fois contre les grilles
   oracle de `legacy/`, puis régénération des 7 checkpoints sans `legacy/`. Suppression de
   `legacy/`.
5. **Trancher D3 et D4** avant d'accumuler de nouvelles données.
6. **Seulement ensuite**, la boucle de décision du concept : déclencheurs sur état RAM, planner,
   executor, action log JSONL. C'est là que la valeur du projet est censée être.

## Chantiers ouverts du spike, relus

- `[6,7]` d'overworld_screen3 (villageois errant suspecté) : disparaît avec D1 et D7.
- house2_interior : entré et cartographié par le spike après la revue. Pépé le Ramollo y parle d'un
  téléphone "à l'extérieur" : premier indice lu dans le jeu, à suivre par le planner.
- Croissance mémoire de `ScreenMap.build` : cesse d'être un sujet sans rechargement de fichier.
- OCR des dialogues : après la boucle de décision, pas avant.
- Épée et `cut_grass` : objectif de jeu, à traiter par le planner, pas par un script.
