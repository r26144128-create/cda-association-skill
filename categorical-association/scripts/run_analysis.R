# Run one analysis for the categorical-association Skill.
#
# Usage: Rscript run_analysis.R <data file> <spec.json> <output dir>
#
# spec.json example:
#   {"question": "...", "structure": "independent", "types": {"gender": "binary", "party": "nominal"},
#    "method_id": "crosstab", "reason": "...",
#    "analysis": "crosstab", "x": "gender", "y": "party",
#    "count": null, "success": null, "ordinal": [], "design": "unknown",
#    "levels": {"party": ["Dem", "Rep", "Ind"]}, "conf_level": 0.95}
#   analysis "trend" also takes "x_scores" / "y_scores"; "stratified" takes "z".
#   Optional "recode" creates new categorical variables first (see cda_recode in R/utils.R).
#
# Writes to <output dir>: result.json, PNG plots, 分析報告_<data>_<analysis>.md, reproduce.R.
# On failure, result.json contains {"error": "..."} and the script exits with status 1.

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 3) {
  stop("Usage: Rscript run_analysis.R <data file> <spec.json> <output dir>")
}
data_file <- args[1]; spec_file <- args[2]; out_dir <- args[3]
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

fail <- function(msg) {
  writeLines(jsonlite::toJSON(list(error = msg), auto_unbox = TRUE, pretty = TRUE),
             file.path(out_dir, "result.json"), useBytes = TRUE)
  message("ERROR: ", msg)
  quit(status = 1)
}

script_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
source(file.path(dirname(normalizePath(sub("^--file=", "", script_arg[1]))), "load_engine.R"))

spec <- jsonlite::fromJSON(spec_file, simplifyVector = TRUE)
data <- tryCatch(as.data.frame(read_data(data_file)), error = function(e) fail(paste("無法讀取資料：", conditionMessage(e))))
recode_notes <- character()
if (!is.null(spec$recode)) {
  data <- tryCatch(cda_recode(data, spec$recode), error = function(e) fail(conditionMessage(e)))
  recode_notes <- attr(data, "recode_notes")
}

needed <- unlist(spec[c("x", "y", "z", "count")])
missing_cols <- setdiff(needed, names(data))
if (length(missing_cols) > 0) {
  fail(sprintf("資料中找不到欄位：%s。現有欄位：%s", paste(missing_cols, collapse = ", "),
               paste(names(data), collapse = ", ")))
}
for (v in names(spec$levels)) {
  data[[v]] <- factor(data[[v]], levels = spec$levels[[v]], ordered = v %in% spec$ordinal)
}

`%||%` <- function(a, b) if (is.null(a)) b else a
analyses <- list(
  crosstab = list(fun = "cda_crosstab", args = list(
    x = spec$x, y = spec$y, count = spec$count, success = spec$success,
    ordinal = spec$ordinal %||% character(), design = spec$design %||% "unknown",
    conf.level = spec$conf_level %||% 0.95)),
  trend = list(fun = "cda_trend", args = list(
    x = spec$x, y = spec$y, count = spec$count, ordinal = spec$ordinal %||% character(),
    x_scores = spec$x_scores, y_scores = spec$y_scores, success = spec$success)),
  stratified = list(fun = "cda_stratified", args = list(
    x = spec$x, y = spec$y, z = spec$z, count = spec$count, success = spec$success,
    conf.level = spec$conf_level %||% 0.95))
)
if (!spec$analysis %in% names(analyses)) {
  fail(paste0("本 Skill 不支援的分析：", spec$analysis,
              "。本 Skill 只做兩個類別變數的關聯分析（crosstab、trend、stratified）。"))
}
call_info <- analyses[[spec$analysis]]
result <- tryCatch(do.call(call_info$fun, c(list(data = data), call_info$args)),
                   error = function(e) fail(conditionMessage(e)))
result$facts <- c(recode_notes, result$facts)  # say how any new variable was made

plots <- cda_plots(result)
result$plots <- character()
for (name in names(plots)) {
  path <- file.path(out_dir, paste0(name, ".png"))
  ggplot2::ggsave(path, plots[[name]], width = 7, height = 4.5, dpi = 150, bg = "white")
  result$plots <- c(result$plots, basename(path))
}

