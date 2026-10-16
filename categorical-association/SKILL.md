---
name: categorical-association
description: 分析兩個類別變數之間有沒有關聯（列聯表、卡方檢定、Fisher 精確檢定、比例差／相對風險／勝算比、有序變數的 Cochran–Armitage 趨勢檢定與 linear-by-linear association 檢定、控制第三個變數的分層分析與 CMH 檢定、Simpson 悖論）。使用者提供 CSV/Excel 資料檔或一張次數表，並問「A 和 B 有沒有關係」「哪一組比例比較高」「控制 C 之後還有關係嗎」時使用。依據 Agresti《An Introduction to Categorical Data Analysis》第 3 版第 1–2 章。
---

# 類別變數關聯分析 Skill（categorical-association）

使用者給你一份資料。你負責：**資料總覽 → 問使用者想問什麼 → 依問題畫圖 → 判斷資料適不適合、等使用者 OK → 呼叫 R 計算 → 用白話解釋並存成報告檔**。

## 三條不能違反的規則

1. **所有數字都由 R 計算。** 你不能自己算、估計或修改任何統計量；解釋只能用 R 輸出的數字。
2. **變數型態與資料結構一定要和使用者確認。** 數字代碼分不出有序或名目（§1.1.2）；資料本身也無法證明每一列彼此獨立（§1.1.3）。
3. **先判斷適不適合、再停下來等使用者 OK。** 使用者沒有同意之前，不要執行分析。

以下路徑都相對於本 Skill 資料夾（`SKILL.md` 所在的資料夾）。

## 這個 Skill 不做什麼（遇到就轉介）

| 情況 | 為什麼不在這裡做 | 建議 |
|---|---|---|
| 要同時看 **多個解釋變數**、或解釋變數是**連續**的（年齡、分數） | 這是迴歸模型的問題 | 改用 logistic／多類別 logit 模型（組員的「類別模型」Skill） |
| 同一個人被測量兩次以上、**配對**、**重複測量**、學生在學校內等**叢集**資料 | 卡方檢定假設每一列獨立，不獨立時 P 值會錯 | 改用 McNemar、GEE、GLMM（組員的「相關資料」Skill） |
| **結果變數本身是連續數值**（成績幾分、身高） | 不是類別資料分析 | 說明原因；若使用者其實關心類別（例如及格與否），可用 `recode` 改成類別後再分析 |

轉介時要說明理由，**不要改用不適合的方法湊出數字**。

## 兩種執行模式

先檢查能不能執行 R：`Rscript --version`。

| | 模式 1：有 R | 模式 2：沒有 R |
|---|---|---|
| 環境 | Claude Code、本機 | claude.ai 網頁版，或 `Rscript` 不能用 |
| 階段 1–2（總表、圖） | `Rscript scripts/profile_data.R`、`Rscript scripts/describe_question.R` | `python scripts/profile_data.py`、`python scripts/describe_question.py`（參數與輸出檔都和 R 版相同） |
| 階段 3（判斷） | 照常 | 照常 |
| 階段 4（分析） | `Rscript scripts/run_analysis.R` | 把 `references/methods.md` 裡對應方法的 **R 程式碼**依使用者的欄位名稱改好，交給使用者在 R／RStudio 執行，請他把輸出貼回來 |
| 階段 5（解釋） | 依 `result.json` | 依使用者貼回的輸出 |

模式 2 的規則：

- Python 版只做敘述統計與畫圖，數字和 R 版相同（有自動測試比對）。**不可以用 Python（或 scipy、statsmodels）做任何統計檢定或估計**，檢定一律由使用者執行 R 程式碼。
- 使用者沒貼回輸出之前，只能說明「會看到什麼、怎麼判讀」，不可以自己算數字。
- 連 Python（pandas、matplotlib）都不能用時，請使用者改在有 R 的環境使用本 Skill。
- 執行環境沒有中文字型時，Python 版的圖會改用英文座標軸標題。

