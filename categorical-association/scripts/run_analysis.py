# Run one analysis without R (claude.ai): same input and output files as run_analysis.R.
#
# Usage: python run_analysis.py <data file> <spec.json> <output dir>
#
# Writes to <output dir>: result.json, PNG plots, 分析報告_<data>_<analysis>.md, reproduce.py,
# and a copy of spec.json. On failure, result.json contains {"error": "..."} and the script
# exits with status 1. All numbers come from cda_engine.py, which mirrors R/association.R.

import json
import math
import os
import shutil
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import cda_describe as cd  # noqa: E402
import cda_engine as ce  # noqa: E402

if len(sys.argv) != 4:
    sys.exit("Usage: python run_analysis.py <data file> <spec.json> <output dir>")
data_file, spec_file, out_dir = sys.argv[1:4]
os.makedirs(out_dir, exist_ok=True)


def fail(msg):
    cd.write_json({"error": msg}, os.path.join(out_dir, "result.json"))
    print("ERROR:", msg, file=sys.stderr)
    sys.exit(1)


with open(spec_file, encoding="utf-8") as f:
    spec = json.load(f)
try:
    data = cd.read_data(data_file)
except Exception as e:
    fail("無法讀取資料： %s" % e)
recode_notes = []
if spec.get("recode"):
    try:
        data, recode_notes = cd.cda_recode(data, spec["recode"])
    except ValueError as e:
        fail(str(e))
needed = []
for k in ("x", "y", "z", "count"):        # as unlist() in R: a value may be a list of names
    v = spec.get(k)
    needed += v if isinstance(v, list) else ([] if v is None else [v])
missing_cols = [v for v in needed if v not in data.columns]
if missing_cols:
    fail("資料中找不到欄位：%s。現有欄位：%s" % (", ".join(missing_cols), ", ".join(data.columns)))
for v, lv in (spec.get("levels") or {}).items():
    data[v] = cd.as_factor(data[v], lv if isinstance(lv, list) else [lv])


def as_list(v):
    return [] if v is None else (v if isinstance(v, list) else [v])


analysis = spec.get("analysis")
conf = spec.get("conf_level") or 0.95
try:
    if analysis == "crosstab":
        result = ce.cda_crosstab(data, spec["x"], spec["y"], count=spec.get("count"), success=spec.get("success"),
                                 ordinal=as_list(spec.get("ordinal")), design=spec.get("design") or "unknown",
                                 conf_level=conf)
    elif analysis == "trend":
        result = ce.cda_trend(data, spec["x"], spec["y"], count=spec.get("count"), ordinal=as_list(spec.get("ordinal")),
                              x_scores=spec.get("x_scores"), y_scores=spec.get("y_scores"), success=spec.get("success"))
    elif analysis == "stratified":
        result = ce.cda_stratified(data, spec["x"], spec["y"], spec["z"], count=spec.get("count"),
                                   success=spec.get("success"), conf_level=conf)
    else:
        fail("本 Skill 不支援的分析：%s。本 Skill 只做兩個類別變數的關聯分析（crosstab、trend、stratified）。" % analysis)
except ce.CdaError as e:
    fail(str(e))
result["facts"] = recode_notes + result["facts"]   # say how any new variable was made

# ---- plots (same file names as the R version) ----
cjk = cd.setup_fonts()
import matplotlib.pyplot as plt  # noqa: E402
import numpy as np  # noqa: E402

COLORS = ["#66c2a5", "#fc8d62", "#8da0cb", "#e78ac3", "#a6d854", "#ffd92f", "#e5c494", "#b3b3b3"]


def save(fig, name):
    fig.tight_layout()
    fig.savefig(os.path.join(out_dir, name + ".png"), facecolor="white")
    plt.close(fig)


