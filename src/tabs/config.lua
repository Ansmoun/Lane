-- Tab Configuración: sidebar + contenido + status.
--
-- Estructura del sidebar:
--   Apariencia          (header, no clickeable)
--     Paleta            dropdown con preview de swatches
--     Barra             radio group con 9 estilos
--     Wallpaper         ruta + aplicar
--     Animaciones       master + 3 sub + hz + duración
--   Launcher            posición
--   Atajos              abrir sxhkdrc
--   Sistema             recargar daemons, reiniciar sesión

local W = require("lib.widgets")
local U = require("lib.helpers.util")
local D = require("lib.data.config")
local log = require("lib.log")
local thumbs = require("lib.thumbs")

local M = {}

local HOME = os.getenv("HOME") or "."

-- ── Helpers de layout.lua ─────────────────────────────────────────

local function find_layout()
    for _, p in ipairs({ "layout.lua", HOME .. "/.config/lane/layout.lua" }) do
        local f = io.open(p, "r")
        if f then f:close() return p end
    end
    return nil
end

local function read_layout_style()
    local p = find_layout()
    if not p then return nil end
    local f = io.open(p, "r"); if not f then return nil end
    local c = f:read("*a"); f:close()
    return c:match('style%s*=%s*"([^"]*)"')
end

local function update_layout_style(style)
    local p = find_layout()
    if not p then return false, "layout.lua no encontrado" end
    local f = io.open(p, "r"); if not f then return false, "no se puede leer" end
    local c = f:read("*a"); f:close()
    local new_c, n = c:gsub('style%s*=%s*"[^"]*"',
        string.format('style     = "%s"', style), 1)
    if n == 0 then
        new_c = c:gsub("return%s*{",
            string.format('return {\n    style     = "%s",', style), 1)
    end
    local w = io.open(p, "w"); if not w then return false, "no se puede escribir" end
    w:write(new_c); w:close()
    return true
end

-- ── Helpers de UI ─────────────────────────────────────────────────

local function muted(T, text, font)
    return W.Text.new {
        text = text, font = font or "DejaVu Sans 10",
        r = T.muted_rgb[1], g = T.muted_rgb[2], b = T.muted_rgb[3],
        align = "left", valign = "center",
    }
end

local function section_header(T, text)
    return W.Text.new {
        text = text, font = "DejaVu Sans Bold 13",
        r = T.accent_rgb[1], g = T.accent_rgb[2], b = T.accent_rgb[3],
        align = "left", valign = "center",
    }
end

local function spacer(h)
    return W.Text.new { text = "", font = "DejaVu Sans 1",
        min_width = 1, min_height = h or 8 }
end

local function row(T, label, control)
    return W.Group.new {
        orientation = "horizontal", spacing = 12,
        children = {
            { widget = muted(T, label), weight = 1 },
            { widget = control,        weight = 0 },
        },
    }
end

local function column(children, spacing, padding)
    return W.Group.new {
        orientation = "vertical",
        spacing = spacing or 10,
        padding = padding or 18,
        children = children,
    }
end

-- ── Controles genéricos ───────────────────────────────────────────

local function make_button(T, text, on_click, opts)
    opts = opts or {}
    return W.Button.new {
        text = text,
        font = opts.font or "DejaVu Sans 10",
        flat = opts.flat ~= false,
        padding_x = opts.padding_x or 12,
        padding_y = opts.padding_y or 6,
        corner_radius = opts.corner_radius or 5,
        color_hover = T.bg_focus_rgb,
        color_text = opts.color_text or T.fg_rgb,
        min_width = opts.min_width,
        on_click = on_click,
    }
end

local function make_toggle(T, getter, setter)
    local btn = make_button(T, getter() and "Activado" or "Desactivado", nil,
        { min_width = 110 })
    btn.opts.on_click = function()
        local v = not getter()
        setter(v)
        btn:set_text(v and "Activado" or "Desactivado")
    end
    return btn
end

