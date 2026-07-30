# Read ~/.env_data_ingestion_apps (KEY=VALUE) and resolve app paths.

read_env_file <- function(path) {
    path <- path.expand(path)
    if (!file.exists(path)) return(stats::setNames(character(0), character(0)))
    lines <- trimws(readLines(path, warn = FALSE))
    lines <- lines[nzchar(lines) & !startsWith(lines, "#")]
    lines <- sub("^export[[:space:]]+", "", lines)
    m <- regmatches(lines, regexec("^([A-Za-z_][A-Za-z0-9_]*)=(.*)$", lines))
    keys <- vapply(m, function(x) if (length(x) == 3L) x[2] else NA_character_, character(1))
    vals <- vapply(m, function(x) if (length(x) == 3L) x[3] else NA_character_, character(1))
    ok <- !is.na(keys)
    vals <- sub('^"(.*)"$', "\\1", trimws(vals[ok]))
    vals <- sub("^'(.*)'$", "\\1", vals)
    stats::setNames(vals, keys[ok])
}

build_cfg <- function(app_dir) {
    conf <- read_env_file(Sys.getenv("DATA_INGESTION_ENV_FILE", "~/.env_data_ingestion_apps"))
    getv <- function(key, default = "") {
        if (key %in% names(conf) && nzchar(conf[[key]])) return(unname(conf[[key]]))
        v <- Sys.getenv(key, ""); if (nzchar(v)) v else default
    }
    app_dir <- normalizePath(app_dir, mustWork = FALSE)    # server.R passes a trailing slash
    if (!dir.exists(file.path(app_dir, "scripts"))) {      # runApp always chdirs here; fallback only
        alt <- getv("ORDER_UPLOAD_APP")
        if (nzchar(alt)) app_dir <- normalizePath(alt, mustWork = FALSE)
    }
    py <- getv("GENSCRIPT_PY")
    if (!nzchar(py)) py <- file.path(app_dir, "benchling-python-env", "bin", "python")
    list(
        app_dir     = app_dir,                             # .env + venv live here (python cwd)
        orders_dir  = getv("GS_ORDERS_DIR"),
        scripts_dir = file.path(app_dir, "scripts"),
        logs_dir    = file.path(app_dir, "logs"),          # error logs + the status mirror
        py          = py,
        env         = getv("GENSCRIPT_ENV", "test")
    )
}
