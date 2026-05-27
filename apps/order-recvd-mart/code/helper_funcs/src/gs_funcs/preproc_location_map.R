# Kwame Okrah
# 2026-05-23

preproc_location_map_00 = function(df) {  
    n_col = ncol(df)
    n_row = nrow(df)

    # Find all rows with an "Order ID"
    order_id_index = list()
    for (k in 1:nrow(df)) {
        order_id_index[[paste0("row_", k)]] = grep("Order ID", df[k,])
    }
    order_id_index = order_id_index[sapply(order_id_index, length) > 0]

    # Parse out tables
    hold = list()

    for (k in names(order_id_index)) {
        x = order_id_index[[k]]
        n = length(x)

        for (i in 1:n) {
            if (i == n) {
                col_sel = x[i]:n_col
            }else{
                col_sel = x[i]:(x[i+1]-1)
            }
          
            # Grab box_type
            num_k = as.numeric(gsub("row_", "", k))
            bt = df[num_k - 1, 1]
          
            bt_check = grep("Wells Box", bt)
            if (length(bt_check)==1) {
                bt = sapply(strsplit(bt, " "), "[[", 1)
                bt = gsub("\\*", "x", bt)
            }else{
                msg = paste0("Check row:", num_k + 1, " and col: ", 
                            x[i], " in the Location Map xcel sheet.",
                            "\nThe expected 'Wells Box' missing! (K.Okrah)\n")
                cat(msg)
                stop()
            }
          
            # Grab data
            df_sub = df[(num_k + 1):n_row, col_sel, drop=FALSE]
            colnames(df_sub) = df[num_k, col_sel]
          
            # Find data_end_index
            data_end = (1:n_row)[-grep("^Box", df_sub[["Box Name"]])]
            if (length(data_end) > 0) {
                data_end_index = min(data_end) - 1
            }else{
                data_end_index = n_row
            } 
          
            df_sub = df_sub[1:data_end_index,,drop=FALSE]
          
            # Drop NA column
            na_col_name = is.na(colnames(df_sub)) | colnames(df_sub) == ""
            if (any(na_col_name)) df_sub = df_sub[,!na_col_name,drop=FALSE]
          
            # Add box type
            df_sub[["Box Type"]] = bt
          
            hold[[paste0(k, " | col_", x[i])]] = df_sub
        }
    }
    res = do.call(rbind, hold)
    rownames(res) = NULL
  
    return(res)
}

preproc_location_map = function(path, version="00") {
        tibl = readxl::read_excel(path, sheet=1, skip=1)
        df = rbind(colnames(tibl), as.data.frame(tibl))
    
        if (version=="00") {
            res = preproc_location_map_00(df)
        }else{
            cat("Select the appropriate version number. (K.Okrah)\n")
            stop()
        }
        
        return(res)
}