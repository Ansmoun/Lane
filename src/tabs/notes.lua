-- Tab Notas: lista + detalle con editor externo.

local W = require("lib.widgets")
local G = require("lib.helpers.graphics")
local cairo = require("lib.cairo")
local pango = require("lib.pango")
local U = require("lib.helpers.util")
local D = require("lib.data.notes")

local M = {}

-- ── Row widget para la lista ─────────────────────────────────
local ListRow = setmetatable({}, { __index = W.Text })
ListRow.__index = ListRow

function ListRow.new(item, theme, on_click)
    local self = setmetatable(W.Text.new { text = "" }, ListRow)
    self.item = item
    self.theme = theme
    self.min_h = 44
    self.min_w = 200
    self.max_w = 10000
    return self
end

function ListRow:draw(cr)
    if self.hover then
        local r, g, b = G.hex_to_rgba(self.theme.separator or "#3c3836")
        cairo.set_rgba(cr, r, g, b, 0.35)
        cairo.rectangle(cr, self.x0, self.y0,
            self:getWidth(), self:getHeight())
        cairo.fill(cr)
    end

    local t = self.theme
    local item = self.item

    local check_col = item.done and t.muted or t.accent
    local r, g, b = G.hex_to_rgba(check_col)
    pango.draw_text(cr, self.x0 + 8, self.y0 + 6,
        item.done and "☑" or "☐", "DejaVu Sans 12",
        { r = r, g = g, b = b })

    local title_col = item.done and t.muted or t.fg_normal
    r, g, b = G.hex_to_rgba(title_col)
    pango.draw_text(cr, self.x0 + 30, self.y0 + 4,
        item.title or "", "DejaVu Sans 11",
        { r = r, g = g, b = b })

    if item.preview and item.preview ~= "" then
        r, g, b = G.hex_to_rgba(t.muted)
        pango.draw_text(cr, self.x0 + 30, self.y0 + 22,
            item.preview, "DejaVu Sans 9",
            { r = r, g = g, b = b })
    end

    -- separador
    r, g, b = G.hex_to_rgba(t.separator or "#3c3836")
    cairo.set_rgba(cr, r, g, b, 0.5)
    cairo.rectangle(cr, self.x0 + 8, self.y1 - 1, self:getWidth() - 16, 1)
    cairo.fill(cr)
end

