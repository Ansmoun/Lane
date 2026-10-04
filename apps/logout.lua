-- Logout menu: daemon con trigger file /tmp/lane-logout.cmd.
-- Uso:
--   echo toggle > /tmp/lane-logout.cmd
--   echo show   > /tmp/lane-logout.cmd
--   echo hide   > /tmp/lane-logout.cmd
--   echo quit   > /tmp/lane-logout.cmd
--
-- Atajo sugerido (sxhkdrc):
--   super + shift + e
--       echo toggle > /tmp/lane-logout.cmd
--
-- Layout: 2x2 de botones + franja ancha abajo (apagar).
-- Cierre: Esc, o click fuera de la ventana (grab_pointer).

local Server = require("lib.server")
local Window = require("lib.window")
local theme  = require("lib.theme")
local log    = require("lib.log")
local anim   = require("lib.anim")
local cairo  = require("lib.cairo")
local xcb    = require("lib.xcb")
local W      = require("lib.widgets")
local LogoutButton = require("lib.widgets.logoutbutton")
local ffi    = require("ffi")
ffi.cdef[[int usleep(unsigned int usec);]]

local HOME       = os.getenv("HOME")
local ICON_DIR   = HOME .. "/proyectos/lane/icons-png/88/logout/"
local LOCK       = HOME .. "/.local/bin/lock"
local TRIGGER    = "/tmp/lane-logout.cmd"

local BTN_W      = 120
local BTN_H      = 100
local BAND_H     = 80
local BTN_GAP    = 8
local POP_MARGE  = 14
local ICON_SIZE  = 44
local RADIUS     = 6

local CONTENT_W  = BTN_W * 2 + BTN_GAP
local CONTENT_H  = BTN_H * 2 + BAND_H + BTN_GAP * 2
local WIN_W      = CONTENT_W + POP_MARGE * 2
local WIN_H      = CONTENT_H + POP_MARGE * 2

local ITEMS = {
    { id = "lock",    icon = "lock",    label = "Bloquear",
      cmd = LOCK, hover = "#83a598", wide = false },
    { id = "logout",  icon = "logout",  label = "Cerrar sesion",
      cmd = 'loginctl terminate-session "$XDG_SESSION_ID" || loginctl terminate-user "$USER"',
      hover = "#d65d0e", wide = false },
    { id = "reboot",  icon = "reboot",  label = "Reiniciar",
      cmd = "loginctl reboot",   hover = "#b8bb26", wide = false },
    { id = "suspend", icon = "suspend", label = "Suspender",
      cmd = "loginctl suspend",  hover = "#b16286", wide = false },
    { id = "power",   icon = "power",   label = "Apagar",
      cmd = "loginctl poweroff", hover = "#fb4934", wide = true  },
}

local srv = Server.new({ exit_on_empty = false })
local mem = require("lib.mem")
mem.attach(srv, "logout")



local ITEMS = {
    { id = "lock",    icon = "lock",    label = "Bloquear",
      cmd = LOCK, hover = "#83a598", wide = false },
    { id = "logout",  icon = "logout",  label = "Cerrar sesion",
      cmd = 'loginctl terminate-session "$XDG_SESSION_ID" || loginctl terminate-user "$USER"',
      hover = "#d65d0e", wide = false },
    { id = "reboot",  icon = "reboot",  label = "Reiniciar",
      cmd = "loginctl reboot",   hover = "#b8bb26", wide = false },
    { id = "suspend", icon = "suspend", label = "Suspender",
      cmd = "loginctl suspend",  hover = "#b16286", wide = false },
    { id = "power",   icon = "power",   label = "Apagar",
      cmd = "loginctl poweroff", hover = "#fb4934", wide = true  },
}

local srv = Server.new({ exit_on_empty = false })
local mem = require("lib.mem")
mem.attach(srv, "logout")

-- ── Estado de animacion (mismo patron que apps/launcher.lua) ───────
local ANIM_MS = 240
local last_visible_h = -1
local slide = {
    current = 0,
    target  = 0,
}

