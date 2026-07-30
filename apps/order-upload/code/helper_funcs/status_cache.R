# Local mirror of each order's Benchling state, written by the python tools into
# <app>/logs/status-<env>.json (genscript_status_cache.py). A file read, so the table paints
# at startup without touching Benchling. Absent or unreadable -> list(), i.e. every order reads No
# until a Refresh checks.

status_cache_path <- function(cfg) file.path(cfg$logs_dir, sprintf("status-%s.json", cfg$env))

read_status_cache <- function(cfg) {
    path <- status_cache_path(cfg)
    if (!file.exists(path)) return(list())
    doc <- tryCatch({
        txt <- paste(readLines(path, warn = FALSE), collapse = "")
        if (nzchar(txt)) jsonlite::fromJSON(txt, simplifyVector = FALSE) else NULL
    }, error = function(e) NULL)
    orders <- if (is.list(doc)) doc$orders else NULL
    if (is.null(orders) || !is.list(orders)) list() else orders
}
