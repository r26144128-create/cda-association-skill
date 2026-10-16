# Part 1: association between two categorical variables (Agresti 2019, Ch.2).

# Drop rows with missing values in the analysed columns and turn the categorical columns
# into factors, keeping any level order the caller already set (checklist items 2 and 5):
#   - any missing: report how many observations were dropped and what share (a fact)
#   - missing >= 5%: MISSING_DROPPED warning; >= 20%: MISSING_HIGH (stronger wording)
#   - a category with no observations is removed and the user is told (EMPTY_CATEGORY)
.prepare_categorical <- function(data, vars, count = NULL) {
  cols <- c(vars, count)
  complete <- stats::complete.cases(data[, cols, drop = FALSE])
  w <- if (is.null(count)) rep(1, nrow(data)) else data[[count]]
  warnings <- list()
  facts <- character()
  if (any(!complete)) {
    n_drop <- sum(w[!complete], na.rm = TRUE)
    share <- n_drop / sum(w, na.rm = TRUE)
    facts <- sprintf("因 %s 有缺失，排除 %s 個觀察值（占 %s）。", paste(vars, collapse = "/"),
                     format(n_drop, big.mark = ",", trim = TRUE), scales::percent(share, accuracy = 0.1))
    if (share >= 0.2) {
      warnings[[1]] <- cda_warning(
        "MISSING_HIGH",
        sprintf(paste0("缺失比例 %s（≥ 20%%），結果可能高度受缺失影響。是否有偏誤取決於缺失的原因，",
                       "光看比例無法判斷；請說明資料為什麼缺失。"), scales::percent(share, accuracy = 0.1)),
        "§9.5.1")
    } else if (share >= 0.05) {
      warnings[[1]] <- cda_warning(
        "MISSING_DROPPED",
        sprintf(paste0("缺失比例 %s（≥ 5%%），可能影響結果。是否有偏誤取決於缺失的原因",
                       "（例如某些人比較不會回答），光看比例無法判斷。"), scales::percent(share, accuracy = 0.1)),
        "§9.5.1")
    }
  }
  d <- data[complete, , drop = FALSE]
  wd <- w[complete]
  for (v in vars) {
    if (!is.factor(d[[v]])) d[[v]] <- factor(d[[v]])
    totals <- tapply(wd, d[[v]], sum)
    empty <- names(totals)[is.na(totals) | totals == 0]
    if (length(empty) > 0) {
      warnings[[length(warnings) + 1]] <- cda_warning(
        "EMPTY_CATEGORY",
        sprintf("%s 的類別「%s」沒有任何觀察值（整列或整欄都是 0），已從分析中移除。", v,
                paste(empty, collapse = "」「")),
        "§2.3.3")
      keep <- !(d[[v]] %in% empty)
      d <- d[keep, , drop = FALSE]
      wd <- wd[keep]
    }
    d[[v]] <- droplevels(d[[v]])
  }
  list(data = d, warnings = warnings, facts = facts)
}

.count_formula <- function(vars, count) {
  stats::as.formula(paste(if (is.null(count)) "" else count, "~", paste(vars, collapse = " + ")))
}

# Cochran's rule for when the Pearson X² large-sample approximation may be unreliable
# (§2.4.7): a 2×2 table with any expected count < 5; a larger table with any expected
# count < 1 or more than 20% of cells below 5.
.sparse_table <- function(expected) {
  n_low <- sum(expected < 5)
  share <- n_low / length(expected)
  sparse <- if (all(dim(expected) == 2)) min(expected) < 5 else min(expected) < 1 || share > 0.2
  list(sparse = sparse, min = min(expected), n_low = n_low, n_cells = length(expected), share = share)
}

.sparse_message <- function(sp) {
  sprintf(paste0("期望次數最小為 %s，有 %d / %d 格（%s）小於 5：依 Cochran 準則，Pearson 卡方的大樣本近似可能不可靠，",
                 "建議以 Fisher 精確檢定為主。"),
          fmt_num(sp$min, 2), sp$n_low, sp$n_cells, scales::percent(sp$share, accuracy = 1))
}

