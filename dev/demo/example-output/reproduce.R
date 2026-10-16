# 重現這次分析的 R 程式碼（需要本 Skill 的 R/ 資料夾）
for (f in list.files("C:/Users/Administrator/Desktop/categorical analysis/cda-association-skill/categorical-association/R", pattern = "\\.R$", full.names = TRUE)) source(f)
data <- as.data.frame(read_data("C:/Users/Administrator/Desktop/categorical analysis/cda-association-skill/example_data/02_trend_housing.csv"))
spec <- jsonlite::fromJSON("{\"question\":\"住戶對管理的影響力越大，居住滿意度越高嗎？\",\"structure\":\"independent\",\"types\":{\"Infl\":\"ordinal\",\"Sat\":\"ordinal\"},\"method_id\":\"trend\",\"reason\":\"兩個有序變數，用 linear-by-linear association 檢定（§2.5.1）\",\"analysis\":\"trend\",\"x\":\"Infl\",\"y\":\"Sat\",\"count\":\"Freq\",\"ordinal\":[\"Infl\",\"Sat\"],\"design\":\"cross-sectional\",\"levels\":{\"Infl\":[\"Low\",\"Medium\",\"High\"],\"Sat\":[\"Low\",\"Medium\",\"High\"]}}")
if (!is.null(spec$recode)) data <- cda_recode(data, spec$recode)
for (v in names(spec$levels)) data[[v]] <- factor(data[[v]], levels = spec$levels[[v]], ordered = v %in% spec$ordinal)
result <- cda_trend(data, x = "Infl", y = "Sat", count = "Freq", ordinal = c("Infl", 
"Sat"), x_scores = NULL, y_scores = NULL, success = NULL)
print(result)
