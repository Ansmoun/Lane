-- Tab Buscar. Version sin drag. Header y filas comparten una
-- funcion pura compute_cols(avail). Sin estado compartido, sin
-- snap-back, sin "walking".

local W = require("lib.widgets")
local G = require("lib.helpers.graphics")
local F = require("lib.helpers.format")
local U = require("lib.helpers.util")
local cairo = require("lib.cairo")
local pango = require("lib.pango")
local D = require("lib.data.search")
local Area = require("lib.area")

local M = {}

local HOME = os.getenv("HOME") or ""

local ROOTS = {
    { label = "Inicio",   path = HOME },
    { label = "DATA",     path = "/mnt/DATA" },
    { label = "OptiOS",   path = "/mnt/OptiOS" },
    { label = "Todas",    path = nil,
      multi = string.format("%q %q %q", HOME, "/mnt/DATA", "/mnt/OptiOS") },
    { label = "Sistema",  path = "/", max_depth = 6 },
}

local TYPES = {
    { key = "all",   label = "Todo" },
    { key = "file",  label = "Archivos" },
    { key = "dir",   label = "Carpetas" },
    { key = "image", label = "Imágenes" },
    { key = "audio", label = "Audio" },
    { key = "video", label = "Vídeo" },
    { key = "doc",   label = "Docs" },
}

local SIZES = {
    { label = "Cualq.",  min = 0,       max = nil },
    { label = ">1KB",    min = 1024,    max = nil },
    { label = ">10KB",   min = 10240,   max = nil },
    { label = ">100KB",  min = 102400,  max = nil },
    { label = ">1MB",    min = 1048576, max = nil },
    { label = ">10MB",   min = 10485760, max = nil },
    { label = "<1MB",    min = 0,       max = 1048576 },
}

local DATES = {
    { label = "Cualq.", days = nil },
    { label = "24h",    days = 1 },
    { label = "Semana", days = 7 },
    { label = "Mes",    days = 30 },
    { label = "Año",    days = 365 },
}

-- Definicion de columnas
local COL_DEFS = {
    { key = "icon", label = "",        width = 20,  align = "left"  },
    { key = "name", label = "Nombre",  flex = 4,    align = "left"  },
    { key = "path", label = "Ruta",    flex = 6,    align = "left"  },
    { key = "size", label = "Tamaño",  width = 80,  align = "right" },
    { key = "date", label = "Fecha",   width = 90,  align = "right" },
}
local COL_GAP = 6
local COL_PAD = 8
local MIN_FLEX = 80

