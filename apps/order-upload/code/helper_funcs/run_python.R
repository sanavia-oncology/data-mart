# Run the benchling python tools. wd = app_dir so their load_dotenv() finds .env;
# scripts passed by absolute path from scripts_dir (app_dir/scripts).

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L || (length(a) == 1L && is.na(a))) b else a

.script <- function(cfg, name) file.path(cfg$scripts_dir, name)

# Pin the status mirror's dir explicitly rather than leaning on the tools' <cwd>/logs default.
.penv <- function(cfg) c("current", GENSCRIPT_LOGS_DIR = cfg$logs_dir)

# genscript_status.py args for these ids (marker-based; no CSV needed).
.status_args <- function(ids, cfg) c(.script(cfg, "genscript_status.py"),
                                     as.vector(rbind("--order-id", ids)), "--env", cfg$env)

# Synchronous: one call -> named list {state, uploaded}; list() on failure. Only the fallback for
# when a finished run left nothing in the mirror (see status_cache.R).
py_status <- function(ids, cfg) {
    if (!length(ids)) return(list())
    res <- tryCatch(processx::run(cfg$py, .status_args(ids, cfg), wd = cfg$app_dir,
                                  env = .penv(cfg), error_on_status = FALSE, timeout = 120),
                    error = function(e) { message("[py_status] ", conditionMessage(e)); NULL })
    if (is.null(res) || res$status != 0L) {
        if (!is.null(res)) message("[py_status] exit ", res$status, ": ", res$stderr)
        return(list())
    }
    tryCatch(jsonlite::fromJSON(res$stdout, simplifyVector = FALSE), error = function(e) list())
}

# Asynchronous: start the status check in the background, JSON written to a temp file. Returns
# list(proc, outfile); the caller polls proc$is_alive() and parses outfile once it exits. Keeps the
# whole-table refresh off the UI thread so the app never freezes on a slow Benchling round-trip.
py_status_async <- function(ids, cfg) {
    outfile <- tempfile(fileext = ".json")
    proc <- processx::process$new(cfg$py, .status_args(ids, cfg), wd = cfg$app_dir,
                                  env = .penv(cfg), stdout = outfile, stderr = "|")
    list(proc = proc, outfile = outfile)
}

# Storage locations for the dropdown -> data.frame(id, name); 0 rows on failure. Backgrounded like
# the status check: SDK import + round trip is seconds, and it would sit in front of the first paint.
py_locations_async <- function(cfg) {
    outfile <- tempfile(fileext = ".json")
    args <- c(.script(cfg, "genscript_locations.py"), "--env", cfg$env)
    proc <- processx::process$new(cfg$py, args, wd = cfg$app_dir, env = .penv(cfg),
                                  stdout = outfile, stderr = "|")
    list(proc = proc, outfile = outfile)
}

py_locations_collect <- function(lp) {
    empty <- data.frame(id = character(), name = character(), stringsAsFactors = FALSE)
    locs <- tryCatch({
        txt <- paste(readLines(lp$outfile, warn = FALSE), collapse = "")
        if (nzchar(txt)) jsonlite::fromJSON(txt, simplifyDataFrame = TRUE) else NULL
    }, error = function(e) NULL)
    tryCatch(unlink(lp$outfile), error = function(e) NULL)
    if (is.null(locs) || !NROW(locs)) return(empty)
    data.frame(id = as.character(locs$id), name = as.character(locs$name), stringsAsFactors = FALSE)
}

# Long-running upload/cleanup. `-u` = unbuffered, so python's print() streams live over the
# pipe (the uploader's log() doesn't flush); stderr folded into stdout to keep order.
py_run_async <- function(kind, order, cfg, location = NULL) {
    spec <- switch(kind,
        upload  = c(.script(cfg, "genscript_order_uploader.py"), "--csv", order$csv_path,
                    "--location", location, "--env", cfg$env),
        cleanup = c(.script(cfg, "dev-tools/cleanup_run.py"), "--order-id", order$order_id,
                    "--env", cfg$env, "--yes"),
        stop("unknown kind: ", kind))
    processx::process$new(cfg$py, c("-u", spec), wd = cfg$app_dir, env = .penv(cfg),
                          stdout = "|", stderr = "2>&1")
}
