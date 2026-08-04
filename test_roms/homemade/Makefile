# Makefile RGBDS amélioré

# Couleurs
GREEN  := \033[0;32m
RED    := \033[0;31m
YELLOW := \033[1;33m
NC     := \033[0m

# Dossiers
SRC_DIR := .
BUILD_DIR := build

# Fichiers
ASM_SRCS := $(wildcard $(SRC_DIR)/*.asm)
ROMS := $(patsubst $(SRC_DIR)/%.asm,$(BUILD_DIR)/%.gb,$(ASM_SRCS))
OBJS := $(patsubst $(SRC_DIR)/%.asm,$(BUILD_DIR)/%.o,$(ASM_SRCS))

# Outils RGBDS
RGBASM := rgbasm
RGBLINK := rgblink
RGBFIX := rgbfix
RGBFIX_FLAGS := -v -p 0

# Flags
RGBASM_FLAGS :=
RGBLINK_FLAGS :=

# Cible par défaut : tout compiler
all: $(BUILD_DIR) $(ROMS)
	@echo -e "$(GREEN)✅ Compilation terminée pour toutes les ROMs$(NC)"

# Crée le dossier build si nécessaire
$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

# Génération ROM
$(BUILD_DIR)/%.gb: $(BUILD_DIR)/%.o
	@echo -e "$(YELLOW)🔗 Linking $< -> $@$(NC)"
	@$(RGBLINK) $(RGBLINK_FLAGS) -o $@ $<
	@echo -e "$(YELLOW)🎨 Fixing ROM $@$(NC)"
	@$(RGBFIX) $(RGBFIX_FLAGS) $@
	@echo -e "$(GREEN)✅ ROM générée : $@$(NC)"
	@rm -f $(BUILD_DIR)/$*.o  # supprime l'o après succès

# Assemblage
$(BUILD_DIR)/%.o: $(SRC_DIR)/%.asm | $(BUILD_DIR)
	@echo -e "$(YELLOW)🛠️  Assembling $<$(NC)"
	@$(RGBASM) $(RGBASM_FLAGS) -o $@ $<
	@echo -e "$(GREEN)✅ Objet généré : $@$(NC)"

# Nettoyage
clean:
	@echo -e "$(RED)🧹 Nettoyage des fichiers générés...$(NC)"
	@rm -rf $(BUILD_DIR)
	@echo -e "$(RED)✅ Fichiers temporaires supprimés$(NC)"

.PHONY: all clean
