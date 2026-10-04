-- Screenshot: daemon con trigger file /tmp/lane-screenshot.cmd.
--
-- Estados:
--   idle       -- sin ventana ni grabacion
--   panel      -- panel de captura abierto
--   recording  -- ffmpeg grabando video
--   done       -- video terminado (proximo)
--
-- Trigger "toggle" rota el estado:
--   idle      -> abre panel
--   panel     -> cierra panel
--   recording -> detiene grabacion
--   done      -> cierra vista video terminado
--
-- Atajo sugerido (sxhkdrc):
--   super + Print
--       echo toggle > /tmp/lane-screenshot.cmd

local Server = require("lib.server")
local Window = require("lib.window")
local theme  = require("lib.theme")
local cairo  = require("lib.cairo")
local pango  = require("lib.pango")
local xcb    = require("lib.xcb")
local log    = require("lib.log")
local W      = require("lib.widgets")
local Area   = require("lib.area")
local xanim  = require("lib.xshape_anim")

local TRIGGER   = "/tmp/lane-screenshot.cmd"
local HOME      = os.getenv("HOME")
local DIR_IMG   = HOME .. "/Imágenes/Capturas"
local DIR_VID   = HOME .. "/Videos/Capturas"
local CONF_FILE  = HOME .. "/.config/lane/screenshot.conf"
local FFMPEG_PID = "/tmp/lane-ffmpeg.pid"
local FFMPEG_LOG = "/tmp/lane-ffmpeg.log"

local PANEL_W, PANEL_H = 460, 360
local REC_W, REC_H     = 220, 44
local ADV_W, ADV_H     = 340, 240

local srv = Server.new({ exit_on_empty = false })
local mem = require("lib.mem")
mem.attach(srv, "screenshot")

local anim = require("lib.anim")
anim.init(srv, { fps = 30 })
local T = theme.load()
log.info("screenshot", "paleta: %s", T.path)

local state = "idle"
local panel_win = nil
local panel_tab = nil
local rec_win = nil
local rec_mon = nil
local rec_file = nil
local rec_start = 0
local rec_timer = nil
local prev_win = nil
local prev_timer = nil
local adv_win = nil
local panel_handle = nil
local adv_handle   = nil
local prev_handle  = nil

-- ── Helpers del reveal ────────────────────────────────────────────
local function blit_and_attach(win, w, h, radius)
    if win.cr and win.image_surface then
        cairo.save(win.cr)
        cairo.set_operator(win.cr, cairo.OPERATOR.SOURCE)
        cairo.set_source_surface(win.cr, win.image_surface, 0, 0)
        cairo.paint(win.cr)
        cairo.restore(win.cr)
        cairo.flush_surface(win.surface)
    end
    return xanim.attach { srv = srv, win = win, w = w, h = h, radius = radius }
end

-- ── CONF ──────────────────────────────────────────────────────────
local function load_conf()
    local c = { quality = "mid", preset = "veryfast", crf = 23 }
    local f = io.open(CONF_FILE, "r")
    if not f then return c end
    for line in f:lines() do
        local k, v = line:match("^(%w+)%s*=%s*(.+)$")
        if k == "quality" then c.quality = v
        elseif k == "preset" then c.preset = v
        elseif k == "crf"    then c.crf = tonumber(v) or 23 end
    end
    f:close()
    return c
end

local function save_conf(c)
    os.execute("mkdir -p '" .. HOME .. "/.config/lane'")
    local f = io.open(CONF_FILE, "w")
    if not f then return end
    f:write("quality=" .. (c.quality or "mid") .. "\n")
    f:write("preset="  .. (c.preset  or "veryfast") .. "\n")
    f:write("crf="     .. tostring(c.crf or 23) .. "\n")
    f:close()
end

local function preset_for(quality, custom_preset, custom_crf)
    if quality == "low"  then return "ultrafast", 28 end
    if quality == "high" then return "medium",    18 end
    if quality == "custom" then
        return (custom_preset or "veryfast"), (custom_crf or 23)
    end
    return "veryfast", 23  -- mid o default
end

-- ── util ──────────────────────────────────────────────────────────
local function file_exists(p)
    local f = io.open(p, "r")
    if f then f:close(); return true end
    return false
end

local function ts()
    return os.date("%Y-%m-%d_%H%M%S")
end

local function mkdir(d)
    os.execute("mkdir -p '" .. d .. "'")
end

-- ── HELPERS DE LA PREVIEW ─────────────────────────────────────────
local function file_size(p)
    local f = io.open(p, "rb")
    if not f then return 0 end
    local sz = f:seek("end")
    f:close()
    return sz or 0
