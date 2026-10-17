# categorical-association

一個 Claude skill，從原始資料一路帶使用者走到**兩個類別變數有沒有關聯**的結論：

**資料總覽 → 問使用者想問什麼 → 依問題畫圖 → 對照注意事項清單判斷適不適合（✅／⚠️／❌），等使用者 OK → R 計算 → 白話解釋並存成報告**

所有數字都由 skill 內的程式計算，Claude 不可以自己算或修改數字。「資料適不適合用這個方法」依據我們整理的**注意事項清單**（`references/checklist.md`）：統計人看到資料時會先停下來想一想的 16 個狀況，其中 9 條是第一版的核心 guardrails。
方法依據 Agresti《An Introduction to Categorical Data Analysis》第 3 版第 1–2 章。
本 skill 是類別資料分析期中報告的 Part 1（關聯分析）；Part 2（類別模型）、Part 3（相關資料）是組員各自的 skill。

> **第一次使用？** 照 [實作教學](實作教學.md) 一步一步在 claude.ai 安裝並實測。

## 涵蓋的方法

| 這個 skill 做 | 不做（會轉介） |
|---|---|
| 列聯表：卡方 X²／G²、標準化殘差、Fisher 精確檢定 | 多個解釋變數、連續解釋變數 → logistic 模型 |
| 2×2 表：比例差、相對風險、勝算比與 score 信賴區間 | 配對、重複測量、叢集資料 → McNemar、GEE、GLMM |
| 二元結果 × 有序解釋變數：Cochran–Armitage 趨勢檢定 | 結果變數是連續數值 |
| 有序 × 有序：linear-by-linear association 檢定 | 二元名目 × 有序的趨勢檢定（需要先確認分析目的） |
| 控制第三個變數（X、Y 二元）：各層勝算比與信賴區間、CMH、同質性檢定、Simpson 悖論 | |

## Repo 內容

| 檔案 | 說明 |
|---|---|
| `categorical-association/` | skill 資料夾（可以直接在網頁上看程式碼） |
| `categorical-association.zip` | skill 打包檔，下載後解壓縮安裝 |
| `make-skill-tutorial.qmd`／`.html` | 製作教學：設計、安裝、上台示範、三層驗證、開發過程 |
| `methods.qmd`／`.html` | 方法比較：比例差、相對風險、勝算比該報哪個，卡方、Fisher 與趨勢檢定的差別 |
| `example_data/` | 示範資料，見下方「示範資料」 |
| `dev/` | 開發紀錄：自動測試、真實資料驗證、AI 使用紀錄 |
| `實作教學.md` | 給第一次使用的人：在 claude.ai 安裝 Skill 並用示範資料實測的步驟 |

### skill 資料夾結構

```
categorical-association/
├── SKILL.md                     總流程：範圍、兩種執行模式、五個階段、輸出用語規則
├── references/
│   ├── checklist.md             注意事項清單：16 條狀況、MVP 9 條 guardrails（階段 3 判斷用）
│   ├── decision-tree.md         依變數型態與資料結構選方法
│   ├── methods.md               各方法速查＋沒有 R 時交給使用者的 R 程式碼
│   └── textbook-methods.md      教科書的公式、節號、警告代碼
├── scripts/
│   ├── profile_data.R / .py     階段 1：資料總覽、判斷變數型態與資料結構
│   ├── describe_question.R / .py 階段 2：依問題畫圖、算判斷要用的數字
│   ├── cda_describe.py          Python 版共用程式（網頁版用）
│   ├── run_analysis.R           階段 4：計算、畫圖、產生報告
│   ├── load_engine.R            載入計算引擎
│   └── install_packages.R       安裝需要的 R 套件
└── R/                           計算引擎（association.R、describe.R、profile.R、plots.R、utils.R）
```

## 安裝（Claude Code，Windows）

需求：R（`Rscript` 要在 PATH 中）與 R 套件。

1. 下載 `categorical-association.zip` 並解壓縮。
2. 安裝 R 套件：

   ```
   Rscript categorical-association/scripts/install_packages.R
   ```

