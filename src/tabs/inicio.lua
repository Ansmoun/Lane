-- Tab Inicio: portada del panel. Avatar circular + identidad +
-- cards Sistema/Sesión + reloj.

local W = require("lib.widgets")
local F = require("lib.helpers.format")
local cairo = require("lib.cairo")
local pango = require("lib.pango")
local G = require("lib.helpers.graphics")
local D = require("lib.data.inicio")

local M = {}

-- ── Avatar circular ────────────────────────────────────────────
local Avatar = setmetatable({}, { __index = W.Text })
Avatar.__index = Avatar

function Avatar.new(opts)
    local self = setmetatable(W.Text.new { text = "" }, Avatar)
    self.size = opts.size or 140
    self.initial = opts.initial or "?"
    self.accent_rgb = opts.accent_rgb or { 0.5, 0.7, 0.9 }
    self.bg_rgb = opts.bg_rgb or { 0.1, 0.1, 0.15 }
    self.border_rgb = opts.border_rgb or { 0.3, 0.3, 0.4 }
    self.surface = nil
    self.min_w = self.size
    self.min_h = self.size
    self.max_w = self.size
    self.max_h = self.size

    if opts.path then
        local s, err = cairo.load_png(opts.path)
        if s then self.surface = s end
    end

    return self
end

function Avatar:set_path(path)
    if self.surface then
        cairo.destroy_surface(self.surface)
        self.surface = nil
    end
    if path then
        local s = cairo.load_png(path)
        if s then self.surface = s end
    end
    self:damage()
end

function Avatar:draw(cr)
    local s = self.size
    local cx = self.x0 + s / 2
    local cy = self.y0 + s / 2
    local r = s / 2 - 2

    -- Anillo exterior
    cairo.set_rgb(cr, self.accent_rgb[1], self.accent_rgb[2], self.accent_rgb[3])
    cairo.arc(cr, cx, cy, r + 1, 0, 2 * math.pi)
    cairo.fill(cr)

    -- Circulo interior (recorte)
    cairo.save(cr)
    cairo.arc(cr, cx, cy, r - 1, 0, 2 * math.pi)
    cairo.clip(cr)

    if self.surface then
        -- Dibujar imagen recortada al circulo, centrada, cubriendo el area.
        local nw = cairo.surface_width(self.surface)
        local nh = cairo.surface_height(self.surface)
        if nw > 0 and nh > 0 then
            local target = (r - 1) * 2
            local scale = math.max(target / nw, target / nh)
            local dw = nw * scale
            local dh = nh * scale
            local dx = cx - dw / 2
            local dy = cy - dh / 2
            cairo.draw_surface(cr, self.surface, dx, dy, dw, dh)
        end
    else
        -- Fondo + inicial
        cairo.set_rgb(cr, self.bg_rgb[1], self.bg_rgb[2], self.bg_rgb[3])
        cairo.rectangle(cr, cx - r, cy - r, 2 * r, 2 * r)
        cairo.fill(cr)

        local initial = self.initial:sub(1, 1):upper()
        local r1, g1, b1 = G.hex_to_rgba("#ebdbb2")
        local iw, ih = pango.measure(initial, "DejaVu Sans Bold 60")
        pango.draw_text(cr, cx - iw/2, cy - ih/2, initial,
            "DejaVu Sans Bold 60", { r = r1, g = g1, b = b1 })
    end

    cairo.restore(cr)
end

