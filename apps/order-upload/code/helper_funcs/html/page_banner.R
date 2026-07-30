# author: Kwame Okrah
# date: 2025-11-09

# page_banner
page_banner = function(title="Main page title") {
    res = tags$div(
              style="background-position: center 10%;
                     background-size: cover;
                     background: #31387d;
                     padding: 15px 0;
                     color: white;",
        tags$div(class="container",
                 tags$h1(class="display-5 fw-lighter", title))
    )
    
    return(res)
}