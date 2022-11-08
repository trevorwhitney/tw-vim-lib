local M = {}

function M.setup()
  require("which-key").setup({
    window = {
      border = "single",
    },
  })
end

return M
