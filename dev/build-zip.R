# Build categorical-association.zip for uploading to claude.ai (Settings → Capabilities → Skills).
# Run from the repo root: Rscript dev/build-zip.R
zip_file <- "categorical-association.zip"
if (file.exists(zip_file)) file.remove(zip_file)
files <- list.files("categorical-association", recursive = TRUE, full.names = TRUE)
files <- files[!grepl("__pycache__", files)]
utils::zip(zip_file, files, flags = "-r9Xq")
message("OK: ", zip_file, " (", length(files), " files)")
