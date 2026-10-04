-- Tab Configuracion: apariencia, entorno y atajos.
-- Tres tabs internos:
--   Apariencia  paleta, animaciones, tasa de refresco
--   Entorno     selector de gestor de ventanas
--   Atajos      (en construccion)

local W = require("lib.widgets")
local U = require("lib.helpers.util")
local D = require("lib.data.config")
local S = require("lib.data.session")
local log = require("lib.log")

local M = {}

-- ══════════════════════════════════════════════════════════════════
-- Helpers de UI (fuera de M.new para no recrearlos por instancia)
-- ══════════════════════════════════════════════════════════════════

-- Texto secundario (muted)
local function muted(theme, text, font)
    return W.Text.new {
        text = text, font = font or "DejaVu Sans 10",
        r = theme.muted_rgb[1],
        g = theme.muted_rgb[2],
        b = theme.muted_rgb[3],
        align = "left", valign = "center",
    }
end

-- Texto principal
local function fg(theme, text, font)
    return W.Text.new {
        text = text, font = font or "DejaVu Sans Bold 11",
        r = theme.fg_rgb[1],
        g = theme.fg_rgb[2],
        b = theme.fg_rgb[3],
        align = "center", valign = "center",
    }
end

-- Fila de ciclado: [label muted (w=1)] [<] [valor] [>]
local function make_cycler(theme, label, getter, setter, list_getter,
                          on_change)
    local title = muted(theme, label)
    local value = fg(theme, getter())
    local btn_prev = W.Button.new {
        text = "<", flat = true, font = "DejaVu Sans 12",
        padding_x = 10, padding_y = 4,
        color_hover = theme.bg_focus_rgb,
    }
    local btn_next = W.Button.new {
        text = ">", flat = true, font = "DejaVu Sans 12",
        padding_x = 10, padding_y = 4,
        color_hover = theme.bg_focus_rgb,
    }

    local function cycle(delta)
        local list = list_getter()
        if #list == 0 then return end
        local cur = getter()
        local idx = 1
        for i, v in ipairs(list) do
            if v == cur then idx = i; break end
        end
        idx = idx + delta
        if idx < 1 then idx = #list end
        if idx > #list then idx = 1 end
        local new_val = list[idx]
        value:set_text(new_val)
        setter(new_val)
        if on_change then on_change() end
    end

    btn_prev.opts.on_click = function() cycle(-1) end
    btn_next.opts.on_click = function() cycle(1) end

    return W.Group.new {
        orientation = "horizontal", spacing = 8,
        children = {
            { widget = title,    weight = 1 },
            { widget = btn_prev, weight = 0 },
            { widget = value,    weight = 0 },
            { widget = btn_next, weight = 0 },
        },
    }
end

-- Fila toggle: [label muted (w=1)] [boton]
local function make_toggle(theme, label, getter, setter, on_change)
    local title = muted(theme, label)
    local btn = W.Button.new {
        text = getter() and "Si" or "No",
        flat = true, font = "DejaVu Sans Bold 11",
        padding_x = 12, padding_y = 4,
        color_hover = theme.bg_focus_rgb,
    }
    btn.opts.on_click = function()
        local new_val = not getter()
        setter(new_val)
        btn:set_text(new_val and "Si" or "No")
        if on_change then on_change() end
    end
    return W.Group.new {
        orientation = "horizontal", spacing = 8,
        children = {
            { widget = title, weight = 1 },
            { widget = btn,   weight = 0 },
        },
    }
end

-- Fila numerica: [label muted (w=1)] [input]
local function make_numeric(theme, label, getter, setter, min, max, on_change)
    local title = muted(theme, label)
    local input = W.TextInput.new {
        text = tostring(getter()),
        font = "DejaVu Sans Bold 11",
        padding_x = 8, padding_y = 4,
        color_bg = nil,
        color_border = theme.separator,
        corner_radius = 3,
        min_width = 60,
        min_height = 24,
        on_submit = function(text)
            input:set_focused(false)
            local n = tonumber(U.trim(text or ""))
            if not n or n < min or n > max then
                input:set_text(tostring(getter()))
                return
            end
            n = math.floor(n)
            if n ~= getter() then
                setter(n)
                input:set_text(tostring(n))
                if on_change then on_change() end
            end
        end,
        on_cancel = function()
            input:set_text(tostring(getter()))
            input:set_focused(false)
        end,
    }
    input.opts.on_focus_request = function()
        input:set_focused(true)
    end
    return W.Group.new {
        orientation = "horizontal", spacing = 8,
        children = {
            { widget = title, weight = 1 },
            { widget = input, weight = 0 },
        },
    }
