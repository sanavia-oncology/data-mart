# Shared by the in-app modal and the ?embed=creds page, so the two can't drift apart.

creds_fields <- function(cur, orders_value) {
    ph <- function(k) if (k %in% names(cur)) "already set — leave blank to keep" else ""
    tagList(
        textInput("cr_test_url", "Test tenant URL",
                  value = creds_get(cur, "BENCHLING_TEST_TENANT_URL"), width = "100%"),
        passwordInput("cr_test_key", "Test API key", placeholder = ph("BENCHLING_TEST_API_KEY"),
                      width = "100%"),
        textInput("cr_prod_url", "Prod tenant URL",
                  value = creds_get(cur, "BENCHLING_PROD_TENANT_URL"), width = "100%"),
        passwordInput("cr_prod_key", "Prod API key",
                      placeholder = ph("BENCHLING_PROD_API_KEY"), width = "100%"),
        tags$hr(),
        # Lands in the app env file, not the creds file — it's config, not a secret.
        tags$label("Orders folder", class = "control-label", `for` = "cr_orders"),
        tags$div(class = "d-flex gap-2 align-items-center",
                 tags$div(style = "flex: 1 1 auto;",
                          textInput("cr_orders", NULL, value = orders_value, width = "100%")),
                 tags$div(style = "flex: 0 0 auto; margin-bottom: 15px;",
                          actionButton("cr_orders_pick", "Choose…", class = "btn-outline-secondary")))
    )
}
