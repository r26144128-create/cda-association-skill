# Golden tests for R/association.R: our functions must reproduce Agresti (2019).
# Run from the repo root: Rscript -e "testthat::test_dir('dev/tests')"
library(testthat)

root <- if (dir.exists("categorical-association")) "." else file.path("..", "..")
source(file.path(root, "categorical-association", "R", "utils.R"))
source(file.path(root, "categorical-association", "R", "association.R"))

test_that("§2.4 party ID by gender (Table 2.4): X², G², standardized residuals", {
  P <- read_data(agresti_file("Political.dat"))
  P$party <- factor(P$party, levels = c("Dem", "Rep", "Ind"))
  res <- cda_crosstab(P, "gender", "party")
  expect_equal(res$tests$statistic[1], 12.569, tolerance = 1e-3)  # book: X² = 12.57
  expect_equal(res$tests$statistic[2], 12.60, tolerance = 1e-2)   # book: G² = 12.60
  expect_equal(unname(res$tables$standardized_residuals["female", "Dem"]), 3.27)
  expect_equal(unname(res$tables$standardized_residuals["female", "Rep"]), -2.50)
  expect_length(res$warnings, 0)
})

test_that("§2.2–2.3 aspirin and heart attacks (Table 2.2): score CIs", {
  asp <- data.frame(
    group = factor(c("placebo", "placebo", "aspirin", "aspirin"), levels = c("placebo", "aspirin")),
    MI = factor(c("yes", "no", "yes", "no"), levels = c("yes", "no")),
    n = c(189, 10845, 104, 10933))
  est <- cda_crosstab(asp, "group", "MI", count = "n")$estimates
  rownames(est) <- est$measure
  expect_equal(unname(unlist(est["difference of proportions", c("lower", "upper")])),
               c(0.00472, 0.01079), tolerance = 1e-2)
  expect_equal(est["relative risk", "estimate"], 1.82, tolerance = 1e-2)
  expect_equal(unname(unlist(est["relative risk", c("lower", "upper")])),
               c(1.43390, 2.30471), tolerance = 1e-4)
  expect_equal(est["odds ratio", "estimate"], 1.83205, tolerance = 1e-4)
  expect_equal(unname(unlist(est["odds ratio", c("lower", "upper")])),
               c(1.44080, 2.32955), tolerance = 1e-4)
})

test_that("§2.6 tea tasting (Table 2.7): Fisher only (no mid-P in v1), small-sample warning", {
  tea <- data.frame(poured = rep(c("milk", "tea"), each = 4),
                    guess = c("milk", "milk", "milk", "tea", "milk", "tea", "tea", "tea"))
  res <- cda_crosstab(tea, "poured", "guess")
  p <- setNames(res$tests$p_value, res$tests$test)
  expect_equal(unname(p["Fisher exact (two-sided)"]), 0.4857, tolerance = 1e-3)
  expect_false(any(grepl("mid-P", c(res$tests$test, res$facts))))   # v1 reports Fisher only
  expect_true("LOW_EXPECTED" %in% vapply(res$warnings, `[[`, "", "code"))
})

test_that("§2.3.5 case-control design suppresses difference and relative risk", {
  cc <- data.frame(smoker = c("yes", "yes", "no", "no"), cancer = c("case", "control", "case", "control"),
                   n = c(688, 650, 21, 59))
  res <- cda_crosstab(cc, "smoker", "cancer", count = "n", design = "case-control")
  expect_equal(res$estimates$measure, "odds ratio")
  expect_true("CASE_CONTROL" %in% vapply(res$warnings, `[[`, "", "code"))
})

malformation <- function() {
  m <- malformation_counts()
  m$alcohol <- factor(m$alcohol, levels = c("0", "<1", "1-2", "3-5", ">=6"))
  m$malformation <- factor(m$malformation, levels = c("present", "absent"))
  m
}

