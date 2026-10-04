-- apps/autostart.lua: entry point del autostart.
-- Lo invoca bin/lane-session antes de exec al WM.

local autostart = require("autostart")
local log = require("lib.log")

local SPEC_PATH = (os.getenv("HOME") or ".") .. "/proyectos/lane/autostart.lua"
local PROJECT   = (os.getenv("HOME") or ".") .. "/proyectos/lane"

local ok, spec = pcall(dofile, SPEC_PATH)
if not ok or type(spec) ~= "table" then
    log.error("autostart", "no se pudo leer %s: %s", SPEC_PATH, tostring(spec))
    os.exit(1)
end

local n = autostart.run(spec, { cwd = PROJECT })
log.info("autostart", "%d daemons lanzados", n)
