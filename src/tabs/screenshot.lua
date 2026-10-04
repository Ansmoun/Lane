-- Tab Screenshot: panel con dos tabs (Foto, Video).
-- Grid 3x2 de CardButtons para elegir modo.
-- En Video: fila de calidad (4 pills) + boton Avanzado.

local W = require("lib.widgets")
local screens = require("lib.screens")
local CardButton = require("lib.widgets.cardbutton")
local log = require("lib.log")

local M = {}

local ICON_DIR = os.getenv("HOME") ..
    "/proyectos/lane/icons-png/88/screenshot/"

local CARD_W, CARD_H   = 132, 90
local QUAL_W, QUAL_H   = 55, 45
local ADV_W,  ADV_H    = 84, 45

local QUALITY_PRESETS = {
    low    = { label = "Baja",   icon = "quality-low"    },
    mid    = { label = "Media",  icon = "quality-mid"    },
    high   = { label = "Alta",   icon = "quality-high"   },
    custom = { label = "Custom", icon = "quality-custom" },
}

local function to_hex(rgb)
    return string.format("#%02x%02x%02x",
        math.floor((rgb[1] or 0) * 255 + 0.5),
        math.floor((rgb[2] or 0) * 255 + 0.5),
        math.floor((rgb[3] or 0) * 255 + 0.5))
end

local function hex_to_rgb(hex)
    local h = hex:gsub("^#", "")
    return {
        tonumber(h:sub(1,2), 16) / 255,
        tonumber(h:sub(3,4), 16) / 255,
        tonumber(h:sub(5,6), 16) / 255,
    }
end

-- Mezcla lineal de dos colores {r,g,b} (0..1). t=0 -> c1, t=1 -> c2.
local function mix_rgb(c1, c2, t)
    return {
        c1[1] + (c2[1] - c1[1]) * t,
        c1[2] + (c2[2] - c1[2]) * t,
        c1[3] + (c2[3] - c1[3]) * t,
    }
end

local function make_card(theme, icon, title, subtitle, on_click, opts)
    opts = opts or {}
    return CardButton.new {
        icon         = icon,
        icon_dir     = ICON_DIR,
        title        = title,
        subtitle     = subtitle or "",
        width        = opts.w or CARD_W,
        height       = opts.h or CARD_H,
        icon_size    = opts.icon_size or 32,
        font_title   = opts.font_title or "DejaVu Sans Bold 10",
        font_sub     = opts.font_sub or "DejaVu Sans 8",
        bg_color     = to_hex(theme.bg_card_rgb),
        hover_color  = to_hex(mix_rgb(theme.bg_card_rgb,
            (function()
                local a = opts.hover_accent
                if type(a) == "string" then a = hex_to_rgb(a) end
                return a or theme.accent_rgb
            end)(), 0.72)),
        fg_color     = to_hex(theme.fg_rgb),
        fg_sub_color = to_hex(theme.muted_rgb),
        border_color = to_hex(theme.separator_rgb),
        accent_color = to_hex(theme.accent_rgb),
        corner_radius = opts.corner_radius or 8,
        on_click     = on_click,
    }
end

