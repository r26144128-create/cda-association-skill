# 重現這次分析的 R 程式碼（需要本 Skill 的 R/ 資料夾）
for (f in list.files("C:/Users/Administrator/Desktop/categorical analysis/cda-association-skill/categorical-association/R", pattern = "\\.R$", full.names = TRUE)) source(f)
data <- as.data.frame(read_data("C:/Users/Administrator/Desktop/categorical analysis/cda-association-skill/example_data/01_crosstab_titanic.csv"))
spec <- jsonlite::fromJSON("{\"question\":\"鐵達尼號上女性的存活率比男性高嗎？\",\"structure\":\"independent\",\"types\":{\"Sex\":\"binary\",\"Survived\":\"binary\"},\"method_id\":\"crosstab\",\"reason\":\"兩個二元變數、每一列是不同的乘客，用列聯表與卡方檢定\",\"analysis\":\"crosstab\",\"x\":\"Sex\",\"y\":\"Survived\",\"success\":\"Yes\",\"design\":\"cross-sectional\",\"levels\":{\"Sex\":[\"Female\",\"Male\"],\"Survived\":[\"Yes\",\"No\"]}}")
if (!is.null(spec$recode)) data <- cda_recode(data, spec$recode)
for (v in names(spec$levels)) data[[v]] <- factor(data[[v]], levels = spec$levels[[v]], ordered = v %in% spec$ordinal)
result <- cda_crosstab(data, x = "Sex", y = "Survived", count = NULL, success = "Yes", 
    ordinal = character(0), design = "cross-sectional", conf.level = 0.95)
print(result)
