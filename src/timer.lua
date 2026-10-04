-- Reloj monotono en milisegundos. Usa clock_gettime para tener
-- tiempo real, no de CPU. os.clock() no sirve aqui: mide tiempo
-- de CPU del proceso, y el server pasa el rato bloqueado en poll.

local ffi = require("bindings.cdef.time")

local M = {}

local CLOCK_MONOTONIC = 1

local ts = ffi.new("struct timespec")
ffi.C.clock_gettime(CLOCK_MONOTONIC, ts)  -- una vez para asegurar

function M.now_ms()
    ffi.C.clock_gettime(CLOCK_MONOTONIC, ts)
    return tonumber(ts.tv_sec) * 1000 + math.floor(tonumber(ts.tv_nsec) / 1000000)
end

return M
