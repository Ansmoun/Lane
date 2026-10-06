local App = require("lib.app")
App.new {
    name  = "network",
    title = "LANE — Red",
    width = 800, height = 500,
    build = function(srv, T)
        return require("tabs.net").new(srv, T)
    end,
}:run()
