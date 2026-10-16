# Stage 2 without R (claude.ai): same output as describe_question.R.
#
# Usage: python describe_question.py <data file> <question.json> <output dir>
# Writes to <output dir>: check.json, bar_<variable>.png, relation.png, 初步檢視_<data>.md.
# On failure, check.json contains {"error": "..."} and the script exits with status 1.

import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import cda_describe as cd  # noqa: E402

if len(sys.argv) != 4:
    sys.exit("Usage: python describe_question.py <data file> <question.json> <output dir>")
data_file, q_file, out_dir = sys.argv[1:4]
os.makedirs(out_dir, exist_ok=True)


def fail(msg):
    cd.write_json({"error": msg}, os.path.join(out_dir, "check.json"))
    print("ERROR:", msg, file=sys.stderr)
    sys.exit(1)


with open(q_file, encoding="utf-8") as f:
    q = json.load(f)
x, y, z, count = q.get("x"), q.get("y"), q.get("z"), q.get("count")
try:
    data = cd.read_data(data_file)
except Exception as e:
    fail("無法讀取資料： %s" % e)
recode_notes = []
if q.get("recode"):
    try:
        data, recode_notes = cd.cda_recode(data, q["recode"])
    except ValueError as e:
        fail(str(e))
needed = [v for v in (x, y, z, count) if v is not None]
missing_cols = [v for v in needed if v not in data.columns]
if missing_cols:
    fail("資料中找不到欄位：%s。現有欄位：%s" % (", ".join(missing_cols), ", ".join(data.columns)))
for v, lv in (q.get("levels") or {}).items():
    data[v] = cd.as_factor(data[v], lv)

try:
    facts, d, w, tab = cd.question_check(data, x, y, z, count)
except Exception as e:
    fail(str(e))

cjk = cd.setup_fonts()
plots = []
for v in [v for v in (x, y, z) if v is not None]:
    name = "bar_%s.png" % v
    cd.plot_bar(d, v, w, os.path.join(out_dir, name), cjk)
    plots.append(name)
cd.plot_relation(d, x, y, w, os.path.join(out_dir, "relation.png"), cjk, z)
plots.append("relation.png")
facts["plots"] = plots
facts["recode_notes"] = recode_notes
cd.write_json(facts, os.path.join(out_dir, "check.json"))

# Markdown summary for the user (same layout as describe_question.R).
fc = cd.fmt_count
lines = ["# 初步檢視：%s" % os.path.basename(data_file), ""] + recode_notes + [
    "- 使用的觀察值：%s（因缺失刪除 %s）" % (fc(facts["n"]), fc(facts["n_missing_dropped"])),
    "- 最小的一組：%s = %s，%s 個" % (facts["smallest_group"]["variable"], facts["smallest_group"]["level"],
                                fc(facts["smallest_group"]["n"])),
    "- 獨立假設下的最小期望次數：%s；期望次數 < 5 的格子：%d / %d；次數為 0 的格子：%d" % (
        cd.fmt_num(facts["min_expected"]), facts["cells_expected_below_5"], facts["cells_total"], facts["zero_cells"])]
for s in facts.get("strata", []):
    lines.append("- %s = %s：%s 個，最小期望次數 %s，0 次數格子 %d" % (
        z, s["stratum"], fc(s["n"]), cd.fmt_num(s["min_expected"]), s["zero_cells"]))
lines += ["", "## 次數表", "",
          "| %s \\ %s | %s | 合計 |" % (x, y, " | ".join(str(c) for c in tab.columns)),
          "|" + "---|" * (tab.shape[1] + 2)]
for r, row in tab.iterrows():
    lines.append("| %s | %s | %s |" % (r, " | ".join(fc(v) for v in row), fc(row.sum())))
lines += ["", "## 圖", ""] + ["![](%s)" % p for p in plots]
cd.write_lines(lines, os.path.join(out_dir, "初步檢視_%s.md" % cd.data_stem(data_file)))
print("OK:", os.path.abspath(os.path.join(out_dir, "check.json")))
