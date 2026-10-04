-- PanelApp: proceso que mantiene un Server vivo y crea/destruye
-- paneles on-demand.
--
-- Uso:
--     local app = PanelApp.new {
--         trigger_path = "/tmp/lane-panel.cmd",
--         panel_opts = { tabs = {...}, title = "..." },
--     }
--     app:run()
--
-- Cuando el usuario cierra el panel (q, Esc, boton X), el panel
-- se destruye. El proceso sigue vivo esperando un nuevo trigger.
--
-- Para disparar: escribe un archivo en trigger_path.
--     echo toggle > /tmp/lane-panel.cmd

local Server = require("lib.server")
local Panel  = require("panel")
local log    = require("lib.log")

local PanelApp = {}
PanelApp.__index = PanelApp

function PanelApp.new(opts)
    opts = opts or {}
    local self = setmetatable({}, PanelApp)
    self.opts = opts
    self.server = opts.server or Server.new {
        exit_on_empty = false,
    }
    self.panel_opts = opts.panel_opts or {}
    self.panel = nil
    self.trigger_path = opts.trigger_path

    if self.trigger_path then
        self.server:watch_trigger(self.trigger_path,
            function(cmd) self:_on_trigger(cmd) end)
        log.info("panelapp", "observando trigger en %s", self.trigger_path)
    end

    -- Si se pasa un theme, conectar rebuild. La idea: la tab de
    -- configuracion muta el theme y llama theme.rebuild() para que
    -- el panel se reconstruya con los nuevos colores.
    if opts.theme then
        self.theme = opts.theme
        self.theme.rebuild = function() self:rebuild() end
    end

    return self
end

-- Cierra el panel actual y lo reconstruye con el theme actual.
-- Los tabs se vuelven a construir desde cero (asi recogen los
-- colores frescos de theme).
function PanelApp:rebuild()
    if not self.panel then return end
    local active_id = self.panel.tabbed and self.panel.tabbed.active_id
    log.info("panelapp", "rebuild (activo=%s)", tostring(active_id))
    self.panel:close()
    self.panel = nil
    self:show()
    if active_id and self.panel then
        self.panel:set_tab(active_id)
    end
end

function PanelApp:_on_trigger(cmd)
    log.info("panelapp", "trigger: %s", cmd)
    if cmd == "toggle" then
        self:toggle()
    elseif cmd == "show" then
        self:show()
    elseif cmd == "hide" then
        self:hide()
    elseif cmd == "quit" then
        self:quit()
    else
        log.warn("panelapp", "comando desconocido: %s", cmd)
    end
end

function PanelApp:show()
    if self.panel then
        log.info("panelapp", "ya visible, ignorando show")
        return
    end
    log.info("panelapp", "creando panel")
    local opts = self.panel_opts
    -- Encadenar on_close para que ademas de destruir el panel,
    -- liberemos nuestra referencia.
    local user_on_close = opts.on_close
    local panel_opts = {}
    for k, v in pairs(opts) do panel_opts[k] = v end
    panel_opts.server = self.server
    panel_opts.on_close = function()
        if user_on_close then user_on_close() end
        self.panel = nil
        log.info("panelapp", "panel cerrado, proceso sigue vivo")
        collectgarbage("collect")
    end
    self.panel = Panel.new(panel_opts)
end

function PanelApp:hide()
    if not self.panel then return end
    log.info("panelapp", "cerrando panel (hide)")
    self.panel:close()
end

function PanelApp:toggle()
    if self.panel then
        self:hide()
    else
        self:show()
    end
end

function PanelApp:quit()
    log.info("panelapp", "quit")
    if self.panel then self.panel:close() end
    self.server:stop()
end

function PanelApp:run()
    self.server:run()
end

return PanelApp
