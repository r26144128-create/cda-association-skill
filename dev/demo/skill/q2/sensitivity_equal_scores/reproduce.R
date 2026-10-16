# 重現這次分析的 R 程式碼（需要本專案 R/ 資料夾中的函式）
for (f in list.files("C:/Users/Administrator/Desktop/skill-test-part1/.claude/skills/categorical-data-analysis/R", pattern = "\\.R$", full.names = TRUE)) source(f)
data <- as.data.frame(read_data("C:/Users/Administrator/Desktop/skill-test-part1/student_por.csv"))
spec <- jsonlite::fromJSON("{\n  \"question\": \"每週讀書時間（studytime）越長，及格率（pass）越高嗎？\",\n  \"structure\": \"independent\",\n  \"types\": {\"studytime\": \"ordinal\", \"pass\": \"binary\"},\n  \"method_id\": \"ordinal_trend\",\n  \"reason\": \"解釋變數為有序（4 類）、結果為二元、每列為獨立學生，用線性趨勢檢定 M²（Cochran–Armitage，§2.5）；敏感度分析：分數改用等距 1–4（§2.5.4）\",\n  \"analysis\": \"trend\",\n  \"x\": \"studytime\",\n  \"y\": \"pass\",\n  \"count\": null,\n  \"success\": \"pass\",\n  \"ordinal\": [\"studytime\"],\n  \"design\": \"cross-sectional\",\n  \"levels\": {\"studytime\": [\"1\", \"2\", \"3\", \"4\"], \"pass\": [\"fail\", \"pass\"]},\n  \"x_scores\": [1, 2, 3, 4],\n  \"conf_level\": 0.95\n}")
for (v in names(spec$levels)) data[[v]] <- factor(data[[v]], levels = spec$levels[[v]], ordered = v %in% spec$ordinal)
result <- cda_trend(data, x = "studytime", y = "pass", count = NULL, ordinal = "studytime", 
    x_scores = 1:4, y_scores = NULL, success = "pass")
print(result)
