# Tests for the Skill as a whole: data profiling, recode, the run_analysis.R pipeline,
# and the mode-2 R code in references/methods.md (it must give the engine's numbers).
# Run from the repo root: Rscript -e "testthat::test_dir('dev/tests')"
library(testthat)

root <- if (dir.exists("categorical-association")) "." else file.path("..", "..")
skill <- file.path(root, "categorical-association")
for (f in c("utils.R", "association.R", "profile.R")) source(file.path(skill, "R", f))
student_file <- file.path(root, "dev", "demo", "student_por.csv")
student <- as.data.frame(read_data(student_file))

type_of <- function(p, var) Filter(function(v) v$name == var, p$variables)[[1]]$type_guess
hint_types <- function(p) vapply(p$structure$hints, `[[`, "", "type")

# ---- Stage 1: profiling ----

test_that("independent survey (Political): id, binary, nominal; no structure hints", {
  p <- cda_profile(read_data(agresti_file("Political.dat")))
  expect_equal(type_of(p, "person"), "id")
  expect_equal(type_of(p, "gender"), "binary")
  expect_equal(type_of(p, "party"), "nominal")
  expect_equal(p$structure$default, "independent")
})

test_that("non-independent data is flagged so the Skill can refer it elsewhere", {
  expect_equal(hint_types(cda_profile(read_data(agresti_file("Abortion.dat")))), "repeated_measures")
  expect_equal(hint_types(cda_profile(read_data(agresti_file("Envir_opinions.dat")))),
               "possible_matched_pairs_wide")
  d <- data.frame(school = rep(sprintf("S%02d", 1:15), each = 8),
                  pass = rep(c("yes", "no"), 60), sex = rep(c("M", "F", "F", "M"), 30))
  expect_equal(hint_types(cda_profile(d)), "clustered")
})

test_that("numeric codes need confirmation; Chinese scales are ordinal candidates; counts are detected", {
  crabs <- cda_profile(read_data(agresti_file("Crabs.dat")))
  expect_equal(type_of(crabs, "color"), "ordinal_or_nominal_code")
  expect_equal(type_of(crabs, "width"), "continuous")
  d <- data.frame(滿意度 = rep(c("非常不滿意", "不滿意", "普通", "滿意", "非常滿意"), 6),
                  性別 = rep(c("男", "女"), 15))
  expect_equal(type_of(cda_profile(d), "滿意度"), "ordinal_candidate")
  agg <- data.frame(group = c("placebo", "placebo", "aspirin", "aspirin"),
                    MI = c("yes", "no", "yes", "no"), count = c(189, 10845, 104, 10933))
  expect_equal(hint_types(cda_profile(agg)), "aggregated_counts")
})

test_that("UCI student data: binary, nominal, codes", {
  p <- cda_profile(student)
  expect_equal(type_of(p, "romantic"), "binary")
  expect_equal(type_of(p, "Mjob"), "nominal")
  expect_equal(type_of(p, "studytime"), "ordinal_or_nominal_code")
  expect_equal(type_of(p, "age"), "continuous")
})

test_that("cda_recode: thresholds and category merges are done in R", {
  d <- data.frame(G3 = c(0, 9, 10, 15, 20), Walc = c(1, 2, 3, 4, 5))
  r <- cda_recode(d, list(
    passed = list(from = "G3", breaks = 10, labels = c("fail", "pass")),
    W2 = list(from = "Walc", map = list("1" = "few", "2" = "few", "3" = "many", "4" = "many", "5" = "many"))))
  expect_equal(as.character(r$passed), c("fail", "fail", "pass", "pass", "pass"))
  expect_equal(as.character(r$W2), c("few", "few", "many", "many", "many"))
  notes <- attr(r, "recode_notes")
  expect_length(notes, 3)                                   # breaks: description + cut-point reminder
  expect_match(notes[2], "切點")                            # checklist item 11
  expect_false(any(grepl("切點", notes[3])))                # merging categories gets no cut-point reminder
  expect_error(cda_recode(d, list(bad = list(from = "Walc", map = list("1" = "a")))), "沒有對應")
})

