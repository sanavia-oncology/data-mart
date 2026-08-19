# author: Kwame Okrah
# date: 2026-03-04

library(shiny)
library(bslib)
library(DT)
library(shinyFiles)

# Set limit to 1 GB
options(shiny.maxRequestSize = 1000 * 1024^2)

# set app directory
app_dir = "/Users/kwameokrah/data-lifecycle-apps/data-mart/apps/merge-order-sheets/"

# load helper function
helper_funcs_dir = paste0(app_dir, "code")
helper_r_scripts = list.files(helper_funcs_dir, full.names=TRUE, recursive=TRUE)
for (fl in helper_r_scripts) source(fl)

# build core ui page components
pages_dir = paste0(app_dir, "code/ui_pages")
pages_r_scripts = list.files(pages_dir, full.names=TRUE, recursive=TRUE)
for (fl in pages_r_scripts) source(fl)

# build application page
theme = bslib::bs_theme(version = 5,
                        navbar_bg = "rgba(0, 11, 140, 1)",
                        nav_link_font_size = "16px !important")

bslib::page_navbar(

    title = tagList(
        tags$img(
            src = "img/sanavia_cream.png",
            height = "40px",
            style = "margin-right:5px;"
        ),
        ""
    ),

    padding = 0,
    theme = theme,
    underline = FALSE,
    footer = footer_section(),

    application_page
)
