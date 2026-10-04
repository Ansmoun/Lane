local App = require("app")
App.new {
    name  = "search",
    title = "LANE — Buscar archivos",
    width = 900, height = 600,
    build = function(srv, T)
        return require("tabs.search").new(srv, T)
    end,
}:run()
