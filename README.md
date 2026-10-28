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
│   ├── methods.md               各方法速查＋可以自己執行的 R 程式碼
│   └── textbook-methods.md      教科書的公式、節號、警告代碼
├── scripts/
│   ├── profile_data.R / .py     階段 1：資料總覽、判斷變數型態與資料結構
│   ├── describe_question.R / .py 階段 2：依問題畫圖、算判斷要用的數字
│   ├── run_analysis.R / .py     階段 4：計算、畫圖、產生報告
│   ├── cda_describe.py          Python 版：讀資料、總表、畫圖（網頁版用）
│   ├── cda_engine.py            Python 版的計算引擎（網頁版用，對照 R/association.R 改寫）
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

- 全部步驟都改用 Python 版程式自動執行（需要 pandas、matplotlib、scipy），不需要 R，也不用 RStudio。
- Python 版是 R 版逐行對照改寫的；自動測試逐項比對兩邊的數字、結論句、警告與報告檔，結果相同。

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
| `reproduce.R`（網頁版為 `reproduce.py`） | 自己重跑這次分析的程式碼 |

## 示範資料

`example_data/student-por.csv`：UCI 公開的葡萄牙高中生資料（葡萄牙文課）：649 位學生、一人一列、33 欄、分號分隔（見「資料來源」）。示範會用到的欄位：

| 欄位 | 內容 |
|---|---|
| `address` | 住在都市（U）或鄉下（R） |
| `internet` | 家裡有沒有網路（yes、no） |
| `Dalc`、`Walc` | 平日、週末的喝酒程度（1 很少 – 5 很多） |
| `paid` | 有沒有上付費補習（yes、no） |
| `higher` | 想不想讀大學（yes、no） |
| `studytime` | 每週讀書時間（1 少於 2 小時、2 為 2–5 小時、3 為 5–10 小時、4 超過 10 小時） |

其他欄位的意思見 UCI 網站的資料說明。同一份資料可以問「能做」和「不能做」的問題：`Dalc` 和 `Walc` 是同一個學生的兩個回答，比較兩者是配對資料，不能用卡方。

## 試用示範資料

開一個新對話，上傳 `student-por.csv`，輸入「請用 categorical-association 分析這份資料」，再照下表回答；每一題開一個新對話。`make-skill-tutorial.html` 的「跟著做」有同樣的文字，可以直接複製。

| 問題 | 確認時回答 | 預期結果 |
|---|---|---|
| ✅ 住在都市或鄉下，和家裡有沒有網路有關嗎？ | 每一列是不同的學生；這題用不到 Mjob、Fjob；成功 = yes（有網路）；用推薦的 | 有網路的比例：都市 81.6%、鄉下 65.5%；X² = 20.06，P < 0.001；比例差 0.16、相對風險 1.25、勝算比 2.34 |
| ❌ 學生平日和週末的喝酒程度一樣嗎？ | 對，Dalc 和 Walc 是同一個學生回答的平日和週末喝酒程度 | 卡方標 ❌（同一個學生的兩個回答不獨立），說明是配對資料、要用配對資料的方法，不會給出卡方結果 |
| ⚠️ 有沒有上付費補習，和想不想讀大學有關嗎？ | 每一列是不同的學生；成功 = yes（想讀大學）；用推薦的 | 有補習的只有 39 人，最小期望次數 4.15，依 Cochran 準則提醒卡方可能不可靠，以 Fisher 精確檢定為主：P = 0.788，證據不足 |
| 每週讀書時間越長，越想讀大學嗎？ | studytime 是有序的：1 < 2 < 3 < 4（數字越大讀越久）；每一列是不同的學生；成功 = yes；用推薦的 | Cochran–Armitage 趨勢檢定 M² = 22.97（df = 1），P < 0.001；對照忽略順序的 X² = 34.30（df = 3） |

示範重點：

- 第 1 步只會給總表；說出問題後，第 2 步才畫相關變數的圖。
- 第 1 步會問 `Mjob`、`Fjob`（媽媽、爸爸的工作）是不是同一個人的兩次回答：選項相同，資料證明不了，所以要問人。
- `studytime` 是數字代碼，skill 不會自動當成有序，一定先問使用者。
- 同一份資料，問題不同，判斷就不同：skill 看的是問題用到哪些欄位、這些欄位之間是什麼關係。

## 測試

