local App = require("app")
App.new {
    name  = "disks",
    title = "LANE — Discos",
    width = 800, height = 500,
    build = function(srv, T)
        return require("tabs.disks").new(srv, T)
    end,
}:run()