test_that("§2.5.2 alcohol and malformation (Table 2.6): Cochran-Armitage M² with midpoint scores", {
  res <- cda_trend(malformation(), "alcohol", "malformation", count = "count",
                   ordinal = "alcohol", x_scores = c(0, 0.5, 1.5, 4, 7), success = "present")
  t <- setNames(res$tests$statistic, res$tests$test)
  p <- setNames(res$tests$p_value, res$tests$test)
  expect_equal(unname(t["Cochran-Armitage trend (M2)"]), 6.5699, tolerance = 1e-4)    # book: M² = 6.57
  expect_equal(unname(p["Cochran-Armitage trend (M2)"]), 0.01037, tolerance = 1e-3)   # book: P = 0.010
  expect_equal(unname(t["Pearson X2 (ignores order)"]), 12.1, tolerance = 1e-2)  # book: X² = 12.1
  expect_equal(unname(t["M2 (equally spaced scores)"]), 1.83, tolerance = 1e-2)  # §2.5.4: 1.83
  expect_true(any(grepl("M = 2.56", res$facts, fixed = TRUE)))             # book: M = 2.56
  expect_match(res$method_label, "Cochran–Armitage")
  expect_true("SCORE_SENSITIVE" %in% vapply(res$warnings, `[[`, "", "code"))
})

test_that("§2.5.5 Cochran-Armitage refuses an explanatory variable not confirmed as ordinal", {
  expect_error(cda_trend(malformation(), "alcohol", "malformation", count = "count"), "§2.5.5")
})

test_that("trend: ordinal × ordinal is linear-by-linear; binary nominal x × ordinal y is refused", {
  lv <- c("low", "mid", "high")
  oo <- expand.grid(a = lv, b = lv)
  oo$n <- c(20, 10, 5, 10, 15, 10, 5, 10, 20)
  res <- cda_trend(oo, "a", "b", count = "n", ordinal = c("a", "b"))
  expect_match(res$method_label, "Linear-by-linear")
  expect_true("Linear-by-linear association (M2)" %in% res$tests$test)
  expect_error(cda_trend(oo, "a", "b", count = "n", ordinal = "a"), "Linear-by-linear")

  bo <- expand.grid(sex = c("F", "M"), sat = lv)
  bo$n <- c(10, 12, 15, 9, 20, 8)
  expect_error(cda_trend(bo, "sex", "sat", count = "n", ordinal = "sat"), "需要先確認分析目的")
  # a two-level x the user explicitly confirmed as ordinal (e.g. low/high dose) is allowed
  expect_match(cda_trend(bo, "sex", "sat", count = "n", ordinal = c("sex", "sat"))$method_label, "Linear-by-linear")
})

test_that("Cochran's rule: larger tables warn only for expected < 1 or > 20% of cells below 5", {
  codes <- function(res) vapply(res$warnings, `[[`, "", "code")
  # 3×3, one cell (1/9 = 11%) has expected < 5 and none < 1: no warning
  ok <- expand.grid(a = c("p", "q", "r"), b = c("u", "v", "w"))
  ok$n <- c(60, 60, 15, 60, 60, 15, 15, 15, 2)        # only cell (r, w) has expected 3.39
  res <- cda_crosstab(ok, "a", "b", count = "n")
  expect_false("LOW_EXPECTED" %in% codes(res))
  # 3×3 with a sparse column: 3/9 cells below 5 -> warning and a Fisher test
  bad <- ok
  bad$n[c(7, 8, 9)] <- c(1, 2, 1)
  res <- cda_crosstab(bad, "a", "b", count = "n")
  expect_true("LOW_EXPECTED" %in% codes(res))
  expect_true(any(grepl("^Fisher exact", res$tests$test)))
})

test_that("§2.7 death penalty (Table 2.9): conditional/marginal ORs, Simpson, logistic", {
  dp <- read_data(agresti_file("DeathPenalty.dat"))
  dp$D <- factor(dp$D, levels = c("white", "black"))
  dp$V <- factor(dp$V, levels = c("white", "black"))
  dp$P <- factor(dp$P, levels = c("yes", "no"))
  res <- cda_stratified(dp, "D", "P", "V", count = "count")
  est <- setNames(res$estimates$estimate, res$estimates$measure)
  expect_equal(unname(est["conditional odds ratio (V = white)"]), 0.43, tolerance = 1e-2)  # book 0.43
  expect_equal(unname(est["conditional odds ratio (V = black)"]), 0)                      # book 0.0
  expect_equal(unname(est["marginal odds ratio"]), 1.45, tolerance = 1e-2)                # book 1.45
  expect_equal(log(unname(est["common odds ratio (logistic model)"])), -0.868, tolerance = 1e-3)  # Ex. 4.11
  lr <- res$tests[grepl("^LR", res$tests$test), ]
  expect_equal(lr$statistic, 5.0, tolerance = 1e-2)   # Ex. 4.11 solution: LR = 5.0
  expect_equal(lr$p_value, 0.025, tolerance = 1e-2)   # P = 0.025
  expect_true("SIMPSON" %in% vapply(res$warnings, `[[`, "", "code"))
})

