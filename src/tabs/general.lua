-- Tab Recursos -> General. Barras CPU/RAM/GPU/SWAP + temps embebido.

local W         = require("lib.widgets")
local F         = require("lib.helpers.format")
local D_cpu     = require("lib.data.cpu")
local D_ram     = require("lib.data.ram")
local D_gpu     = require("lib.data.gpu")
local temps_mod = require("tabs.temps")

local M = {}

function M.new(srv, theme)
    local Config = require("lib.data.config")
    local anim_values = Config.get_anim_opts().values
    local temps_tab = temps_mod.new(srv, theme, { compact = true })

    local bars = W.BarRow.new {
        left_width = 60, pct_width = 44, detail_width = 150,
        row_height = 20, warn_at = 0.7, crit_at = 0.9,
        bar_color = theme.telemetry.cpu or theme.accent,
        bar_bg = theme.separator,
        rows = {
            { id = "cpu",  label = "CPU",  color = theme.telemetry.cpu },
            { id = "ram",  label = "RAM",  color = theme.telemetry.ram },
            { id = "gpu",  label = "GPU",  color = theme.telemetry.gpu },
            { id = "swap", label = "SWAP", color = theme.telemetry.battery },
        },
    }

    local bars_card = W.Card.new {
        title = nil,
        content = bars,
        padding = 14,
        bg = theme.bg_card_rgb,
        border = theme.separator_rgb,
    }

    -- Compact: no envolvemos temps en otra card con titulo, va
    -- directo debajo de las barras.
    local layout = W.Group.new {
        orientation = "vertical",
        spacing = 8,
        children = {
            { widget = bars_card,          weight = 0 },
            { widget = temps_tab.widget,   weight = 1 },
        },
    }

    local function refresh()
        -- set_animated si anim_values; si no, set normal.
        local setf = anim_values and function(id, data)
            bars:set_animated(id, data, 500)
        end or function(id, data)
            bars:set(id, data)
        end

        local c = D_cpu.sample()
        setf("cpu", {
            pct = c.usage,
            detail = string.format("%.0f MHz · %d°C", c.freq, c.temp),
        })

        local r = D_ram.sample()
        setf("ram", {
            pct = r.pct,
            detail = F.mb(r.used) .. " / " .. F.mb(r.total),
        })

        local g = D_gpu.status()
        if g then
            setf("gpu", {
                pct = g.render / 100,
                detail = string.format("%.0f MHz · %.2f W", g.freq, g.power),
            })
        else
            bars:set_empty("gpu", "sin servicio")
        end

        if r.swap_total > 0 then
            setf("swap", {
                pct = r.swap_pct,
                detail = F.mb(r.swap_used) .. " / " .. F.mb(r.swap_total),
            })
        else
            bars:set_empty("swap", "sin swap")
        end
    end

    local timer

    return {
        widget = layout,
        start = function()
            D_cpu.reset()
            refresh()
            refresh()
            if temps_tab.start then temps_tab.start() end
            timer = srv:add_timer(2000, refresh)
        end,
        stop = function()
            if timer then timer:cancel(); timer = nil end
            if temps_tab.stop then temps_tab.stop() end
        end,
    }
end

return M