end

-- Divisor de seccion: label + linea
local function make_section_title(theme, text)
    local title = W.Text.new {
        text = text, font = "DejaVu Sans Bold 10",
        r = theme.accent_rgb[1],
        g = theme.accent_rgb[2],
        b = theme.accent_rgb[3],
        align = "left", valign = "center",
    }
    return W.Group.new {
        orientation = "horizontal", padding = 0,
        children = { { widget = title, weight = 1 } },
    }
end

-- ══════════════════════════════════════════════════════════════════
-- Tab Apariencia
-- ══════════════════════════════════════════════════════════════════

local function build_apariencia_tab(srv, theme, state)
    local pending = state.pending

    local update_status -- forward

    local theme_cycler = make_cycler(theme, "Tema",
        function() return pending.theme end,
        function(v) pending.theme = v end,
        function() return state.themes_list end,
        function()
            pending.dirty = true
            if update_status then update_status() end
        end)

    local palette_cycler = make_cycler(theme, "Paleta",
        function() return pending.palette end,
        function(v) pending.palette = v end,
        function() return state.palettes_list end,
        function()
            pending.dirty = true
            if update_status then update_status() end
        end)

    local anim_row = make_toggle(theme, "Animar panel",
        function() return pending.animate_panel end,
        function(v) pending.animate_panel = v end,
        function()
            pending.dirty = true
            if update_status then update_status() end
        end)

    local tabs_row = make_toggle(theme, "Crossfade entre tabs",
        function() return pending.animate_tabs end,
        function(v) pending.animate_tabs = v end,
        function()
            pending.dirty = true
            if update_status then update_status() end
        end)

    local widgets_row = make_toggle(theme, "Animar entrada de widgets",
        function() return pending.animate_widgets end,
        function(v) pending.animate_widgets = v end,
        function()
            pending.dirty = true
            if update_status then update_status() end
        end)

    local values_row = make_toggle(theme, "Animar cambios de datos",
        function() return pending.animate_values end,
        function(v) pending.animate_values = v end,
        function()
            pending.dirty = true
            if update_status then update_status() end
        end)

    local hz_row = make_numeric(theme, "Tasa de refresco (Hz)",
        function() return pending.anim_hz end,
        function(v) pending.anim_hz = v end,
        1, 240,
        function()
            pending.dirty = true
            if update_status then update_status() end
        end)

    local dur_row = make_numeric(theme, "Duracion del fade (ms)",
        function() return pending.anim_duration end,
        function(v) pending.anim_duration = v end,
        50, 5000,
        function()
            pending.dirty = true
            if update_status then update_status() end
        end)

    local hint = W.Text.new {
        text = "Hz: 1-240. Duracion: 50-5000 ms.",
        font = "DejaVu Sans 8",
        r = theme.muted_rgb[1],
        g = theme.muted_rgb[2],
        b = theme.muted_rgb[3],
        align = "left", valign = "center",
        wrap = true,
    }

    local status_label = W.Text.new {
        text = "", font = "DejaVu Sans 10",
        align = "center", valign = "center",
        r = 0.75, g = 0.75, b = 0.80,
    }

    update_status = function()
        if pending.dirty then
            status_label:set_text("Cambios pendientes - pulsa Aplicar")
        else
            status_label:set_text("Sin cambios")
        end
    end
    update_status()

    local btn_apply = W.Button.new {
        text = "Aplicar", flat = true, font = "DejaVu Sans Bold 10",
        padding_x = 14, padding_y = 6,
        color_hover = theme.bg_focus_rgb,
        color_text = { 0.55, 0.85, 0.60 },
    }
    btn_apply.opts.on_click = function()
        log.info("config", "aplicar apariencia: tema=%s paleta=%s panel=%s tabs=%s widgets=%s values=%s hz=%d dur=%d",
            pending.theme, pending.palette,
            tostring(pending.animate_panel),
            tostring(pending.animate_tabs),
            tostring(pending.animate_widgets),
            tostring(pending.animate_values),
            pending.anim_hz, pending.anim_duration)

        D.set("theme", pending.theme)
        D.set("palette", pending.palette)

        -- Escribir tambien el archivo que lee theme.find_palette_path().
        -- D.set escribe a conf.lua (~/.config/awesome/), que es la
        -- config del awesome original. theme.lua lee de
        -- ~/.config/lane/palette. Son dos archivos distintos: hay
        -- que escribir ambos para que los demas procesos, que hacen
        -- theme.reload_in_place() sin argumento, lean la paleta nueva.
        U.write_file(
            (os.getenv("HOME") or "") .. "/.config/lane/palette",
            pending.palette .. "\n")
        D.set_bool("animate_panel",   pending.animate_panel)
        D.set_bool("animate_tabs",    pending.animate_tabs)
        D.set_bool("animate_widgets", pending.animate_widgets)
        D.set_bool("animate_values",  pending.animate_values)
        D.set_int("anim_hz", pending.anim_hz)
        D.set_int("anim_duration", pending.anim_duration)

        local anim = require("lib.anim")
        if anim.is_ready() then anim.set_fps(pending.anim_hz) end

        local theme_mod = require("lib.theme")
        local path = theme_mod.palette_path(pending.palette)
        local ok, err = theme_mod.reload_in_place(theme, path)
        if not ok then
            log.error("config", "reload fallo: %s", tostring(err))
            status_label:set_text("Error: " .. tostring(err))
            return
        end

        -- Avisar a los demas procesos del entorno (daemons y otras
        -- apps abiertas) que la paleta cambio. Ellos recargan y se
        -- reconstruyen solos al recibir SIGUSR1.
        local reload = require("lib.reload")
        local n = reload.broadcast()

        -- La reconstruccion de ESTE proceso la dispara theme.watch
        -- (registrado por lib.app).
        if n > 0 then
            status_label:set_text(string.format(
                "Aplicado. Avisados %d procesos.", n))
        else
            status_label:set_text("Aplicado.")
        end
        pending.dirty = false
    end

    local content = W.Group.new {
        orientation = "vertical", spacing = 10, padding = 0,
        children = {
            make_section_title(theme, "Apariencia"),
            theme_cycler,
            palette_cycler,
            make_section_title(theme, "Animaciones"),
            anim_row,
            tabs_row,
            widgets_row,
            values_row,
            hz_row,
            dur_row,
            hint,
            status_label,
            btn_apply,
        },
    }

    return W.Card.new {
        content = content, padding = 16,
        bg = theme.bg_card_rgb,
        border = theme.separator_rgb,
    }
