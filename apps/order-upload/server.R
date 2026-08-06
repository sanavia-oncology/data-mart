# GenScript Orders — server.

options(shiny.sanitize.errors = FALSE, shiny.fullstacktrace = TRUE)

server <- function(input, output, session) {
    cfg <- build_cfg(paste0(getwd(), "/"))
    # The iframed creds form has no table and no Benchling work — skip everything that serves them.
    embed <- identical(parseQueryString(isolate(session$clientData$url_search))$embed, "creds")

    # Tenant the app is pointed at. Session-scoped and always starts at test — a reload
    # never leaves you silently in prod. ecfg() is what every python call must use.
    env_rv <- reactiveVal("test")
    # cfg is captured once, so the creds form updates this instead of needing a restart.
    orders_dir_rv <- reactiveVal(cfg$orders_dir)
    ecfg   <- function() modifyList(cfg, list(env = isolate(env_rv()),
                                              orders_dir = isolate(orders_dir_rv())))

    orders_rv    <- reactiveVal(NULL)
    status_rv    <- reactiveVal(list())
    selected_rv  <- reactiveVal(character(0))   # selected bare ids (multi)
    queue_rv     <- reactiveVal(character(0))   # remaining ids in the current batch
    log_rv       <- reactiveVal(character(0))   # current run's output — kept for the error log, not shown live
    result_rv    <- reactiveVal(NULL)           # last finished run: list(kind, ok, order, logfile)
    status_busy  <- reactiveVal(FALSE)          # TRUE while the async Benchling sync runs
    sync_ok      <- reactiveVal(TRUE)   # FALSE after a failed sync: the cache can't prove upload state
    run_rv       <- reactiveValues(running = FALSE, order = NULL, kind = NULL, started = NULL, location = NULL)
    current_proc <- NULL   # plain var: must survive the poll's invalidations
    status_proc  <- NULL   # plain var: the async status-sync process, as list(proc, outfile)
    loc_proc     <- NULL   # plain var: the async location fetch, same shape

    LOG_CAP <- 4000L
    MAX_RUN_MIN <- 30
    log_dir <- cfg$logs_dir   # gitignored; holds failure logs + the status mirror

    # Dump a failed run's captured output to logs/<kind>-<order>-<ts>.log and return the path.
    write_error_log <- function(kind, order, lines) {
        dir.create(log_dir, showWarnings = FALSE, recursive = TRUE)
        path <- file.path(log_dir, sprintf("%s-%s-%s.log", kind, order %||% "run",
                                            format(Sys.time(), "%Y%m%d-%H%M%S")))
        tryCatch(writeLines(lines, path), error = function(e) NULL)
        path
    }

    # Backgrounded: fetching these inline held up the session function, and so the first paint.
    locations_rv <- reactiveVal(NULL)
    if (!embed) loc_proc <- tryCatch(py_locations_async(ecfg()), error = function(e) NULL)
    observe({
        lp <- loc_proc
        if (is.null(lp)) return()
        if (lp$proc$is_alive()) { invalidateLater(400); return() }
        loc_proc <<- NULL
        locations_rv(py_locations_collect(lp))
    })
    observe({
        locs <- locations_rv()
        if (is.null(locs)) return()
        choices <- if (NROW(locs)) stats::setNames(locs$id, sprintf("%s  (%s)", locs$name, locs$id)) else character(0)
        updateSelectizeInput(session, "upload_location", choices = choices, selected = "", server = FALSE)
    })

    append_log <- function(lines) {
        lines <- lines[nzchar(lines)]
        if (length(lines)) log_rv(utils::tail(c(log_rv(), lines), LOG_CAP))
    }
    drain_lines <- function() {
        p <- current_proc
        if (!is.null(p)) tryCatch(append_log(p$read_output_lines()), error = function(e) invisible())
    }

    # Background sync; the poll observe below folds the result in. Nothing waits on it.
    launch_status <- function(ids) {
        if (!is.null(status_proc)) {                      # cancel any in-flight sync
            tryCatch(if (status_proc$proc$is_alive()) status_proc$proc$kill(), error = function(e) NULL)
            tryCatch(unlink(status_proc$outfile), error = function(e) NULL)
            status_proc <<- NULL
        }
        if (!length(ids)) { status_busy(FALSE); return() }
        status_proc <<- tryCatch(py_status_async(ids, ecfg()), error = function(e) NULL)
        if (is.null(status_proc)) {
            showNotification("Could not start the Benchling check — is the python env built?",
                             type = "error", duration = 12)
            sync_ok(FALSE)
        }
        status_busy(!is.null(status_proc))
    }

    # A rejected key used to look identical to "nothing changed", so say which failure it was.
    sync_error_msg <- function(code, err) {
        txt <- paste(err, collapse = " ")
        if (grepl("401|Failed to authenticate|authentication_error", txt))
            "Benchling rejected the credentials (401). Open Set App Credentials and paste a current API key."
        else if (grepl("ERROR: set BENCHLING_", txt, fixed = TRUE))
            "Credentials are missing. Fill them in under Set App Credentials."
        else if (grepl("marker folder", txt, ignore.case = TRUE))
            sub(".*RuntimeError: ", "", txt)          # already actionable — pass it through
        else if (grepl("403|forbidden|permission", txt, ignore.case = TRUE))
            "Benchling refused the request (403) — that key has no access to this tenant."
        else if (grepl("Timeout|ConnectError|nodename nor servname|Name or service not known", txt))
            "Could not reach Benchling — check the network and the tenant URL."
        else
            paste0("Benchling check failed (exit ", code, "). Details in logs/.")
    }

    # complete or partial both mean "entities exist in Benchling" -> clean-up-eligible, not upload.
    # No entry = not uploaded, until a Refresh checks Benchling and corrects it.
    order_state <- function(v) if (is.null(v)) "none" else v$state %||% "none"

    # Patch only the orders whose state actually moved. Leaving status_rv untouched when a check
    # agrees with what's shown is what keeps the table from redrawing under the user.
    apply_states <- function(new) {
        cur <- status_rv()
        moved <- Filter(function(id) !identical(order_state(cur[[id]]), order_state(new[[id]])), names(new))
        if (!length(moved)) return(invisible(FALSE))
        for (id in moved) cur[[id]] <- new[[id]]
        status_rv(cur)
        invisible(TRUE)
    }

    # Disk only: the orders folder + the status file. No Benchling.
    load_orders <- function() {
        df <- discover_orders(ecfg()$orders_dir)
        orders_rv(df)
        selected_rv(intersect(selected_rv(), df$order_id))
        apply_states(read_status_cache(ecfg()))
        # Not from the DT's initComplete: an unchanged order set doesn't re-render, so it'd stick.
        session$sendCustomMessage("showEl", list(id = "orders_spinner", show = FALSE))
        df
    }
    # The run stamped the mirror on its way out, so this is a file read; live check only if it didn't.
    refresh_one_status <- function(id) {
        cached <- read_status_cache(ecfg())[[id]]
        st <- if (!is.null(cached)) stats::setNames(list(cached), id)
              else tryCatch(py_status(id, ecfg()), error = function(e) NULL)
        if (!is.null(st) && !is.null(st[[id]])) apply_states(st[id])
    }

    # Refresh is the only thing that talks to Benchling. Startup reads disk and stops there.
    observeEvent(input$refresh, {
        if (isTRUE(run_rv$running) || isTRUE(status_busy())) return()
        df <- load_orders()
        launch_status(if (nrow(df)) df$order_id else character(0))
    })
    # Or a fresh machine reads "No" for every order until someone hits Refresh.
    if (!embed) isolate({
        df0 <- load_orders()
        launch_status(if (nrow(df0)) df0$order_id else character(0))
    })

    # The sync's answer wins where it differs; a failed/empty run leaves the mirror's values alone.
    observe({
        if (!isTRUE(status_busy())) return()
        sp <- status_proc
        if (is.null(sp)) { status_busy(FALSE); return() }
        if (sp$proc$is_alive()) { invalidateLater(400); return() }
        st <- tryCatch({
            txt <- paste(readLines(sp$outfile, warn = FALSE), collapse = "")
            if (nzchar(txt)) jsonlite::fromJSON(txt, simplifyVector = FALSE) else list()
        }, error = function(e) list())
        code <- tryCatch(sp$proc$get_exit_status(), error = function(e) NA_integer_)
        err  <- tryCatch(sp$proc$read_all_error_lines(), error = function(e) character(0))
        tryCatch(unlink(sp$outfile), error = function(e) NULL)
        status_proc <<- NULL
        if (identical(code, 0L) && length(st)) {
            apply_states(st)
            sync_ok(TRUE)
        } else {
            showNotification(sync_error_msg(code, err), type = "error", duration = 15)
            if (length(err)) write_error_log("status", NULL, err)
            sync_ok(FALSE)
        }
        status_busy(FALSE)
    })

    # Split the current selection by Benchling status. `up` = has entities in Benchling
    # (complete OR partial) -> Clean up; `not` = nothing there -> Upload. A partial/failed
    # order routes to Clean up so we never re-upload on top of it and duplicate lots.
    selected_split <- reactive({
        st <- status_rv(); up <- character(0); not <- character(0)
        # Both actions key off a status we no longer trust, so offer neither.
        if (!sync_ok()) return(list(up = up, not = not))
        for (id in selected_rv()) {
            if (order_state(st[[id]]) %in% c("complete", "partial")) up <- c(up, id) else not <- c(not, id)
        }
        list(up = up, not = not)
    })

    output$sidebar_status <- renderUI({
        df <- orders_rv(); st <- status_rv()
        if (is.null(df) || !nrow(df))
            return(tags$p("No orders found. Set the orders folder in Set App Credentials.",
                          class = "text-secondary", style = "font-size: 13px;"))
        n_up   <- sum(vapply(df$order_id, function(i) identical(order_state(st[[i]]), "complete"), logical(1)))
        n_fail <- sum(vapply(df$order_id, function(i) identical(order_state(st[[i]]), "partial"),  logical(1)))
        if (!sync_ok())
            return(tagList(
                tags$p(sprintf("%d order%s found", nrow(df), if (nrow(df) == 1L) "" else "s"),
                       style = "margin: 0; font-size: 13px;"),
                # Outlives the error toast, so the blank column is never left unexplained.
                tags$p("Benchling unreachable — upload status unavailable.", class = "text-danger",
                       style = "margin: 0; font-size: 13px;")))
        tagList(
            tags$p(sprintf("%d order%s found", nrow(df), if (nrow(df) == 1L) "" else "s"), style = "margin: 0; font-size: 13px;"),
            tags$p(sprintf("%d already in Benchling", n_up), class = "text-secondary", style = "margin: 0; font-size: 13px;"),
            if (n_fail > 0L)
                tags$p(sprintf("%d failed upload%s — needs clean up", n_fail, if (n_fail == 1L) "" else "s"),
                       class = "text-danger", style = "margin: 0; font-size: 13px;"),
            if (isTRUE(status_busy()))
                tags$div(class = "run-working", style = "margin-top: 8px;",
                         tags$span(class = "spinner"), tags$span("Syncing with Benchling…"))
        )
    })

    orders_view <- reactive({
        df <- orders_rv()
        if (is.null(df) || !nrow(df))
            return(data.frame(`Order ID` = character(), `Order Date` = character(), Uploaded = character(), check.names = FALSE))
        st <- status_rv()
        uploaded <- if (!sync_ok()) rep("—", nrow(df)) else vapply(df$order_id, function(id)
            switch(order_state(st[[id]]), complete = "Yes", partial = "Failed", "No"), character(1))
        data.frame(`Order ID` = df$order_id,
                   `Order Date` = ifelse(is.na(df$order_date), "", format(df$order_date, "%Y-%m-%d")),
                   Uploaded = uploaded, check.names = FALSE, stringsAsFactors = FALSE)
    })

    orders_filtered = reactive({
        data = orders_view()
        if (!sync_ok()) return(data)     # every row reads "—"; a Yes/No filter would empty the table
        if (isTruthy(input$uploaded) && input$uploaded != "All") {
            data = data[data[["Uploaded"]] == input$uploaded, ]
        }
        data
    })

    orders_proxy <- DT::dataTableProxy("orders_table")

    # Runs before the observer below, so the clear and the page reset both reach the client
    # ahead of the redraw. Without selectPage a filter applied from page 2+ lands past the
    # end of the shorter result and the table comes up empty.
    observeEvent(input$uploaded, {
        selected_rv(character(0))
        session$sendCustomMessage("clearSel", list())
        DT::selectPage(orders_proxy, 1)
    }, ignoreInit = TRUE)

    # Render once per order-set; filter and status changes go through the proxy instead, so
    # the search box and the current page survive them.
    hide_spinner <- DT::JS("function(s){var el=document.getElementById('orders_spinner'); if(el) el.style.display='none';}")
    output$orders_table = DT::renderDataTable({
        if (is.null(orders_rv()) || !nrow(orders_rv()))
            return(DT::datatable(data.frame(Message = "No orders found — set the orders folder in Set App Credentials."),
                                 rownames = FALSE, options = list(dom = "t", paging = FALSE, initComplete = hide_spinner)))
        # OS-style selection via the Select extension: single click = one row, Cmd/Ctrl = toggle,
        # Shift = range. DT's own selection is off; we push the selected order ids to Shiny ourselves.
        # drawCallback re-applies the selection after every redraw (e.g. the status replaceData),
        # which would otherwise drop the Select highlight; the suppress flag stops that re-select
        # from echoing back to Shiny.
        DT::datatable(isolate(orders_filtered()), rownames = FALSE, extensions = "Select",
        selection = 'none',
        options = list(pageLength = 7,
                       dom = "tpf",
                       columnDefs = list(
                           list(className = 'dt-nowrap', targets = '_all')),
                       initComplete = hide_spinner,
                       select = list(style = "os", items = "row"),
                       drawCallback = DT::JS(
                           "function() {",
                           "  var ids = window._gsSelectedIds || [];",
                           "  if (!ids.length) return;",
                           "  window._gsSuppressSelect = true;",
                           "  this.api().rows().every(function() {",
                           "    var d = this.data(); if (d && ids.indexOf(d[0]) >= 0) this.select();",
                           "  });",
                           "  window._gsSuppressSelect = false;",
                           "}")),
        # Server-side processing keeps only the current page client-side, so the select event
        # can't see off-page rows — merge them back in by hand, keyed on the modifier.
        callback = DT::JS(
            "var gsMod = false;",
            "$(table.table().container()).on('mousedown', 'tbody tr', function(e) {",
            "  gsMod = e.ctrlKey || e.metaKey || e.shiftKey;",
            "});",
            "table.on('select deselect', function() {",
            "  if (window._gsSuppressSelect) return;",
            "  var page = table.rows().data().toArray().map(function(r){return r[0];});",
            "  var ids = table.rows({selected:true}).data().toArray().map(function(r){return r[0];});",
            "  if (gsMod) {",
            "    ids = (window._gsSelectedIds || []).filter(function(id){ return page.indexOf(id) < 0; }).concat(ids);",
            "  }",
            "  window._gsSelectedIds = ids;",
            "  Shiny.setInputValue('orders_selected_ids', ids, {priority:'event'});",
            "});"))
    }, server = TRUE)

    # Skipped while the "no orders" message table is up — its single column would break replaceData.
    observe({
        if (embed) return()
        data <- orders_filtered()
        if (is.null(orders_rv()) || !nrow(orders_rv())) return()
        DT::replaceData(orders_proxy, data, resetPaging = FALSE, rownames = FALSE, clearSelection = "none")
    })

    observeEvent(input$orders_selected_ids, {
        ids <- input$orders_selected_ids; df <- orders_rv()
        selected_rv(if (is.null(df) || !length(ids)) character(0) else intersect(df$order_id, ids))
    }, ignoreNULL = FALSE)

    # ---- detail pane (static scaffold, updated in place) ----
    output$detail_title <- renderText({
        ids <- selected_rv()
        if (!length(ids)) "" else if (length(ids) == 1L) ids else sprintf("%d orders selected", length(ids))
    })
    output$detail_status <- renderUI({
        ids <- selected_rv(); if (!length(ids)) return(NULL)
        sp <- selected_split()
        syncing <- if (isTRUE(status_busy()))
            tags$p("Checking Benchling…", class = "text-secondary", style = "font-size: 12px; margin: 4px 0 0;")
        body <- if (length(ids) == 1L) {
            state <- order_state(status_rv()[[ids]])
            if (identical(state, "complete"))
                tags$p("In Benchling — upload complete.", class = "text-secondary", style = "font-size: 13px;")
            else if (identical(state, "partial"))
                tags$p("Failed / incomplete upload — the push didn't finish (no completion marker). Clean it up, then upload again.",
                       class = "text-danger", style = "font-size: 13px;")
            else tags$p("Not in Benchling. Pick a location, then Upload.", class = "text-secondary", style = "font-size: 13px;")
        } else {
            parts <- c(if (length(sp$not)) sprintf("%d to upload", length(sp$not)),
                       if (length(sp$up)) sprintf("%d in Benchling", length(sp$up)))
            tagList(
                tags$p(paste(parts, collapse = " · "), class = "text-secondary",
                       style = "font-size: 13px; margin-bottom: 0;"),
                if (length(sp$not) && length(sp$up))
                    tags$p("Select only not-in-Benchling orders to upload them.",
                           class = "text-secondary", style = "font-size: 12px; margin: 2px 0 0;")
            )
        }
        tagList(body, syncing)
    })
    # No live log stream — just a plain status: a "working" note while running, then a finished
    # line (in the order-ID font) on success, or an error note pointing at the log file on failure.
    output$run_status <- renderUI({
        if (isTRUE(run_rv$running)) {
            msg <- if (identical(run_rv$kind, "cleanup"))
                "Cleaning up in Benchling — this takes about 3–5 minutes."
            else
                "Uploading to Benchling — this takes about 3–5 minutes."
            return(tags$div(class = "run-working", tags$span(class = "spinner"), tags$span(msg)))
        }
        res <- result_rv(); if (is.null(res)) return(NULL)
        if (isTRUE(res$ok))
            return(tags$p(if (identical(res$kind, "cleanup")) "Clean up finished" else "Upload finished",
                          class = "h5 text-primary fw-bold", style = "margin: 0;"))
        tagList(
            tags$p(sprintf("%s failed — an error occurred.",
                           if (identical(res$kind, "cleanup")) "Clean up" else "Upload"),
                   class = "text-danger fw-bold", style = "font-size: 13px; margin: 0 0 2px;"),
            tags$p(sprintf("Error logs are at %s", res$logfile %||% log_dir),
                   class = "text-secondary", style = "font-size: 12px; margin: 0; word-break: break-all;")
        )
    })
    outputOptions(output, "detail_title",  suspendWhenHidden = FALSE)
    outputOptions(output, "detail_status", suspendWhenHidden = FALSE)
    outputOptions(output, "run_status",    suspendWhenHidden = FALSE)

    observe({ session$sendCustomMessage("showEl", list(id = "detail", show = length(selected_rv()) > 0)) })

    # Location + Upload appear only for a pure not-uploaded selection; Clean up whenever
    # an uploaded order is selected. Cleanup never involves a location.
    # Mirror statuses are fine to show, not to act on until the sync confirms them: pushing on top
    # of a stale "not uploaded" duplicates an order.
    observe({
        running <- isTRUE(run_rv$running); syncing <- isTRUE(status_busy())
        sp <- selected_split(); n_not <- length(sp$not); n_up <- length(sp$up)
        pure_upload <- n_not > 0L && n_up == 0L
        updateActionButton(session, "upload_btn",  label = if (n_not > 1L) sprintf("Upload %d", n_not) else "Upload")
        updateActionButton(session, "cleanup_btn", label = if (n_up  > 1L) sprintf("Clean up %d", n_up) else "Clean up")
        session$sendCustomMessage("showEl", list(id = "uploaded_wrap", show = !is.null(orders_rv()) && nrow(orders_rv()) > 0))
        session$sendCustomMessage("showEl", list(id = "loc_wrap",    show = pure_upload))
        session$sendCustomMessage("showEl", list(id = "upload_btn",  show = pure_upload))
        session$sendCustomMessage("showEl", list(id = "cleanup_wrap", show = n_up > 0L && !running && !syncing))
        session$sendCustomMessage("toggleBtn", list(id = "upload_btn",  disable = running || syncing || !pure_upload || !isTruthy(input$upload_location)))
        session$sendCustomMessage("toggleBtn", list(id = "refresh",     disable = running || syncing))
    })

    # ---- batch queue: run the selected orders one by one ----
    start_next <- function() {
        q <- queue_rv()
        if (!length(q)) { run_rv$running <- FALSE; return() }
        id <- q[1]; queue_rv(q[-1])
        ord <- orders_rv()[orders_rv()$order_id == id, , drop = FALSE]
        if (!nrow(ord)) { start_next(); return() }
        log_rv(character(0))   # fresh buffer per order, so an error log holds only that order
        append_log(sprintf("$ %s %s", run_rv$kind, id))
        run_rv$running <- TRUE; run_rv$order <- id; run_rv$started <- Sys.time()
        loc <- if (identical(run_rv$kind, "upload")) run_rv$location else NULL
        current_proc <<- tryCatch(py_run_async(run_rv$kind, ord[1, ], ecfg(), location = loc),
            error = function(e) { append_log(paste("[ERROR] launch:", conditionMessage(e))); NULL })
        if (is.null(current_proc)) { run_rv$running <- FALSE; start_next() }
    }

    observeEvent(input$upload_btn, {
        if (isTRUE(run_rv$running)) return()
        ids <- selected_split()$not; if (!length(ids)) return()
        if (!isTruthy(input$upload_location)) return()   # button is disabled without a location anyway
        result_rv(NULL)
        run_rv$kind <- "upload"; run_rv$location <- input$upload_location
        queue_rv(ids); start_next()
    }, ignoreInit = TRUE)

    # Clean up is destructive — confirm (naming the order) before doing anything.
    observeEvent(input$cleanup_btn, {
        if (isTRUE(run_rv$running)) return()
        ids <- selected_split()$up; if (!length(ids)) return()
        msg <- if (length(ids) == 1L)
            sprintf("Are you sure you want to clean up order %s?", ids)
        else
            sprintf("Are you sure you want to clean up these %d orders (%s)?", length(ids), paste(ids, collapse = ", "))
        showModal(modalDialog(
            title = "Clean up order?",
            tags$p(msg),
            tags$p("This archives its lots, containers, boxes, and sequences in Benchling. The app can't undo it.",
                   class = "text-secondary", style = "font-size: 13px;"),
            footer = tagList(
                modalButton("Cancel"),
                actionButton("cleanup_confirm", "Clean up", class = "btn-danger")
            ),
            easyClose = TRUE
        ))
    }, ignoreInit = TRUE)

    reset_env_radio <- function() updateRadioButtons(session, "env_choice", selected = env_rv())

    observeEvent(input$env_choice, {
        to <- input$env_choice
        if (identical(to, env_rv())) return()
        if (identical(to, "prod")) {
            cur <- creds_read()
            if (!all(c("BENCHLING_PROD_TENANT_URL", "BENCHLING_PROD_API_KEY") %in% names(cur))) {
                showNotification("Production credentials are not set — add them in Set App Credentials.",
                                 type = "error", duration = 8)
                reset_env_radio()
                return()
            }
        }
        showModal(modalDialog(
            title = if (identical(to, "prod")) "Switch to PRODUCTION?" else "Switch back to test?",
            tags$p(sprintf("Uploads, clean-ups and status checks will run against the %s tenant.",
                           if (identical(to, "prod")) "production" else "test")),
            if (identical(to, "prod"))
                tags$p("Production has no GenScript schemas yet, so uploads there will fail.",
                       class = "text-secondary", style = "font-size: 13px;"),
            footer = tagList(actionButton("env_cancel", "Cancel"),
                             actionButton("env_confirm", "Switch",
                                          class = if (identical(to, "prod")) "btn-danger" else "btn-primary")),
            # No easyClose: a dismissed modal would leave the radio naming a tenant we never switched to.
            easyClose = FALSE
        ))
    }, ignoreInit = TRUE)

    observeEvent(input$env_cancel, {
        removeModal()
        reset_env_radio()
    }, ignoreInit = TRUE)

    observeEvent(input$env_confirm, {
        removeModal()
        if (isTRUE(run_rv$running)) { reset_env_radio(); return() }
        env_rv(input$env_choice)
        status_rv(list())            # the mirror is per-tenant; drop what the old one said
        df <- load_orders()
        launch_status(if (nrow(df)) df$order_id else character(0))   # same reason as startup
        showNotification(sprintf("Now using the %s tenant.", toupper(env_rv())), type = "message")
    }, ignoreInit = TRUE)

    show_creds_modal <- function() {
        cur <- creds_read()
        showModal(modalDialog(
            title = "Set App Credentials",
            tags$p(sprintf("Stored in %s, outside the repo, so recloning never destroys them.",
                           CREDS_FILE), class = "text-secondary", style = "font-size: 13px;"),
            creds_fields(cur, isolate(orders_dir_rv())),
            footer = tagList(modalButton("Cancel"),
                             actionButton("creds_save", "Save", class = "btn-primary")),
            easyClose = TRUE
        ))
    }

    observeEvent(input$creds_btn, show_creds_modal(), ignoreInit = TRUE)

    # ?creds=1 opens the form straight away, so the portal link lands where it says it does.
    # Drop the param once used, or every reload reopens the modal.
    observeEvent(session$clientData$url_search, once = TRUE, {
        if (identical(parseQueryString(session$clientData$url_search)$creds, "1")) {
            show_creds_modal()
            session$sendCustomMessage("clearQuery", list())
        }
    })

    observeEvent(input$creds_save, {
        typed  <- trimws(input$cr_orders %||% "")
        orders <- if (nzchar(typed)) path.expand(typed) else ""
        res <- tryCatch({
            # Checked before anything is written, so a typo can't half-save the form.
            if (nzchar(orders) && !dir.exists(orders)) stop("orders folder not found: ", typed)
            creds_write(list(BENCHLING_TEST_TENANT_URL = input$cr_test_url,
                             BENCHLING_TEST_API_KEY    = input$cr_test_key,
                             BENCHLING_PROD_TENANT_URL = input$cr_prod_url,
                             BENCHLING_PROD_API_KEY    = input$cr_prod_key))
            app_env_write(list(GS_ORDERS_DIR = orders))
            TRUE
        }, error = function(e) conditionMessage(e))
        if (isTRUE(res)) {
            removeModal()
            orders_dir_rv(orders)
            if (embed) {
                showNotification("Saved. Reload Order Upload to pick up the change.", type = "message")
            } else {
                load_orders()
                showNotification("Settings saved.", type = "message")
            }
        } else {
            showNotification(paste("Could not save:", res), type = "error", duration = 10)
        }
    }, ignoreInit = TRUE)

    # A browser folder picker can't return an absolute path, and R here runs on the user's own Mac.
    pick_rv <- reactiveVal(NULL)   # reactive, so launching the process wakes the poll below
    observeEvent(input$cr_orders_pick, {
        if (!is.null(pick_rv())) return()
        cur <- trimws(input$cr_orders %||% "")
        loc <- if (nzchar(cur) && dir.exists(cur)) sprintf(' default location (POSIX file "%s")', cur) else ""
        # Bare `activate` targets osascript itself; System Events would trigger an automation prompt.
        args <- c("-e", "activate",
                  "-e", sprintf('POSIX path of (choose folder with prompt "Select the orders folder"%s)', loc))
        pick_rv(tryCatch(processx::process$new("osascript", args, stdout = "|", stderr = "|"),
                         error = function(e) NULL))
        if (is.null(pick_rv()))
            showNotification("Could not open the folder picker.", type = "error", duration = 10)
    }, ignoreInit = TRUE)

    observe({
        p <- pick_rv()
        if (is.null(p)) return()
        if (p$is_alive()) { invalidateLater(300); return() }
        pick_rv(NULL)
        out <- tryCatch(trimws(paste(p$read_all_output_lines(), collapse = "")), error = function(e) "")
        if (!nzchar(out)) return()                       # cancel exits non-zero with no stdout
        if (nchar(out) > 1L) out <- sub("/$", "", out)   # `choose folder` returns a trailing slash
        updateTextInput(session, "cr_orders", value = out)
    })

    observeEvent(input$cleanup_confirm, {
        removeModal()
        if (isTRUE(run_rv$running)) return()
        ids <- selected_split()$up; if (!length(ids)) return()
        result_rv(NULL)
        run_rv$kind <- "cleanup"; run_rv$location <- NULL
        queue_rv(ids); start_next()
    }, ignoreInit = TRUE)

    finalize_run <- function(p) {
        drain_lines()
        ec <- tryCatch(p$get_exit_status(), error = function(e) NA_integer_)
        append_log(sprintf("-- exit %s --", if (is.na(ec)) "unknown" else ec))
        done <- run_rv$order; kind <- run_rv$kind
        if (!(!is.na(ec) && ec == 0L)) {
            logfile <- write_error_log(kind, done, log_rv())
            result_rv(list(kind = kind, ok = FALSE, order = done, logfile = logfile))
        } else if (is.null(result_rv()) || isTRUE(result_rv()$ok)) {
            result_rv(list(kind = kind, ok = TRUE, order = done))   # don't mask an earlier batch failure
        }
        current_proc <<- NULL
        run_rv$running <- FALSE
        if (!is.null(done)) refresh_one_status(done)
        start_next()   # advance to the next order in the batch (no-op if queue empty)
    }

    observe({
        if (!isTRUE(run_rv$running)) return()
        p <- current_proc
        if (is.null(p)) { run_rv$running <- FALSE; return() }
        drain_lines()
        over <- tryCatch(as.numeric(Sys.time() - run_rv$started, units = "mins") > MAX_RUN_MIN, error = function(e) FALSE)
        if (isTRUE(over) && p$is_alive()) {
            tryCatch(p$kill_tree(), error = function(e) NULL)
            append_log(sprintf("[TIMEOUT] killed after %dm", MAX_RUN_MIN))
            finalize_run(p); return()
        }
        if (p$is_alive()) invalidateLater(700) else finalize_run(p)
    })

    session$onSessionEnded(function() {
        pp <- isolate(pick_rv())
        if (!is.null(pp) && pp$is_alive()) tryCatch(pp$kill(), error = function(e) NULL)
        if (!is.null(current_proc) && current_proc$is_alive()) tryCatch(current_proc$kill_tree(), error = function(e) NULL)
        if (!is.null(status_proc) && status_proc$proc$is_alive()) tryCatch(status_proc$proc$kill(), error = function(e) NULL)
        if (!is.null(loc_proc) && loc_proc$proc$is_alive()) tryCatch(loc_proc$proc$kill(), error = function(e) NULL)
    })
}
