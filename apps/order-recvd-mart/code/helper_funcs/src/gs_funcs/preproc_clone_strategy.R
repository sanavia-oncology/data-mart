# Kwame Okrah
# 2026-05-23

preproc_clone_strategy = function(path) {
  tibl = readxl::read_excel(path, sheet=1, skip=1)
  df = as.data.frame(tibl)
  return(df)
}