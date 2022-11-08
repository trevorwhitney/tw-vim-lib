local M = {}

function M.setup()
  local db = require("dashboard")

  db.custom_header = {
    " ███╗   ██╗ ███████╗ ██████╗  ██╗   ██╗ ██╗ ███╗   ███╗",
    " ████╗  ██║ ██╔════╝██╔═══██╗ ██║   ██║ ██║ ████╗ ████║",
    " ██╔██╗ ██║ █████╗  ██║   ██║ ██║   ██║ ██║ ██╔████╔██║",
    " ██║╚██╗██║ ██╔══╝  ██║   ██║ ╚██╗ ██╔╝ ██║ ██║╚██╔╝██║",
    " ██║ ╚████║ ███████╗╚██████╔╝  ╚████╔╝  ██║ ██║ ╚═╝ ██║",
    " ╚═╝  ╚═══╝ ╚══════╝ ╚═════╝    ╚═══╝   ╚═╝ ╚═╝     ╚═╝",
    "                                                       ",
  }

  db.custom_center = {
    { icon = " ", desc = "Find Buffer               ", shortcut = "SPC f b ", action = "Telescope buffers" },
    {
      icon = " ", desc = "Find file                 ",
      shortcut = "SPC f f ",
      action = "Telescope git_files",
    },
    { icon = " ", desc = "Recently opened files     ", shortcut = "SPC f o ", action = "Telescope oldfiles" },
    { icon = " ", desc = "Find word                 ", shortcut = "SPC f g ", action = "" },
    { icon = " ", desc = "Open last session         ", shortcut = "SPC s l ", action = "SessionLoad" },
    { icon = " ", desc = "New file                  ", shortcut = "SPC c n ", action = "DashboardNewFilw" },
  }
end

return M