# Checklist item 3 (text reminder only): a group of the explanatory variable with fewer
# than 10 observations gives unstable proportions and wide intervals. Not a rule that
# the method cannot be used.
.small_group_reminder <- function(tab, x, limit = 10) {
  sizes <- rowSums(tab)
  small <- sizes[sizes < limit]
  if (length(small) == 0) return(list())
  list(cda_warning(
    "SMALL_GROUP",
    sprintf(paste0("%s 有人數很少的組：%s。這是估計穩定性的提醒，不代表方法不能用：",
                   "這些組的比例與比例差、相對風險、勝算比的信賴區間會很寬，請搭配次數表、期望次數與信賴區間一起判斷。"),
            x, paste(sprintf("%s（%s 個）", names(small), format(small, trim = TRUE)), collapse = "、")),
    "§2.2.1"))
}

#' Two-way contingency table analysis
#'
#' @param data     data frame, one row per subject (or per cell when `count` is given)
#' @param x        explanatory / row variable
#' @param y        response / column variable
#' @param count    optional column of cell frequencies for already-tabulated data
#' @param success  for 2x2 tables, the level of `y` treated as "success" (default: first level)
#' @param ordinal  names of variables the user confirmed as ordinal
#' @param design   study design; "case-control" suppresses measures it cannot support (§2.3.5)
#' @param conf.level confidence level
cda_crosstab <- function(data, x, y, count = NULL, success = NULL, ordinal = character(),
                         design = c("unknown", "cohort", "cross-sectional", "experiment",
                                    "case-control"),
                         conf.level = 0.95) {
  design <- match.arg(design)
  facts <- character()

  prep <- .prepare_categorical(data, c(x, y), count)
  d <- prep$data
  warnings <- prep$warnings

  tab <- stats::xtabs(.count_formula(c(x, y), count), data = d)
  n <- sum(tab)
  r <- nrow(tab); c <- ncol(tab)
  if (r < 2 || c < 2) stop("每個變數至少要有 2 個類別才能分析關聯。")

  # --- Chi-squared tests of independence (§2.4) ---
  chi <- suppressWarnings(stats::chisq.test(tab, correct = FALSE))
  expected <- chi$expected
  g2 <- 2 * sum(ifelse(tab > 0, tab * log(tab / expected), 0))
  df <- (r - 1) * (c - 1)
  tests <- data.frame(
    test = c("Pearson X2", "Likelihood-ratio G2"),
    statistic = c(unname(chi$statistic), g2),
    df = df,
    p_value = c(chi$p.value, stats::pchisq(g2, df, lower.tail = FALSE)),
    book_ref = "§2.4.3"
  )
  facts <- c(facts,
    sprintf("樣本數 n = %d；%s 有 %d 類，%s 有 %d 類。", as.integer(n), x, r, y, c),
    sprintf("Pearson 卡方 X² = %s（df = %d），P = %s；概似比 G² = %s。",
            fmt_num(chi$statistic, 2), df, fmt_p(chi$p.value), fmt_num(g2, 2)))

  # --- Small expected frequencies → exact test (§2.4.7, §2.6) ---
  sp <- .sparse_table(expected)
  facts <- c(facts, sprintf("獨立假設下的期望次數最小為 %s；小於 5 的格子 %d / %d。",
                            fmt_num(sp$min, 2), sp$n_low, sp$n_cells))
  if (sp$sparse) {
    warnings[[length(warnings) + 1]] <- cda_warning("LOW_EXPECTED", .sparse_message(sp), "§2.4.7")
  }
  if (r == 2 && c == 2) {
    fisher <- stats::fisher.test(tab)
    tests <- rbind(tests, data.frame(test = "Fisher exact (two-sided)", statistic = NA, df = NA,
                                     p_value = fisher$p.value, book_ref = "§2.6"))
    facts <- c(facts, sprintf("Fisher 精確檢定雙尾 P = %s。", fmt_p(fisher$p.value)))
  } else if (sp$sparse) {
    set.seed(20261030)
    fisher <- tryCatch(stats::fisher.test(tab, workspace = 2e7),
                       error = function(e) stats::fisher.test(tab, simulate.p.value = TRUE, B = 1e5))
    tests <- rbind(tests, data.frame(test = paste("Fisher exact:", fisher$method),
                                     statistic = NA, df = NA, p_value = fisher$p.value,
                                     book_ref = "§2.6"))
    facts <- c(facts, sprintf("Fisher 精確檢定 P = %s。", fmt_p(fisher$p.value)))
  }

  warnings <- c(warnings, .small_group_reminder(tab, x))

  # --- Standardized residuals: where the association comes from (§2.4.5) ---
  stdres <- chi$stdres
  big <- which(abs(stdres) > 2, arr.ind = TRUE)
  if (r == 2 && c == 2) {
    # In a 2x2 table all four residuals share the same absolute value; describe one cell.
    big <- big[big[, 1] == 1 & big[, 2] == 1, , drop = FALSE]
  }
  if (nrow(big) > 0) {
    big <- big[order(-abs(stdres[big])), , drop = FALSE]
    cells <- apply(big, 1, function(i) sprintf("%s=%s、%s=%s（%s，實際次數比獨立時預期的%s）",
      x, rownames(tab)[i[1]], y, colnames(tab)[i[2]], fmt_num(stdres[i[1], i[2]], 2),
      if (stdres[i[1], i[2]] > 0) "多" else "少"))
    prefix <- if (r == 2 && c == 2) "2×2 表四格的標準化殘差絕對值相同，以其中一格為代表：" else "標準化殘差絕對值大於 2 的格子："
    facts <- c(facts, paste0(prefix, paste(cells, collapse = "；"), "。"))
  } else {
    facts <- c(facts, "所有格子的標準化殘差絕對值都不超過 2。")
  }

  # --- 2x2 effect measures (§2.2–2.3), score CIs as used in the book ---
  estimates <- data.frame()
  if (r == 2 && c == 2) {
    s <- if (is.null(success)) colnames(tab)[1] else success
    if (!s %in% colnames(tab)) stop("success 必須是 ", y, " 的其中一個類別。")
    fail <- setdiff(colnames(tab), s)
    x1 <- tab[1, s]; n1 <- sum(tab[1, ]); x2 <- tab[2, s]; n2 <- sum(tab[2, ])
    p1 <- x1 / n1; p2 <- x2 / n2
    g1 <- rownames(tab)[1]; g2name <- rownames(tab)[2]
    or <- (tab[1, s] * tab[2, fail]) / (tab[1, fail] * tab[2, s])
    or_ci <- PropCIs::orscoreci(x1, n1, x2, n2, conf.level)$conf.int
    estimates <- data.frame(measure = "odds ratio", estimate = or,
                            lower = or_ci[1], upper = or_ci[2],
                            ci_method = "score", book_ref = "§2.3.3")
    if (design != "case-control") {
      diff_ci <- PropCIs::diffscoreci(x1, n1, x2, n2, conf.level)$conf.int
      rr_ci <- PropCIs::riskscoreci(x1, n1, x2, n2, conf.level)$conf.int
      estimates <- rbind(data.frame(
        measure = c("difference of proportions", "relative risk"),
        estimate = c(p1 - p2, p1 / p2), lower = c(diff_ci[1], rr_ci[1]),
        upper = c(diff_ci[2], rr_ci[2]), ci_method = "score",
        book_ref = c("§2.2.2", "§2.2.3")), estimates)
      facts <- c(facts,
        sprintf("%s=%s 的比例：%s 組為 %s（%d/%d），%s 組為 %s（%d/%d）。",
                y, s, g1, fmt_num(p1), as.integer(x1), as.integer(n1),
                g2name, fmt_num(p2), as.integer(x2), as.integer(n2)),
        sprintf("比例差（%s − %s）= %s，%d%% CI [%s, %s]。", g1, g2name, fmt_num(p1 - p2, 4),
                round(conf.level * 100), fmt_num(diff_ci[1], 4), fmt_num(diff_ci[2], 4)),
        sprintf("相對風險 RR（%s / %s）= %s，%d%% CI [%s, %s]。", g1, g2name, fmt_num(p1 / p2, 2),
                round(conf.level * 100), fmt_num(rr_ci[1], 2), fmt_num(rr_ci[2], 2)))
    } else {
      warnings[[length(warnings) + 1]] <- cda_warning(
        "CASE_CONTROL",
        "case-control 研究中結果的比例由研究設計決定，不能估計比例差或相對風險，只能報告勝算比。",
        "§2.3.5")
    }
    facts <- c(facts, sprintf("勝算比 OR（%s 相對於 %s，%s=%s 的勝算）= %s，%d%% CI [%s, %s]。",
                              g1, g2name, y, s, fmt_num(or, 2), round(conf.level * 100),
                              fmt_num(or_ci[1], 2), fmt_num(or_ci[2], 2)))
    if (any(tab == 0)) {
      zero <- which(tab == 0, arr.ind = TRUE)
      warnings[[length(warnings) + 1]] <- cda_warning(
        "ZERO_CELL",
        sprintf(paste0("次數為 0 的格子：%s。勝算比或相對風險可能變成 0、∞、無法計算或非常不穩定，",
                       "實際影響取決於是哪一格為 0，請看原始次數表。這裡不使用 Wald 信賴區間，",
                       "改用 score 信賴區間，也沒有加 0.5 修正。"),
                paste(sprintf("%s=%s、%s=%s", x, rownames(tab)[zero[, 1]], y, colnames(tab)[zero[, 2]]),
                      collapse = "；")),
        "§2.3.3")
    }
    if (max(p1, p2) > 0.2 && design != "case-control") {
      warnings[[length(warnings) + 1]] <- cda_warning(
        "OR_NOT_RR",
        "比例不算小，勝算比不能當成相對風險來解釋（「幾倍的機率」要看 RR）。",
        "§2.3.4")
    }
  }

  # --- Ordinal information is ignored by X² and G² (§2.4.7, §2.5) ---
  ord <- intersect(ordinal, c(x, y))
  if (length(ord) > 0 || is.ordered(d[[x]]) || is.ordered(d[[y]])) {
    warnings[[length(warnings) + 1]] <- cda_warning(
      "ORDINAL_IGNORED",
      "卡方檢定把變數當成無順序（nominal），忽略了類別順序；有序變數可以用檢定力較高的趨勢檢定（M²）。",
      "§2.4.7, §2.5")
  }

  cda_result(
    method = "crosstab", book_ref = "§2.1–2.4, §2.6", tier = "A",
    method_label = "列聯表分析：卡方獨立性檢定（chi-squared test of independence）",
    estimates = estimates, tests = tests,
    tables = list(counts = tab, expected = round(expected, 2),
                  row_proportions = round(prop.table(tab, 1), 4),
                  standardized_residuals = round(stdres, 2)),
    warnings = warnings, facts = c(prep$facts, facts),
    notes = list(
      variables = list(x = x, y = y),
      reminder = "卡方檢定只回答「有沒有證據顯示有關聯」，不代表關聯有多強；強度要看比例、勝算比與殘差（§2.4.7）。"))
}