end

local function human_size(n)
    if n < 1024 then return n .. " B" end
    if n < 1024 * 1024 then return string.format("%.1f KB", n / 1024) end
    return string.format("%.1f MB", n / (1024 * 1024))
end

local function close_preview()
    if prev_timer then prev_timer:cancel(); prev_timer = nil end
    if not prev_handle or not prev_handle:visible() then return end
    xcb.ungrab_pointer(srv.conn)
    if prev_win and not prev_win.destroyed then
        pcall(function() prev_win:restore_input_focus() end)
    end
    prev_handle:hide()
    if state == "done" then state = "idle" end
end

local PREV_W, PREV_H = 420, 400
local PREV_THUMB_H   = 200

-- Widget que reserva exactamente PREV_THUMB_H de alto y dibuja la
-- miniatura centrada con aspect ratio preservado. Sin esto, el
-- Group que reservaba el espacio quedaba con min_h = 0 y todo el
-- contenido de abajo se superponia sobre la miniatura.
local PreviewArea = setmetatable({}, { __index = Area })
PreviewArea.__index = PreviewArea

function PreviewArea.new(surface)
    local self = setmetatable(Area.new({}), PreviewArea)
    self.surface = surface
    self.min_w, self.max_w = 0, 10000
    self.min_h, self.max_h = PREV_THUMB_H, PREV_THUMB_H
    return self
end

function PreviewArea:draw(cr)
    if not self.surface then return end
    local cw = self:getWidth()
    local ch = self:getHeight()
    local tw = cairo.surface_width(self.surface)
    local th = cairo.surface_height(self.surface)
    if tw == 0 or th == 0 then return end
    local avail_w = cw - 16
    local avail_h = ch - 8
    local scale = math.min(avail_w / tw, avail_h / th, 1.0)
    local dw = tw * scale
    local dh = th * scale
    local dx = self.x0 + (cw - dw) / 2
    local dy = self.y0 + (ch - dh) / 2
    cairo.draw_surface(cr, self.surface, dx, dy, dw, dh)
end

