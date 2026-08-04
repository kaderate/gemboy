# Lance les ROMs de test (Blargg + maison) headless via run_test.rb et
# génère une capture d'écran (screenshots/<suite>/<nom>.png) pour chacune.

RUBY := bundle exec ruby
RUN_TEST := run_test.rb
SCREENSHOTS_DIR := screenshots

GREEN  := \033[0;32m
YELLOW := \033[1;33m
NC     := \033[0m

SUITES := cpu_instrs dmg_sound halt_bug instr_timing interrupt_time mem_timing oam_bug

.PHONY: all clean rom $(SUITES)

# Lance toutes les suites
all: $(SUITES)

# Lance une suite précise (ex: make dmg_sound)
$(SUITES):
	@mkdir -p $(SCREENSHOTS_DIR)/$@
	@find $@ -name '*.gb' -print0 | while IFS= read -r -d '' rom; do \
		name=$$(basename "$$rom" .gb); \
		printf "$(YELLOW)-> %s$(NC)\n" "$$rom"; \
		$(RUBY) $(RUN_TEST) "$$rom" "$(SCREENSHOTS_DIR)/$@/$$name.png"; \
	done
	@printf "$(GREEN)Terminé : %s$(NC)\n" "$@"

# Lance une ROM précise : make rom ROM=chemin/vers/xxx.gb
rom:
	@test -n "$(ROM)" || (echo "Usage: make rom ROM=chemin/vers/rom.gb" && exit 1)
	@mkdir -p $(SCREENSHOTS_DIR)
	@$(RUBY) $(RUN_TEST) "$(ROM)" "$(SCREENSHOTS_DIR)/$$(basename "$(ROM)" .gb).png"

# Supprime les captures générées
clean:
	@rm -rf $(SCREENSHOTS_DIR)