end

-- ══════════════════════════════════════════════════════════════════
-- Tab Entorno
-- ══════════════════════════════════════════════════════════════════

local function build_entorno_tab(srv, theme, state)
    -- Detectar WMs
    local wms = S.list_installed()
    local current_wm = S.get_wm() or (wms[1] and wms[1].id)
    local pending_wm = current_wm

    if #wms == 0 then
        return W.Card.new {
            content = W.Text.new {
                text = "No se detectaron gestores de ventanas en $PATH.",
                font = "DejaVu Sans 11",
                r = theme.muted_rgb[1],
                g = theme.muted_rgb[2],
                b = theme.muted_rgb[3],
                align = "center", valign = "center",
                wrap = true,
            },
            padding = 20,
            bg = theme.bg_card_rgb,
            border = theme.separator_rgb,
        }
    end

    -- Botonera de WMs: una fila por WM, con boton radio a la izquierda
    local wm_rows = {}
    local radio_buttons = {}

    local function update_radios()
        for id, btn in pairs(radio_buttons) do
            btn:set_text(id == pending_wm and "[X]" or "[ ]")
        end
    end

    for _, wm in ipairs(wms) do
        local radio = W.Button.new {
            text = (wm.id == pending_wm) and "[X]" or "[ ]",
            flat = true, font = "DejaVu Sans Mono Bold 12",
            padding_x = 8, padding_y = 4,
            color_hover = theme.bg_focus_rgb,
        }
        radio.opts.on_click = function()
            pending_wm = wm.id
            update_radios()
        end
        radio_buttons[wm.id] = radio

        local name = W.Text.new {
            text = wm.name, font = "DejaVu Sans Bold 11",
            r = theme.fg_rgb[1],
            g = theme.fg_rgb[2],
            b = theme.fg_rgb[3],
            align = "left", valign = "center",
        }
        local desc = muted(theme, wm.desc, "DejaVu Sans 9")

        local info = W.Group.new {
            orientation = "vertical", spacing = 0, padding = 0,
            children = {
                { widget = name, weight = 0 },
                { widget = desc, weight = 0 },
            },
        }

        wm_rows[#wm_rows + 1] = W.Group.new {
            orientation = "horizontal", spacing = 10, padding = 0,
            children = {
                { widget = radio, weight = 0 },
                { widget = info,  weight = 1 },
            },
        }
    end

    local status_label = W.Text.new {
        text = "Actual: " .. tostring(current_wm) ..
               "    ·    Se aplica al reiniciar la sesion",
        font = "DejaVu Sans 9",
        r = theme.muted_rgb[1],
        g = theme.muted_rgb[2],
        b = theme.muted_rgb[3],
        align = "center", valign = "center",
    }

    local btn_apply = W.Button.new {
        text = "Aplicar gestor de ventanas",
        flat = true, font = "DejaVu Sans Bold 10",
        padding_x = 14, padding_y = 6,
        color_hover = theme.bg_focus_rgb,
        color_text = { 0.55, 0.85, 0.60 },
    }
    btn_apply.opts.on_click = function()
        if pending_wm == current_wm then
            status_label:set_text("Sin cambios. Actual: " .. current_wm)
            return
        end
        S.set_wm(pending_wm)
        current_wm = pending_wm
        status_label:set_text("Guardado: " .. current_wm ..
            "    ·    Se aplica al reiniciar la sesion")
        log.info("config", "wm guardado: %s", current_wm)
    end

    local content_children = {
        make_section_title(theme, "Gestor de ventanas"),
        W.Text.new {
            text = "El gestor de ventanas se cambia al reiniciar la sesion. " ..
                   "No es posible cambiarlo en caliente.",
            font = "DejaVu Sans 9",
            r = theme.muted_rgb[1],
            g = theme.muted_rgb[2],
            b = theme.muted_rgb[3],
            align = "left", valign = "center",
            wrap = true,
        },
        W.Text.new { text = "", font = "DejaVu Sans 1", min_height = 6 },
    }
    for _, row in ipairs(wm_rows) do
        content_children[#content_children + 1] = row
    end
    content_children[#content_children + 1] =
        W.Text.new { text = "", font = "DejaVu Sans 1", min_height = 6 }
    content_children[#content_children + 1] = status_label
    content_children[#content_children + 1] = btn_apply

    local content = W.Group.new {
        orientation = "vertical", spacing = 8, padding = 0,
        children = content_children,
    }

    return W.Card.new {
        content = content, padding = 16,
        bg = theme.bg_card_rgb,
        border = theme.separator_rgb,
    }
end

-- ══════════════════════════════════════════════════════════════════
-- Tab Atajos (placeholder)
-- ══════════════════════════════════════════════════════════════════

local function build_atajos_tab(srv, theme, state)
    return W.Card.new {
        content = W.Text.new {
            text = "En construccion.",
            font = "DejaVu Sans 11",
            r = theme.muted_rgb[1],
            g = theme.muted_rgb[2],
            b = theme.muted_rgb[3],
            align = "center", valign = "center",
            wrap = true,
        },
        padding = 20,
        bg = theme.bg_card_rgb,
        border = theme.separator_rgb,
    }
end

-- ══════════════════════════════════════════════════════════════════
-- M.new
-- ══════════════════════════════════════════════════════════════════

function M.new(srv, theme)
    log.info("config", "factory inicio")

    local state = {
        pending = {
            theme           = D.get("theme")   or "gruvbox",
            palette         = D.get("palette") or "ayu",
            animate_panel   = D.get_bool("animate_panel", false),
            animate_tabs    = D.get_bool("animate_tabs",    true),
            animate_widgets = D.get_bool("animate_widgets", true),
            animate_values  = D.get_bool("animate_values",  true),
            anim_hz         = D.get_int("anim_hz", 30),
            anim_duration   = D.get_int("anim_duration", 300),
            dirty           = false,
        },
        themes_list   = D.list_themes(),
        palettes_list = D.list_palettes(),
    }

    -- TabbedPanel con los tres tabs
    local tabs = {
        {
            id = "apariencia", label = "Apariencia",
            factory = function()
                return { widget = build_apariencia_tab(srv, theme, state) }
            end,
        },
        {
            id = "entorno", label = "Entorno",
            factory = function()
                return { widget = build_entorno_tab(srv, theme, state) }
            end,
        },
        {
            id = "atajos", label = "Atajos",
            factory = function()
                return { widget = build_atajos_tab(srv, theme, state) }
            end,
        },
    }

    local tabbed = W.TabbedPanel.new {
        tabs = tabs,
        compact = false,
        theme = theme,
        spacing = 8,
    }

    local layout = W.Group.new {
        orientation = "vertical", spacing = 10, padding = 12,
        children = { { widget = tabbed, weight = 1 } },
    }

    log.info("config", "factory OK")
    return {
        widget = layout,
        start = function() log.info("config", "start") end,
        stop = function() end,
    }
end

return M
