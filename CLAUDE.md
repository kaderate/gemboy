# Gemboy — notes pour agents

Émulateur Game Boy DMG-01 et Game Boy Color en Ruby (pas de SGB). Le mode est déterminé par
`ModelSelector` à partir de l'en-tête de la ROM (flag CGB à `$0143`) et du flag CLI `--cgb`
(force le mode CGB sur une ROM "dual-compatible") ; une ROM `.gbc` non compatible DMG tourne
en CGB, sinon en DMG.

Architecture, composants et décisions de conception : [ARCHITECTURE.md](ARCHITECTURE.md).
Ne pas les redécrire ici, ça diverge.

## Commandes

```bash
bundle exec rspec                                          # suite complète
bundle exec rspec --tag accuracy                           # verrou cpu_instrs + dmg-acid2 + cgb-acid2 (~40s, exclu par défaut)
bundle exec rubocop                                        # lint
bin/gemboy roms/<rom>.gb                                   # lancer une ROM (fenêtre SDL)
ruby test_roms/run_test.rb <rom.gb> <out.png>              # une ROM headless + screenshot
ruby test_roms/run_all.rb                                  # rapport HTML de toutes les suites
ruby profiling/run_profiling.rb <stackprof|vernier>        # profiling
```

## Déboguer une ROM

Deux réflexes avant de toucher au code :

1. **Se demander ce que fait le vrai hardware (DMG ou CGB selon le mode de la ROM)**, pas ce
   que fait notre code. La plupart des symptômes spectaculaires (opcode invalide, boucle
   infinie, écran figé) viennent d'une hypothèse matérielle qu'on ne reproduit pas, pas d'une
   instruction fausse. Pandocs tranche — et DMG/CGB divergent souvent sur les mêmes registres
   (`LCDC.0`, priorité sprite...), vérifier lequel des deux modes est réellement actif avant de
   supposer un comportement.
2. **Lire la ROM avant d'accuser l'émulateur.** Désassembler les octets autour de l'adresse
   suspecte (`File.binread(rom).bytes`) sépare un bug de chez nous d'un comportement légitime
   du jeu. Un état qui paraît aberrant peut être voulu : la pile de SML2 vit en RAM externe
   (`LD SP,$A8FF`), un SP hors WRAM n'est donc pas une corruption.

Outillage, dans cet ordre : reproduire en headless avec un script jetable (composants
instanciés à la main, inputs simulés en fonction du temps émulé, borne en cycles) ; garder un
historique circulaire des N dernières instructions dumpé dans le `rescue` ; poser un watchpoint
mémoire via `MMU.prepend` sur `#write`. Annoncer ce que le script va mesurer avant de le lancer.

Les root causes déjà élucidées et les pistes écartées sont dans `docs/BACKLOG_DONE.md` : le
lire avant de rouvrir une enquête sur l'APU, le PPU ou les MBC.

## Tests

- `spec/` — RSpec. Passer par les builders de `spec/support/builders.rb` (`build_mmu`,
  `build_cpu`, `build_ppu`…). Par défaut le MMU n'a pas l'état post-boot : une spec qui dépend
  d'un registre ou d'un flag doit le poser explicitement.
- `test_roms/` — suites de référence (Blargg, dmg-acid2, cgb-acid2, mealybug), headless.
  `test_roms/homemade/` est exclu de `run_all.rb`.
- Lire le résultat d'une ROM via le port série ou le PNG exporté par le run courant, jamais un
  fichier déjà présent dans `test_roms/screenshots/` : il peut être périmé.
- `run_all.rb` tourne déjà dans les deux CI et prend plusieurs minutes : ne pas le lancer sans
  demander.

## Conventions

- **Commits** : une seule ligne, à l'impératif, pas de corps. Impact entre parenthèses si
  utile : `Freeze the PPU while the LCD is off (unblocks Super Mario Land 2)`.
- **Commentaires** : quasi aucun, et **en anglais**. Uniquement une contrainte cachée, un
  invariant subtil ou un *pourquoi* non déductible du code, en une ligne. Jamais d'en-tête de
  méthode. Justifier un fix se fait dans le message de commit ou le backlog, pas dans le code.
- **Répartition** : le propriétaire du dépôt écrit lui-même ce qui a une valeur d'apprentissage
  (diagnostic, cœur de l'émulation) ; le mécanique ou répétitif (specs à mettre à jour, tables
  de constantes, outillage) peut être délégué. Discuter l'approche avant de se lancer.

## Outils

- `docs/` est **local et gitignoré** (`/docs/*`) : `BACKLOG.md` (chantiers ouverts, source de
  vérité sur ce qui reste à faire), `BACKLOG_DONE.md` (root causes et pièges archivés) et
  `PERFORMANCE.md` (mesures et pistes d'optimisation). Ne pas y faire référence depuis un
  fichier versionné, le lien serait mort pour qui clone le dépôt.
- `scripts/ai_commit_msg.sh` propose un message de commit depuis le diff indexé, via un hook
  `prepare-commit-msg` à installer une fois (le hook n'est pas versionné) :
  ```bash
  printf '#!/bin/sh\nexec "$(git rev-parse --show-toplevel)/scripts/ai_commit_msg.sh" "$@"\n' > .git/hooks/prepare-commit-msg
  chmod +x .git/hooks/prepare-commit-msg
  ```
  `GEMBOY_AI_MSG=0 git commit` le désactive ponctuellement.

## Documentation externe

Pandocs fait référence. `gbdev.io/pandocs` répond 403 en fetch direct et
`raw.githubusercontent.com` 404 sur ce dépôt : passer par l'API GitHub
`repos/gbdev/pandocs/contents/src/<fichier>.md` et décoder le base64.
