-- Tab GPU: anillo + spark + motors + KV estado.
-- Layout compacto: 1024x600 friendly.

local W = require("lib.widgets")
local G = require("lib.helpers.graphics")
local D = require("lib.data.gpu")

local M = {}

function M.new(srv, theme)
    local Config = require("lib.data.config")
    local A = Config.get_anim_opts()
    local anim_values = A.values
    local spec = D.specs()

    local gr, gg, gb = G.hex_to_rgba(theme.telemetry.gpu or "#d3869b")

    local ring = W.Ring.new {
        text = "0",
        sub  = "MHz",
        color = { gr, gg, gb },
        raw_range = { 0, 100 },
        size = 130, thickness = 10,
    }

    local spark = W.Spark.new {
        samples = 60, min = 0, max = 100,
        color = theme.telemetry.gpu or "#d3869b",
        fill = true,
        axis_width = 36, axis_format = "%d%%",
        grid = true,
        min_width = 220, min_height = 110,
    }

    local motors = W.Motors.new {
        left_width = 60, pct_width = 38,
        bar_height = 8, row_height = 14,
        bar_color = theme.telemetry.gpu,
        bar_bg = theme.separator,
        pct_font = "DejaVu Sans Mono 9",
        rows = {
            { id = "render",  label = "Render" },
            { id = "blitter", label = "Blitter" },
            { id = "video",   label = "Video" },
        },
    }

    local state = W.KV.new {
        key_width = 100, row_height = 16, row_spacing = 5,
        key_color = { 0.55, 0.55, 0.60 },
        value_color = { 0.90, 0.90, 0.90 },
        rows = {
            { id = "rc6",   label = "RC6 reposo", format = "%.1f%%" },
            { id = "power", label = "Consumo",    format = "%.2f W" },
            { id = "irqs",  label = "IRQs",       format = "%d/s" },
        },
    }

    -- Header de hardware: va DEBAJO del anillo, dentro de la card
    -- de GPU. Poco texto, no necesita card propia.
    local hw = W.Header.new {
        markup = true,
        font = "DejaVu Sans 9",
        color = { 0.65, 0.65, 0.70 },
        align = "center",
        valign = "top",
        wrap = true,
        min_height = 24,
    }

    -- Card GPU: anillo arriba, header debajo.
    local ring_box = W.Group.new {
        orientation = "vertical",
        spacing = 6,
        children = {
            { widget = ring, weight = 1 },
            { widget = hw,   weight = 0 },
        },
    }

    local gpu_card = W.Card.new {
        title = "GPU",
        content = ring_box,
        padding = 10,
        bg = theme.bg_card_rgb,
        border = theme.separator_rgb,
    }

    local spark_card = W.Card.new {
        title = "Historia (60s)",
        content = spark,
        padding = 10,
        bg = theme.bg_card_rgb,
        border = theme.separator_rgb,
    }

    local motors_card = W.Card.new {
        title = "Motores",
        content = motors,
        padding = 10,
        bg = theme.bg_card_rgb,
        border = theme.separator_rgb,
    }

    local state_card = W.Card.new {
        title = "Estado",
        content = state,
        padding = 10,
        bg = theme.bg_card_rgb,
        border = theme.separator_rgb,
    }

    local top = W.Group.new {
        orientation = "horizontal", spacing = 10,
        children = {
            { widget = gpu_card,   weight = 0 },
            { widget = spark_card, weight = 1 },
        },
    }

    local bot = W.Group.new {
        orientation = "horizontal", spacing = 10,
        children = {
            { widget = motors_card, weight = 1 },
            { widget = state_card,  weight = 1 },
        },
    }

    local layout = W.Group.new {
        orientation = "vertical", spacing = 10,
        children = {
            { widget = top, weight = 1 },
            { widget = bot, weight = 1 },
        },
    }

    local function refresh_hw()
        hw:set_markup(string.format(
            '<span foreground="%s" weight="bold">Intel HD Graphics</span> ' ..
            '<span foreground="%s">(Sandy Bridge GT1) · 32 nm · 6 EU · %d-%d MHz (boost %d)</span>',
            theme.accent, theme.muted,
            math.floor(spec.min), math.floor(spec.max), math.floor(spec.boost)))
    end

    local function refresh()
        local s = D.status()
        if not s then return end
        -- s.render/blitter/video vienen en 0..100 (porcentaje del
        -- /tmp/gpu-status.txt). BarRow espera 0..1. Sin el /100 las
        -- barras quedaban clavadas al maximo.
        local mr = s.render  / 100
        local mb = s.blitter / 100
        local mv = s.video   / 100
        if anim_values then
            ring:animate_to(s.render,
                string.format("%d", math.floor(s.freq)), nil, 700)
            spark:push_animated(s.render, 350)
            motors:set_animated("render",  mr, 500)
            motors:set_animated("blitter", mb, 500)
            motors:set_animated("video",   mv, 500)
        else
            ring:set_value(s.render,
                string.format("%d", math.floor(s.freq)))
            spark:push(s.render)
            motors:set("render",  mr)
            motors:set("blitter", mb)
            motors:set("video",   mv)
        end
        state:set("rc6",   s.rc6)
        state:set("power", s.power)
        state:set("irqs",  s.irqs)
    end

    local timer

    return {
        widget = layout,
        start = function()
            refresh_hw()
            refresh()
            timer = srv:add_timer(2000, refresh)
        end,
        stop = function()
            if timer then timer:cancel(); timer = nil end
        end,
    }
end

return M