local function show_preview(path, kind)
    if prev_win then close_preview() end

    local thumb = path
    if kind == "video" then
        thumb = path:gsub("%.mp4$", "_thumb.png")
        if not file_exists(thumb) then
            os.execute(string.format(
                "ffmpeg -y -i '%s' -frames:v 1 -ss 0 '%s' >/dev/null 2>&1",
                path, thumb))
        end
    end

    local thumb_surface = cairo.load_png_cached(thumb)

    local size_bytes = file_size(path)
    local dur_s = nil
    if kind == "video" and rec_start > 0 then
        dur_s = os.time() - rec_start
    end

    local title_text = (kind == "foto") and "Foto lista" or "Video terminado"

    local function make_btn(label, cb)
        return W.Button.new {
            text = label, font = "DejaVu Sans 10", flat = true,
            padding_x = 8, padding_y = 8, corner_radius = 6,
            color_hover = T.bg_focus_rgb, color_text = T.fg_rgb,
            on_click = cb,
        }
    end

    local info_text = string.format("%s · %s",
        human_size(size_bytes),
        (dur_s and string.format("%02d:%02d", math.floor(dur_s/60), dur_s%60)
              or "—"))

    local info_lbl = W.Text.new {
        text = info_text, font = "DejaVu Sans 10",
        align = "center", valign = "center",
        r = T.muted_rgb[1], g = T.muted_rgb[2], b = T.muted_rgb[3],
    }

    local btn_row = W.Group.new {
        orientation = "horizontal", spacing = 4,
        children = {
            { widget = make_btn("Abrir", function()
                os.execute("(xdg-open '" .. path .. "') >/dev/null 2>&1 &")
                close_preview()
            end), weight = 1 },
            { widget = make_btn("Copiar", function()
                os.execute("printf '%s' '" .. path .. "' | xclip -selection clipboard")
                close_preview()
            end), weight = 1 },
            { widget = make_btn("Carpeta", function()
                local dir = path:match("(.+)/[^/]+$") or "."
                os.execute("(xdg-open '" .. dir .. "') >/dev/null 2>&1 &")
                close_preview()
            end), weight = 1 },
            { widget = make_btn("Borrar", function()
                os.remove(path)
                if kind == "video" then os.remove(thumb) end
                close_preview()
            end), weight = 1 },
            { widget = make_btn("Cerrar", function()
                close_preview()
            end), weight = 1 },
        },
    }

    local path_lbl = W.Text.new {
        text = path, font = "DejaVu Sans 9",
        align = "center", valign = "center",
        r = T.muted_rgb[1], g = T.muted_rgb[2], b = T.muted_rgb[3],
    }
    local title_lbl = W.Text.new {
        text = title_text, font = "DejaVu Sans Bold 12",
        align = "center", valign = "center",
        r = T.fg_rgb[1], g = T.fg_rgb[2], b = T.fg_rgb[3],
    }

    local inner = W.Group.new {
        orientation = "vertical", spacing = 6, padding = 12,
        children = {
            { widget = title_lbl,                     weight = 0 },
            { widget = PreviewArea.new(thumb_surface), weight = 0 },
            { widget = info_lbl,                      weight = 0 },
            { widget = path_lbl,                      weight = 0 },
            { widget = btn_row,                       weight = 0 },
        },
    }

    if not prev_win or prev_win.destroyed then
        prev_win = Window.new(srv, {
            kind = "menu",
            width = PREV_W, height = PREV_H,
            x = "cursor-screen", y = "cursor-screen",
            disable_q_close = true,
            title = title_text,
            backing_store = 2,
            on_draw = function(cr, cw, ch)
                local bg = T.bg_rgb
                local bcg = T.bg_card_rgb
                cairo.set_rgb(cr, bg[1], bg[2], bg[3])
                cairo.rounded_rect(cr, 0, 0, cw, ch, 12)
                cairo.fill(cr)
                cairo.set_rgb(cr, bcg[1], bcg[2], bcg[3])
                cairo.rounded_rect(cr, 2, 2, cw - 4, ch - 4, 10)
                cairo.fill(cr)
            end,
            on_key = function(key)
                if key.pressed and key.name == "Escape"
                   and not key.mods.ctrl and not key.mods.alt
                   and not key.mods.super then
                    close_preview()
                end
            end,
            on_mouse = function(x, y, button)
                if button ~= 1 then return end
                if x < 0 or y < 0 or x >= PREV_W or y >= PREV_H then
                    close_preview()
                end
            end,
        })
        prev_handle = blit_and_attach(prev_win, PREV_W, PREV_H, 12)
    end

    prev_win:set_root(inner)
    prev_win:damage_all()
    prev_win:draw()
    if prev_win.cr and prev_win.image_surface then
        cairo.save(prev_win.cr)
        cairo.set_operator(prev_win.cr, cairo.OPERATOR.SOURCE)
        cairo.set_source_surface(prev_win.cr, prev_win.image_surface, 0, 0)
        cairo.paint(prev_win.cr)
        cairo.restore(prev_win.cr)
        cairo.flush_surface(prev_win.surface)
    end

    prev_handle:reset()
    prev_handle:show()
    xcb.grab_pointer(srv.conn, prev_win.id)
    prev_win:set_input_focus()
    state = "done"

    prev_timer = srv:add_timer(15000, function()
        if prev_timer then prev_timer:cancel(); prev_timer = nil end
        close_preview()
    end)
    log.info("screenshot", "preview: %s (%s)", path, kind)
end

-- ── CLAMP DE REGION ───────────────────────────────────────────────
-- Ajusta una region a la interseccion con la pantalla virtual.
-- xwininfo puede reportar coords negativas o fuera de rango cuando
-- la ventana esta parcialmente fuera o bspwm la reposiciona.
-- Sin esto, x11grab falla con BadMatch y el video sale vacio.
local function clamp_region(r)
    local ms = require("lib.screens").list()
    if #ms == 0 then return r end
    local minx, miny = math.huge, math.huge
    local maxx, maxy = -math.huge, -math.huge
    for _, m in ipairs(ms) do
        if m.x < minx then minx = m.x end
        if m.y < miny then miny = m.y end
        if m.x + m.w > maxx then maxx = m.x + m.w end
        if m.y + m.h > maxy then maxy = m.y + m.h end
    end
    local x0 = math.max(r.x, minx)
    local y0 = math.max(r.y, miny)
    local x1 = math.min(r.x + r.w, maxx)
    local y1 = math.min(r.y + r.h, maxy)
    if x1 <= x0 or y1 <= y0 then
        log.warn("screenshot", "region fuera de pantalla: %dx%d+%d+%d",
            r.w, r.h, r.x, r.y)
        return nil
    end
    if x0 ~= r.x or y0 ~= r.y or (x1 - x0) ~= r.w or (y1 - y0) ~= r.h then
        log.info("screenshot", "region clampeada: %dx%d+%d+%d -> %dx%d+%d+%d",
            r.w, r.h, r.x, r.y, x1 - x0, y1 - y0, x0, y0)
    end
    return { x = x0, y = y0, w = x1 - x0, h = y1 - y0, wid = r.wid }
