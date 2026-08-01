# zsh-install — development tasks (part of dev-setup)
# Run `make help` for a list of targets.

SHELL     := /bin/sh
MIRRORS   := test/.mirrors
STRESS_N  ?= 100

.DEFAULT_GOAL := help

.PHONY: help
help: ## Show this help
	@echo "zsh-install — make targets"
	@echo
	@grep -hE '^[a-zA-Z0-9_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
	  | awk 'BEGIN{FS=":.*?## "}{printf "  \033[1;34m%-14s\033[0m %s\n", $$1, $$2}'
	@echo
	@echo "Examples:"
	@echo "  make test                 # lint + full functional suite"
	@echo "  make stress STRESS_N=100  # 100 install/re-install/boot cycles"
	@echo "  make docker-test          # run the installer on real Linux images"

.PHONY: lint
lint: ## Shellcheck + multi-shell parse check
	@echo "==> shellcheck (POSIX sh dialect)"
	@if command -v shellcheck >/dev/null 2>&1; then \
	  shellcheck -s sh -S warning install.sh test/run-tests.sh && echo "  ok clean"; \
	else echo "  ! shellcheck not installed (skipping)"; fi
	@echo "==> parse check"
	@for s in sh dash bash ksh zsh; do \
	  if command -v $$s >/dev/null 2>&1; then \
	    $$s -n install.sh && echo "  ok $$s"; \
	  fi; \
	done

.PHONY: mirrors
mirrors: ## Clone upstream repos locally so tests run fast/offline
	@mkdir -p $(MIRRORS)
	@set -e; \
	clone() { \
	  if [ -d "$(MIRRORS)/$$2/.git" ]; then \
	    echo "  ok $$2 (cached)"; \
	  else \
	    git clone --depth=1 -q "$$1" "$(MIRRORS)/$$2" && echo "  ok $$2"; \
	  fi; \
	}; \
	echo "==> mirroring upstreams into $(MIRRORS)"; \
	clone https://github.com/ohmyzsh/ohmyzsh.git                  ohmyzsh; \
	clone https://github.com/romkatv/powerlevel10k.git            powerlevel10k; \
	clone https://github.com/zsh-users/zsh-autosuggestions.git    zsh-autosuggestions; \
	clone https://github.com/zsh-users/zsh-syntax-highlighting.git zsh-syntax-highlighting; \
	clone https://github.com/zsh-users/zsh-completions.git        zsh-completions

.PHONY: test
test: lint mirrors ## Run the full functional test suite
	@echo
	@sh test/run-tests.sh

.PHONY: stress
stress: mirrors ## Run STRESS_N full install cycles (default 100)
	@sh test/run-tests.sh --stress $(STRESS_N)

.PHONY: e2e
e2e: ## Test the published one-liner against the live repo (needs network)
	@echo "==> end-to-end: published one-liner into a throwaway HOME"
	@H=$$(mktemp -d) && \
	  HOME=$$H NO_CHSH=1 NO_FONT=1 NO_EXEC=1 sh -c "$$(curl -fsSL https://raw.githubusercontent.com/bhataprameya/dev-setup/main/zsh-install/install.sh)" >/dev/null 2>&1 && \
	  grep -q 'powerlevel10k/powerlevel10k' $$H/.zshrc && \
	  test -s $$H/.p10k.zsh && \
	  test -d $$H/.oh-my-zsh/custom/plugins/zsh-autosuggestions && \
	  env -i HOME=$$H ZDOTDIR=$$H PATH=$$PATH TERM=xterm zsh -i -c 'exit 0' && \
	  echo "  ok one-liner works end-to-end" && rm -rf $$H

.PHONY: docker-test
docker-test: ## Run the installer on real Linux images (root + non-root)
	@if ! docker info >/dev/null 2>&1; then \
	  echo "docker daemon unavailable — start Docker and retry"; exit 1; fi
	@set -e; for img in debian:stable-slim ubuntu:24.04 alpine:3.20 fedora:40; do \
	  echo "==> $$img (root)"; \
	  docker run --rm -v "$$PWD:/src:ro" -w /root "$$img" sh -c '\
	    (command -v apk >/dev/null && apk add --no-cache git curl >/dev/null) || \
	    (command -v apt-get >/dev/null && apt-get update -qq && apt-get install -y -qq git curl >/dev/null) || \
	    (command -v dnf >/dev/null && dnf install -y -q git curl >/dev/null); \
	    cp -r /src /tmp/repo && cd /tmp/repo && \
	    NO_CHSH=1 NO_FONT=1 NO_EXEC=1 sh install.sh >/dev/null && \
	    grep -q powerlevel10k "$$HOME/.zshrc" && \
	    zsh -i -c "exit 0" && echo "    ok root install + boot"'; \
	  echo "==> $$img (non-root)"; \
	  docker run --rm -v "$$PWD:/src:ro" "$$img" sh -c '\
	    (command -v apk >/dev/null && apk add --no-cache git curl shadow sudo >/dev/null) || \
	    (command -v apt-get >/dev/null && apt-get update -qq && apt-get install -y -qq git curl sudo >/dev/null) || \
	    (command -v dnf >/dev/null && dnf install -y -q git curl sudo >/dev/null); \
	    (command -v zsh >/dev/null) || (command -v apk >/dev/null && apk add --no-cache zsh >/dev/null) || \
	      (command -v apt-get >/dev/null && apt-get install -y -qq zsh >/dev/null) || \
	      (command -v dnf >/dev/null && dnf install -y -q zsh >/dev/null); \
	    (adduser -D tester 2>/dev/null || useradd -m tester); \
	    cp -r /src /tmp/repo && chown -R tester /tmp/repo && \
	    su tester -c "cd /tmp/repo && NO_CHSH=1 NO_FONT=1 NO_EXEC=1 sh install.sh >/dev/null && \
	      grep -q powerlevel10k \$$HOME/.zshrc && zsh -i -c \"exit 0\" && echo \"    ok non-root install + boot\""'; \
	done

.PHONY: clean
clean: ## Remove cached mirrors and test leftovers
	@rm -rf $(MIRRORS)
	@echo "  ok cleaned"
