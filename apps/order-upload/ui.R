# GenScript Orders — Shiny UI (clones the Sanavia checkR navbar/banner/footer theme).
library(shiny)
library(bslib)
library(DT)

app_dir <- paste0(getwd(), "/")
for (fl in list.files(paste0(app_dir, "code"), full.names = TRUE, recursive = TRUE)) source(fl)

theme <- bslib::bs_theme(version = 5, navbar_bg = "rgba(0, 11, 140, 1)",
                         nav_link_font_size = "16px !important")

# ?embed=creds serves the form alone, so the landing page can iframe it without the app around it.
embed_creds_page <- function() {
    bslib::page_fluid(
        theme = theme,
        tags$div(class = "p-3",
                 creds_fields(creds_read(), app_env_get("GS_ORDERS_DIR")),
                 actionButton("creds_save", "Save", class = "btn-primary"))
    )
}

app_page <- function() bslib::page_navbar(
    tags$head(tags$style(HTML(".navbar .nav.navbar-nav { display: none !important; }"))),
    title = tagList(
        tags$a(href = "/", style = "text-decoration: none;",
               tags$img(src = "img/sanavia_cream.png", height = "40px", style = "margin-right:8px;")),
        tags$a(href = "/",
               style = paste("color: rgba(255,255,255,0.92);", "text-decoration: none;",
                             "font-size: 17px;", "vertical-align: middle;"),
               "Order Upload")
    ),
    padding = 0,
    theme = theme,
    footer = footer_section(),
    application_page
)

function(request) {
    if (identical(parseQueryString(request$QUERY_STRING)$embed, "creds")) embed_creds_page()
    else app_page()
}
