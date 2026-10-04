-- Tab Discos: particiones + SMART + hardware.

local W = require("lib.widgets")
local cairo = require("lib.cairo")
local G = require("lib.helpers.graphics")
local D = require("lib.data.disk")

local M = {}

local function fmt_hours(h)
    local d = math.floor(h / 24)
    if d >= 365 then
        local y = math.floor(d / 365)
        return string.format("%d h  (%d años %d días)",
            math.floor(h), y, d - y * 365)
    end
    return string.format("%d h  (%d días)", math.floor(h), d)
end

local function fmt_tb(lbas)
    return string.format("%.2f TB", lbas * 512 / (1024 ^ 4))
end

local function fmt_gb(b)
    if b >= 1024 * 1024 * 1024 then
        return string.format("%.0f GB", b / (1024 ^ 3))
    end
    return string.format("%.0f MB", b / (1024 ^ 2))
end

-- Card de una particion: construida ad-hoc, se reescribe su contenido
-- cuando cambia.
local function make_part_content(theme)
    local title = W.Text.new {
        text = "", font = "DejaVu Sans Bold 11",
        align = "center", valign = "center",
        r = 1, g = 1, b = 1,
    }
    local mount_lbl = W.Text.new {
        text = "", font = "DejaVu Sans 9",
        align = "left", valign = "center",
    }
    local dev_lbl = W.Text.new {
        text = "", font = "DejaVu Sans 9",
        align = "left", valign = "center",
        r = 0.55, g = 0.55, b = 0.60,
    }
    local fs_lbl = W.Text.new {
        text = "", font = "DejaVu Sans Bold 9",
        align = "right", valign = "center",
    }
    local pct_lbl = W.Text.new {
        text = "", font = "DejaVu Sans Bold 11",
        align = "center", valign = "center",
    }
    local used_lbl = W.Text.new {
        text = "", font = "DejaVu Sans 9",
        align = "center", valign = "center",
        r = 0.55, g = 0.55, b = 0.60,
    }
    local avail_lbl = W.Text.new {
        text = "", font = "DejaVu Sans 9",
        align = "center", valign = "center",
        r = 0.55, g = 0.55, b = 0.60,
    }

    -- Barra de progreso custom
    local Bar = setmetatable({}, { __index = W.Text })
    Bar.__index = Bar
    function Bar.new(pct)
        local self = setmetatable(W.Text.new { text = "" }, Bar)
        self.pct = pct or 0
        self.min_h = 8
        self.min_w = 80
        return self
    end
    function Bar:set_pct(p) self.pct = p; self:damage() end
    function Bar:draw(cr)
        local x, y = self.x0, self.y0
        local w, h = self:getWidth(), self:getHeight()
        local radius = h / 2
        local G_ = require("lib.helpers.graphics")
        cairo.set_rgb(cr, 0.30, 0.30, 0.34)
        cairo.rounded_rect(cr, x, y, w, h, radius)
        cairo.fill(cr)
        if self.pct > 0 then
            local fw = w * math.min(1, self.pct)
            local col = self.color or { 0.55, 0.85, 0.60 }
            cairo.set_rgb(cr, col[1], col[2], col[3])
            cairo.rounded_rect(cr, x, y, fw, h, math.min(radius, fw/2))
            cairo.fill(cr)
        end
    end

    local bar = Bar.new(0)

    local info_row = W.Group.new {
        orientation = "horizontal", spacing = 6,
        children = {
            { widget = mount_lbl, weight = 1 },
            { widget = dev_lbl, weight = 1 },
            { widget = fs_lbl, weight = 0 },
        },
    }

    local content = W.Group.new {
        orientation = "vertical", spacing = 4,
        children = {
            title, info_row, bar, pct_lbl, avail_lbl,
        },
    }

    return {
        content = content,
        update = function(d, theme)
            title:set_text(d.label ~= "" and d.label or d.mount)
            title.r = theme.accent_rgb[1]
            title.g = theme.accent_rgb[2]
            title.b = theme.accent_rgb[3]
            mount_lbl:set_text("  " .. d.mount)
            dev_lbl:set_text((d.dev or ""):gsub("^/dev/", ""))
            fs_lbl:set_text(d.fs_type or "?")
            fs_lbl.r = theme.fg_normal_rgb and theme.fg_normal_rgb[1] or 0.9
            fs_lbl.g = theme.fg_normal_rgb and theme.fg_normal_rgb[2] or 0.9
            fs_lbl.b = theme.fg_normal_rgb and theme.fg_normal_rgb[3] or 0.9
            bar:set_pct(d.pct / 100)
            pct_lbl:set_text(string.format("%d%%  ·  %s / %s",
                d.pct, d.used, d.size))
            avail_lbl:set_text(d.avail .. " libres")
        end,
    }
end

