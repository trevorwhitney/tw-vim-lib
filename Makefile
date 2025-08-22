.PHONY: help docker lint lint-lua lint-nix format format-lua format-nix

help:
	@echo "Available targets:"
	@echo "  docker     - Build the Claude Docker image"
	@echo "  lint       - Run all linters (Lua and Nix)"
	@echo "  lint-lua   - Run luacheck on Lua files"
	@echo "  lint-nix   - Run statix on Nix files"
	@echo "  format     - Run all formatters (Lua and Nix)"
	@echo "  format-lua - Format Lua files with stylua"
	@echo "  format-nix - Format Nix files with nixpkgs-fmt"

docker:
	docker build -t tw-claude-code:latest -f lua/tw/claude/docker/Dockerfile lua/tw/claude/docker

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
