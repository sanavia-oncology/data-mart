# Read/write the Benchling credentials in ~/.env_benchling.

CREDS_FILE   <- path.expand("~/.env_benchling")
CREDS_KEYS   <- c("BENCHLING_TEST_TENANT_URL", "BENCHLING_TEST_API_KEY",
                  "GENSCRIPT_TEST_MARKER_FOLDER_ID", "BENCHLING_PROD_TENANT_URL",
                  "BENCHLING_PROD_API_KEY")
CREDS_SECRET <- c("BENCHLING_TEST_API_KEY", "BENCHLING_PROD_API_KEY")
CREDS_REQ    <- c("BENCHLING_TEST_TENANT_URL", "BENCHLING_TEST_API_KEY")

creds_read <- function() {
    if (!file.exists(CREDS_FILE)) return(list())
    lines <- trimws(readLines(CREDS_FILE, warn = FALSE))
    lines <- lines[nzchar(lines) & !startsWith(lines, "#")]
    m <- regmatches(lines, regexec("^([A-Za-z_][A-Za-z0-9_]*)=(.*)$", lines))
    out <- list()
    for (x in m) if (length(x) == 3L && x[2] %in% CREDS_KEYS)
        out[[x[2]]] <- sub("^'(.*)'$", "\\1", sub('^"(.*)"$', "\\1", trimws(x[3])))
    out
}

creds_get <- function(cur, key) if (key %in% names(cur)) cur[[key]] else ""

# Blank incoming value keeps what's on disk, so leaving a secret untouched can't wipe it.
creds_write <- function(incoming) {
    merged <- creds_read()
    for (k in intersect(CREDS_KEYS, names(incoming))) {
        v <- trimws(as.character(if (is.null(incoming[[k]])) "" else incoming[[k]]))
        if (nzchar(v)) merged[[k]] <- v
    }
    missing <- setdiff(CREDS_REQ, names(merged)[nzchar(unlist(merged))])
    if (length(missing)) stop("missing: ", paste(missing, collapse = ", "))
    ordered <- merged[intersect(CREDS_KEYS, names(merged))]
    tmp <- paste0(CREDS_FILE, ".tmp")
    writeLines(paste0(names(ordered), "=", unlist(ordered)), tmp)
    Sys.chmod(tmp, "0600")
    if (!file.rename(tmp, CREDS_FILE)) { unlink(tmp); stop("could not replace ", CREDS_FILE) }
}