# ---- Checklist guardrails added in batch 2 (items 2, 5, 7) ----

codes_of <- function(res) vapply(res$warnings, `[[`, "", "code")

test_that("missing values: always reported; warning at >= 5%, stronger at >= 20%", {
  base <- data.frame(a = rep(c("x", "y"), 50), b = rep(c("u", "u", "v", "v"), 25))
  few <- base; few$a[1:3] <- NA                     # 3%
  res <- cda_crosstab(few, "a", "b")
  expect_true(any(grepl("排除 3 個觀察值（占 3.0%）", res$facts, fixed = TRUE)))
  expect_false(any(c("MISSING_DROPPED", "MISSING_HIGH") %in% codes_of(res)))
  some <- base; some$a[1:8] <- NA                   # 8%
  expect_true("MISSING_DROPPED" %in% codes_of(cda_crosstab(some, "a", "b")))
  many <- base; many$a[1:25] <- NA                  # 25%
  res <- cda_crosstab(many, "a", "b")
  expect_true("MISSING_HIGH" %in% codes_of(res))
  expect_false("MISSING_DROPPED" %in% codes_of(res))
})

test_that("an empty category is removed and reported; zero cells are named", {
  d <- data.frame(g = factor(c("a", "a", "b", "b"), levels = c("a", "b", "c")),
                  y = c("yes", "no", "yes", "no"), n = c(10, 5, 0, 7))
  res <- cda_crosstab(d, "g", "y", count = "n")
  expect_true("EMPTY_CATEGORY" %in% codes_of(res))
  expect_equal(rownames(res$tables$counts), c("a", "b"))
  zero <- res$warnings[[which(codes_of(res) == "ZERO_CELL")]]$message
  expect_match(zero, "g=b、y=yes")
  expect_match(zero, "沒有加 0.5")
})

test_that("strata: opposite directions and significant homogeneity are flagged; CIs listed", {
  u <- as.data.frame(UCBAdmissions)
  res <- cda_stratified(u, "Gender", "Admit", "Dept", count = "Freq", success = "Admitted")
  expect_true(all(c("OPPOSITE_DIRECTIONS", "HETEROGENEITY") %in% codes_of(res)))
  expect_equal(sum(grepl("^Dept=.*CI \\[", res$facts)), 6)
  expect_match(res$notes$reminder, "P > 0.05 不代表共同勝算比一定適合")
})

test_that("strata: same direction in every stratum gives no OPPOSITE_DIRECTIONS", {
  dp <- read_data(agresti_file("DeathPenalty.dat"))
  dp$D <- factor(dp$D, levels = c("white", "black"))
  dp$V <- factor(dp$V, levels = c("white", "black"))
  dp$P <- factor(dp$P, levels = c("yes", "no"))
  res <- cda_stratified(dp, "D", "P", "V", count = "count")
  expect_false("OPPOSITE_DIRECTIONS" %in% codes_of(res))
  expect_true("SIMPSON" %in% codes_of(res))
})

test_that("small groups get a stability reminder (text only), not a refusal", {
  d <- data.frame(g = c("a", "a", "b", "b"), y = c("yes", "no", "yes", "no"), n = c(200, 300, 4, 3))
  res <- cda_crosstab(d, "g", "y", count = "n")
  w <- res$warnings[[which(codes_of(res) == "SMALL_GROUP")]]$message
  expect_match(w, "b（7 個）")
  expect_match(w, "不代表方法不能用")
  expect_true(nrow(res$estimates) > 0)                     # the analysis still runs
  big <- data.frame(g = c("a", "a", "b", "b"), y = c("yes", "no", "yes", "no"), n = c(20, 30, 6, 4))
  expect_false("SMALL_GROUP" %in% codes_of(cda_crosstab(big, "g", "y", count = "n")))
})
