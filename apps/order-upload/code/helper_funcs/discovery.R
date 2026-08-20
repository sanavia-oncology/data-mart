# Discover orders written by merge-order-sheets:
# GS_ORDERS_DIR/<YYYY-MM>/<order>/merged_sheets/<order>_<type>_<YYYY-MM-DD>-merged-sheets.csv

order_date_from_filename <- function(csv_path, order_id, month_folder) {
    nm <- basename(csv_path)
    m <- regmatches(nm, regexpr("[0-9]{4}-[0-9]{2}-[0-9]{2}(?=-merged-sheets\\.csv$)",
                                nm, perl = TRUE))
    if (length(m) == 1L) suppressWarnings(as.Date(m)) else as.Date(NA)
}

# -> data.frame(order_id, order_date, csv_path), newest first. 0 rows = "no orders", not an error.
discover_orders <- function(orders_dir, date_source = order_date_from_filename) {
    empty <- data.frame(order_id = character(), order_date = as.Date(character()),
                        csv_path = character(), stringsAsFactors = FALSE)
    if (is.null(orders_dir) || !nzchar(orders_dir) || !dir.exists(orders_dir)) return(empty)
    rows <- list()
    for (mdir in list.dirs(orders_dir, recursive = FALSE, full.names = TRUE)) {
        # Every current-order folder is YEAR-MONTH; Legacy (and anything else) is not ours to read.
        if (!grepl("^[0-9]{4}-[0-9]{2}$", basename(mdir))) next
        for (odir in list.dirs(mdir, recursive = FALSE, full.names = TRUE)) {
            csvs <- list.files(file.path(odir, "merged_sheets"),
                               pattern = "-merged-sheets\\.csv$", full.names = TRUE)
            for (csv in csvs) {
                d <- tryCatch(date_source(csv, basename(odir), basename(mdir)),
                              error = function(e) as.Date(NA))
                rows[[length(rows) + 1L]] <- data.frame(
                    order_id = basename(odir), order_date = d, csv_path = csv,
                    stringsAsFactors = FALSE)
            }
        }
    }
    if (!length(rows)) return(empty)
    out <- do.call(rbind, rows)
    out <- out[order(out$order_date, decreasing = TRUE, na.last = TRUE), , drop = FALSE]
    # A re-merge lands under the month it ran in, so one order can exist twice — keep the newest.
    out[!duplicated(out$order_id), , drop = FALSE]
}