在 repo 根目錄執行：

```
Rscript dev/tests/download-data.R                # 第一次：下載課本資料（見下方「資料來源」）
Rscript -e "testthat::test_dir('dev/tests')"
```

- `dev/tests/test-association.R`：用教科書的例子（政黨×性別、阿斯匹靈、品茶、飲酒與畸形、死刑判決）檢查每個數字都和課本一致
- `dev/tests/test-association.R` 也檢查注意事項清單的規則：Cochran 準則、0 cell 與空類別、缺失比例、各層方向不一致、小組人數提醒、兩種趨勢檢定的命名與拒絕條件
- `dev/tests/test-skill.R`：資料判斷、recode、階段 1–4 的程式端對端、模式 2 的 R 程式碼和引擎結果一致、不支援的分析會拒絕、示範資料的預期結果（`Mjob`／`Fjob` 要被偵測為可能的配對資料），以及用 R 內建資料（`Titanic`、`UCBAdmissions`、MASS 的 `housing`）測次數表、趨勢與分層分析（另用 R 內建函式重算）
- `dev/tests/test-python.R`：Python 版和 R 版逐項比對：第 1–2 步的總表與檢查數字（11 份資料、9 個問題），以及第 4 步 16 個分析案例的 `result.json` 與報告檔（沒有 Python 時自動略過）

沒有下載課本資料時，用到這些資料的測試會自動略過。

`dev/demo/` 是真實資料的盲測紀錄（葡萄牙高中生資料：人為判斷、skill 的判斷與輸出、獨立驗證程式），`dev/ai-log/log.csv` 是 AI 使用紀錄。重新打包 zip：`Rscript dev/build-zip.R`。

## 資料來源

### 本 repo 收錄的資料

- `example_data/student-por.csv`：Cortez, P. (2008). Student Performance [Dataset]. UCI Machine Learning Repository. <https://doi.org/10.24432/C5TG7T>。授權：[CC BY 4.0](https://creativecommons.org/licenses/by/4.0/)。UCI 的 `student-por.csv`。

### 測試用的 R 內建資料（不另存檔案）

測試程式在執行時由 R 產生，不放在 repo 裡：

- `Titanic`（R Core Team, 2026）。原始資料：Dawson, R. J. M. (1995). The "unusual episode" data revisited. *Journal of Statistics Education*, 3(3).
- `UCBAdmissions`（R Core Team, 2026）。原始資料：Bickel, P. J., Hammel, E. A., & O'Connell, J. W. (1975). Sex bias in graduate admissions: Data from Berkeley. *Science*, 187(4175), 398–404.
- MASS 套件的 `housing`（Venables & Ripley, 2002），把房型與接觸程度合併加總。原始資料：Madsen, M. (1976). Statistical analysis of multiple contingency tables. Two examples. *Scandinavian Journal of Statistics*, 3, 97–106.

### 其他收錄的資料

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
- Python 套件：pandas（The pandas development team）、matplotlib（Hunter, 2007）、NumPy（Harris et al., 2020）、SciPy（Virtanen et al., 2020）
- Quarto（Allaire et al.）：產生 `methods.html` 與 `make-skill-tutorial.html`
- 開發過程使用 Claude Code（Anthropic）輔助，紀錄見 `dev/ai-log/log.csv`

## 參考文獻

Agresti, A. (2019). *An Introduction to Categorical Data Analysis* (3rd ed.). Wiley.

Harris, C. R., Millman, K. J., van der Walt, S. J., et al. (2020). Array programming with NumPy. *Nature*, 585, 357–362.

Hunter, J. D. (2007). Matplotlib: A 2D graphics environment. *Computing in Science & Engineering*, 9(3), 90–95.

Ooms, J. (2014). The jsonlite package: A practical and consistent mapping between JSON data and R objects. arXiv:1403.2805.

Venables, W. N., & Ripley, B. D. (2002). *Modern Applied Statistics with S* (4th ed.). Springer.

Virtanen, P., Gommers, R., Oliphant, T. E., et al. (2020). SciPy 1.0: Fundamental algorithms for scientific computing in Python. *Nature Methods*, 17, 261–272.

Wickham, H. (2011). testthat: Get started with testing. *The R Journal*, 3(1), 5–10.

Wickham, H. (2016). *ggplot2: Elegant Graphics for Data Analysis*. Springer.
