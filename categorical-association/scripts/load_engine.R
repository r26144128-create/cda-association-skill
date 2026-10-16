# Sourced by the Skill's scripts: find and load the analysis engine (the R/ folder),
# either bundled inside the Skill (skill/R) or in the repository root (../../R).
local({
  script_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
  script_dir <- dirname(normalizePath(sub("^--file=", "", script_arg[1])))
  candidates <- file.path(script_dir, c(file.path("..", "R"), file.path("..", "..", "R")))
  engine_dir <- Filter(function(d) file.exists(file.path(d, "utils.R")), candidates)
  if (length(engine_dir) == 0) stop("找不到統計引擎（R/ 資料夾）。")
  engine_dir <- normalizePath(engine_dir[1], winslash = "/")
  for (f in list.files(engine_dir, pattern = "\\.R$", full.names = TRUE)) source(f, encoding = "UTF-8")
  assign("ENGINE_DIR", engine_dir, envir = globalenv())
})
