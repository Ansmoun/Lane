-- apps/autostart.lua: entry point del autostart.
-- Lo invoca bin/lane-session antes de exec al WM.

local autostart = require("autostart")
local log = require("lib.log")

-- Rutas relativas al CWD. lane-session hace `cd $PROJECT` antes
-- de invocar este script, asi que el CWD siempre es la raiz del
-- proyecto (working copy o /opt/lane). Hardcodear $HOME rompia la
-- instalacion de sistema: los daemons arrancaban desde el working
-- copy aunque lane-session fuera de /opt.
local SPEC_PATH = "./autostart.lua"
local PROJECT   = "."

local ok, spec = pcall(dofile, SPEC_PATH)
if not ok or type(spec) ~= "table" then
    log.error("autostart", "no se pudo leer %s: %s", SPEC_PATH, tostring(spec))
    os.exit(1)
end

local n = autostart.run(spec, { cwd = PROJECT })
log.info("autostart", "%d daemons lanzados", n)