-- Construye rects de mascara redondeada con visible_h filas.
-- Recorre solo 3 zonas (curvatura arriba, plano medio, curvatura
-- abajo) y fusiona filas consecutivas con el mismo dx.
local function build_rounded_rects(w, h, r, visible_h)
    if visible_h < 1 then return {} end
    r = math.min(r or 0, math.floor(h / 2), math.floor(w / 2))
    local y_start = h - visible_h
    local r2 = r * r
    local rects = {}

    local function dx_at(y)
        local dx = 0
        if y < r then
            local dy = r - y - 0.5
            local sq = r2 - dy * dy
            if sq > 0 then dx = r - math.floor(math.sqrt(sq) + 0.5) end
        elseif y >= h - r then
            local dy = y - (h - r) + 0.5
            local sq = r2 - dy * dy
            if sq > 0 then dx = r - math.floor(math.sqrt(sq) + 0.5) end
        end
        if dx < 0 then dx = 0 end
        return dx
    end

    local prev_dx, run_y0 = nil, nil
    local function flush_run(y_end)
        if prev_dx ~= nil then
            local rw = w - 2 * prev_dx
            if rw > 0 then
                rects[#rects + 1] = { prev_dx, run_y0, rw,
                                      y_end - run_y0 }
            end
        end
    end

    local y = y_start
    while y < h and y < r do
        local dx = dx_at(y)
        if dx ~= prev_dx then
            if prev_dx ~= nil then flush_run(y) end
            prev_dx, run_y0 = dx, y
        end
        y = y + 1
    end
    local flat_end = h - r - 1
    if y <= flat_end then
        if prev_dx ~= 0 then
            if prev_dx ~= nil then flush_run(y) end
            prev_dx, run_y0 = 0, y
        end
        y = flat_end + 1
    end
    while y < h do
        local dx = dx_at(y)
        if dx ~= prev_dx then
            if prev_dx ~= nil then flush_run(y) end
            prev_dx, run_y0 = dx, y
        end
        y = y + 1
    end
    if prev_dx ~= nil then flush_run(h) end
    return rects
end

local win = nil

local function apply_mask(input_too)
    if not win or win.destroyed then return end
    local vis = math.floor(slide.current * WIN_H + 0.5)
    if vis == last_visible_h and not input_too then return end
    last_visible_h = vis

    local rects = build_rounded_rects(WIN_W, WIN_H, RADIUS, vis)
    xcb.shape_rectangles(srv.conn, win.id, rects,
        { kind = xcb.SHAPE_KIND.Bounding })
    if input_too then
        xcb.shape_rectangles(srv.conn, win.id, rects,
            { kind = xcb.SHAPE_KIND.Input })
    end
    xcb.flush(srv.conn)
end

local function animate_slide()
    local from = slide.current
    local to   = slide.target
    if from == to then return end

    -- Animacion sincrona con usleep. Timing perfecto, sin variacion
    -- por eventos X que retrasen timers. El server procesa todo en
    -- orden y el usuario no puede interactuar durante 240ms.
    local steps = 16
    local step_ms = ANIM_MS / steps
    xcb.flush(srv.conn)

    for i = 1, steps do
        local t = i / steps
        local e = t * t * (3 - 2 * t)
        slide.current = from + (to - from) * e
        apply_mask(i == steps)
        if i < steps then
            ffi.C.usleep(math.floor(step_ms * 1000))
        end
    end
    slide.current = to
end



local T = theme.load()
log.info("logout", "paleta: %s", T.path)

anim.init(srv, { fps = 30 })

-- Forward declaration: do_hide se usa en on_click de los botones
local do_hide

-- Forward declaration: do_hide se usa en on_click de los botones
local do_hide

local function make_button(item)
    local w = item.wide and CONTENT_W or BTN_W
    local h = item.wide and BAND_H    or BTN_H
    return LogoutButton.new {
        icon         = item.icon,
        label        = item.label,
        icon_dir     = ICON_DIR,
        width        = w,
        height       = h,
        wide         = item.wide,
        bg_color     = "#1a1a1a",
        hover_color  = item.hover,
        fg_color     = "#ebdbb2",
        fg_dark      = "#000000",
        border_color = "#333333",
        icon_size    = ICON_SIZE,
        corner_radius = RADIUS,
        font         = "DejaVu Sans 10",
        on_click = function()
            if item.cmd then
                os.execute("(" .. item.cmd .. ") >/dev/null 2>&1 &")
            end
            do_hide()
        end,
    }
end

local function build_root()
    local row1 = W.Group.new {
        orientation = "horizontal",
        spacing = BTN_GAP,
        children = { make_button(ITEMS[1]), make_button(ITEMS[2]) },
    }
    local row2 = W.Group.new {
        orientation = "horizontal",
        spacing = BTN_GAP,
        children = { make_button(ITEMS[3]), make_button(ITEMS[4]) },
    }
    local band = make_button(ITEMS[5])

    return W.Group.new {
        orientation = "vertical",
        spacing = BTN_GAP,
        padding = POP_MARGE,
        children = { row1, row2, band },
    }
