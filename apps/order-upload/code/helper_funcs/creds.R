# Read/write the Benchling credentials in ~/.env_benchling.

CREDS_FILE <- path.expand("~/.env_benchling")
CREDS_KEYS <- c("BENCHLING_TEST_TENANT_URL", "BENCHLING_TEST_API_KEY",
                "BENCHLING_PROD_TENANT_URL", "BENCHLING_PROD_API_KEY")
CREDS_REQ  <- c("BENCHLING_TEST_TENANT_URL", "BENCHLING_TEST_API_KEY")

creds_read <- function() {
    conf <- read_env_file(CREDS_FILE)
    as.list(conf[intersect(names(conf), CREDS_KEYS)])
}

creds_get <- function(cur, key) if (key %in% names(cur)) cur[[key]] else ""

# Blank incoming keeps what's on disk; keys the form doesn't own survive a save untouched.
creds_write <- function(incoming) {
    merged <- as.list(read_env_file(CREDS_FILE))
    for (k in intersect(CREDS_KEYS, names(incoming))) {
        v <- trimws(as.character(if (is.null(incoming[[k]])) "" else incoming[[k]]))
        if (nzchar(v)) merged[[k]] <- v
    }
    missing <- setdiff(CREDS_REQ, names(merged)[nzchar(unlist(merged))])
    if (length(missing)) stop("missing: ", paste(missing, collapse = ", "))
    write_env_file(CREDS_FILE, merged)
}
