-- heavily inspired by/adapted from https://github.com/joshuavial/aider.nvim
local M = {}

local Path = require("plenary.path")
local Utils = require("avante.utils")

local defaultArgs = {
  "--architect",
  "--cache-prompts",
  "--code-theme", "solarized-light",
  "--light-mode",
  "--model", "anthropic/claude-3-5-sonnet-20241022",
  "--vim",
  "--watch-files",
}

M.aider_buf = nil
M.aider_job_id = nil

local function open_vsplit_window()
  vim.api.nvim_command("vnew")
end

local function open_hsplit_window()
  vim.api.nvim_command("new")
end

local function open_editor_relative_window()
  local buf = vim.api.nvim_create_buf(false, true)
  local width = vim.api.nvim_get_option("columns")
  local height = vim.api.nvim_get_option("lines")
  local win = vim.api.nvim_open_win(
    buf,
    true,
    { relative = "editor", width = width - 10, height = height - 10, row = 2, col = 2 }
  )
  vim.api.nvim_set_current_win(win)
end

local function open_window(window_type)
  if window_type == "vsplit" then
    open_vsplit_window()
  elseif window_type == "hsplit" then
    open_hsplit_window()
  else
    open_editor_relative_window()
  end
end

local function open_buffer_in_new_window(window_type, aider_buf)
  if window_type == "vsplit" then
    vim.api.nvim_command("vsplit | buffer " .. aider_buf)
  elseif window_type == "hsplit" then
    vim.api.nvim_command("split | buffer " .. aider_buf)
  else
    vim.api.nvim_command("buffer " .. aider_buf)
  end
end

local function OnExit(job_id, exit_code, event_type)
  vim.schedule(function()
    if M.aider_buf and vim.api.nvim_buf_is_valid(M.aider_buf) then
      vim.api.nvim_buf_set_option(M.aider_buf, "modifiable", true)
      local message
      if exit_code == 0 then
        message = "Aider process completed successfully."
      else
        message = "Aider process exited with code: " .. exit_code
      end
      vim.api.nvim_buf_set_lines(M.aider_buf, -1, -1, false, { "", message })
      vim.api.nvim_buf_set_option(M.aider_buf, "modifiable", false)
    end
  end)
end

function M.Open(args, window_type)
  args = args or defaultArgs
  window_type = window_type or "vsplit"
  if M.aider_buf and vim.api.nvim_buf_is_valid(M.aider_buf) then
    open_buffer_in_new_window(window_type, M.aider_buf)
  else
    local command = "aider " .. table.concat(args, " ")
    open_window(window_type)
    M.aider_buf = vim.api.nvim_get_current_buf()
    M.aider_job_id = vim.fn.termopen(command, { on_exit = OnExit })
    vim.bo[M.aider_buf].bufhidden = "hide"
    vim.bo[M.aider_buf].filetype = "AiderConsole"
    vim.cmd('startinsert')
  end
end

---@return nil
function M.AddQuickfixFiles()
  local quickfix_files = vim
      .iter(vim.fn.getqflist({ items = 0 }).items)
      :filter(function(item) return item.bufnr ~= 0 end)
      :map(function(item) return Utils.relative_path(vim.api.nvim_buf_get_name(item.bufnr)) end)
      :totable()

  local unique_paths = {}
  for _, filepath in ipairs(quickfix_files) do
    if not filepath or filepath == "" then return end

    local absolute_path = Path:new(Utils.get_project_root()):joinpath(filepath):absolute()
    local stat = vim.loop.fs_stat(absolute_path)

    if stat and stat.type == "file" then
      local uniform_path = Utils.uniform_path(filepath)
      if not vim.tbl_contains(unique_paths, uniform_path) then
        table.insert(unique_paths, uniform_path)
      end
    end
  end

  M.Send({ "/add", table.concat(unique_paths, " ") })
end

function M.Send(args)
  if not M.aider_buf or not vim.api.nvim_buf_is_valid(M.aider_buf) then
    M.Open()

    -- Wait a bit for the Aider chat to initialize
    vim.defer_fn(function()
      M.Send(args)
    end, 1000)
    return
  end

  vim.fn.chansend(M.aider_job_id, table.concat(args, " ") .. "\n")
end

function M.VimTestStrategy(cmd)
  M.Send({ "/run", cmd })
end

local function configureAiderKeymap()
  local aider = require("tw.aider")

  local keymap = {
    { "<leader>c", group = "AI Code Assistant", nowait = true, remap = false },
    {
      mode = { "n", "v" },
      { "<leader>ca", function() aider.Open() end, desc = "Open Aider" },
      {
        "<leader>cf",
        function()
          local filename = vim.fn.expand("%")
          local rel_path = Path:new(filename):make_relative(Utils.get_project_root())
          aider.Send({ "/add", rel_path })
        end,
        desc = "Aider Add File"
      },
      { "<leader>cq", function() aider.AddQuickfixFiles() end, desc = "Aider Add Quickfix Files" },
    },
    {
      mode = { "n" },
      { "<leader>ta", ":w<cr> :TestNearest -strategy=aider<cr>", desc = "Test Nearest (Aider)", nowait = false, remap = false },
    }
  }

  local wk = require("which-key")
  wk.add(keymap)
end

local function configureTerminalKeymap()
  local keymap = vim.keymap
  keymap.set("t", "jj", "<C-\\><C-n>", { noremap = true })
  keymap.set("t", "<Esc>", "<C-\\><C-n>", { noremap = true })
end

function M.setup()
  configureAiderKeymap()
  configureTerminalKeymap()
end

return M
