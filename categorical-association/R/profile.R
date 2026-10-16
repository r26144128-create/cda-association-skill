# Data profiling for the Skill: guess each variable's scale and look for signs of
# non-independent data. Everything here is a *guess* for the user to confirm: the data
# alone cannot tell ordinal from nominal codes (§1.1.2) or reveal the study design.

.ordinal_words <- c(
  "非常", "很", "有點", "普通", "還好", "尚可", "不太", "同意", "滿意", "喜歡",
  "低", "中", "高", "從不", "從未", "很少", "偶爾", "有時", "經常", "時常", "總是",
  "輕", "重", "差", "好", "優", "劣", "每天", "每週", "每月",
  "never", "rarely", "seldom", "sometimes", "often", "usually", "always",
  "low", "medium", "moderate", "high", "none", "slight", "mild", "severe",
  "poor", "fair", "good", "excellent", "agree", "disagree", "neutral",
  "satisf", "dissatisf", "strongly", "very", "somewhat", "little"
)
.id_name_pattern <- paste0(
  "^(id|.*_id|person|subject|case|patient|participant|respondent|student|school|class|",
  "cluster|family|household|group|litter|center|centre|hospital|clinic|crab)$|",
  "編號|學號|代號|受試|個案|病患|病人|受訪|學生|學校|班級|家庭|家戶|醫院|群組")
.time_name_pattern <- paste0(
  "^(time|visit|week|month|year|wave|occasion|round|period|trial|session|situation|question|",
  "item|condition|course|t)$|時間|時點|次數|第幾|週|月份|年度|期|回合|題目|情境|科目|課程|學科")
.pair_name_pattern <- "pre|post|before|after|baseline|follow|^y[0-9]$|^t[0-9]$|前測|後測|之前|之後|第一次|第二次"
.count_name_pattern <- "^(n|count|counts|freq|frequency|weight|wt)$|次數|人數|頻數|數量|個數"
.age_name_pattern <- "^age$|_age$|^age_|年齡|歲"

# Categories in character-code order (numbers numerically), so the order shown to the
# user does not depend on the computer's locale and matches the Python version.
code_order_factor <- function(v) {
  if (is.factor(v)) return(v)
  factor(v, levels = sort(unique(v[!is.na(v)]), method = "radix"))
}

profile_variable <- function(v, name) {
  n <- length(v)
  miss <- sum(is.na(v))
  x <- v[!is.na(v)]
  uniq <- unique(x)
  k <- length(uniq)
  is_num <- is.numeric(x)
  int_like <- is_num && all(abs(x - round(x)) < 1e-8)
  lev_counts <- if (k <= 20) table(code_order_factor(x)) else NULL

  guess <- "nominal"; confirm <- FALSE; reason <- ""
  if (k == 0) {
    guess <- "empty"; reason <- "全部缺失"
  } else if (grepl(.id_name_pattern, name, ignore.case = TRUE) && k > 10) {
    guess <- "id"; reason <- "欄名像識別碼，且類別很多"
  } else if (k == length(x) && k > 20 && (int_like || !is_num)) {
    guess <- "id"; reason <- "每一列的值都不同"
  } else if (k == 2) {
    guess <- "binary"; reason <- "只有 2 種值"
  } else if (is_num && grepl(.age_name_pattern, name, ignore.case = TRUE)) {
    guess <- "continuous"; reason <- "欄名像年齡，視為數值變數"
  } else if (is_num && !int_like) {
    guess <- "continuous"; reason <- "含小數的數值"
  } else if (int_like && k <= 10 && max(x) - min(x) == k - 1) {
    guess <- "ordinal_or_nominal_code"; confirm <- TRUE
    reason <- sprintf("只有 %d 個連續整數（%s–%s），可能是有序量表或類別代碼", k, min(x), max(x))
  } else if (int_like && min(x) >= 0 && grepl(.count_name_pattern, name, ignore.case = TRUE)) {
    guess <- "frequency_weight"; confirm <- TRUE; reason <- "欄名像次數，可能是彙整資料的次數欄"
  } else if (int_like && min(x) >= 0) {
    guess <- "count_or_continuous"; confirm <- TRUE; reason <- "非負整數且值很多，可能是計數或連續量"
  } else if (is_num) {
    guess <- "continuous"; reason <- "數值且值很多"
  } else if (k > 20) {
    guess <- "nominal_many_levels"; confirm <- TRUE; reason <- "文字類別超過 20 種，可能是自由填答或識別碼"
  } else {
    hits <- vapply(as.character(uniq), function(u)
      any(vapply(.ordinal_words, function(w) grepl(w, u, ignore.case = TRUE), logical(1))), logical(1))
    if (mean(hits) >= 0.5) {
      guess <- "ordinal_candidate"; confirm <- TRUE; reason <- "類別名稱像有順序的量表，請確認順序"
    } else {
      reason <- "文字類別，看起來沒有順序"
    }
  }
  list(
    name = name, n = n, n_missing = miss, n_unique = k,
    type_guess = guess, needs_confirmation = confirm, reason = reason,
    levels = if (!is.null(lev_counts)) as.list(stats::setNames(as.integer(lev_counts), names(lev_counts))) else NULL,
    examples = utils::head(as.character(uniq), 5),
    range = if (is_num && k > 0) c(min(x), max(x)) else NULL
  )
}

