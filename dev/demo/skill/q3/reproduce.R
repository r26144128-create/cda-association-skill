# 重現這次分析的 R 程式碼（需要本專案 R/ 資料夾中的函式）
for (f in list.files("C:/Users/Administrator/Desktop/skill-test-part1/.claude/skills/categorical-data-analysis/R", pattern = "\\.R$", full.names = TRUE)) source(f)
data <- as.data.frame(read_data("C:/Users/Administrator/Desktop/skill-test-part1/student_por.csv"))
spec <- jsonlite::fromJSON("{\n  \"question\": \"控制學校（school）之後，有沒有交往（romantic）和及格（pass）的關係還在嗎？\",\n  \"structure\": \"independent\",\n  \"types\": {\"romantic\": \"binary\", \"pass\": \"binary\", \"school\": \"binary\"},\n  \"method_id\": \"three_way\",\n  \"reason\": \"X、Y 皆為二元、加一個二元控制變數 school、每列為獨立學生，用分層 2×2 表的條件勝算比與 CMH 檢定（§2.7、§4.3.4）\",\n  \"analysis\": \"stratified\",\n  \"x\": \"romantic\",\n  \"y\": \"pass\",\n  \"z\": \"school\",\n  \"count\": null,\n  \"success\": \"pass\",\n  \"ordinal\": [],\n  \"design\": \"cross-sectional\",\n  \"levels\": {\"romantic\": [\"yes\", \"no\"], \"pass\": [\"pass\", \"fail\"], \"school\": [\"GP\", \"MS\"]},\n  \"conf_level\": 0.95\n}")
for (v in names(spec$levels)) data[[v]] <- factor(data[[v]], levels = spec$levels[[v]], ordered = v %in% spec$ordinal)
result <- cda_stratified(data, x = "romantic", y = "pass", z = "school", 
    count = NULL, success = "pass", conf.level = 0.95)
print(result)
