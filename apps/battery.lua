local App = require("app")
App.new {
    name  = "battery",
    title = "LANE — Batería",
    width = 500, height = 560,
    build = function(srv, T)
        return require("tabs.bat").new(srv, T)
    end,
}:run()
