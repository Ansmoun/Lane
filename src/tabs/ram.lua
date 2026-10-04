-- Tab RAM: anillo + breakdown + modulos + swap + acciones.

local W = require("lib.widgets")
local G = require("lib.helpers.graphics")
local F = require("lib.helpers.format")
local D = require("lib.data.ram")
local cairo = require("lib.cairo")
local pango = require("lib.pango")

local M = {}

-- Widget inline: barra de swap con 2 segmentos (usado / libre).
local SwapBar = setmetatable({}, { __index = W.Text })
SwapBar.__index = SwapBar
function SwapBar.new(opts)
    local self = setmetatable(W.Text.new { text = "" }, SwapBar)
    self.used_color = opts.used_color
    self.free_color = opts.free_color
    self.data = { total = 0, used = 0 }
    self.min_w = 100
    self.min_h = 16
    return self
end
function SwapBar:set_data(total, used)
    self.data.total = total
    self.data.used  = used
    self:damage()
end
function SwapBar:draw(cr)
    local x, y = self.x0, self.y0
    local w, h = self:getWidth(), self:getHeight()
    local radius = h / 2
    local total = self.data.total
    local used  = self.data.used
    local pct   = total > 0 and (used / total) or 0

    -- Fondo (libre) con clip al rect para que las esquinas no se
    -- salgan si el widget es mas angosto que 2*radius.
    cairo.save(cr)
    cairo.rectangle(cr, x, y, w, h)
    cairo.clip(cr)

    local fc = self.free_color
    cairo.set_rgb(cr, fc[1], fc[2], fc[3])
    cairo.rounded_rect(cr, x, y, w, h, radius)
    cairo.fill(cr)

    if pct > 0 then
        local uc = self.used_color
        cairo.set_rgb(cr, uc[1], uc[2], uc[3])
        local uw = w * pct
        if uw < h then uw = h end
        if uw > w then uw = w end
        cairo.rounded_rect(cr, x, y, uw, h, radius)
        cairo.fill(cr)
    end

    cairo.restore(cr)
end

-- Boton pequeno para +- swappiness.
local function make_swp_btn(text, size)
    return W.Button.new {
        text = text,
        padding_x = 8,
        padding_y = 3,
        corner_radius = 4,
        font = "DejaVu Sans Bold 12",
        color_normal  = { 0.20, 0.20, 0.24 },
        color_hover   = { 0.30, 0.30, 0.36 },
        color_pressed = { 0.14, 0.14, 0.18 },
        min_width = size or 24,
        min_height = 22,
    }
end