def plot_conditional_props(res):
    v = res["notes"]["variables"]
    props = res["tables"]["row_proportions"]
    fig, ax = plt.subplots(figsize=(7, 4.5), dpi=150)
    bottom = np.zeros(len(props))
    for j, col in enumerate(props.columns):
        vals = props[col].values
        ax.bar(list(props.index), vals, bottom=bottom, color=COLORS[j % len(COLORS)], width=0.65,
               edgecolor="white", label=str(col))
        for k, val in enumerate(vals):
            if val >= 0.04:
                ax.text(k, bottom[k] + val / 2, "%d%%" % round(val * 100), ha="center", va="center", color="white")
        bottom += vals
    ax.yaxis.set_major_formatter(lambda t, _: "%d%%" % round(t * 100))
    ax.set_xlabel(v["x"])
    ax.set_ylabel(("各組內 %s 的比例" % v["y"]) if cjk else ("Proportion of %s within group" % v["y"]))
    ax.legend(title=v["y"], bbox_to_anchor=(1.02, 0.5), loc="center left")
    ax.spines[["top", "right"]].set_visible(False)
    save(fig, "conditional_props")


def plot_residuals(res):
    v = res["notes"]["variables"]
    r = res["tables"]["standardized_residuals"]
    lim = max(3, float(np.abs(r.values).max()))
    fig, ax = plt.subplots(figsize=(7, 4.5), dpi=150)
    im = ax.imshow(r.values, cmap="RdBu_r", vmin=-lim, vmax=lim, aspect="auto")
    for i in range(r.shape[0]):
        for j in range(r.shape[1]):
            val = r.values[i, j]
            ax.text(j, i, "%.2f" % val, ha="center", va="center", fontsize=12,
                    fontweight="bold" if abs(val) > 2 else "normal")
    ax.set_xticks(range(r.shape[1]), [str(c) for c in r.columns])
    ax.set_yticks(range(r.shape[0]), [str(i) for i in r.index])
    ax.set_xlabel(v["y"]); ax.set_ylabel(v["x"])
    fig.colorbar(im, ax=ax, label="標準化殘差" if cjk else "Standardized residual")
    save(fig, "residuals")


def plot_trend(res):
    v = res["notes"]["variables"]
    tab = res["tables"]["counts"]
    if tab.shape[1] != 2:
        plot_conditional_props(res)
        os.replace(os.path.join(out_dir, "conditional_props.png"), os.path.join(out_dir, "trend.png"))
        return
    s = [col for col, sc in zip(tab.columns, res["notes"]["scores"]["y"]) if sc == 1][0]
    prop = tab[s] / tab.sum(axis=1)
    n = tab.sum(axis=1)
    fig, ax = plt.subplots(figsize=(7, 4.5), dpi=150)
    xs = range(len(prop))
    ax.plot(xs, prop.values, color="grey", zorder=1)
    ax.scatter(xs, prop.values, s=30 + 200 * n / n.max(), color="#1f3a5f", zorder=2)
    for k, pv in enumerate(prop.values):
        ax.annotate("%.2f%%" % (pv * 100), (k, pv), textcoords="offset points", xytext=(0, 10), ha="center")
    ax.set_xticks(list(xs), list(prop.index))
    ax.yaxis.set_major_formatter(lambda t, _: "%d%%" % round(t * 100))
    ax.margins(y=0.25)
    ax.set_xlabel(v["x"]); ax.set_ylabel(("「%s」的比例" % s) if cjk else ("Proportion of %s" % s))
    ax.spines[["top", "right"]].set_visible(False)
    save(fig, "trend")


def plot_stratified(res):
    v = res["notes"]["variables"]
    st = res["tables"]["strata"]
    xl = list(dict.fromkeys(row[v["x"]] for row in res["tables"]["partial_tables"]))
    fig, axes = plt.subplots(1, len(st), figsize=(max(7, 1.6 * len(st)), 4.5), dpi=150, sharey=True, squeeze=False)
    for k, row in enumerate(st):
        ax = axes[0][k]
        vals = [row["p1"], row["p2"]]
        ax.bar(xl, vals, color=["#1f3a5f", "#e07b39"], width=0.6)
        for i, pv in enumerate(vals):
            if not math.isnan(pv):
                ax.text(i, pv, "%.1f%%" % (pv * 100), ha="center", va="bottom", fontsize=9)
        title = row["stratum"] if k == len(st) - 1 else "%s = %s" % (v["z"], row["stratum"])
        ax.set_title(title, fontsize=9)
        ax.spines[["top", "right"]].set_visible(False)
    axes[0][0].yaxis.set_major_formatter(lambda t, _: "%d%%" % round(t * 100))
    axes[0][0].set_ylabel(("「%s」的比例" % res["notes"]["success"]) if cjk else ("Proportion of %s" % res["notes"]["success"]))
    save(fig, "stratified")


