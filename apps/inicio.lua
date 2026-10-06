local App = require("lib.app")
App.new {
    name  = "inicio",
    title = "LANE — Inicio",
    width = 700, height = 560,
    build = function(srv, T)
        return require("tabs.inicio").new(srv, T)
    end,
}:run()