-- ── Tab ────────────────────────────────────────────────────────
function M.new(srv, theme)
    -- Avatar
    local avatar_path = D.find_avatar()
    local initial = D.user():sub(1, 1)
    local avatar = Avatar.new {
        size = 130,
        initial = initial,
        path = avatar_path,
        accent_rgb = theme.accent_rgb,
        bg_rgb = theme.bg_card_rgb,
    }
    local avatar_centered = W.Group.new {
        orientation = "horizontal",
        children = {
            { widget = W.Text.new { text = "" }, weight = 1 },
            { widget = avatar, weight = 0 },
            { widget = W.Text.new { text = "" }, weight = 1 },
        },
    }

    -- Identidad
    local greet = W.Text.new {
        text = F.greeting(),
        font = "DejaVu Sans 10",
        align = "center", valign = "center",
        r = 0.85, g = 0.85, b = 0.90,
    }
    local user_host = W.Text.new {
        markup = string.format(
            '<span foreground="%s" weight="bold">%s@%s</span>',
            theme.accent or "#8ec07c", D.user(), D.host()),
        font = "DejaVu Sans Bold 14",
        align = "center", valign = "center",
    }
    local distro = W.Text.new {
        text = D.distro(),
        font = "DejaVu Sans 10",
        align = "center", valign = "center",
        r = 0.55, g = 0.55, b = 0.60,
    }

    local identity = W.Group.new {
        orientation = "vertical", spacing = 4,
        children = { greet, user_host, distro },
    }

    -- ── Card Sistema ──────────────────────────────────────────
    local sys_kernel  = W.Text.new { text = "-", font = "DejaVu Sans Mono 10",
        align = "right", valign = "center", r = 0.90, g = 0.90, b = 0.90 }
    local sys_uptime  = W.Text.new { text = "-", font = "DejaVu Sans Mono 10",
        align = "right", valign = "center", r = 0.90, g = 0.90, b = 0.90 }
    local sys_screens = W.Text.new { text = "-", font = "DejaVu Sans Mono 10",
        align = "right", valign = "center", r = 0.90, g = 0.90, b = 0.90 }
    local sys_ip      = W.Text.new { text = "-", font = "DejaVu Sans Mono 10",
        align = "right", valign = "center", r = 0.90, g = 0.90, b = 0.90 }

    local function kv_row(label, value_widget)
        local l = W.Text.new {
            text = label, font = "DejaVu Sans 10",
            r = 0.55, g = 0.55, b = 0.60,
            align = "left", valign = "center",
        }
        return W.Group.new {
            orientation = "horizontal",
            children = {
                { widget = l,             weight = 1 },
                { widget = value_widget,  weight = 0 },
            },
        }
    end

    local sistema_inner = W.Group.new {
        orientation = "vertical", spacing = 5,
        children = {
            kv_row("Kernel",   sys_kernel),
            kv_row("Uptime",   sys_uptime),
            kv_row("Pantallas", sys_screens),
            kv_row("IP local", sys_ip),
        },
    }
    local sistema_card = W.Card.new {
        title = "Sistema",
        content = sistema_inner,
        padding = 12,
        bg = theme.bg_card_rgb,
        border = theme.separator_rgb,
    }

    -- ── Card Sesión ───────────────────────────────────────────
    local ses_wm       = W.Text.new { text = "-", font = "DejaVu Sans Mono 10",
        align = "right", valign = "center", r = 0.90, g = 0.90, b = 0.90 }
    local ses_display  = W.Text.new { text = "-", font = "DejaVu Sans Mono 10",
        align = "right", valign = "center", r = 0.90, g = 0.90, b = 0.90 }
    local ses_terminal = W.Text.new { text = "-", font = "DejaVu Sans Mono 10",
        align = "right", valign = "center", r = 0.90, g = 0.90, b = 0.90 }
    local ses_shell    = W.Text.new { text = "-", font = "DejaVu Sans Mono 10",
        align = "right", valign = "center", r = 0.90, g = 0.90, b = 0.90 }

    local sesion_inner = W.Group.new {
        orientation = "vertical", spacing = 5,
        children = {
            kv_row("WM",       ses_wm),
            kv_row("Display",  ses_display),
            kv_row("Terminal", ses_terminal),
            kv_row("Shell",    ses_shell),
        },
    }
    local sesion_card = W.Card.new {
        title = "Sesión",
        content = sesion_inner,
        padding = 12,
        bg = theme.bg_card_rgb,
        border = theme.separator_rgb,
    }

    local cards_row = W.Group.new {
        orientation = "horizontal", spacing = 12,
        children = {
            { widget = sistema_card, weight = 1 },
            { widget = sesion_card,  weight = 1 },
        },
    }

    -- ── Reloj ─────────────────────────────────────────────────
    local date_lbl = W.Text.new {
        text = F.date(),
        font = "DejaVu Sans 10",
        r = 0.55, g = 0.55, b = 0.60,
        align = "center", valign = "center",
    }
    local time_lbl = W.Text.new {
        text = "",
        font = "DejaVu Sans Bold 28",
        align = "center", valign = "center",
    }

    local clock = W.Group.new {
        orientation = "vertical", spacing = 2,
        children = { date_lbl, time_lbl },
    }

    -- ── Layout ────────────────────────────────────────────────
    local layout = W.Group.new {
        orientation = "vertical", spacing = 14, padding = 16,
        children = {
            { widget = avatar_centered, weight = 0 },
            { widget = identity,        weight = 0 },
            { widget = cards_row,       weight = 0 },
            { widget = clock,           weight = 1 },
        },
    }

    -- ── Refresh ───────────────────────────────────────────────
    local function refresh_static()
        sys_kernel:set_text(D.kernel())
        sys_screens:set_text(tostring(D.screens()))
        ses_wm:set_text("Awesome 4.3")
        ses_display:set_text("X11")
        ses_terminal:set_text("terminology")
        ses_shell:set_text(D.shell_name())
    end

    -- Timer rapido: SOLO el reloj. Nada de IO.
    local function refresh_clock()
        local t = os.date("*t")
        local hh = t.hour
        local mm = t.min
        local ss = t.sec
        local accent = theme.accent or "#8ec07c"
        time_lbl:set_markup(string.format(
            '<span foreground="%s" weight="bold">%02d:%02d</span>' ..
            '<span foreground="%s">:%02d</span>',
            theme.fg_normal or "#ebdbb2", hh, mm, accent, ss))
    end

    -- Timer lento: uptime, IP, fecha. Popen de ip route va aqui,
    -- no en el timer de 1s.
    local function refresh_slow()
        sys_uptime:set_text(F.uptime(D.uptime_secs()))
        sys_ip:set_text(D.ip_local())
        date_lbl:set_text(F.date())
    end

    local t_fast, t_slow

    return {
        widget = layout,
        start = function()
            refresh_static()
            refresh_slow()
            refresh_clock()
            t_fast = srv:add_timer(1000, refresh_clock)
            t_slow = srv:add_timer(30000, function()
                refresh_slow()
            end)
        end,
        stop = function()
            if t_fast then t_fast:cancel(); t_fast = nil end
            if t_slow then t_slow:cancel(); t_slow = nil end
        end,
    }
end

return M