# ---- Stage 3: run_analysis.R end to end (the three Part 1 questions) ----

run_skill <- function(spec, data = student_file) {
  dir <- tempfile("skill-run-")
  dir.create(dir)
  spec_file <- file.path(dir, "spec.json")
  writeLines(jsonlite::toJSON(spec, auto_unbox = TRUE, null = "null"), spec_file, useBytes = TRUE)
  status <- system2("Rscript", c(shQuote(file.path(skill, "scripts", "run_analysis.R")),
                                 shQuote(data), shQuote(spec_file), shQuote(file.path(dir, "out"))),
                    stdout = FALSE, stderr = FALSE)
  list(status = status, dir = file.path(dir, "out"),
       json = jsonlite::fromJSON(file.path(dir, "out", "result.json")))
}
stat_of <- function(json, name) json$tests$statistic[json$tests$test == name]

test_that("q1 romantic × pass: crosstab writes result, plots, report and reproduce.R", {
  r <- run_skill(list(question = "有交往對象的學生，及格率比較低嗎？", analysis = "crosstab",
                      x = "romantic", y = "pass", success = "pass", design = "cross-sectional",
                      levels = list(romantic = c("yes", "no"), pass = c("pass", "fail"))))
  expect_equal(r$status, 0)
  expect_equal(stat_of(r$json, "Pearson X2"), 4.27669, tolerance = 1e-5)
  or <- r$json$estimates[r$json$estimates$measure == "odds ratio", ]
  expect_equal(c(or$estimate, or$lower, or$upper), c(0.63642, 0.41435, 0.97750), tolerance = 1e-4)
  expect_setequal(list.files(r$dir), c("result.json", "spec.json", "reproduce.R",
                                       "conditional_props.png", "residuals.png", "分析報告_student_por_crosstab.md"))
  report <- readLines(file.path(r$dir, "分析報告_student_por_crosstab.md"), encoding = "UTF-8")
  expect_true(any(grepl("4.2767", report, fixed = TRUE)))   # the report carries R's numbers
})

test_that("q2 studytime × pass: trend test with midpoint scores and sensitivity analysis", {
  r <- run_skill(list(analysis = "trend", x = "studytime", y = "pass", success = "pass",
                      ordinal = list("studytime"), x_scores = c(1, 3.5, 7.5, 12),
                      levels = list(studytime = c("1", "2", "3", "4"), pass = c("pass", "fail"))))
  expect_equal(r$status, 0)
  expect_equal(stat_of(r$json, "Cochran-Armitage trend (M2)"), 15.42152, tolerance = 1e-5)
  expect_equal(stat_of(r$json, "M2 (equally spaced scores)"), 17.66550, tolerance = 1e-5)
})

test_that("q3 romantic × pass controlling for school: stratified analysis", {
  r <- run_skill(list(analysis = "stratified", x = "romantic", y = "pass", z = "school", success = "pass",
                      levels = list(romantic = c("yes", "no"), pass = c("pass", "fail"))))
  expect_equal(r$status, 0)
  est <- setNames(r$json$estimates$estimate, r$json$estimates$measure)
  expect_equal(unname(est["marginal odds ratio"]), 0.63642, tolerance = 1e-4)
  expect_equal(unname(est["common odds ratio (logistic model)"]), 0.69548, tolerance = 1e-4)
})

test_that("recode inside the spec: pass/fail made from G3 matches the stored pass column", {
  r <- run_skill(list(analysis = "crosstab", x = "romantic", y = "passed", success = "pass",
                      recode = list(passed = list(from = "G3", breaks = 10, labels = c("fail", "pass"))),
                      levels = list(romantic = c("yes", "no"), passed = c("pass", "fail"))))
  expect_equal(r$status, 0)
  expect_equal(stat_of(r$json, "Pearson X2"), 4.27669, tolerance = 1e-5)
  expect_match(r$json$facts[1], "新變數 passed")
})

