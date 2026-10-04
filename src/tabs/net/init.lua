local W = require("lib.widgets")
local D = require("lib.data.config")

local M = {}

function M.new(srv, theme)
    local tabs = {
        { id = "conexion", label = "Conexión", icon = "wifi",
          factory = function()
              return require("tabs.net.conexion").new(srv, theme)
          end },
        { id = "registro", label = "Registro", icon = "book",
          factory = function()
              return require("tabs.net.registro").new(srv, theme)
          end },
        { id = "redes", label = "Redes", icon = "signal",
          factory = function()
              return require("tabs.net.redes").new(srv, theme)
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
