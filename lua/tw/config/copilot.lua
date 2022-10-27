vim.keymap.set("i", "<C-n>", "<Plug>(copilot-next)", { silent = true })
vim.keymap.set("i", "<C-p>", "<Plug>(copilot-previous)", { silent = true })

vim.g.copilot_no_tab_map = true
vim.keymap.set(
  "i",
  "<Plug>(vimrc:copilot-dummy-map)",
  'copilot#Accept("")',
  { silent = true, expr = true, desc = "Copilot dummy accept, needed for nvim-cmp" }
)