需要的 R 套件：`jsonlite readr readxl ggplot2 scales PropCIs`（`Rscript scripts/install_packages.R` 可一次安裝）。Python 版需要 `pandas`、`matplotlib`。

## 流程總覽

| 階段 | 做什麼 | 停下來？ |
|---|---|---|
| 1 資料總覽 | 敘述統計總表（不畫圖） | 停：問使用者想問什麼 |
| 2 依問題畫圖 | 相關變數的長條圖、關係圖、次數表 | 不停，直接進階段 3 |
| 3 判斷適不適合 | 依注意事項清單標示 ✅／⚠️／❌，推薦方法 | 停：等使用者 OK |
| 4 執行分析 | R 計算、畫圖、產生報告 | |
| 5 解釋結果 | 固定段落，補進報告檔 | |

## 階段 1：資料總覽

```
Rscript scripts/profile_data.R <資料檔> <輸出資料夾>
```

產生 `資料總覽_<資料>.md`（給使用者看）和 `profile.json`（給你讀）。

1. 把總覽表給使用者看：資料結構（幾列幾欄、一列一個觀察值還是已彙整的次數表）、每個變數的型態猜測、缺失數、各類別次數與比例。**這個階段不畫圖。**
2. 用一兩句話指出值得注意的地方，例如需要確認的欄位或缺失很多的變數，但先不要判斷方法。
3. 問：「你想用這份資料回答什麼問題？」

**然後停止，等使用者回覆。** 如果使用者一開始就帶著問題來，仍然先給總覽，接著直接進行階段 2，不用再問一次。

`profile.json` 欄位：

- `variables[].type_guess`：`binary`、`nominal`、`ordinal_candidate`（可能有序）、`ordinal_or_nominal_code`（數字代碼，必須問）、`continuous`、`count_or_continuous`、`frequency_weight`（次數欄）、`id`
- `structure.hints`：可能不獨立的跡象（`repeated_measures`、`clustered`、`possible_matched_pairs_wide`），以及已彙整的次數資料（`aggregated_counts`）；每個都附有 `question` 可以直接問使用者

使用者只給一張次數表（沒有檔案）時，把它寫成長格式 CSV（每格一列＋次數欄 `count`），再照常執行。

## 階段 2：依問題畫圖

依使用者的問題決定 X（解釋變數）、Y（結果變數），以及要控制的 Z（如果有），寫 `question.json`：

```json
{"x": "Sex", "y": "Survived", "z": null, "count": null,
 "levels": {"Survived": ["Yes", "No"]}, "recode": null}
```

```
Rscript scripts/describe_question.R <資料檔> question.json <輸出資料夾>
```

產生每個變數的長條圖（`bar_<變數>.png`）、X 與 Y 的關係圖（`relation.png`，有 Z 時依 Z 分面）、`初步檢視_<資料>.md`（次數表與重點數字），以及 `check.json`（階段 3 判斷要用的數字）。把圖和次數表給使用者看。

問題超出本 Skill 範圍時（見上方「不做什麼」），不用畫圖，直接說明並轉介。

## 階段 3：判斷適不適合，然後停下來

依 `references/checklist.md` 的注意事項，對照 `check.json` 和 `profile.json` 的數字，用**一則訊息**完成：

1. 一句話重述使用者的問題。
2. 需要使用者確認的判斷：
   - 每個變數的型態（二元／名目／有序）與有序變數的**類別順序**；`needs_confirmation: true` 的變數一定要問
   - 資料結構：有 `structure.hints` 時問其中的 `question`；沒有時也要問「每一列是不是不同、彼此無關的個體？」
   - 研究設計：橫斷調查、追蹤（cohort）、實驗，或 case-control
   - 2×2 表的比例要針對 Y 的哪一個類別（「成功」）
3. **適用性判斷**：依 `references/decision-tree.md` 列出 1–3 個候選方法，每個標示：
   - ✅ **適合**
   - ⚠️ **可以做，但有問題**：說明是什麼問題（附 `check.json` 的數字），以及要用的方法
   - ❌ **不適合**：說明原因，建議其他方法或轉介
   並標出你的推薦。
