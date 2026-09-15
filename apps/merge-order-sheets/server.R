# author: Kwame Okrah
# date: 2026-03-04

server = function(input, output, session) {
    dotenv::load_dot_env("~/.env_data_mart_order_upload")
    main_folder = Sys.getenv("GS_ORDERS_DIR")
    
    # Part I ------------------------------------------------------------ #
    # organize file paths by order

    order_files_paths = tryCatch(
        get_paths_by_order(main_folder),
        error = function(e) {
            error_msg = "'order_files_paths()' an error occurred."
            return(error_msg)
        }
    )
    
    table_front_page = tryCatch(
        make_front_page_table(order_files_paths),
        error = function(e) {
            error_msg = "'make_front_page_table()' an error occurred."
            return(error_msg)
        }
    )
    
    observe({
        if (!is.data.frame(table_front_page)) {
            showNotification(
                ui = table_front_page,
                type = "message",
                duration = 5
            )
        }else{
            sel = table_front_page$prod_date %in% "Unknown"
            
            if (sum(sel) > 1) {
                tmp = table_front_page$merge_date[sel]
                table_front_page$prod_date[sel] = tmp
            }
            
            output$front_table = DT::renderDataTable(DT::datatable({
                table_front_page
            },
            rownames = TRUE,
            selection = "single",
            options = list(pageLength=6,
                           dom = "tpf",
                           columnDefs = list(
                               list(className='dt-nowrap', targets='_all'))
            )))
            
            ui = tags$div(
                id = "main_contents2",
                class="row",
                tags$div(
                    class="col",
                    id="col1_div",
                    
                    tags$p("Merged order sheets table",
                           class="h5 text-primary fw-bold"),
                    tags$div(
                        id="table_div"
                    ),
                    tags$p("Select a row to download data",
                           class="h6 text-secondary"),
                    tags$p(""),
                    DT::dataTableOutput("front_table"),
                    downloadButton("download_order_sheets", 
                                   "Download Selected Order Sheet")
                ),
                tags$div(
                    class="col",
                    id="col2_div",
                    tags$p("Purity and concentration graph",
                           class="h5 text-primary fw-bold"),
                    tags$div(
                        id="table_div"
                    ),
                    tags$p("Select a row to see QC graph",
                           class="h6 text-secondary"),
                    tags$p(""),
                    
                    tags$div(
                        id="qc_preview_bottom"
                    ),
                    tags$div(
                        id="qc_preview_bottom1",
                    ),
                
                )
            )
            
            insertUI(
                "#main_contents",
                "afterEnd",
                ui=ui
            )
        }
        
    })
    
    ms_val = reactiveVal()
    ms_val2 = reactiveVal()
    observe({
        sel = input$front_table_rows_selected
        oid = table_front_page[sel, "order_id"]
        sel_paths = order_files_paths[[oid]]
        
        hold = list()

        # 1. engineering sheets
        engineering_sheets_p = sel_paths[grep("engineering_sheets", sel_paths)]
        if (length(engineering_sheets_p)) {
            for (i in engineering_sheets_p) {
                i_ = sapply(strsplit(i, "/"), function(x) x[length(x)])
                i_ = paste0(oid, "_", i_)
                hold[[i_]] = read.csv(i, header = T, check.names = F)
            }
        }
        
        # 2. merged sheets 
        mosp = sel_paths[grep("-merged-sheets.csv$", sel_paths)]
        mosp_ = sapply(strsplit(mosp, "/"), function(x) x[length(x)])
        mosp_ = gsub("-merged-sheets.csv", "_merged-sheets.csv", mosp_)
        ms = read.csv(mosp, header = T, check.names = F)
        hold[[mosp_]] = ms
        
        # 3. download info.
        info = Sys.info()
        si = data.frame(user=info["user"],
                        nodename=info["nodename"],
                        sysname=info["sysname"])
          
        si = cbind(si, table_front_page[sel,,drop=F])
        sin = paste0(oid, "_", Sys.Date(), "_download-info.csv")
        hold[[sin]] = si
        
        ms_val(hold)
        ms_val2(oid)
        
        output$plot = renderPlot( { 
                plot_qc_metrics(ms)
        }) 
        
        ui = tags$div(
            id="qc_preview_bottom1",
            card(
                plotOutput("plot", width = "100%", height = "350px")    
            )
        )
        
        removeUI("#qc_preview_bottom1")
        
        insertUI(
            "#qc_preview_bottom",
            "afterEnd",
            ui = ui
        )
        
    }) |> bindEvent(input$front_table_rows_selected)

    # download_order_sheets download handler
    output$download_order_sheets = downloadHandler(
        filename = function() {
            if (is.null(ms_val2())) {
                tmp = "EMPTY"
            }else{
                tmp = ms_val2()
            }
            paste0(tmp, "_", Sys.Date(), "_merged-order-sheets.zip")
        },
        content = function(file) {
            temp_dir = tempdir()
            
            RES = ms_val()
            files_to_zip = names(RES)
            full_paths = file.path(temp_dir, files_to_zip)
            
            for (j in 1:length(files_to_zip)) {
                write.csv(RES[[j]], file=full_paths[j], row.names=FALSE)    
            }
    
            # zip() records whatever paths you give it, so cd into temp_dir
            # first so the archive doesn't include the full absolute path
            old_wd = setwd(temp_dir)
            on.exit(setwd(old_wd))
            
            zip::zip(zipfile=file, files=files_to_zip)
        },
        contentType = "application/zip"
    )
    
    
    
    # Part II ----------------------------------------------------------- #
    clone_strategy_val = reactiveVal()
    order_summary_val = reactiveVal()
    location_map_val = reactiveVal()
    metadata_val = reactiveVal()
    merged_sheets_val = reactiveVal()
    eng_sheets_val = reactiveVal()
    
    observe({
        if (nchar(input$order_id_text) <= 1) {
            order_id_checks = FALSE
        }else{
            order_id_checks = TRUE
        }
        
        if (!order_id_checks) {
            showNotification(
                ui = paste("Please enter a valid order ID"),
                type = "message",
                duration = 5
            )
        }else{
            check1 = input$order_id_text %in% table_front_page$order_id
            
            if (check1) {
                showNotification(
                    ui = paste("Entered order ID exists. Select 'Update' option for updates."),
                    type = "message",
                    duration = 5
                ) 
            }else{
                removeUI("#order_id_div")
                removeUI("#goto_database_div")
                
                insertUI(
                    selector = "#current_date",
                    where = "afterEnd",
                    ui = tags$div(
                        id = "order_id_div",
                        tags$p(paste0("Order ID: ",
                                      input$order_id_text),
                               class="text-secondary"),
                        tags$p(""),
                        actionButton(inputId="reset_form", 
                                     label="Back to Frontpage",
                                     width="100%",
                                     disabled=FALSE),
                        tags$div(id="below_reset_div"),
                        tags$div(id="below_reset_div1")
                    )
                )
                
                clone_strategy_sheet_ui = tags$div(
                    class="col",
                    tags$p("Clone strategy",
                           class="h5 text-primary fw-bold"),
                    tags$div(
                        id="clone_strategy_sheet_div"
                    ),
                    fileInput("clone_strategy_file",
                              "Upload clone strategy sheet",
                              width="100%"),
                    actionButton("clone_strategy_preproc",
                                 "Preprocess Clone Strategy",
                                 width="100%",
                                 class="btn-secondary"),
                    tags$div(id="clone_strategy_preproc_bottom_div")
                )
                
                order_summary_sheet_ui = tags$div(
                    class="col",
                    tags$p("Order summary",
                           class="h5 text-primary fw-bold"),
                    tags$div(
                        id="order_summary_sheet_div"
                    ),
                    fileInput("order_summary_file",
                              "Upload order summary sheet",
                              width="100%"),
                    actionButton("order_summary_preproc",
                                 "Preprocess Order Summary",
                                 width="100%",
                                 class="btn-secondary",
                                 disabled=TRUE),
                    tags$div(id="order_summary_preproc_bottom_div")
                )
                
                location_map_sheet_ui = tags$div(
                    class="col",
                    tags$p("Location map",
                           class="h5 text-primary fw-bold"),
                    tags$div(
                        id="location_map_sheet_div"
                    ),
                    fileInput("location_map_file",
                              "Upload location map sheet",
                              width="100%"),
                    actionButton("location_map_preproc",
                                 "Preprocess Location Map",
                                 width="100%",
                                 class="btn-secondary",
                                 disabled=TRUE),
                    tags$div(id="location_map_preproc_bottom_div")
                )
                
                order_report_sheet_ui = tags$div(
                    class="col",
                    tags$div(
                        id="order_report_sheet_div"
                    ),
                    tags$div(
                        id="order_report_sheet_div1",
                        tags$p("Order report",
                               class="h5 text-primary fw-bold"),
                        tags$div(
                            id="order_report_sheet_div"
                        ),
                        fileInput("order_report_file",
                                  "Upload order report pdf",
                                  width="100%"),
                        actionButton("order_report_info",
                                     "Get Report Information",
                                     class="btn-secondary",
                                     width="100%",
                                     disabled=TRUE),
                        tags$div(id="order_report_info_bottom_div")
                    ),
                )
                
                ui = tags$div(
                    id = "main_contents2",
                    class="row",
                    clone_strategy_sheet_ui,
                    order_summary_sheet_ui,
                    location_map_sheet_ui,
                    order_report_sheet_ui
                )

                removeUI("#main_contents2")
                
                insertUI(
                    selector="#main_contents",
                    where="afterEnd",
                    ui=ui
                )
            }
        }
        
    }) |> bindEvent(input$submit_order_id)
    
    observe({
        session$reload()
    }) |> bindEvent(input$reset_form)

    # 2. clone_strategy_preproc
    observe({
        datapath = input$clone_strategy_file$datapath
        
        if (is.null(datapath)) {
            showNotification(
                ui = paste("Please select a clone strategy file."),
                type = "message",
                duration = 5
            )
        }else{
            ftype = sapply(strsplit(datapath, "\\."), function(x) x[length(x)])
            
            if (!ftype %in% c("xlsx", "xls")) {
                showNotification(
                    ui = paste("Please load an excel file."),
                    type = "message",
                    duration = 5
                )
            }else{
                clone_strategy_df = tryCatch(
                    preproc_clone_strategy(datapath),
                    error = function(e) {
                        error_msg = "An error occurred in 'preproc_clone_strategy()'."
                        return(error_msg)
                    }
                )
                if (!is.data.frame(clone_strategy_df)) {
                    showNotification(
                        ui = clone_strategy_df,
                        type = "message",
                        duration = 5
                    )
                }else{
                    clone_strategy_df = preproc_clone_strategy(datapath)
                    check = clone_strategy_df_preproc(clone_strategy_df)
                    if (!check == "pass") {
                        showNotification(
                            ui = check,
                            type = "message",
                            duration = 5
                        )
                    }else{
                        order_id = clone_strategy_df[,"Order ID"]
                        obs_order_id = unique(sapply(strsplit(order_id, "-"), "[[", 1))
                        if (!input$order_id_text == obs_order_id) {
                            showNotification(
                                ui = paste0("The Order ID entered does not match the observed: ",
                                            obs_order_id),
                                type = "message",
                                duration = 5
                            )
                        }else{
                            cn = colnames(clone_strategy_df)
                            msg1 = obs_order_id
                            msg2 = paste0(length(cn), 
                                          " cols & ",
                                          nrow(clone_strategy_df),
                                          " rows")
                            msg = paste0(msg1, " (", msg2, ")")
                            
                            output$clone_strategy_table = DT::renderDataTable(DT::datatable({
                                data.frame(
                                    "Column"=1:length(cn),
                                    "Name"=cn
                                )
                            },
                            rownames = FALSE,
                            options = list(pageLength = 4,
                                           dom = "tpf",
                                           columnDefs = list(
                                               list(className='dt-nowrap', targets='_all'))
                            )))
                            
                            ui = tags$div(
                                id="clone_strategy_preproc_bottom_div1",
                                tags$p(""),
                                tags$br(),
                                tags$p(msg,
                                       class="h6 text-secondary"),
                                DT::dataTableOutput("clone_strategy_table"),
                            )
                            
                            removeUI("#clone_strategy_preproc_bottom_div1")
                            
                            insertUI(
                                selector="#clone_strategy_preproc_bottom_div",
                                where="afterEnd",
                                ui=ui
                            )
                            
                            updateActionButton(session, 
                                               "order_summary_preproc", 
                                               disabled=FALSE)
                            
                            clone_strategy_val(clone_strategy_df)
                        }
                    }
                }
            }
        }
        
    }) |> bindEvent(input$clone_strategy_preproc)
    
    # 3. order_summary_preproc
    observe({
        datapath = input$order_summary_file$datapath
        
        if (is.null(datapath)) {
            showNotification(
                ui = paste("Please select an order summary file."),
                type = "message",
                duration = 5
            )
        }else{
            
            ftype = sapply(strsplit(datapath, "\\."), function(x) x[length(x)])
            
            if (!ftype %in% c("xlsx", "xls")) {
                showNotification(
                    ui = paste("Please load an excel file."),
                    type = "message",
                    duration = 5
                )
            }else{
                
                order_summary_df = tryCatch(
                    preproc_order_summary(datapath),
                    error = function(e) {
                        error_msg = "An error occurred in 'preproc_order_summary()'."
                        return(error_msg)
                    }
                )
                
                if (!is.data.frame(order_summary_df)) {
                    showNotification(
                        ui = order_summary_df,
                        type = "message",
                        duration = 5
                    )
                }else{
                    check = order_summary_df_preproc(order_summary_df)
                    if (!check == "pass") {
                        showNotification(
                            ui = check,
                            type = "message",
                            duration = 5
                        )
                    }else{
                        order_id = order_summary_df[,"Order ID"]
                        obs_order_id = unique(sapply(strsplit(order_id, "-"), "[[", 1))
                        if (!input$order_id_text == obs_order_id) {
                            showNotification(
                                ui = paste0("The Order ID entered does not match the observed: ",
                                            obs_order_id),
                                type = "message",
                                duration = 5
                            )
                        }else{
                            clone_strategy_df = clone_strategy_val()
                            
                            id1 = clone_strategy_df[,"Protein Name"]
                            id2 = order_summary_df[,"Name"]
                            
                            if (!length(id1)==length(id2)) {
                                id_check = FALSE    
                            }else{
                                if (!all(sort(id1)==sort(id2))) {
                                    id_check = FALSE
                                }else{
                                    id_check = TRUE
                                }
                            } 
                            
                            if (!id_check) {
                                showNotification(
                                    ui = "Clone_Strategy 'Protein Name' and Order_Summary 'Name' do not match!",
                                    type = "message",
                                    duration = 5
                                )
                            }else{
                                cn = colnames(order_summary_df)
                                msg1 = obs_order_id
                                msg2 = paste0(length(cn),
                                              " cols & ",
                                              nrow(order_summary_df),
                                              " rows")
                                msg = paste0(msg1, " (", msg2, ")")
                                
                                output$order_summary_table = DT::renderDataTable(DT::datatable({
                                    data.frame(
                                        "Column"=1:length(cn),
                                        "Name"=cn
                                    )
                                },
                                rownames = FALSE,
                                options = list(pageLength = 4,
                                               dom = "tpf",
                                               columnDefs = list(
                                                   list(className='dt-nowrap', targets='_all'))
                                )))
                                
                                ui = tags$div(
                                    id="order_summary_preproc_bottom_div1",
                                    tags$p(""),
                                    tags$br(),
                                    tags$p(msg,
                                           class="h6 text-secondary"),
                                    DT::dataTableOutput("order_summary_table"),
                                )
                                
                                removeUI("#order_summary_preproc_bottom_div1")
                                
                                insertUI(
                                    selector="#order_summary_preproc_bottom_div",
                                    where="afterEnd",
                                    ui=ui
                                )
                                
                                updateActionButton(session,
                                                   "location_map_preproc",
                                                   disabled=FALSE)
                                
                                order_summary_val(order_summary_df)
              
                            }
                        }
                    }
                }
            }
        }
        
    }) |> bindEvent(input$order_summary_preproc)
    
    # 4. location_map_preproc
    observe({
        datapath = input$location_map_file$datapath
        
        if (is.null(datapath)) {
            showNotification(
                ui = paste("Please select a location map file."),
                type = "message",
                duration = 5
            )
        }else{
            ftype = sapply(strsplit(datapath, "\\."), function(x) x[length(x)])
            
            if (!ftype %in% c("xlsx", "xls")) {
                showNotification(
                    ui = paste("Please load an excel file."),
                    type = "message",
                    duration = 5
                )
            }else{
                location_map_df_0 = tryCatch(
                    preproc_location_map(datapath),
                    error = function(e) {
                        error_msg = "An error occurred in 'preproc_location_map()'."
                        return(error_msg)
                    }
                )
                
                if (!is.data.frame(location_map_df_0)) {
                    showNotification(
                        ui = location_map_df_0,
                        type = "message",
                        duration = 5
                    )
                }else{
                    location_map_df = flatten_location_map(location_map_df_0)
                    
                    order_id = location_map_df[,"Order ID"]
                    obs_order_id = unique(sapply(strsplit(order_id, "-"), "[[", 1))
                    if (!input$order_id_text == obs_order_id) {
                        showNotification(
                            ui = paste0("The Order ID entered does not match the observed: ",
                                        obs_order_id),
                            type = "message",
                            duration = 5
                        )
                    }else{
                        clone_strategy_df = clone_strategy_val()
                        
                        id1 = clone_strategy_df[,"Protein Name"]
                        id2 = location_map_df[,"Name"]
                        
                        if (!length(id1)==length(id2)) {
                            id_check = FALSE    
                        }else{
                            if (!all(sort(id1)==sort(id2))) {
                                id_check = FALSE
                            }else{
                                id_check = TRUE
                            }
                        }
                        
                        if (!id_check) {
                            showNotification(
                                ui = "Clone_Strategy 'Protein Name' and Location_Map 'Name' do not match!",
                                type = "message",
                                duration = 5
                            )
                        }else{
                            
                            cn = colnames(location_map_df)
                            msg1 = obs_order_id
                            msg2 = paste0(length(cn),
                                          " cols & ",
                                          nrow(location_map_df),
                                          " rows")
                            msg = paste0(msg1, " (", msg2, ")")
                            
                            output$location_map_table = DT::renderDataTable(DT::datatable({
                                data.frame(
                                    "Column"=1:length(cn),
                                    "Name"=cn
                                )
                            },
                            rownames = FALSE,
                            options = list(pageLength = 4,
                                           dom = "tpf",
                                           columnDefs = list(
                                               list(className='dt-nowrap', targets='_all'))
                            )))
                            
                            ui = tags$div(
                                id="location_map_preproc_bottom_div1",
                                tags$p(""),
                                tags$br(),
                                tags$p(msg,
                                       class="h6 text-secondary"),
                                DT::dataTableOutput("location_map_table"),
                            )
                            
                            removeUI("#location_map_preproc_bottom_div1")
                            
                            insertUI(
                                selector="#location_map_preproc_bottom_div",
                                where="afterEnd",
                                ui=ui
                            )
                            
                            updateActionButton(session,
                                               "order_report_info",
                                               disabled=FALSE)
                            
                            location_map_val(location_map_df)
                            
                            removeUI("#below_reset_div1")
                            
                            ui2 = tags$div(
                                id="below_reset_div1",
                                tags$p(""),
                                tags$br(),
                                tags$p(""),
                                actionButton(inputId="proceed_to_metadata",
                                             label="Proceed to Metadata",
                                             class="btn-warning",
                                             width="100%",
                                             disabled=FALSE)
                            )
                            
                            ui3 = tags$div(
                                id="below_reset_div1",
                                tags$p(""),
                                tags$br(),
                                tags$p(""),
                                tags$p(paste0("100% Match Rate!"),
                                       class="h6 text-secondary"),
                                actionButton(inputId="merge_sheets",
                                             label="Merge Order Sheets",
                                             class="btn-primary",
                                             width="100%",
                                             disabled=FALSE)
                            )
                            
                            if (TRUE) {
                                insertUI(
                                    "#below_reset_div",
                                    "afterEnd",
                                    ui=ui2
                                )
                            }else{
                                insertUI(
                                    "#below_reset_div",
                                    "afterEnd",
                                    ui=ui3
                                )
                            }
                        }
                    }
                }  
            }
        }
        
    }) |> bindEvent(input$location_map_preproc)
    
    # 5. order_report_info
    observe({
        datapath = input$order_report_file$datapath
        
        if (is.null(datapath)) {
            showNotification(
                ui = paste("Please select an order report file."),
                type = "message",
                duration = 5
            )
        }else{
            
            ftype = sapply(strsplit(datapath, "\\."), function(x) x[length(x)])
            
            if (!ftype %in% c("pdf")) {
                showNotification(
                    ui = paste("Please load a pdf file."),
                    type = "message",
                    duration = 5
                )
            }else{
                meta_data = pdftools::pdf_info(datapath)
                
                ui = tags$div(
                    id="order_report_info_bottom_div1",
                    tags$p(""),
                    tags$br(),
                    tags$p(paste0("Date: ", meta_data$created),
                           class="h6 text-secondary"),
                    tags$p(paste0(meta_data$pages, " pages"),
                           class="h6 text-secondary")
                )
                
                removeUI("#order_report_info_bottom_div1")
                
                insertUI(
                    selector="#order_report_info_bottom_div",
                    where="afterEnd",
                    ui=ui
                )
            }
        }
        
    }) |> bindEvent(input$order_report_info)
    observe({
        removeUI("#order_report_sheet_div1")
        
        metadata_ui = tags$div(
            id = "order_report_sheet_div1",
            tags$p("Order metadata",
                   class="h5 text-secondary fw-bold"),
            tags$div(
                id="order_metadata_sheet_div"
            ),
            fileInput("order_metadata_file",
                      "Upload order metadata",
                      width="100%"),
            actionButton("order_metadata_preproc",
                         "Preprocess Order Metadata",
                         width="100%",
                         class="btn-secondary"),
            tags$div(id="order_metadata_bottom_div"),
            tags$div(id="order_metadata_bottom_div1")
        )
        
        insertUI(
            selector="#order_report_sheet_div",
            where="afterEnd",
            ui=metadata_ui
        )
        
    }) |> bindEvent(input$proceed_to_metadata)
    
    # 6. metadata_preproc
    observe({
        datapath = input$order_metadata_file$datapath
        
        if (is.null(datapath)) {
            showNotification(
                ui = paste("Please select a metadata file."),
                type = "message",
                duration = 5
            )
        }else{
            ftype = sapply(strsplit(datapath, "\\."), function(x) x[length(x)])
            
            if (!ftype %in% c("csv")) {
                showNotification(
                    ui = paste("Please load a csv file."),
                    type = "message",
                    duration = 5
                )
            }else{
                metadata_df = read.csv(datapath, header = T, check.names = F)
                
                if (!"assembly_id" %in% colnames(metadata_df)) {
                    showNotification(
                        ui = paste("'assembly_id' column is missing."),
                        type = "message",
                        duration = 5
                    )
                }else{
                    cn = colnames(metadata_df)
                    msg1 = input$order_id_text
                    msg2 = paste0(length(cn),
                                  " cols & ",
                                  nrow(metadata_df),
                                  " rows")
                    msg = paste0(msg1, " (", msg2, ")")
                    
                    output$metadata_table = DT::renderDataTable(DT::datatable({
                        data.frame(
                            "Column"=1:length(cn),
                            "Name"=cn
                        )
                    },
                    rownames = FALSE,
                    options = list(pageLength = 4,
                                   dom = "tpf",
                                   columnDefs = list(
                                       list(className='dt-nowrap', targets='_all'))
                    )))
                    
                    ui = tags$div(
                        id="order_metadata_bottom_div1",
                        tags$p(""),
                        tags$br(),
                        tags$p(msg,
                               class="h6 text-secondary"),
                        DT::dataTableOutput("metadata_table"),
                    )
                    
                    removeUI("#order_metadata_bottom_div1")
                    
                    insertUI(
                        selector="#order_metadata_bottom_div",
                        where="afterEnd",
                        ui=ui
                    )
                    
                    clone_strategy_df = clone_strategy_val()
                    over_lap = clone_strategy_df[,"Protein Name"] %in% metadata_df[,"assembly_id"]
                    over_lap_rate = paste0(round(mean(over_lap) * 100, 2), "%")
                    
                    removeUI("#below_reset_div1")
                    
                    ui2 = tags$div(
                        id="below_reset_div1",
                        tags$p(""),
                        tags$br(),
                        tags$p(""),
                        tags$p(paste0(over_lap_rate, " Match Rate!"),
                               class="h6 text-secondary"),
                        actionButton(inputId="merge_sheets",
                                     label="Merge Order Sheets",
                                     class="btn-primary",
                                     width="100%",
                                     disabled=FALSE)
                    )
                    
                    insertUI(
                        "#below_reset_div",
                        "afterEnd",
                        ui=ui2
                    )
                    
                    metadata_val(metadata_df)
                }
            }
        }
        
    }) |> bindEvent(input$order_metadata_preproc)
    
    # 7. merge_sheets
    observe({
        removeUI("#below_reset_div1")
        removeUI("#main_contents2")
        
        withProgress(message = 'Merge in progress...', 
                     value = 0, {
                         
                         order_summary_df = order_summary_val()
                         clone_strategy_df = clone_strategy_val()
                         location_map_df = location_map_val()
                         metadata_df = metadata_val()
                         
                         merge_id = order_summary_df[,"Name"]
                         rownames(clone_strategy_df) = clone_strategy_df[,"Protein Name"]
                         rownames(location_map_df) = location_map_df[,"Name"]
                         rownames(metadata_df) = metadata_df[,"assembly_id"]
                         
                         keep = !colnames(clone_strategy_df) %in% c("Order ID", "Protein Name")
                         clone_strategy_df = clone_strategy_df[merge_id,keep,drop=F]
                         
                         keep = !colnames(location_map_df) %in% c("Order ID", "Name")
                         location_map_df = location_map_df[merge_id,keep,drop=F]
                         
                         metadata_df = metadata_df[merge_id,,drop=F]
                         
                         na_assembly_id = is.na(metadata_df[,"assembly_id"])
                         if (any(na_assembly_id)) {
                             tmp = merge_id[na_assembly_id]
                             metadata_df[na_assembly_id,"assembly_id"] = tmp
                             metadata_df[na_assembly_id,"assembly_id_alias"] = tmp
                         }

                         merged_sheets_df = cbind(order_summary_df,
                                                  clone_strategy_df,
                                                  location_map_df,
                                                  merge_date = rep(Sys.Date(), length(merge_id)),
                                                  metadata_df)
                         
                         rownames(merged_sheets_df) = NULL
                         
                         merged_sheets_val(merged_sheets_df)
                     })
        
        if (all(merged_sheets_df$construction_id %in% "not_available")) {
            # start save
            sys_date_ = Sys.Date()
            sys_date = substr(sys_date_, 1, 7)
            main_folder_date = paste0(main_folder, "/", sys_date)
            
            if (!dir.exists(main_folder_date)) {
                dir.create(main_folder_date)
            }
            
            order_id_text = input$order_id_text
            main_folder_order = paste0(main_folder_date, "/", order_id_text)
            
            if (!dir.exists(main_folder_order)) {
                dir.create(main_folder_order)
            }
            
            main_merged_sheets = paste0(main_folder_order, "/merged_sheets")
            main_order_data = paste0(main_folder_order, "/order_data")
            
            if (!dir.exists(main_merged_sheets)) {
                dir.create(main_merged_sheets)
            }
            if (!dir.exists(main_order_data)) {
                dir.create(main_order_data)
            }
            
            main_merged_sheets_name = paste0(order_id_text, "_",
                                             sys_date_, 
                                             "-merged-sheets.csv")
            
            merged_sheets_path = paste0(main_merged_sheets, 
                                        "/", 
                                        main_merged_sheets_name)
            
            write.csv(merged_sheets_df, file=merged_sheets_path, row.names=F)
            
            hold = list(input$clone_strategy_file,
                        input$order_summary_file,
                        input$location_map_file,
                        input$order_report_file)
            
            for (i in 1:length(hold)) {
                info = hold[[i]]
                if (!is.null(info)) {
                    
                    loc_fl = paste0(main_order_data, "/",
                                    gsub(" ", "_", info[,"name"]))
                    
                    loc_fl = gsub("\\([0-9]+\\)", "", loc_fl)
                    
                    cmd = paste0("cp ",
                                 info[,"datapath"], " ",
                                 loc_fl)
                    system(cmd)
                }
            }
            
            ui2 = tags$div(
                id="below_reset_div1",
                tags$p(""),
                tags$br(),
                tags$p(""),
                tags$p("Merge complete!",
                       class="h6 text-secondary"),
                tags$br(),
                tags$p("You may exit app",
                       class="h6 text-secondary"),
            )
            
            insertUI(
                "#below_reset_div",
                "afterEnd",
                ui=ui2
            )
            
        }else{
            
            engineering_sheets = merged_sheets_df$engineering_sheet
            engineering_sheets = engineering_sheets[!is.na(engineering_sheets)]
            engineering_sheets = unique(engineering_sheets)
            
            sel = !merged_sheets_df$construction_id == "not_available"
            
            eng_sheets_tab = merged_sheets_df[sel, c("construction_id", 
                                                     "engineering_sheet"),
                                              drop=F]
            
            eng_sheets_tab = eng_sheets_tab[!is.na(eng_sheets_tab$engineering_sheet),,drop=F]
            
            eng_sheets_val(eng_sheets_tab)
            
            output$eng_tab = DT::renderDataTable(DT::datatable({
                data.frame(engineering_sheet=engineering_sheets)
            },
            rownames = TRUE,
            selection = "single",
            options = list(pageLength=5,
                           dom = "tpf",
                           columnDefs = list(
                               list(className='dt-nowrap', targets='_all'))
            )))
            
            ui_eng = tags$div(
                id ="main_contents2",
                class="row",
                tags$div(
                    class="col",
                    tags$p("Engineering Sheets Detected!",
                           class="h5 text-primary fw-bold"),
                    tags$p("Required engineering sheets are below"),
                    DT::dataTableOutput("eng_tab")
                ),
                
                tags$div(
                    class="col",
                    tags$p("Select the required sheets and upload"),
                    fileInput("eng_sheets_files",
                              NULL, 
                              buttonLabel = "Upload sheets", 
                              multiple = TRUE),
                    tags$br(),
                    actionButton(inputId="upload_eng_sheets", 
                                 label="Upload Engineering Sheets",
                                 class="btn-secondary",
                                 disabled=FALSE),
                ),
            )
            
            insertUI(
                "#main_contents",
                "afterEnd",
                ui=ui_eng
            )
        }
        
    }) |> bindEvent(input$merge_sheets)
    
    # 8. upload_eng_sheets
    observe({
        
        eng_sheets_tab = eng_sheets_val()
        
        datapath = input$eng_sheets_files$datapath
        file_names = input$eng_sheets_files$name
        
        if (is.null(datapath)) {
            showNotification(
                ui = paste("Please select sheets."),
                type = "message",
                duration = 5
            )
        }else{
            
            eng_sheets_tabl = split(eng_sheets_tab, eng_sheets_tab$engineering_sheet)
    
            nms = names(eng_sheets_tabl)
            file_names_check = nms %in% file_names
            
            if (!all(file_names_check)) {
                
                msg = paste0("The ff sheets are missing: ",
                             paste0(which(!file_names_check), collapse = ", "),
                             ".")
                
                showNotification(
                    ui = msg,
                    type = "message",
                    duration = 5
                )
                
            }else{
            
                names(datapath) = file_names
                
                eng_hold = list()
                msg_hold = list()
                
                for (k in nms) {
                    dat = read.csv(file = datapath[k], header = T, check.names = F)
                    
                    if (!"construction_id" %in% colnames(dat)) {
                        msg = "does not have a 'construction_id' column"
                    }else{
                        if (!all(eng_sheets_tabl[[k]]$construction_id %in% dat$construction_id)) {
                            msg = "construction ids missing"
                        }else{
                            msg = "pass"
                        }
                    }
                    
                    msg_hold[[k]] = msg
                    eng_hold[[k]] = dat
                }
                
                msg_hold = unlist(msg_hold)
                
                pcheck = msg_hold %in% "pass"
                if (!all(pcheck)) {
                    m1 = msg_hold[pcheck][1]
                    m2 = names(msg_hold)[pcheck][1]
                    
                    showNotification(
                        ui = paste0(m2, ": ", m1),
                        type = "message",
                        duration = 5
                    )
                    
                }else{
                    # all checks passed
                    merged_sheets_df = merged_sheets_val()
                    
                    # start save
                    sys_date_ = Sys.Date()
                    sys_date = substr(sys_date_, 1, 7)
                    main_folder_date = paste0(main_folder, "/", sys_date)
                    
                    if (!dir.exists(main_folder_date)) {
                        dir.create(main_folder_date)
                    }
                    
                    order_id_text = input$order_id_text
                    main_folder_order = paste0(main_folder_date, "/", order_id_text)
                    
                    if (!dir.exists(main_folder_order)) {
                        dir.create(main_folder_order)
                    }
                    
                    main_merged_sheets = paste0(main_folder_order, "/merged_sheets")
                    main_order_data = paste0(main_folder_order, "/order_data")
                    engineering_sheets_data = paste0(main_folder_order, "/engineering_sheets")
                    
                    if (!dir.exists(main_merged_sheets)) {
                        dir.create(main_merged_sheets)
                    }
                    if (!dir.exists(main_order_data)) {
                        dir.create(main_order_data)
                    }
                    if (!dir.exists(engineering_sheets_data)) {
                        dir.create(engineering_sheets_data)
                    }
                    
                    main_merged_sheets_name = paste0(order_id_text, "_",
                                                     sys_date_, 
                                                     "-merged-sheets.csv")
                    
                    merged_sheets_path = paste0(main_merged_sheets, 
                                                "/", 
                                                main_merged_sheets_name)
                    
                    write.csv(merged_sheets_df, file=merged_sheets_path, row.names=F)
                    
                    hold = list(input$clone_strategy_file,
                                input$order_summary_file,
                                input$location_map_file,
                                input$order_report_file)
                    
                    for (i in 1:length(hold)) {
                        info = hold[[i]]
                        if (!is.null(info)) {
                            
                            loc_fl = paste0(main_order_data, "/",
                                            gsub(" ", "_", info[,"name"]))
                            
                            loc_fl = gsub("\\([0-9]+\\)", "", loc_fl)
                            
                            cmd = paste0("cp ",
                                         info[,"datapath"], " ",
                                         loc_fl)
                            system(cmd)
                        }
                    }
                    
                    
                    for (fl in names(eng_hold)) {
                        flp = paste0(engineering_sheets_data, "/", fl)
                        Y = eng_hold[[fl]]
                        Y = cbind("order_id"=rep(input$order_id_text, nrow(Y)),
                                  Y)
                        write.csv(Y,
                                  file = flp,
                                  row.names = FALSE)
                    }
                    
                    
                    removeUI("#main_contents2")
                    removeUI("#below_reset_div1")
                    
                    ui2 = tags$div(
                        id="below_reset_div1",
                        tags$p(""),
                        tags$br(),
                        tags$p(""),
                        tags$p("Merge complete!",
                               class="h6 text-secondary"),
                        tags$br(),
                        tags$p("You may exit app",
                               class="h6 text-secondary"),
                    )
                    
                    insertUI(
                        "#below_reset_div",
                        "afterEnd",
                        ui=ui2
                    )
                    
                    
                }
            }
        }
        
    }) |> bindEvent(input$upload_eng_sheets)
    
}

