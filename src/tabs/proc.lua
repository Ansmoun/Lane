-- Tab Procesos: lista ordenable + filtro + pills + menu contextual.

local W      = require("lib.widgets")
local G      = require("lib.helpers.graphics")
local U      = require("lib.helpers.util")
local cairo  = require("lib.cairo")
local pango  = require("lib.pango")
local CM     = require("lib.widgets.contextmenu")
local xcb    = require("lib.xcb")
local Area   = require("lib.area")

local D_cpu   = require("lib.data.cpu")
local D_ram   = require("lib.data.ram")
local D_gpu   = require("lib.data.gpu")
local D_temps = require("lib.data.temps")
local D_bat   = require("lib.data.bat")

local M = {}

local VISIBLE_ROWS = 14
local ROW_H        = 22

-- ═════════════════════════════════════════════════════════════
-- Columnas
-- ═════════════════════════════════════════════════════════════
local COLS = {
    { key = "pid",  label = "PID",     width = 55, align = "right",  pssort = "pid"  },
    { key = "user", label = "USER",    width = 85, align = "left",   pssort = "user" },
    { key = "pri",  label = "PRI",     width = 40, align = "center", pssort = "pri"  },
    { key = "cpu",  label = "CPU%",    width = 60, align = "right",  pssort = "pcpu" },
    { key = "mem",  label = "RAM",     flex  = 1,  align = "right",  pssort = "rss"  },
    { key = "time", label = "TIME",    width = 75, align = "right",  pssort = "time" },
    { key = "comm", label = "COMMAND", flex  = 3,  align = "left",   pssort = "comm" },
}
local COL_GAP  = 6
local COL_PAD  = 8
local MIN_FLEX = 60

