local Server    = require("lib.server")
local wallpaper = require("wallpaper")
local log       = require("lib.log")

local IMG = arg[1] or os.getenv("LANETK_WALLPAPER")

if not IMG then
    local home = os.getenv("HOME")
    if home then
        IMG = home .. "/imagenes/wallpapers/98616585_p0_master1200.jpg"
    end
end

if not IMG then
    log.error("wallpaper", "no hay ruta: pasa arg[1] o define LANETK_WALLPAPER")
    os.exit(1)
end

local srv = Server.new { exit_on_empty = false }
local wp, err = wallpaper.set(srv, IMG)

if not wp then
    log.error("wallpaper", "no se pudo aplicar: %s", err or "?")
    os.exit(1)
end

if #wp.errors > 0 then
    log.warn("wallpaper", "avisos: %s", table.concat(wp.errors, "; "))
end

log.info("wallpaper", "listo. Ctrl+C para salir.")
srv:run()
wp.close()
