-- autostart.lua: daemons que se inician con la sesión de LANE.
--
-- Dos tipos de entrada:
--   local    : el daemon vive en este mismo repositorio (./run apps/X.lua)
--   externo  : el daemon vive en su propio proyecto, instalado en /opt/
--
-- Solo se arrancan daemons de larga vida (barra, launcher). Las apps
-- one-shot (files, procs, disks, etc.) no van en autostart: se invocan
-- desde el launcher o desde atajos.
--
-- Al salir de la sesión (X se cae), todos los procesos mueren solos
-- porque pierden su conexión X.

return {
    { name = "wallpaper", cmd = "./run apps/wallpaper.lua", wait_x = true },

    { name = "bar",
      cmd  = "/opt/lane-bar/run /opt/lane-bar/app.lua",
      wait_x = true, delay = 300 },

    { name = "launcher",
      cmd  = "/opt/lane-launcher/run /opt/lane-launcher/app.lua",
      wait_x = true, delay = 400 },

    { name = "screenshot", cmd = "./run apps/screenshot.lua", wait_x = true },
    { name = "logout",     cmd = "./run apps/logout.lua",     wait_x = true },
}
