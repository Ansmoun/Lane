-- Sub-tab Registro: totales hoy/semana/mes + por interfaz.

local W = require("lib.widgets")
local F = require("lib.helpers.format")
local D = require("lib.data.net")

local M = {}

function M.new(srv, theme)
    local C_RX = theme.telemetry.internet or "#83a598"
    local C_TX = theme.telemetry.cpu or "#8ec07c"

    local function stat_card(id, title)
        local rx = W.Text.new {
            text = "0 B", font = "DejaVu Sans Bold 11",
            align = "center", valign = "center",
        }
        local tx = W.Text.new {
            text = "0 B", font = "DejaVu Sans 9",
            align = "center", valign = "center",
        }
        local inner = W.Group.new {
            orientation = "vertical", spacing = 4,
            children = { rx, tx },
        }
        local card = W.Card.new {
            title = title, content = inner,
            padding = 10,
            bg = theme.bg_card_rgb,
            border = theme.separator_rgb,
        }
        return { widget = card, rx = rx, tx = tx }
    end

    local hoy    = stat_card("hoy",    "Hoy")
    local semana = stat_card("semana", "Semana")
    local mes    = stat_card("mes",    "Mes")

    local NUM_ROWS = 6
    local net_rows = {}
    local rows_group = W.Group.new {
        orientation = "vertical", spacing = 4, children = {},
    }

    for i = 1, NUM_ROWS do
        local lbl = W.Text.new {
            text = "", font = "DejaVu Sans 9",
            r = 0.55, g = 0.55, b = 0.60,
            align = "left", valign = "center",
        }
        local val = W.Text.new {
            text = "", font = "DejaVu Sans 9",
            align = "right", valign = "center",
        }
        local row = W.Group.new {
            orientation = "horizontal",
            children = {
                { widget = lbl, weight = 1 },
                { widget = val, weight = 1 },
            },
        }
        net_rows[i] = { lbl = lbl, val = val }
        rows_group:add(row)
    end

    local list_card = W.Card.new {
        title = "Total por interfaz (mes)",
        content = rows_group,
        padding = 10,
        bg = theme.bg_card_rgb,
        border = theme.separator_rgb,
    }

    local stat_row = W.Group.new {
        orientation = "horizontal", spacing = 10,
        children = { hoy.widget, semana.widget, mes.widget },
    }

    local layout = W.Group.new {
        orientation = "vertical", spacing = 10,
        children = {
            { widget = stat_row,  weight = 0 },
            { widget = list_card, weight = 1 },
        },
    }

    local function set_stat(stat, data)
        local r1, g1, b1 = unpack(theme.accent_rgb)
        stat.rx:set_text("↓ " .. F.bytes(data.rx))
        stat.rx:set_color(r1, g1, b1)
        stat.tx:set_text("↑ " .. F.bytes(data.tx))
    end

    local function refresh()
        local s = D.traffic_summary()
        set_stat(hoy,    s.hoy)
        set_stat(semana, s.semana)
        set_stat(mes,    s.mes)

        local list = {}
        for k, v in pairs(s.mes.by_net or {}) do
            table.insert(list, { key = k, rx = v.rx, tx = v.tx })
        end
        table.sort(list, function(a, b) return a.rx > b.rx end)

        for i = 1, NUM_ROWS do
            local item = list[i]
            if item then
                net_rows[i].lbl:set_text(item.key)
                net_rows[i].val:set_text(string.format("↓ %s  ↑ %s",
                    F.bytes(item.rx), F.bytes(item.tx)))
            else
                net_rows[i].lbl:set_text("")
                net_rows[i].val:set_text("")
            end
        end
    end

    local t

    return {
        widget = layout,
        start = function()
            refresh()
            t = srv:add_timer(5000, refresh)
        end,
        stop = function() if t then t:cancel(); t = nil end end,
    }
end

return M
