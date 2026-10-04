-- Panel: ventana con un TabbedPanel dentro. Toda la logica de
-- tabs y lazy loading vive en TabbedPanel. Este modulo solo crea
-- la ventana, el fondo, y gestiona Esc.
--
-- Animaciones: si conf.lua tiene animate_panel = "true", el
-- TabbedPanel hace crossfade al cambiar de tab. La tasa en Hz se
-- lee de anim_hz y la duración del fade de anim_duration. El motor
-- de animaciones se inicializa aquí si aún no lo está.

local Window = require("lib.window")
local W      = require("lib.widgets")
local cairo  = require("lib.cairo")
local log    = require("lib.log")
local D      = require("lib.data.config")

local Panel = {}
Panel.__index = Panel

function Panel.new(opts)
    opts = opts or {}
    local self = setmetatable({}, Panel)
    self.opts = opts
    self.theme = opts.theme

    if opts.bg then
        self.bg = opts.bg
    elseif opts.theme and opts.theme.bg_rgb then
        self.bg = opts.theme.bg_rgb
    else
        self.bg = { 0.10, 0.10, 0.13 }
    end

    -- Leer preferencias de animación. opts.* tiene prioridad sobre
    -- conf.lua (útil para tests). Si nada está definido, default:
    -- animación apagada, 30 Hz, 300 ms.
    local animate_panel = opts.animate_panel
    if animate_panel == nil then
        animate_panel = D.get_bool("animate_panel", false)
    end
    local anim_hz = opts.anim_hz
    if anim_hz == nil then
        anim_hz = D.get_int("anim_hz", 30)
    end
    local anim_duration = opts.anim_duration
    if anim_duration == nil then
        anim_duration = D.get_int("anim_duration", 300)
    end
    -- animate_tabs controla SOLO el crossfade entre tabs. Si
    -- animate_panel es true pero animate_tabs es false, el motor
    -- se inicializa (los tabs pueden animar sus widgets) pero
    -- el TabbedPanel no hace crossfade al cambiar de tab.
    local animate_tabs = opts.animate_tabs
    if animate_tabs == nil then
        animate_tabs = D.get_bool("animate_tabs", true)
    end
    if not animate_panel then animate_tabs = false end

    -- Inicializar el motor de animaciones si hace falta. Solo se
    -- inicializa una vez; anim.is_ready() lo confirma.
    local srv = opts.server
    if srv and animate_panel then
        local anim = require("lib.anim")
        if not anim.is_ready() then
            anim.init(srv, { fps = anim_hz })
        else
            anim.set_fps(anim_hz)
        end
    end

    self.tabbed = W.TabbedPanel.new {
        tabs           = opts.tabs or {},
        spacing        = opts.spacing or 6,
        theme          = opts.theme,
        anim           = animate_tabs,
        anim_fps       = anim_hz,
        anim_duration  = anim_duration,
    }

    local outer = W.Group.new {
        orientation = "vertical",
        padding = opts.padding or 8,
        spacing = 0,
        children = { self.tabbed },
    }
    self.outer = outer

    local win_opts = {
        kind          = opts.kind or "normal",
        parent_window = opts.parent_window,
        title         = opts.title or "Panel",
        width         = opts.width or "80%",
        height        = opts.height or "80%",
        x             = opts.x or "center",
        y             = opts.y or "center",
        disable_q_close = true,
        on_draw = function(cr, w, h)
            cairo.set_rgb(cr, self.bg[1], self.bg[2], self.bg[3])
            cairo.paint(cr)
        end,
        on_key = function(key)
            if key.pressed and key.name == "Escape"
               and not key.mods.ctrl and not key.mods.alt
               and not key.mods.super then
                if not self.window.focus_widget then
                    self.window:close("escape")
                end
            end
        end,
        on_close = function()
            if self.tabbed.active_id then
                self.tabbed:_stop_active()
            end
            if opts.on_close then opts.on_close() end
        end,
    }

    if opts.server then
        self.window = Window.new(opts.server, win_opts)
    else
        self.window = Window.new(win_opts)
    end

    self.window:set_root(outer)

    if opts.tabs and opts.tabs[1] then
        self.tabbed:set_tab(opts.tabs[1].id)
    end

    return self
end

function Panel:set_tab(id)  self.tabbed:set_tab(id) end
function Panel:get_tab(id)  return self.tabbed:get_tab(id) end
function Panel:get_window() return self.window end
function Panel:close()      self.window:close("panel") end
function Panel:run()        self.window:run() end

return Panel
