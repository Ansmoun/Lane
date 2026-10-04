-- Tab Temperaturas. Portado del original de Awesome. Usa W.*, los
-- timers del Server, y una tabla `theme`.

local W = require("lib.widgets")
local D = require("lib.data.temps")

local M = {}

local function color_temp(theme, t)
    if not t then return theme.muted end
    if t >= 85 then return theme.usage_crit end
    if t >= 75 then return theme.usage_crit end
    if t >= 60 then return theme.usage_warn end
    if t >= 40 then return theme.accent end
    return theme.telemetry.cpu
end

function M.new(srv, theme, opts)
    opts = opts or {}
    local compact = opts.compact or false
    local coretemp_path = D.find_coretemp()

    local temp_hex = theme.telemetry.temp or "#d65d0e"
    local G = require("lib.helpers.graphics")
    local tr, tg, tb = G.hex_to_rgba(temp_hex)

    local ring = W.Ring.new {
        text = "0",
        sub  = "°C",
        color = { tr, tg, tb },
        size = 130,
        thickness = 10,
    }

    local spark = W.Spark.new {
        samples = 300,
        min = 30, max = 100,
        color = theme.telemetry.temp or "#d65d0e",
        fill = true,
        axis_width = 42,
        axis_format = "%dC",
        grid = true,
        min_width = 240,
        min_height = 110,
    }

    local sensors = W.Rows.new {
        group_width = 60,
        name_width  = 110,
        value_width = 70,
        row_height = 18,
        row_spacing = 6,
        rows = {
            { id = "core0", group = "CPU",   name = "Core 0" },
            { id = "core1", group = "CPU",   name = "Core 1" },
            { id = "pkg",   group = "CPU",   name = "Package" },
            { id = "x86",   group = "Placa", name = "x86_pkg_temp" },
            { id = "acpi",  group = "Placa", name = "ACPI (acpitz)" },
            { id = "disk",  group = "Disco", name = "ST320LT012" },
        },
    }

    local layout
    if compact then
        -- Modo compacto: un solo Card con borde que contiene todo.
        -- El anillo lleva "Temperatura máxima" escrito dentro (via
        -- el campo sub del Ring).
        local top = W.Group.new {
            orientation = "horizontal",
            spacing = 10,
            children = {
                { widget = ring,   weight = 1 },
                { widget = spark,  weight = 1 },
            },
        }
        local inner = W.Group.new {
            orientation = "vertical",
            spacing = 8,
            children = {
                { widget = top,     weight = 1 },
                { widget = sensors, weight = 1 },
            },
        }
        layout = W.Card.new {
            title = nil,
            content = inner,
            padding = 10,
            bg = theme.bg_card_rgb,
            border = theme.separator_rgb,
        }
    else
        -- Modo clasico: 3 cards con titulo.
        local ring_wrap = W.Card.new {
            title = "Temperatura máxima",
            content = ring,
            padding = 10,
            bg = theme.bg_card_rgb,
            border = theme.separator_rgb,
        }
        local spark_wrap = W.Card.new {
            title = "Historia (10 min)",
            content = spark,
            padding = 10,
            bg = theme.bg_card_rgb,
            border = theme.separator_rgb,
        }
        local sensors_wrap = W.Card.new {
            title = "Sensores",
            content = sensors,
            padding = 10,
            bg = theme.bg_card_rgb,
            border = theme.separator_rgb,
        }
        local top = W.Group.new {
            orientation = "horizontal",
            spacing = 12,
            children = {
                { widget = ring_wrap,  weight = 1 },
                { widget = spark_wrap, weight = 1 },
            },
        }
        layout = W.Group.new {
            orientation = "vertical",
            spacing = 12,
            children = { top, sensors_wrap },
        }
    end

    local function update_row(id, temp)
        if not temp then
            sensors:set_markup(id, string.format(
                '<span foreground="%s">--</span>', theme.muted))
            return
        end
        sensors:set_markup(id, string.format(
            '<span foreground="%s" weight="bold">%d°C</span>',
            color_temp(theme, temp), temp))
    end

    local function refresh()
        local c = D.read_coretemp(coretemp_path)
        local z = D.read_zones()

        update_row("core0", c.core0)
        update_row("core1", c.core1)
        update_row("pkg",   c.pkg)
        update_row("x86",   z.x86)
        update_row("acpi",  z.board)

        D.read_smart(function(disk_temp) update_row("disk", disk_temp) end)

        local max_cpu = 0
        for _, v in ipairs({ c.core0, c.core1, c.pkg }) do
            if v and v > max_cpu then max_cpu = v end
        end

        ring:set_value(max_cpu / 100,
            string.format("%d", max_cpu),
            "°C máxima")
        spark:push(max_cpu)
    end

    local timer = nil

    return {
        widget = layout,
        start = function()
            refresh()
            timer = srv:add_timer(5000, refresh)
        end,
        stop = function()
            if timer then timer:cancel(); timer = nil end
        end,
    }
end

return M
