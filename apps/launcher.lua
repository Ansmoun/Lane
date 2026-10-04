-- Launcher de aplicaciones: daemon con trigger file.
-- Uso:
--   echo toggle > /tmp/lane-launcher.cmd
--   echo show   > /tmp/lane-launcher.cmd
--   echo hide   > /tmp/lane-launcher.cmd
--   echo quit   > /tmp/lane-launcher.cmd
--
-- Atajo sugerido (sxhkdrc):
--   super + d
--       echo toggle > /tmp/lane-launcher.cmd
--
-- Cada show crea un tab nuevo (estado limpio). Cada hide lo destruye.
-- El proceso queda vivo entre shows.

local Server = require("lib.server")
local Window = require("lib.window")
local theme  = require("lib.theme")
local cairo  = require("lib.cairo")
local log    = require("lib.log")
local xanim  = require("lib.xshape_anim")

local TRIGGER    = "/tmp/lane-launcher.cmd"
local W_LAUNCHER = 640
local H_LAUNCHER = 460

local srv = Server.new({ exit_on_empty = false })
local mem = require("lib.mem")
mem.attach(srv, "launcher")

local T = theme.load()
log.info("launcher", "paleta: %s", T.path)

-- Prewarm: hacer scan de apps y resolver los iconos del top 20 del
-- historial ANTES de srv:run(). Sin esto, el primer super+d paga el
-- costo entero (scan + primera construccion del indice de iconos,
-- que hace find sobre /usr/share/icons) y el usuario ve el fondo
-- sin iconos durante medio segundo.
do
    local D = require("lib.data.launcher")
    local t0 = os.time()
    log.info("launcher", "prewarm: scan...")
    local n = D.scan()
    log.info("launcher", "prewarm: scan OK (%d apps)", n or 0)
    local hist = D.history_top(20)
    local n_icons = 0
    for _, e in ipairs(hist) do
        if e.icon and e.icon ~= "" then
            D.find_icon(e.icon)
            n_icons = n_icons + 1
        end
    end
    log.info("launcher", "prewarm done: %d iconos en %ds",
        n_icons, os.time() - t0)
end

local xcb = require("lib.xcb")
local ffi = require("ffi")
ffi.cdef[[int usleep(unsigned int usec);]]

local DOCK_GEO_FILE = "/tmp/lane-dock-geometry"
local LOCK_FILE     = "/tmp/lane-launcher-open"
local GAP_FROM_DOCK = 8
local RADIUS        = 14
local ANIM_MS       = 260

local win = nil
local tab = nil
local win_handle = nil

local function read_dock_geo()
    local f = io.open(DOCK_GEO_FILE, "r")
    if not f then return nil end
    local line = f:read("*l")
    f:close()
    if not line then return nil end
    local x, y, w, h = line:match("(%d+)%s+(%d+)%s+(%d+)%s+(%d+)")
    if not x then return nil end
    return tonumber(x), tonumber(y), tonumber(w), tonumber(h)
end

local function compute_position()
    local dx, dy, dw, dh = read_dock_geo()
    if not dx then return nil end
    local x = dx + math.floor((dw - W_LAUNCHER) / 2)
    local y = dy - H_LAUNCHER - GAP_FROM_DOCK
    if y < 0 then y = 0 end
    return x, y
end

local function ensure_window()
    local x, y = compute_position()
    if win and not win.destroyed then
        -- Reposicionar por si el dock cambio de tamano/posicion
        -- mientras el launcher estaba oculto.
        if x and y then win:move(x, y) end
        return win
    end
    local opts = {
        kind = "menu",
        title = "lane-launcher",
        width  = W_LAUNCHER,
        height = H_LAUNCHER,
        disable_q_close = true,
        -- Backing store Always: el servidor X conserva los pixeles
        -- ocultos por la mascara. Sin esto, cada tick de la animacion
        -- requiere redibujar todo el arbol de widgets (20+ iconos SVG
        -- + textos Pango), que en Celeron 847 tarda 30-50ms por frame.
        backing_store = 2,  -- 2 = Always
        on_draw = function(cr, cw, ch)
            local bg  = T.bg_rgb
            local bcg = T.bg_card_rgb
            if not bg or not bcg then
                cairo.set_rgb(cr, 0.04, 0.05, 0.08)
                cairo.paint(cr)
                return
            end
            cairo.set_rgb(cr, bg[1], bg[2], bg[3])
            cairo.rounded_rect(cr, 0, 0, cw, ch, 14)
            cairo.fill(cr)
            cairo.set_rgb(cr, bcg[1], bcg[2], bcg[3])
            cairo.rounded_rect(cr, 2, 2, cw - 4, ch - 4, 12)
            cairo.fill(cr)
        end,
        on_focus_in = function()
            if tab and tab.focus then tab.focus() end
        end,
    }
    if x then opts.x = x; opts.y = y
    else opts.x = "cursor-screen"; opts.y = "cursor-screen" end
    win = Window.new(srv, opts)
    -- win.x / win.y ya quedan seteados por Window.new. Los usamos
    -- en do_toggle para detectar si el dock se movio.
    win_handle = xanim.attach {
        srv = srv, win = win,
        w = W_LAUNCHER, h = H_LAUNCHER,
        radius = RADIUS, ms = ANIM_MS,
    }
    return win