function M.new(srv, theme, parent_win)
    D.migrate_legacy()

    local prompt_module = require("password_prompt")
    local prompt = prompt_module.new(srv, parent_win, theme)

    -- ── Lista (vista principal) ───────────────────────────────
    local function make_list_view()
        local list = W.ScrollView.new {
            row_height = 44,
            bg_color = theme.bg_card,
            min_width = 200,
            min_height = 200,
        }
        local sb = W.ScrollBar.new {
            orientation = "vertical",
            width = 14,
            thickness = 3,
            handle_r = 4,
            step = 60,
            color_handle = theme.accent,
            color_track = theme.separator,
        }
        W.ScrollLink.link(list, sb)

        local function refresh_list()
            local notes = D.list()
            list:set_items(notes)
        end

        list.opts.on_click = function(row_item, idx)
            -- row_item es lo que devolvió draw_row, aquí es la nota
            -- pero ScrollView no expone items directamente.
        end

        -- Sobreescribir el comportamiento: usar getByXY + draw_row
        list.draw_row = function(cr, item, idx, y, row_h, width, hover)
            -- dibujado inline
            if hover then
                local r, g, b = G.hex_to_rgba(theme.separator or "#3c3836")
                cairo.set_rgba(cr, r, g, b, 0.35)
                cairo.rectangle(cr, 0, y, width, row_h)
                cairo.fill(cr)
            end

            local r, g, b

            r, g, b = G.hex_to_rgba(item.done and theme.muted or theme.accent)
            pango.draw_text(cr, 8, y + 6,
                item.done and "☑" or "☐", "DejaVu Sans 12",
                { r = r, g = g, b = b })

            r, g, b = G.hex_to_rgba(item.done and theme.muted or theme.fg_normal)
            pango.draw_text(cr, 30, y + 4,
                item.title or "", "DejaVu Sans 11",
                { r = r, g = g, b = b })

            if item.preview and item.preview ~= "" then
                r, g, b = G.hex_to_rgba(theme.muted)
                pango.draw_text(cr, 30, y + 22,
                    item.preview, "DejaVu Sans 9",
                    { r = r, g = g, b = b })
            end

            r, g, b = G.hex_to_rgba(theme.separator or "#3c3836")
            cairo.set_rgba(cr, r, g, b, 0.5)
            cairo.rectangle(cr, 8, y + row_h - 1, width - 16, 1)
            cairo.fill(cr)
        end

        -- Handler de click: buscar la nota por índice
        list.on_click = function(item, idx)
            -- item es la tabla devuelta por ScrollView, que es la nota
            if item and item.path then
                show_detail(item.path)
            end
        end

        return { list = list, sb = sb, refresh = refresh_list }
    end

    -- ── Contenedor con lista + botones ────────────────────────
    local list_holder
    local holder = W.Group.new {
        orientation = "vertical",
        spacing = 6,
        padding = 10,
    }

    -- ── Acciones de lista ─────────────────────────────────────
    local function nueva_nota()
        prompt:show {
            title = "Nueva nota",
            mask = false,
            on_submit = function(text)
                if text and text ~= "" then
                    local path = D.create(text)
                    show_detail(path)
                end
            end,
        }
    end

    local function abrir_carpeta()
        os.execute(
            "(terminology -e micro " .. D.DIR .. " &) " ..
            "|| (x-terminal-emulator -e micro " .. D.DIR .. " &)")
    end

    -- ── Detalle ───────────────────────────────────────────────
    local function make_detail_view(path)
        local n = D.read(path)
        if not n then return nil end

        local detail_scroll = W.ScrollView.new {
            row_height = 18,
            bg_color = theme.bg_card,
            min_width = 200,
            min_height = 200,
        }
        local detail_sb = W.ScrollBar.new {
            orientation = "vertical",
            width = 14,
            thickness = 3,
            handle_r = 4,
            step = 90,
            color_handle = theme.accent,
            color_track = theme.separator,
        }
        W.ScrollLink.link(detail_scroll, detail_sb)

        -- Partir el body en líneas
        local lines = {}
        local body = n.body or ""
        for line in (body .. "\n"):gmatch("(.-)\n") do
            lines[#lines + 1] = { line = line }
        end
        if #lines == 0 then lines = { { line = "(nota vacía)" } } end
        detail_scroll:set_items(lines)

        detail_scroll.draw_row = function(cr, item, idx, y, rh, width)
            local r, g, b = G.hex_to_rgba(theme.fg_normal)
            pango.draw_text(cr, 4, y, item.line or "", "DejaVu Sans 10",
                { r = r, g = g, b = b })
        end

        -- Botones de cabecera
        local back_btn   = W.Button.new { text = "← Atrás", flat = true,
            font = "DejaVu Sans 10", padding_x = 6, padding_y = 3 }
        local toggle_btn = W.Button.new {
            text = n.done and "Marcar pendiente" or "Marcar hecha",
            flat = true, font = "DejaVu Sans 10",
            padding_x = 6, padding_y = 3,
        }
        local edit_btn   = W.Button.new { text = "Editar", flat = true,
            font = "DejaVu Sans 10", padding_x = 6, padding_y = 3 }
        local del_btn    = W.Button.new { text = "Eliminar", flat = true,
            font = "DejaVu Sans 10", padding_x = 6, padding_y = 3,
            color_text = { 0.90, 0.40, 0.40 } }

        back_btn.opts.on_click = function() show_list_view() end
        toggle_btn.opts.on_click = function()
            D.toggle_done(path)
            show_detail(path)
        end
        edit_btn.opts.on_click = function()
            os.execute("(terminology -e micro " .. path .. " &)")
        end
        del_btn.opts.on_click = function()
            D.delete(path)
            show_list_view()
        end

        local header = W.Group.new {
            orientation = "horizontal", spacing = 6,
            children = {
                { widget = back_btn,   weight = 0 },
                { widget = toggle_btn, weight = 0 },
                { widget = del_btn,    weight = 0 },
                { widget = edit_btn,   weight = 0 },
            },
        }

        local title = W.Text.new {
            markup = true,
            text = string.format('<span foreground="%s" weight="bold">%s</span>',
                n.done and theme.muted or theme.fg_normal, n.title or "?"),
            font = "DejaVu Sans Bold 13",
            align = "left",
            valign = "center",
        }

        return W.Group.new {
            orientation = "vertical", spacing = 6, padding = 10,
            children = {
                { widget = title,  weight = 0 },
                { widget = header, weight = 0 },
                { widget = W.Group.new {
                    orientation = "horizontal", spacing = 0,
                    children = {
                        { widget = detail_scroll, weight = 1 },
                        { widget = detail_sb,     weight = 0 },
                    },
                }, weight = 1 },
            },
        }
    end

    -- ── Cambio de vista ───────────────────────────────────────
    local function clear_holder()
        holder:clear()
    end

    function show_list_view()
        clear_holder()
        local lv = make_list_view()
        lv.refresh()

        local nueva = W.Button.new { text = "+ Nueva nota", flat = true,
            font = "DejaVu Sans 10", padding_x = 6, padding_y = 3,
            color_text = { 0.55, 0.85, 0.60 } }
        local abrir = W.Button.new { text = "Abrir carpeta", flat = true,
            font = "DejaVu Sans 10", padding_x = 6, padding_y = 3 }

        nueva.opts.on_click = nueva_nota
        abrir.opts.on_click = abrir_carpeta

        local actions = W.Group.new {
            orientation = "horizontal", spacing = 6,
            children = {
                { widget = nueva, weight = 0 },
                { widget = abrir, weight = 0 },
            },
        }

        holder:add(actions, 0)
        holder:add(W.Group.new {
            orientation = "horizontal", spacing = 0,
            children = {
                { widget = lv.list, weight = 1 },
                { widget = lv.sb,   weight = 0 },
            },
        }, 1)
        holder:invalidate_layout()
    end

    function show_detail(path)
        clear_holder()
        local dv = make_detail_view(path)
        if not dv then show_list_view(); return end
        holder:add(dv, 1)
        holder:invalidate_layout()
    end

    -- Arrancar con la lista
    show_list_view()

    return {
        widget = holder,
        start = function() end,
        stop = function() prompt:close() end,
    }
end

return M
