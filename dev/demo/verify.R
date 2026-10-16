# Part 1：獨立驗證計算
#
# 用來核對 Skill 在真實資料上的數字。刻意「不使用」Skill 的 R/ 資料夾的任何函式，
# 只用 R 內建函式與課本（Agresti, 2019）示範的指令，走和 Skill 不同的程式路徑。
#
# 執行（在專案根目錄）：Rscript dev/demo/verify.R
# 輸出：dev/demo/verify_results.json

d <- read.csv("dev/demo/student_por.csv")
d$romantic <- factor(d$romantic, levels = c("yes", "no"))   # 第一列：有交往
d$pass <- factor(d$pass, levels = c("pass", "fail"))        # 第一欄：及格
d$school <- factor(d$school, levels = c("GP", "MS"))
out <- list()

# ---- q1：交往 × 及格（2×2 表；課本 §2.2–2.4、§2.6 的 R 指令）----
tab1 <- table(d$romantic, d$pass)
chi1 <- chisq.test(tab1, correct = FALSE)                   # §2.4.5
x1 <- tab1["yes", "pass"]; n1 <- sum(tab1["yes", ])
x2 <- tab1["no", "pass"];  n2 <- sum(tab1["no", ])
or1 <- (tab1["yes", "pass"] * tab1["no", "fail"]) / (tab1["yes", "fail"] * tab1["no", "pass"])
out$q1 <- list(
  n = sum(tab1),
  p_romantic_yes = x1 / n1, p_romantic_no = x2 / n2,
  X2 = unname(chi1$statistic), X2_p = chi1$p.value,
  fisher_p = fisher.test(tab1)$p.value,                      # §2.6
  diff = x1 / n1 - x2 / n2,
  diff_ci = as.numeric(PropCIs::diffscoreci(x1, n1, x2, n2, 0.95)$conf.int),   # §2.2.4
  rr = (x1 / n1) / (x2 / n2),
  rr_ci = as.numeric(PropCIs::riskscoreci(x1, n1, x2, n2, 0.95)$conf.int),     # §2.2.4
  or = or1,
  or_ci = as.numeric(PropCIs::orscoreci(x1, n1, x2, n2, 0.95)$conf.int),       # §2.3.3
  min_expected = min(chi1$expected))

# ---- q2：讀書時間（有序 1–4）× 及格（課本 §2.5.2 的 CMHtest 指令）----
# 分數：組長在 Skill 詢問時選擇各類讀書時數的中點（<2、2–5、5–10、>10 小時 → 1, 3.5, 7.5, 12），
# 並以等距分數 1–4 做敏感度對照（§2.5.4）。
tab2 <- table(d$studytime, d$pass)
m2_mid <- vcdExtra::CMHtest(tab2, rscores = c(1, 3.5, 7.5, 12))$table["cor", ]  # 「Nonzero correlation」列即 M²
m2 <- vcdExtra::CMHtest(tab2, rscores = 1:4)$table["cor", ]
out$q2 <- list(
  n = sum(tab2),
  pass_rate_by_studytime = as.numeric(prop.table(tab2, 1)[, "pass"]),
  M2_mid = unname(m2_mid["Chisq"]), M2_mid_p = unname(m2_mid["Prob"]),
  M2 = unname(m2["Chisq"]), M2_p = unname(m2["Prob"]),
  X2 = unname(chisq.test(tab2, correct = FALSE)$statistic))

# ---- q3：交往 × 及格，控制學校（§2.7；§4.3.4 的 logistic 模型與 CMH）----
# 用「每位學生一列」的資料配適 logistic 模型（Skill 用的是彙整後的次數表，路徑不同）
fit <- glm(I(pass == "pass") ~ romantic + school, family = binomial, data = d)
fit0 <- glm(I(pass == "pass") ~ school, family = binomial, data = d)
tab3 <- table(d$romantic, d$pass, d$school)
cond_or <- apply(tab3, 3, function(t) (t[1, 1] * t[2, 2]) / (t[1, 2] * t[2, 1]))
marg <- apply(tab3, c(1, 2), sum)
out$q3 <- list(
  conditional_or = as.numeric(cond_or),                      # GP、MS
  marginal_or = (marg[1, 1] * marg[2, 2]) / (marg[1, 2] * marg[2, 1]),
  common_or = exp(-coef(fit)[["romanticno"]]),               # 有交往相對於沒交往
  LR = fit0$deviance - fit$deviance,
  LR_p = pchisq(fit0$deviance - fit$deviance, 1, lower.tail = FALSE),
  CMH = unname(mantelhaen.test(tab3, correct = FALSE)$statistic),
  CMH_p = mantelhaen.test(tab3, correct = FALSE)$p.value)

jsonlite::write_json(out, "dev/demo/verify_results.json", auto_unbox = TRUE, digits = NA, pretty = TRUE)
str(out, give.attr = FALSE)
