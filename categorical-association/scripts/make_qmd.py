# Write a reproducible Quarto file for one finished analysis without R (claude.ai):
# same input and output as make_qmd.R, built from the same text pieces in scripts/qmd/.
#
# Usage: python make_qmd.py <data file> <output dir>
#
# Reads spec.json and result.json from <output dir> and writes 分析_<data>_<analysis>.qmd there.
# The file contains R code that needs only CRAN packages; Claude then replaces the marker
# under "## 結論與解釋" with the stage-5 interpretation.

import json
import os
import re
import sys

if len(sys.argv) != 3:
    sys.exit("Usage: python make_qmd.py <data file> <output dir>")
data_file, out_dir = sys.argv[1:3]
qmd_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), "qmd")

with open(os.path.join(out_dir, "spec.json"), encoding="utf-8") as f:
    spec = json.load(f)
with open(os.path.join(out_dir, "result.json"), encoding="utf-8") as f:
    result = json.load(f)
if result.get("error"):
    sys.exit("result.json 有錯誤，先修正分析再產生 qmd。")


def as_list(v):
    # R's jsonlite writes a one-element vector as a scalar
    return v if isinstance(v, list) else [v]


def num(v):
    v = float(v)
    return str(int(v)) if v.is_integer() else repr(v)


def q(s):
    return '"' + str(s).replace("\\", "\\\\").replace('"', '\\"') + '"'


def r_vec(v, quote=True):
    return "c(" + ", ".join(q(s) if quote else num(s) for s in v) + ")"


def label(v):
    return num(v) if isinstance(v, (int, float)) and not isinstance(v, bool) else str(v)


def bt(s):
    return "`" + s + "`"


def cell(s):
    return str(s).replace("|", "\\|")


def fill(piece, values):
    with open(os.path.join(qmd_dir, piece), encoding="utf-8") as f:
        text = f.read()
    if text.endswith("\n"):
        text = text[:-1]
    for k, v in values.items():
        text = text.replace("{{" + k + "}}", v)
    return text


analysis = spec["analysis"]
x, y, z, count = spec.get("x"), spec.get("y"), spec.get("z"), spec.get("count")
conf = num(spec.get("conf_level") or 0.95)
if spec.get("success") is None:
    success = "colnames(tab3)[1]" if analysis == "stratified" else "colnames(tab)[1]"
else:
    success = q(spec["success"])
variables = [v for v in (x, y, z) if v is not None]

# ---- reading the data, the same way as read_data() in R/utils.R ----
# claude.ai puts a code like "ccd840c3-" in front of uploaded file names; the user's own copy
# has the original name, so the qmd reads that one.
base = re.sub(r"^[0-9a-f]{8}-", "", os.path.basename(data_file))
low = base.lower()
if low.endswith(".dat"):
    read_code = "df <- read.table(data_file, header = TRUE)"
elif low.endswith(".xlsx") or low.endswith(".xls"):
    read_code = "df <- as.data.frame(readxl::read_excel(data_file))"
else:
    raw = open(data_file, "rb").read()
    try:
        text = raw.decode("utf-8")
        encoding = "UTF-8"
    except UnicodeDecodeError:
        text = raw.decode("big5", errors="replace")
        encoding = "BIG5"
    header = text.splitlines()[0] if text else ""
    sep = max([",", ";", "\t"], key=lambda s: header.count(s))
    delim = {",": '","', ";": '";"', "\t": '"\\t"'}[sep]
    read_code = ("df <- as.data.frame(readr::read_delim(data_file, delim = %s,\n"
                 "  locale = readr::locale(encoding = %s), show_col_types = FALSE))" % (delim, q(encoding)))

recode_lines = []
for nm, r in (spec.get("recode") or {}).items():
    if r.get("breaks") is not None:
        breaks = sorted(float(b) for b in as_list(r["breaks"]))
        recode_lines += [
            "# 新變數 %s：由 %s 依門檻切分（每個門檻開始一個新類別）" % (nm, r["from"]),
            "df[[%s]] <- cut(as.numeric(df[[%s]]), breaks = c(-Inf, %s, Inf),\n  labels = %s, right = FALSE)" % (
                q(nm), q(r["from"]), ", ".join(num(b) for b in breaks), r_vec(as_list(r["labels"])))]
    else:
        m = r["map"]
        targets = list(dict.fromkeys(str(v) for v in m.values()))
        recode_lines += [
            "# 新變數 %s：由 %s 合併類別" % (nm, r["from"]),
            "df[[%s]] <- factor(unname(c(%s)[as.character(df[[%s]])]),\n  levels = %s)" % (
                q(nm), ", ".join("%s = %s" % (q(k), q(v)) for k, v in m.items()), q(r["from"]), r_vec(targets))]
recode_block = "\n```{r}\n" + "\n".join(recode_lines) + "\n```\n" if recode_lines else ""

