-- wallpaper.lua: fondo de escritorio nativo (ffmpeg + X11 pixmap).
-- Uso: require("wallpaper").set(srv, "/ruta/imagen")

local ffi     = require("ffi")
local xcb     = require("lib.xcb")
local screens = require("lib.screens")
local log     = require("lib.log")

local M = {}

local function shquote(s)
    return "'" .. s:gsub("'", "'\\''") .. "'"
end

local function have(cmd)
    local h = io.popen("command -v " .. cmd .. " 2>/dev/null")
    if not h then return false end
    local line = h:read("*l")
    h:close()
    return line ~= nil and line ~= ""
end

-- ffmpeg -> BGRA crudo, tamaño exacto w x h, cover + lanczos.
local function decode_cover(path, w, h)
    local vf = string.format(
        "scale=%d:%d:flags=lanczos:force_original_aspect_ratio=increase,crop=%d:%d",
        w, h, w, h)
    local cmd = string.format(
        "ffmpeg -nostdin -v error -i %s -vf %s -frames:v 1 -f rawvideo -pix_fmt bgra - 2>/dev/null",
        shquote(path), shquote(vf))
    local p = io.popen(cmd, "r")
    if not p then return nil, "io.popen fallo" end
    local data = p:read("*a")
    p:close()
    local expect = w * h * 4
    if not data or #data ~= expect then
        return nil, string.format("ffmpeg devolvio %d bytes, esperaba %d",
            data and #data or 0, expect)
    end
    return data
end

local function make_pixmap(srv, w, h, bgra)
    local conn  = srv.conn
    local root  = srv.screen.root
    local depth = srv.screen.root_depth

    local pid = xcb.generate_id(conn)
    local err = xcb.check_cookie(conn,
        xcb.create_pixmap_checked(conn, depth, pid, root, w, h),
        "create_pixmap")
    if err then return nil, err end

    local gc = xcb.generate_id(conn)
    err = xcb.check_cookie(conn,
        xcb.create_gc_checked(conn, gc, pid),
        "create_gc")
    if err then
        xcb.free_pixmap(conn, pid)
        return nil, err
    end

    err = xcb.check_cookie(conn,
        xcb.put_image_checked(conn, pid, gc, w, h, 0, 0, depth,
            xcb.IMAGE_FORMAT.ZPixmap, bgra),
        "put_image")
    xcb.free_gc(conn, gc)

    if err then
        xcb.free_pixmap(conn, pid)
        return nil, err
    end
    return pid
end

local function make_desktop_window(srv, mon, pid)
    local screen = srv.screen
    local wid, _, cerr = xcb.create_window(srv.conn, {
        parent = screen.root,
        x = mon.x, y = mon.y,
        width = mon.w, height = mon.h,
        border_width = 0,
        depth = screen.root_depth,
        class = xcb.WIN_CLASS.InputOutput,
        visual = screen.root_visual,
        override_redirect = true,
        background_pixmap = pid,
        event_mask = 0,
    })
    if not wid then return nil, "create_window: " .. (cerr or "?") end

    xcb.map_window(srv.conn, wid)
    xcb.configure_window(srv.conn, wid, xcb.CONFIG.Stack, { stack = 1 })
    xcb.flush(srv.conn)
    return wid
end

function M.set(srv, path, opts)
    opts = opts or {}
    if opts.mode and opts.mode ~= "cover" then
        return nil, "wallpaper: modo no soportado: " .. opts.mode
    end
    if not have("ffmpeg") then
        return nil, "wallpaper: ffmpeg no esta en PATH"
    end
    if not path or path == "" then
        return nil, "wallpaper: path vacio"
    end
    local f = io.open(path, "rb")
    if not f then return nil, "wallpaper: no se puede leer: " .. tostring(path) end
    f:close()

    local mons = opts.monitor and { opts.monitor } or screens.list()
    if #mons == 0 then return nil, "wallpaper: no hay monitores" end

    log.info("wallpaper", "aplicando %s en %d monitor(es)", path, #mons)

    local windows, errors = {}, {}
    for _, mon in ipairs(mons) do
        local bgra, derr = decode_cover(path, mon.w, mon.h)
        if not bgra then
            errors[#errors + 1] = string.format("%s: %s", mon.name, derr)
            log.error("wallpaper", "%s: %s", mon.name, derr)
        else
            local pid, perr = make_pixmap(srv, mon.w, mon.h, bgra)
            bgra = nil
            if not pid then
                errors[#errors + 1] = string.format("%s: %s", mon.name, perr)
                log.error("wallpaper", "%s: %s", mon.name, perr)
            else
                local wid, werr = make_desktop_window(srv, mon, pid)
                if not wid then
                    errors[#errors + 1] = string.format("%s: %s", mon.name, werr)
                    log.error("wallpaper", "%s: %s", mon.name, werr)
                    xcb.free_pixmap(srv.conn, pid)
                else
                    windows[#windows + 1] = { wid = wid, pid = pid, mon = mon }
                    log.info("wallpaper", "%s: win 0x%x (%dx%d+%d+%d)",
                        mon.name, tonumber(wid), mon.w, mon.h, mon.x, mon.y)
                end
            end
        end
    end

    collectgarbage("collect")
    xcb.flush(srv.conn)

    if #windows == 0 then
        return nil, "wallpaper: ningun monitor tuvo exito: " ..
            table.concat(errors, "; ")
    end

    return {
        windows = windows,
        errors  = errors,
        close = function()
            local conn = srv.conn
            for _, w in ipairs(windows) do
                xcb.destroy_window(conn, w.wid)
                xcb.free_pixmap(conn, w.pid)
            end
            xcb.flush(conn)
        end,
    }
end

return M
