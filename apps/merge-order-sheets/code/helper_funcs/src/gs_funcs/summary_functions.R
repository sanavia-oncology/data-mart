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

front_page_table = function(merged_sheets_list){
    oid = names(merged_sheets_list)
    
    mdate = sapply(merged_sheets_list, 
                   function(x) x[["merge_date"]][1])
    
    gdate = sapply(merged_sheets_list, 
                   function(x) x[["genscript_date"]][1])
    
    n_mol = sapply(merged_sheets_list, nrow)
    
    order_type = sapply(merged_sheets_list, 
                        function(x) x[["order_type"]][1])
    
    assembly_type = sapply(merged_sheets_list,
                           function(x) paste0(sort(unique(x[["assembly_type"]])),
                                              collapse = "|"))
    
    assembly_type = gsub("AT", "", assembly_type)
    assembly_type = paste0("AT", assembly_type)
    
    df = data.frame("merge_date"=mdate,
                    "order_id"=oid,
                    "size"=n_mol,
                    "type"=order_type,
                    "prod_date"=gdate,
                    "assembly_type"=assembly_type,
                    check.names = F)
    
    df = df[rev(order(df$merge_date, df$prod_date)),,drop=F]
    rownames(df) = NULL
    
    return(df)
}


make_front_page_table = function(order_files_paths) {
    # read in all merged_sheet.csv
    merged_sheets_list = list()
    
    for (order_folder in names(order_files_paths)) {
        fls = order_files_paths[[order_folder]]
        
        dat = read.csv(fls[grep("merged-sheets.csv$", fls)], 
                       header = TRUE,
                       check.names = FALSE,
                       stringsAsFactors = FALSE)
        
        location_map = fls[grep("Summary", fls)]
        location_map = sapply(strsplit(location_map, "Summary"), "[[", 2)
        location_map = gsub("[A-Z]|[a-z]", "", location_map)
        location_map = gsub("_|\\.", "", location_map)
        
        if (!gsub("[0-9]", "", location_map) == "") {
            dat$genscript_date = "Unknown"
        }else{
            if (!nchar(location_map)==8) {
                dat$genscript_date = "Unknown"
            }else{
                month = substr(location_map, 1, 2)
                day = substr(location_map, 3, 4)
                yr = substr(location_map, 5, 8)
                dat$genscript_date = paste0(yr, "-", month, "-", day)
            }
        }
        
        merged_sheets_list[[order_folder]] = dat
    }
    
    table_front_page = front_page_table(merged_sheets_list)
    
    return(table_front_page)
}



plot_qc_metrics = function(x) {
    op = par(mfrow=c(1, 2))
    
    conc = x[,"Concentration(mg/ml)"]
    purity_sds = x[,"Purity by CE-SDS under NR(%)"]
    purity_hplc = x[,"Purity by SEC-HPLC(%)"]
    
    conc4 = conc > 4
    conc[conc4] = 4
    
    main = sapply(strsplit(x[1, "Order ID"], "-"), "[[", 1)
    
    plot(conc, purity_sds, ylim=c(0, 100),
         xlim = c(0, 4), pch=19,
         main = paste0(main, ": Conc. x Purity (CE-SDS)"),
         col = "steelblue",
         ylab = "Purity by CE-SDS under NR(%)",
         xlab = "Concentration(mg/ml)")
    abline(h=seq(0, 100, 10), v=seq(0, 4, .5), lty=3)
    points(conc[conc4], purity_sds[conc4], pch="x", col="red", lwd=1.5)
    
    if (sum(conc4, na.rm = T) > 0) {
        text(3, 15, "x = conc. > 4 (mg/ml)", lwd=2, cex=1, col="red2")
    }
    mtext(paste0("Date: ", Sys.Date()), 3, 2.75, col="gray80")
    
    plot(conc, purity_hplc, ylim=c(0, 100),
         main = paste0(main, ": Conc. x Purity (SEC-HPLC)"),
         xlim=c(0, 4), pch=19,
         col = "steelblue",
         ylab = "Purity by SEC-HPLC(%)",
         xlab = "Concentration(mg/ml)")
    abline(h=seq(0, 100, 10), v=seq(0, 4, .5), lty=3)
    points(conc[conc4], purity_hplc[conc4], pch="x", col="red", lwd=1.5)
    
    if (sum(conc4, na.rm = T) > 0) {
        text(3, 15, "x = conc. > 4 (mg/ml)", lwd=2, cex=1, col="red2")
    }
    mtext(paste0("Date: ", Sys.Date()), 3, 2.75, col="gray80")
    
    par(op)
}


qc_metrics = function(x, cc = 0.1, pc = 90) {
    conc = x[,"Concentration(mg/ml)"]
    purity_sds = x[,"Purity by CE-SDS under NR(%)"]
    sel = conc > cc & purity_sds > pc
    sel[is.na(sel)] = FALSE
    sel
}    
