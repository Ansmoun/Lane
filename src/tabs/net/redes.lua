-- Sub-tab Redes: conexiones activas + WiFi + dispositivos.

local W = require("lib.widgets")
local U = require("lib.helpers.util")
local D_wifi = require("lib.data.wifi")
local D_disp = require("lib.data.dispositivos")

local M = {}

function M.new(srv, theme)
    -- Conexiones activas
    local NUM_ACTIVE = 2
    local active_rows = {}
    local active_group = W.Group.new {
        orientation = "vertical", spacing = 4, children = {},
    }
    for i = 1, NUM_ACTIVE do
        local type_tb  = W.Text.new {
            text = "", font = "DejaVu Sans 9",
            align = "left", valign = "center",
        }
        local iface_tb = W.Text.new {
            text = "", font = "DejaVu Sans 9",
            align = "left", valign = "center",
        }
        local ip_tb = W.Text.new {
            text = "", font = "DejaVu Sans 9",
            align = "right", valign = "center",
        }
        local row = W.Group.new {
            orientation = "horizontal",
            children = {
                { widget = type_tb,  weight = 0 },
                { widget = iface_tb, weight = 0 },
                { widget = ip_tb,    weight = 1 },
            },
        }
        active_rows[i] = { type = type_tb, iface = iface_tb, ip = ip_tb }
        active_group:add(row)
    end
    local active_card = W.Card.new {
        title = "Conectado ahora",
        content = active_group,
        padding = 10,
        bg = theme.bg_card_rgb,
        border = theme.separator_rgb,
    }

    -- WiFi disponibles
    local NUM_WIFI = 5
    local wifi_rows = {}
    local wifi_group = W.Group.new {
        orientation = "vertical", spacing = 4, children = {},
    }
    for i = 1, NUM_WIFI do
        local ssid_tb = W.Text.new {
            text = "", font = "DejaVu Sans 9",
            align = "left", valign = "center",
        }
        local info_tb = W.Text.new {
            text = "", font = "DejaVu Sans 9",
            r = 0.55, g = 0.55, b = 0.60,
            align = "right", valign = "center",
        }
        local row = W.Group.new {
            orientation = "horizontal",
            children = {
                { widget = ssid_tb, weight = 1 },
                { widget = info_tb, weight = 0 },
            },
        }
        wifi_rows[i] = { ssid = ssid_tb, info = info_tb }
        wifi_group:add(row)
    end
    local wifi_card = W.Card.new {
        title = "WiFi disponibles",
        content = wifi_group,
        padding = 10,
        bg = theme.bg_card_rgb,
        border = theme.separator_rgb,
    }

    -- Dispositivos
    local NUM_DISP = 6
    local disp_rows = {}
    local disp_group = W.Group.new {
        orientation = "vertical", spacing = 3, children = {},
    }
    for i = 1, NUM_DISP do
        local ip_tb  = W.Text.new {
            text = "", font = "DejaVu Sans 8",
            align = "left", valign = "center",
        }
        local mac_tb = W.Text.new {
            text = "", font = "DejaVu Sans 8",
            r = 0.55, g = 0.55, b = 0.60,
            align = "left", valign = "center",
        }
        local hn_tb = W.Text.new {
            text = "", font = "DejaVu Sans 8",
            r = 0.55, g = 0.55, b = 0.60,
            align = "left", valign = "center",
        }
        local seen_tb = W.Text.new {
            text = "", font = "DejaVu Sans 8",
            r = 0.55, g = 0.55, b = 0.60,
            align = "right", valign = "center",
        }
        local row = W.Group.new {
            orientation = "horizontal", spacing = 6,
            children = {
                { widget = ip_tb,   weight = 0 },
                { widget = mac_tb,  weight = 0 },
                { widget = hn_tb,   weight = 1 },
                { widget = seen_tb, weight = 0 },
            },
        }
        disp_rows[i] = { ip = ip_tb, mac = mac_tb, hn = hn_tb, seen = seen_tb }
        disp_group:add(row)
    end
    local disp_card = W.Card.new {
        title = "Dispositivos en la red",
        content = disp_group,
        padding = 10,
        bg = theme.bg_card_rgb,
        border = theme.separator_rgb,
    }

    local layout = W.Group.new {
        orientation = "vertical", spacing = 10,
        children = {
            { widget = W.Group.new {
                orientation = "horizontal", spacing = 10,
                children = {
                    { widget = active_card, weight = 1 },
                    { widget = wifi_card,   weight = 1 },
                },
            }, weight = 1 },
            { widget = disp_card, weight = 1 },
        },
    }

    local function refresh_active()
        local out = U.shell_once(
            "ip -4 -br addr show up 2>/dev/null | grep -v '^lo'")
        local lines = {}
        for l in out:gmatch("[^\n]+") do lines[#lines+1] = l end
        for i = 1, NUM_ACTIVE do
            local line = lines[i]
            local r = active_rows[i]
            if line then
                local iface, _, ip = line:match("^(%S+)%s+(%S+)%s+(%S+)")
                if iface and ip then
                    local typ = "Otro"
                    if iface:match("^wl") then typ = "WiFi"
                    elseif iface:match("^en") then typ = "Cable" end
                    r.type:set_text(typ)
                    r.iface:set_text(iface)
                    r.ip:set_text(ip:gsub("/.*$", ""))
                end
            else
                r.type:set_text(""); r.iface:set_text(""); r.ip:set_text("")
            end
        end
    end

    local function refresh_wifi()
        local wiface = D_wifi.wifi_iface()
        if wiface == "" then
            for i = 1, NUM_WIFI do
                wifi_rows[i].ssid:set_text("")
                wifi_rows[i].info:set_text("")
            end
            return
        end
        local out = U.shell_once(
            "nmcli -t -f SSID,SIGNAL,SECURITY dev wifi list ifname " ..
            wiface .. " 2>/dev/null | head -" .. NUM_WIFI)
        local i = 1
        for line in out:gmatch("[^\n]+") do
            if i > NUM_WIFI then break end
            local ssid, sig, sec = line:match("^(.-):(%d+):(.*)$")
            if ssid and ssid ~= "" then
                local saved = D_wifi.find_saved(ssid)
                local prefix = saved and "* " or "  "
                wifi_rows[i].ssid:set_text(prefix .. ssid)
                wifi_rows[i].info:set_text(
                    D_wifi.signal_bars(tonumber(sig) or 0))
                i = i + 1
            end
        end
        while i <= NUM_WIFI do
            wifi_rows[i].ssid:set_text("")
            wifi_rows[i].info:set_text("")
            i = i + 1
        end
    end

    local function refresh_disp()
        D_disp.scan(false, function(all)
            for i = 1, NUM_DISP do
                local e = all[i]
                local r = disp_rows[i]
                if e then
                    r.ip:set_text(e.ip)
                    r.mac:set_text(e.mac)
                    r.hn:set_text(e.hostname or "—")
                    r.seen:set_text(e.seen_str or "")
                else
                    r.ip:set_text(""); r.mac:set_text("")
                    r.hn:set_text(""); r.seen:set_text("")
                end
            end
        end)
    end

    local t

    return {
        widget = layout,
        start = function()
            refresh_active()
            refresh_wifi()
            refresh_disp()
            t = srv:add_timer(5000, function()
                refresh_active()
                refresh_disp()
            end)
        end,
        stop = function() if t then t:cancel(); t = nil end end,
    }
end

return M
