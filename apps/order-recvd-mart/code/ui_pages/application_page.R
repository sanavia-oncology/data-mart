# author: Kwame Okrah
# date: 2026-03-05

main_contents = tags$div(
    tags$div(
        id = "main_contents"
    )
)

app_card = tags$div(
    style="height: 660px; font-size: 14px;",

    layout_sidebar(
      height = "100%",
      border_color = "rgba(227, 227, 227, 1)",
      bg = "rgba(255, 255, 255, 1)",

      sidebar = sidebar(
                    width = 250,
                    open = "open",
                    bg = "rgba(238, 238, 238, 1)",
                    
                    tags$p(paste0("Today's date: ", Sys.Date()),
                           class="text-secondary"),
                    tags$div(
                        id="current_date"
                    ),
                    actionButton(inputId = "load_data", 
                                 label = "Load Data"),
                    ),
      
      main_contents
    )
)

application_page = bslib::nav_panel(
    tags$style(
        HTML("
            textarea.form-control {
            font-size: 13px;
            }
    
            .btn {
            padding: 6px 10px;
            font-size: 14px;
            }
    
            .cell-btn:hover {
            color: white;
            font-weight: bold;
            cursor: pointer;
            }
    
            #data_path { 
            color: #017BC2; 
            }
        ")
    ),
          
    title = "Download Orders",
    page_banner("Download Received Order Sheets"),
    
    app_card
)