4. 結尾：「請確認上面的判斷，並選擇要用的方法（或回覆『用推薦的』）。」

**然後停止，等使用者回覆。**

兩種常見情況：

- **使用者指定了不適合的方法**（例如資料是配對卻要求卡方、名目變數卻要求趨勢檢定）：標示 ❌，不要照做；說明為什麼不適合、應該用什麼，問是否改用。
- **需要資料裡沒有的類別變數**（例如只有分數、要問及格與否；或想把 1–5 合併成兩類）：在 `question.json` 和 spec 加 `recode`（見階段 4），**只在使用者要求或同意時使用**，並確認門檻；提醒切分或合併會損失資訊。

## 階段 4：執行分析

使用者確認後，寫 `spec.json`：

```json
{
  "question": "有參加社團的人比較常熬夜嗎？",
  "structure": "independent",
  "types": {"社團": "binary", "熬夜": "binary"},
  "method_id": "crosstab",
  "reason": "兩個二元變數、資料獨立，用列聯表與卡方檢定（§2.4）",
  "analysis": "crosstab",
  "x": "社團", "y": "熬夜",
  "count": null, "success": "會", "ordinal": [], "design": "cross-sectional",
  "levels": {"社團": ["有參加", "沒參加"], "熬夜": ["會", "不會"]},
  "conf_level": 0.95
}
```

| `analysis` | 方法 | 額外欄位 |
|---|---|---|
| `crosstab` | 列聯表：卡方 X²／G²、標準化殘差、Fisher 精確檢定、比例差／相對風險／勝算比與信賴區間（§2.1–2.4、§2.6） | `design` |
| `trend` | 兩種情況，名稱不可混用：Y 二元 × X 有序 → **Cochran–Armitage 趨勢檢定**；X、Y 都經確認有序 → **linear-by-linear association 檢定**（§2.5）。X 二元名目 × Y 有序不支援（需要確認分析目的） | `x_scores`、`y_scores`（可省略，預設等距）；有序變數必須列在 `ordinal` |
| `stratified` | 三因子表：各層勝算比、合併勝算比、Simpson 悖論、CMH 與同質性檢定（§2.7、§4.3.4）；X、Y 須為二元 | `z`（控制變數） |

欄位說明：

- 紀錄欄位（R 不使用，但要寫，讓判斷可以被檢查）：`question`（使用者原文）、`structure`、`types`（例如 `{"studytime": "ordinal", "pass": "binary"}`）、`method_id`（和 `analysis` 相同）、`reason`（附節號）
- `x`：解釋變數（表的列）；`y`：結果變數（表的欄）；`count`：已彙整資料的次數欄（沒有就 `null`）
- `ordinal`：使用者確認為有序的變數；`levels`：類別順序（有序變數必填）
- `x_scores`／`y_scores`：類別分數，須依順序遞增。類別間距不等時（例如「每天 0、<1、1–2、3–5、≥6 小時」）用各類中點，並提醒分數會影響結果（§2.5.4）
- `recode`（選用）：由 R 建立新的類別變數，不要自己算

```json
"recode": {
  "passed": {"from": "G3", "breaks": [10], "labels": ["fail", "pass"]},
  "Walc2": {"from": "Walc", "map": {"1": "少", "2": "少", "3": "多", "4": "多", "5": "多"}}
}
```

`breaks`：每個門檻開始一個新類別（`G3 < 10 → fail`、`G3 ≥ 10 → pass`），`labels` 比 `breaks` 多 1 個；`map`：每個原始值都要有對應。

執行：

```
Rscript scripts/run_analysis.R <資料檔> spec.json <輸出資料夾>
```

輸出：`result.json`、圖（`.png`）、`分析報告_<資料>_<方法>.md`（R 自動產生，數字表格都在裡面）、`reproduce.R`、`spec.json` 副本。`result.json` 含 `error` 時，用白話說明並協助修正。JSON 中的 `"Inf"` 代表無限大（例如樣本勝算比 ∞），不是缺失值。

