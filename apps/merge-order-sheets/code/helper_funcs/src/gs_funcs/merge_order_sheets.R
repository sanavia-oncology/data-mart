# Kwame Okrah
# 2026-05-23

read_order_sheets = function(FLS) {

    FLS = FLS[grep("clone_strategy|location_map|order_summary", FLS)]
    
    FLS_stem = gsub(project_fldr, "", FLS)
    FLS_stem_list = strsplit(FLS_stem, "/")
    f = sapply(FLS_stem_list, "[[", 4)
    FLS_list = split(FLS, f)
    FLS_len_ = sapply(FLS_list, length)
    FLS_len = c("clone_strategy"=0, "location_map"=0, "order_summary"=0)   
 
    FLS_len[names(FLS_len_)] = FLS_len_
    
    hold = list()
    hold[["number_of_sheets"]] = FLS_len
  
    for (k in names(FLS_list)) {
        if (k == "clone_strategy") {
            if (FLS_len[k] > 0) {
                if (FLS_len[k] == 1) {
                    path = FLS_list[[k]]
                    hold[[k]] = preproc_clone_strategy(path)
                }else{
                    hold[[k]] = "clone_strategy_multiple_sheets"
                }
            }else{
                hold[[k]] = "clone_strategy_empty"
            }
        }
      
        if (k == "order_summary") {
            if (FLS_len[k] > 0) {
                if (FLS_len[k] == 1) {
                    path = FLS_list[[k]]
                    hold[[k]] = preproc_order_summary(path)
                }else{
                    hold[[k]] = "order_summary_multiple_sheets"
                }
            }else{
                hold[[k]] = "order_summary_empty"
            }
        }
      
        if (k == "location_map") {
            if (FLS_len[k] > 0) {
                if (FLS_len[k] == 1) {
                    path = FLS_list[[k]]
                    hold[[k]] = preproc_location_map(path)
                }else{
                    hold[[k]] = "location_map_multiple_sheets"
                }
            }else{
                hold[[k]] = "location_map_empty"
            }
        }
    }

    return(hold)
}



merge_order_sheets = function(order_sheets) {
    clone_strategy = order_sheets[["clone_strategy"]]
    order_summary = order_sheets[["order_summary"]]
    location_map = order_sheets[["location_map"]]

    # 1. merge order_summary and clone_strategy
    oid_cs = clone_strategy[["Protein Name"]]
    oid_os = order_summary[["Name"]]
    
    if (any(duplicated(oid_cs))) {
        msg = "clone_strategy 'Protein Name' contains duplicates (K.Okrah)\n"
        cat(msg)
        stop()
    }
    
    if (any(duplicated(oid_os))) {
        msg = "order_summary 'Name' contains duplicates (K.Okrah)\n"
        cat(msg)
        stop()
    }
    
    if (!length(oid_cs)==length(oid_os)) {
        msg = paste0("clone_strategy 'Protein Name' and ",
                     "order_summary 'Name' lengths do not match!",
                     " (K.Okrah)\n")
        cat(msg)
        stop()
    }
    if (!all(sort(oid_cs)==sort(oid_os))) {
        msg = paste0("clone_strategy 'Protein Name' and ",
                     "order_summary 'Name' names do not match!",
                     " (K.Okrah)\n")
        cat(msg)
        stop()
    }
    
    rownames(clone_strategy) = oid_cs
    rownames(order_summary) = oid_os
    oid = oid_cs
    
    merged_hold = cbind(order_summary[oid,,drop=F], 
                        clone_strategy[oid,,drop=F])
    
    # 2. add location map
    oid_loc = location_map[["Name"]]
    
    if (any(duplicated(oid_loc))) {
        msg = "location_map 'Name ID' contains duplicates (K.Okrah)\n"
        cat(msg)
        stop()
    }
    
    if (length(oid_cs) < length(oid_loc)) {
        msg = paste0("location_map 'Name' is longer than ",
                     "clone_strategy 'Protein Name'",
                     " (K.Okrah)\n")
        cat(msg)
        stop()
    }
    if (length(oid_os) < length(oid_loc)) {
        msg = paste0("location_map 'Name' is longer than ",
                     "order_summary 'Name'",
                     " (K.Okrah)\n")
        cat(msg)
        stop()
    }
    
    if (!all(oid_loc %in% oid)) {
        msg = paste0("The location_map 'Order ID's below ",
                     "are not in clone_strategy/order_summary sheets",
                     " (K.Okrah)\n")
        cat(msg)
        print(oid_loc[!oid_loc %in% oid])
        stop()
    }
    
    rownames(location_map) = oid_loc
    merged_hold = cbind(merged_hold, location_map[oid,,drop=FALSE])
    rownames(merged_hold) = NULL
    
    return(merged_hold)    
}
