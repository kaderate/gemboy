# Koholint

Un agent qui joue à Link's Awakening DX à travers l'émulateur [gemboy](https://github.com/kaderate/gemboy),
en Ruby. Le concept : exécution déterministe entre les décisions, faits lus dans la mémoire du jeu,
LLM sollicité uniquement aux points de décision, chaque fait tracé jusqu'à sa source.

Ce dépôt est initialisé à partir du spike `lib/game_agents/` de gemboy (branche
`claude/usage-2mr345`, commit `c952ded`), après la revue d'architecture qui a conclu à une
réécriture sur des fondations différentes en gardant le savoir accumulé. La ROM n'est pas
versionnée.

## Par où commencer

Dans cet ordre, et rien d'autre avant d'avoir une question de session :

1. `NEXT.md` : état courant, indicateurs, prochaine question.
2. `DECISIONS.md` : les choix en vigueur et ce qui les invaliderait.
3. `AGENTS.md` : les règles de travail. Elles priment sur l'envie de "juste finir un fix".
4. `docs/ARCHITECTURE_REVIEW.md` : pourquoi on réécrit, et quoi.
5. `docs/CONCEPT.md` : le concept d'origine, toujours valide.

`docs/archive/EXPLORATION_LOG.md` est le journal narratif du spike. C'est une archive : on y
cherche un fait précis, on ne le lit pas pour reprendre le chantier.

## Arborescence

| Chemin | Rôle |
|---|---|
| `data/ram_registry.json` | Adresses mémoire du jeu, chacune avec sa provenance et son `verified_count`. Source de vérité pour tout ce qui lit la RAM. |
| `data/world_model.json` | Faits accumulés sur le jeu : salles, PNJ, dialogues, inventaire, modèle de mouvement. |
| `data/puzzle_*.json` | Le paquet d'entrée et les hypothèses du premier puzzle résolu, avec leur validateur dans `legacy/`. |
| `legacy/` | Le code du spike, intact. Il régénère les checkpoints de `Zelda::Scenarios` et fait tourner le rapport "Carnet de Koholint". À remplacer, pas à étendre (voir `DECISIONS.md`). Ses grilles JSON servent d'oracle pour valider le nouvel outil de navigation, une fois. |
| `lib/` | Le nouveau code. Vide au départ. |

## Dépendance à gemboy

Le code de `legacy/` atteint les internes de gemboy par chemins relatifs (`profiling/utils.rb`,
`lib/ppu/tile.rb`) et ne tourne donc pas tel quel ici. La première brique du nouveau code est une
API de session headless côté gemboy (frames, touches, lecture mémoire, snapshot/restore en
mémoire) dont ce dépôt dépendra comme d'une gem, version épinglée. Tant qu'elle n'existe pas,
`legacy/` se lance depuis un clone de gemboy.

## Commandes

Aucune pour l'instant. Elles arriveront avec `lib/`.
