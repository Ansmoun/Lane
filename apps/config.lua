-- Configuración de LANE: apariencia, entorno, atajos.
-- watch_theme = true para que reload_in_place local dispare el
-- rebuild del arbol (config aplica cambios de paleta en si mismo).

local App = require("lib.app")

App.new {
    name  = "config",
    title = "LANE — Configuración",
    width = 700, height = 620,
    watch_theme = true,
    build = function(srv, T)
        return require("tabs.config").new(srv, T)
    end,
}:run()
