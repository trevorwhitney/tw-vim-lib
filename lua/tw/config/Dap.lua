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

  vim.cmd('command! -nargs=0 DapToggleConsole lua require("dapui").open(2)')

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
          "console",
        },
        size = 15,
        position = "bottom",
      },
    },
    floating = {
      max_height = 0.6,  -- These can be integers or a float between 0 and 1.
      max_width = 0.8,   -- Floats will be treated as percentage of your screen.
      border = "single", -- Border style. Can be "single", "double" or "rounded"
      mappings = {
        close = { "q", "<Esc>" },
      },
    },
  })
end

local function configureKeyamp()
  local wk = require("which-key")

  local keymap = {
    { "<leader>d",  group = "Debug",                                                                     nowait = false,                  remap = false },
    -- a, A, d, D, and m are reserved for languages specific actions
    { "<leader>dB", "<cmd>Telescope dap list_breakpoints<cr>",                                           desc = "List Breakpoints",       nowait = false, remap = false },
    { "<leader>dC", "<cmd>lua require'dap'.clear_breakpoints()<cr>",                                     desc = "Clear Breakpoints",      nowait = false, remap = false },
    { "<leader>dE", "<cmd>lua require'dapui'.eval(vim.fn.input '[Expression] > ', { enter = true})<cr>", desc = "Evaluate Input",         nowait = false, remap = false },
    { "<leader>dF", "<cmd>Telescope dap frames<cr>",                                                     desc = "List Frames",            nowait = false, remap = false },
    { "<leader>dO", "<cmd>lua require'dapui'.toggle(2)<cr>",                                             desc = "Toggle Console",         nowait = false, remap = false },
    { "<leader>dR", "<cmd>lua require'dap'.run_to_cursor()<cr>",                                         desc = "Run to Cursor",          nowait = false, remap = false },
    { "<leader>dS", "<cmd>lua require'dap.ui.widgets'.scopes()<cr>",                                     desc = "Scopes",                 nowait = false, remap = false },
    { "<leader>dT", "<cmd>lua require'dap'.set_breakpoint(vim.fn.input '[Condition] > ')<cr>",           desc = "Conditional Breakpoint", nowait = false, remap = false },
    { "<leader>dU", "<cmd>lua require'dapui'.toggle()<cr>",                                              desc = "Toggle UI",              nowait = false, remap = false },
    { "<leader>dX", "<cmd>lua require'dap'.terminate()<cr>",                                             desc = "Terminate",              nowait = false, remap = false },
    { "<leader>db", "<cmd>lua require'dap'.step_back()<cr>",                                             desc = "Step Back",              nowait = false, remap = false },
    { "<leader>dc", "<cmd>lua require'dap'.continue()<cr>",                                              desc = "Continue",               nowait = false, remap = false },
    { "<leader>dd", "<cmd>lua require'dap'.continue()<cr>",                                              desc = "Debug",                  nowait = false, remap = false },
    { "<leader>de", "<cmd>lua require'dapui'.eval(nil, {enter = true})<cr>",                             desc = "Evaluate",               nowait = false, remap = false },
    { "<leader>dg", "<cmd>lua require'dap'.session()<cr>",                                               desc = "Get Session",            nowait = false, remap = false },
    { "<leader>dh", "<cmd>lua require'dap.ui.widgets'.hover()<cr>",                                      desc = "Hover Variables",        nowait = false, remap = false },
    { "<leader>di", "<cmd>lua require'dap'.step_into()<cr>",                                             desc = "Step Into",              nowait = false, remap = false },
    { "<leader>dl", "<cmd>lua require'dap'.run_last()<cr>",                                              desc = "Run Last",               nowait = false, remap = false },
    { "<leader>do", "<cmd>lua require'dap'.step_over()<cr>",                                             desc = "Step Over",              nowait = false, remap = false },
    { "<leader>dp", "<cmd>lua require'dap'.pause.toggle()<cr>",                                          desc = "Pause",                  nowait = false, remap = false },
    { "<leader>dq", "<cmd>lua require'dap'.close()<cr>",                                                 desc = "Quit",                   nowait = false, remap = false },
    { "<leader>dr", "<cmd>lua require'dap'.repl.toggle()<cr>",                                           desc = "Toggle Repl",            nowait = false, remap = false },
    { "<leader>dt", "<cmd>lua require'dap'.toggle_breakpoint()<cr>",                                     desc = "Toggle Breakpoint",      nowait = false, remap = false },
    { "<leader>du", "<cmd>lua require'dap'.step_out()<cr>",                                              desc = "Step Out",               nowait = false, remap = false },
    { "<leader>dx", "<cmd>lua require'dap'.disconnect()<cr>",                                            desc = "Disconnect",             nowait = false, remap = false },
  }

  wk.add(keymap)
end

local function configureAutoComplete()
  vim.cmd([[
    au FileType dap-repl lua require('dap.ext.autocompl').attach()
  ]])
end

local function additionalAdapters()
  require("dap-vscode-js").setup({
    node_path = "node",                                                                        -- Path of node executable. Defaults to $NODE_PATH, and then "node"
    debugger_path = vim.env.HOME .. "/.local/share/nvim/site/pack/packer/opt/vscode-js-debug", -- Path to vscode-js-debug installation.
    adapters = { "pwa-node" },                                                                 -- which adapters to register in nvim-dap
    -- log_file_path = vim.env.HOME .. "/dap_vscode_js.log", -- Path for file logging
    -- log_file_level = vim.log.levels.DEBUG, -- Logging level for output to file. Set to false to disable file logging.
    -- log_console_level = vim.log.levels.DEBUG -- Logging level for output to console. Set to false to disable console output.
  })

  for _, language in ipairs({ "typescript", "javascript" }) do
    require("dap").configurations[language] = {
      {
        type = "pwa-node",
        request = "launch",
        name = "Launch file",
        program = "${file}",
        cwd = "${workspaceFolder}",
      },
      {
        type = "pwa-node",
        request = "attach",
        name = "Attach",
        processId = require("dap.utils").pick_process,
        cwd = "${workspaceFolder}",
      },
      {
        console = "integratedTerminal",
        cwd = "${workspaceFolder}",
        internalConsoleOptions = "neverOpen",
        name = "Debug Jest Tests",
        request = "launch",
        rootPath = "${workspaceFolder}",
        runtimeExecutable = "node",
        type = "pwa-node",
        runtimeArgs = {
          "./node_modules/jest/bin/jest.js",
          "--runInBand",
        },
      },
    }
  end
end

function M.setup()
  require("dap-go").setup({
    delve = {
      detatched = false,
      args = {
        "--log",
        "--log-output=dap,debugger"
      }
    }
  })
  -- Uncomment to change log level
  require("dap").set_log_level("TRACE")
  configureDapUI()
  configureKeyamp()
  configureAutoComplete()
  additionalAdapters()
end

return M
