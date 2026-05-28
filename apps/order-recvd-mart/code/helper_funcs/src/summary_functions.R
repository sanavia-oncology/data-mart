# Kwame Okrah
# 2026-05-23

plot_merged_sheet = function(ms, fig_path=NULL) {
    order_id = sapply(strsplit(ms[["Order ID"]][1], "-"), "[[", 1)
    conc = ms[["Concentration(mg/ml)"]]
    purity = ms[["Purity by SEC-HPLC(%)"]]

    xlim = c(0, 100)
    
    ylim = c(0, max(conc, na.rm = T))
    if (ylim[2] < 3) ylim[2] = 3
    
    if (!is.null(fig_path)) {
        pdf(fig_path, height = 3, width = 6.85)
    }
    
    op = par(mar=c(3.25, 3.25, 1.25, 0.75), mgp=c(2, 0.75, 0))
    
    main = paste0("Order ID: ", order_id, " (N = ", length(conc), ")")
    plot(purity, conc,
         cex=0.9,
         pch=19,
         col=densCols(purity, conc),
         ylim=ylim, xlim=xlim, main=main,
         ylab="Concentration (mg/ml)",
         xlab="Purity by SEC-HPLC (%)")
    abline(h=seq(0, 500, 0.5), lty=3,col="gray30")
    abline(v=seq(0, 100, 5), lty=3, col="gray30")
    
    abline(v=c(70, 80, 90), col="red", lty=2)
    par(op)
    
    if (!is.null(fig_path)) {
        dev.off()
    }
}


front_page_table = function(merged_sheets_list, 
                            status=NULL,
                            order_type=NULL) {
    odate = names(merged_sheets_list)
    odate = paste0(substr(odate, 1, 4), "-", 
                   substr(odate, 5, 6), "-", 
                   substr(odate, 7, 8))
    
    mdate = sapply(merged_sheets_list, 
                   function(x) x[["Merge Date"]][1])
           
    
    oid = sapply(merged_sheets_list, 
                 function(x) sapply(strsplit(x[["Order ID"]][1], "-"), "[[", 1))
    n_mol = sapply(merged_sheets_list, nrow)

    if (is.null(status)) {
        status = rep("to_implement", length(oid))    
    }
    
    if (is.null(order_type)) {
        order_type = rep("to_implement", length(oid))    
    }
    
    
    df = data.frame("Date"=odate,
                    "Order ID"=oid,
                    "Order Size"=n_mol,
                    "Order Type"=order_type,
                    "Status"=status,
                    check.names = F)
    
    df = df[rev(order(df$Date)),,drop=F]
    rownames(df) = NULL
    
    return(df)
}