end

local function do_show()
    if win_handle and win_handle:visible() then return end
    ensure_window()

    -- Construir el tab SOLO la primera vez. En shows siguientes el
    -- arbol ya esta montado y los pixeles del XCB surface siguen
    -- intactos. NO redibujar: cada damage_all + draw paga 200ms
    -- (20+ SVG + Pango), y es la causa del entrecortado en cada
    -- show, no solo el primero.
    if not win.root then
        local launcher_mod = require("tabs.launcher")
        tab = launcher_mod.new(srv, T)
        win:set_root(tab.widget)
        tab.start()
        win:damage_all()
        win:draw()
        -- Blit una sola vez para llenar el XCB surface.
        local cairo = require("lib.cairo")
        if win.cr and win.image_surface then
            cairo.save(win.cr)
            cairo.set_operator(win.cr, cairo.OPERATOR.SOURCE)
            cairo.set_source_surface(win.cr, win.image_surface, 0, 0)
            cairo.paint(win.cr)
            cairo.restore(win.cr)
            cairo.flush_surface(win.surface)
        end
    end

    win:set_input_focus()
    if tab and tab.focus then tab.focus() end

    local lf = io.open(LOCK_FILE, "w")
    if lf then lf:write("1\n"); lf:close() end

    win_handle:show()
    log.info("launcher", "mostrado")
end

local function do_hide()
    if not win_handle or not win_handle:visible() then return end
    log.info("launcher", "ocultando")
    if win and not win.destroyed then
        pcall(function() win:restore_input_focus() end)
    end
    os.remove(LOCK_FILE)
    win_handle:hide()
end

local function do_toggle()
    -- Si el dock se movio desde el ultimo show (el usuario cambio
    -- de monitor), el launcher puede estar mostrado en la posicion
    -- vieja aunque win_handle:visible() diga true. En ese caso lo
    -- cerramos primero y lo abrimos en la posicion nueva.
    if win_handle and win_handle:visible() then
        local x, y = compute_position()
        if x and win and not win.destroyed then
            local moved = (win.x ~= x or win.y ~= y)
            if moved then
                log.info("launcher", "dock movido, reposicionando")
                do_hide()
                local tm
                tm = srv:add_timer(50, function()
                    tm:cancel()
                    do_show()
                end)
                return
            end
        end
        do_hide()
    else
        do_show()
    end
end

-- Hot reload de paleta: si la ventana esta abierta, cerrarla y
-- reabrirla con los colores nuevos. Si esta cerrada, no hacer nada.
theme.watch(function()
    if not tab then return end
    log.info("launcher", "rebuild por cambio de paleta")
    do_hide()
    local tm
    tm = srv:add_timer(80, function()
        tm:cancel()
        do_show()
    end)
end)

local reload = require("lib.reload")
reload.install(srv, function()
    log.info("launcher", "SIGUSR1: rebuild cross-process")
    theme.reload_in_place(T)
    if tab then
        do_hide()
        local tm
        tm = srv:add_timer(80, function()
            tm:cancel()
            do_show()
        end)
    end
end)

srv:watch_trigger(TRIGGER, function(cmd)
    log.info("launcher", "trigger: %s", cmd)
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
        log.warn("launcher", "comando desconocido: %s", cmd)
    end
end)

-- Seguimiento del dock mientras el launcher esta visible.
-- Si el dock se mueve de monitor (el usuario arrastra el mouse a la
-- otra pantalla), el launcher se reposiciona encima. Sin esto, el
-- launcher queda mostrandose en la posicion vieja.
--
-- Corre cada 250ms. Solo hace trabajo si el launcher esta visible.
local function watch_dock_position()
    if not win_handle or not win_handle:visible() then return end
    if not win or win.destroyed then return end
    local x, y = compute_position()
    if not x or not y then return end
    if win.x ~= x or win.y ~= y then
        log.info("launcher", "siguiendo al dock: (%d,%d) -> (%d,%d)",
            win.x, win.y, x, y)
        win:move(x, y)
    end
end

srv:add_timer(250, watch_dock_position)

log.info("launcher", "daemon listo. trigger: %s", TRIGGER)
srv:run()
log.info("launcher", "adios")
