-- autostart.lua: daemons que se inician con la sesión de LANE.
--
-- Cada entrada:
--   name    identificador (para logs)
--   cmd     comando shell (string). Se ejecuta con CWD = raiz del proyecto.
--   wait_x  true si necesita que X este arriba antes de lanzar (default true)
--   delay   ms de espera antes de lanzar (default 0)
--
-- Al salir de la sesion (X se cae), todos los procesos mueren solos
-- porque pierden su conexion X. No hace falta cleanup explicito.

return {
    {
        name   = "wallpaper",
        cmd    = "./run apps/wallpaper.lua",
        wait_x = true,
    },
    {
        name   = "bar",
        cmd    = "./run apps/bar.lua",
        wait_x = true,
        delay  = 300,
    },
    {
        name   = "launcher",
        cmd    = "./run apps/launcher.lua",
        wait_x = true,
    },
    {
        name   = "screenshot",
        cmd    = "./run apps/screenshot.lua",
        wait_x = true,
    },
    {
        name   = "logout",
        cmd    = "./run apps/logout.lua",
        wait_x = true,
    },
}