levels = spec.get("levels") or {}
factor_code = []
for v in variables:
    if levels.get(v) is not None:
        factor_code.append("df[[%s]] <- factor(df[[%s]], levels = %s)" % (q(v), q(v), r_vec([label(s) for s in as_list(levels[v])])))
    else:
        factor_code.append('df[[%s]] <- factor(df[[%s]], levels = sort(unique(df[[%s]]), method = "radix"))' % (q(v), q(v), q(v)))
miss_cols = "vars" if count is None else "c(vars, %s)" % q(count)
if count is None:
    missing_code = "c(排除筆數 = sum(miss), 比例 = mean(miss))"
    zero_code = ""
else:
    missing_code = ("w <- df[[%s]]\nc(排除次數 = sum(w[miss], na.rm = TRUE), 比例 = sum(w[miss], na.rm = TRUE) / sum(w, na.rm = TRUE))"
                    % q(count))
    zero_code = "\ndf <- df[df[[%s]] > 0, ]                  # 次數為 0 的列不影響次數表" % q(count)
formula = ("~ " if count is None else bt(count) + " ~ ") + " + ".join(bt(v) for v in variables)

# ---- analysis settings table ----
types = spec.get("types") or {}
settings = []
if spec.get("question") is not None:
    settings.append("| 問題 | %s |" % cell(spec["question"]))
settings.append("| 資料檔 | `%s` |" % cell(base))
settings.append("| 方法 | %s（Agresti %s） |" % (cell(result["method_label"]), result["book_ref"]))
if spec.get("reason") is not None:
    settings.append("| 選擇理由 | %s |" % cell(spec["reason"]))
settings.append("| 變數 | 解釋變數 X：%s；結果變數 Y：%s%s |" % (cell(x), cell(y), "" if z is None else "；控制變數 Z：" + cell(z)))
if types:
    settings.append("| 變數型態 | %s |" % cell("；".join("%s：%s" % (k, v) for k, v in types.items())))
if spec.get("structure") is not None:
    settings.append("| 資料結構 | %s |" % cell(spec["structure"]))
if spec.get("design") is not None:
    settings.append("| 研究設計 | %s |" % cell(spec["design"]))

title = "分析報告：%s" % (spec.get("question") or result["method_label"])
pieces = [fill("header.qmd", {
    "title": title.replace('"', '\\"'), "data_file": base, "data_file_q": q(base), "settings": "\n".join(settings),
    "read_code": read_code, "recode_block": recode_block, "factor_code": "\n".join(factor_code),
    "vars": r_vec(variables), "miss_cols": miss_cols, "missing_code": missing_code, "zero_code": zero_code})]

test_names = [t["test"] for t in result["tests"]]
if analysis == "crosstab":
    pieces.append(fill("crosstab.qmd", {"formula": formula}))
    if "Fisher exact (two-sided)" in test_names:
        pieces.append(fill("fisher_2x2.qmd", {}))
    elif any(t.startswith("Fisher exact:") for t in test_names):
        pieces.append(fill("fisher_rxc.qmd", {}))
    if result["estimates"]:
        piece = "effect_cc.qmd" if spec.get("design") == "case-control" else "effect.qmd"
        pieces.append(fill(piece, {"success": success, "conf": conf}))
    pieces.append(fill("plot.qmd", {"x_q": q(x), "y_q": q(y)}))
elif analysis == "trend":
    notes = result["notes"]
    ca = notes["trend_type"] == "cochran_armitage"
    if ca:
        v = "as.numeric(colnames(tab) == %s)   # %s：成功 = 1，其他 = 0" % (success, y)
    else:
        v = r_vec(as_list(notes["scores"]["y"]), quote=False) + "   # " + y + " 各類的分數（依順序）"
    pieces.append(fill("trend.qmd", {
        "formula": formula, "x": x, "u": r_vec(as_list(notes["scores"]["x"]), quote=False), "v": v,
        "trend_name": "Cochran–Armitage 趨勢檢定" if ca else "Linear-by-linear association 檢定"}))
    if spec.get("x_scores") is not None or spec.get("y_scores") is not None:
        pieces.append(fill("trend_sensitivity.qmd", {"v_equal": "v" if ca else "seq_len(ncol(tab))"}))
    pieces.append(fill("plot.qmd", {"x_q": q(x), "y_q": q(y)}))
else:
    pieces.append(fill("stratified.qmd", {"formula": formula, "success": success, "conf": conf}))
    pieces.append(fill("plot_stratified.qmd", {"x_q": q(x), "y_q": q(y), "z_q": q(z)}))

warnings = result["warnings"]
warnings_block = ("\n## 注意事項\n\n" + "\n".join("- %s（Agresti %s）" % (w["message"], w["book_ref"]) for w in warnings) + "\n"
                  if warnings else "")
pieces.append(fill("footer.qmd", {"warnings_block": warnings_block, "reminder": result["notes"]["reminder"]}))

out_file = os.path.join(out_dir, "分析_%s_%s.qmd" % (os.path.splitext(base)[0], analysis))
with open(out_file, "w", encoding="utf-8", newline="") as f:
    f.write("\n".join(pieces) + "\n")
print("QMD:", os.path.abspath(out_file))
