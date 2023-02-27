local M = {}

local function configureDapUI()
  local breakpoint = {
    text = "",
    texthl = "LspDiagnosticsSignError",
    linehl = "",
    numhl = "",
  }

  local breakpoint_rejected = {
    text = "",
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
            size = 0.75, -- Can be float or integer > 1
          },
          { id = "breakpoints", size = 0.25 },
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
      R = { "<cmd>lua require'dap'.run_to_cursor()<cr>", "Run to Cursor" },
      E = { "<cmd>lua require'dapui'.eval(vim.fn.input '[Expression] > ', { enter = true})<cr>", "Evaluate Input" },
      C = {
        "<cmd>lua require'dap'.set_breakpoint(vim.fn.input '[Condition] > ')<cr>",
        "Conditional Breakpoint",
      },
      U = { "<cmd>lua require'dapui'.toggle()<cr>", "Toggle UI" },
      b = { "<cmd>lua require'dap'.step_back()<cr>", "Step Back" },
      c = { "<cmd>lua require'dap'.continue()<cr>", "Continue" },
      e = { "<cmd>lua require'dapui'.eval(nil, {enter = true})<cr>", "Evaluate" },
      g = { "<cmd>lua require'dap'.session()<cr>", "Get Session" },
      h = { "<cmd>lua require'dap.ui.widgets'.hover()<cr>", "Hover Variables" },
      S = { "<cmd>lua require'dap.ui.widgets'.scopes()<cr>", "Scopes" },
      i = { "<cmd>lua require'dap'.step_into()<cr>", "Step Into" },
      o = { "<cmd>lua require'dap'.step_over()<cr>", "Step Over" },
      p = { "<cmd>lua require'dap'.pause.toggle()<cr>", "Pause" },
      q = { "<cmd>lua require'dap'.close()<cr>", "Quit" },
      r = { "<cmd>lua require'dap'.repl.toggle()<cr>", "Toggle Repl" },
      s = { "<cmd>lua require'dap'.continue()<cr>", "Start" },
      t = { "<cmd>lua require'dap'.toggle_breakpoint()<cr>", "Toggle Breakpoint" },
      x = { "<cmd>lua require'dap'.disconnect()<cr>", "Disconnect" },
      X = { "<cmd>lua require'dap'.terminate()<cr>", "Terminate" },
      u = { "<cmd>lua require'dap'.step_out()<cr>", "Step Out" },
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