end

-- ── SELECTOR DE VENTANA ───────────────────────────────────────────
-- Devuelve { x, y, w, h } o nil si el usuario cancela.
local function select_window_region()
    log.info("screenshot", "selectwindow: esperando click...")
    local p = io.popen("xdotool selectwindow 2>/dev/null")
    local wid = p:read("*l")
    p:close()
    if not wid or wid == "" then
        log.info("screenshot", "selectwindow cancelado por el usuario")
        return nil
    end
    log.info("screenshot", "wid: %s", wid)

    local q = io.popen("xwininfo -id " .. wid .. " 2>/dev/null")
    local out = q:read("*a") or ""
    q:close()
    log.info("screenshot", "xwininfo: %d bytes", #out)
    if #out == 0 then
        log.warn("screenshot", "xwininfo sin salida")
        return nil
    end

    local x = tonumber(out:match("Absolute upper%-left X:%s*(%-?%d+)"))
    local y = tonumber(out:match("Absolute upper%-left Y:%s*(%-?%d+)"))
    local w = tonumber(out:match("Width:%s*(%d+)"))
    local h = tonumber(out:match("Height:%s*(%d+)"))
    log.info("screenshot", "parse: x=%s y=%s w=%s h=%s",
        tostring(x), tostring(y), tostring(w), tostring(h))

    if not (x and y and w and h) then
        log.warn("screenshot", "xwininfo parse fail")
        return nil
    end
    log.info("screenshot", "region: %dx%d+%d+%d", w, h, x, y)
    return { x = x, y = y, w = w, h = h, wid = wid }
end

-- ── FOTO ──────────────────────────────────────────────────────────
local function do_foto(mode)
    mkdir(DIR_IMG)
    local path = DIR_IMG .. "/" .. ts() .. ".png"
    local cmd
    if mode.kind == "full" then
        cmd = "scrot '" .. path .. "'"
    elseif mode.kind == "monitor" then
        local m = mode.mon
        cmd = string.format("scrot -a %d,%d,%d,%d '%s'",
            m.x, m.y, m.w, m.h, path)
    elseif mode.kind == "area" then
        cmd = "scrot -s '" .. path .. "'"
    elseif mode.kind == "window" then
        local r = select_window_region()
        if not r then state = "idle"; return end
        local rc = clamp_region(r)
        if not rc then state = "idle"; return end
        cmd = string.format("scrot -a %d,%d,%d,%d '%s'",
            rc.x, rc.y, rc.w, rc.h, path)
        mode._wid = r.wid
    end
    log.info("screenshot", "foto cmd: %s", cmd)
    os.execute(cmd)
    if not file_exists(path) and mode.kind == "window" and mode._wid then
        log.warn("screenshot", "scrot no genero archivo, probando import")
        local fb = "import -window " .. mode._wid .. " '" .. path .. "'"
        log.info("screenshot", "fallback: %s", fb)
        os.execute(fb)
    end
    if file_exists(path) then
        log.info("screenshot", "foto OK: %s", path)
        show_preview(path, "foto")
    else
        log.warn("screenshot", "foto no generada")
        state = "idle"
    end
end

-- ── VIDEO ─────────────────────────────────────────────────────────
local function read_pid()
    local f = io.open(FFMPEG_PID, "r")
    if not f then return nil end
    local pid = f:read("*l")
    f:close()
    if not pid or pid == "" then return nil end
    return pid
end

local function pid_alive(pid)
    if not pid then return false end
    local ok = os.execute("kill -0 " .. pid .. " 2>/dev/null")
    return ok == true
end

local function close_rec_indicator()
    if rec_timer then rec_timer:cancel(); rec_timer = nil end
    if rec_win then rec_win:close("rec"); rec_win = nil end
end

local function start_rec_indicator(mon)
    local x = mon.x + mon.w - REC_W - 10
    local y = mon.y + 10
    local w
    w = Window.new(srv, {
        kind = "menu",
        width = REC_W, height = REC_H,
        x = x, y = y,
        disable_q_close = true,
        on_draw = function(cr, cw, ch)
            local bg = T.bg_rgb
            local fg = T.fg_rgb
            local urg = T.urgent_rgb
            cairo.set_rgb(cr, bg[1], bg[2], bg[3])
            cairo.rounded_rect(cr, 0, 0, cw, ch, 6)
            cairo.fill(cr)

            cairo.new_path(cr)
            cairo.set_rgb(cr, urg[1], urg[2], urg[3])
            cairo.arc(cr, 14, ch / 2, 5, 0, 2 * math.pi)
            cairo.fill(cr)

            local elapsed = os.time() - rec_start
            local mm = math.floor(elapsed / 60)
            local ss = elapsed % 60
            local txt = string.format("REC %02d:%02d", mm, ss)
            pango.draw_text(cr, 28, 10, txt, "DejaVu Sans Bold 11",
                { r = fg[1], g = fg[2], b = fg[3] })
            pango.draw_text(cr, 28, 26, "super+Print para detener",
                "DejaVu Sans 8",
                { r = 0.6, g = 0.6, b = 0.6 })
        end,
    })
    w:set_root(W.Group.new { children = {} })
    rec_win = w
    rec_timer = srv:add_timer(1000, function()
        if rec_win then rec_win:damage_all() end
    end)
end

local function on_recording_done()
    if not rec_file then
        log.warn("screenshot", "on_recording_done sin archivo (ignorado)")
        return
    end
    log.info("screenshot", "grabacion terminada: %s", rec_file)
    close_rec_indicator()

    local path = rec_file
    if file_exists(path) then
        show_preview(path, "video")
    else
        log.warn("screenshot", "video no generado: %s", path)
        state = "idle"
    end
    rec_file = nil
    rec_start = 0
end

local function stop_recording()
    local pid = read_pid()
    if not pid then
        log.warn("screenshot", "no hay pid ffmpeg")
        return
    end
    log.info("screenshot", "SIGINT a ffmpeg pid=%s", pid)
    os.execute("kill -INT " .. pid)
    -- Timer one-shot: cancelar el actual antes de reprogramar.
    -- srv:add_timer se reprograma solo; sin cancelar, esto entra en
    -- bucle infinito cuando el pid ya murio.
    local tm
    local function check()
        tm:cancel()
        if pid_alive(pid) then
            tm = srv:add_timer(150, check)
        else
            os.remove(FFMPEG_PID)
            on_recording_done()
        end
    end
    tm = srv:add_timer(150, check)
end

local function do_video(mode, quality, custom_preset, custom_crf)
    mkdir(DIR_VID)
    local path = DIR_VID .. "/" .. ts() .. ".mp4"

    local region
    if mode.kind == "full" then
        local scr = require("lib.screens").list()
        -- pantalla virtual: sumar bounding box de todos los monitores
        local minx, miny = math.huge, math.huge
        local maxx, maxy = -math.huge, -math.huge
        for _, m in ipairs(scr) do
            if m.x < minx then minx = m.x end
            if m.y < miny then miny = m.y end
            if m.x + m.w > maxx then maxx = m.x + m.w end
            if m.y + m.h > maxy then maxy = m.y + m.h end
        end
        region = { x = minx, y = miny, w = maxx - minx, h = maxy - miny }
    elseif mode.kind == "monitor" then
        local m = mode.mon
        region = { x = m.x, y = m.y, w = m.w, h = m.h }
    elseif mode.kind == "window" then
        local r = select_window_region()
        if not r then
            log.warn("screenshot", "video window cancelado")
            state = "idle"
            return
        end
        local rc = clamp_region(r)
        if not rc then state = "idle"; return end
        region = rc
    elseif mode.kind == "area" then
        local p = io.popen("slop -f '%x %y %w %h' 2>/dev/null")
        local out = p:read("*l")
        p:close()
        if not out or out == "" then
            log.warn("screenshot", "slop cancelado o sin salida")
            return
        end
        local sx, sy, sw, sh = out:match("^(%d+) (%d+) (%d+) (%d+)$")
        if not sx then
            log.warn("screenshot", "slop parse fail: %s", out)
            return
        end
        region = { x = tonumber(sx), y = tonumber(sy),
                   w = tonumber(sw), h = tonumber(sh) }
    end

    -- libx264 + yuv420p exige dimensiones pares. Redondear hacia abajo.
    region.w = region.w - (region.w % 2)
    region.h = region.h - (region.h % 2)
    log.info("screenshot", "region par: %dx%d+%d+%d",
        region.w, region.h, region.x, region.y)

    local preset, crf = preset_for(quality, custom_preset, custom_crf)
    log.info("screenshot", "calidad=%s preset=%s crf=%d",
        tostring(quality), preset, crf)

    local cmd = string.format(
        "sh -c 'nohup ffmpeg -y -f x11grab -video_size %dx%d -framerate 30 " ..
        "-i :0.0+%d,%d -c:v libx264 -preset %s -crf %d " ..
        "-pix_fmt yuv420p \"%s\" >%s 2>&1 & echo $! >%s'",
        region.w, region.h, region.x, region.y,
        preset, crf,
        path, FFMPEG_LOG, FFMPEG_PID)

    log.info("screenshot", "video start: %dx%d+%d+%d -> %s",
        region.w, region.h, region.x, region.y, path)
    os.execute(cmd)

    rec_file = path
    rec_start = os.time()
    rec_mon = (mode.mon) or require("lib.screens").list()[1]

    start_rec_indicator(rec_mon)
    state = "recording"
end

-- ── SUB-PANEL AVANZADO ────────────────────────────────────────────
-- Ventana modal con preset + CRF. Se abre desde el boton "Avanzado"
-- del tab Video. Comparte conf con el panel principal.

local ADV_PRESETS = { "ultrafast", "veryfast", "medium", "slow" }

local function close_advanced()
    if not adv_handle or not adv_handle:visible() then return end
    xcb.ungrab_pointer(srv.conn)
    if adv_win and not adv_win.destroyed then
        pcall(function() adv_win:restore_input_focus() end)
    end
    adv_handle:hide()
end

local function show_advanced_panel(conf, on_save)
    if adv_win then close_advanced() end

    local function save()
        on_save(conf)
    end

    local preset_buttons = {}
    local function update_preset_visual()
        for _, pb in ipairs(preset_buttons) do
            pb.selected = (pb._key == conf.preset)
            pb:damage()
        end
    end

    local CardButton = require("lib.widgets.cardbutton")
    local function to_hex(rgb)
        return string.format("#%02x%02x%02x",
            math.floor((rgb[1] or 0) * 255 + 0.5),
            math.floor((rgb[2] or 0) * 255 + 0.5),
            math.floor((rgb[3] or 0) * 255 + 0.5))
    end

    for _, pname in ipairs(ADV_PRESETS) do
        local captured = pname
        local pb = CardButton.new {
            icon = nil, title = captured, subtitle = "",
            width = 74, height = 36, icon_size = 0,
            font_title = "DejaVu Sans 9",
            font_sub   = "DejaVu Sans 7",
            bg_color     = to_hex(T.bg_card_rgb),
            hover_color  = to_hex(T.bg_focus_rgb),
            fg_color     = to_hex(T.fg_rgb),
            fg_sub_color = to_hex(T.muted_rgb),
            border_color = to_hex(T.separator_rgb),
            accent_color = to_hex(T.accent_rgb),
            corner_radius = 6,
            on_click = function()
                conf.preset = captured
                update_preset_visual()
                save()
            end,
        }
        pb._key = captured
        pb.selected = (captured == conf.preset)
        preset_buttons[#preset_buttons + 1] = pb
    end

    local preset_row = W.Group.new {
        orientation = "horizontal",
        spacing = 4,
        children = (function()
            local c = {}
            for _, pb in ipairs(preset_buttons) do
                c[#c + 1] = { widget = pb, weight = 0 }
            end
            return c
        end)(),
    }

    local crf_input = W.TextInput.new {
        text = tostring(conf.crf or 23),
        font = "DejaVu Sans Mono 10",
        padding_x = 6, padding_y = 4,
        min_width = 60, min_height = 36,
        color_bg = to_hex(T.bg_card_rgb),
        color_border = to_hex(T.separator_rgb),
        corner_radius = 6,
        color_text = T.fg_rgb,
        color_cursor = T.accent_rgb,
        on_change = function(text)
            local n = tonumber(text)
            if n and n >= 0 and n <= 51 then
                conf.crf = n
                save()
            end
        end,
    }

    local preset_lbl = W.Text.new {
        text = "Preset",
        font = "DejaVu Sans 9",
        align = "left", valign = "center",
        r = T.muted_rgb[1], g = T.muted_rgb[2], b = T.muted_rgb[3],
    }
    local crf_lbl = W.Text.new {
        text = "CRF (0-51)",
        font = "DejaVu Sans 9",
        align = "left", valign = "center",
        r = T.muted_rgb[1], g = T.muted_rgb[2], b = T.muted_rgb[3],
    }
    local hint_lbl = W.Text.new {
        text = "Solo se aplica cuando Calidad = Custom.",
        font = "DejaVu Sans 8",
        align = "left", valign = "center",
        r = T.muted_rgb[1], g = T.muted_rgb[2], b = T.muted_rgb[3],
    }

    local close_btn = W.Button.new {
        text = "Cerrar",
        font = "DejaVu Sans 10",
        flat = true,
        padding_x = 12, padding_y = 8,
        corner_radius = 6,
        color_hover = T.bg_focus_rgb,
        color_text = T.fg_rgb,
        on_click = function()
            save()
            close_advanced()
        end,
    }

    local inner = W.Group.new {
        orientation = "vertical",
        spacing = 8,
        padding = 14,
        children = {
            { widget = preset_lbl, weight = 0 },
            { widget = preset_row, weight = 0 },
            { widget = crf_lbl,    weight = 0 },
            { widget = W.Group.new {
                orientation = "horizontal",
                spacing = 6,
                children = { { widget = crf_input, weight = 0 } },
            }, weight = 0 },
            { widget = hint_lbl,   weight = 0 },
            { widget = W.Group.new {
                orientation = "horizontal",
                spacing = 0,
                children = { { widget = close_btn, weight = 1 } },
            }, weight = 0 },
        },
    }

    if not adv_win or adv_win.destroyed then
        adv_win = Window.new(srv, {
            kind = "menu",
            width = ADV_W, height = ADV_H,
            x = "cursor-screen", y = "cursor-screen",
            disable_q_close = true,
            title = "Avanzado",
            backing_store = 2,
            on_draw = function(cr, cw, ch)
                local bg  = T.bg_rgb
                local bcg = T.bg_card_rgb
                cairo.set_rgb(cr, bg[1], bg[2], bg[3])
                cairo.rounded_rect(cr, 0, 0, cw, ch, 10)
                cairo.fill(cr)
                cairo.set_rgb(cr, bcg[1], bcg[2], bcg[3])
                cairo.rounded_rect(cr, 2, 2, cw - 4, ch - 4, 8)
                cairo.fill(cr)
            end,
            on_key = function(key)
                if key.pressed and key.name == "Escape"
                   and not key.mods.ctrl and not key.mods.alt
                   and not key.mods.super then
                    close_advanced()
                end
            end,
            on_mouse = function(x, y, button)
                if button ~= 1 then return end
                if x < 0 or y < 0 or x >= ADV_W or y >= ADV_H then
                    close_advanced()
                end
            end,
        })
        adv_handle = blit_and_attach(adv_win, ADV_W, ADV_H, 10)
    end

    adv_win:set_root(inner)
    adv_win:damage_all()
    adv_win:draw()
    if adv_win.cr and adv_win.image_surface then
        cairo.save(adv_win.cr)
        cairo.set_operator(adv_win.cr, cairo.OPERATOR.SOURCE)
        cairo.set_source_surface(adv_win.cr, adv_win.image_surface, 0, 0)
        cairo.paint(adv_win.cr)
        cairo.restore(adv_win.cr)
        cairo.flush_surface(adv_win.surface)
    end
    adv_handle:reset()
    adv_handle:show()
    xcb.grab_pointer(srv.conn, adv_win.id)
    adv_win:set_input_focus()
end

-- ── PANEL ─────────────────────────────────────────────────────────
local function close_panel()
    if not panel_handle or not panel_handle:visible() then return end
    xcb.ungrab_pointer(srv.conn)
    if panel_win and not panel_win.destroyed then
        pcall(function() panel_win:restore_input_focus() end)
    end
    panel_handle:hide()
    if state == "panel" then state = "idle" end
end

local function open_panel()
    local mod = require("tabs.screenshot")

    local function do_foto_mode(mode)
        close_panel()
        local tm
        tm = srv:add_timer(80, function()
            tm:cancel()
            do_foto(mode)
            state = "idle"
        end)
    end

    local conf = load_conf()

    local function on_quality_change(quality, preset, crf)
        conf.quality = quality
        conf.preset  = preset
        conf.crf     = crf
        save_conf(conf)
    end

    local function on_advanced()
        show_advanced_panel(conf, function(c)
            save_conf(c)
        end)
    end

    local function do_video_mode(mode, quality, custom_preset, custom_crf)
        close_panel()
        local tm
        tm = srv:add_timer(80, function()
            tm:cancel()
            do_video(mode, quality, custom_preset, custom_crf)
        end)
    end

    panel_tab = mod.new(srv, T, {
        on_foto = do_foto_mode,
        on_video = do_video_mode,
        on_cancel = close_panel,
        initial_quality = conf.quality,
        initial_preset  = conf.preset,
        initial_crf     = conf.crf,
        on_quality_change = on_quality_change,
        on_advanced = on_advanced,
    })

    if not panel_win or panel_win.destroyed then
        panel_win = Window.new(srv, {
            kind = "menu",
            width = PANEL_W, height = PANEL_H,
            x = "cursor-screen", y = "cursor-screen",
            disable_q_close = true,
            title = "Screenshot",
            backing_store = 2,
            on_draw = function(cr, cw, ch)
                local bg = T.bg_rgb
                local bcg = T.bg_card_rgb
                cairo.set_rgb(cr, bg[1], bg[2], bg[3])
                cairo.rounded_rect(cr, 0, 0, cw, ch, 12)
                cairo.fill(cr)
                cairo.set_rgb(cr, bcg[1], bcg[2], bcg[3])
                cairo.rounded_rect(cr, 2, 2, cw - 4, ch - 4, 10)
                cairo.fill(cr)
            end,
            on_key = function(key)
                if key.pressed and key.name == "Escape"
                   and not key.mods.ctrl and not key.mods.alt
                   and not key.mods.super then
                    close_panel()
                end
            end,
            on_mouse = function(x, y, button)
                if button ~= 1 then return end
                if x < 0 or y < 0 or x >= PANEL_W or y >= PANEL_H then
                    close_panel()
                end
            end,
        })
        panel_handle = blit_and_attach(panel_win, PANEL_W, PANEL_H, 12)
    end

    panel_win:set_root(panel_tab.widget)
    if panel_tab.start then panel_tab.start() end
    panel_win:damage_all()
    panel_win:draw()
    if panel_win.cr and panel_win.image_surface then
        cairo.save(panel_win.cr)
        cairo.set_operator(panel_win.cr, cairo.OPERATOR.SOURCE)
        cairo.set_source_surface(panel_win.cr, panel_win.image_surface, 0, 0)
        cairo.paint(panel_win.cr)
        cairo.restore(panel_win.cr)
        cairo.flush_surface(panel_win.surface)
    end
    panel_handle:reset()
    panel_handle:show()
    xcb.grab_pointer(srv.conn, panel_win.id)
    panel_win:set_input_focus()
    state = "panel"
end

-- ── STATE MACHINE ────────────────────────────────────────────────
local function do_toggle()
    if state == "idle" then
        open_panel()
    elseif state == "panel" then
        close_panel()
    elseif state == "recording" then
        stop_recording()
    elseif state == "done" then
        close_preview()
    end
end

-- Hot reload de paleta.
--   - En estado "panel": cerrar y reabrir el panel.
--   - En estado "done" (preview visible): cerrar la preview (no se
--     puede reconstruir el archivo despues de grabado; se descarta).
--   - En estado "recording": no tocar, la grabacion continua.
--   - En estado "idle": no-op.
local function destroy_all_windows()
    if panel_win and not panel_win.destroyed then
        xcb.destroy_window(srv.conn, panel_win.id)
    end
    if adv_win and not adv_win.destroyed then
        xcb.destroy_window(srv.conn, adv_win.id)
    end
    if prev_win and not prev_win.destroyed then
        xcb.destroy_window(srv.conn, prev_win.id)
    end
    panel_win, panel_handle = nil, nil
    adv_win, adv_handle = nil, nil
    prev_win, prev_handle = nil, nil
    panel_tab = nil
    state = "idle"
end

theme.watch(function()
    if state == "panel" then
        log.info("screenshot", "rebuild del panel por cambio de paleta")
        xcb.ungrab_pointer(srv.conn)
        destroy_all_windows()
        local tm
        tm = srv:add_timer(80, function()
            tm:cancel()
            open_panel()
        end)
    elseif state == "done" then
        log.info("screenshot", "preview cerrada por cambio de paleta")
        xcb.ungrab_pointer(srv.conn)
        destroy_all_windows()
    end
end)

local reload = require("lib.reload")
reload.install(srv, function()
    log.info("screenshot", "SIGUSR1: rebuild cross-process")
    theme.reload_in_place(T)
    if state == "panel" then
        xcb.ungrab_pointer(srv.conn)
        destroy_all_windows()
        local tm
        tm = srv:add_timer(80, function()
            tm:cancel()
            open_panel()
        end)
    elseif state == "done" then
        xcb.ungrab_pointer(srv.conn)
        destroy_all_windows()
    end
end)

srv:watch_trigger(TRIGGER, function(cmd)
    log.info("screenshot", "trigger: %s (state=%s)", cmd, state)
    if cmd == "toggle" or cmd == "" then
        do_toggle()
    elseif cmd == "show" then
        if state == "idle" then open_panel() end
    elseif cmd == "hide" then
        if state == "panel" then close_panel() end
    elseif cmd == "stop" then
        if state == "recording" then stop_recording() end
    elseif cmd == "quit" then
        if rec_win then rec_win:close("quit") end
        destroy_all_windows()
        srv:stop()
    else
        log.warn("screenshot", "cmd desconocido: %s", cmd)
    end
end)

log.info("screenshot", "daemon listo. trigger: %s", TRIGGER)
srv:run()
log.info("screenshot", "adios")
