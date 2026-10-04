-- Tab Launcher: buscador de apps + comandos.

local W = require("lib.widgets")
local G = require("lib.helpers.graphics")
local cairo = require("lib.cairo")
local pango = require("lib.pango")
local svg = require("lib.svg")
local D = require("lib.data.launcher")

local M = {}

local ROW_H = 52

function M.new(srv, theme)
    local st = {
        query = "",
        results = {},
        selected = 1,
    }

    -- Forward declarations (los closures internos los necesitan)
    local input
    local list

    list = W.ScrollView.new {
        row_height = ROW_H,
        bg_color = nil,
        min_width = 400,
        min_height = ROW_H * 4,
        on_click = function(item)
            if item then
                D.execute(item)
                if list.window then list.window:close("launcher ejecutado") end
            end
        end,
    }

    local icon_surface_cache = {}

    local function get_icon_surface(path)
        if not path then return nil end
        local s = icon_surface_cache[path]
        if s ~= nil then return s or nil end
        local ext = (path:match("%.([%w]+)$") or ""):lower()
        local surface
        if ext == "svg" then
            surface = svg.load(path)
        else
            surface = cairo.load_png_cached(path)
        end
        icon_surface_cache[path] = surface or false
        return surface
    end

    list.draw_row = function(cr, item, idx, y, rh, width, hover)
        if not item then return end
        local is_sel = (idx == st.selected)

        if is_sel then
            local r, g, b = G.hex_to_rgba(theme.accent or "#8ec07c")
            cairo.set_rgba(cr, r, g, b, 0.20)
            cairo.rectangle(cr, 0, y, width, rh); cairo.fill(cr)
            cairo.set_rgb(cr, r, g, b)
            cairo.rectangle(cr, 2, y + 10, 3, rh - 20)
            cairo.fill(cr)
        elseif hover then
            local r, g, b = G.hex_to_rgba(theme.separator or "#504945")
            cairo.set_rgba(cr, r, g, b, 0.30)
            cairo.rectangle(cr, 0, y, width, rh); cairo.fill(cr)
        end

        -- Icono
        local icon_size = 32
        local icon_x = 18
        local icon_y = y + (rh - icon_size) / 2
        local surface = get_icon_surface(item._icon_path)
        if surface then
            cairo.draw_surface(cr, surface, icon_x, icon_y, icon_size, icon_size)
        else
            local r, g, b = G.hex_to_rgba(theme.separator or "#504945")
            cairo.set_rgba(cr, r, g, b, 0.6)
            cairo.rounded_rect(cr, icon_x, icon_y, icon_size, icon_size, 7)
            cairo.fill(cr)
            local letter = (item.name or "?"):sub(1, 1):upper()
            local r2, g2, b2 = G.hex_to_rgba(theme.fg_normal or "#ebdbb2")
            local lw = pango.measure(letter, "DejaVu Sans Bold 16")
            local _, lh = pango.measure(letter, "DejaVu Sans Bold 16")
            pango.draw_text(cr,
                icon_x + (icon_size - lw) / 2,
                icon_y + (icon_size - lh) / 2,
                letter, "DejaVu Sans Bold 16",
                { r = r2, g = g2, b = b2 })
        end

        -- Texto
        local text_x = icon_x + icon_size + 16
        local text_w = width - text_x - 18

        local title_color = is_sel and (theme.accent or "#8ec07c")
                            or (theme.fg_normal or "#ebdbb2")
        local r, g, b = G.hex_to_rgba(title_color)
        cairo.save(cr)
        cairo.rectangle(cr, text_x, y, text_w, rh / 2); cairo.clip(cr)
        pango.draw_text(cr, text_x, y + 8, item.name or "?", "DejaVu Sans 12",
            { r = r, g = g, b = b })
        cairo.restore(cr)

        local sub = item.comment or ""
        if item.kind == "command" then sub = "Ejecutar: " .. (item.name or "") end
        if sub ~= "" then
            if #sub > 90 then sub = sub:sub(1, 88) .. "..." end
            local r2, g2, b2 = G.hex_to_rgba(theme.muted or "#928374")
            cairo.save(cr)
            cairo.rectangle(cr, text_x, y + rh / 2, text_w, rh / 2); cairo.clip(cr)
            pango.draw_text(cr, text_x, y + 28, sub, "DejaVu Sans 10",
                { r = r2, g = g2, b = b2 })
            cairo.restore(cr)
        end

        local r3, g3, b3 = G.hex_to_rgba(theme.separator or "#504945")
        cairo.set_rgba(cr, r3, g3, b3, 0.25)
        cairo.rectangle(cr, 18, y + rh - 1, width - 36, 1)
        cairo.fill(cr)
    end

    local slider = W.ScrollBar.new {
        orientation = "vertical", width = 14, thickness = 3, handle_r = 4,
        step = ROW_H * 3,
        color_handle = theme.accent,
        color_track = theme.separator,
    }
    W.ScrollLink.link(list, slider)

    local rows_area = W.Group.new {
        orientation = "horizontal", spacing = 0,
        children = {
            { widget = list,   weight = 1 },
            { widget = slider, weight = 0 },
        },
    }

    local function scroll_to_selected()
        if not list.window then return end
        local off = list:get_offset()
        local vh  = list:getHeight()
        if vh <= 0 then return end
        local first   = math.floor(off / ROW_H)
        local visible = math.max(1, math.floor(vh / ROW_H))
        local last    = first + visible - 1
        local sel0    = st.selected - 1
        if sel0 < first then
            list:set_offset(sel0 * ROW_H)
        elseif sel0 > last then
            list:set_offset((sel0 - visible + 1) * ROW_H)
        end
    end

    local function move_selection(delta)
        local n = #st.results
        if n == 0 then return end
        local new_sel = st.selected + delta
        if new_sel < 1 then new_sel = 1 end
        if new_sel > n then new_sel = n end
        if new_sel == st.selected then return end
        st.selected = new_sel
        scroll_to_selected()
        if list.window then
            list.window:damage_all()
        end
    end

    -- Divider de 1px (separador entre la lista y el footer).
    local Area = require("lib.area")
    local Divider = setmetatable({}, { __index = Area })
    Divider.__index = Divider
    function Divider.new(color)
        local self = setmetatable(Area.new({}), Divider)
        self.color = color or "#242a35"
        self.min_h, self.max_h = 1, 1
        return self
    end
    function Divider:draw(cr)
        local r, g, b = G.hex_to_rgba(self.color)
        cairo.set_rgb(cr, r, g, b)
        cairo.rectangle(cr, self.x0, self.y0, self:getWidth(), 1)
        cairo.fill(cr)
    end

    input = W.TextInput.new {
        text = "",
        font = "DejaVu Sans 14",
        padding_x = 16, padding_y = 10,
        min_height = 52,
        color_bg = theme.bg_focus,
        color_border = nil,
        corner_radius = 22,
        color_text = theme.fg_rgb,
        placeholder = "Buscar aplicaciones...",
        color_placeholder = theme.muted_rgb,
        on_change = function(text) st.query = text or "" end,
        on_submit = function()
            input:set_focused(false)
            local e = st.results[st.selected]
            if e then
                D.execute(e)
                if input.window then input.window:close("lanzado") end
            end
        end,
        on_cancel = function()
            if input.window then input.window:close("escape") end
        end,
        on_up   = function() move_selection(-1) end,
        on_down = function() move_selection(1)  end,
    }
    input.opts.on_focus_request = function()
        input:set_focused(true)
    end

    local last_query = nil  -- nil fuerza el primer refresh

    -- Forward: refresh la llama pero se define mas abajo.
    local update_footer

    local function refresh()
        if st.query == last_query then return end
        last_query = st.query
        st.results = D.search(st.query)

        for _, e in ipairs(st.results) do
            if not e._icon_path and e.icon and e.icon ~= "" then
                e._icon_path = D.find_icon(e.icon)
            end
        end

        st.selected = 1
        list:set_items(st.results)
        list.offset = 0
        if update_footer then update_footer() end
        if list.window then list.window:damage_all() end
    end

    -- Input envuelto en un Group con padding, para que la pill
    -- flote con aire alrededor. padding = 10 uniforme.
    local input_wrap = W.Group.new {
        orientation = "horizontal",
        padding = 10,
        children = { { widget = input, weight = 1 } },
    }

    -- Footer: divider + contador de resultados alineado a la izquierda.
    local footer_count = W.Text.new {
        text = "0 resultados",
        font = "DejaVu Sans 10",
        align = "left", valign = "center",
        r = theme.muted_rgb[1],
        g = theme.muted_rgb[2],
        b = theme.muted_rgb[3],
    }

    update_footer = function()
        local n = #st.results
        local text = (n == 1) and "1 resultado" or (n .. " resultados")
        if st.query ~= "" and st.query:sub(1, 1) == ">" then
            text = "comando"
        end
        footer_count:set_text(text)
    end

    local divider = Divider.new(theme.separator)
    local footer_wrap = W.Group.new {
        orientation = "horizontal",
        padding = 6,
        children = { { widget = footer_count, weight = 1 } },
    }

    local layout = W.Group.new {
        orientation = "vertical", spacing = 0,
        children = {
            { widget = input_wrap, weight = 0 },
            { widget = rows_area,  weight = 1 },
            { widget = divider,    weight = 0 },
            { widget = footer_wrap, weight = 0 },
        },
    }

    -- Poblar los resultados AHORA, antes del primer draw.
    -- Sin esto, el primer super+d hace el trabajo en el timer de 80ms
    -- y el usuario ve "fondo -> 500ms -> lista".
    refresh()

    local poll

    return {
        widget = layout,
        focus = function()
            if input.window then
                input.window:set_focus_widget(input)
            end
        end,
        start = function()
            D.scan()
            input:set_focused(true)
            poll = srv:add_timer(80, refresh)
        end,
        stop = function()
            if poll then poll:cancel(); poll = nil end
            icon_surface_cache = {}
            svg.clear_cache()
        end,
    }
end

return M
