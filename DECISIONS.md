# Décisions

Une entrée par choix structurant : contexte, options, choix, et la condition qui l'invaliderait.
Statuts : `ratifiée` (validée par le propriétaire), `mesurée` (établie empiriquement, à ratifier),
`prise sans validation` (héritée du spike, à revoir), `à trancher` (ouverte, propriétaire).

## D1 — Source de position et de salle : HRAM, pas OAM

- **Statut** : mesurée, à ratifier.
- **Contexte** : le spike lisait la position de Link dans l'OAM par exclusion et détection de
  tuile, et nommait les écrans par ordre de découverte. Deux chasses par diff mémoire avaient
  échoué en ne scannant que la WRAM. Un diff sur tout l'espace `0x0000-0xFFFF`, fait le 7 septembre
  après la revue, a trouvé les octets en HRAM.
- **Choix** : `0xFF98` (X), `0xFF99` (Y), `0xFF9E` (direction), `0xFFF6` (salle), `0xFFF7` (carte)
  sont la source primaire. Détail et `verified_count` dans `data/ram_registry.json`. L'OAM devient
  un cross-check, jamais la source.
- **Invalidée si** : une salle où ces octets ne suivent pas Link, ou deux salles distinctes avec le
  même `0xFFF6`+`0xFFF7`.

## D2 — Position par OAM

- **Statut** : prise sans validation pendant le spike, **obsolète** par D1.
- Conservée pour mémoire : elle a coûté `find_link`, `cell_for`, la détection de scroll par
  SCX/SCY, `clear_entry_lock!` et une part des budgets de retries. Ne pas réintroduire.

## D3 — Mode matériel : DMG

- **Statut** : prise sans validation. **À trancher.**
- **Contexte** : la ROM DX tourne en DMG faute de flag `--cgb`, découvert incidemment. Le contenu
  DX (donjon des couleurs, photographe) est verrouillé derrière le mode CGB. Les checkpoints et le
  catalogue de tuiles (hash incluant la palette) sont spécifiques au mode.
- **Options** : rester en DMG (checkpoints et données actuels réutilisables, contenu DX
  inaccessible) ou passer en CGB (tout régénérer, jeu complet, hash des tuiles à revoir).
- **Coût du report** : chaque nouveau checkpoint ou donnée créée en DMG sera à refaire si CGB est
  choisi plus tard.

## D4 — Exploration exhaustive par écran

- **Statut** : prise sans validation. **À trancher.**
- **Contexte** : `ScreenMap.build` sonde toutes les cases d'un écran, 1,5 à 5 h par écran, avec un
  plancher d'une sonde live par case. Le concept demande une exploration scriptée, pas exhaustive.
- **Options** : cartographier ce que le prochain objectif exige, en lisant le terrain depuis l'état
  du jeu ; ou tout cartographier, avec le nouvel outil sur snapshot.
- **Recommandation de la revue** : à la demande.

## D5 — `legacy/` se remplace, ne s'étend pas

- **Statut** : proposée par la revue, à ratifier.
- **Choix** : le code importé du spike sert à régénérer les checkpoints de `Zelda::Scenarios` et à
  produire le rapport, jusqu'à ce que `lib/` couvre ces deux usages. On n'y ajoute ni composant ni
  correctif au-delà de ce qu'exige une régénération. Ses grilles JSON servent d'oracle une fois,
  pour valider le nouvel outil de navigation, puis sont supprimées.
- **Invalidée si** : la réécriture de `lib/` n'a pas atteint la parité "régénérer tous les
  checkpoints" dans un délai fixé par le propriétaire.

## D6 — API de session headless côté gemboy, dépendance en gem épinglée

- **Statut** : proposée par la revue, à ratifier.
- **Choix** : gemboy expose un objet session (avancer de N frames, touches, lecture mémoire,
  snapshot/restore en mémoire, `Motherboard` dessous). Le save state devient une fonctionnalité de
  l'émulateur. Ce dépôt en dépend comme d'une gem à version épinglée ; un changement de timing de
  l'émulateur invalide explicitement les checkpoints au lieu de le faire silencieusement.
- **Invalidée si** : gemboy refuse cette API dans son périmètre ; alors elle vit ici, en
  s'appuyant sur `Motherboard` uniquement.

## D7 — Sonde de collision par snapshot, pas par marche-retour

- **Statut** : proposée par la revue, à ratifier.
- **Choix** : toute mesure sur une case part d'un snapshot en mémoire de l'état à cette case ;
  chaque direction est testée depuis ce même état puis restaurée. Plus de retour à pied, plus de
  budget de récupération, plus d'ordre de directions.
- **Invalidée si** : le coût mémoire d'un snapshot rend impraticable d'en garder un par case
  d'écran ; mesurer avant de conclure.
