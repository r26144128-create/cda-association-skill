# 重現這次分析的 R 程式碼（需要本專案 R/ 資料夾中的函式）
for (f in list.files("C:/Users/Administrator/Desktop/skill-test-part1/.claude/skills/categorical-data-analysis/R", pattern = "\\.R$", full.names = TRUE)) source(f)
data <- as.data.frame(read_data("C:/Users/Administrator/Desktop/skill-test-part1/student_por.csv"))
spec <- jsonlite::fromJSON("{\n  \"question\": \"有交往對象（romantic）的學生，及格率（pass）比較低嗎？\",\n  \"structure\": \"independent\",\n  \"types\": {\"romantic\": \"binary\", \"pass\": \"binary\"},\n  \"method_id\": \"crosstab\",\n  \"reason\": \"兩個二元變數、每列為獨立學生，用 2×2 列聯表比較比例並做卡方獨立性檢定（§2.1–2.4）\",\n  \"analysis\": \"crosstab\",\n  \"x\": \"romantic\",\n  \"y\": \"pass\",\n  \"count\": null,\n  \"success\": \"pass\",\n  \"ordinal\": [],\n  \"design\": \"cross-sectional\",\n  \"levels\": {\"romantic\": [\"yes\", \"no\"], \"pass\": [\"pass\", \"fail\"]},\n  \"conf_level\": 0.95\n}")
for (v in names(spec$levels)) data[[v]] <- factor(data[[v]], levels = spec$levels[[v]], ordered = v %in% spec$ordinal)
result <- cda_crosstab(data, x = "romantic", y = "pass", count = NULL, 
    success = "pass", ordinal = list(), design = "cross-sectional", 
    conf.level = 0.95)
print(result)
