-- autostart.lua: lanza los daemons declarados en autostart.lua (raiz
-- del proyecto) y sale. Los procesos lanzados quedan reparentados a
-- init y viven hasta que X cae (XKillClient los mata).

local log = require("lib.log")

local M = {}

-- Espera a que X responda. Usa xdpyinfo contra $DISPLAY en vez de
-- chequear un socket hardcodeado, porque el numero de display cambia
-- (:0, :1, :2...) segun cuantas sesiones X haya arrancado.
local function wait_x(timeout_s)
    timeout_s = timeout_s or 10
    local display = os.getenv("DISPLAY") or ":0"
    local t0 = os.time()
    while os.time() - t0 < timeout_s do
        local rc = os.execute(
            string.format("xdpyinfo -display %q >/dev/null 2>&1", display))
        if rc == true or rc == 0 then return true end
        os.execute("sleep 0.2")
    end
    return false
end

local function spawn(name, cmd, cwd)
    -- Cada daemon redirige su salida a /tmp/lane-<name>.log
    -- en vez de /dev/null. Sin esto no hay forma de diagnosticar.
    local log_path = "/tmp/lane-" .. (name or "daemon") .. ".log"
    local full = string.format(
        "cd %q && nohup sh -c %q >%q 2>&1 & echo $!",
        cwd, cmd, log_path)
    local h = io.popen(full, "r")
    if not h then
        log.error("autostart", "%s: io.popen fallo", name)
        return nil
    end
    local pid = tonumber(h:read("*l"))
    h:close()
    if pid then
        log.info("autostart", "%s lanzado (pid=%d)", name, pid)
    else
        log.warn("autostart", "%s: no se pudo leer el pid", name)
    end
    return pid
end

-- spec: lista de entradas de autostart.lua
-- opts.cwd: directorio de trabajo para los comandos (default: cwd actual)
function M.run(spec, opts)
    opts = opts or {}
    local cwd = opts.cwd or "."
    if type(spec) ~= "table" then
        log.error("autostart", "spec no es tabla")
        return 0
    end
    local n = 0
    for _, entry in ipairs(spec) do
        if type(entry) == "table" and entry.cmd then
            if entry.wait_x then
                if not wait_x(10) then
                    log.error("autostart", "%s: timeout esperando X",
                        entry.name or "?")
                    goto continue
                end
            end
            if (entry.delay or 0) > 0 then
                os.execute(string.format("sleep %.2f", entry.delay / 1000))
            end
            spawn(entry.name or "?", entry.cmd, cwd)
            n = n + 1
        end
        ::continue::
    end
    return n
end

return M
