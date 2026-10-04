-- app.lua: esqueleto comun de las apps one-shot del entorno.
--
-- Encapsula el patron que hoy esta copiado en cada apps/*.lua:
-- Server + Window + tab + Esc-cierra + rebuild-on-theme-change.
--
-- Uso:
--   local app = require("app").new {
--       name  = "config",
--       title = "LANE — Configuración",
--       width = 700, height = 560,
--       build = function(srv, T)
--           return require("tabs.config").new(srv, T)
--       end,
--       -- opcional: handler extra de teclado (se llama despues del
--       -- tab, antes del Esc)
--       on_key = function(key, win) ... return consumed end,
--   }
--   app:run()
--
-- Cuando se llama theme.reload_in_place en el mismo proceso, el
-- watcher que registra App.new dispara un rebuild: cierra la Window
-- actual y crea una nueva con el tab reconstruido. Los widgets
-- nuevos capturan los colores frescos.

local Server = require("lib.server")
local Window = require("lib.window")
local theme  = require("lib.theme")
local cairo  = require("lib.cairo")
local anim   = require("lib.anim")
local log    = require("lib.log")
local ewmh   = require("lib.ewmh")

local App = {}
App.__index = App

function App.new(opts)
    opts = opts or {}
    local self = setmetatable({}, App)
    self.opts = opts
    self.srv = Server.new({ exit_on_empty = false })
    self.theme = theme.load()
    anim.init(self.srv, { fps = 30 })

    self.win = nil
    self.tab = nil
    self._rebuilding = false
    self.ewmh = ewmh.new(self.srv)

    log.info(opts.name or "app", "paleta: %s", self.theme.path)

    -- Camino 1: SIGUSR1 recibido desde otro proceso. El callback
    -- recarga la paleta en ESTE proceso y reconstruye. Lo tienen
    -- todas las apps.
    local reload = require("lib.reload")
    reload.install(self.srv, function()
        log.info(opts.name or "app", "SIGUSR1: rebuild cross-process")
        theme.reload_in_place(self.theme)
        self:rebuild()
    end)

    -- Camino 2: theme.watch. Solo para apps que hacen reload_in_place
    -- por si mismas (config, cuando el usuario pulsa Aplicar). Con
    -- watch_theme = true, el mismo reload_in_place local dispara el
    -- rebuild. Sin esta opcion, el watcher no se registra.
    if opts.watch_theme then
        theme.watch(function()
            self:rebuild()
        end)
    end

    return self
end

function App:_build_window()
    if self.tab == nil then
        self.tab = self.opts.build(self.srv, self.theme)
    end

    local w = self.opts.width  or 700
    local h = self.opts.height or 560

    local win
    win = Window.new(self.srv, {
        kind = self.opts.kind or "normal",
        width = w, height = h,
        x = "center", y = "center",
        title = self.opts.title or "LANE",
        disable_q_close = true,
        on_draw = function(cr, cw, ch)
            local bg = self.theme.bg_rgb
            cairo.set_rgb(cr, bg[1], bg[2], bg[3])
            cairo.paint(cr)
        end,
        on_key = function(key)
            if self.tab and self.tab.on_key then
                if self.tab.on_key(key) then return end
            end
            if self.opts.on_key then
                if self.opts.on_key(key, win) then return end
            end
            if key.pressed and key.name == "Escape"
               and not key.mods.ctrl
               and not key.mods.alt
               and not key.mods.super then
                win:close("escape")
            end
        end,
        on_close = function()
            -- Distinguir cierre del usuario de cierre por rebuild.
            -- En rebuild, el timer de App:rebuild va a crear una
            -- ventana nueva en 50 ms. En cierre del usuario, hay que
            -- parar el server explicitamente (porque usamos
            -- exit_on_empty = false).
            if not self._rebuilding then
                self.srv:stop()
            end
        end,
    })

    win:set_root(self.tab.widget)
    if self.tab.start then self.tab.start() end
    self.win = win
end

function App:rebuild()
    if self._rebuilding then return end
    if not self.win or self.win.destroyed then return end
    self._rebuilding = true
    log.info(self.opts.name or "app", "rebuild in-place (sin cerrar ventana)")

    -- Detener el tab actual (cancela timers, etc).
    if self.tab and self.tab.stop then
        pcall(self.tab.stop)
    end
    self.tab = nil

    -- Reconstruir el arbol en el proximo tick. Sin esto, creariamos
    -- widgets nuevos desde dentro del propio callback del boton
    -- Aplicar (que vive en el arbol que se esta por reemplazar).
    local tm
    tm = self.srv:add_timer(20, function()
        tm:cancel()
        self._rebuilding = false
        if not self.srv.running then return end
        if not self.win or self.win.destroyed then return end

        -- Crear el tab nuevo con la paleta fresca.
        self.tab = self.opts.build(self.srv, self.theme)

        -- Reemplazar el root del arbol en la MISMA Window. El id X
        -- no cambia, X no dispara MapNotify, el WM no reubica la
        -- ventana. No hay teletransporte entre workspaces ni robo
        -- de foco.
        self.win:set_root(self.tab.widget)

        if self.tab.start then self.tab.start() end
    end)
end

function App:run()
    self:_build_window()
    self.srv:run()
    if self.tab and self.tab.stop then
        pcall(self.tab.stop)
    end
    log.info(self.opts.name or "app", "adios")
end

return App
