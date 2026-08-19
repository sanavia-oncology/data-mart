# Kwame Okrah
# 2026-05-23

preproc_clone_strategy = function(path) {
  tibl = readxl::read_excel(path, sheet=1, skip=1)
  df = as.data.frame(tibl)
  return(df)
}

clone_strategy_df_preproc = function(clone_strategy_df) {
    clone_strategy_df_colnames = colnames(clone_strategy_df)
    
    if (!"Order ID" %in% clone_strategy_df_colnames) {
        res = "'Order ID' column is missing. Check and try again."
    }else{
        if (!"Protein Name" %in% clone_strategy_df_colnames) {
            res = "'Protein Name' column is missing. Check and try again."
        }else{
            order_id_dups = duplicated(clone_strategy_df[,"Order ID"])
            protein_name_dups = duplicated(clone_strategy_df[,"Protein Name"])
            if (any(order_id_dups)) {
                res = "'Order ID' column contains duplicates!"
                dups = paste0(which(order_id_dups)+1, collapse = ", ")
                res = paste0(res, " See row(s): ", dups, ".")
            }else{
                if (any(protein_name_dups)) {
                    res = "'Protein Name' column contains duplicates!"
                    dups = paste0(which(protein_name_dups)+1, collapse = ", ")
                    res = paste0(res, " See row(s): ", dups, ".")
                }else{
                    order_id = clone_strategy_df[,"Order ID"]
                    u_order_id = unique(sapply(strsplit(order_id, "-"), "[[", 1))
                    if (length(u_order_id) != 1) {
                        res = "Observed 'Order ID' is not unique!"
                    }else{
                        res = "pass"    
                    }
                }
            }
        }
    }
    
    return(res)
}