-- opts:
--   on_select(kind, mode, quality, custom_preset, custom_crf)
--   initial_quality, initial_preset, initial_crf
--   on_quality_change(quality, preset, crf)
--   on_advanced()  -- opcional: abre el sub-panel modal
function M.new(srv, theme, opts)
    opts = opts or {}

    local monitors = screens.list()
    log.info("screenshot-tab", "%d monitores detectados", #monitors)

    local state = {
        quality       = opts.initial_quality or "mid",
        custom_preset = opts.initial_preset  or "veryfast",
        custom_crf    = opts.initial_crf     or 23,
    }

    local function emit(kind, mode)
        if kind == "foto" and opts.on_foto then
            opts.on_foto(mode)
        elseif kind == "video" and opts.on_video then
            opts.on_video(mode, state.quality,
                state.custom_preset, state.custom_crf)
        end
    end

    local function notify_quality_change()
        if opts.on_quality_change then
            opts.on_quality_change(state.quality,
                state.custom_preset, state.custom_crf)
        end
    end

    local function make_mode_grid(kind)
        -- Lista de cards: pantalla, area, ventana, + 1 por monitor.
        -- En Video, la ultima posicion se llena con "Avanzado" en
        -- lugar de un spacer vacio.
        -- Colores de hover: vivos, hardcodeados a proposito.
        -- El hover es un estado transitorio y efimero; la paleta del
        -- tema no tiene colores con la saturacion suficiente para
        -- verse con el tinte del fondo, y estos se eligen para que
        -- el texto negro tenga contraste suficiente.
        local COLOR_FULL   = "#5aa8ff"  -- azul
        local COLOR_AREA   = "#33d6c6"  -- turquesa
        local COLOR_WINDOW = "#b878ff"  -- violeta
        local COLOR_ADV    = "#ff7d4d"  -- naranja
        -- Monitores: rotar entre colores para que no se vean todos iguales.
        local COLOR_MON = {
            "#ffb84d",  -- ambar
            "#ff6bb5",  -- rosa
            "#7ddc4d",  -- verde lima
            "#ff5c5c",  -- rojo
        }

        local cards = {}
        cards[#cards + 1] = make_card(theme, "screen-full",
            "Pantalla", "todos los monitores",
            function() emit(kind, { kind = "full" }) end,
            { hover_accent = COLOR_FULL })
        cards[#cards + 1] = make_card(theme, "area",
            "Area", "arrastrar el cursor",
            function() emit(kind, { kind = "area" }) end,
            { hover_accent = COLOR_AREA })
        cards[#cards + 1] = make_card(theme, "window",
            "Ventana", "click en una ventana",
            function() emit(kind, { kind = "window" }) end,
            { hover_accent = COLOR_WINDOW })

        for i, mon in ipairs(monitors) do
            local sub = string.format("%d x %d", mon.w, mon.h)
            local col = COLOR_MON[((i - 1) % #COLOR_MON) + 1]
            cards[#cards + 1] = make_card(theme, "monitor",
                mon.name, sub,
                function()
                    emit(kind, { kind = "monitor", mon = mon })
                end,
                { hover_accent = col })
        end

        local extra = nil
        if kind == "video" then
            extra = make_card(theme, "quality-custom",
                "Avanzado", "preset y CRF",
                function()
                    if opts.on_advanced then opts.on_advanced() end
                end,
                { hover_accent = COLOR_ADV })
        end

        -- Grid 3 columnas
        local COLS = 3
        local total = #cards + (extra and 1 or 0)
        local rows = {}
        for i = 1, total, COLS do
            local row_children = {}
            for j = 0, COLS - 1 do
                local idx = i + j
                local card
                if idx <= #cards then
                    card = cards[idx]
                elseif idx == #cards + 1 and extra then
                    card = extra
                end
                if card then
                    row_children[#row_children + 1] =
                        { widget = card, weight = 0 }
                else
                    local sp = W.Text.new { text = "" }
                    sp.min_w, sp.max_w = CARD_W, CARD_W
                    sp.min_h, sp.max_h = CARD_H, CARD_H
                    row_children[#row_children + 1] =
                        { widget = sp, weight = 0 }
                end
            end
            rows[#rows + 1] = {
                widget = W.Group.new {
                    orientation = "horizontal",
                    spacing = 10,
                    children = row_children,
                },
                weight = 0,
            }
        end

        return rows
    end

    local function make_quality_row()
        local order = { "low", "mid", "high", "custom" }
        local buttons = {}

        local function update_selected()
            for _, btn in ipairs(buttons) do
                btn.selected = (btn._key == state.quality)
                btn:damage()
            end
        end

        -- Un color por nivel de calidad (hardcoded, vivos).
        local QUAL_COLORS = {
            low    = "#ff5c5c",  -- rojo
            mid    = "#ffb84d",  -- ambar
            high   = "#7ddc4d",  -- verde lima
            custom = "#b878ff",  -- violeta
        }
        for _, key in ipairs(order) do
            local q = QUALITY_PRESETS[key]
            local captured = key
            local b = make_card(theme, q.icon, q.label, "",
                function()
                    state.quality = captured
                    update_selected()
                    notify_quality_change()
                end,
                { w = QUAL_W, h = QUAL_H, icon_size = 20,
                  font_title = "DejaVu Sans Bold 8",
                  hover_accent = QUAL_COLORS[captured] })
            b._key = captured
            b.selected = (captured == state.quality)
            buttons[#buttons + 1] = b
        end

        local children = {}
        for _, btn in ipairs(buttons) do
            children[#children + 1] = { widget = btn, weight = 0 }
        end

        -- Etiqueta "Calidad" antes de los pills
        local quality_lbl = W.Text.new {
            text = "Calidad",
            font = "DejaVu Sans Bold 10",
            align = "left", valign = "center",
            r = theme.muted_rgb[1],
            g = theme.muted_rgb[2],
            b = theme.muted_rgb[3],
        }

        return W.Group.new {
            orientation = "horizontal",
            spacing = 8,
            children = {
                { widget = quality_lbl, weight = 0 },
                (function()
                    local c = { widget = W.Group.new {
                        orientation = "horizontal",
                        spacing = 6,
                        children = children,
                    }, weight = 1 }
                    return c
                end)(),
            },
        }
    end

    local function make_tab(kind)
        local children = make_mode_grid(kind)
        if kind == "video" then
            -- Separador visual + espaciado antes de la fila de calidad
            local sep = W.Text.new { text = "" }
            sep.min_h, sep.max_h = 6, 6
            children[#children + 1] = { widget = sep, weight = 0 }
            children[#children + 1] = {
                widget = make_quality_row(), weight = 0,
            }
        end
        return W.Group.new {
            orientation = "vertical",
            spacing = 12,
            padding = 14,
            children = children,
        }
    end

    local tabs = {
        {
            id = "foto", label = "Foto", icon = "tab-foto",
            factory = function() return { widget = make_tab("foto") } end,
        },
        {
            id = "video", label = "Video", icon = "tab-video",
            factory = function() return { widget = make_tab("video") } end,
        },
    }

    local tabbed = W.TabbedPanel.new {
        tabs = tabs,
        compact = false,
        theme = theme,
        spacing = 10,
        tabsbar_opts = {
            pad_x = 14,
            pad_y = 6,
            gap   = 6,
        },
    }

    -- Envolver en un Group con padding vertical para dar aire
    -- arriba y abajo del TabsBar.
    local wrapped = W.Group.new {
        orientation = "vertical",
        padding = 4,
        children = { tabbed },
    }

    return {
        widget = wrapped,
        start = function() end,
        stop  = function() end,
    }
end

return M
