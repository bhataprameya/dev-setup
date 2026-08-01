# dev-setup — top-level tasks
# Delegates to every component folder that has its own Makefile.

SHELL := /bin/sh

# Any immediate subdirectory containing a Makefile is a component.
COMPONENTS := $(patsubst %/Makefile,%,$(wildcard */Makefile))

.DEFAULT_GOAL := help

.PHONY: help
help: ## Show this help
	@echo "dev-setup — make targets"
	@echo
	@grep -hE '^[a-zA-Z0-9_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
	  | awk 'BEGIN{FS=":.*?## "}{printf "  \033[1;34m%-10s\033[0m %s\n", $$1, $$2}'
	@echo
	@echo "Components: $(COMPONENTS)"
	@echo
	@echo "Run a single component's tasks directly, e.g.:"
	@echo "  cd zsh-install && make test"

.PHONY: list
list: ## List discovered components
	@for c in $(COMPONENTS); do echo "  $$c"; done

.PHONY: lint
lint: ## Lint every component
	@for c in $(COMPONENTS); do \
	  echo "==> $$c"; \
	  $(MAKE) -C "$$c" lint || exit 1; \
	done

.PHONY: test
test: ## Run every component's test suite
	@for c in $(COMPONENTS); do \
	  echo "==> $$c"; \
	  $(MAKE) -C "$$c" test || exit 1; \
	done

.PHONY: clean
clean: ## Clean every component
	@for c in $(COMPONENTS); do \
	  $(MAKE) -C "$$c" clean || true; \
	done