# ---- Markdown report: every number is written here by R, never retyped by the model ----
md_table <- function(df, digits = 4) {
  if (is.null(df) || nrow(df) == 0) return(character())
  fmt <- function(v) if (is.numeric(v)) ifelse(is.na(v), "—", ifelse(is.infinite(v), "∞",
    ifelse(abs(v) < 1e-3 & v != 0, formatC(v, digits = 3, format = "e"), formatC(v, digits = digits, format = "f")))) else as.character(v)
  cells <- as.data.frame(lapply(df, fmt), check.names = FALSE, stringsAsFactors = FALSE)
  c(paste0("| ", paste(names(df), collapse = " | "), " |"),
    paste0("|", paste(rep("---", ncol(df)), collapse = "|"), "|"),
    apply(cells, 1, function(r) paste0("| ", paste(r, collapse = " | "), " |")))
}
counts <- result$tables$counts
count_md <- if (!is.null(counts) && length(dim(counts)) == 2) {
  m <- as.matrix(counts)
  md_table(cbind(data.frame(` ` = rownames(m), check.names = FALSE), as.data.frame.matrix(m)), digits = 0)
} else if (!is.null(result$tables$partial_tables)) md_table(result$tables$partial_tables, digits = 0) else character()
data_name <- tools::file_path_sans_ext(basename(data_file))
report <- c(
  sprintf("# 分析報告：%s", spec$question %||% result$method_label), "",
  sprintf("- 資料檔：`%s`", basename(data_file)),
  sprintf("- 方法：%s（Agresti %s）", result$method_label, result$book_ref),
  if (!is.null(spec$structure)) sprintf("- 資料結構：%s", spec$structure),
  if (!is.null(spec$reason)) sprintf("- 選擇理由：%s", spec$reason), "",
  "## 次數表", "", count_md, "",
  "## 結果", "", paste0("- ", result$facts), "",
  if (nrow(result$tests) > 0) c("## 檢定", "", md_table(result$tests[, c("test", "statistic", "df", "p_value", "book_ref")]), ""),
  if (nrow(result$estimates) > 0) c("## 效果量與信賴區間", "", md_table(result$estimates), ""),
  if (length(result$warnings) > 0) c("## 注意事項", "",
    vapply(result$warnings, function(w) sprintf("- %s（Agresti %s）", w$message, w$book_ref), ""), ""),
  "## 圖", "", sprintf("![](%s)", result$plots), "",
  sprintf("> %s", result$notes$reminder))
report_file <- file.path(out_dir, sprintf("分析報告_%s_%s.md", data_name, spec$analysis))
writeLines(report, report_file, useBytes = TRUE)
result$report <- basename(report_file)

writeLines(c(
  "# 重現這次分析的 R 程式碼（需要本 Skill 的 R/ 資料夾）",
  sprintf('for (f in list.files("%s", pattern = "\\\\.R$", full.names = TRUE)) source(f)', ENGINE_DIR),
  sprintf('data <- as.data.frame(read_data("%s"))', normalizePath(data_file, winslash = "/")),
  sprintf('spec <- jsonlite::fromJSON(%s)', deparse(paste(readLines(spec_file, warn = FALSE), collapse = "\n"))),
  'if (!is.null(spec$recode)) data <- cda_recode(data, spec$recode)',
  'for (v in names(spec$levels)) data[[v]] <- factor(data[[v]], levels = spec$levels[[v]], ordered = v %in% spec$ordinal)',
  paste0("result <- ", paste(deparse(as.call(c(as.name(call_info$fun), quote(data), call_info$args))), collapse = "\n")),
  "print(result)"
), file.path(out_dir, "reproduce.R"), useBytes = TRUE)

spec_copy <- file.path(out_dir, "spec.json")  # keep the decision record next to the results
if (!file.exists(spec_copy) || normalizePath(spec_file) != normalizePath(spec_copy)) {
  invisible(file.copy(spec_file, spec_copy, overwrite = TRUE))
}
cda_to_json(result, file.path(out_dir, "result.json"))
message("OK: ", normalizePath(file.path(out_dir, "result.json")))
message("REPORT: ", normalizePath(report_file))
