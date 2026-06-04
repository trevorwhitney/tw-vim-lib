-- luacheck configuration for tw-vim-lib
--
-- `vim` is the global Neovim API table; it is always available in plugin code.
globals = { "vim" }

-- Third-party vendored Go-test helpers live under test/vendor and are not Lua
-- sources we control; never lint them.
exclude_files = { "**/vendor/**" }

-- Several modules embed long shell one-liners and telescope command strings
-- that must stay on a single line to remain correct/readable. stylua already
-- enforces formatting, so we don't additionally fail lint on line length.
max_line_length = false

-- Treat an underscore prefix as an explicit "intentionally unused" marker for
-- locals and functions (luacheck already does this for arguments). This lets
-- us keep self-documenting names for unused positional captures and
-- deliberately-disabled helpers without tripping the unused checks.
ignore = { "21./^_", "211/^_" }
