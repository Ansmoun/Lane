-- Tab Batería: telemetría de sysfs.

local W = require("lib.widgets")
local G = require("lib.helpers.graphics")
local D = require("lib.data.bat")

local M = {}

local function fmt_time(hours)
    if not hours or hours <= 0 or hours > 999 then return "-" end
    local h = math.floor(hours)
    local m = math.floor((hours - h) * 60)
    if h > 0 then return string.format("%dh %02dm", h, m) end
    return string.format("%dm", m)
end

function M.new(srv, theme)
    if not D.available() then
        local msg = W.Text.new {
            text = "Sin batería detectada",
            font = "DejaVu Sans 14",
            r = 0.55, g = 0.55, b = 0.60,
            align = "center",
        }
        return { widget = msg }
    end

    local history = G.history(60)
    local br, bg, bb = G.hex_to_rgba(theme.telemetry and theme.telemetry.battery
                                     or theme.accent)

    local ring = W.Ring.new {
        text = "0%", sub = "---",
        color = { br, bg, bb },
        raw_range = { 0, 100 },
        size = 150, thickness = 12,
    }

    local spark = W.Spark.new {
        samples = 60, min = 0, max = 100,
        color = theme.telemetry and theme.telemetry.battery or theme.accent,
        fill = true,
        axis_width = 32, axis_format = "%d%%",
        grid = true,
        min_width = 200, min_height = 100,
    }

    local hw_kv = W.KV.new {
        key_width = 90, row_height = 16, row_spacing = 5,
        key_color = { 0.55, 0.55, 0.60 },
        value_color = { 0.90, 0.90, 0.90 },
        rows = {
            { id = "model",  label = "Modelo" },
            { id = "vendor", label = "Fabric." },
            { id = "serial", label = "Serial" },
            { id = "tech",   label = "Tecnología" },
            { id = "vmin",   label = "V. mínimo" },
            { id = "vnow",   label = "V. actual" },
        },
    }
    local hw_card = W.Card.new {
        title = "Hardware", content = hw_kv, padding = 10,
        bg = theme.bg_card_rgb, border = theme.separator_rgb,
    }

    local st_kv = W.KV.new {
        key_width = 90, row_height = 16, row_spacing = 5,
        rows = {
            { id = "status",  label = "Estado" },
            { id = "time",    label = "Tiempo" },
            { id = "power",   label = "Consumo" },
            { id = "current", label = "Corriente" },
        },
    }
    local st_card = W.Card.new {
        title = "Estado", content = st_kv, padding = 10,
        bg = theme.bg_card_rgb, border = theme.separator_rgb,
    }

    local sa_kv = W.KV.new {
        key_width = 100, row_height = 16, row_spacing = 5,
        rows = {
            { id = "cycles", label = "Ciclos" },
            { id = "health", label = "Salud" },
            { id = "full",   label = "Cap. actual" },
            { id = "design", label = "Cap. diseño" },
        },
    }
    local sa_card = W.Card.new {
        title = "Salud", content = sa_kv, padding = 10,
        bg = theme.bg_card_rgb, border = theme.separator_rgb,
    }

    local spark_card = W.Card.new {
        title = "Historia (10 min)", content = spark, padding = 10,
        bg = theme.bg_card_rgb, border = theme.separator_rgb,
    }

    local top = W.Group.new {
        orientation = "horizontal", spacing = 10,
        children = {
            { widget = W.Card.new {
                title = "Batería", content = ring, padding = 10,
                bg = theme.bg_card_rgb, border = theme.separator_rgb,
              }, weight = 0 },
            { widget = hw_card, weight = 1 },
            { widget = st_card, weight = 1 },
        },
    }
    local bot = W.Group.new {
        orientation = "horizontal", spacing = 10,
        children = {
            { widget = sa_card,    weight = 1 },
            { widget = spark_card, weight = 2 },
        },
    }

    local layout = W.Group.new {
        orientation = "vertical", spacing = 10,
        children = {
            { widget = top, weight = 1 },
            { widget = bot, weight = 1 },
        },
    }

    local function refresh()
        local s = D.sample()
        if not s then return end

        local sub
        if s.status == "Charging" then sub = "CA"
        elseif s.status == "Full" then sub = "lleno"
        else sub = string.format("%.2f W", s.power_w) end

        ring:set_value(s.capacity,
            string.format("%d%%", math.floor(s.capacity)), sub)

        local r, g, b
        if s.status == "Charging" or s.status == "Full" then
            r, g, b = G.hex_to_rgba(theme.accent)
        elseif s.capacity <= 15 then
            r, g, b = G.hex_to_rgba(theme.usage_crit)
        elseif s.capacity <= 35 then
            r, g, b = G.hex_to_rgba(theme.usage_warn)
        else
            r, g, b = G.hex_to_rgba(theme.telemetry and
                theme.telemetry.battery or theme.accent)
        end
        ring.color = { r, g, b }

        spark:push(s.capacity)

        hw_kv:set("model",  s.model)
        hw_kv:set("vendor", s.vendor)
        hw_kv:set("serial", s.serial)
        hw_kv:set("tech",   s.technology)
        hw_kv:set("vmin",   string.format("%.2f V", s.voltage_min_design / 1e6))
        hw_kv:set("vnow",   string.format("%.3f V", s.voltage_now / 1e6))

        st_kv:set("status",  s.status)
        st_kv:set("time",    fmt_time(s.time_hours))
        st_kv:set("power",   string.format("%.2f W", s.power_w))
        st_kv:set("current", string.format("%d mA",
            math.floor(s.current_now / 1000)))

        sa_kv:set("cycles", s.cycle_count and tostring(s.cycle_count) or "N/A")
        sa_kv:set("health",
            s.charge_full_pct > 0 and (s.charge_full_pct .. "%") or "N/A")
        sa_kv:set("full",   string.format("%d mAh",
            math.floor(s.charge_full / 1000)))
        sa_kv:set("design", string.format("%d mAh",
            math.floor(s.charge_full_design / 1000)))
    end

    local timer

    return {
        widget = layout,
        start = function()
            refresh()
            timer = srv:add_timer(10000, refresh)
        end,
        stop = function()
            if timer then timer:cancel(); timer = nil end
        end,
    }
end

return M
