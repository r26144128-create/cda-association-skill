# 方法速查（含模式 2 的 R 程式碼）

每個方法：什麼時候用、假設、會得到什麼、R 程式碼。**模式 2（沒有 R 可以執行）**時，把程式碼的 `df`、欄位名稱換成使用者的，交給使用者自己執行，請他貼回輸出。判斷適不適合用哪個方法，依 `checklist.md`。

所有程式碼開頭都先讀資料，並報告缺失：

```r
df <- read.csv("資料檔.csv", fileEncoding = "UTF-8")   # Excel 檔：df <- readxl::read_excel("資料檔.xlsx")
miss <- !complete.cases(df[c("X", "Y")])           # 有控制變數時加上 "Z"
c(排除筆數 = sum(miss), 比例 = mean(miss))          # 有缺失一律報告；≥ 5% 要提醒（checklist 第 5 條）
df <- df[!miss, ]
# 已彙整的次數資料（每格一列，有 count 欄）：
# tab <- xtabs(count ~ X + Y, data = df)
tab <- table(df$X, df$Y)            # 列 = 解釋變數 X，欄 = 結果變數 Y
tab                                 # 一定先看原始次數
```

---

## 1. 列聯表與卡方檢定（`crosstab`）

- **用途**：兩個類別變數有沒有關聯；哪些格子比「無關聯」時預期的多或少。
- **假設**：每一列獨立。
- **得到**：X²、G²、df = (I−1)(J−1)、P 值；標準化殘差（|r| > 2 表示該格明顯偏離）。
- **期望次數（Cochran 準則）**：2×2 表有任何一格 < 5，或更大的表有任何一格 < 1、或超過 20% 的格子 < 5 時，Pearson 卡方的大樣本近似可能不可靠，改以 Fisher 精確檢定為主（第 3 節）。

```r
prop.table(tab, 1)                  # 各組（列）的條件比例
ct <- chisq.test(tab, correct = FALSE)
ct                                  # Pearson X²
ct$expected                         # 期望次數
c(最小 = min(ct$expected), 小於5的比例 = mean(ct$expected < 5))
ct$stdres                           # 標準化殘差
G2 <- 2 * sum(tab * log(tab / ct$expected), na.rm = TRUE)
c(G2 = G2, p = pchisq(G2, ct$parameter, lower.tail = FALSE))
```

## 2. 2×2 表的效果量

- **用途**：兩組在「成功」比例上差多少。
- **得到**：比例差、相對風險、勝算比與 95% score 信賴區間。
- **注意**：
  - case-control 只能用勝算比，不報比例差與相對風險。
  - 勝算比是「勝算」的倍數，不是機率的倍數；只有比例很小時才接近相對風險。
  - 有 0 次數的格子時：不用 Wald 信賴區間、不加 0.5 修正；下面的 score 區間仍可用，並一定要呈現原始次數。

```r
# 把「成功」放在第 1 欄、第 1 組放在第 1 列
n1 <- sum(tab[1, ]); n2 <- sum(tab[2, ])
y1 <- tab[1, 1];     y2 <- tab[2, 1]
PropCIs::diffscoreci(y1, n1, y2, n2, conf.level = 0.95)    # 比例差（score 區間）
PropCIs::riskscoreci(y1, n1, y2, n2, conf.level = 0.95)    # 相對風險
PropCIs::orscoreci(y1, n1, y2, n2, conf.level = 0.95)      # 勝算比
```

## 3. Fisher 精確檢定（期望次數太小）

- **用途**：依第 1 節的 Cochran 準則，卡方近似可能不可靠時。
- **注意**：第一版只報 Fisher 精確檢定的 P 值，不另外報 mid-P。

```r
fisher.test(tab)                                   # 雙尾
# 大表算不出來時，改用模擬的 P 值（並說明是模擬的）：
# fisher.test(tab, simulate.p.value = TRUE, B = 1e5)
```

## 4. 趨勢檢定（`trend`）：兩種情況，名稱不可混用

兩種都用 M² = (n − 1)R²（df = 1），但名稱不同：

| 情況 | 名稱 |
|---|---|
| Y 為二元結果、X 為使用者確認的有序變數 | **Cochran–Armitage 趨勢檢定** |
| X 與 Y 都經使用者確認有自然順序 | **Linear-by-linear association 檢定** |
| X 為二元名目（例如性別）、Y 為有序 | 第一版**不支援**，需要確認分析目的；可先用第 1 節看有沒有關聯 |