function M.new(srv, theme)
    local G_ = require("lib.helpers.graphics")
    local ram_hex = theme.telemetry.ram or "#83a598"
    local r_r, r_g, r_b = G_.hex_to_rgba(ram_hex)

    local swappiness = D.swappiness()
    local st = { swap_total = 0, swap_used = 0 }

    -- Anillo
    local ring = W.Ring.new {
        text = "0%", sub = "",
        color = { r_r, r_g, r_b },
        raw_range = { 0, 100 },
        size = 150, thickness = 12,
    }

    -- Breakdown (barra apilada + leyenda)
    local breakdown = W.BarMulti.new {
        bar_height = 16,
        legend_cols = 3,
        legend_font = "DejaVu Sans 9",
        legend_color = { 0.75, 0.75, 0.80 },
        segments = {
            { id = "used",    color = ram_hex,             label = "En uso" },
            { id = "cached",  color = theme.telemetry.gpu or "#d3869b",
              label = "Caché" },
            { id = "free",    color = theme.separator,     label = "Libre" },
            { id = "buffers", color = theme.telemetry.battery or "#b8bb26",
              label = "Buffers" },
            { id = "srecl",   color = theme.accent,        label = "Reclaim" },
            { id = "shmem",   color = theme.usage_warn,    label = "Compartida" },
        },
    }

    -- Modulos fisicos (texto multilinea con markup)
    local mods_text = W.Text.new {
        text = "",
        font = "DejaVu Sans 9",
        valign = "top",
        align = "left",
        wrap = true,
    }
    local mods_card = W.Card.new {
        title = "Módulos",
        content = mods_text,
        padding = 10,
        bg = theme.bg_card_rgb,
        border = theme.separator_rgb,
        min_height = 80,
    }

    -- Swap
    local ur, ug, ub = G_.hex_to_rgba(theme.telemetry.battery or "#b8bb26")
    local fr, fg, fb = G_.hex_to_rgba(theme.separator)
    local swap_bar = SwapBar.new {
        used_color = { ur, ug, ub },
        free_color = { fr, fg, fb },
    }
    local swap_text = W.Text.new {
        text = "",
        font = "DejaVu Sans 9",
        valign = "center",
        align = "left",
    }

    local swp_val = W.Text.new {
        text = tostring(swappiness),
        font = "DejaVu Sans Bold 11",
        r = 0.90, g = 0.90, b = 0.90,
        align = "center",
        valign = "center",
    }
    local swp_minus = make_swp_btn("−", 22)
    local swp_plus  = make_swp_btn("+", 22)

    swp_minus.opts.on_click = function()
        local new = math.max(0, math.min(100, swappiness - 5))
        swappiness = D.set_swappiness(new)
        swp_val:set_text(tostring(swappiness))
    end
    swp_plus.opts.on_click = function()
        local new = math.max(0, math.min(100, swappiness + 5))
        swappiness = D.set_swappiness(new)
        swp_val:set_text(tostring(swappiness))
    end

    local swp_label = W.Text.new {
        text = "swappiness",
        font = "DejaVu Sans 9",
        r = 0.55, g = 0.55, b = 0.60,
        align = "left", valign = "center",
    }

    local swp_row = W.Group.new {
        orientation = "horizontal",
        spacing = 6,
        children = {
            { widget = swp_label, weight = 1 },
            { widget = swp_minus, weight = 0 },
            { widget = swp_val,   weight = 0 },
            { widget = swp_plus,  weight = 0 },
        },
    }

    local swap_inner = W.Group.new {
        orientation = "vertical",
        spacing = 8,
        children = {
            { widget = swap_bar,  weight = 0 },
            { widget = swap_text, weight = 0 },
            { widget = swp_row,   weight = 0 },
        },
    }
    local swap_card = W.Card.new {
        title = "Swap",
        content = swap_inner,
        padding = 10,
        bg = theme.bg_card_rgb,
        border = theme.separator_rgb,
    }

    -- Acciones
    local actions = W.Actions.new {
        button_width = 190,
        actions = {
            { label = "Drop caches",
              cmd = "sync; echo 3 | sudo -n tee /proc/sys/vm/drop_caches > /dev/null",
              ok_msg = "Caches liberadas" },
            { label = "Compactar memoria",
              cmd = "echo 1 | sudo -n tee /proc/sys/vm/compact_memory > /dev/null",
              ok_msg = "Memoria compactada" },
            { label = "Liberar swap",
              cmd = "sudo -n swapoff -a && sudo -n swapon -a",
              ok_msg = "Swap liberada" },
        },
    }
    local actions_card = W.Card.new {
        title = "Acciones",
        content = actions,
        padding = 10,
        bg = theme.bg_card_rgb,
        border = theme.separator_rgb,
    }

    -- Top: ring + breakdown
    local top = W.Group.new {
        orientation = "horizontal", spacing = 10,
        children = {
            { widget = W.Card.new { title = "RAM", content = ring,
                                    padding = 10,
                                    bg = theme.bg_card_rgb,
                                    border = theme.separator_rgb },
              weight = 0 },
            { widget = W.Card.new { title = "Breakdown", content = breakdown,
                                    padding = 10,
                                    bg = theme.bg_card_rgb,
                                    border = theme.separator_rgb },
              weight = 1 },
        },
    }

    -- Bottom: modulos + swap + acciones
    local bottom = W.Group.new {
        orientation = "horizontal", spacing = 10,
        children = {
            { widget = mods_card,    weight = 1 },
            { widget = swap_card,    weight = 1 },
            { widget = actions_card, weight = 1 },
        },
    }

    local layout = W.Group.new {
        orientation = "vertical", spacing = 10,
        children = {
            { widget = top,    weight = 1 },
            { widget = bottom, weight = 1 },
        },
    }

    local function refresh_modules()
        local modules = D.modules()
        if not modules then
            mods_text:set_markup(string.format(
                '<span foreground="%s">dmidecode sin output. Verifica sudoers.</span>',
                theme.muted))
            return
        end
        local parts = {}
        for _, m in ipairs(modules) do
            local l1 = string.format(
                '<span foreground="%s" weight="bold">%s</span> <span foreground="%s">%s @ %s</span>',
                theme.accent, m.size or "?",
                theme.fg_normal, m.type or "?", m.speed or "?")
            local extras = {}
            if m.manuf and m.manuf ~= "?" and m.manuf ~= "" and m.manuf ~= "Unknown" then
                table.insert(extras, m.manuf)
            end
            if m.part and m.part ~= "?" and m.part ~= "" and m.part ~= "Unknown"
               and not m.part:match("^%[Empty") then
                table.insert(extras, "Part " .. m.part)
            end
            local l2 = ""
            if #extras > 0 then
                l2 = '\n<span foreground="' .. theme.muted .. '">' ..
                     table.concat(extras, " · ") .. '</span>'
            end
            table.insert(parts, l1 .. l2)
        end
        mods_text:set_markup(table.concat(parts, "\n\n"))
    end

    local function refresh()
        local s = D.sample()

        ring:set_value(s.pct * 100,
            string.format("%d%%", math.floor(s.pct * 100)),
            F.mb(s.used) .. " / " .. F.mb(s.total))

        local used_real = math.max(0,
            s.total - s.free - s.cached - s.srecl - s.buffers)
        local function frac(kb) return s.total > 0 and kb / s.total or 0 end

        local used_color = ram_hex
        if s.pct > 0.8 then used_color = theme.usage_crit
        elseif s.pct > 0.5 then used_color = theme.usage_warn end

        breakdown:set({
            { id = "used",    pct = frac(used_real), color = used_color,
              value_str = F.mb(used_real) },
            { id = "cached",  pct = frac(s.cached),
              value_str = F.mb(s.cached) },
            { id = "free",    pct = frac(s.free),
              value_str = F.mb(s.free) },
            { id = "buffers", pct = frac(s.buffers),
              value_str = F.mb(s.buffers) },
            { id = "srecl",   pct = frac(s.srecl),
              value_str = F.mb(s.srecl) },
            { id = "shmem",   pct = 0,
              value_str = F.mb(s.shmem) },
        })

        st.swap_total = s.swap_total
        st.swap_used  = s.swap_used
        swap_bar:set_data(s.swap_total, s.swap_used)

        if s.swap_total > 0 then
            swap_text:set_markup(string.format(
                '<span foreground="%s">%s</span> <span foreground="%s">/ %s</span>',
                theme.fg_normal, F.mb(s.swap_used),
                theme.muted,     F.mb(s.swap_total)))
        else
            swap_text:set_markup('<span foreground="' .. theme.muted ..
                '">Sin swap configurada</span>')
        end
    end

    local timer

    return {
        widget = layout,
        start = function()
            refresh_modules()
            refresh()
            timer = srv:add_timer(2000, refresh)
        end,
        stop = function()
            if timer then timer:cancel(); timer = nil end
        end,
    }
end

return M
