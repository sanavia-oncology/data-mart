# Discover orders under GS_ORDERS_DIR: <month>/<order>/<merged sheets csv>.

order_date_from_filename <- function(csv_path, order_id, month_folder) {
    m <- regmatches(basename(csv_path), regexpr("^[0-9]{8}", basename(csv_path)))
    if (length(m) == 1L) suppressWarnings(as.Date(m, "%Y%m%d")) else as.Date(NA)
}

# -> data.frame(order_id, order_date, csv_path), newest first. 0 rows = "no orders", not an error.
discover_orders <- function(orders_dir, date_source = order_date_from_filename) {
    empty <- data.frame(order_id = character(), order_date = as.Date(character()),
                        csv_path = character(), stringsAsFactors = FALSE)
    if (is.null(orders_dir) || !nzchar(orders_dir) || !dir.exists(orders_dir)) return(empty)
    rows <- list()
    for (mdir in list.dirs(orders_dir, recursive = FALSE, full.names = TRUE)) {
        for (odir in list.dirs(mdir, recursive = FALSE, full.names = TRUE)) {
            csvs <- list.files(odir, pattern = "-merged_sheets\\.csv$", full.names = TRUE)
            if (!length(csvs)) next
            d <- tryCatch(date_source(csvs[1], basename(odir), basename(mdir)),
                          error = function(e) as.Date(NA))
            rows[[length(rows) + 1L]] <- data.frame(
                order_id = basename(odir), order_date = d, csv_path = csvs[1],
                stringsAsFactors = FALSE)
        }
    }
    if (!length(rows)) return(empty)
    out <- do.call(rbind, rows)
    out[order(out$order_date, decreasing = TRUE, na.last = TRUE), , drop = FALSE]
}