# Linear-trend statistic M² = (n − 1) R² for a table with ordered scores (§2.5.1).
.m2_statistic <- function(tab, u, v) {
  p <- tab / sum(tab)
  pr <- rowSums(p); pc <- colSums(p)
  ubar <- sum(u * pr); vbar <- sum(v * pc)
  r <- sum(outer(u - ubar, v - vbar) * p) / sqrt(sum((u - ubar)^2 * pr) * sum((v - vbar)^2 * pc))
  m2 <- (sum(tab) - 1) * r^2
  list(r = r, m2 = m2, p = stats::pchisq(m2, 1, lower.tail = FALSE))
}

#' Trend tests based on M² = (n − 1)r² (§2.5). The Skill supports two cases, named apart:
#'   binary y × ordinal x  -> Cochran–Armitage trend test (§2.5.5)
#'   ordinal x × ordinal y -> linear-by-linear association test (§2.5.1)
#' A binary nominal x with an ordinal y is refused: an x with two levels is not ordinal
#' just because it can be coded 0/1, so the purpose of the analysis must be settled first.
#'
#' @param ordinal  variables the user confirmed as ordinal
#' @param x_scores,y_scores  ordered scores for the categories; default equally spaced
cda_trend <- function(data, x, y, count = NULL, ordinal = character(),
                      x_scores = NULL, y_scores = NULL, success = NULL) {
  prep <- .prepare_categorical(data, c(x, y), count)
  d <- prep$data
  warnings <- prep$warnings
  tab <- stats::xtabs(.count_formula(c(x, y), count), data = d)
  r <- nrow(tab); c <- ncol(tab)
  if (r < 2 || c < 2) stop("每個變數至少要有 2 個類別。")
  is_ord <- function(v) v %in% ordinal || is.ordered(d[[v]])
  if (c == 2) {
    if (r == 2) stop("X 與 Y 都只有 2 類，這是 2×2 表，請改用列聯表分析（crosstab）。")
    if (!is_ord(x)) {
      stop(sprintf(paste0("%s 沒有經使用者確認為有序變數。Cochran–Armitage 趨勢檢定需要 X 有自然順序（§2.5.5）；",
                          "名目變數請改用列聯表分析（crosstab）。"), x))
    }
    trend_type <- "cochran_armitage"
  } else {
    if (r == 2 && !is_ord(x)) {
      stop(sprintf(paste0("%s 是二元名目變數、%s 是有序變數：本 Skill 第一版不對這種情況做趨勢檢定，",
                          "需要先確認分析目的。可以先用列聯表分析（crosstab）看有沒有關聯。"), x, y))
    }
    not_ord <- Filter(Negate(is_ord), c(x, y))
    if (length(not_ord) > 0) {
      stop(sprintf(paste0("%s 沒有經使用者確認為有序變數。Linear-by-linear association 檢定需要 X 與 Y 都有自然順序（§2.5.1）；",
                          "名目變數請改用列聯表分析（crosstab）。"), paste(not_ord, collapse = "、")))
    }
    trend_type <- "linear_by_linear"
  }
  custom <- !is.null(x_scores) || !is.null(y_scores)
  u <- if (is.null(x_scores)) seq_len(r) else as.numeric(x_scores)
  # A binary y gets score 1 for "success" and 0 otherwise: any two scores give the same M²
  # (§2.5.2), and this way the sign of R describes the trend in the success proportion.
  s <- NULL
  if (c == 2) {
    s <- if (is.null(success)) colnames(tab)[1] else success
    if (!s %in% colnames(tab)) stop("success 必須是 ", y, " 的其中一個類別。")
    v <- as.numeric(colnames(tab) == s)
    y_scores <- NULL
  } else {
    v <- if (is.null(y_scores)) seq_len(c) else as.numeric(y_scores)
  }
  if (length(u) != r || length(v) != c) stop("分數的個數必須等於類別數。")
  if (is.unsorted(u) || (c > 2 && is.unsorted(v))) stop("分數必須依類別順序遞增（§2.5.1）。")

  main <- .m2_statistic(tab, u, v)
  chi <- suppressWarnings(stats::chisq.test(tab, correct = FALSE))
  label <- if (trend_type == "cochran_armitage") "Cochran–Armitage 趨勢檢定（M²）" else "Linear-by-linear association 檢定（M²）"
  test_name <- if (trend_type == "cochran_armitage") "Cochran-Armitage trend (M2)" else "Linear-by-linear association (M2)"
  tests <- data.frame(
    test = c(test_name, "Pearson X2 (ignores order)"),
    statistic = c(main$m2, unname(chi$statistic)), df = c(1, (r - 1) * (c - 1)),
    p_value = c(main$p, chi$p.value), book_ref = c("§2.5.1", "§2.4.3"))
  m <- sign(main$r) * sqrt(main$m2)

  facts <- c(
    sprintf("樣本數 n = %d；%s 有 %d 類，%s 有 %d 類。", as.integer(sum(tab)), x, r, y, c),
    if (trend_type == "cochran_armitage")
      sprintf("方法：Cochran–Armitage 趨勢檢定（%s 為二元結果、%s 為有序解釋變數）。", y, x)
    else sprintf("方法：Linear-by-linear association 檢定（%s 與 %s 都是有序變數）。", x, y),
    if (c == 2) sprintf("%s 的分數：%s；%s 是二元變數（%s = 1，其他 = 0）。", x, paste(u, collapse = ", "), y, s)
    else sprintf("%s 的分數：%s；%s 的分數：%s。", x, paste(u, collapse = ", "), y, paste(v, collapse = ", ")),
    sprintf("相關係數 R = %s；M² = (n − 1)R² = %s（df = 1），P = %s。",
            fmt_num(main$r, 4), fmt_num(main$m2, 2), fmt_p(main$p)),
    sprintf("單尾檢定（%s）：M = %s，P = %s。",
            if (c == 2) sprintf("%s 越高，%s=%s 的比例越%s", x, y, s, if (m > 0) "高" else "低")
            else sprintf("%s 越高，%s 越%s", x, y, if (m > 0) "高" else "低"),
            fmt_num(m, 2), fmt_p(stats::pnorm(-abs(m)))),
    sprintf(paste0("對照：忽略順序的卡方檢定 X² = %s（df = %d），P = %s。",
                   "有真正的線性趨勢時，M² 只用 1 個自由度，通常檢定力較高（§2.5.3）。"),
            fmt_num(chi$statistic, 2), (r - 1) * (c - 1), fmt_p(chi$p.value)))

  if (c == 2) {
    prop <- tab[, s] / rowSums(tab)
    facts <- c(facts, paste0(y, "=", s, " 的比例：",
                             paste(sprintf("%s %s", rownames(tab), scales::percent(prop, accuracy = 0.01)),
                                   collapse = "、"), "。"))
  }

  if (custom) {
    eq <- .m2_statistic(tab, seq_len(r), seq_len(c))
    tests <- rbind(tests, data.frame(test = "M2 (equally spaced scores)", statistic = eq$m2,
                                     df = 1, p_value = eq$p, book_ref = "§2.5.4"))
    facts <- c(facts, sprintf("敏感度分析：改用等距分數時 M² = %s，P = %s。",
                              fmt_num(eq$m2, 2), fmt_p(eq$p)))
    if ((main$p < 0.05) != (eq$p < 0.05)) {
      warnings[[length(warnings) + 1]] <- cda_warning(
        "SCORE_SENSITIVE",
        "不同分數設定得到不同結論；資料不平衡時 M² 對分數很敏感，應說明分數的選擇理由並謹慎解讀。",
        "§2.5.4")
    }
  } else {
    facts <- c(facts, "使用等距分數。若類別間距離不相等，應依實際意義設定分數並做敏感度分析（§2.5.4）。")
  }
  warnings <- c(warnings, .small_group_reminder(tab, x))
  sp <- .sparse_table(chi$expected)
  if (sp$sparse) {
    warnings[[length(warnings) + 1]] <- cda_warning(
      "LOW_EXPECTED",
      sprintf("期望次數最小為 %s，有 %d / %d 格小於 5：用來對照的 Pearson 卡方可能不可靠；M² 也是大樣本方法，請謹慎解讀。",
              fmt_num(sp$min, 2), sp$n_low, sp$n_cells),
      "§2.4.7, §2.5.2")
  }

  cda_result(
    method = "trend", book_ref = "§2.5", tier = "A", method_label = label,
    tests = tests,
    tables = list(counts = tab, row_proportions = round(prop.table(tab, 1), 4)),
    warnings = warnings, facts = c(prep$facts, facts),
    notes = list(variables = list(x = x, y = y), scores = list(x = u, y = v), trend_type = trend_type,
                 reminder = "M² 只檢定「線性趨勢」；R 的大小受邊際分配影響，不適合單獨描述關聯強度（§2.5.2）。"))
}

