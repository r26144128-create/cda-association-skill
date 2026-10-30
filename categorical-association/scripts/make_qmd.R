# Write a reproducible Quarto file for one finished analysis (end of stage 5, only when the
# user asks for it).
#
# Usage: Rscript make_qmd.R <data file> <output dir>
#
# Reads spec.json and result.json from <output dir> (written by run_analysis.R) and writes
# 分析_<data>_<analysis>.qmd there. The R code in the file needs only CRAN packages, not this
# Skill, and recomputes every number. The text pieces live in scripts/qmd/ and are shared with
# make_qmd.py, so both versions write the same file. Claude then replaces the marker under
# "## 結論與解釋" with the stage-5 interpretation.

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 2) stop("Usage: Rscript make_qmd.R <data file> <output dir>")
data_file <- args[1]; out_dir <- args[2]
script_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
qmd_dir <- file.path(dirname(normalizePath(sub("^--file=", "", script_arg[1]))), "qmd")

spec <- jsonlite::fromJSON(file.path(out_dir, "spec.json"), simplifyVector = TRUE)
result <- jsonlite::fromJSON(file.path(out_dir, "result.json"), simplifyVector = TRUE)
if (!is.null(result$error)) stop("result.json 有錯誤，先修正分析再產生 qmd。")

`%||%` <- function(a, b) if (is.null(a)) b else a
q <- function(s) paste0('"', gsub('"', '\\\\"', gsub("\\\\", "\\\\\\\\", s)), '"')
num <- function(v) as.character(as.numeric(v))
r_vec <- function(v, quote = TRUE) paste0("c(", paste(if (quote) q(v) else num(v), collapse = ", "), ")")
bt <- function(s) paste0("`", s, "`")
cell <- function(s) gsub("|", "\\|", s, fixed = TRUE)
fill <- function(piece, values) {
  text <- paste(readLines(file.path(qmd_dir, piece), encoding = "UTF-8", warn = FALSE), collapse = "\n")
  for (k in names(values)) text <- gsub(paste0("{{", k, "}}"), values[[k]], text, fixed = TRUE)
  text
}

analysis <- spec$analysis
x <- spec$x; y <- spec$y; z <- spec$z; count <- spec$count
conf <- num(spec$conf_level %||% 0.95)
success <- if (is.null(spec$success)) "colnames(tab)[1]" else q(spec$success)
if (analysis == "stratified" && is.null(spec$success)) success <- "colnames(tab3)[1]"
vars <- c(x, y, z)

# ---- reading the data, the same way as read_data() in R/utils.R ----
# claude.ai puts a code like "ccd840c3-" in front of uploaded file names; the user's own copy
# has the original name, so the qmd reads that one.
base <- sub("^[0-9a-f]{8}-", "", basename(data_file))
read_code <- if (grepl("\\.dat$", base, ignore.case = TRUE)) {
  "df <- read.table(data_file, header = TRUE)"
} else if (grepl("\\.xlsx?$", base, ignore.case = TRUE)) {
  "df <- as.data.frame(readxl::read_excel(data_file))"
} else {
  text <- rawToChar(readBin(data_file, "raw", file.info(data_file)$size))
  encoding <- if (validUTF8(text)) "UTF-8" else "BIG5"
  header <- sub("[\r\n].*$", "", text)
  counts <- vapply(c(",", ";", "\t"), function(s) lengths(regmatches(header, gregexpr(s, header, fixed = TRUE))), 0)
  delim <- c("," = '","', ";" = '";"', "\t" = '"\\t"')[[names(which.max(counts))]]
  sprintf("df <- as.data.frame(readr::read_delim(data_file, delim = %s,\n  locale = readr::locale(encoding = %s), show_col_types = FALSE))",
          delim, q(encoding))
}

recode_lines <- character()
for (nm in names(spec$recode)) {
  r <- spec$recode[[nm]]
  if (!is.null(r$breaks)) {
    recode_lines <- c(recode_lines,
      sprintf("# 新變數 %s：由 %s 依門檻切分（每個門檻開始一個新類別）", nm, r$from),
      sprintf("df[[%s]] <- cut(as.numeric(df[[%s]]), breaks = c(-Inf, %s, Inf),\n  labels = %s, right = FALSE)",
              q(nm), q(r$from), paste(num(sort(as.numeric(unlist(r$breaks)))), collapse = ", "), r_vec(unlist(r$labels))))
  } else {
    m <- unlist(r$map)
    recode_lines <- c(recode_lines,
      sprintf("# 新變數 %s：由 %s 合併類別", nm, r$from),
      sprintf("df[[%s]] <- factor(unname(c(%s)[as.character(df[[%s]])]),\n  levels = %s)",
              q(nm), paste(sprintf("%s = %s", q(names(m)), q(m)), collapse = ", "), q(r$from), r_vec(unique(unname(m)))))
  }
}
recode_block <- if (length(recode_lines) > 0) paste0("\n```{r}\n", paste(recode_lines, collapse = "\n"), "\n```\n") else ""

