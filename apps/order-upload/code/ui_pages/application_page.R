# Sidebar (Refresh) | orders table (col1) | detail scaffold (col2).
# Detail widgets are static and updated in place — re-creating an actionButton resets
# its click counter and can spuriously fire observeEvent.

main_contents <- tags$div(
    tags$div(
        id = "main_contents", class = "row",
        tags$div(
            class = "col", id = "main_contents_col1",
            tags$p("Orders", class = "h5 text-primary fw-bold", style = "margin-bottom: 2px;"),
            tags$p("Click an order to upload it to Benchling or clean it up.",
                   class = "text-secondary", style = "font-size: 13px;"),
            tags$div(id = "orders_spinner", class = "orders-loading",
                     tags$div(class = "spinner"),
                     tags$span("Loading orders…")),
            tags$div(id = "uploaded_wrap", style = "display: none;",
                fluidRow(column(6, selectInput("uploaded", "Uploaded",
                                               c("All", "Yes", "No", "Failed"))))),
            DT::DTOutput("orders_table")
        ),
        tags$div(
            class = "col", id = "main_contents_col2",
            tags$div(
                id = "detail", style = "display: none;",
                tags$p(class = "h5 text-primary fw-bold", style = "margin-bottom: 6px;",
                       textOutput("detail_title", inline = TRUE)),
                uiOutput("detail_status"),
                tags$div(
                    id = "loc_wrap", style = "display: none; margin-top: 6px;",
                    selectizeInput("upload_location", "Benchling location", choices = NULL, selected = "",
                        options = list(placeholder = "Search a location…",
                                       onInitialize = I("function() { this.setValue(''); }")))
                ),
                tags$div(style = "margin-top: 6px;",
                    actionButton("upload_btn", "Upload", class = "btn-primary btn-sm",
                                 style = "display: none;", disabled = "disabled")),
                tags$div(style = "margin-top: 14px; min-height: 22px;", uiOutput("run_status"))
            )
        )
    )
)

app_card <- tags$div(
    style = "height: 660px; font-size: 14px;",
    layout_sidebar(
        height = "100%", border_color = "rgba(227, 227, 227, 1)", bg = "rgba(255, 255, 255, 1)",
        sidebar = sidebar(
            width = 300, open = "always", bg = "rgba(238, 238, 238, 1)",
            tags$p("Orders", class = "h6 fw-bold", style = "margin-bottom: 2px;"),
            tags$p("Sync order files from disk and check which are already in Benchling.",
                   class = "text-secondary", style = "font-size: 13px;"),
            actionButton("refresh", "Refresh", class = "btn-primary", icon = icon("arrows-rotate"),
                         onclick = "var s=document.getElementById('orders_spinner'); if(s) s.style.display='';"),
            tags$div(style = "margin-top: 14px;", uiOutput("sidebar_status")),
            # Clean up is rare and destructive — a muted text link pinned to the bottom of the
            # sidebar, deliberately not a button, so nobody archives an order by a stray click.
            tags$div(style = "margin-top: auto; text-align: left;",
                     tags$div(id = "cleanup_wrap", style = "display: none;",
                              actionLink("cleanup_btn", "Clean up", class = "cleanup-link")),
                     tags$div(style = "margin-top: 8px;",
                              actionLink("creds_btn", "Benchling credentials", class = "cleanup-link")),
                     tags$div(style = "margin-top: 6px;", uiOutput("env_badge", inline = TRUE)))
        ),
        main_contents
    )
)

application_page <- bslib::nav_panel(
    tags$style(HTML("
        .btn { padding: 6px 10px; font-size: 14px; }

        .orders-loading { display: flex; align-items: center; gap: 10px; padding: 24px 2px;
                          color: #6c757d; font-size: 13px; }
        .orders-loading .spinner { width: 20px; height: 20px; border: 3px solid #dfe3e8;
                          border-top-color: rgba(0,11,140,1); border-radius: 50%;
                          animation: gs-spin 0.8s linear infinite; }
        @keyframes gs-spin { to { transform: rotate(360deg); } }

        .run-working { display: flex; align-items: center; gap: 8px; color: #6c757d; font-size: 13px; }
        .run-working .spinner { flex: none; width: 16px; height: 16px; border: 2px solid #dfe3e8;
                          border-top-color: rgba(0,11,140,1); border-radius: 50%;
                          animation: gs-spin 0.8s linear infinite; }

        /* Clean up: muted text link, not a button — low-emphasis, hard to hit by accident */
        .cleanup-link { font-size: 12px; color: #9aa0a6; text-decoration: none; }
        .cleanup-link:hover { color: #c1121f; text-decoration: underline; }
        #env_badge a { text-decoration: none; }
        #env_badge .env-tag { font-size: 12px; font-weight: 600; letter-spacing: .03em; }
        /* fill the sidebar's flex column so #cleanup_wrap's margin-top:auto pins it to the bottom */
        .sidebar-content { height: 100%; }

        #main_contents, #main_contents > #main_contents_col1, #main_contents > #main_contents_col2 { min-width: 0; }
        /* col1 hugs the ~640px table; col2 (detail pane) sits right beside it, capped so it
           doesn't stretch — avoids a big empty gap between the table and the detail pane. */
        #main_contents > #main_contents_col1 { flex: 0 1 640px; max-width: 640px; }
        #main_contents > #main_contents_col2 { flex: 1 1 360px; max-width: 620px; }
        #main_contents_col1 .dataTables_wrapper { width: 100%; }
        #main_contents_col1 table.dataTable { width: 100% !important; }

        /* checkR table theme. Set via the Bootstrap token, not a cell background, so
           DataTables' hover and .selected rules still win. */
        #main_contents_col1 .table { --bs-table-striped-bg: #eaf0fa; --bs-table-striped-color: #212529; }
        #main_contents_col1 table.dataTable thead th { background-color: #f2f5fb; vertical-align: top; }
        #main_contents_col1 td.dt-nowrap, #main_contents_col1 th.dt-nowrap { white-space: nowrap; }

        #main_contents_col1 .dataTables_paginate { margin-top: 10px; }
        #main_contents_col1 .dataTables_paginate .page-link { padding: 4px 10px; font-size: 13px; }
        #main_contents_col1 .dataTables_filter { float: right; margin-top: 4px; }
        #main_contents_col1 .dataTables_filter label { font-size: 13px; margin-bottom: 0; }
        #main_contents_col1 .dataTables_filter input { font-size: 13px; margin-left: 6px; }
        #uploaded_wrap .form-select { max-width: 240px; font-size: 13px; }
        #uploaded_wrap .control-label { font-size: 13px; margin-bottom: 2px; }
    ")),
    tags$script(HTML("
        Shiny.addCustomMessageHandler('toggleBtn', function(m){ var b=document.getElementById(m.id); if(b) b.disabled=m.disable; });
        Shiny.addCustomMessageHandler('showEl',   function(m){ var e=document.getElementById(m.id); if(e) e.style.display=m.show?'':'none'; });
        Shiny.addCustomMessageHandler('btnClass', function(m){ var b=document.getElementById(m.id); if(b){ if(m.remove) b.classList.remove(m.remove); if(m.add) b.classList.add(m.add);} });
        Shiny.addCustomMessageHandler('clearSel', function(m){ window._gsSelectedIds = []; });
        Shiny.addCustomMessageHandler('clearQuery', function(m){ history.replaceState({}, '', location.pathname); });
    ")),
    title = "Order Upload",
    page_banner("Order Upload"),
    app_card
)
