# Stage 2: once the user has a question, draw the variables involved and report the facts
# needed to check the data against references/checklist.md.
#
# Usage: Rscript describe_question.R <data file> <question.json> <output dir>
#
# question.json example:
#   {"x": "Sex", "y": "Survived", "z": null, "count": null,
#    "levels": {"Survived": ["Yes", "No"]}, "recode": null}
#
# Writes to <output dir>: check.json, bar_<variable>.png, relation.png, 初步檢視_<data>.md.
# On failure, check.json contains {"error": "..."} and the script exits with status 1.

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 3) stop("Usage: Rscript describe_question.R <data file> <question.json> <output dir>")
data_file <- args[1]; q_file <- args[2]; out_dir <- args[3]
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

fail <- function(msg) {
  writeLines(jsonlite::toJSON(list(error = msg), auto_unbox = TRUE, pretty = TRUE),
             file.path(out_dir, "check.json"), useBytes = TRUE)
  message("ERROR: ", msg)
  quit(status = 1)
}

script_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
source(file.path(dirname(normalizePath(sub("^--file=", "", script_arg[1]))), "load_engine.R"))

q <- jsonlite::fromJSON(q_file, simplifyVector = TRUE)
data <- tryCatch(as.data.frame(read_data(data_file)), error = function(e) fail(paste("無法讀取資料：", conditionMessage(e))))
recode_notes <- character()
if (!is.null(q$recode)) {
  data <- tryCatch(cda_recode(data, q$recode), error = function(e) fail(conditionMessage(e)))
  recode_notes <- attr(data, "recode_notes")
}
needed <- unlist(q[c("x", "y", "z", "count")])
missing_cols <- setdiff(needed, names(data))
if (length(missing_cols) > 0) {
  fail(sprintf("資料中找不到欄位：%s。現有欄位：%s", paste(missing_cols, collapse = ", "),
               paste(names(data), collapse = ", ")))
}
for (v in names(q$levels)) data[[v]] <- factor(data[[v]], levels = q$levels[[v]])

chk <- tryCatch(cda_question_check(data, q$x, q$y, q$z, q$count), error = function(e) fail(conditionMessage(e)))
f <- chk$facts

plots <- list()
for (v in c(q$x, q$y, q$z)) plots[[paste0("bar_", v)]] <- plot_bar(chk$data, v, chk$weights)
plots$relation <- plot_xy(chk$data, q$x, q$y, chk$weights, q$z)
for (name in names(plots)) {
  ggplot2::ggsave(file.path(out_dir, paste0(name, ".png")), plots[[name]],
                  width = if (name == "relation" && !is.null(q$z)) 9 else 6, height = 4, dpi = 150, bg = "white")
}
f$plots <- paste0(names(plots), ".png")
f$recode_notes <- I(recode_notes)
writeLines(jsonlite::toJSON(f, auto_unbox = TRUE, pretty = TRUE, digits = NA, null = "null"),
           file.path(out_dir, "check.json"), useBytes = TRUE)

# Markdown summary for the user.
tab <- chk$table
md_tab <- c(paste0("| ", q$x, " \\ ", q$y, " | ", paste(colnames(tab), collapse = " | "), " | 合計 |"),
            paste0("|", strrep("---|", ncol(tab) + 2)),
            sprintf("| %s | %s | %s |", rownames(tab),
                    apply(tab, 1, function(r) paste(format(r, big.mark = ",", trim = TRUE), collapse = " | ")),
                    format(rowSums(tab), big.mark = ",", trim = TRUE)))
lines <- c(sprintf("# 初步檢視：%s", basename(data_file)), "",
           recode_notes,
           sprintf("- 使用的觀察值：%s（因缺失刪除 %s）", format(f$n, big.mark = ",", trim = TRUE), format(f$n_missing_dropped, big.mark = ",", trim = TRUE)),
           sprintf("- 最小的一組：%s = %s，%s 個", f$smallest_group$variable, f$smallest_group$level,
                   format(f$smallest_group$n, big.mark = ",", trim = TRUE)),
           sprintf("- 獨立假設下的最小期望次數：%s；期望次數 < 5 的格子：%d / %d；次數為 0 的格子：%d",
                   fmt_num(f$min_expected, 2), f$cells_expected_below_5, f$cells_total, f$zero_cells),
           if (!is.null(q$z)) vapply(f$strata, function(s)
             sprintf("- %s = %s：%s 個，最小期望次數 %s，0 次數格子 %d", q$z, s$stratum,
                     format(s$n, big.mark = ",", trim = TRUE), fmt_num(s$min_expected, 2), s$zero_cells), ""),
           "", "## 次數表", "", md_tab, "",
           "## 圖", "", sprintf("![](%s)", f$plots))
con <- file(file.path(out_dir, paste0("初步檢視_", tools::file_path_sans_ext(basename(data_file)), ".md")),
            open = "w", encoding = "UTF-8")
writeLines(lines, con)
close(con)
message("OK: ", normalizePath(file.path(out_dir, "check.json")))