function M.new(srv, theme)
    -- Barra de particiones (arriba): una card por particion.
    local parts_row = W.Group.new {
        orientation = "horizontal",
        spacing = 10,
        children = {},
    }
    local part_holders = {}   -- array de { content, card }

    -- KV SMART
    local smart = W.KV.new {
        key_width = 110, row_height = 15, row_spacing = 4,
        key_color = { 0.55, 0.55, 0.60 },
        value_color = { 0.90, 0.90, 0.90 },
        rows = {
            { id = "temp",    label = "Temperatura" },
            { id = "hours",   label = "Horas encendidas" },
            { id = "cycles",  label = "Ciclos de encendido" },
            { id = "realloc", label = "Sectores reasignados" },
            { id = "pending", label = "Sectores pendientes" },
            { id = "offline", label = "Sectores offline" },
            { id = "crc",     label = "Errores UDMA CRC" },
            { id = "load",    label = "Ciclos de carga" },
            { id = "written", label = "Total escrito" },
            { id = "read",    label = "Total leído" },
        },
    }
    local smart_card = W.Card.new {
        title = "SMART",
        content = smart,
        padding = 10,
        bg = theme.bg_card_rgb,
        border = theme.separator_rgb,
        min_height = 180,
    }

    -- KV Hardware
    local hw = W.KV.new {
        key_width = 110, row_height = 15, row_spacing = 4,
        rows = {
            { id = "model",  label = "Modelo" },
            { id = "family", label = "Familia" },
            { id = "serial", label = "Número de serie" },
            { id = "firm",   label = "Firmware" },
            { id = "cap",    label = "Capacidad" },
            { id = "sector", label = "Sectores" },
            { id = "phys",   label = "Físico" },
            { id = "link",   label = "Interfaz" },
        },
    }
    local hw_card = W.Card.new {
        title = "Hardware",
        content = hw,
        padding = 10,
        bg = theme.bg_card_rgb,
        border = theme.separator_rgb,
        min_height = 180,
    }

    -- Contenedor de particiones con titulo
    local parts_card = W.Card.new {
        title = "Particiones",
        content = parts_row,
        padding = 10,
        bg = theme.bg_card_rgb,
        border = theme.separator_rgb,
        min_height = 130,
    }

    local mid = W.Group.new {
        orientation = "horizontal", spacing = 10,
        children = {
            { widget = smart_card, weight = 1 },
            { widget = hw_card,    weight = 1 },
        },
    }

    local layout = W.Group.new {
        orientation = "vertical", spacing = 10,
        children = {
            { widget = parts_card, weight = 0 },
            { widget = mid,        weight = 1 },
        },
    }

    -- Limpiar y repoblar particiones
    local function rebuild_parts(list)
        require("lib.log").info("disks", "rebuild_parts: %d particiones", #list)
        parts_row:clear()
        part_holders = {}

        if #list == 0 then
            local empty = W.Text.new {
                text = "Sin particiones montadas",
                font = "DejaVu Sans 10",
                align = "center",
                r = 0.55, g = 0.55, b = 0.60,
            }
            parts_row:add(empty)
            return
        end

        for _, d in ipairs(list) do
            local pc = make_part_content(theme)
            pc.update(d, theme)
            local card = W.Card.new {
                title = nil,
                content = pc.content,
                padding = 10,
                bg = theme.bg_card_rgb,
                border = theme.separator_rgb,
            }
            parts_row:add(card)
            part_holders[#part_holders + 1] = { content = pc, card = card }
        end

        -- CRITICO: las cards recien añadidas no tienen rect hasta
        -- que el arbol se relayoute. Sin esta llamada, quedan en
        -- 0x0 y Group:draw no las pinta (bug: desaparecen a los 10s).
        parts_row:invalidate_layout()
    end

    -- Refresh
    local function refresh_parts()
        local p = D.partitions()
        require("lib.log").info("disks", "refresh_parts: %d", #p)
        rebuild_parts(p)
    end

    local function refresh_smart()
        local s = D.smart_read()
        if not s then
            smart_card:set_title("Salud SMART  ·  (sin datos)")
            return
        end
        if s.passed then
            smart_card:set_title(string.format(
                '<span foreground="%s">Salud SMART</span>  ·  ' ..
                '<span foreground="%s" weight="bold">PASSED</span>',
                theme.muted, theme.telemetry.cpu or theme.accent))
        else
            smart_card:set_title(string.format(
                '<span foreground="%s">Salud SMART</span>  ·  ' ..
                '<span foreground="%s" weight="bold">FALLANDO</span>',
                theme.muted, theme.usage_crit))
        end

        smart:set("temp",    string.format("%d °C", math.floor(s.temp)))
        smart:set("hours",   fmt_hours(s.hours))
        smart:set("cycles",  string.format("%d", math.floor(s.cycles)))
        smart:set("realloc", s.realloc)
        smart:set("pending", s.pending)
        smart:set("offline", s.offline)
        smart:set("crc",     s.crc)
        smart:set("load",    s.load_cycles)
        smart:set("written", fmt_tb(s.lba_written))
        smart:set("read",    fmt_tb(s.lba_read))

        hw:set("model",  s.model_name)
        hw:set("family", s.model_family)
        hw:set("serial", s.serial)
        hw:set("firm",   s.firmware)
        hw:set("cap",    fmt_gb(s.cap_bytes))
        hw:set("sector", string.format("%d B / %d B",
            math.floor(s.sec_logical), math.floor(s.sec_physical)))
        hw:set("phys",   string.format("%d rpm  ·  %s",
            math.floor(s.rotation), s.form_factor))
        hw:set("link",   string.format("%s  ·  %s",
            s.sata_version, s.sata_link))
    end

    local t_fast, t_slow

    return {
        widget = layout,
        start = function()
            refresh_parts()
            D.smart_trigger("/dev/sda")
            refresh_smart()
            t_fast = srv:add_timer(10000, refresh_parts)
            t_slow = srv:add_timer(60000, function()
                D.smart_trigger("/dev/sda")
                refresh_smart()
            end)
        end,
        stop = function()
            if t_fast then t_fast:cancel(); t_fast = nil end
            if t_slow then t_slow:cancel(); t_slow = nil end
        end,
    }
end

return M
