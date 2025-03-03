# CLAUDE.md - Guidelines for tw-vim-lib

## Commands
- Test: `vim-test` for test runner integration (`<leader>tt` in files, `<leader>tn` for nearest)
- Lint: Language-specific linters configured (eslint_d, markdownlint, shellcheck)
- Format: `<leader>=` (current buffer) or `<leader>+` (modified Git lines)
- Go-specific: `GoTest`, `GoTestFunc`, `GoCoverage`, `GoBuild`

## Code Style
- **Naming**: snake_case for functions/variables, PascalCase for modules/tables
- **Imports**: Local vars for required modules at top, short aliases for common ones
- **Organization**: Module pattern with local table `local M = {}` and `return M` at end
- **Functions**: Public as `M.function_name`, private as `local function_name`
- **Documentation**: Comments for function blocks, TODOs clearly marked
- **Formatting**: 2-space indentation, trailing commas in tables
- **Error Handling**: Early returns, conditional validity checks

## File Structure
- `/lua/tw/`: Core functionality modules
- `/lua/tw/languages/`: Language-specific configurations
- `/autoload/tw/`: VimScript utility functions
- `/ftplugin/`: Filetype-specific settings
- `/after/ftplugin/`: Additional filetype overrides