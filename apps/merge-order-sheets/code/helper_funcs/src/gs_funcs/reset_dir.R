# Kwame Okrah
# 2026-03-08

reset_dir = function(dir_path) {
    if (dir.exists(dir_path)) {
        unlink(dir_path, recursive = TRUE)
    }
    dir.create(dir_path, recursive = TRUE)
}