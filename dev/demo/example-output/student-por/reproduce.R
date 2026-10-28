# 重現這次分析的 R 程式碼（需要本 Skill 的 R/ 資料夾）
for (f in list.files("C:/Users/Administrator/Desktop/categorical analysis/cda-association-skill/categorical-association/R", pattern = "\\.R$", full.names = TRUE)) source(f)
data <- as.data.frame(read_data("C:/Users/Administrator/Desktop/categorical analysis/cda-association-skill/example_data/student-por.csv"))
spec <- jsonlite::fromJSON("{\"question\":\"住在都市或鄉下，和家裡有沒有網路有關嗎？\",\"structure\":\"independent\",\"types\":{\"address\":\"binary\",\"internet\":\"binary\"},\"method_id\":\"crosstab\",\"reason\":\"兩個不同的二元變數、每一列是不同的學生，用列聯表與卡方檢定\",\"analysis\":\"crosstab\",\"x\":\"address\",\"y\":\"internet\",\"success\":\"yes\",\"design\":\"cross-sectional\",\"levels\":{\"address\":[\"U\",\"R\"],\"internet\":[\"yes\",\"no\"]}}")
if (!is.null(spec$recode)) data <- cda_recode(data, spec$recode)
for (v in names(spec$levels)) data[[v]] <- factor(data[[v]], levels = spec$levels[[v]], ordered = v %in% spec$ordinal)
result <- cda_crosstab(data, x = "address", y = "internet", count = NULL, 
    success = "yes", ordinal = character(0), design = "cross-sectional", 
    conf.level = 0.95)
print(result)