end

local function do_show()
    if slide.target == 1 then return end

    local bg  = T.bg_rgb or { 0.06, 0.06, 0.06 }
    local sep = T.separator_rgb or { 0.2, 0.2, 0.2 }

    if not win or win.destroyed then
        win = Window.new(srv, {
            kind = "menu",
            width  = WIN_W,
            height = WIN_H,
            x = "cursor-screen",
            y = "cursor-screen",
            disable_q_close = true,
            title = "Logout",
            backing_store = 2,   -- Always
            on_draw = function(cr, cw, ch)
                cairo.set_rgb(cr, bg[1], bg[2], bg[3])
                cairo.rounded_rect(cr, 0, 0, cw, ch, RADIUS)
                cairo.fill(cr)
                cairo.set_rgb(cr, sep[1], sep[2], sep[3])
                cairo.set_line_width(cr, 1)
                cairo.rounded_rect(cr, 0.5, 0.5, cw - 1, ch - 1, RADIUS)
                cairo.stroke(cr)
            end,
            on_key = function(key)
                if key.pressed and key.name == "Escape"
                   and not key.mods.ctrl and not key.mods.alt
                   and not key.mods.super then
                    do_hide()
                end
            end,
            on_mouse = function(x, y, button)
                if button ~= 1 then return end
                if x < 0 or y < 0 or x >= WIN_W or y >= WIN_H then
                    do_hide()
                end
            end,
        })
        win:set_root(build_root())
        win:damage_all()
        win:draw()
        -- Blit una vez para llenar el XCB surface.
        if win.cr and win.image_surface then
            cairo.save(win.cr)
            cairo.set_operator(win.cr, cairo.OPERATOR.SOURCE)
            cairo.set_source_surface(win.cr, win.image_surface, 0, 0)
            cairo.paint(win.cr)
            cairo.restore(win.cr)
            cairo.flush_surface(win.surface)
        end
    end

    -- Reset de la animacion por si quedo a medias.
    slide.current = 0
    slide.target  = 0
    last_visible_h = -1
    -- Mascara vacia inicial: la ventana queda mapeada pero invisible.
    apply_mask(true)

    xcb.grab_pointer(srv.conn, win.id)
    win:set_input_focus()

    slide.target = 1
    animate_slide()
    log.info("logout", "mostrado")
end

do_hide = function()
    if slide.target == 0 then return end
    log.info("logout", "ocultando")

    -- Soltar grab ANTES de animar. Sin esto, el grab sigue activo
    -- durante la animacion y el usuario no puede interactuar con
    -- el resto de la pantalla mientras la mascara baja.
    xcb.ungrab_pointer(srv.conn)
    if win and not win.destroyed then
        pcall(function() win:restore_input_focus() end)
    end

    slide.target = 0
    animate_slide()
end

local function do_toggle()
    if slide.target == 1 then do_hide() else do_show() end
end

-- Hot reload de paleta: si el menu esta abierto, cerrarlo y
-- reabrirlo con los colores nuevos.
theme.watch(function()
    -- Con la ventana persistente, cambiar colores en caliente
    -- requiere cerrar y recrear. El cierre es sincrono, asi que
    -- no hace falta timer de diferido.
    if not win or win.destroyed then return end
    log.info("logout", "rebuild por cambio de paleta")
    if slide.target == 1 then
        do_hide()
    end
    xcb.destroy_window(srv.conn, win.id)
    win = nil
    last_visible_h = -1
    slide.current = 0
    slide.target  = 0
end)

local reload = require("lib.reload")
reload.install(srv, function()
    log.info("logout", "SIGUSR1: rebuild cross-process")
    theme.reload_in_place(T)
    if not win or win.destroyed then return end
    if slide.target == 1 then do_hide() end
    xcb.destroy_window(srv.conn, win.id)
    win = nil
    last_visible_h = -1
    slide.current = 0
    slide.target  = 0
end)

srv:watch_trigger(TRIGGER, function(cmd)
    log.info("logout", "trigger: %s", cmd)
    if cmd == "toggle" or cmd == "" then
        do_toggle()
    elseif cmd == "show" then
        do_show()
    elseif cmd == "hide" then
        do_hide()
    elseif cmd == "quit" then
        do_hide()
        srv:stop()
    else
        log.warn("logout", "comando desconocido: %s", cmd)
    end
end)

log.info("logout", "daemon listo. trigger: %s", TRIGGER)
srv:run()
log.info("logout", "adios")
