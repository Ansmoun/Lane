-- events.lua: dispatcher central de Lane.
--
-- Singleton. Vive toda la sesión (~3MB idle). Recibe comandos por
-- socket y decide qué hacer: mandar SIGUSR2 a un hijo vivo (toggle
-- interno de la app) o spawnear uno nuevo.
--
-- Filosofía:
--   * Los hijos (screenshot/logout) son procesos
--     independientes con ciclo de vida propio: nacen, atienden, y
--     siguen vivos esperando SIGUSR2 o cerrados (ventana oculta).
--     Solo mueren por crash o SIGTERM externo.
--   * Events no mantiene "is_open": si el pid está vivo, manda
--     SIGUSR2 y la app decide qué hacer según su propio estado
--     interno (do_toggle). Si está muerto, spawnea.
--   * Cooldown de 1s post-spawn: ignorar toggles durante el boot
--     del proceso (no respondió al socket todavía).

local Server      = require("lib.server")
local unix_socket = require("lib.unix_socket")
local signal      = require("lib.signal")
local log         = require("lib.log")

local SOCK_PATH = (os.getenv("XDG_RUNTIME_DIR") or "/tmp")
                  .. "/lane-events.sock"

local HOME = os.getenv("HOME")

local LANE_DIR = (function()
    for _, d in ipairs({ "/opt/lane", HOME .. "/proyectos/lane" }) do
        local f = io.open(d .. "/run", "r")
        if f then f:close(); return d end
    end
end)()

if not LANE_DIR then
    io.stderr:write("events: no se encontró lane/run\n")
    os.exit(1)
end

local SPAWN_COOLDOWN = 1  -- segundos

local APPS = {
    screenshot = {
        entry = LANE_DIR .. "/run " .. LANE_DIR .. "/apps/screenshot.lua",
        log   = "/tmp/lane-screenshot.log",
    },
    logout = {
        entry = LANE_DIR .. "/run " .. LANE_DIR .. "/apps/logout.lua",
        log   = "/tmp/lane-logout.log",
    },
    wallpaper = {
        entry = LANE_DIR .. "/run " .. LANE_DIR .. "/apps/wallpaper.lua",
        log   = "/tmp/lane-wallpaper.log",
        one_shot = true,
    },
}

local function is_alive(pid)
    if not pid or pid < 1 then return false end
    return signal.send(pid, 0)
end

local function spawn(name, opts)
    opts = opts or {}
    local a = APPS[name]
    if not a or not a.entry then
        log.error("events", "spawn: app desconocida o sin entry: %s", name)
        return nil
    end
    local extra = opts.toggle_on_start and " --toggle-on-start" or ""
    local cmd = string.format("nohup %s%s > %s 2>&1 & echo $!",
        a.entry, extra, a.log)
    local h = io.popen(cmd)
    if not h then
        log.error("events", "spawn: io.popen falló para %s", name)
        return nil
    end
    local pid = tonumber((h:read("*l") or ""):match("(%d+)"))
    h:close()
    if not pid then
        log.error("events", "spawn: no pude leer pid de %s", name)
        return nil
    end
    log.info("events", "spawn %s (pid=%d)", name, pid)
    a.pid = pid
    a.spawn_at = os.time()
    return pid
end

-- Estrategia uniforme:
--   * screenshot/logout: mueren al cerrar su ventana. Cada toggle
--     = spawn fresco con --toggle-on-start. El proceso abre su
--     ventana al arrancar (sin signal, sin race del signalfd).
--   * wallpaper: one-shot, no togglea.
--   * launcher: ya no vive acá. Es parte del daemon de lane-bar
--     (super+d → /opt/lane-bar/bin/lane-bar toggle-launcher).
--
-- Si en el futuro querés cachear alguno, es agregar
-- `idle_shutdown_ms` en el APPS entry y un timer en events. No
-- cambia esta función.

local function toggle(name)
    local a = APPS[name]
    if not a then return nil, "app desconocida: " .. tostring(name) end

    if a.one_shot then
        spawn(name)
        return "spawned"
    end

    if is_alive(a.pid) then
        signal.send(a.pid, signal.SIGUSR2)
        log.info("events", "toggle %s: SIGUSR2 → pid %d", name, a.pid)
        return "signaled"
    end

    a.pid = nil
    spawn(name, { toggle_on_start = true })
    return "spawned"
end

local function status()
    local parts = {}
    for name, a in pairs(APPS) do
        if not a.one_shot then
            parts[#parts+1] = string.format("%s: pid=%s alive=%s",
                name, tostring(a.pid), tostring(is_alive(a.pid)))
        end
    end
    table.sort(parts)
    return table.concat(parts, " | ")
end

local function cleanup_children()
    for _, a in pairs(APPS) do
        if a.pid and is_alive(a.pid) then
            log.info("events", "cleanup: TERM pid %d", a.pid)
            signal.send(a.pid, signal.SIGTERM)
        end
    end
end

local srv = Server.new({ exit_on_empty = false })

local _sock = unix_socket.server {
    srv  = srv,
    path = SOCK_PATH,
    handler = function(cmd, args)
        cmd = cmd or ""
        args = (args or ""):gsub("%s+$", "")
        log.info("events", "socket cmd=%s args=%s", cmd, args)

        if cmd == "ping" then return "pong"
        elseif cmd == "status" then return status()
        elseif cmd == "quit" then
            cleanup_children()
            srv:stop()
            return "bye"
        elseif cmd == "toggle" then
            return toggle(args) or "err"
        elseif cmd == "wallpaper" then
            spawn("wallpaper")
            return "spawned"
        end
        return nil, "unknown: " .. cmd .. " " .. args
    end,
}

log.info("events", "listo. socket: %s", SOCK_PATH)

srv:run()
cleanup_children()
log.info("events", "adios")
