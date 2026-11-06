.PHONY: help build build-local build-github clean preview all \
        install create-branches migrate-repo validate-structure clone-repos \
        generate-uml-classes-repo generate-uml-classes-all \
        commit-updated-grammars check-class-map

# Default target
.DEFAULT_GOAL := help

# Colors for output
CYAN := \033[0;36m
GREEN := \033[0;32m
YELLOW := \033[0;33m
RED := \033[0;31m
NC := \033[0m # No Color

# Configuration
REPOS_DIR := repos
BUILD_DIR := build
SPECS_REPOS := specifications-BASE specifications-RM specifications-AM \
               specifications-LANG specifications-SM specifications-QUERY \
			   specifications-PROC specifications-CDS specifications-CNF \
		  	   specifications-ITS-REST specifications-TERM
ADL_ANTLR_REPO := https://github.com/openEHR/adl-antlr.git
ADL_ANTLR_DIR  := $(REPOS_DIR)/adl-antlr
ADL_ANTLR_SRC  := $(ADL_ANTLR_DIR)/src/main/antlr/adl
OPENEHR_ANTLR4_REPO := https://github.com/openEHR/openEHR-antlr4.git
OPENEHR_ANTLR4_DIR  := $(REPOS_DIR)/openEHR-antlr4
OPENEHR_ANTLR4_SRC  := $(OPENEHR_ANTLR4_DIR)/reader_common/src/main/antlr
# update-grammars only refreshes these branches; release/* keep the grammar of their release
GRAMMAR_BRANCHES := development
on_grammar_branch = { case " $(GRAMMAR_BRANCHES) " in *" $$(git -C "$(1)" rev-parse --abbrev-ref HEAD) "*) true;; *) echo "$(CYAN)Skipping $(1): not on $(GRAMMAR_BRANCHES)$(NC)"; false;; esac; }

##@ General

help: ## Display this help message
	@echo "$(CYAN)openEHR Antora Migration & Build System$(NC)"
	@echo ""
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make $(CYAN)<target>$(NC)\n"} /^[a-zA-Z_0-9-]+:.*?##/ { printf "  $(CYAN)%-20s$(NC) %s\n", $$1, $$2 } /^##@/ { printf "\n$(YELLOW)%s$(NC)\n", substr($$0, 5) } ' $(MAKEFILE_LIST)


##@ Development Workflow

all: clean-all install create-all-branches migrate-all build-local preview ## Full setup from scratch: wipe everything, install, branch, migrate, build and preview

install: ## Install Node.js dependencies
	@echo "$(GREEN)Installing Node.js dependencies...$(NC)"
	npm install
	make clone-repos
	@echo "$(GREEN)Development environment setup complete!$(NC)"
	@echo "$(CYAN)Next steps:$(NC)"
	@echo "  1. Run 'make create-all-branches' to create release branches from tags"
	@echo "  2. Run 'make migrate-all' to migrate repositories to Antora structure"
	@echo "  3. Run 'make build-local' to build the site"
	@echo "  4. Run 'make preview' to preview the site"

clone-repos: ## Clone all openEHR specification repositories
	@echo "$(GREEN)Cloning openEHR specification repositories...$(NC)"
	@mkdir -p $(REPOS_DIR)
	@for repo in $(SPECS_REPOS); do \
		if [ ! -d "$(REPOS_DIR)/$$repo" ]; then \
			echo "$(CYAN)Cloning $$repo...$(NC)"; \
			git clone https://github.com/openEHR/$$repo.git $(REPOS_DIR)/$$repo; \
		else \
			echo "$(YELLOW)$$repo already exists, skipping...$(NC)"; \
		fi \
	done
	@echo "$(GREEN)Done cloning repositories.$(NC)"
	@$(MAKE) update-grammars

update-grammars: ## Clone/update grammar repos, copy .g4 into spec repos, git commit there
	@echo "$(GREEN)Updating ANTLR grammar files from adl-antlr...$(NC)"
	@if [ ! -d "$(ADL_ANTLR_DIR)" ]; then \
		echo "$(CYAN)Cloning adl-antlr...$(NC)"; \
		git clone $(ADL_ANTLR_REPO) $(ADL_ANTLR_DIR); \
	else \
		echo "$(CYAN)Updating adl-antlr...$(NC)"; \
		git -C $(ADL_ANTLR_DIR) pull --quiet; \
	fi
	@for module in ADL1.4 ADL2 OPT2; do \
		dir="$(REPOS_DIR)/specifications-AM/modules/$$module/partials"; \
		if [ -d "$$dir" ] && $(call on_grammar_branch,$$dir); then \
			echo "$(CYAN)Copying g4 files to AM/$$module/partials...$(NC)"; \
			cp $(ADL_ANTLR_SRC)/*.g4 "$$dir/"; \
		fi \
	done
	@echo "$(GREEN)Updating ANTLR grammar files from openEHR-antlr4...$(NC)"
	@if [ ! -d "$(OPENEHR_ANTLR4_DIR)" ]; then \
		echo "$(CYAN)Cloning openEHR-antlr4...$(NC)"; \
		git clone $(OPENEHR_ANTLR4_REPO) $(OPENEHR_ANTLR4_DIR); \
	else \
		echo "$(CYAN)Updating openEHR-antlr4...$(NC)"; \
		git -C $(OPENEHR_ANTLR4_DIR) pull --quiet; \
	fi
	@for module in EL; do \
		dir="$(REPOS_DIR)/specifications-LANG/modules/$$module/partials"; \
		if [ -d "$$dir" ] && $(call on_grammar_branch,$$dir); then \
			echo "$(CYAN)Copying g4 files to LANG/$$module/partials...$(NC)"; \
			cp $(OPENEHR_ANTLR4_SRC)/El*.g4 "$$dir/" 2>/dev/null || true; \
		fi \
	done
	@for module in odin BEL; do \
		dir="$(REPOS_DIR)/specifications-LANG/modules/$$module/partials"; \
		if [ -d "$$dir" ] && $(call on_grammar_branch,$$dir); then \
			echo "$(CYAN)Copying adl-antlr g4 files to LANG/$$module/partials...$(NC)"; \
			cp $(ADL_ANTLR_SRC)/*.g4 "$$dir/"; \
		fi \
	done
	@for module in odin expression; do \
		dir="$(REPOS_DIR)/specifications-BASE/modules/$$module/partials"; \
		if [ -d "$$dir" ]; then \
			echo "$(CYAN)Copying adl-antlr g4 files to BASE/$$module/partials...$(NC)"; \
			cp $(ADL_ANTLR_SRC)/*.g4 "$$dir/"; \
		fi \
	done
	@for module in decision_language; do \
		dir="$(REPOS_DIR)/specifications-PROC/modules/$$module/partials"; \
		if [ -d "$$dir" ] && $(call on_grammar_branch,$$dir); then \
			echo "$(CYAN)Copying adl-antlr g4 files to PROC/$$module/partials...$(NC)"; \
			cp $(ADL_ANTLR_SRC)/*.g4 "$$dir/"; \
		fi \
	done
	@echo "$(GREEN)Done copying grammar files.$(NC)"
	@$(MAKE) commit-updated-grammars

commit-updated-grammars: ## Stage and commit updated .g4 files under repos/specifications-*
	@echo "$(GREEN)Staging grammar commits in specification repos...$(NC)"
	@GRAMMAR_BRANCHES="$(GRAMMAR_BRANCHES)" ./scripts/commit-updated-grammars.sh $(REPOS_DIR)

list-repos: ## List all specification repositories
	@echo "$(CYAN)OpenEHR Specification Repositories:$(NC)"
	@for repo in $(SPECS_REPOS); do \
		echo "  - $$repo"; \
	done

check-deps: ## Check if required dependencies are installed
	@echo "$(CYAN)Checking dependencies...$(NC)"
	@command -v node >/dev/null 2>&1 || { echo "$(RED)Node.js is not installed$(NC)"; exit 1; }
	@command -v npm >/dev/null 2>&1 || { echo "$(RED)npm is not installed$(NC)"; exit 1; }
	@command -v git >/dev/null 2>&1 || { echo "$(RED)git is not installed$(NC)"; exit 1; }
	@echo "$(GREEN)All required dependencies are installed$(NC)"


##@ Repository Management

update-repos: ## Update all cloned repositories
	@echo "$(GREEN)Updating all repositories...$(NC)"
	@for repo in $(SPECS_REPOS); do \
		if [ -d "$(REPOS_DIR)/$$repo" ]; then \
			echo "$(CYAN)Updating $$repo...$(NC)"; \
			cd $(REPOS_DIR)/$$repo && git fetch --all && cd ../..; \
		fi \
	done
	@echo "$(GREEN)Done updating repositories.$(NC)"

create-branches: ## Create release/* from tags and development from master (usage: make create-branches REPO=specifications-BASE)
	@if [ -z "$(REPO)" ]; then \
		echo "$(RED)Error: REPO variable not set. Usage: make create-branches REPO=specifications-BASE$(NC)"; \
		exit 1; \
	fi
	@echo "$(GREEN)Creating release and development branches in $(REPO)...$(NC)"
	@./scripts/create-release-branches.sh $(REPOS_DIR)/$(REPO)

create-all-branches: ## Create release/* and development branches for all repositories
	@echo "$(GREEN)Creating release branches for all repositories...$(NC)"
	@for repo in $(SPECS_REPOS); do \
		echo "$(CYAN)Processing $$repo...$(NC)"; \
		make create-branches REPO=$$repo; \
	done
	@echo "$(GREEN)Done creating branches for all repositories.$(NC)"

##@ Migration Operations

migrate-repo: ## Migrate a single repository to Antora structure (usage: make migrate-repo REPO=specifications-BASE)
	@if [ -z "$(REPO)" ]; then \
		echo "$(RED)Error: REPO variable not set. Usage: make migrate-repo REPO=specifications-BASE$(NC)"; \
		exit 1; \
	fi
	@echo "$(GREEN)Migrating $(REPO) to Antora structure...$(NC)"
	@MIGRATION_BRANCH=$${MIGRATION_BRANCH:-development} ./scripts/migration/main-migrate-repo.sh $(REPOS_DIR)/$(REPO)
	@$(MAKE) update-grammars

migrate-all: ## Migrate all repositories to Antora structure
	@echo "$(GREEN)Migrating all repositories to Antora structure...$(NC)"
	@for repo in $(SPECS_REPOS); do \
		echo "$(CYAN)Migrating $$repo...$(NC)"; \
		make migrate-repo REPO=$$repo; \
	done
	@$(MAKE) update-grammars
	@echo "$(GREEN)Done migrating all repositories.$(NC)"

generate-uml-classes-repo: ## Generate ROOT UML class partials via bmm-publisher (usage: make generate-uml-classes-repo REPO=specifications-BASE)
	@if [ -z "$(REPO)" ]; then \
		echo "$(RED)Error: REPO variable not set. Usage: make generate-uml-classes-repo REPO=specifications-BASE$(NC)"; \
		exit 1; \
	fi
	@echo "$(GREEN)Generating UML classes for $(REPO)...$(NC)"
	@repo_path="$(REPOS_DIR)/$(REPO)"; \
	component="$${repo_path##*/}"; \
	component="$${component#specifications-}"; \
	cd "$$repo_path" && ../../scripts/migration/3a-generate-uml-classes.sh "$$component"

generate-uml-classes-all: ## Generate ROOT UML class partials for all repositories via bmm-publisher
	@echo "$(GREEN)Generating UML classes for all repositories...$(NC)"
	@for repo in $(SPECS_REPOS); do \
		echo "$(CYAN)Generating UML classes for $$repo...$(NC)"; \
		make generate-uml-classes-repo REPO=$$repo; \
	done
	@echo "$(GREEN)Done generating UML classes.$(NC)"

validate-structure: ## Validate Antora structure in a repository (usage: make validate-structure REPO=specifications-BASE)
	@if [ -z "$(REPO)" ]; then \
		echo "$(RED)Error: REPO variable not set. Usage: make validate-structure REPO=specifications-BASE$(NC)"; \
		exit 1; \
	fi
	@echo "$(GREEN)Validating Antora structure in $(REPO)...$(NC)"
	@./scripts/validate-structure.sh $(REPOS_DIR)/$(REPO)

check-class-map: ## Check class_* in global-vars.yml against the class partials each repo's latest release includes
	@python3 scripts/check-class-map.py --repos $(REPOS_DIR)


validate-all: ## Validate Antora structure in all repositories
	@echo "$(GREEN)Validating all repositories...$(NC)"
	@for repo in $(SPECS_REPOS); do \
		echo "$(CYAN)Validating $$repo...$(NC)"; \
		make validate-structure REPO=$$repo; \
	done



##@ Build Operations

build: ## Build the full site using production playbook
	@echo "$(GREEN)Building openEHR specifications site...$(NC)"
	npx antora antora-playbook.yml
	@echo "$(GREEN)Build complete! Site generated in $(BUILD_DIR)$(NC)"

build-local: ## Build site using local repositories
	@echo "$(GREEN)Building site from local repositories...$(NC)"
	@if [ ! -d "$(REPOS_DIR)" ]; then \
		echo "$(RED)Error: $(REPOS_DIR) directory not found. Run 'make install' first.$(NC)"; \
		exit 1; \
	fi
	npx antora antora-playbook-local.yml 2>&1 | tee build.log
	@echo "$(GREEN)Build complete! Site generated in $(BUILD_DIR) — log: build.log$(NC)"

build-github: ## Build site using local repositories for github docs
	@echo "$(GREEN)Building site from local repositories for github docs...$(NC)"
	@if [ ! -d "$(REPOS_DIR)" ]; then \
		echo "$(RED)Error: $(REPOS_DIR) directory not found. Run 'make install' first.$(NC)"; \
		exit 1; \
	fi
	npx antora antora-playbook-github.yml 2>&1 | tee build-github.log
	@touch docs/.nojekyll
	@echo "$(GREEN)Build complete! Site generated in 'docs' — log: build-github.log$(NC)"

clean: ## Clean build artifacts and cache
	@echo "$(YELLOW)Cleaning build artifacts...$(NC)"
	rm -rf $(BUILD_DIR)
	rm -rf .cache
	@echo "$(GREEN)Clean complete.$(NC)"

clean-all: clean ## Clean everything including cloned repos
	@echo "$(RED)Cleaning everything including cloned repositories...$(NC)"
	rm -rf $(REPOS_DIR)
	@echo "$(GREEN)Clean complete.$(NC)"


##@ Preview

preview: ## Start local HTTP server to preview built site
	@if [ ! -d "$(BUILD_DIR)" ]; then \
		echo "$(RED)Error: Build directory $(BUILD_DIR) not found. Run 'make build' or 'make build-local' first.$(NC)"; \
		exit 1; \
	fi
	@echo "$(GREEN)Starting preview server at http://localhost:8080$(NC)"
	@echo "$(YELLOW)Press Ctrl+C to stop$(NC)"
	@cd $(BUILD_DIR) && python3 -m http.server 8080


##@ CI/CD

ci-build: install build ## CI build target
	@echo "$(GREEN)CI build complete$(NC)"


