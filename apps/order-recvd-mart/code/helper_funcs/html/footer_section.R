# author: Kwame Okrah

# footer section
footer_section = function(text="ⓒ 2026 Sanavia Oncology Inc.") {
    res = tags$footer(
                tags$div(
                    class="text-center text-muted p-2",
                    style="position: fixed; bottom: 0; width: 100%; background-color: rgb(214, 209, 196); z-index: 9999;",
                    text)
    )

    return(res)
}
