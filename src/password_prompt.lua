-- password_prompt: ventana hija X11 con un TextInput, para pedir
-- texto (contraseñas, rutas, nombres).
--
-- Uso:
--   local P = require("password_prompt")
--   local prompt = P.new(srv, parent_win, theme)
--   prompt:show {
--       title = "Contraseña",
--       mask = true,
--       on_submit = function(text) ... end,
--       on_cancel = function() ... end,
--   }

local Window = require("lib.window")
local W      = require("lib.widgets")
local cairo  = require("lib.cairo")

local M = {}

local Prompt = {}
Prompt.__index = Prompt

function M.new(srv, parent_win, theme)
    local self = setmetatable({}, Prompt)
    self.srv = srv
    self.parent_win = parent_win
    self.theme = theme
    self.win = nil
    self.input = nil
    return self
end

function Prompt:show(opts)
    opts = opts or {}
    if self.win and not self.win.destroyed then
        self.win:close("reenvio")
        self.win = nil
    end

    local T = self.theme

    local title = W.Text.new {
        markup = true,
        text = string.format('<span foreground="%s" weight="bold">%s</span>',
            T.fg_normal or "#ebdbb2", opts.title or "Entrada"),
        font = "DejaVu Sans Bold 12",
        align = "center",
        valign = "center",
    }

    local input = W.TextInput.new {
        text = "",
        font = "DejaVu Sans 12",
        padding_x = 10,
        padding_y = 6,
        mask = opts.mask ~= false,
        color_bg = T.bg_card,
        color_border = T.accent,
        corner_radius = 4,
        on_submit = function(text)
            self:close()
            if opts.on_submit then opts.on_submit(text) end
        end,
        on_cancel = function()
            self:close()
            if opts.on_cancel then opts.on_cancel() end
        end,
    }
    self.input = input

    local hint = W.Text.new {
        text = "Enter para aceptar · Esc para cancelar",
        font = "DejaVu Sans 9",
        r = 0.55, g = 0.55, b = 0.60,
        align = "center",
        valign = "center",
    }

    local content = W.Group.new {
        orientation = "vertical",
        spacing = 12,
        padding = 20,
        children = { title, input, hint },
    }

    local w, h = 400, 130
    local scr = self.parent_win.server.screen
    local x = math.floor((scr.width_in_pixels - w) / 2)
    local y = math.floor((scr.height_in_pixels - h) / 2)

    local popup = Window.new(self.srv, {
        parent_window = self.parent_win,
        kind = "child",
        width = w, height = h,
        x = x, y = y,
        on_draw = function(cr, cw, ch)
            cairo.set_rgb(cr, 0.13, 0.13, 0.17)
            cairo.paint(cr)
            cairo.set_rgb(cr, 0.40, 0.40, 0.50)
            cairo.set_line_width(cr, 2)
            cairo.rectangle(cr, 1, 1, cw - 2, ch - 2)
            cairo.stroke(cr)
        end,
        on_key = function(key) input:on_key(key) end,
        on_close = function()
            if opts.on_cancel then opts.on_cancel() end
        end,
    })
    popup:set_root(content)
    popup:set_input_focus()
    input:set_focused(true)
    input.window = popup

    self.win = popup
end

function Prompt:close()
    if self.win and not self.win.destroyed then
        self.win:close("prompt cerrado")
    end
    self.win = nil
    self.input = nil
end

return M