plot_names = {"crosstab": ["conditional_props", "residuals"], "trend": ["trend"], "stratified": ["stratified"]}[analysis]
{"crosstab": lambda r: (plot_conditional_props(r), plot_residuals(r)),
 "trend": plot_trend, "stratified": plot_stratified}[analysis](result)
result["plots"] = [p + ".png" for p in plot_names]

# ---- Markdown report (same layout as run_analysis.R) ----


def fmt_cell(v, digits=4):
    if v is None or (isinstance(v, float) and math.isnan(v)):
        return "—"
    if isinstance(v, (int, float, np.floating, np.integer)):
        v = float(v)
        if math.isinf(v):
            return "∞"
        if abs(v) < 1e-3 and v != 0:
            return "%.3e" % v
        return "%.*f" % (digits, v)
    return str(v)


def md_table(rows, cols, digits=4):
    if not rows:
        return []
    out = ["| " + " | ".join(cols) + " |", "|" + "|".join(["---"] * len(cols)) + "|"]
    for r in rows:
        out.append("| " + " | ".join(fmt_cell(r.get(c), digits) for c in cols) + " |")
    return out


if analysis == "stratified":
    pt = result["tables"]["partial_tables"]
    count_md = md_table(pt, list(pt[0].keys()), digits=0)
else:
    tab = result["tables"]["counts"]
    rows = [dict({" ": idx}, **{c: tab.loc[idx, c] for c in tab.columns}) for idx in tab.index]
    count_md = md_table(rows, [" "] + list(tab.columns), digits=0)
data_name = cd.data_stem(data_file)
report = ["# 分析報告：%s" % (spec.get("question") or result["method_label"]), "",
          "- 資料檔：`%s`" % os.path.basename(data_file),
          "- 方法：%s（Agresti %s）" % (result["method_label"], result["book_ref"])]
if spec.get("structure") is not None:
    report.append("- 資料結構：%s" % spec["structure"])
if spec.get("reason") is not None:
    report.append("- 選擇理由：%s" % spec["reason"])
report += ["", "## 次數表", ""] + count_md + ["", "## 結果", ""] + ["- " + f for f in result["facts"]] + [""]
if result["tests"]:
    report += ["## 檢定", ""] + md_table(result["tests"], ["test", "statistic", "df", "p_value", "book_ref"]) + [""]
if result["estimates"]:
    report += ["## 效果量與信賴區間", ""] + md_table(result["estimates"],
                                              ["measure", "estimate", "lower", "upper", "ci_method", "book_ref"]) + [""]
if result["warnings"]:
    report += ["## 注意事項", ""] + ["- %s（Agresti %s）" % (w["message"], w["book_ref"]) for w in result["warnings"]] + [""]
report += ["## 圖", ""] + ["![](%s)" % p for p in result["plots"]] + ["", "> %s" % result["notes"]["reminder"]]
report_file = os.path.join(out_dir, "分析報告_%s_%s.md" % (data_name, analysis))
cd.write_lines(report, report_file)
result["report"] = os.path.basename(report_file)

# ---- reproduce.py, spec copy, result.json ----
here = os.path.dirname(os.path.abspath(__file__)).replace("\\", "/")
cd.write_lines([
    "# 重現這次分析的 Python 程式碼（需要本 Skill 的 scripts/ 資料夾）",
    "import subprocess, sys",
    "subprocess.run([sys.executable, %r, %r, %r, %r], check=True)" % (
        here + "/run_analysis.py", os.path.abspath(data_file).replace("\\", "/"),
        os.path.abspath(os.path.join(out_dir, "spec.json")).replace("\\", "/"), os.path.abspath(out_dir).replace("\\", "/")),
], os.path.join(out_dir, "reproduce.py"))
spec_copy = os.path.join(out_dir, "spec.json")
if os.path.abspath(spec_file) != os.path.abspath(spec_copy):
    shutil.copyfile(spec_file, spec_copy)
out = ce.to_json(result)
if len(out["plots"]) == 1:          # R's jsonlite writes a one-element vector as a scalar
    out["plots"] = out["plots"][0]
cd.write_json(out, os.path.join(out_dir, "result.json"))
print("OK:", os.path.abspath(os.path.join(out_dir, "result.json")))
print("REPORT:", os.path.abspath(report_file))
