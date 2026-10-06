local App = require("lib.app")
App.new {
    name  = "sysmon",
    title = "LANE — Monitor de recursos",
    width = 900, height = 560,
    build = function(srv, T)
        return require("tabs.resources").new(srv, T)
    end,
}:run()
