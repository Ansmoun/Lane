-- Tab CPU: ring + cores + info + dos historiales (uso y MHz).
-- Layout en dos columnas:
--   izquierda (arriba -> abajo): CPU (ring+cores), Info (KV)
--   derecha   (arriba -> abajo): Historia uso, Historia MHz

local W = require("lib.widgets")
local F = require("lib.helpers.format")
local D = require("lib.data.cpu")

local M = {}

function M.new(srv, theme)
    -- Leer las opciones de animacion del conf.lua. Si el motor no
    -- esta listo (animate_panel = false), los tres flags quedan
    -- en false automaticamente. animate_widgets controla las
    -- animaciones de entrada; animate_values controla las de
    -- actualizacion de datos (ring.animate_to, spark.push_animated).
    local Config = require("lib.data.config")
    local A = Config.get_anim_opts()
    local anim_widgets = A.widgets
    local anim_values  = A.values

    D.reset()
    D.sample()
    local first = D.sample()
    local range = D.freq_range()

    -- Los MHz pueden no caber exactos en el rango declarado por el
    -- kernel: a veces el turbo sube un poco mas. Damos un margen
    -- de seguridad a max para que el spark no sature el borde.
    local freq_min = range.min or 800
    local freq_max = range.max or 1100
    if freq_max <= freq_min then freq_max = freq_min + 100 end

    local core_rows = {}
    for i = 0, math.max(0, first.n_cores - 1) do
        table.insert(core_rows, { "core" .. i, "Core " .. i })
    end

    local ring = W.Ring.new {
        text = "0%",
        sub  = "CPU",
        color = { 0.55, 0.85, 0.60 },
        raw_range = { 0, 100 },
        size = 130, thickness = 10,
    }

    local cores = W.Motors.new {
        left_width = 44, pct_width = 38,
        bar_height = 6, row_height = 12,
        bar_color = theme.telemetry.cpu,
        bar_bg = theme.separator,
        pct_font = "DejaVu Sans Mono 9",
        rows = core_rows,
    }

    -- Card CPU: ring arriba, cores abajo. Los dos en un Group
    -- vertical. El ring se centra horizontalmente con spacers de
    -- weight 1 a cada lado (mismo patron que el avatar de Inicio).
    local cpu_inner = W.Group.new {
        orientation = "vertical",
        spacing = 8,
        children = {
            { widget = W.Group.new {
                orientation = "horizontal",
                children = {
                    { widget = W.Text.new { text = "", font = "DejaVu Sans 1" }, weight = 1 },
                    { widget = ring, weight = 0 },
                    { widget = W.Text.new { text = "", font = "DejaVu Sans 1" }, weight = 1 },
                },
            }, weight = 0 },
            { widget = cores, weight = 0 },
        },
    }

    local spark_usage = W.Spark.new {
        samples = 60, min = 0, max = 100,
        color = theme.telemetry.cpu or "#8ec07c",
        fill = true,
        axis_width = 32, axis_format = "%d",
        grid = true,
        min_width = 200, min_height = 90,
    }

    local spark_freq = W.Spark.new {
        samples = 60,
        min = freq_min, max = freq_max,
        color = theme.accent or "#d79921",
        fill = true,
        axis_width = 52, axis_format = "%d",
        grid = true,
        min_width = 200, min_height = 90,
    }

    local info = W.KV.new {
        key_width = 90, row_height = 13, row_spacing = 2,
        key_color = { 0.55, 0.55, 0.60 },
        value_color = { 0.90, 0.90, 0.90 },
        rows = {
            { id = "model",  label = "Modelo" },
            { id = "freq",   label = "Frecuencia" },
            { id = "temp",   label = "Temperatura", format = "%d°C" },
            { id = "uptime", label = "Uptime" },
            { id = "load",   label = "Load avg" },
        },
    }

    local cpu_card = W.Card.new {
        title = "CPU", content = cpu_inner,
        padding = 10,
        bg = theme.bg_card_rgb,
        border = theme.separator_rgb,
        min_height = 220,
    }
    local info_card = W.Card.new {
        title = "Info", content = info,
        padding = 10,
        bg = theme.bg_card_rgb,
        border = theme.separator_rgb,
        min_height = 140,
    }
    local usage_card = W.Card.new {
        title = "Historia uso (60s)", content = spark_usage,
        padding = 10,
        bg = theme.bg_card_rgb,
        border = theme.separator_rgb,
    }
    local freq_card = W.Card.new {
        title = "Historia MHz (60s)", content = spark_freq,
        padding = 10,
        bg = theme.bg_card_rgb,
        border = theme.separator_rgb,
    }

    local left_col = W.Group.new {
        orientation = "vertical", spacing = 10,
        children = {
            { widget = cpu_card,  weight = 1 },
            { widget = info_card, weight = 1 },
        },
    }
    local right_col = W.Group.new {
        orientation = "vertical", spacing = 10,
        children = {
            { widget = usage_card, weight = 1 },
            { widget = freq_card,  weight = 1 },
        },
    }

    local layout = W.Group.new {
        orientation = "horizontal", spacing = 10,
        children = {
            { widget = left_col,  weight = 1 },
            { widget = right_col, weight = 1 },
        },
    }

    -- Estado de las animaciones de entrada de los sparks. Cada
    -- sparkline necesita >=2 puntos para dibujar algo; la
    -- animacion se dispara en el primer refresh_fast que alcance
    -- ese umbral, no en play_intro.
    local anim_on = false
    local usage_revealed = false
    local freq_revealed  = false

    local function refresh_fast(instant)
        local s = D.sample()
        if instant or not anim_values then
            ring:set_value(s.usage * 100,
                string.format("%d%%", math.floor(s.usage * 100)),
                string.format("%.0f MHz", s.freq))
        else
            ring:animate_to(s.usage * 100,
                string.format("%d%%", math.floor(s.usage * 100)),
                string.format("%.0f MHz", s.freq), 700)
        end

        if anim_values then
            spark_usage:push_animated(s.usage * 100, 350)
            spark_freq:push_animated(s.freq, 350)
        else
            spark_usage:push(s.usage * 100)
            spark_freq:push(s.freq)
        end

        -- Reveal de los sparks: solo si anim_widgets esta activo.
        -- Si no, arrancan revelados desde el primer punto util.
        if not usage_revealed and #spark_usage.history:get() >= 2 then
            usage_revealed = true
            if anim_on and anim_widgets then
                local anim = require("lib.anim")
                anim.tween(spark_usage, "alpha", 0, 1, 600, anim.EASE.out_quad)
                anim.tween(spark_usage, "reveal", 0, 1, 900, anim.EASE.out_cubic)
            end
        end
        if not freq_revealed and #spark_freq.history:get() >= 2 then
            freq_revealed = true
            if anim_on and anim_widgets then
                local anim = require("lib.anim")
                anim.tween(spark_freq, "alpha", 0, 1, 600, anim.EASE.out_quad)
                anim.tween(spark_freq, "reveal", 0, 1, 900, anim.EASE.out_cubic)
            end
        end

        -- per_core[i] ya viene en 0..1. Pasarlo tal cual (BarRow
        -- espera pct en 0..1). Si animate_values esta activo,
        -- animar el pct_value con set_animated.
        for i = 0, (s.n_cores - 1) do
            local pct = s.per_core[i] or 0
            if anim_values then
                cores:set_animated("core" .. i, pct, 500)
            else
                cores:set("core" .. i, pct)
            end
        end
        info:set_markup("freq", string.format(
            '<span foreground="%s">%d MHz <span foreground="%s">(%d-%d)</span></span>',
            theme.fg_normal, math.floor(s.freq),
            theme.muted, range.min, range.max))
        info:set("temp", s.temp)
    end

    local function refresh_slow()
        local i = D.info()
        info:set("model", i.model)
        info:set("uptime", F.uptime(i.uptime))
        info:set("load", i.loadavg)
    end

    local t_fast, t_slow

    -- Animaciones de entrada. Solo si el motor esta inicializado
    -- (anim.is_ready()); si animate_panel = false, no hay animacion
    -- y los widgets quedan en estado final desde el primer frame.
    local function play_intro()
        if not anim_widgets then return end
        local anim = require("lib.anim")
        if not anim.is_ready() then return end

        anim.tween(ring, "reveal", 0, 1, 700, anim.EASE.out_cubic)
        anim.tween_custom(info, function(e)
            info:set_alpha(e)
        end, 500, anim.EASE.out_quad)

        for i, row in ipairs(cores.rows) do
            anim.delay((i - 1) * 35, function()
                anim.tween_custom(cores, function(e)
                    row.reveal = e
                    cores:damage()
                end, 450, anim.EASE.out_cubic)
            end)
        end
    end

    return {
        widget = layout,
        start = function()
            local anim = require("lib.anim")
            anim_on = anim.is_ready()
            usage_revealed = false
            freq_revealed  = false
            if anim_on and anim_widgets then
                spark_usage.alpha  = 0
                spark_usage.reveal = 0
                spark_freq.alpha   = 0
                spark_freq.reveal  = 0
            else
                spark_usage.alpha  = 1
                spark_usage.reveal = 1
                usage_revealed = true
                spark_freq.alpha   = 1
                spark_freq.reveal  = 1
                freq_revealed  = true
            end
            refresh_slow()
            -- Instantaneo para no pelear con el reveal del anillo.
            refresh_fast(true)
            play_intro()
            t_fast = srv:add_timer(1000, function()
                refresh_fast(false)
            end)
            t_slow = srv:add_timer(5000, refresh_slow)
        end,
        stop = function()
            if t_fast then t_fast:cancel(); t_fast = nil end
            if t_slow then t_slow:cancel(); t_slow = nil end
        end,
    }
end

return M