# Look for signs that rows are not independent observations (Ch.8–10).
detect_structure <- function(data, vars) {
  hints <- list()
  types <- vapply(vars, `[[`, "", "type_guess")
  nrow_d <- nrow(data)

  # 1. An id-like column with repeated values: repeated measures or clustered data.
  # Needs at least 5 distinct ids (otherwise it is an ordinary grouping variable such as
  # treatment arm), and does not apply to aggregated data where each row is a table cell.
  id_cols <- names(data)[grepl(.id_name_pattern, names(data), ignore.case = TRUE)]
  if (any(types == "frequency_weight")) id_cols <- character()
  for (idc in id_cols) {
    ids <- data[[idc]][!is.na(data[[idc]])]
    per_id <- table(ids)
    if (length(per_id) >= 5 && max(per_id) >= 2) {
      time_cols <- setdiff(names(data)[grepl(.time_name_pattern, names(data), ignore.case = TRUE)], idc)
      within <- Filter(function(tc) {
        k <- length(unique(stats::na.omit(data[[tc]])))
        k >= 2 && k <= 20 && all(tapply(data[[tc]], data[[idc]], function(z) !anyDuplicated(stats::na.omit(z))))
      }, time_cols)
      kind <- if (length(within) > 0) "repeated_measures" else "clustered"
      hints[[length(hints) + 1]] <- list(
        type = kind, columns = I(c(idc, within)),
        evidence = sprintf("%s 有 %d 個不同的值，每個值出現 %d–%d 列（中位數 %s）%s",
                           idc, length(per_id), min(per_id), max(per_id), stats::median(per_id),
                           if (length(within)) paste0("；", paste(within, collapse = "/"), " 在每個 ", idc, " 內不重複，像是測量時點或題目") else ""),
        question = if (kind == "repeated_measures")
          sprintf("同一個 %s 是否被測量了多次（每次一列）？", idc)
          else sprintf("%s 是否代表群組（例如學校、家庭），同群組內的觀察可能彼此相關？", idc),
        book_ref = "§9.1, §10.1")
    }
  }

  # 2. Wide matched pairs: two or more categorical columns sharing the same set of levels.
  # Generic codes such as 0/1 are shared by unrelated variables, so only flag columns whose
  # names look like repeated measurements, or that share a text scale with 3+ categories.
  # Skipped when the data are already in long (repeated-measures) format.
  cat_cols <- names(data)[types %in% c("binary", "nominal", "ordinal_candidate", "ordinal_or_nominal_code")]
  long_format <- any(vapply(hints, function(h) h$type == "repeated_measures", logical(1)))
  if (length(cat_cols) >= 2 && !long_format) {
    sets <- lapply(cat_cols, function(cc) sort(unique(as.character(stats::na.omit(data[[cc]]))), method = "radix"))
    names(sets) <- cat_cols
    seen <- character()
    for (i in seq_along(sets)) {
      same <- names(sets)[vapply(sets, identical, logical(1), sets[[i]])]
      key <- paste(same, collapse = "|")
      if (length(same) >= 2 && !key %in% seen) {
        seen <- c(seen, key)
        named_like_pairs <- sum(grepl(.pair_name_pattern, same, ignore.case = TRUE)) >= 2
        text_scale <- length(sets[[i]]) >= 3 && !is.numeric(data[[same[1]]])
        if (!named_like_pairs && !text_scale) next
        hints[[length(hints) + 1]] <- list(
          type = "possible_matched_pairs_wide", columns = I(same),
          evidence = sprintf("%s 的類別完全相同（%s）%s", paste(same, collapse = "、"),
                             paste(sets[[i]], collapse = "/"),
                             if (named_like_pairs) "，且欄名像前後測或重複測量" else ""),
          question = sprintf("%s 是不是「同一個人」在不同時間或不同題目的回答（配對資料）？還是只是剛好用相同選項的不同變數？",
                             paste(same, collapse = "、")),
          book_ref = "§8.1")
      }
    }
  }

  # 3. Aggregated data: a frequency column means each row is a cell, not a subject.
  freq_cols <- names(types)[types == "frequency_weight"]
  if (length(freq_cols) > 0) {
    hints[[length(hints) + 1]] <- list(
      type = "aggregated_counts", columns = I(freq_cols),
      evidence = sprintf("%s 看起來是次數欄，每一列可能代表一個格子而不是一個人", paste(freq_cols, collapse = "、")),
      question = sprintf("%s 是否代表「這種組合有幾個人」？", paste(freq_cols, collapse = "、")),
      book_ref = "§3.2.5, §5.2.3")
  }

  list(
    n_rows = nrow_d,
    hints = hints,
    default = if (length(hints) == 0) "independent" else "needs_confirmation",
    note = "資料本身無法證明觀察值彼此獨立。第 1–7 章的方法都假設獨立（§1.1.3），請使用者確認每一列是否為不同的獨立個體。"
  )
}

cda_profile <- function(data) {
  data <- as.data.frame(data, check.names = FALSE)
  vars <- lapply(names(data), function(nm) profile_variable(data[[nm]], nm))
  names(vars) <- names(data)
  list(n_rows = nrow(data), n_cols = ncol(data), variables = unname(vars),
       structure = detect_structure(data, vars))
}
