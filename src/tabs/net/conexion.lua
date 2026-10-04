-- Sub-tab Conexión: anillo RX, spark RX/TX, info, ping.

local W = require("lib.widgets")
local G = require("lib.helpers.graphics")
local F = require("lib.helpers.format")
local D_net  = require("lib.data.net")
local D_wifi = require("lib.data.wifi")
local D_ping = require("lib.data.ping")

local M = {}

function M.new(srv, theme)
    local Config = require("lib.data.config")
    local anim_values = Config.get_anim_opts().values
    local TIMEOUT = 2

    local ring = W.Ring.new {
        text = "0", sub = "RX",
        color = { 0.55, 0.85, 0.60 },
        raw_range = { 0, 100 },
        size = 160, thickness = 12,
    }

    local dsp = W.DualSpark.new {
        samples = 60,
        color_a = theme.telemetry.internet or "#83a598",
        color_b = theme.telemetry.cpu or "#8ec07c",
        fill_a = true,
        auto_max = true,
        floor_max = 10240,
        axis_width = 42, axis_format = "%dK",
        grid = true,
        min_width = 240, min_height = 120,
    }

    local info = W.KV.new {
        key_width = 90, row_height = 15, row_spacing = 4,
        rows = {
            { id = "tipo",  label = "Tipo" },
            { id = "iface", label = "Interfaz" },
            { id = "ip",    label = "IP" },
            { id = "gw",    label = "Gateway" },
            { id = "ssid",  label = "SSID" },
            { id = "rx",    label = "↓ RX" },
            { id = "tx",    label = "↑ TX" },
        },
    }

    -- Ping
    local ping_value = W.Text.new {
        text = "-- ms", font = "DejaVu Sans Bold 14",
        align = "center", valign = "center",
        r = 0.65, g = 0.65, b = 0.70,
    }
    local ping_loss = W.Text.new {
        text = "", font = "DejaVu Sans 9",
        align = "center", valign = "center",
        r = 0.55, g = 0.55, b = 0.60,
    }

    local ping_status = { active = false, host = D_ping.hosts().active }

    local ping_card_content = W.Group.new {
        orientation = "vertical", spacing = 4,
        children = { ping_value, ping_loss },
    }

    local ping_card = W.Card.new {
        title = "Ping · " .. ping_status.host,
        content = ping_card_content,
        padding = 10,
        bg = theme.bg_card_rgb,
        border = theme.separator_rgb,
    }

    -- Ring card
    local ring_card = W.Card.new {
        title = "Velocidad RX",
        content = ring,
        padding = 10,
        bg = theme.bg_card_rgb,
        border = theme.separator_rgb,
    }

    local info_card = W.Card.new {
        title = "Conexión",
        content = info,
        padding = 10,
        bg = theme.bg_card_rgb,
        border = theme.separator_rgb,
    }

    local dsp_card = W.Card.new {
        title = "Historia (60 s)",
        content = dsp,
        padding = 10,
        bg = theme.bg_card_rgb,
        border = theme.separator_rgb,
    }

    local layout = W.Group.new {
        orientation = "vertical", spacing = 10,
        children = {
            { widget = dsp_card, weight = 1 },
            { widget = W.Group.new {
                orientation = "horizontal", spacing = 10,
                children = {
                    { widget = ring_card, weight = 1 },
                    { widget = info_card, weight = 1 },
                    { widget = ping_card, weight = 1 },
                },
            }, weight = 1 },
        },
    }

    local prev_rx, prev_tx
    local ping_ok_hist = G.history(30)
    local ping_tick = 0

    local function refresh()
        local iface = D_wifi.iface()
        if iface ~= "" then
            local inf = D_net.iface_info(iface)
            info:set("tipo",  inf.tipo)
            info:set("iface", inf.iface)
            info:set("ip",    inf.ip)
            info:set("gw",    inf.gw)
            info:set("ssid",  inf.ssid)

            local b = D_net.iface_bytes(iface)
            if b then
                if not prev_rx then
                    prev_rx, prev_tx = b.rx, b.tx
                else
                    local rx_now = (b.rx - prev_rx) / TIMEOUT
                    local tx_now = (b.tx - prev_tx) / TIMEOUT
                    prev_rx, prev_tx = b.rx, b.tx

                    local pct = 0
                    if rx_now > 0 then
                        pct = math.min(100,
                            math.log(rx_now + 1) / math.log(10 * 1048576) * 100)
                    end
                    if anim_values then
                        ring:animate_to(pct,
                            F.speed(rx_now), "RX", 700)
                        dsp:push_a_animated(rx_now, 350)
                        dsp:push_b(tx_now)
                    else
                        ring:set_value(pct,
                            F.speed(rx_now), "RX")
                        dsp:push_a(rx_now)
                        dsp:push_b(tx_now)
                    end

                    info:set("rx", F.speed(rx_now))
                    info:set("tx", F.speed(tx_now))
                end
            end
        end

        -- Ping: lanzar y leer
        ping_tick = ping_tick + 1
        if ping_tick % 2 == 0 then
            D_ping.ping_async(ping_status.host)
        end
        local result = D_ping.ping_read(5)
        if result then
            if result.ms then
                ping_ok_hist:push(1)
                local color = theme.telemetry.cpu or "#8ec07c"
                if result.ms >= 300 then
                    color = theme.usage_crit
                elseif result.ms >= 100 then
                    color = theme.usage_warn
                end
                local r, g, b = G.hex_to_rgba(color)
                ping_value:set_text(string.format("%.0f ms", result.ms))
                ping_value:set_color(r, g, b)
            else
                ping_ok_hist:push(0)
                ping_value:set_text("-- ms")
                local r, g, b = G.hex_to_rgba(theme.usage_crit)
                ping_value:set_color(r, g, b)
            end
            local oks = ping_ok_hist:get()
            local total, lost = 0, 0
            for _, v in ipairs(oks) do
                total = total + 1
                if v == 0 then lost = lost + 1 end
            end
            local pct = total > 0 and math.floor(lost * 100 / total + 0.5) or 0
            local color = theme.muted
            if pct > 0 and pct < 5 then color = theme.accent
            elseif pct >= 5 then color = theme.usage_crit end
            local r, g, b = G.hex_to_rgba(color)
            ping_loss:set_text(pct .. "% loss")
            ping_loss:set_color(r, g, b)
        end
    end

    local t

    return {
        widget = layout,
        start = function()
            refresh()
            t = srv:add_timer(2000, refresh)
        end,
        stop = function() if t then t:cancel(); t = nil end end,
    }
end

return M
