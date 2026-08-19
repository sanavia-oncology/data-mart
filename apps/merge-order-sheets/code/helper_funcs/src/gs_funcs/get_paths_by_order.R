# Kwame Okrah
# 2026-05-23

get_paths_by_order = function(project_fldr) {

    YR_FLDRS = list.dirs(project_fldr, 
                         recursive=FALSE, 
                         full.names=FALSE)
  
    hold = list()

    for (i in 1:length(YR_FLDRS)) {
        YR_FLDR = YR_FLDRS[i]
        ORDERS_FLDRS = list.dirs(paste0(project_fldr, "/", YR_FLDR),
                                 recursive=FALSE, 
                                 full.names=FALSE)
      
        for (j in 1:length(ORDERS_FLDRS)) {
            FLS = list.files(paste0(project_fldr, "/", 
                                    YR_FLDR, "/", 
                                    ORDERS_FLDRS[j]),
                             recursive=TRUE, full.names=TRUE)
            FLS = FLS[grep(".xlsx$|.csv$", FLS)]
            hold[[ORDERS_FLDRS[j]]] = FLS
        }
    }

    return(hold)
}