test_that("out-of-scope requests fail with an explanation instead of a wrong number", {
  r <- run_skill(list(analysis = "logistic", y = "pass", x = list("sex")))
  expect_equal(r$status, 1)
  expect_match(r$json$error, "不支援")
  r <- run_skill(list(analysis = "crosstab", x = "nonexistent", y = "pass"))
  expect_match(r$json$error, "找不到欄位")
  # nominal Mjob (5 levels) has no scores: the trend test must refuse (§2.5.5)
  r <- run_skill(list(analysis = "trend", x = "Mjob", y = "pass", success = "pass"))
  expect_equal(r$status, 1)
})

# ---- Mode 2: the R code handed to users without R (references/methods.md) ----

test_that("methods.md code reproduces the engine's numbers", {
  df <- student
  tab <- table(factor(df$romantic, levels = c("yes", "no")), factor(df$pass, levels = c("pass", "fail")))
  ct <- chisq.test(tab, correct = FALSE)
  expect_equal(unname(ct$statistic), 4.27669, tolerance = 1e-5)
  y1 <- tab[1, 1]; n1 <- sum(tab[1, ]); y2 <- tab[2, 1]; n2 <- sum(tab[2, ])
  expect_equal(PropCIs::orscoreci(y1, n1, y2, n2, conf.level = 0.95)$conf.int[1:2], c(0.41435, 0.97750),
               tolerance = 1e-4)

  x_scores <- c(1, 3.5, 7.5, 12); y_scores <- c(1, 0)
  u <- x_scores[as.integer(factor(df$studytime, levels = c("1", "2", "3", "4")))]
  v <- y_scores[as.integer(factor(df$pass, levels = c("pass", "fail")))]
  expect_equal((length(u) - 1) * cor(u, v)^2, 15.42152, tolerance = 1e-5)

  tab3 <- table(factor(df$romantic, levels = c("yes", "no")), factor(df$pass, levels = c("pass", "fail")), df$school)
  expect_equal(unname(mantelhaen.test(tab3, correct = FALSE)$statistic), 2.49069, tolerance = 1e-5)
  m <- margin.table(tab3, c(1, 2))
  expect_equal((m[1, 1] * m[2, 2]) / (m[1, 2] * m[2, 1]), 0.63642, tolerance = 1e-4)
})

# ---- example_data/: the live-demo files give the numbers promised in README.md ----
# Each Skill result is also recomputed with base R only (chisq.test, cor, mantelhaen.test).

demo_file <- function(f) file.path(root, "example_data", f)

test_that("01 Titanic sex × survived: crosstab on raw rows", {
  r <- run_skill(list(analysis = "crosstab", x = "Sex", y = "Survived", success = "Yes",
                      levels = list(Sex = c("Female", "Male"), Survived = c("Yes", "No"))),
                 data = demo_file("01_crosstab_titanic.csv"))
  expect_equal(r$status, 0)
  expect_equal(stat_of(r$json, "Pearson X2"), 456.874, tolerance = 1e-5)
  est <- setNames(r$json$estimates$estimate, r$json$estimates$measure)
  expect_equal(unname(est[c("difference of proportions", "relative risk", "odds ratio")]),
               c(0.5199, 3.452, 10.147), tolerance = 1e-3)
  d <- read.csv(demo_file("01_crosstab_titanic.csv"))
  expect_equal(unname(chisq.test(table(d$Sex, d$Survived), correct = FALSE)$statistic), 456.874, tolerance = 1e-5)
})

