local W = require("lib.widgets")
local D = require("lib.data.config")

local M = {}

function M.new(srv, theme)
    local tabs = {
        { id = "general", label = "General", icon = "dashboard",
          factory = function()
              return require("tabs.general").new(srv, theme)
          end },
        { id = "cpu", label = "CPU", icon = "chip",
          factory = function()
              return require("tabs.cpu").new(srv, theme)
          end },
        { id = "ram", label = "RAM", icon = "memory",
          factory = function()
              return require("tabs.ram").new(srv, theme)
          end },
        { id = "gpu", label = "GPU", icon = "gpu",
          factory = function()
              return require("tabs.gpu").new(srv, theme)
          end },
    }

    local A = D.get_anim_opts()

    local tabbed = W.TabbedPanel.new {
        tabs          = tabs,
        theme         = theme,
        compact       = true,
        anim          = A.tabs,
        anim_fps      = A.hz,
        anim_duration = A.duration,
    }
    return {
        widget = tabbed,
        start = function() end,
        stop  = function() tabbed:stop() end,
    }
end

return M
