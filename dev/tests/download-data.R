# Download the textbook data used by the tests. These files are not included in this
# repository because their source does not state a license for redistribution.
#
# Source: Agresti, A. (2019). An Introduction to Categorical Data Analysis (3rd ed.), data
# files published by the author at https://github.com/alanagresti/categorical-data
# (linked from https://www.alanagresti.com/). Original sources are given in the book.
#
# Run from the repository root: Rscript dev/tests/download-data.R
# Tests that need these files are skipped until they are downloaded.

files <- c("Political.dat", "DeathPenalty.dat", "Abortion.dat", "Envir_opinions.dat", "Crabs.dat")
base <- "https://raw.githubusercontent.com/alanagresti/categorical-data/master/"
dest <- file.path("dev", "tests", "data")
dir.create(dest, showWarnings = FALSE, recursive = TRUE)
for (f in files) {
  utils::download.file(paste0(base, f), file.path(dest, f), mode = "wb", quiet = TRUE)
  message("OK: ", file.path(dest, f))
}