- **假設**：每一列獨立；類別分數要依順序遞增。數字代碼（1、2、3、4）不代表有順序，一定要使用者確認。
- **注意**：
  - 類別間距不相等時（例如每天 0、<1、1–2、3–5 小時），請使用者確認分數（例如區間中點），並提醒結論可能隨分數改變。
  - 只抓**線性**趨勢；一律和忽略順序的卡方（第 1 節）對照。

### 4a. Cochran–Armitage 趨勢檢定（Y 二元 × X 有序）

```r
x_scores <- c(1, 2, 3, 4)          # X 各類的分數（依順序）
u <- x_scores[as.integer(factor(df$X, levels = c("1", "2", "3", "4")))]
v <- as.numeric(df$Y == "成功的類別")   # Y：成功 = 1，其他 = 0
R  <- cor(u, v); n <- length(u)
M2 <- (n - 1) * R^2
c(R = R, M2 = M2, p = pchisq(M2, 1, lower.tail = FALSE))
```

### 4b. Linear-by-linear association 檢定（有序 × 有序）

```r
x_scores <- c(1, 2, 3)             # X 各類的分數（依順序）
y_scores <- c(1, 2, 3)             # Y 各類的分數（依順序）
u <- x_scores[as.integer(factor(df$X, levels = c("低", "中", "高")))]
v <- y_scores[as.integer(factor(df$Y, levels = c("低", "中", "高")))]
R  <- cor(u, v); n <- length(u)
M2 <- (n - 1) * R^2
c(R = R, M2 = M2, p = pchisq(M2, 1, lower.tail = FALSE))
```

## 5. 控制第三個變數（`stratified`，分層分析與 CMH）

- **用途**：控制 Z 之後，X 和 Y 還有關聯嗎？會不會出現 Simpson 悖論？
- **先問使用者**：Z 是干擾變數（同時影響 X 和 Y）才分層；中介變數（X 造成的結果）不要控制。
- **第一版範圍**：X、Y 二元，Z 是類別的分層變數。Z 是連續或要控制多個變數時，轉介類別模型 Skill。
- **得到**：各層勝算比與信賴區間、合併勝算比、共同勝算比、CMH 檢定、同質性檢定。
- **注意**：
  - 不論同質性檢定是否顯著，都要列出各層勝算比、信賴區間與方向。
  - 方向相反（有的 > 1、有的 < 1）或同質性檢定顯著時，要逐層報告，不能只報共同勝算比。
  - 同質性檢定只是輔助：P > 0.05 不代表共同勝算比一定適合。

```r
tab3 <- table(df$X, df$Y, df$Z)                # 2 × 2 × K，「成功」放在 Y 的第 1 類
for (k in dimnames(tab3)[[3]]) {               # 各層勝算比與 score 信賴區間
  t <- tab3[, , k]
  print(k); print(PropCIs::orscoreci(t[1, 1], sum(t[1, ]), t[2, 1], sum(t[2, ]), conf.level = 0.95))
}
m <- margin.table(tab3, c(1, 2)); (m[1,1] * m[2,2]) / (m[1,2] * m[2,1])  # 合併勝算比
mantelhaen.test(tab3, correct = FALSE)         # CMH 檢定
# 同質性（各層勝算比是否相同）：logistic 模型的交互作用檢定
fit0 <- glm(Y == "成功" ~ X + Z, family = binomial, data = df)
fit1 <- glm(Y == "成功" ~ X * Z, family = binomial, data = df)
anova(fit0, fit1, test = "LRT")
```

---

## 判讀速記（用語依 checklist 第 14–16 條）

| 看到 | 要這樣說 |
|---|---|
| P < 0.05 | 有證據顯示有關聯（不代表關聯強），並用效果量和信賴區間說明大小 |
| P ≥ 0.05 | 證據不足，無法確定有關聯（不是「沒有關係」） |
| 標準化殘差 > 2 / < −2 | 這一格比無關聯時預期的多 / 少 |
| 勝算比信賴區間包含 1 | 看不出兩組勝算不同 |
| 比例差信賴區間包含 0 | 看不出兩組比例不同 |
| 勝算比 = 2 | 勝算是 2 倍（不是機率 2 倍） |
| 各層勝算比都和合併勝算比方向相反 | Simpson 悖論：以控制後（各層）的結果為準 |
| M² 顯著但 X² 不顯著 | 有線性趨勢，只是被卡方的大自由度稀釋了 |
