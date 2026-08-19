# Kwame Okrah
# 2026-05-23

preproc_order_summary = function(path) {
  tibl = readxl::read_excel(path, sheet=1, skip=1)
  df = as.data.frame(tibl)

  SEL = colnames(df)
  SEL = SEL[!SEL %in% c("Order ID", "Name", "Lot No", "Type", "Purification")]
  
  for (k in SEL) {
      x = df[[k]]
      if (k == "Endotoxin Level(EU/mg)") {
          x[x=="/"] = "0.0"
      }
      if (k == "Ship Temp") {
          df[[k]] = -1 * as.numeric(gsub("[^0-9.]", "", x))
      }else{
          df[[k]] = as.numeric(gsub("[^0-9.]", "", x))
      }
  }

  colnames(df)[colnames(df) == "Ship Temp"] = "Ship Temp (Deg. Cels.)"
  df[["Purification"]] = gsub("™", "", df[["Purification"]])
  
  return(df)
}


order_summary_df_preproc = function(order_summary_df) {
    order_summary_df_colnames = colnames(order_summary_df)
    
    if (!"Order ID" %in% order_summary_df_colnames) {
        res = "'Order ID' column is missing. Check and try again."
    }else{
        if (!"Name" %in% order_summary_df_colnames) {
            res = "'Name' column is missing. Check and try again."
        }else{
            order_id_dups = duplicated(order_summary_df[,"Order ID"])
            protein_name_dups = duplicated(order_summary_df[,"Name"])
            if (any(order_id_dups)) {
                res = "'Order ID' column contains duplicates!"
                dups = paste0(which(order_id_dups)+1, collapse = ", ")
                res = paste0(res, " See row(s): ", dups, ".")
            }else{
                if (any(protein_name_dups)) {
                    res = "'Name' column contains duplicates!"
                    dups = paste0(which(protein_name_dups)+1, collapse = ", ")
                    res = paste0(res, " See row(s): ", dups, ".")
                }else{
                    order_id = order_summary_df[,"Order ID"]
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
