# Shared by the tests (testthat loads helper-*.R files first).

root <- if (dir.exists("categorical-association")) "." else file.path("..", "..")

# Textbook data files are downloaded, not stored in the repository (see download-data.R).
# A test that needs one is skipped until it has been downloaded.
agresti_file <- function(name) {
  path <- file.path(root, "dev", "tests", "data", name)
  testthat::skip_if_not(file.exists(path), paste0(name, " 尚未下載：先執行 Rscript dev/tests/download-data.R"))
  path
}

# Agresti (2019) Table 2.6: maternal alcohol consumption and infant malformation.
# Original source: Graubard, B. I., & Korn, E. L. (1987). Choice of column scores for
# testing independence in ordered 2 × K contingency tables. Biometrics, 43, 471–476.
malformation_counts <- function() {
  data.frame(alcohol = rep(c("0", "<1", "1-2", "3-5", ">=6"), each = 2),
             malformation = rep(c("absent", "present"), 5),
             count = c(17066, 48, 14464, 38, 788, 5, 126, 1, 37, 1))
}