#' Three-way analysis of a 2 × 2 × K table: X–Y association controlling for Z (§2.7).
#' Conditional and marginal odds ratios, Simpson's paradox check, and the logistic model
#' logit P(Y) = α + βx + β_k^Z with its LR test, Cochran–Mantel–Haenszel (score) test and
#' homogeneity test (§4.3.4, §5.2.1).
cda_stratified <- function(data, x, y, z, count = NULL, success = NULL, conf.level = 0.95) {
  prep <- .prepare_categorical(data, c(x, y, z), count)
  d <- prep$data
  warnings <- prep$warnings
  if (nlevels(d[[x]]) != 2 || nlevels(d[[y]]) != 2) {
    stop("目前只支援 X 與 Y 都是二元的 2×2×K 表（§2.7）。")
  }
  s <- if (is.null(success)) levels(d[[y]])[1] else success
  if (!s %in% levels(d[[y]])) stop("success 必須是 ", y, " 的其中一個類別。")
  fail <- setdiff(levels(d[[y]]), s)
  tab3 <- stats::xtabs(.count_formula(c(x, y, z), count), data = d)[, c(s, fail), , drop = FALSE]
  xl <- dimnames(tab3)[[1]]; zl <- dimnames(tab3)[[3]]
  K <- length(zl)
  if (K < 2) stop(z, " 至少要有 2 個類別才能做分層分析。")

  odds_ratio <- function(t) (t[1, 1] * t[2, 2]) / (t[1, 2] * t[2, 1])
  stratum_row <- function(t, label) {
    ci <- PropCIs::orscoreci(t[1, 1], sum(t[1, ]), t[2, 1], sum(t[2, ]), conf.level)$conf.int
    data.frame(stratum = label, n = sum(t), p1 = t[1, 1] / sum(t[1, ]), p2 = t[2, 1] / sum(t[2, ]),
               odds_ratio = odds_ratio(t), lower = ci[1], upper = ci[2])
  }
  strata <- do.call(rbind, lapply(zl, function(k) stratum_row(tab3[, , k], k)))
  marginal <- stratum_row(apply(tab3, c(1, 2), sum), paste0("合併（忽略 ", z, "）"))

  # Logistic model with x and z (§4.3.4). The baseline for x is its second level, so exp(β)
  # is the odds ratio of the first level versus the second, as in the stratum tables.
  wide <- expand.grid(x = xl, z = zl, stringsAsFactors = FALSE)
  wide$succ <- mapply(function(a, b) tab3[a, s, b], wide$x, wide$z)
  wide$fail <- mapply(function(a, b) tab3[a, fail, b], wide$x, wide$z)
  wide$x <- stats::relevel(factor(wide$x, levels = xl), ref = xl[2])
  wide$z <- factor(wide$z, levels = zl)
  fit <- stats::glm(cbind(succ, fail) ~ x + z, family = stats::binomial, data = wide)
  fit0 <- stats::glm(cbind(succ, fail) ~ z, family = stats::binomial, data = wide)
  term <- paste0("x", xl[1])
  beta <- stats::coef(fit)[[term]]
  se <- sqrt(diag(stats::vcov(fit)))[[term]]
  # Profile-likelihood interval; no Wald fallback (checklist item 2). If it cannot be
  # computed (e.g. zero cells), the interval is left empty and the user is told.
  ci <- tryCatch(suppressMessages(stats::confint(fit, term, level = conf.level)),
                 error = function(e) c(NA_real_, NA_real_))
  lr <- fit0$deviance - fit$deviance
  cmh <- stats::mantelhaen.test(tab3, correct = FALSE)
  homog_p <- stats::pchisq(fit$deviance, fit$df.residual, lower.tail = FALSE)

  tests <- data.frame(
    test = c("LR test of conditional independence (beta = 0)", "Wald test (beta = 0)",
             "Cochran-Mantel-Haenszel (score test, beta = 0)", "Homogeneous association (residual deviance)"),
    statistic = c(lr, (beta / se)^2, unname(cmh$statistic), fit$deviance),
    df = c(1, 1, 1, fit$df.residual),
    p_value = c(stats::pchisq(lr, 1, lower.tail = FALSE),
                stats::pchisq((beta / se)^2, 1, lower.tail = FALSE), cmh$p.value, homog_p),
    book_ref = c("§4.3.4", "§4.3.4", "§4.3.4", "§4.3.4, §5.2.1"))
  estimates <- rbind(
    data.frame(measure = paste0("conditional odds ratio (", z, " = ", strata$stratum, ")"),
               estimate = strata$odds_ratio, lower = strata$lower, upper = strata$upper,
               ci_method = "score", book_ref = "§2.7.4"),
    data.frame(measure = "marginal odds ratio", estimate = marginal$odds_ratio,
               lower = marginal$lower, upper = marginal$upper, ci_method = "score", book_ref = "§2.7.4"),
    data.frame(measure = "common odds ratio (logistic model)", estimate = exp(beta),
               lower = exp(ci[1]), upper = exp(ci[2]), ci_method = "profile likelihood",
               book_ref = "§4.3.4"))
  rownames(estimates) <- NULL

  pct <- function(p) scales::percent(p, accuracy = 0.1)
  or_txt <- function(o) if (is.nan(o)) "無法計算" else if (is.finite(o)) fmt_num(o, 2) else "∞"
  direction_txt <- function(o) {
    if (is.nan(o)) "方向無法判斷"
    else if (o > 1) paste0(y, "=", s, " 的勝算 ", xl[1], " 組較高")
    else if (o < 1) paste0(y, "=", s, " 的勝算 ", xl[1], " 組較低")
    else "兩組相同"
  }
  facts <- c(
    sprintf("樣本數 n = %d；比較 %s（%s vs %s）在 %s=%s 的比例，控制 %s（%d 層）。",
            as.integer(sum(tab3)), x, xl[1], xl[2], y, s, z, K),
    sprintf("%s=%s：%s 組 %s、%s 組 %s，條件勝算比 = %s，%d%% CI [%s, %s]（%s）。", z, strata$stratum,
            xl[1], pct(strata$p1), xl[2], pct(strata$p2), vapply(strata$odds_ratio, or_txt, ""),
            round(conf.level * 100), vapply(strata$lower, or_txt, ""), vapply(strata$upper, or_txt, ""),
            vapply(strata$odds_ratio, direction_txt, "")),
    sprintf("忽略 %s 合併後：%s 組 %s、%s 組 %s，邊際勝算比 = %s。", z, xl[1], pct(marginal$p1),
            xl[2], pct(marginal$p2), or_txt(marginal$odds_ratio)),
    if (all(is.finite(ci)))
      sprintf("控制 %s 後的共同勝算比（logistic 模型）= %s，%d%% CI [%s, %s]。", z, fmt_num(exp(beta), 2),
              round(conf.level * 100), fmt_num(exp(ci[1]), 2), fmt_num(exp(ci[2]), 2))
    else sprintf("控制 %s 後的共同勝算比（logistic 模型）= %s；信賴區間無法計算（常見原因是 0 次數的格子），不改用 Wald 區間。",
                 z, fmt_num(exp(beta), 2)),
    sprintf("條件獨立檢定：概似比 LR = %s（df = 1），P = %s；CMH = %s，P = %s。",
            fmt_num(lr, 2), fmt_p(tests$p_value[1]), fmt_num(cmh$statistic, 2), fmt_p(cmh$p.value)),
    sprintf("同質關聯檢定（各層勝算比是否相同）：deviance = %s（df = %d），P = %s。",
            fmt_num(fit$deviance, 2), fit$df.residual, fmt_p(homog_p)))

  side <- function(o) ifelse(is.nan(o), NA, sign(log(o)))
  cond_sides <- stats::na.omit(side(strata$odds_ratio))
  cond_sides <- cond_sides[cond_sides != 0]
  marg_side <- side(marginal$odds_ratio)
  if (length(cond_sides) > 0 && length(unique(cond_sides)) == 1 && !is.na(marg_side) &&
      marg_side != 0 && marg_side != cond_sides[1]) {
    warnings[[length(warnings) + 1]] <- cda_warning(
      "SIMPSON",
      sprintf("Simpson 悖論：控制 %s 後，每一層的關聯方向都和合併後相反。只看合併的表會得到錯誤方向的結論。", z),
      "§2.7.3")
  }
  # Effect modification (checklist item 7): strata pointing in opposite directions, or a
  # significant homogeneity test. No ratio cut-off for "very different" sizes.
  if (length(cond_sides) > 0 && length(unique(cond_sides)) > 1) {
    warnings[[length(warnings) + 1]] <- cda_warning(
      "OPPOSITE_DIRECTIONS",
      sprintf(paste0("各層勝算比的方向不一致（有的 > 1、有的 < 1）：%s 和 %s 的關係可能因 %s 而不同，",
                     "不能只報共同勝算比，要逐層報告並看各層的信賴區間。"), x, y, z),
      "§2.7.5")
  }
  if (homog_p < 0.05) {
    warnings[[length(warnings) + 1]] <- cda_warning(
      "HETEROGENEITY",
      sprintf("同質關聯檢定顯著（P = %s）：各層勝算比可能不同，共同勝算比不能單獨代表全部，要逐層報告。",
              fmt_p(homog_p)),
      "§4.3.4, §5.2.1")
  }
  if (any(apply(tab3, 3, function(t) any(t == 0)))) {
    warnings[[length(warnings) + 1]] <- cda_warning(
      "ZERO_CELL",
      paste0("有分層表出現 0 次的格子，該層勝算比可能是 0、∞、無法計算或非常不穩定，請看原始次數表；",
             "這裡使用 score 信賴區間，沒有加 0.5 修正。"),
      "§2.3.3, §5.3.3")
  }
  n_cell <- wide$succ + wide$fail
  fitted_counts <- c(stats::fitted(fit) * n_cell, (1 - stats::fitted(fit)) * n_cell)
  if (min(fitted_counts) < 5) {
    warnings[[length(warnings) + 1]] <- cda_warning(
      "SMALL_FITTED",
      "模型的配適次數有小於 5 的格子，同質關聯檢定（deviance）的卡方近似可能不準。",
      "§5.2.2")
  }

  partial <- as.data.frame(tab3, responseName = "count")
  names(partial)[1:3] <- c(x, y, z)
  cda_result(
    method = "stratified", book_ref = "§2.7, §4.3.4", tier = "A",
    method_label = "三因子表：分層勝算比、Simpson 悖論與 CMH 檢定",
    estimates = estimates, tests = tests,
    tables = list(partial_tables = partial, strata = rbind(strata, marginal)),
    warnings = warnings, facts = c(prep$facts, facts),
    notes = list(variables = list(x = x, y = y, z = z), success = s,
                 reminder = paste0("同質關聯檢定只是輔助：P > 0.05 不代表共同勝算比一定適合（小樣本時檢定力可能不足），",
                                   "請一併檢視各層勝算比、信賴區間與分層圖。控制變數只能排除「有測量到的」第三變數；",
                                   "觀察資料中仍可能有其他混淆因子（§2.7）。")))
}
