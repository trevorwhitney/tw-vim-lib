local M = {}

local function configureDapUI()
  local breakpoint = {
    text = "",
    texthl = "LspDiagnosticsSignError",
    linehl = "",
    numhl = "",
  }

  local breakpoint_rejected = {
    text = "",
    texthl = "LspDiagnosticsSignHint",
    linehl = "",
    numhl = "",
  }

  local dap_stopped = {
    text = "",
    texthl = "LspDiagnosticsSignInformation",
    linehl = "DiagnosticUnderlineInfo",
    numhl = "LspDiagnosticsSignInformation",
  }

  vim.fn.sign_define("DapBreakpoint", breakpoint)
  vim.fn.sign_define("DapBreakpointRejected", breakpoint_rejected)
  vim.fn.sign_define("DapStopped", dap_stopped)

  require("dapui").setup({
    layouts = {
      {
        elements = {
          -- Provide as ID strings or tables with "id" and "size" keys
          {
            id = "scopes",
            size = 0.40, -- Can be float or integer > 1
          },
          {
            id = "stacks",
            size = 0.40, -- Can be float or integer > 1
          },
          { id = "breakpoints", size = 0.20 },
        },
        size = 40,
        position = "left",
      },
      {
        elements = {
          "repl",
          -- "console",
        },
        size = 15,
        position = "bottom",
      },
    },
    floating = {
      max_height = 0.6, -- These can be integers or a float between 0 and 1.
      max_width = 0.8, -- Floats will be treated as percentage of your screen.
      border = "single", -- Border style. Can be "single", "double" or "rounded"
      mappings = {
        close = { "q", "<Esc>" },
      },
    },
  })
end

local function configureKeyamp()
  local keymap = {
    d = {
      name = "Debug",
      B = { "<cmd>Telescope dap list_breakpoints<cr>", "List Breakpoints" },
      C = {
        "<cmd>lua require'dap'.set_breakpoint(vim.fn.input '[Condition] > ')<cr>",
        "Conditional Breakpoint",
      },
      E = {
        "<cmd>lua require'dapui'.eval(vim.fn.input '[Expression] > ', { enter = true})<cr>",
        "Evaluate Input",
      },
      F = { "<cmd>Telescope dap frames<cr>", "List Frames" },
      R = { "<cmd>lua require'dap'.run_to_cursor()<cr>", "Run to Cursor" },
      S = { "<cmd>lua require'dap.ui.widgets'.scopes()<cr>", "Scopes" },
      T = { "<cmd>lua require'dap'.clear_breakpoints()<cr>", "Clear Breakpoints" },
      U = { "<cmd>lua require'dapui'.toggle()<cr>", "Toggle UI" },
      X = { "<cmd>lua require'dap'.terminate()<cr>", "Terminate" },

      b = { "<cmd>lua require'dap'.step_back()<cr>", "Step Back" },
      c = { "<cmd>lua require'dap'.continue()<cr>", "Continue" },
      e = { "<cmd>lua require'dapui'.eval(nil, {enter = true})<cr>", "Evaluate" },
      g = { "<cmd>lua require'dap'.session()<cr>", "Get Session" },
      h = { "<cmd>lua require'dap.ui.widgets'.hover()<cr>", "Hover Variables" },
      i = { "<cmd>lua require'dap'.step_into()<cr>", "Step Into" },
      l = { "<cmd>lua require'dap'.run_last()<cr>", "Run Last" },
      o = { "<cmd>lua require'dap'.step_over()<cr>", "Step Over" },
      p = { "<cmd>lua require'dap'.pause.toggle()<cr>", "Pause" },
      q = { "<cmd>lua require'dap'.close()<cr>", "Quit" },
      r = { "<cmd>lua require'dap'.repl.toggle()<cr>", "Toggle Repl" },
      s = { "<cmd>lua require'dap'.continue()<cr>", "Start" },
      t = { "<cmd>lua require'dap'.toggle_breakpoint()<cr>", "Toggle Breakpoint" },
      u = { "<cmd>lua require'dap'.step_out()<cr>", "Step Out" },
      x = { "<cmd>lua require'dap'.disconnect()<cr>", "Disconnect" },
    },
  }

  local which_key = require("which-key")

  which_key.register(keymap, {
    mode = "n",
    prefix = "<leader>",
    buffer = nil,
    silent = true,
    noremap = true,
    nowait = false,
  })

  local keymap_v = {
    name = "Debug",
    e = { "<cmd>lua require'dapui'.eval()<cr>", "Evaluate" },
  }
  which_key.register(keymap_v, {
    mode = "v",
    prefix = "<leader>",
    buffer = nil,
    silent = true,
    noremap = true,
    nowait = false,
  })
end

local function configureAutoComplete()
  vim.cmd([[
    au FileType dap-repl lua require('dap.ext.autocompl').attach()
  ]])
end

function M.setup()
  configureDapUI()
  configureKeyamp()
  configureAutoComplete()

  -- Uncomment to change log level
  -- require("dap").set_log_level("DEBUG")
end

return M