3. 把 `categorical-association` 資料夾複製到 `C:\Users\<使用者名稱>\.claude\skills\`（沒有 `skills` 資料夾就自己建立）。
4. 在 `C:\Users\<使用者名稱>\.claude\settings.json` 的 `permissions.allow` 加入 `"Bash(Rscript *)"` 與 `"PowerShell(Rscript *)"`。
5. 在資料所在的資料夾啟動 Claude Code，輸入 `/categorical-association` 開始使用，或直接用自然語言問。

claude.ai 網頁版：在「設定 → 功能」開啟程式碼執行，再到「Skills」上傳 zip。網頁版沒有 R，skill 會改用**模式 2**：

- 第 1–2 步（總表、圖）用 Python 版自動跑（需要 pandas、matplotlib，網頁版實測都有），輸出和 R 版相同。
- 第 4 步（統計檢定）給你改好欄位名稱的 R 程式碼，你在 RStudio 執行後把輸出貼回去，它再解釋。Python 不做任何統計檢定。

**不要上傳含個人資料的檔案**（姓名、學號、病歷）。

## 輸出檔案

| 檔案 | 內容 |
|---|---|
| `資料總覽_<資料>.md`、`profile.json` | 階段 1：每個變數的次數、比例、缺失、型態猜測；資料結構的提示 |
| `初步檢視_<資料>.md`、`check.json`、`bar_*.png`、`relation.png` | 階段 2：問題用到的變數的長條圖、關係圖、次數表、期望次數 |
| `分析報告_<資料>_<方法>.md` | 完整報告：次數表、檢定、效果量、注意事項、圖，以及 Claude 補在最前面的白話結論 |
| `*.png` | 條件比例圖、殘差圖、趨勢圖或分層勝算比圖 |
| `result.json` | 所有數字（給程式讀） |
| `spec.json` | 這次的判斷紀錄：問題、變數型態、資料結構、方法與理由 |
| `reproduce.R` | 自己重跑這次分析的 R 程式碼 |

## 示範資料

| 檔案 | 內容 | 資料形式 | 對應分析 |
|---|---|---|---|
| `01_crosstab_titanic.csv` | 鐵達尼號 2201 位乘客的艙等、性別、年齡、是否存活（R 內建 `Titanic`） | 原始資料（一人一列） | 列聯表（`crosstab`） |
| `02_trend_housing.csv` | 哥本哈根 1681 戶住戶對管理的影響力 × 居住滿意度（R 套件 MASS 的 `housing`，合併房型與接觸程度） | 長格式＋次數欄（`Freq`） | 趨勢檢定（`trend`） |
| `03_stratified_berkeley.csv` | 1973 年柏克萊研究所 6 個科系、4526 位申請者的性別與錄取結果（R 內建 `UCBAdmissions`） | 長格式＋次數欄（`Freq`） | 分層分析（`stratified`） |
| `04_paired_student_courses.csv` | 358 位葡萄牙高中生的數學與葡萄牙文是否及格，**每人 2 列**（UCI 學生資料） | 原始資料（同一人多列） | **不適合**：資料不獨立，示範 Skill 會偵測並拒絕、轉介 McNemar |

## 試用示範資料

每一份都一樣：把資料放到一個空資料夾，在那裡啟動 Claude Code，輸入問題；skill 停下來確認時照表回答。

| 資料 | 輸入 | 確認時回答 | 預期結果 |
|---|---|---|---|
| `01` | 鐵達尼號上女性的存活率比男性高嗎？ | 每一列是不同的乘客；成功 = 存活（Yes）；用推薦的 | 存活率 73.2% vs 21.2%；X² = 456.87，P < 0.001；比例差 0.52、相對風險 3.45、勝算比 10.15 |
| `02` | 住戶對管理的影響力越大，居住滿意度越高嗎？ | 兩個都是有序（Low < Medium < High）；不是配對，是同一戶回答的兩個不同問題；用推薦的 | Linear-by-linear association 檢定：M² = 101.37（df = 1），P < 0.001；忽略順序的 X² = 106.18（df = 4） |
| `03` | 柏克萊研究所錄取有性別差異嗎？控制科系之後呢？ | 每一列是一群不同的申請者；成功 = 錄取（Admitted）；科系是同時影響申請與錄取的變數，要控制；用推薦的 | 合併看勝算比 1.84（男生較易錄取）；控制科系後共同勝算比 0.90（95% CI 0.77–1.06），CMH 的 P = 0.217；警告：各科系勝算比方向不一致、同質性檢定 P = 0.001，要逐科系報告 |
| `04` | 數學和葡萄牙文的及格率一樣嗎？ | 對，每個學生都有兩列，一列數學、一列葡萄牙文 | 第 1 步就提醒 `student_id` 重複；卡方／Fisher 標 ❌（同一學生的兩次觀察不獨立），建議改用 McNemar 檢定並轉介相關資料的 Skill，不會給出卡方結果 |

示範重點：

- `01` 的第 1 步只會給總表；說出問題後，第 2 步才畫性別與存活的圖。
- `02` 的兩欄類別都是 Low／Medium／High，skill 會懷疑是配對資料而停下來問。這是刻意保留的示範：資料證明不了的事，skill 一定要問人。
- `03` 合併來看男生較易錄取，分科系後差異幾乎消失，是控制變數改變結論的經典例子。
- `04` 看起來是普通的「科目 × 及格」表，但每個學生出現兩次。這是示範「不適合」的案例：skill 要自己發現資料不獨立、停下來問、拒絕做卡方並轉介。

另外也可以用 `01` 試其他問題，例如「艙等和存活有關嗎？」（4×2 表、看標準化殘差），或「控制年齡（大人／小孩）後，性別和存活還有關嗎？」（分層分析）。

## 測試

在 repo 根目錄執行：

```
Rscript dev/tests/download-data.R                # 第一次：下載課本資料（見下方「資料來源」）
Rscript -e "testthat::test_dir('dev/tests')"
```

- `dev/tests/test-association.R`：用教科書的例子（政黨×性別、阿斯匹靈、品茶、飲酒與畸形、死刑判決）檢查每個數字都和課本一致
- `dev/tests/test-association.R` 也檢查注意事項清單的規則：Cochran 準則、0 cell 與空類別、缺失比例、各層方向不一致、小組人數提醒、兩種趨勢檢定的命名與拒絕條件
- `dev/tests/test-skill.R`：資料判斷、recode、階段 1–4 的程式端對端、模式 2 的 R 程式碼和引擎結果一致、不支援的分析會拒絕、上面三份示範資料的預期結果（另用 R 內建函式重算）
- `dev/tests/test-python.R`：Python 版和 R 版在 9 份資料、8 個問題上的總表與檢查數字逐項一致（沒有 Python 時自動略過）

沒有下載課本資料時，用到這些資料的測試會自動略過。

`dev/demo/` 是真實資料的盲測紀錄（葡萄牙高中生資料：人為判斷、skill 的判斷與輸出、獨立驗證程式），`dev/ai-log/log.csv` 是 AI 使用紀錄。重新打包 zip：`Rscript dev/build-zip.R`。

## 資料來源

### 本 repo 收錄的資料

- `example_data/01_crosstab_titanic.csv`：R 內建資料集 `Titanic`（R Core Team, 2026），由次數表展開成一人一列。原始資料：Dawson, R. J. M. (1995). The "unusual episode" data revisited. *Journal of Statistics Education*, 3(3).
- `example_data/02_trend_housing.csv`：R 套件 MASS 的 `housing`（Venables & Ripley, 2002），把房型與接觸程度合併加總。原始資料：Madsen, M. (1976). Statistical analysis of multiple contingency tables. Two examples. *Scandinavian Journal of Statistics*, 3, 97–106.
- `example_data/03_stratified_berkeley.csv`：R 內建資料集 `UCBAdmissions`（R Core Team, 2026），轉成長格式。原始資料：Bickel, P. J., Hammel, E. A., & O'Connell, J. W. (1975). Sex bias in graduate admissions: Data from Berkeley. *Science*, 187(4175), 398–404.
- `example_data/04_paired_student_courses.csv`：Cortez, P. (2008). Student Performance [Dataset]. UCI Machine Learning Repository. <https://doi.org/10.24432/C5TG7T>。授權：[CC BY 4.0](https://creativecommons.org/licenses/by/4.0/)。**修改**：用原作者提供的配對程式找出數學與葡萄牙文兩科都修的學生，只保留能唯一配對的 358 位並編代號 `student_id`；轉成每人 2 列的長格式；新增 `pass`（G3 ≥ 10）；只保留 `student_id`、`course`、`school`、`sex`、`pass` 五欄。
- `dev/demo/student_por.csv`：Cortez, P. (2008). Student Performance [Dataset]. UCI Machine Learning Repository. <https://doi.org/10.24432/C5TG7T>。授權：[CC BY 4.0](https://creativecommons.org/licenses/by/4.0/)。**修改**：由分號分隔改成逗號分隔，並新增 `pass` 欄（G3 ≥ 10 為 pass，否則 fail）；其餘內容未更動。相關論文：Cortez, P., & Silva, A. (2008). Using data mining to predict secondary school student performance. In *Proceedings of 5th Future Business Technology Conference* (pp. 5–12).

### 不收錄、由測試時下載的資料

`dev/tests/data/` 的 5 份檔案（`Political.dat`、`DeathPenalty.dat`、`Abortion.dat`、`Envir_opinions.dat`、`Crabs.dat`）是 Agresti (2019) 書中的資料，由作者公開在 <https://github.com/alanagresti/categorical-data>（連結自 <https://www.alanagresti.com/>）。該處沒有說明是否可以重新散布，所以本 repo **不收錄這些檔案**，由 `dev/tests/download-data.R` 從作者的網站下載。各資料的原始來源見書中對應的表。

### 測試程式中引用的課本小表格

`dev/tests/` 直接寫入了幾張課本例子的次數（各 4–10 個數字），用來核對計算結果與課本一致：

- 阿斯匹靈與心肌梗塞（Agresti, 2019, Table 2.2）：Steering Committee of the Physicians' Health Study Research Group (1989). Final report on the aspirin component of the ongoing Physicians' Health Study. *New England Journal of Medicine*, 321, 129–135.
- 吸菸與肺癌的 case-control 研究（Agresti, 2019, §2.3.5）：Doll, R., & Hill, A. B. (1950). Smoking and carcinoma of the lung. *British Medical Journal*, 2(4682), 739–748.
- 品茶實驗（Agresti, 2019, Table 2.7）：Fisher, R. A. (1935). *The Design of Experiments*. Oliver & Boyd.
- 孕期飲酒與畸形（Agresti, 2019, Table 2.6）：Graubard, B. I., & Korn, E. L. (1987). Choice of column scores for testing independence in ordered 2 × K contingency tables. *Biometrics*, 43, 471–476.

`methods.qmd` 的例子（宵夜、通勤、手搖飲、滑手機、補習班）都是我們自己編的假想資料。

## 使用的軟體

- R Core Team (2026). *R: A language and environment for statistical computing*. R Foundation for Statistical Computing. <https://www.R-project.org/>
- R 套件：ggplot2（Wickham, 2016）、jsonlite（Ooms, 2014）、readr、readxl、scales（Wickham et al.）、PropCIs（Scherer）、MASS（Venables & Ripley, 2002）、testthat（Wickham, 2011）、yaml；方法頁另用 epitools（Aragon）計算延伸說明中的 mid-P
- Python 套件：pandas（The pandas development team）、matplotlib（Hunter, 2007）
- Quarto（Allaire et al.）：產生 `methods.html` 與 `make-skill-tutorial.html`
- 開發過程使用 Claude Code（Anthropic）輔助，紀錄見 `dev/ai-log/log.csv`

## 參考文獻

Agresti, A. (2019). *An Introduction to Categorical Data Analysis* (3rd ed.). Wiley.

Hunter, J. D. (2007). Matplotlib: A 2D graphics environment. *Computing in Science & Engineering*, 9(3), 90–95.

Ooms, J. (2014). The jsonlite package: A practical and consistent mapping between JSON data and R objects. arXiv:1403.2805.

Venables, W. N., & Ripley, B. D. (2002). *Modern Applied Statistics with S* (4th ed.). Springer.

Wickham, H. (2011). testthat: Get started with testing. *The R Journal*, 3(1), 5–10.

Wickham, H. (2016). *ggplot2: Elegant Graphics for Data Analysis*. Springer.
