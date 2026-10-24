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
                                                  "03_stratified_berkeley.csv", "04_paired_student_courses.csv")),
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

# ---- Stage 4: run_analysis.py (web mode) must give the same result.json as run_analysis.R ----

test_that("stage 4: Python analysis matches R on crosstab, trend, stratified, edge cases and refusals", {
  skip_if_not(has_python, "Python with pandas and matplotlib not available")
  skip_if_not(system2(python, c("-c", shQuote("import scipy")), stdout = FALSE, stderr = FALSE) == 0, "scipy not available")
  student <- file.path(root, "dev", "demo", "student_por.csv")
  ex <- function(f) file.path(root, "example_data", f)
  tmp_csv <- function(df) { p <- tempfile(fileext = ".csv"); write.csv(df, p, row.names = FALSE); p }
  tea <- tmp_csv(data.frame(poured = rep(c("milk", "tea"), each = 4),
                            guess = c("milk", "milk", "milk", "tea", "milk", "tea", "tea", "tea")))
  cc <- tmp_csv(data.frame(smoker = c("yes", "yes", "no", "no"), cancer = c("case", "control", "case", "control"),
                           n = c(688, 650, 21, 59)))
  sparse <- tmp_csv(data.frame(a = rep(c("p", "q", "r"), 3), b = rep(c("u", "v", "w"), each = 3),
                               n = c(60, 60, 15, 60, 60, 15, 1, 2, 1)))
  empty <- tmp_csv(data.frame(g = rep(c("a", "b", "c"), each = 2), y = rep(c("yes", "no"), 3), n = c(10, 5, 0, 7, 0, 0)))
  cases <- list(
    list(student, '{"analysis":"crosstab","x":"romantic","y":"pass","success":"pass","design":"cross-sectional","levels":{"romantic":["yes","no"],"pass":["pass","fail"]}}'),
    list(student, '{"analysis":"trend","x":"studytime","y":"pass","success":"pass","ordinal":["studytime"],"x_scores":[1,3.5,7.5,12],"levels":{"studytime":["1","2","3","4"],"pass":["pass","fail"]}}'),
    list(student, '{"analysis":"stratified","x":"romantic","y":"pass","z":"school","success":"pass","levels":{"romantic":["yes","no"],"pass":["pass","fail"]}}'),
    list(ex("01_crosstab_titanic.csv"), '{"analysis":"crosstab","x":"Sex","y":"Survived","success":"Yes","levels":{"Sex":["Female","Male"],"Survived":["Yes","No"]}}'),
    list(ex("01_crosstab_titanic.csv"), '{"analysis":"crosstab","x":"Class","y":"Survived"}'),
    list(ex("02_trend_housing.csv"), '{"analysis":"trend","x":"Infl","y":"Sat","count":"Freq","ordinal":["Infl","Sat"],"levels":{"Infl":["Low","Medium","High"],"Sat":["Low","Medium","High"]}}'),
    list(ex("03_stratified_berkeley.csv"), '{"analysis":"stratified","x":"Gender","y":"Admit","z":"Dept","count":"Freq","success":"Admitted","levels":{"Gender":["Male","Female"],"Admit":["Admitted","Rejected"]}}'),
    list(mal_file, '{"analysis":"trend","x":"alcohol","y":"malformation","count":"count","ordinal":["alcohol"],"x_scores":[0,0.5,1.5,4,7],"success":"present","levels":{"alcohol":["0","<1","1-2","3-5",">=6"],"malformation":["present","absent"]}}'),
    list(tea, '{"analysis":"crosstab","x":"poured","y":"guess"}'),
    list(cc, '{"analysis":"crosstab","x":"smoker","y":"cancer","count":"n","design":"case-control"}'),
    list(sparse, '{"analysis":"crosstab","x":"a","y":"b","count":"n"}'),
    list(empty, '{"analysis":"crosstab","x":"g","y":"y","count":"n"}'),
    list(student, '{"analysis":"crosstab","x":"romantic","y":"passed","success":"pass","recode":{"passed":{"from":"G3","breaks":[10],"labels":["fail","pass"]}}}'),
    list(student, '{"analysis":"logistic","y":"pass","x":["sex"]}'),
    list(student, '{"analysis":"trend","x":"sex","y":"studytime","ordinal":["studytime"]}'))
  for (q in cases) {
    q_file <- tempfile(fileext = ".json")
    writeLines(q[[2]], q_file, useBytes = TRUE)
    out <- run_both("run_analysis", q[[1]], q_file)
    expect_equal(out$py_status, out$r_status, info = q[[2]])
    r <- jsonlite::fromJSON(file.path(out$dir, "r", "result.json"))
    p <- jsonlite::fromJSON(file.path(out$dir, "py", "result.json"))
    expect_equal(p, r, tolerance = 1e-6, info = q[[2]])
    if (is.null(r$error)) {
      expect_identical(read_md(file.path(out$dir, "py")), read_md(file.path(out$dir, "r")), info = q[[2]])
    }
  }
})