-- Funcion pura. Mismo avail → mismo reparto siempre.
local function compute_cols(avail)
    local fixed_sum, flex_total = 0, 0
    for _, c in ipairs(COL_DEFS) do
        if c.flex then
            flex_total = flex_total + c.flex
        else
            fixed_sum = fixed_sum + c.width
        end
    end

    local gaps = COL_GAP * (#COL_DEFS - 1)
    local used = fixed_sum + gaps + COL_PAD * 2
    local free = avail - used

    local out = {}
    if free < MIN_FLEX * 2 then
        -- No hay espacio: cada flex recibe su minimo y confiamos
        -- en que el clip recorte lo que sobra.
        for _, c in ipairs(COL_DEFS) do
            out[#out + 1] = c.flex and MIN_FLEX or c.width
        end
    else
        for _, c in ipairs(COL_DEFS) do
            if c.flex then
                out[#out + 1] = math.floor(free * c.flex / flex_total)
            else
                out[#out + 1] = c.width
            end
        end
    end
    return out
end

-- ═════════════════════════════════════════════════════════════
-- Header widget
-- ═════════════════════════════════════════════════════════════
local HeaderRow = setmetatable({}, { __index = Area })
HeaderRow.__index = HeaderRow

function HeaderRow.new(opts)
    local self = setmetatable(Area.new(opts), HeaderRow)
    self.theme = opts.theme
    self.get_sort = opts.get_sort
    self.on_sort = opts.on_sort
    self.right_reserve = opts.right_reserve or 0
    self.min_h = 22
    self.min_w = 100
    self.max_w = 10000
    return self
end

function HeaderRow:draw(cr)
    local avail = self:getWidth() - self.right_reserve
    if avail < 50 then return end
    local widths = compute_cols(avail)
    local sort = self.get_sort and self.get_sort() or { key = "", dir = "asc" }

    local x = self.x0 + COL_PAD
    for i, c in ipairs(COL_DEFS) do
        local active = (c.key == sort.key)
        local color = active and (self.theme.accent or "#8ec07c")
                      or (self.theme.muted or "#928374")
        local mark = ""
        if active then
            mark = (sort.dir == "desc") and "  v" or "  ^"
        end
        local text = c.label .. mark

        if text ~= "" then
            local r, g, b = G.hex_to_rgba(color)
            local font = "DejaVu Sans Bold 10"
            local tw = pango.measure(text, font)
            local tx = x
            if c.align == "right" then tx = x + widths[i] - tw end
            local _, th = pango.measure(text, font)
            local ty = self.y0 + (self:getHeight() - th) / 2
            pango.draw_text(cr, tx, ty, text, font, { r = r, g = g, b = b })
        end
        x = x + widths[i] + COL_GAP
    end
end

function HeaderRow:on_mouse_press(mx, my, button)
    if button ~= 1 then return end
    local avail = self:getWidth() - self.right_reserve
    if avail < 50 then return end
    local widths = compute_cols(avail)
    local x = COL_PAD
    for i, c in ipairs(COL_DEFS) do
        if mx >= x and mx < x + widths[i] then
            if self.on_sort then self.on_sort(c.key) end
            return
        end
        x = x + widths[i] + COL_GAP
    end
end

-- ═════════════════════════════════════════════════════════════
-- Ciclador
-- ═════════════════════════════════════════════════════════════
local function make_cycler(theme, label, get_idx, set_idx, list_ref, on_change)
    local title = W.Text.new {
        text = label, font = "DejaVu Sans 9",
        r = 0.55, g = 0.55, b = 0.60,
        align = "left", valign = "center",
    }
    local value = W.Text.new {
        text = list_ref()[get_idx()].label,
        font = "DejaVu Sans 10",
        r = 0.90, g = 0.90, b = 0.90,
        align = "center", valign = "center",
    }
    local btn_prev = W.Button.new {
        text = "<", flat = true, font = "DejaVu Sans 10",
        padding_x = 4, padding_y = 1,
    }
    local btn_next = W.Button.new {
        text = ">", flat = true, font = "DejaVu Sans 10",
        padding_x = 4, padding_y = 1,
    }
    local function cycle(delta)
        local list = list_ref()
        local idx = get_idx() + delta
        if idx < 1 then idx = #list end
        if idx > #list then idx = 1 end
        set_idx(idx)
        value:set_text(list[idx].label)
        if on_change then on_change() end
    end
    btn_prev.opts.on_click = function() cycle(-1) end
    btn_next.opts.on_click = function() cycle(1) end
    return W.Group.new {
        orientation = "horizontal", spacing = 3,
        children = {
            { widget = title,    weight = 0 },
            { widget = btn_prev, weight = 0 },
            { widget = value,    weight = 1 },
            { widget = btn_next, weight = 0 },
        },
    }
end

-- ═════════════════════════════════════════════════════════════
-- Tab
-- ═════════════════════════════════════════════════════════════
function M.new(srv, theme)
    local st = {
        query = "",
        root_idx = 1, type_idx = 1, size_idx = 1, date_idx = 1,
        sort_key = "name", sort_dir = "asc",
        case_sensitive = false,
        raw_items = {}, filtered = {},
        search_handle = nil,
    }

    local list
    local query_input
    local update_status
    local apply_filters_and_sort
    local trigger_search

    local header
    header = HeaderRow.new {
        theme = theme,
        right_reserve = 22,
        get_sort = function() return { key = st.sort_key, dir = st.sort_dir } end,
        on_sort = function(key)
            if st.sort_key == key then
                st.sort_dir = (st.sort_dir == "desc") and "asc" or "desc"
            else
                st.sort_key = key
                st.sort_dir = "asc"
            end
            apply_filters_and_sort()
            list:set_items(st.filtered)
            header:damage()
        end,
    }

    list = W.ScrollView.new {
        row_height = 20,
        bg_color = theme.bg_card,
        min_width = 400,
        min_height = 200,
        on_click = function(item)
            if not item then return end
            os.execute(string.format("(xdg-open %q >/dev/null 2>&1 &)", item.path))
        end,
        on_right_click = function(item)
            if not item then return end
            os.execute(string.format(
                "printf '%%s' %q | xclip -selection clipboard 2>/dev/null &",
                item.path))
        end,
    }

    list.draw_row = function(cr, item, idx, y, rh, width, hover)
        if not item then return end

        if hover then
            local r, g, b = G.hex_to_rgba(theme.separator or "#504945")
            cairo.set_rgba(cr, r, g, b, 0.35)
            cairo.rectangle(cr, 0, y, width, rh); cairo.fill(cr)
        elseif idx % 2 == 0 then
            local r, g, b = G.hex_to_rgba(theme.separator or "#504945")
            cairo.set_rgba(cr, r, g, b, 0.12)
            cairo.rectangle(cr, 0, y, width, rh); cairo.fill(cr)
        end

        -- Misma funcion pura que el header
        local widths = compute_cols(width)
        local x = COL_PAD
        local r, g, b

        -- Icono
        if item.is_dir then
            r, g, b = G.hex_to_rgba(theme.accent or "#8ec07c")
        else
            r, g, b = G.hex_to_rgba(theme.muted or "#928374")
        end
        cairo.set_rgb(cr, r, g, b)
        cairo.rectangle(cr, x + 4, y + rh / 2 - 3, 8, 6)
        cairo.fill(cr)
        x = x + widths[1] + COL_GAP

        -- Nombre
        r, g, b = G.hex_to_rgba(theme.fg_normal or "#ebdbb2")
        cairo.save(cr)
        cairo.rectangle(cr, x, y, widths[2], rh); cairo.clip(cr)
        pango.draw_text(cr, x, y + (rh - 12) / 2, item.name, "DejaVu Sans 10",
            { r = r, g = g, b = b })
        cairo.restore(cr)
        x = x + widths[2] + COL_GAP

        -- Ruta
        r, g, b = G.hex_to_rgba(theme.muted or "#928374")
        local parent = item.path:match("(.+)/[^/]+$") or "/"
        cairo.save(cr)
        cairo.rectangle(cr, x, y, widths[3], rh); cairo.clip(cr)
        pango.draw_text(cr, x, y + (rh - 12) / 2, parent, "DejaVu Sans 10",
            { r = r, g = g, b = b })
        cairo.restore(cr)
        x = x + widths[3] + COL_GAP

        -- Tamaño
        r, g, b = G.hex_to_rgba(theme.fg_normal or "#ebdbb2")
        local size_txt = item.is_dir and "-" or F.bytes(item.size)
        local sw = pango.measure(size_txt, "DejaVu Sans 10")
        cairo.save(cr)
        cairo.rectangle(cr, x, y, widths[4], rh); cairo.clip(cr)
        pango.draw_text(cr, x + widths[4] - sw, y + (rh - 12) / 2, size_txt,
            "DejaVu Sans 10", { r = r, g = g, b = b })
        cairo.restore(cr)
        x = x + widths[4] + COL_GAP

        -- Fecha
        r, g, b = G.hex_to_rgba(theme.muted or "#928374")
        local date_txt = item.is_dir and "-" or os.date("%Y-%m-%d", item.mtime or 0)
        local dw = pango.measure(date_txt, "DejaVu Sans 10")
        cairo.save(cr)
        cairo.rectangle(cr, x, y, widths[5], rh); cairo.clip(cr)
        pango.draw_text(cr, x + widths[5] - dw, y + (rh - 12) / 2, date_txt,
            "DejaVu Sans 10", { r = r, g = g, b = b })
        cairo.restore(cr)
    end

    local slider = W.ScrollBar.new {
        orientation = "vertical", width = 16, thickness = 3, handle_r = 4,
        step = 60,
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

    query_input = W.TextInput.new {
        text = "",
        font = "DejaVu Sans 10",
        padding_x = 6, padding_y = 4,
        color_bg = nil,
        color_border = theme.separator,
        corner_radius = 3,
        on_change = function(text) st.query = U.trim(text or "") end,
        on_submit = function()
            query_input:set_focused(false)
            trigger_search()
        end,
        on_cancel = function()
            query_input:set_text("")
            st.query = ""
            query_input:set_focused(false)
        end,
    }
    query_input.opts.on_focus_request = function()
        query_input:set_focused(true)
    end

    local btn_search = W.Button.new {
        text = "Buscar", flat = true, font = "DejaVu Sans 10",
        padding_x = 8, padding_y = 4,
        color_text = { 0.55, 0.85, 0.60 },
    }
    local case_btn = W.Button.new {
        text = "Aa", flat = true, font = "DejaVu Sans 10",
        padding_x = 6, padding_y = 3,
    }
    local status = W.Text.new {
        text = "", font = "DejaVu Sans 9",
        r = 0.55, g = 0.55, b = 0.60,
        align = "left", valign = "center",
    }

    local root_cycler = make_cycler(theme, "En",
        function() return st.root_idx end,
        function(i) st.root_idx = i end,
        function() return ROOTS end,
        function() if st.query ~= "" then trigger_search() end end)

    local type_cycler = make_cycler(theme, "Tipo",
        function() return st.type_idx end,
        function(i) st.type_idx = i end,
        function() return TYPES end,
        function() if st.query ~= "" then trigger_search() end end)

    local size_cycler = make_cycler(theme, "Tam",
        function() return st.size_idx end,
        function(i) st.size_idx = i end,
        function() return SIZES end,
        function()
            apply_filters_and_sort()
            list:set_items(st.filtered)
            update_status()
        end)

    local date_cycler = make_cycler(theme, "Fecha",
        function() return st.date_idx end,
        function(i) st.date_idx = i end,
        function() return DATES end,
        function()
            apply_filters_and_sort()
            list:set_items(st.filtered)
            update_status()
        end)

    apply_filters_and_sort = function()
        local size_def = SIZES[st.size_idx]
        local date_def = DATES[st.date_idx]
        local now = os.time()

        local filtered = {}
        for _, item in ipairs(st.raw_items) do
            local keep = true
            if not item.is_dir then
                if size_def.min and size_def.min > 0 and item.size < size_def.min then
                    keep = false
                end
                if size_def.max and item.size > size_def.max then
                    keep = false
                end
                if keep and date_def.days then
                    local cutoff = now - date_def.days * 86400
                    if (item.mtime or 0) < cutoff then keep = false end
                end
            end
            if keep then filtered[#filtered + 1] = item end
        end

        table.sort(filtered, function(a, b)
            local va, vb
            if st.sort_key == "name" then
                va, vb = a.name:lower(), b.name:lower()
            elseif st.sort_key == "size" then
                va, vb = a.size or 0, b.size or 0
            elseif st.sort_key == "date" then
                va, vb = a.mtime or 0, b.mtime or 0
            elseif st.sort_key == "path" then
                va, vb = a.path:lower(), b.path:lower()
            else
                va, vb = a.name:lower(), b.name:lower()
            end
            if st.sort_dir == "asc" then return va < vb end
            return va > vb
        end)

        st.filtered = filtered
    end

    update_status = function()
        if st.query == "" then
            status:set_text("")
            return
        end
        local total = #st.raw_items
        local shown = #st.filtered
        if total == 0 then
            status:set_text("Sin resultados")
        elseif shown == total then
            status:set_text(string.format("%d resultado%s",
                total, total == 1 and "" or "s"))
        else
            status:set_text(string.format("%d de %d (filtros)", shown, total))
        end
    end

    trigger_search = function()
        if st.search_handle then
            st.search_handle:cancel()
            st.search_handle = nil
        end
        if st.query == "" then
            st.raw_items = {}
            st.filtered = {}
            list:set_items({})
            update_status()
            return
        end

        local root = ROOTS[st.root_idx]
        local type_key = TYPES[st.type_idx].key
        status:set_text("Buscando...")

        D.search(srv, st.query, root.path, type_key, st.case_sensitive,
                 root.multi, root.max_depth, function(items)
            st.raw_items = items or {}
            apply_filters_and_sort()
            list:set_items(st.filtered)
            update_status()
        end)
    end

    btn_search.opts.on_click = function() trigger_search() end

    case_btn.opts.on_click = function()
        st.case_sensitive = not st.case_sensitive
        case_btn:set_text(st.case_sensitive and "[Aa]" or "Aa")
        if st.query ~= "" then trigger_search() end
    end

    local filter_bar = W.Group.new {
        orientation = "horizontal", spacing = 10, padding = 6,
        children = {
            { widget = root_cycler, weight = 1 },
            { widget = type_cycler, weight = 1 },
            { widget = size_cycler, weight = 1 },
            { widget = date_cycler, weight = 1 },
        },
    }
    local query_bar = W.Group.new {
        orientation = "horizontal", spacing = 6, padding = 6,
        children = {
            { widget = query_input, weight = 1 },
            { widget = case_btn,    weight = 0 },
            { widget = btn_search,  weight = 0 },
        },
    }
    local status_bar = W.Group.new {
        orientation = "horizontal", spacing = 6, padding = 6,
        children = { { widget = status, weight = 1 } },
    }

    local layout = W.Group.new {
        orientation = "vertical", spacing = 4, padding = 10,
        children = {
            { widget = query_bar,  weight = 0 },
            { widget = filter_bar, weight = 0 },
            { widget = status_bar, weight = 0 },
            { widget = header,     weight = 0 },
            { widget = rows_area,  weight = 1 },
        },
    }

    return {
        widget = layout,
        start = function() end,
        stop = function()
            if st.search_handle then st.search_handle:cancel() end
        end,
    }
end

return M