local function make_numeric(T, getter, setter, min, max, width)
    local input = W.TextInput.new {
        text = tostring(getter()),
        font = "DejaVu Sans 10",
        padding_x = 8, padding_y = 4,
        color_bg = T.bg_card,
        color_border = T.separator,
        color_text = T.fg_rgb,
        color_cursor = T.accent_rgb,
        corner_radius = 4,
        min_width = width or 60,
        min_height = 26,
        on_submit = function(text)
            input:set_focused(false)
            local n = tonumber(U.trim(text or ""))
            if not n or n < min or n > max then
                input:set_text(tostring(getter()))
                return
            end
            n = math.floor(n)
            setter(n)
            input:set_text(tostring(n))
        end,
        on_cancel = function()
            input:set_text(tostring(getter()))
            input:set_focused(false)
        end,
    }
    input.opts.on_focus_request = function() input:set_focused(true) end
    return input
end

-- ── Sección: Paleta ───────────────────────────────────────────────

local function build_paleta(T, state, set_status, apply_palette)
    -- item list del dropdown, con el id = nombre de paleta
    local items = {}
    for _, name in ipairs(state.palettes_list) do
        items[#items + 1] = { id = name, label = name }
    end

    -- Dibujar un mini preview de swatches para cada item
    local function draw_preview(cr, item, x, y, w, h)
        local path = state.palettes_dir .. "/" .. item.id .. ".lua"
        local f = io.open(path, "r")
        if not f then return end
        local chunk = loadfile(path)
        f:close()
        if not chunk then return end
        local ok, p = pcall(chunk)
        if not ok or not p or not p.colors then return end
        local G = require("lib.helpers.graphics")
        local keys = { "bg", "bg_card", "accent", "fg", "urgent" }
        local n = #keys
        local sw = (w - (n - 1) * 2) / n
        for i, k in ipairs(keys) do
            local hex = p.colors[k] or (p.semantic and p.semantic[k])
            if hex then
                local r, g, b = G.hex_to_rgba(hex)
                require("lib.cairo").set_rgb(cr, r, g, b)
                require("lib.cairo").rounded_rect(
                    cr, x + (i - 1) * (sw + 2), y, sw, h, 3)
                require("lib.cairo").fill(cr)
            end
        end
    end

    local dd = W.Dropdown.new {
        items = items,
        selected = state.pending.palette,
        theme = T,
        row_h = 34,
        draw_preview = draw_preview,
        on_select = function(id)
            state.pending.palette = id
            apply_palette(id)
        end,
    }

    return column({
        { widget = section_header(T, "Paleta"), weight = 0 },
        { widget = muted(T,
            "Colores base del entorno. Se aplica en caliente."), weight = 0 },
        { widget = dd, weight = 0 },
    }, 10, 18)
end

-- ── Sección: Barra ────────────────────────────────────────────────

local BAR_STYLES = {
    { id = "dock",        label = "Dock (flotante abajo)" },
    { id = "arrow",       label = "Arrow (clásica)" },
    { id = "minimal",     label = "Minimal (sin fondo)" },
    { id = "island",      label = "Island (pastillas)" },
    { id = "underline",   label = "Underline (subrayado)" },
    { id = "glyph",       label = "Glyph (separador │)" },
    { id = "glyph_thick", label = "Glyph thick (separador ┃)" },
    { id = "gap",         label = "Gap (espacios)" },
    { id = "none",        label = "None (todo pegado)" },
}

local function build_barra(T, state, set_status)
    local rg = W.RadioGroup.new {
        items = BAR_STYLES,
        selected = state.current_style,
        theme = T,
        row_h = 32,
        on_select = function(id)
            state.current_style = id
            local ok, err = update_layout_style(id)
            if ok then
                os.execute("echo 'style " .. id .. "' > /tmp/lane-bar.cmd")
                set_status("Estilo: " .. id, false)
            else
                set_status("Error: " .. tostring(err), true)
            end
        end,
    }

    return column({
        { widget = section_header(T, "Barra"), weight = 0 },
        { widget = muted(T,
            "Forma en que se dibujan separadores y fondo. Se aplica en caliente."),
          weight = 0 },
        { widget = rg, weight = 0 },
    }, 10, 18)
end

-- ── Sección: Wallpaper ────────────────────────────────────────────

local WALLPAPER_MODES = {
    { id = "cover",   label = "Cover (llenar, recortar)" },
    { id = "contain", label = "Contain (entera, bandas)" },
    { id = "stretch", label = "Stretch (estirar)" },
    { id = "center",  label = "Center (tamaño nativo)" },
}

local function build_wallpaper(T, state, set_status, apply_wallpaper)
    local cairo = require("lib.cairo")

    -- Preview grande del wallpaper actual (contain).
    local preview_surf = nil
    if state.wallpaper_path then
        local thumb = thumbs.ensure(state.wallpaper_path, 480)
        if thumb then preview_surf = cairo.load_png_cached(thumb) end
    end

    local preview_widget
    if preview_surf then
        preview_widget = W.Icon.new {
            surface = preview_surf,
            fit = "contain",
            min_width = 200, min_height = 260,
        }
    else
        preview_widget = W.Text.new {
            text = "(sin preview)",
            font = "DejaVu Sans 11",
            r = T.muted_rgb[1], g = T.muted_rgb[2], b = T.muted_rgb[3],
            align = "center", valign = "center",
            min_height = 260,
        }
    end

    local preview_box = W.Group.new {
        orientation = "horizontal", spacing = 0,
        children = { { widget = preview_widget, weight = 1 } },
    }
    preview_box.min_h = 280
    preview_box.max_h = 280

    -- TextInput con la ruta actual + botón Aplicar.
    local path_input
    path_input = W.TextInput.new {
        text = state.wallpaper_path or "",
        font = "DejaVu Sans Mono 10",
        padding_x = 8, padding_y = 4,
        color_bg = T.bg_card,
        color_border = T.separator,
        color_text = T.fg_rgb,
        color_cursor = T.accent_rgb,
        corner_radius = 4,
        min_height = 30,
        min_width = 200,
        on_submit = function(text)
            path_input:set_focused(false)
            local p = (text or ""):gsub("^%s+", ""):gsub("%s+$", "")
            if p == "" then return end
            state.wallpaper_path = p
            apply_wallpaper(p, state.wallpaper_mode)
        end,
        on_cancel = function()
            path_input:set_text(state.wallpaper_path or "")
            path_input:set_focused(false)
        end,
    }
    path_input.opts.on_focus_request = function()
        path_input:set_focused(true)
    end

    local btn_apply = make_button(T, "Aplicar", function()
        local p = path_input:get_text():gsub("^%s+", ""):gsub("%s+$", "")
        if p == "" then return end
        state.wallpaper_path = p
        apply_wallpaper(p, state.wallpaper_mode)
    end)

    local btn_open = make_button(T, "Examinar", function()
        local dir = (state.wallpaper_path or ""):match("(.+)/[^/]+$") or HOME
        os.execute("(xdg-open '" .. dir .. "') >/dev/null 2>&1 &")
    end)

    -- Dropdown de modo con 4 items visibles.
    local mode_items = {}
    for _, m in ipairs(WALLPAPER_MODES) do
        mode_items[#mode_items + 1] = { id = m.id, label = m.label }
    end
    local mode_dd = W.Dropdown.new {
        items = mode_items,
        selected = state.wallpaper_mode,
        theme = T,
        row_h = 30,
        visible_rows = 4,
        on_select = function(id)
            state.wallpaper_mode = id
            D.set("wallpaper_mode", id)
            apply_wallpaper(state.wallpaper_path, id)
        end,
    }

    return column({
        { widget = section_header(T, "Wallpaper"), weight = 0 },
        { widget = preview_box, weight = 0 },

        { widget = spacer(8), weight = 0 },
        { widget = muted(T, "Ruta de la imagen"), weight = 0 },
        { widget = path_input, weight = 0 },
        { widget = W.Group.new {
            orientation = "horizontal", spacing = 8,
            children = {
                { widget = btn_apply, weight = 0 },
                { widget = btn_open,  weight = 0 },
            },
        }, weight = 0 },

        { widget = spacer(10), weight = 0 },
        { widget = muted(T, "Modo de relleno"), weight = 0 },
        { widget = mode_dd, weight = 0 },
    }, 10, 18)
end

-- ── Sección: Animaciones ──────────────────────────────────────────

local function build_animaciones(T, state, set_status, apply_anim)
    local function toggle_anim(getter, setter)
        return make_toggle(T, getter, function(v)
            setter(v)
            apply_anim()
        end)
    end

    return column({
        { widget = section_header(T, "Animaciones"), weight = 0 },
        { widget = muted(T,
            "Efectos de transición del panel."), weight = 0 },
        { widget = row(T, "Animaciones (master)",
            toggle_anim(function() return state.pending.animate_panel end,
                function(v) state.pending.animate_panel = v end)), weight = 0 },
        { widget = row(T, "Cambio de tabs",
            toggle_anim(function() return state.pending.animate_tabs end,
                function(v) state.pending.animate_tabs = v end)), weight = 0 },
        { widget = row(T, "Entrada de widgets",
            toggle_anim(function() return state.pending.animate_widgets end,
                function(v) state.pending.animate_widgets = v end)), weight = 0 },
        { widget = row(T, "Cambios de valores",
            toggle_anim(function() return state.pending.animate_values end,
                function(v) state.pending.animate_values = v end)), weight = 0 },
        { widget = row(T, "Tasa (Hz)",
            make_numeric(T, function() return state.pending.anim_hz end,
                function(v) state.pending.anim_hz = v; apply_anim() end,
                1, 240, 70)), weight = 0 },
        { widget = row(T, "Duración (ms)",
            make_numeric(T, function() return state.pending.anim_duration end,
                function(v) state.pending.anim_duration = v; apply_anim() end,
                50, 2000, 80)), weight = 0 },
    }, 10, 18)
end

-- ── Sección: Launcher ─────────────────────────────────────────────

local function build_launcher(T, state, set_status)
    return column({
        { widget = section_header(T, "Launcher"), weight = 0 },
        { widget = muted(T,
            "Aplicación de búsqueda y ejecución. Se abre con super + d."),
          weight = 0 },
        { widget = spacer(8), weight = 0 },
        { widget = muted(T,
            "Configuración de posición y acoplamiento al dock: pendiente.\n" ..
            "Hoy el launcher se ancla encima del dock (8 px de separación)."),
          weight = 0 },
    }, 12, 18)
end

-- ── Sección: Atajos ───────────────────────────────────────────────

local function build_atajos(T, state, set_status)
    return column({
        { widget = section_header(T, "Atajos de teclado"), weight = 0 },
        { widget = muted(T,
            "El editor integrado está en desarrollo.\n" ..
            "Por ahora se abre sxhkdrc en el editor externo."), weight = 0 },
        { widget = make_button(T, "Abrir sxhkdrc", function()
            os.execute("(xdg-open " .. HOME .. "/.config/sxhkd/sxhkdrc) " ..
                ">/dev/null 2>&1 &")
        end), weight = 0 },
    }, 12, 18)
end

-- ── Sección: Sistema ──────────────────────────────────────────────

local function build_sistema(T, state, set_status)
    local function b(text, cmd, msg)
        return make_button(T, text, function()
            os.execute(cmd)
            set_status(msg or text, false)
        end)
    end

    return column({
        { widget = section_header(T, "Barra"), weight = 0 },
        { widget = W.Group.new {
            orientation = "horizontal", spacing = 8,
            children = {
                { widget = b("Recargar barra",
                    "echo reload > /tmp/lane-bar.cmd", "Barra recargada"),
                  weight = 0 },
                { widget = b("Barra a dock",
                    "echo 'style dock' > /tmp/lane-bar.cmd", "Estilo: dock"),
                  weight = 0 },
                { widget = b("Barra a arrow",
                    "echo 'style arrow' > /tmp/lane-bar.cmd", "Estilo: arrow"),
                  weight = 0 },
            },
        }, weight = 0 },

        { widget = spacer(10), weight = 0 },

        { widget = section_header(T, "Daemons"), weight = 0 },
        { widget = W.Group.new {
            orientation = "horizontal", spacing = 8,
            children = {
                { widget = b("Reiniciar launcher",
                    "(pkill -f 'apps/launcher.lua' 2>/dev/null; sleep 0.3; " ..
                    "cd /opt/lane 2>/dev/null || cd ~/proyectos/lane; " ..
                    "./run apps/launcher.lua > /tmp/lane-launcher.log 2>&1) &",
                    "Launcher reiniciado"), weight = 0 },
                { widget = b("Abrir /tmp", "(xdg-open /tmp) >/dev/null 2>&1 &"),
                  weight = 0 },
            },
        }, weight = 0 },

        { widget = spacer(10), weight = 0 },

        { widget = section_header(T, "Sesión"), weight = 0 },
        { widget = muted(T,
            "Reiniciar sesión cierra la sesión gráfica actual.\n" ..
            "Reiniciar sistema apaga la máquina."), weight = 0 },
        { widget = W.Group.new {
            orientation = "horizontal", spacing = 8,
            children = {
                { widget = b("Reiniciar sesión", "(bspc quit) >/dev/null 2>&1 &"),
                  weight = 0 },
                { widget = b("Reiniciar sistema",
                    "(loginctl reboot) >/dev/null 2>&1 &"), weight = 0 },
            },
        }, weight = 0 },
    }, 12, 18)
end

-- ── Sidebar ───────────────────────────────────────────────────────

local SIDEBAR = {
    { id = "hdr_apariencia", label = "Apariencia", header = true },
    { id = "paleta",         label = "Paleta",       indent = 10 },
    { id = "barra",          label = "Barra",        indent = 10 },
    { id = "wallpaper",      label = "Wallpaper",    indent = 10 },
    { id = "animaciones",    label = "Animaciones",  indent = 10 },
    { id = "launcher",       label = "Launcher" },
    { id = "atajos",         label = "Atajos" },
    { id = "sistema",        label = "Sistema" },
}

local DEFAULT_SECTION = "paleta"

-- ── M.new ─────────────────────────────────────────────────────────

function M.new(srv, theme)
    log.info("config", "factory inicio")

    local state = {
        pending = {
            palette         = D.get("palette") or "ayu",
            animate_panel   = D.get_bool("animate_panel", false),
            animate_tabs    = D.get_bool("animate_tabs",    true),
            animate_widgets = D.get_bool("animate_widgets", true),
            animate_values  = D.get_bool("animate_values",  true),
            anim_hz         = D.get_int("anim_hz", 30),
            anim_duration   = D.get_int("anim_duration", 300),
        },
        palettes_list   = D.list_palettes(),
        palettes_dir    = D.palettes_dir(),
        current_style   = read_layout_style() or "dock",
        wallpaper_path  = (os.getenv("LANE_WALLPAPER")
                          or os.getenv("LANETK_WALLPAPER")
                          or (HOME .. "/imagenes/wallpapers/98616585_p0_master1200.jpg")),
        wallpaper_mode  = D.get("wallpaper_mode") or "cover",
    }

    local status_label = W.Text.new {
        text = "", font = "DejaVu Sans 10",
        r = theme.muted_rgb[1], g = theme.muted_rgb[2], b = theme.muted_rgb[3],
        align = "left", valign = "center",
    }
    local status_bar = W.Group.new {
        orientation = "horizontal", spacing = 12, padding = 10,
        children = { { widget = status_label, weight = 1 } },
    }

    local _timer
    local function set_status(msg, is_error)
        if is_error then
            status_label:set_color(theme.urgent_rgb[1],
                theme.urgent_rgb[2], theme.urgent_rgb[3])
        else
            status_label:set_color(theme.muted_rgb[1],
                theme.muted_rgb[2], theme.muted_rgb[3])
        end
        status_label:set_text(msg)
        if _timer then _timer:cancel(); _timer = nil end
        _timer = srv:add_timer(2500, function()
            status_label:set_text("")
            _timer = nil
        end)
    end

    local function apply_palette(name)
        D.set("palette", name)
        local theme_mod = require("lib.theme")
        local path = theme_mod.palette_path(name)
        local ok, err = theme_mod.reload_in_place(theme, path)
        if ok then
            set_status("Paleta: " .. name, false)
        else
            set_status("Error paleta: " .. tostring(err), true)
        end
    end

    -- Aplicar wallpaper: relanzar el daemon con el path y modo.
    local function shq(s)
        return "'" .. s:gsub("'", [['"'"']]) .. "'"
    end

    local function apply_wallpaper(path, mode)
        if not path or path == "" then return end
        -- Resolver la raiz de LANE: preferir /opt/lane si existe.
        local root = "/opt/lane"
        local f = io.open(root .. "/run", "r")
        if not f then
            root = HOME .. "/proyectos/lane"
        else
            f:close()
        end
        -- pkill -f 'apps/wallpaper.lua' mataba al propio shell
        -- porque el cmdline del shell contiene el patron. Anclar
        -- el patron a ^luajit solo matchea al proceso daemon.
        local cmd = string.format(
            "pkill -f '^luajit apps/wallpaper.lua' 2>/dev/null; " ..
            "sleep 0.4; " ..
            "cd %s && " ..
            "setsid nohup ./run apps/wallpaper.lua %s %s " ..
            "> /tmp/lane-wallpaper.log 2>&1 < /dev/null &",
            shq(root), shq(path), shq(mode or "cover"))
        os.execute(cmd)
        set_status("Wallpaper: " .. (mode or "cover"), false)
    end

    local function apply_anim()
        D.set_bool("animate_panel",   state.pending.animate_panel)
        D.set_bool("animate_tabs",    state.pending.animate_tabs)
        D.set_bool("animate_widgets", state.pending.animate_widgets)
        D.set_bool("animate_values",  state.pending.animate_values)
        D.set_int("anim_hz", state.pending.anim_hz)
        D.set_int("anim_duration", state.pending.anim_duration)
        local anim = require("lib.anim")
        if anim.is_ready() then anim.set_fps(state.pending.anim_hz) end
        set_status("Animaciones actualizadas", false)
    end

    -- Sidebar items
    local sidebar_children = {}
    local items_by_id = {}
    local stack  -- forward declaration
    local function set_active_section(id)
        if type(id) ~= "string" or not items_by_id[id] then return end
        for _, item in pairs(items_by_id) do item:set_selected(false) end
        items_by_id[id]:set_selected(true)
        if stack then stack:set_active(id) end
    end

    for _, sec in ipairs(SIDEBAR) do
        local item = W.SidebarItem.new {
            id = sec.id, label = sec.label, theme = theme,
            header = sec.header, indent = sec.indent,
            on_click = function(id) set_active_section(id) end,
        }
        items_by_id[sec.id] = item
        sidebar_children[#sidebar_children + 1] = { widget = item, weight = 0 }
    end

    local sidebar = W.Group.new {
        orientation = "vertical",
        spacing = 2,
        padding = 10,
        min_width = 190,
        children = sidebar_children,
    }

    -- Content stack
    stack = W.Stack.new {}
    stack:add("paleta",      build_paleta(theme, state, set_status, apply_palette))
    stack:add("barra",       build_barra(theme, state, set_status))
    stack:add("wallpaper",   build_wallpaper(theme, state, set_status, apply_wallpaper))
    stack:add("animaciones", build_animaciones(theme, state, set_status, apply_anim))
    stack:add("launcher",    build_launcher(theme, state, set_status))
    stack:add("atajos",      build_atajos(theme, state, set_status))
    stack:add("sistema",     build_sistema(theme, state, set_status))

    items_by_id[DEFAULT_SECTION]:set_selected(true)
    stack:set_active(DEFAULT_SECTION)

    local vsep = W.Text.new { text = "", font = "DejaVu Sans 1",
        min_width = 1, min_height = 1 }

    local body = W.Group.new {
        orientation = "horizontal", spacing = 0,
        children = {
            { widget = sidebar, weight = 0 },
            { widget = vsep,    weight = 0 },
            { widget = stack,   weight = 1 },
        },
    }

    local root = W.Group.new {
        orientation = "vertical", spacing = 0,
        children = {
            { widget = body,       weight = 1 },
            { widget = status_bar, weight = 0 },
        },
    }

    log.info("config", "factory OK")
    return {
        widget = root,
        start = function() log.info("config", "start") end,
        stop = function()
            if _timer then _timer:cancel(); _timer = nil end
        end,
    }
end

return M
