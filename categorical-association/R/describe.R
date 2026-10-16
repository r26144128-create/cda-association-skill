# Descriptive summaries for the Skill's first two stages:
#   stage 1 - one overview table of every variable (no plots)
#   stage 2 - once the user has a question: bar charts and the facts the checklist needs
# Nothing here decides whether a method is suitable; it only reports numbers for Claude
# to compare against references/checklist.md.

# Counts of each value of v, weighted by w when the data are aggregated.
weighted_counts <- function(v, w = NULL) {
  v <- code_order_factor(v)
  if (is.null(w)) return(table(v, useNA = "no"))
  tab <- tapply(w, v, sum)
  tab[is.na(tab)] <- 0
  as.table(tab)
}

# Stage 1: overview table (Markdown) of every column.
cda_overview_md <- function(data, profile, data_name) {
  data <- as.data.frame(data, check.names = FALSE)
  types <- vapply(profile$variables, `[[`, "", "type_guess")
  freq_cols <- names(data)[types == "frequency_weight"]
  w <- if (length(freq_cols) == 1) data[[freq_cols]] else NULL
  type_label <- c(binary = "二元", nominal = "名目", ordinal_candidate = "可能有序",
                  ordinal_or_nominal_code = "數字代碼（有序或名目？）", continuous = "連續",
                  count_or_continuous = "計數或連續", frequency_weight = "次數欄", id = "識別碼",
                  nominal_many_levels = "類別很多的文字", empty = "全部缺失")

  rows <- vapply(profile$variables, function(v) {
    x <- data[[v$name]]
    detail <- if (v$type_guess %in% c("continuous", "count_or_continuous", "frequency_weight")) {
      sprintf("範圍 %s–%s，平均 %s", fmt_num(min(x, na.rm = TRUE), 2), fmt_num(max(x, na.rm = TRUE), 2),
              fmt_num(mean(x, na.rm = TRUE), 2))
    } else if (v$type_guess %in% c("id", "nominal_many_levels", "empty")) {
      sprintf("%d 種值", v$n_unique)
    } else {
      tab <- weighted_counts(x, if (v$name %in% freq_cols) NULL else w)
      paste(sprintf("%s：%s（%s）", names(tab), format(as.numeric(tab), big.mark = ",", trim = TRUE),
                    scales::percent(as.numeric(tab) / sum(tab), accuracy = 0.1)), collapse = "；")
    }
    sprintf("| %s | %s | %d | %s |", v$name, type_label[[v$type_guess]] %||% v$type_guess, v$n_missing, detail)
  }, "")

  structure_lines <- c(
    sprintf("- %d 列、%d 欄", profile$n_rows, profile$n_cols),
    if (!is.null(w)) sprintf("- 看起來是**已彙整的次數表**：`%s` 可能是次數欄，合計 %s 個觀察值。下表的次數已用它加權，需要使用者確認。",
                              freq_cols, format(sum(w, na.rm = TRUE), big.mark = ",", trim = TRUE))
    else "- 看起來是**一列一個觀察值**的原始資料",
    vapply(profile$structure$hints, function(h) paste0("- 需要確認：", h$question), ""))

  c(sprintf("# 資料總覽：%s", data_name), "",
    "## 資料結構", "", structure_lines, "",
    "## 各變數", "",
    "| 欄位 | 型態（猜測，需確認） | 缺失 | 類別與次數（比例）／數值摘要 |",
    "|---|---|---|---|", rows)
}

`%||%` <- function(a, b) if (is.null(a)) b else a

# Stage 2: facts about the variables in the user's question. Only numbers, no verdicts.
cda_question_check <- function(data, x, y, z = NULL, count = NULL) {
  data <- as.data.frame(data, check.names = FALSE)
  vars <- c(x, y, z)
  w_all <- if (is.null(count)) rep(1, nrow(data)) else data[[count]]
  complete <- stats::complete.cases(data[vars])
  missing_n <- sum(w_all[!complete])
  d <- data[complete, , drop = FALSE]
  w <- w_all[complete]
  for (v in vars) d[[v]] <- code_order_factor(d[[v]])
  d <- droplevels(d)

  tab <- stats::xtabs(w ~ d[[x]] + d[[y]])
  dimnames(tab) <- list(levels(d[[x]]), levels(d[[y]]))
  n <- sum(tab)
  expected <- outer(rowSums(tab), colSums(tab)) / n
  facts <- list(
    n = n,
    n_missing_dropped = missing_n,
    n_levels = stats::setNames(as.list(vapply(vars, function(v) nlevels(d[[v]]), 1L)), vars),
    table = list(rows = rownames(tab), cols = colnames(tab), counts = unclass(matrix(tab, nrow(tab)))),
    smallest_group = list(variable = x, level = names(which.min(rowSums(tab))), n = min(rowSums(tab))),
    smallest_outcome_category = list(variable = y, level = names(which.min(colSums(tab))), n = min(colSums(tab))),
    min_expected = min(expected),
    cells_expected_below_5 = sum(expected < 5),
    cells_total = length(expected),
    zero_cells = sum(tab == 0)
  )
  if (!is.null(z)) {
    facts$strata <- lapply(levels(d[[z]]), function(s) {
      keep <- d[[z]] == s
      t2 <- stats::xtabs(w[keep] ~ d[[x]][keep] + d[[y]][keep])
      e2 <- outer(rowSums(t2), colSums(t2)) / sum(t2)
      list(stratum = s, n = sum(t2), min_expected = if (sum(t2) > 0) min(e2) else 0, zero_cells = sum(t2 == 0))
    })
  }
  list(facts = facts, data = d, weights = w, table = tab)
}

# Bar chart of one variable's counts.
plot_bar <- function(d, var, w) {
  tab <- weighted_counts(d[[var]], w)
  df <- data.frame(level = factor(names(tab), levels = names(tab)), n = as.numeric(tab))
  ggplot2::ggplot(df, ggplot2::aes(x = level, y = n)) +
    ggplot2::geom_col(fill = "#1f3a5f", width = 0.65) +
    ggplot2::geom_text(ggplot2::aes(label = format(n, big.mark = ",", trim = TRUE)), vjust = -0.4, size = 4) +
    ggplot2::scale_y_continuous(expand = ggplot2::expansion(mult = c(0, 0.12))) +
    ggplot2::labs(x = var, y = "次數") +
    ggplot2::theme_minimal(base_size = 13)
}

# Distribution of y within each level of x (100% stacked bars), split by z if given.
plot_xy <- function(d, x, y, w, z = NULL) {
  grp <- c(x, y, z)
  df <- stats::aggregate(list(n = w), d[grp], sum)
  df$prop <- stats::ave(df$n, interaction(df[c(x, z)], drop = TRUE), FUN = function(v) v / sum(v))
  p <- ggplot2::ggplot(df, ggplot2::aes(x = .data[[x]], y = prop, fill = .data[[y]])) +
    ggplot2::geom_col(width = 0.65, colour = "white") +
    ggplot2::geom_text(ggplot2::aes(label = scales::percent(prop, accuracy = 1)),
                       position = ggplot2::position_stack(vjust = 0.5), colour = "white", size = 3.5) +
    ggplot2::scale_y_continuous(labels = scales::percent) +
    ggplot2::scale_fill_brewer(palette = "Set2") +
    ggplot2::labs(x = x, y = paste0("各組內 ", y, " 的比例"), fill = y) +
    ggplot2::theme_minimal(base_size = 13)
  if (!is.null(z)) p <- p + ggplot2::facet_wrap(stats::as.formula(paste("~", z)), labeller = ggplot2::label_both)
  p
}
