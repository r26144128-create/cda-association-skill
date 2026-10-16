# The Python version of stages 1-2 (for claude.ai, which has no R) must give the same
# profile.json, check.json and Markdown tables as the R version.
# Skipped when Python with pandas and matplotlib is not available.

root <- if (dir.exists("categorical-association")) "." else file.path("..", "..")
scripts <- file.path(root, "categorical-association", "scripts")
python <- Sys.which(c("python", "python3"))
python <- python[nzchar(python)][1]
Sys.setenv(PYTHONIOENCODING = "utf-8")
has_python <- !is.na(python) &&
  system2(python, c("-c", shQuote("import pandas, matplotlib")), stdout = FALSE, stderr = FALSE) == 0

run_both <- function(stage, data, question = NULL) {
  dir <- tempfile("py-vs-r-")
  args <- c(shQuote(data), if (!is.null(question)) shQuote(question))
  r_status <- system2("Rscript", c(shQuote(file.path(scripts, paste0(stage, ".R"))), args, shQuote(file.path(dir, "r"))),
                      stdout = FALSE, stderr = FALSE)
  py_status <- system2(python, c(shQuote(file.path(scripts, paste0(stage, ".py"))), args, shQuote(file.path(dir, "py"))),
                       stdout = FALSE, stderr = FALSE)
  list(dir = dir, r_status = r_status, py_status = py_status)
}
read_md <- function(dir) readLines(list.files(dir, pattern = "\\.md$", full.names = TRUE), encoding = "UTF-8")

data_files <- c(file.path(root, "example_data", c("01_crosstab_titanic.csv", "02_trend_housing.csv",
                                                  "03_stratified_berkeley.csv")),
                file.path(root, "dev", "demo", "student_por.csv"),
                file.path(root, "dev", "tests", "data", c("Political.dat", "Crabs.dat", "Abortion.dat",
                                                          "Envir_opinions.dat")))
data_files <- data_files[file.exists(data_files)]   # textbook files are downloaded separately
mal_file <- tempfile(fileext = ".csv")              # Table 2.6, written from helper-data.R
write.csv(malformation_counts(), mal_file, row.names = FALSE)
data_files <- c(data_files, mal_file)

test_that("stage 1: Python profile and overview table match R", {
  skip_if_not(has_python, "Python with pandas and matplotlib not available")
  for (f in data_files) {
    out <- run_both("profile_data", f)
    expect_equal(c(out$r_status, out$py_status), c(0, 0), info = f)
    r <- jsonlite::fromJSON(file.path(out$dir, "r", "profile.json"))
    p <- jsonlite::fromJSON(file.path(out$dir, "py", "profile.json"))
    r$file <- p$file <- NULL
    expect_equal(p, r, info = f)
    expect_identical(read_md(file.path(out$dir, "py")), read_md(file.path(out$dir, "r")), info = f)
  }
})

test_that("stage 2: Python question check matches R (levels, recode, strata, missing values)", {
  skip_if_not(has_python, "Python with pandas and matplotlib not available")
  student <- file.path(root, "dev", "demo", "student_por.csv")
  with_na <- tempfile(fileext = ".csv")
  d <- read.csv(student)
  set.seed(1)
  d$romantic[sample(nrow(d), 40)] <- NA
  write.csv(d, with_na, row.names = FALSE, na = "")
  questions <- list(
    list(data_files[1], '{"x":"Sex","y":"Survived","z":"Age","levels":{"Survived":["Yes","No"]}}'),
    list(data_files[1], '{"x":"Class","y":"Survived"}'),
    list(data_files[2], '{"x":"Infl","y":"Sat","count":"Freq","levels":{"Infl":["Low","Medium","High"],"Sat":["Low","Medium","High"]}}'),
    list(data_files[3], '{"x":"Gender","y":"Admit","z":"Dept","count":"Freq"}'),
    list(mal_file, '{"x":"alcohol","y":"malformation","count":"count","levels":{"alcohol":["0","<1","1-2","3-5",">=6"]}}'),
    list(student, '{"x":"studytime","y":"passed","z":"school","recode":{"passed":{"from":"G3","breaks":[10],"labels":["fail","pass"]}}}'),
    list(student, '{"x":"W2","y":"pass","recode":{"W2":{"from":"Walc","map":{"1":"少","2":"少","3":"多","4":"多","5":"多"}}}}'),
    list(with_na, '{"x":"romantic","y":"pass"}'))
  for (q in questions) {
    q_file <- tempfile(fileext = ".json")
    writeLines(q[[2]], q_file, useBytes = TRUE)
    out <- run_both("describe_question", q[[1]], q_file)
    expect_equal(c(out$r_status, out$py_status), c(0, 0), info = q[[2]])
    r <- jsonlite::fromJSON(file.path(out$dir, "r", "check.json"))
    p <- jsonlite::fromJSON(file.path(out$dir, "py", "check.json"))
    expect_equal(p, r, tolerance = 1e-8, info = q[[2]])
    expect_identical(read_md(file.path(out$dir, "py")), read_md(file.path(out$dir, "r")), info = q[[2]])
    expect_setequal(list.files(file.path(out$dir, "py"), pattern = "\\.png$"), p$plots)
  }
})

test_that("stage 2: both versions refuse a column that does not exist", {
  skip_if_not(has_python, "Python with pandas and matplotlib not available")
  q_file <- tempfile(fileext = ".json")
  writeLines('{"x":"romance","y":"pass"}', q_file)
  out <- run_both("describe_question", file.path(root, "dev", "demo", "student_por.csv"), q_file)
  expect_equal(c(out$r_status, out$py_status), c(1, 1))
  expect_match(jsonlite::fromJSON(file.path(out$dir, "py", "check.json"))$error, "找不到欄位：romance")
})