local function compute_cols(avail)
    local fixed_sum, flex_total = 0, 0
    for _, c in ipairs(COLS) do
        if c.flex then flex_total = flex_total + c.flex
        else            fixed_sum  = fixed_sum  + c.width end
    end
    local gaps = COL_GAP * (#COLS - 1)
    local used = fixed_sum + gaps + COL_PAD * 2
    local free = avail - used

    local out = {}
    if free < MIN_FLEX then
        for _, c in ipairs(COLS) do
            out[#out + 1] = c.flex and MIN_FLEX or c.width
        end
    else
        for _, c in ipairs(COLS) do
            if c.flex then
                out[#out + 1] = math.floor(free * c.flex / flex_total)
            else
                out[#out + 1] = c.width
            end
        end
    end
    return out
end

local function draw_aligned(cr, text, font, color, x, y, w, h, align)
    if text == "" then return end
    local tw = pango.measure(text, font)
    local tx = x
    if align == "right"  then tx = x + w - tw end
    if align == "center" then tx = x + (w - tw) / 2 end
    local _, th = pango.measure(text, font)
    local ty = y + (h - th) / 2
    pango.draw_text(cr, tx, ty, text, font, color)
end

-- ═════════════════════════════════════════════════════════════
-- Sampler: ps -eo ... con pssort
-- ═════════════════════════════════════════════════════════════
local function read_procs(sort_pssort, sort_dir)
    local ps_sort = (sort_dir == "desc") and ("-" .. sort_pssort) or sort_pssort
    local cmd = string.format(
        "ps -eo pid,ppid,user,pri,pcpu,pmem,rss,time,comm --sort=%s --no-headers 2>/dev/null",
        ps_sort)
    local out = U.shell_once(cmd)

    local items = {}
    for line in out:gmatch("[^\n]+") do
        local pid, ppid, user, pri, cpu, mem, rss, time, comm =
            line:match("^%s*(%d+)%s+(%d+)%s+(%S+)%s+(%d+)%s+([%d%.]+)%s+([%d%.]+)%s+(%d+)%s+(%S+)%s+(.+)$")
        if pid and comm and comm ~= "ps" and comm ~= "sh" and comm ~= "awk" then
            local rss_kb = tonumber(rss) or 0
            local mb = rss_kb / 1024
            local mem_abs
            if mb >= 1024 then
                mem_abs = string.format("%.1f GB", mb / 1024)
            else
                mem_abs = string.format("%d MB", math.floor(mb))
            end
            items[#items + 1] = {
                pid     = pid,
                ppid    = ppid,
                user    = user,
                pri     = pri,
                cpu     = string.format("%.1f", tonumber(cpu) or 0),
                mem     = string.format("%s  (%s)",
                    string.format("%.1f%%", tonumber(mem) or 0), mem_abs),
                mem_pct = tonumber(mem) or 0,
                rss     = rss,
                time    = time,
                comm    = comm,
            }
        end
    end
    return items
end

-- ═════════════════════════════════════════════════════════════
-- Helpers de telemetria (pills)
-- ═════════════════════════════════════════════════════════════
local net_prev = { rx = nil, tx = nil, time = nil }
-- Cache de la interfaz default. Se refresca cada 30s en lugar de
-- cada 2s: evita 1 fork cada 2s por un dato que rara vez cambia.
local net_iface_cache = { name = nil, time = 0 }

local function net_default_iface()
    local now = os.time()
    if net_iface_cache.name and (now - net_iface_cache.time) < 30 then
        return net_iface_cache.name
    end
    local name = U.trim(U.shell_once(
        "ip route show default 2>/dev/null | awk '{print $5; exit}'"))
    net_iface_cache.name = name
    net_iface_cache.time = now
    return name
end

local function read_uptime()
    local v = U.read_file("/proc/uptime") or "0"
    return tonumber(v:match("^([%d%.]+)")) or 0
end

local function read_net_speed(iface, now)
    if not iface or iface == "" then return 0, 0 end
    local rx = tonumber(U.read_file(
        "/sys/class/net/" .. iface .. "/statistics/rx_bytes") or "0") or 0
    local tx = tonumber(U.read_file(
        "/sys/class/net/" .. iface .. "/statistics/tx_bytes") or "0") or 0
    if not net_prev.rx or not net_prev.time then
        net_prev.rx, net_prev.tx, net_prev.time = rx, tx, now
        return 0, 0
    end
    local dt = now - net_prev.time
    if dt <= 0 then return 0, 0 end
    local srx = (rx - net_prev.rx) / dt
    local stx = (tx - net_prev.tx) / dt
    net_prev.rx, net_prev.tx, net_prev.time = rx, tx, now
    return srx, stx
end

local function fmt_speed(bps)
    if not bps or bps < 0 then return "0" end
    if bps < 1024 then return string.format("%d", math.floor(bps)) end
    if bps < 1048576 then return string.format("%.0fK", bps / 1024) end
    if bps < 1073741824 then return string.format("%.1fM", bps / 1048576) end
    return string.format("%.2fG", bps / 1073741824)
end

local function fmt_uptime(secs)
    if not secs or secs < 0 then return "-" end
    local d = math.floor(secs / 86400)
    local h = math.floor((secs % 86400) / 3600)
    local m = math.floor((secs % 3600) / 60)
    if d > 0 then return string.format("%dd%dh", d, h) end
    if h > 0 then return string.format("%dh%dm", h, m) end
    return string.format("%dm", m)
end

-- ═════════════════════════════════════════════════════════════
-- Tab
-- ═════════════════════════════════════════════════════════════
function M.new(srv, theme)
    local state = {
        sort_key = "cpu",
        sort_dir = "desc",
        filter   = "",
        selected = nil,
    }

    -- ── Forward declarations ────────────────────────────────
    local refresh
    local open_context_menu
    local list
    local filter_input

    -- ── Header: widget propio que dibuja las columnas y maneja
    --    clicks de ordenacion ─────────────────────────────────
    local HeaderRow = setmetatable({}, { __index = Area })
    HeaderRow.__index = HeaderRow

    function HeaderRow.new()
        local self = setmetatable(Area.new {}, HeaderRow)
        self.min_h = 22
        self.min_w = 100
        self.max_w = 10000
        self.right_reserve = 20
        return self
    end

    function HeaderRow:draw(cr)
        local avail = self:getWidth() - self.right_reserve
        if avail < 50 then return end
        local widths = compute_cols(avail)

        local x = self.x0 + COL_PAD
        for i, c in ipairs(COLS) do
            local active = (c.key == state.sort_key)
            local color = active and (theme.accent or "#8ec07c")
                          or (theme.muted or "#928374")
            local mark = ""
            if active then
                mark = (state.sort_dir == "desc") and "  v" or "  ^"
            end
            local text = c.label .. mark
            local r, g, b = G.hex_to_rgba(color)
            local font = "DejaVu Sans Bold 10"
            local tw = pango.measure(text, font)
            local tx = x
            if c.align == "right"  then tx = x + widths[i] - tw end
            if c.align == "center" then tx = x + (widths[i] - tw) / 2 end
            local _, th = pango.measure(text, font)
            local ty = self.y0 + (self:getHeight() - th) / 2
            pango.draw_text(cr, tx, ty, text, font, { r = r, g = g, b = b })
            x = x + widths[i] + COL_GAP
        end
    end

    function HeaderRow:on_mouse_press(mx, my, button)
        if button ~= 1 then return end
        local avail = self:getWidth() - self.right_reserve
        if avail < 50 then return end
        local widths = compute_cols(avail)
        local x = COL_PAD
        for i, c in ipairs(COLS) do
            if mx >= x and mx < x + widths[i] then
                if state.sort_key == c.key then
                    state.sort_dir = (state.sort_dir == "desc") and "asc" or "desc"
                else
                    state.sort_key = c.key
                    state.sort_dir = "desc"
                end
                refresh()
                return
            end
            x = x + widths[i] + COL_GAP
        end
    end

    -- ── Pills de telemetria ─────────────────────────────────
    local gpu_hex = (theme.telemetry and theme.telemetry.gpu) or "#d3869b"
    local gr, gg, gb = G.hex_to_rgba(gpu_hex)
    local cpu_hex = (theme.telemetry and theme.telemetry.cpu) or "#8ec07c"
    local cr, cg, cb = G.hex_to_rgba(cpu_hex)
    local ram_hex = (theme.telemetry and theme.telemetry.ram) or "#83a598"
    local rr, rg, rb = G.hex_to_rgba(ram_hex)

    local pills = W.PillRow.new {
        theme = theme,
        gap = 10, pad_x = 10, pad_y = 4,
        items = {
            { id = "cpu",  label = "CPU",  color = { cr, cg, cb } },
            { id = "ram",  label = "RAM",  color = { rr, rg, rb } },
            { id = "gpu",  label = "GPU",  color = { gr, gg, gb } },
            { id = "temp", label = "TMP",  color = { 0.95, 0.65, 0.45 } },
            { id = "bat",  label = "BAT",  color = { 0.75, 0.85, 0.45 } },
            { id = "net",  label = "NET",  color = { 0.55, 0.75, 0.90 } },
            { id = "up",   label = "UP",   color = { 0.65, 0.65, 0.70 } },
        },
    }

    local function refresh_pills()
        local c = D_cpu.sample()
        if c then
            pills:set("cpu", math.floor((c.usage or 0) * 100) .. "%")
        end

        local r = D_ram.sample()
        if r then
            pills:set("ram", math.floor((r.pct or 0) * 100) .. "%")
        end

        local g = D_gpu.status()
        if g then
            pills:set("gpu", math.floor(g.render or 0) .. "%")
        else
            pills:set("gpu", "off")
        end

        local coretemp = D_temps.find_coretemp and D_temps.find_coretemp() or nil
        if coretemp then
            local t = D_temps.read_coretemp(coretemp)
            local mt = 0
            for _, v in ipairs({ t.core0, t.core1, t.pkg }) do
                if v and v > mt then mt = v end
            end
            pills:set("temp", mt > 0 and (mt .. "C") or "--")
        else
            pills:set("temp", "--")
        end

        if D_bat.available and D_bat.available() then
            local b = D_bat.sample()
            if b then
                if b.status == "Charging" or b.status == "Full" then
                    pills:set("bat", "CA")
                else
                    pills:set("bat", math.floor(b.capacity) .. "%")
                end
            end
        else
            pills:set("bat", "N/A")
        end

        local iface = net_default_iface()
        if iface ~= "" then
            local rxb, txb = read_net_speed(iface, os.time())
            pills:set("net",
                string.format("^%s v%s", fmt_speed(txb), fmt_speed(rxb)))
        else
            pills:set("net", "sin red")
        end

        pills:set("up", fmt_uptime(read_uptime()))
    end

    -- ── Lista ───────────────────────────────────────────────
    -- Comparador: dos procesos son "iguales" si sus campos
    -- visibles no cambiaron. Evita repintar las 14 filas cada 2s
    -- cuando solo cambia el CPU de uno o dos.
    local function proc_equal(a, b)
        if not a or not b then return a == b end
        return a.pid     == b.pid
           and a.user    == b.user
           and a.pri     == b.pri
           and a.cpu     == b.cpu
           and a.mem     == b.mem
           and a.time    == b.time
           and a.comm    == b.comm
    end

    list = W.ScrollView.new {
        row_height = ROW_H,
        bg_color = theme.bg_card,
        min_width = 300,
        min_height = ROW_H * VISIBLE_ROWS,
        compare = proc_equal,
        on_click = function(item)
            state.selected = item
        end,
        on_right_click = function(item)
            state.selected = item
            if item then open_context_menu(item) end
        end,
    }

    list.draw_row = function(cr, item, idx, y, rh, width, hover)
        if not item then return end

        if state.selected and state.selected.pid == item.pid then
            local r, g, b = G.hex_to_rgba(theme.accent or "#8ec07c")
            cairo.set_rgba(cr, r, g, b, 0.20)
            cairo.rectangle(cr, 0, y, width, rh); cairo.fill(cr)
            -- Barra lateral
            cairo.set_rgb(cr, r, g, b)
            cairo.rectangle(cr, 2, y + 5, 3, rh - 10)
            cairo.fill(cr)
        elseif hover then
            local r, g, b = G.hex_to_rgba(theme.separator or "#504945")
            cairo.set_rgba(cr, r, g, b, 0.35)
            cairo.rectangle(cr, 0, y, width, rh); cairo.fill(cr)
        elseif idx % 2 == 0 then
            local r, g, b = G.hex_to_rgba(theme.separator or "#504945")
            cairo.set_rgba(cr, r, g, b, 0.12)
            cairo.rectangle(cr, 0, y, width, rh); cairo.fill(cr)
        end

        -- Misma funcion de reparto que el header.
        local widths = compute_cols(width)
        local x = COL_PAD
        for i, col in ipairs(COLS) do
            local val = item[col.key] or ""
            local color = theme.fg_normal or "#ebdbb2"

            if col.key == "user" and val == "root" then
                color = theme.accent or "#8ec07c"
            elseif col.key == "cpu" then
                local n = tonumber(val) or 0
                if n > 80 then color = theme.usage_crit or "#cc241d"
                elseif n > 50 then color = theme.usage_warn or "#d79921" end
            elseif col.key == "mem" then
                local n = item.mem_pct or 0
                if n > 40 then color = theme.usage_crit or "#cc241d"
                elseif n > 20 then color = theme.usage_warn or "#d79921" end
            end

            local r, g, b = G.hex_to_rgba(color)
            cairo.save(cr)
            cairo.rectangle(cr, x, y, widths[i], rh); cairo.clip(cr)
            draw_aligned(cr, tostring(val), "DejaVu Sans 10",
                { r = r, g = g, b = b }, x, y, widths[i], rh, col.align)
            cairo.restore(cr)
            x = x + widths[i] + COL_GAP
        end
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

    -- ── Filter input ────────────────────────────────────────
    filter_input = W.TextInput.new {
        text = "",
        font = "DejaVu Sans 10",
        padding_x = 6, padding_y = 3,
        color_bg = nil,
        color_border = theme.separator,
        corner_radius = 3,
        on_change = function(text)
            state.filter = U.trim(text or "")
            refresh()
        end,
        on_submit = function()
            filter_input:set_focused(false)
        end,
        on_cancel = function()
            filter_input:set_text("")
            state.filter = ""
            filter_input:set_focused(false)
            refresh()
        end,
    }
    filter_input.opts.on_focus_request = function()
        filter_input:set_focused(true)
    end

    local count_label = W.Text.new {
        text = "Procesos: --",
        font = "DejaVu Sans 10",
        r = 0.55, g = 0.55, b = 0.60,
        align = "left", valign = "center",
    }

    -- ── Header instance ─────────────────────────────────────
    local header = HeaderRow.new()

    -- ── Context menu ────────────────────────────────────────
    local context_menu = CM.new(srv, nil, theme)

    local function make_kill_action(item, sig)
        return function()
            if not item or not item.pid then return end
            os.execute(string.format("kill -%s %s 2>/dev/null",
                sig, item.pid))
            refresh()
        end
    end

    open_context_menu = function(item)
        -- Necesitamos el window padre para crear el child menu.
        local pwin = list.window
        if not pwin then
            -- Aun no llego set_window. No podemos abrir el menu.
            return
        end

        -- Recrear el context menu si cambio el parent.
        if context_menu.parent_win ~= pwin then
            if context_menu.win then context_menu:close() end
            context_menu = CM.new(srv, pwin, theme)
        end

        local cx, cy = xcb.query_pointer(pwin.conn)
        if not cx then return end
        local lx = cx - pwin.x
        local ly = cy - pwin.y

        local items = {
            { label = "Terminar  (PID " .. item.pid .. ")",
              on_click = make_kill_action(item, "TERM") },
            { label = "Forzar cierre",
              color = theme.usage_crit_rgb or { 0.9, 0.4, 0.4 },
              on_click = make_kill_action(item, "KILL") },
            { label = "Pausar",
              on_click = make_kill_action(item, "STOP") },
            { label = "Continuar",
              on_click = make_kill_action(item, "CONT") },
            { sep = true },
            { label = "Prioridad: bajar (+10)",
              on_click = function()
                  os.execute(string.format(
                      "renice +10 -p %s >/dev/null 2>&1", item.pid))
              end },
            { label = "Prioridad: subir (-10)",
              on_click = function()
                  os.execute(string.format(
                      "sudo -n renice -10 -p %s >/dev/null 2>&1", item.pid))
              end },
        }
        context_menu:show(lx, ly, items)
    end

    -- ── Layout ──────────────────────────────────────────────
    local pills_wrap = W.Group.new {
        orientation = "horizontal", spacing = 4, padding = 8,
        children = { { widget = pills, weight = 0 } },
    }

    local top_bar = W.Group.new {
        orientation = "horizontal", spacing = 8, padding = 6,
        children = {
            { widget = count_label,  weight = 0 },
            { widget = filter_input, weight = 1 },
        },
    }

    local header_wrap = W.Group.new {
        orientation = "horizontal", padding = 0,
        children = { { widget = header, weight = 1 } },
    }

    local table_inner = W.Group.new {
        orientation = "vertical", spacing = 0, padding = 0,
        children = {
            { widget = header_wrap, weight = 0 },
            { widget = rows_area,   weight = 1 },
        },
    }

    local table_card = W.Card.new {
        title = nil,
        content = table_inner,
        padding = 6,
        bg = theme.bg_card_rgb,
        border = theme.separator_rgb,
        min_height = 200,
    }

    local layout = W.Group.new {
        orientation = "vertical", spacing = 6, padding = 8,
        children = {
            { widget = pills_wrap, weight = 0 },
            { widget = top_bar,    weight = 0 },
            { widget = table_card, weight = 1 },
        },
    }

    -- ── Refresh ─────────────────────────────────────────────
    refresh = function()
        refresh_pills()

        local base_sort = "pcpu"
        for _, col in ipairs(COLS) do
            if col.key == state.sort_key then base_sort = col.pssort end
        end

        local items = read_procs(base_sort, state.sort_dir)
        local total = #items

        if state.filter ~= "" then
            local f = state.filter:lower()
            local filtered = {}
            for _, item in ipairs(items) do
                if item.comm:lower():find(f, 1, true) then
                    filtered[#filtered + 1] = item
                end
            end
            items = filtered
        end

        if state.filter ~= "" then
            count_label:set_text(string.format(
                "Procesos: %d  (mostrando %d)", total, #items))
        else
            count_label:set_text(string.format("Procesos: %d", total))
        end

        list:set_items(items)
        -- NO resetear el offset. El usuario puede haber scrolleado
        -- y no queremos saltarle la vista. Si el offset excede el
        -- maximo, _recalc_max dentro de set_items ya lo clampea.
    end

    -- ── Timer ───────────────────────────────────────────────
    local t
    return {
        widget = layout,
        start = function()
            refresh()
            t = srv:add_timer(2000, refresh)
        end,
        stop = function()
            if t then t:cancel(); t = nil end
            if context_menu.win then context_menu:close() end
        end,
    }
end

return M
