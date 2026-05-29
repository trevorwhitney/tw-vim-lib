-- Minimal init for headless test runs. Adds plenary and this plugin to runtimepath.
local repo_root = vim.fn.getcwd()
vim.opt.runtimepath:prepend(repo_root)
vim.opt.runtimepath:prepend(repo_root .. "/tests/.deps/plenary.nvim")

-- Add lua directory to package.path for module loading
package.path = repo_root .. "/?.lua;" .. repo_root .. "/?/init.lua;" .. repo_root .. "/lua/?.lua;" .. repo_root .. "/lua/?/init.lua;" .. package.path

vim.cmd("runtime plugin/plenary.vim")
