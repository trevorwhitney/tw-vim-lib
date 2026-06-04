.PHONY: help lint lint-lua lint-nix format format-lua format-nix test test-lua test-plenary test-go

help:
	@echo "Available targets:"
	@echo "  lint          - Run all linters (Lua and Nix)"
	@echo "  lint-lua      - Run luacheck on Lua files"
	@echo "  lint-nix      - Run statix on Nix files"
	@echo "  format        - Run all formatters (Lua and Nix)"
	@echo "  format-lua    - Format Lua files with stylua"
	@echo "  format-nix    - Format Nix files with nixpkgs-fmt"
	@echo "  test          - Run all tests (lua, plenary, go)"
	@echo "  test-lua      - Run standalone Lua unit tests (test/*_test.lua)"
	@echo "  test-plenary  - Run PlenaryBustedDirectory tests"
	@echo "  test-go       - Run Go integration tests (from test/)"

lint: lint-lua lint-nix
	@echo "All linting complete"

lint-lua:
	@echo "Linting Lua files..."
	@if command -v luacheck >/dev/null 2>&1; then \
		luacheck lua/ ftplugin/ after/ftplugin/ --exclude-files "*/vendor/*" --globals vim; \
	else \
		echo "Warning: luacheck not found. Install with: luarocks install luacheck"; \
		exit 1; \
	fi

lint-nix:
	@echo "Linting Nix files..."
	@if command -v statix >/dev/null 2>&1; then \
		statix check nix/; \
	else \
		echo "Warning: statix not found. Install with: nix-env -iA nixpkgs.statix"; \
		exit 1; \
	fi

format: format-lua format-nix
	@echo "All formatting complete"

format-lua:
	@echo "Formatting Lua files..."
	@if command -v stylua >/dev/null 2>&1; then \
		stylua lua/ ftplugin/ after/ftplugin/ --glob '**/*.lua' --glob '!**/vendor/**'; \
	else \
		echo "Warning: stylua not found. Install with: cargo install stylua"; \
		exit 1; \
	fi

format-nix:
	@echo "Formatting Nix files..."
	@if command -v nixpkgs-fmt >/dev/null 2>&1; then \
		nixpkgs-fmt nix/; \
	else \
		echo "Warning: nixpkgs-fmt not found. Install with: nix-env -iA nixpkgs.nixpkgs-fmt"; \
		exit 1; \
	fi

test: test-lua test-plenary test-go
	@echo "All tests complete"

test-lua:
	@echo "Running standalone Lua tests..."
	@failed=0; \
	for f in test/*_test.lua; do \
		echo "--- $$f ---"; \
		if ! lua "$$f"; then failed=1; fi; \
	done; \
	if [ "$$failed" -ne 0 ]; then \
		echo "Some standalone Lua tests failed."; \
		exit 1; \
	fi

test-plenary:
	./tests/setup.sh
	nvim --headless -u tests/minimal_init.lua \
	  -c "PlenaryBustedDirectory tests/agent/ { minimal_init = 'tests/minimal_init.lua' }" \
	  -c "qa!"

test-go:
	@echo "Running Go tests..."
	@cd test && go test ./...
