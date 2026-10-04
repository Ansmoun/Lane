return {
    meta = { name = "Ayu Dark" },
    colors = {
        bg        = "#0b0e14",  -- fondo del popup del panel
        fg        = "#bfbdb6",
        accent    = "#e6b450",
        urgent    = "#f07178",
        bg_card   = "#13171f",  -- fondo de cards (nuevo: entre bg y bg_focus)
        bg_focus  = "#1a1f28",  -- hover de tabs y botones
        bg_urgent = "#1a1f28",
        text_on_color = "#0b0e14",
    },
    semantic = {
        muted     = "#565b66",
        ghost     = "#1c212b",
        separator = "#242a35",  -- separadores visibles, distintos de bg_card
        weekend   = "#f07178",
        today_bg  = "#e6b450",
        today_fg  = "#0b0e14",
        usage_warn = "#ff8f40",
        usage_crit = "#f07178",
    },
    telemetry = {
        internet = "#d2a6ff",   -- violeta
        ram      = "#59c2ff",   -- azul
        gpu      = "#95e6cb",   -- turquesa
        cpu      = "#aad94c",   -- verde
        temp     = "#ffb454",   -- ámbar
        bright   = "#ff8f40",   -- naranja
        volume   = "#f07178",   -- coral
        battery  = "#39bae6",   -- celeste
        disk     = "#e6b450",   -- amarillo
    },
}