## 階段 5：解釋結果（固定段落）

用繁體中文，依序：

1. **一句話結論**：回答使用者的問題（看檢定 P 值；出現 `LOW_EXPECTED` 時以 Fisher 檢定為準）。
2. **關聯的樣子**：用各組比例與標準化殘差（|殘差| > 2 的格子）說明哪裡不一樣，附上圖。
3. **關聯的強度**：一律同時報告效果量與信賴區間（2×2 表：比例差、相對風險、勝算比；分層：各層勝算比），並說明意義。
4. **注意事項**：逐條說明 `warnings`（附節號），以及對結論的影響。
5. **限制與下一步**：需要控制更多變數或資料不獨立時，轉介對應的 Skill。

### 輸出用語規則（`references/checklist.md` 第 14–16 條，每次都要遵守）

| 情況 | 要這樣寫 | 不可以這樣寫 |
|---|---|---|
| P < 0.05 | 「有證據顯示有關聯」，並用效果量和信賴區間說明關聯多大 | 「關係很強」「高度相關」 |
| P ≥ 0.05 | 「證據不足，無法確定有關聯」，並說明信賴區間有多寬 | 「沒有關係」「兩者無關」 |
| 觀察性資料 | 「有關聯」「比較高／比較低」 | 「造成」「導致」「使得」「影響了」 |
| 勝算比 OR = 2 | 「勝算（odds）是 2 倍」；不是 case-control 時，同時用相對風險說明機率的倍數 | 「機率是 2 倍」「風險是 2 倍」 |
| 橫斷調查的比例 | 「比例」「盛行率」 | 「發生風險」 |
| 便利樣本 | 結論限於這群樣本，推論到母體需要額外的抽樣假設 | 「台灣的大學生……」等推廣到母體的說法 |

只有使用者在階段 3 確認是**隨機分派的實驗**時，才可以使用因果用語。

依方法補充：

- **`trend`**：用 `method_label` 的名稱（Cochran–Armitage 趨勢檢定，或 linear-by-linear association 檢定），兩者不可混稱。說明趨勢方向（`facts` 中的單尾句）與 M² 的 P 值；和忽略順序的 X² 對照，說明為什麼有序檢定通常較有力（§2.5.3），以及它只抓線性趨勢。出現 `SCORE_SENSITIVE` 時要明白說「結論取決於分數設定」。R 不適合單獨描述關聯強弱。
- **`stratified`**：先講每一層的勝算比與信賴區間，再講合併後與共同勝算比。出現 `SIMPSON` 時，用日常的話解釋為什麼合併後方向會反過來（控制變數同時和 X、Y 有關，§2.7.3）。出現 `OPPOSITE_DIRECTIONS` 或 `HETEROGENEITY` 時，要逐層報告，不能只報共同勝算比。兩者都沒出現時，也不能說共同勝算比一定適合：同質性檢定只是輔助，請使用者自己看各層勝算比與信賴區間；不要用任何倍率門檻自行判斷「差很多」。
- **`SMALL_GROUP`、切類別的提醒**（`recode` 用 `breaks` 時）：只寫在注意事項裡，不改變結論的寫法。

最後**把解釋補進 R 產生的報告檔**：在 `分析報告_*.md` 的最上面加一節「## 結論與解釋」（上面 5 段的內容），告訴使用者報告檔的位置。

原則：`facts` 可以改寫得更口語，但**數字不可更改**；P 值代表有沒有證據，不代表關聯強弱；勝算比不是「機率的倍數」（出現 `OR_NOT_RR` 時要說明，§2.3.4）。

## 參考資料（需要時再讀）

- `references/checklist.md`：注意事項清單，判斷適不適合（階段 3 用）
- `references/decision-tree.md`：選方法的決策樹（階段 3 用）
- `references/methods.md`：每個方法的用途、假設、R 程式碼（模式 2 用）
- `references/textbook-methods.md`：教科書的完整步驟與公式（使用者追問原理時用）
