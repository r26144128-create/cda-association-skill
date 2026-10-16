# Stage 1: profile a data file - guessed variable scales, data-structure hints and an
# overview table of every variable.
#
# Usage: Rscript profile_data.R <data file> <output dir>
# Writes <output dir>/profile.json and 資料總覽_<data>.md. Every guess must be confirmed with the user.

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 2) stop("Usage: Rscript profile_data.R <data file> <output dir>")
data_file <- args[1]; out_dir <- args[2]
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

script_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
source(file.path(dirname(normalizePath(sub("^--file=", "", script_arg[1]))), "load_engine.R"))

out_file <- file.path(out_dir, "profile.json")
profile <- tryCatch(cda_profile(read_data(data_file)), error = function(e) {
  writeLines(jsonlite::toJSON(list(error = paste("無法讀取資料：", conditionMessage(e))),
                              auto_unbox = TRUE, pretty = TRUE), out_file, useBytes = TRUE)
  message("ERROR: ", conditionMessage(e))
  quit(status = 1)
})
profile$file <- normalizePath(data_file, winslash = "/")

writeLines(jsonlite::toJSON(profile, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null"),
           out_file, useBytes = TRUE)

# Stage 1 overview table shown to the user (no plots at this stage).
data_name <- tools::file_path_sans_ext(basename(data_file))
overview_file <- file.path(out_dir, paste0("資料總覽_", data_name, ".md"))
con <- file(overview_file, open = "w", encoding = "UTF-8")
writeLines(cda_overview_md(read_data(data_file), profile, basename(data_file)), con)
close(con)
message("OK: ", normalizePath(out_file))
message("OK: ", normalizePath(overview_file))
