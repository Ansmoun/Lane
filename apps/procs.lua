local App = require("app")
App.new {
    name  = "procs",
    title = "LANE — Procesos",
    width = 900, height = 600,
    build = function(srv, T)
        return require("tabs.proc").new(srv, T)
    end,
}:run()
