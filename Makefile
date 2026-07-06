# dichotic-plugins hub — ergonomic wrappers over scripts/.
# Run `make help` for the list.

.DEFAULT_GOAL := help
SHELL := /bin/bash

.PHONY: help add-plugin update release secrets list

help: ## List targets
	@echo "dichotic-plugins hub"
	@echo
	@grep -E '^[a-zA-Z0-9_-]+:.*## ' $(MAKEFILE_LIST) | \
		awk 'BEGIN{FS=":.*## "}{printf "  \033[1m%-14s\033[0m %s\n", $$1, $$2}'
	@echo
	@echo "Examples:"
	@echo "  make add-plugin NAME=guillotine REPO=noahbaxter/guillotine"
	@echo "  make release PLUGIN=pewpew VERSION=0.2.0"
	@echo "  make release PLUGIN=pewpew        # version from the plugin's VERSION file"

add-plugin: ## Add a plugin submodule + plugins.json entry (NAME=, REPO=, [BRANCH=])
	@test -n "$(NAME)" || { echo "usage: make add-plugin NAME=foo REPO=noahbaxter/foo [BRANCH=main]"; exit 1; }
	@test -n "$(REPO)" || { echo "usage: make add-plugin NAME=foo REPO=noahbaxter/foo [BRANCH=main]"; exit 1; }
	@./scripts/add-plugin.sh "$(NAME)" "$(REPO)" $(BRANCH)

update: ## Pull all plugin submodules to latest branch tip
	@./scripts/update-plugins.sh

release: ## Trigger a release (PLUGIN=, [VERSION=])
	@test -n "$(PLUGIN)" || { echo "usage: make release PLUGIN=pewpew [VERSION=0.2.0]"; exit 1; }
	@./scripts/release.sh "$(PLUGIN)" $(VERSION)

secrets: ## Sync hub secrets from .secrets.env
	@./scripts/secrets-sync.sh

list: ## Print plugins.json nicely
	@jq . plugins.json