factor_code <- vapply(vars, function(v) {
  lv <- spec$levels[[v]]
  if (!is.null(lv)) sprintf("df[[%s]] <- factor(df[[%s]], levels = %s)", q(v), q(v), r_vec(lv))
  else sprintf("df[[%s]] <- factor(df[[%s]], levels = sort(unique(df[[%s]]), method = \"radix\"))", q(v), q(v), q(v))
}, "")
miss_cols <- if (is.null(count)) "vars" else sprintf("c(vars, %s)", q(count))
missing_code <- if (is.null(count)) {
  "c(排除筆數 = sum(miss), 比例 = mean(miss))"
} else {
  sprintf("w <- df[[%s]]\nc(排除次數 = sum(w[miss], na.rm = TRUE), 比例 = sum(w[miss], na.rm = TRUE) / sum(w, na.rm = TRUE))", q(count))
}
zero_code <- if (is.null(count)) "" else sprintf("\ndf <- df[df[[%s]] > 0, ]                  # 次數為 0 的列不影響次數表", q(count))
formula <- paste0(if (is.null(count)) "~ " else paste0(bt(count), " ~ "), paste(bt(vars), collapse = " + "))

# ---- analysis settings table ----
types <- spec$types
settings <- c(
  if (!is.null(spec$question)) sprintf("| 問題 | %s |", cell(spec$question)),
  sprintf("| 資料檔 | `%s` |", cell(base)),
  sprintf("| 方法 | %s（Agresti %s） |", cell(result$method_label), result$book_ref),
  if (!is.null(spec$reason)) sprintf("| 選擇理由 | %s |", cell(spec$reason)),
  sprintf("| 變數 | 解釋變數 X：%s；結果變數 Y：%s%s |", cell(x), cell(y), if (is.null(z)) "" else paste0("；控制變數 Z：", cell(z))),
  if (length(types) > 0) sprintf("| 變數型態 | %s |", cell(paste(sprintf("%s：%s", names(types), unlist(types)), collapse = "；"))),
  if (!is.null(spec$structure)) sprintf("| 資料結構 | %s |", cell(spec$structure)),
  if (!is.null(spec$design)) sprintf("| 研究設計 | %s |", cell(spec$design)))

pieces <- fill("header.qmd", list(
  title = gsub('"', '\\"', sprintf("分析報告：%s", spec$question %||% result$method_label), fixed = TRUE),
  data_file = base, data_file_q = q(base), settings = paste(settings, collapse = "\n"), read_code = read_code,
  recode_block = recode_block, factor_code = paste(factor_code, collapse = "\n"),
  vars = r_vec(vars), miss_cols = miss_cols, missing_code = missing_code, zero_code = zero_code))

test_names <- result$tests$test
if (analysis == "crosstab") {
  pieces <- c(pieces, fill("crosstab.qmd", list(formula = formula)))
  if ("Fisher exact (two-sided)" %in% test_names) pieces <- c(pieces, fill("fisher_2x2.qmd", list()))
  else if (any(startsWith(test_names, "Fisher exact:"))) pieces <- c(pieces, fill("fisher_rxc.qmd", list()))
  if (length(result$estimates) > 0 && NROW(result$estimates) > 0) {
    piece <- if (identical(spec$design, "case-control")) "effect_cc.qmd" else "effect.qmd"
    pieces <- c(pieces, fill(piece, list(success = success, conf = conf)))
  }
  pieces <- c(pieces, fill("plot.qmd", list(x_q = q(x), y_q = q(y))))
} else if (analysis == "trend") {
  ca <- result$notes$trend_type == "cochran_armitage"
  v <- if (ca) sprintf("as.numeric(colnames(tab) == %s)   # %s：成功 = 1，其他 = 0", success, y)
       else paste0(r_vec(result$notes$scores$y, quote = FALSE), "   # ", y, " 各類的分數（依順序）")
  pieces <- c(pieces, fill("trend.qmd", list(
    formula = formula, x = x, u = r_vec(result$notes$scores$x, quote = FALSE), v = v,
    trend_name = if (ca) "Cochran–Armitage 趨勢檢定" else "Linear-by-linear association 檢定")))
  if (!is.null(spec$x_scores) || !is.null(spec$y_scores)) {
    pieces <- c(pieces, fill("trend_sensitivity.qmd", list(v_equal = if (ca) "v" else "seq_len(ncol(tab))")))
  }
  pieces <- c(pieces, fill("plot.qmd", list(x_q = q(x), y_q = q(y))))
} else {
  pieces <- c(pieces, fill("stratified.qmd", list(formula = formula, success = success, conf = conf)),
              fill("plot_stratified.qmd", list(x_q = q(x), y_q = q(y), z_q = q(z))))
}

w <- result$warnings
warnings_block <- if (length(w) > 0 && NROW(w) > 0) {
  paste0("\n## 注意事項\n\n", paste(sprintf("- %s（Agresti %s）", w$message, w$book_ref), collapse = "\n"), "\n")
} else ""
pieces <- c(pieces, fill("footer.qmd", list(warnings_block = warnings_block, reminder = result$notes$reminder)))

out_file <- file.path(out_dir, sprintf("分析_%s_%s.qmd", tools::file_path_sans_ext(base), analysis))
con <- file(out_file, open = "wb")
writeBin(charToRaw(enc2utf8(paste0(paste(pieces, collapse = "\n"), "\n"))), con)
close(con)
message("QMD: ", normalizePath(out_file))