test_that("02 housing influence × satisfaction: trend test on aggregated counts", {
  lv <- c("Low", "Medium", "High")
  r <- run_skill(list(analysis = "trend", x = "Infl", y = "Sat", count = "Freq",
                      ordinal = list("Infl", "Sat"), levels = list(Infl = lv, Sat = lv)),
                 data = demo_file("02_trend_housing.csv"))
  expect_equal(r$status, 0)
  expect_equal(stat_of(r$json, "Linear-by-linear association (M2)"), 101.3675, tolerance = 1e-5)
  h <- read.csv(demo_file("02_trend_housing.csv"))
  u <- rep(match(h$Infl, lv), h$Freq); v <- rep(match(h$Sat, lv), h$Freq)
  expect_equal((length(u) - 1) * cor(u, v)^2, 101.3675, tolerance = 1e-5)
})

test_that("03 Berkeley gender × admission by department: stratified analysis", {
  r <- run_skill(list(analysis = "stratified", x = "Gender", y = "Admit", z = "Dept", count = "Freq",
                      success = "Admitted", levels = list(Gender = c("Male", "Female"),
                                                          Admit = c("Admitted", "Rejected"))),
                 data = demo_file("03_stratified_berkeley.csv"))
  expect_equal(r$status, 0)
  est <- setNames(r$json$estimates$estimate, r$json$estimates$measure)
  expect_equal(unname(est["marginal odds ratio"]), 1.8411, tolerance = 1e-4)
  expect_equal(unname(est["common odds ratio (logistic model)"]), 0.9050, tolerance = 1e-3)
  expect_equal(stat_of(r$json, "Cochran-Mantel-Haenszel (score test, beta = 0)"), 1.5246, tolerance = 1e-4)
  expect_equal(unname(mantelhaen.test(UCBAdmissions, correct = FALSE)$statistic), 1.5246, tolerance = 1e-4)
  expect_equal(stat_of(r$json, "Homogeneous association (residual deviance)"), 20.204, tolerance = 1e-4)
})

# ---- Stages 1-2: overview table and question check ----

test_that("profile_data.R writes the overview table; describe_question.R writes plots and facts", {
  dir <- tempfile("describe-")
  status <- system2("Rscript", c(shQuote(file.path(skill, "scripts", "profile_data.R")),
                                 shQuote(demo_file("02_trend_housing.csv")), shQuote(dir)), stdout = FALSE, stderr = FALSE)
  expect_equal(status, 0)
  overview <- readLines(file.path(dir, "資料總覽_02_trend_housing.md"), encoding = "UTF-8")
  expect_true(any(grepl("合計 1,681", overview, fixed = TRUE)))        # counts weighted by Freq
  expect_true(any(grepl("Low：627（37.3%）", overview, fixed = TRUE)))

  q_file <- file.path(dir, "question.json")
  writeLines('{"x": "Gender", "y": "Admit", "z": "Dept", "count": "Freq"}', q_file)
  status <- system2("Rscript", c(shQuote(file.path(skill, "scripts", "describe_question.R")),
                                 shQuote(demo_file("03_stratified_berkeley.csv")), shQuote(q_file), shQuote(dir)),
                    stdout = FALSE, stderr = FALSE)
  expect_equal(status, 0)
  chk <- jsonlite::fromJSON(file.path(dir, "check.json"))
  expect_equal(chk$n, 4526)
  expect_equal(nrow(chk$strata), 6)
  expect_equal(chk$cells_expected_below_5, 0)
  expect_true(all(file.exists(file.path(dir, c("bar_Gender.png", "bar_Admit.png", "bar_Dept.png", "relation.png")))))
})

test_that("04 paired student courses: each student appears twice, so the profile flags repeated measures", {
  p <- cda_profile(read_data(demo_file("04_paired_student_courses.csv")))
  hint <- p$structure$hints[[1]]
  expect_equal(hint$type, "repeated_measures")
  expect_equal(as.character(hint$columns), c("student_id", "course"))
  expect_equal(p$structure$default, "needs_confirmation")
})
