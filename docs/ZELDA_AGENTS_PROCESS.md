# Processus de travail des agents

Section à copier telle quelle dans le `AGENTS.md` du futur dépôt de l'agent Zelda. Elle est
écrite pour l'agent, pas pour le propriétaire. Contexte de son origine : la revue
`ZELDA_ARCHITECTURE_REVIEW.md` sur la branche gemboy `claude/architecture-concept-review-4mkde0`,
où 50 commits en 3 jours ont produit un outil de cartographie très raffiné et zéro progrès sur le
but du projet.

---

## Processus

Ce dépôt a déjà dérivé une fois : trois jours d'autonomie, cinq correctifs successifs sur le même
mécanisme, des métriques de moyen prises pour du progrès, et des décisions d'un agent héritées
comme des faits par le suivant. Les règles ci-dessous existent pour que ça ne se reproduise pas.
Elles priment sur ton jugement de "il reste juste un petit fix à faire".

### Une session, une question

- Chaque session commence par **une question falsifiable, un critère de fin et un budget**
  (temps ou nombre de commits), écrits dans le premier message ou dans `NEXT.md`. Exemple valide :
  "Confirmer ou réfuter la position de Link en HRAM, budget 2 h, livrable : entrée du registre RAM
  promue ou réfutée plus une spec." Exemple invalide : "Avancer sur la navigation."
- La borne atteinte, tu t'arrêtes et tu rends un rapport, même si tu "vois la suite". La suite est
  une nouvelle question pour une nouvelle session.
- Avant d'écrire du code, tu **reformules le mandat en critère testable** en deux lignes et tu le
  fais valider. "Regarder l'écran comme un humain" n'est pas un critère. "Un écran dont toutes les
  tuiles sont cataloguées se traverse de A à B sans aucune sonde live" en est un.

### Trois rôles, jamais dans la même session

| Rôle | Fait | Ne fait pas |
|---|---|---|
| Explorateur | spikes jetables, mesures, diffs mémoire, scripts dans le scratchpad | commiter dans le code du projet, décider |
| Constructeur | implémente une décision déjà prise, avec specs, dans son worktree | changer de paradigme, "profiter" pour corriger autre chose |
| Réviseur | lit à froid, juge contre le document de concept et les décisions | lire le journal narratif avant d'avoir jugé, corriger lui-même |

Tu ne juges jamais ta propre construction. Une revue est déclenchée par le propriétaire tous les
N commits ou à chaque matin après une nuit d'autonomie, par une session fraîche sans historique.

### Des décisions, pas des récits

- `DECISIONS.md` est la seule mémoire des choix. Une entrée par décision : contexte, options,
  choix, **et la condition qui invaliderait le choix**. Exemple : "OAM comme source de position.
  Invalidée si une salle contient un sprite mobile autre que Link."
- Quand la condition d'invalidation se produit, c'est un **retour à la décision**, pas un
  contournement. Un villageois errant qui bloque une case n'est pas un cas à gérer avec un budget de
  retries, c'est la preuve que la décision est tombée.
- Le journal narratif (`BACKLOG.md` ou équivalent) est une archive. Tu ne le lis pas pour
  reprendre un chantier, tu lis `NEXT.md` et `DECISIONS.md`. Tu n'y écris pas de décision.
- `NEXT.md` tient sur une page : état, décisions en vigueur, prochaine question, comment la
  vérifier. Toute reprise commence là. Si une reprise exige plus d'une page de lecture, c'est
  `NEXT.md` qui est cassé, pas la reprise.

### Métriques de but, pas de moyen

Trois indicateurs, tenus à jour dans `NEXT.md`, à citer dans chaque rapport de session :

1. **Progression dans le jeu** : dernier jalon atteint (épée, donjon 1, etc.).
2. **Trajet A vers B** : frames émulées pour traverser un écran déjà connu, sans sonde live.
3. **Faits vérifiés** : entrées du registre RAM au statut `verified`.

Une taille de catalogue, un taux de skip, un nombre de cases résolues sont des métriques de moyen.
Un commit qui ne bouge aucun des trois indicateurs doit dire pourquoi il existe.

### Règle anti-rustine

**Trois correctifs successifs sur un même mécanisme sans progression d'un indicateur de but égale
arrêt obligatoire.** Tu écris dans `NEXT.md` une note "paradigme à questionner" avec la question
que le propriétaire doit trancher, et tu t'arrêtes. Le quatrième fix n'est pas "presque là", c'est
le signe que le problème est ailleurs.

### L'autonomie exécute, elle ne conçoit pas

- Une session sans humain (nuit, routine) **exécute des décisions déjà prises** : runs longs,
  rebuilds, campagnes de mesure, specs sur des faits établis.
- Elle ne choisit pas une architecture, ne change pas de source de vérité, ne crée pas un nouveau
  composant, n'introduit pas un nouveau repère de coordonnées.
- Son livrable du matin est **un tableau de mesures et une liste de questions**, pas une pile de
  commits. Si tu as pris une décision de conception pendant une session autonome, tu la marques
  explicitement `DÉCISION PRISE SANS VALIDATION` dans le rapport et dans `DECISIONS.md`.

### Les décisions de fond appartiennent au propriétaire

Tu ne tranches pas, tu proposes avec les options et leurs coûts :

- la couche d'observation (état du jeu en RAM contre sortie du PPU contre pixels) ;
- exploration exhaustive contre navigation à la demande ;
- le mode matériel (DMG contre CGB) ;
- ce qui relève du savoir de *jeu* interdit (où est l'épée) contre le savoir d'*ingénierie*
  autorisé comme hypothèse à vérifier (carte mémoire du désassemblage).

### La mémoire, c'est les specs et les données

- Tout fait mesuré sur le jeu devient **une spec sur checkpoint** ou **une entrée de registre avec
  provenance**. Un fait qui n'est ni l'un ni l'autre sera redécouvert par le prochain agent, à
  plein tarif.
- Pas de commentaire-essai dans le code. Un commentaire tient sur une ligne et dit un *pourquoi*
  non déductible. Le raisonnement va dans le message de commit ou dans `DECISIONS.md`.
- Une exploration qui n'a pas produit de spec ou d'entrée de registre n'a rien produit.

### Parallélisme

- Plusieurs agents seulement sur des **questions indépendantes et bornées**, chacun dans son
  worktree, intégration par le propriétaire.
- Jamais deux agents sur le même mécanisme. Jamais un agent qui construit sur une décision qu'un
  autre agent est en train de remettre en cause.

### Rapport de fin de session

Toujours le même format, dans `NEXT.md`, pour que le suivant reprenne sans te lire :

```
Question : ...
Réponse : confirmée / réfutée / indécise (et pourquoi)
Indicateurs : jeu = ... | trajet A→B = ... | faits vérifiés = ...
Décisions prises : (aucune, ou liste marquée validée / non validée)
Prochaine question proposée : ...
Ce qu'il ne faut PAS refaire : ...
```
