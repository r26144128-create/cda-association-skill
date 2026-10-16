# Shared building blocks for every analysis function.
#
# Every analysis returns a `cda_result`: a list that the website prints and the Skill
# serialises to JSON. Numbers live only in `estimates`, `tests` and `tables`; `facts`
# are fixed-template sentences built from those numbers, so the LLM can rephrase them
# without ever computing anything itself.

cda_result <- function(method, method_label, book_ref, tier,
                       estimates = data.frame(), tests = data.frame(),
                       tables = list(), warnings = list(), facts = character(),
                       notes = list()) {
  structure(
    list(method = method, method_label = method_label, book_ref = book_ref, tier = tier,
         estimates = estimates, tests = tests, tables = tables,
         warnings = warnings, facts = facts, notes = notes),
    class = "cda_result"
  )
}

# A warning always carries the textbook section that justifies it.
cda_warning <- function(code, message, book_ref) {
  list(code = code, message = message, book_ref = book_ref)
}

fmt_num <- function(x, digits = 3) formatC(x, digits = digits, format = "f")

fmt_p <- function(p) {
  vapply(p, function(v) {
    if (is.na(v)) return("NA")
    if (v < 0.001) return("< 0.001")
    formatC(v, digits = 3, format = "f")
  }, "", USE.NAMES = FALSE)
}

# JSON has no infinity and jsonlite would write null, which reads as "missing".
# Write "Inf"/"-Inf" instead (e.g. a sample odds ratio of ∞, an unbounded CI limit).
.mark_infinite <- function(x) {
  if (is.data.frame(x)) { x[] <- lapply(x, .mark_infinite); return(x) }
  if (is.list(x)) return(lapply(x, .mark_infinite))
  if (is.numeric(x) && any(is.infinite(x))) {
    return(lapply(x, function(v) if (is.infinite(v)) (if (v > 0) "Inf" else "-Inf") else v))
  }
  x
}

# Convert a result to JSON for the Skill. Tables become lists of rows.
cda_to_json <- function(result, path = NULL) {
  out <- unclass(result)
  out$tables <- lapply(result$tables, function(t) {
    if (is.table(t) || is.matrix(t)) {
      m <- as.matrix(t)
      list(rows = rownames(m), cols = colnames(m), values = unname(split(m, row(m))))
    } else t
  })
  json <- jsonlite::toJSON(.mark_infinite(out), auto_unbox = TRUE, digits = NA, pretty = TRUE, na = "null")
  if (!is.null(path)) writeLines(json, path, useBytes = TRUE)
  invisible(json)
}

print.cda_result <- function(x, ...) {
  cat(x$method_label, " [", x$book_ref, ", tier ", x$tier, "]\n", sep = "")
  if (length(x$facts)) cat(paste0("- ", x$facts), sep = "\n")
  if (length(x$warnings)) {
    cat("Warnings:\n")
    for (w in x$warnings) cat("  ! ", w$message, " (", w$book_ref, ")\n", sep = "")
  }
  invisible(x)
}

# Read a user's data file. Handles textbook .dat files, Excel files, UTF-8 CSVs (with or
# without BOM) and Big5 CSVs, which Excel in Taiwan often produces.
read_data <- function(path) {
  if (grepl("\\.dat$", path, ignore.case = TRUE)) {
    return(utils::read.table(path, header = TRUE, stringsAsFactors = FALSE))
  }
  if (grepl("\\.xlsx?$", path, ignore.case = TRUE)) {
    return(readxl::read_excel(path))
  }
  raw <- readBin(path, "raw", file.info(path)$size)
  text <- rawToChar(raw)
  encoding <- if (validUTF8(text)) "UTF-8" else "BIG5"
  # Delimiter: whichever of comma, semicolon (common in European exports) or tab
  # appears most often in the header line.
  header <- sub("[\r\n].*$", "", text)
  counts <- vapply(c(",", ";", "\t"), function(s) lengths(regmatches(header, gregexpr(s, header, fixed = TRUE))), 0)
  readr::read_delim(path, delim = names(which.max(counts)), locale = readr::locale(encoding = encoding),
                    show_col_types = FALSE, progress = FALSE)
}

# Create new categorical variables from existing ones, as the user requested (Skill `recode`).
# Done in R so that no value is ever computed by the language model.
#   list(pass = list(from = "G3", breaks = 10, labels = c("fail", "pass")))
#     -> values below 10 become "fail", 10 and above "pass" (each break starts a new category)
#   list(Walc2 = list(from = "Walc", map = list("1" = "low", "2" = "low", "3" = "high", ...)))
#     -> merge or rename categories
# Returns the data with the new columns and a plain-language description of each recode.
cda_recode <- function(data, recode) {
  notes <- character()
  for (nm in names(recode)) {
    r <- recode[[nm]]
    if (is.null(r$from) || !r$from %in% names(data)) stop("recode：找不到來源欄位 ", r$from)
    src <- data[[r$from]]
    if (!is.null(r$breaks)) {
      br <- sort(as.numeric(unlist(r$breaks)))
      labs <- unlist(r$labels)
      if (length(labs) != length(br) + 1) stop("recode：", nm, " 的 labels 數目必須比 breaks 多 1。")
      data[[nm]] <- factor(cut(as.numeric(src), breaks = c(-Inf, br, Inf), labels = labs, right = FALSE), levels = labs)
      ranges <- c(sprintf("< %s", br[1]),
                  if (length(br) > 1) sprintf("%s – < %s", utils::head(br, -1), br[-1]) else NULL,
                  sprintf("≥ %s", br[length(br)]))
      notes <- c(notes, sprintf("新變數 %s 由 %s 轉換：%s。", nm, r$from,
                                paste(sprintf("%s → %s", ranges, labs), collapse = "；")),
                 sprintf(paste0("提醒：把連續的 %s 切成類別會損失資訊，結論可能隨切點改變；看過資料才挑的切點會造成偏誤。",
                                "如果想知道 %s 越大結果怎麼變，較適合用 logistic 等模型（類別模型 Skill）。"),
                         r$from, r$from))
    } else if (!is.null(r$map)) {
      m <- unlist(r$map)
      out <- unname(m[as.character(src)])
      unmapped <- unique(as.character(src[is.na(out) & !is.na(src)]))
      if (length(unmapped) > 0) stop("recode：", r$from, " 的這些值沒有對應：", paste(unmapped, collapse = ", "))
      data[[nm]] <- factor(out, levels = unique(unname(m)))
      notes <- c(notes, sprintf("新變數 %s 由 %s 合併類別：%s。", nm, r$from,
                                paste(sprintf("%s → %s", names(m), m), collapse = "；")))
    } else {
      stop("recode：", nm, " 需要 breaks（依門檻切分）或 map（合併類別）。")
    }
  }
  attr(data, "recode_notes") <- notes
  data
}
