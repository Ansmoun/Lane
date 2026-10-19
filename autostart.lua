-- autostart.lua: daemons que se inician con la sesión de LANE.
--
-- Estructura:
--   * bar       — siempre visible, daemon permanente.
--   * wallpaper — one-shot al boot.
--   * events    — dispatcher central. Spawnea on-demand a
--                 launcher/screenshot/logout cuando el usuario
--                 aprieta el atajo (via lane-events <cmd>).
--
-- Los tres (launcher/screenshot/logout) YA NO arrancan al boot.
-- Arrancan cuando el usuario los invoca por primera vez.

return {
    { name = "wallpaper", cmd = "./run apps/wallpaper.lua", wait_x = true },

    { name = "bar",
      cmd  = "/opt/lane-bar/run /opt/lane-bar/lane-bar.lua",
      wait_x = true, delay = 300 },

    { name = "events",
      cmd  = "./run apps/events.lua",
      wait_x = true, delay = 100 },
}
