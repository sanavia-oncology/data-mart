# author: Kwame Okrah
# date: 2026-03-05

main_contents = tags$div(
    tags$div(
        id = "main_contents",
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

            radioButtons( 
                inputId = "order_type", 
                label = "Order Type", 
                choices = list( 
                    "New order" = 1, 
                    "Update" = 2
                ) 
            ),
            
            tags$div(id = "order_id_top_div"),
            
            tags$div(
                id = "order_id_div",
                
                textInput( 
                    "order_id_text", 
                    "Enter Order ID", 
                    placeholder = "Enter text...",
                    width = "100%"
                ),
                
                actionButton(inputId = "submit_order_id", 
                             label = "Submit",
                             class="btn-warning",
                             width = "100%")
            )
            
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
          
    title = "Order Sheets",
    page_banner("Merge Order Sheets"),
    
    app_card
)





