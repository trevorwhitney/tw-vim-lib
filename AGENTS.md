# Repository Guidelines

## Project Structure & Module Organization
- Core Lua sources live under `lua/`, grouped by feature (`lua/tw/claude`, `lua/tw/formatting`, etc.). Neovim runtime hooks are in `after/`, `ftplugin/`, and `plugin/`.
- Docker assets for the Claude and Codex environments reside in `lua/tw/claude/docker/`.
- Nix definitions live in `nix/`, while reusable prompts and templates are in `prompts/`.
- Go-based integration tests sit in `test/`; vendored helpers are isolated within `test/vendor/`.

## Build, Test, and Development Commands
- `make docker` builds the development container image using `lua/tw/claude/docker/Dockerfile`.
- `make lint` (or the granular `make lint-lua` / `make lint-nix`) runs `luacheck` and `statix` to catch style and configuration issues.
- `make format` formats Lua and Nix files via `stylua` and `nixpkgs-fmt`.
- `go test ./...` (run from the `test/` directory) executes the Go integration suite; use `go test ./... -run Test_Name` to target a specific case.

## Coding Style & Naming Conventions
- Run `make format` before committing; the repo relies on `stylua` defaults (4-space indentation, double-quoted strings) and `nixpkgs-fmt`.
- Lua modules follow `lua/tw/<feature>/<file>.lua` naming; expose public entry points via `return M` tables.
- Keep Neovim keymap leaders consistent (`<leader>c?`) and prefer descriptive function names over abbreviations.
- `luacheck` enforces globals; declare shared globals (e.g., `vim`) in the checker config or scope them locally.

## Testing Guidelines
- Group Go tests under a descriptive parent `t.Run` block (see `test/test_test.go`) and name functions using `Test_FooBar` style for readability in output.
- Strive for deterministic tests; avoid external network or filesystem side effects unless hardened with fixtures.
- When adding Lua modules that require validation, either extend the Go suite or add lightweight Lua-based checks that run under the same `make lint` workflow.

## Commit & Pull Request Guidelines
- Follow the existing conventional-style prefixes observed in history (`feat:`, `fix:`, `chore:`, `docs:`). Example: `feat: add codex buffer cleanup`.
- Each pull request should describe the change, outline validation (e.g., `make lint`, `go test ./...`), and link to related issues or discussions.
- Provide screenshots or terminal snippets when altering user-facing behavior (new keymaps, UI panes, Docker flags) to aid reviewers.
- Squash commits if the history contains fixups; otherwise keep logical chunks that map to reviewable units.
