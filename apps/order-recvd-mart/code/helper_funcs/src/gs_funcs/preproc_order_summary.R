# Kwame Okrah
# 2026-05-23

preproc_order_summary = function(path) {
  tibl = readxl::read_excel(path, sheet=1, skip=1)
  df = as.data.frame(tibl)

  r = c("Order ID", "Name", "Lot No", "Type", "Ship Temp",
        "Cal. M.W.(KDa)", "Theoretical pI", "Extinction Coefficients",
        "Purification", "Buffer", "Concentration(mg/ml)",
        "Purity by SEC-HPLC(%)", "Purity by CE-SDS under NR(%)",
        "Endotoxin Level(EU/mg)", "Size-Volume(ml)", "Unit(Tube)", 
        "Total(mg)")
  
  df = df[,r,drop=FALSE]

  SEL = c("Concentration(mg/ml)",
          "Purity by SEC-HPLC(%)",
          "Purity by CE-SDS under NR(%)",
          "Theoretical pI",
          "Ship Temp",
          "Extinction Coefficients",
          "Endotoxin Level(EU/mg)",
          "Total(mg)")
  
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
