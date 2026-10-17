"""Python version of stages 1-2 for environments without R (claude.ai).

Mirrors R/profile.R, R/describe.R and the recode in R/utils.R so that both give the same
profile.json, check.json and overview tables; dev/tests/test-python.R checks this. Only
descriptive counts and plots live here: every statistical test stays in R.
"""

import json
import math
import os
import re

import pandas as pd

# ---------------------------------------------------------------- reading data

def read_data(path):
    """Textbook .dat files, Excel, UTF-8 CSVs (with or without BOM) and Big5 CSVs."""
    low = path.lower()
    if low.endswith(".dat"):
        return pd.read_csv(path, sep=r"\s+")
    if low.endswith(".xlsx") or low.endswith(".xls"):
        return pd.read_excel(path)
    raw = open(path, "rb").read()
    try:
        text = raw.decode("utf-8-sig")
        encoding = "utf-8-sig"
    except UnicodeDecodeError:
        text = raw.decode("big5", errors="replace")
        encoding = "big5"
    header = text.splitlines()[0] if text else ""
    sep = max([",", ";", "\t"], key=lambda s: header.count(s))
    return pd.read_csv(path, sep=sep, encoding=encoding)


def value_str(v):
    """How R prints a value: 1.0 -> '1', 2.5 -> '2.5'."""
    if isinstance(v, float) and v.is_integer():
        return str(int(v))
    return str(v)


def sort_key(v):
    # Numbers numerically, text by character code (R: sort(method = "radix")).
    if isinstance(v, (int, float)):
        return (0, v, "")
    return (1, 0, str(v))


def is_numeric(series):
    return pd.api.types.is_numeric_dtype(series) and not pd.api.types.is_bool_dtype(series)

# ---------------------------------------------------------------- stage 1: profile

ORDINAL_WORDS = [
    "非常", "很", "有點", "普通", "還好", "尚可", "不太", "同意", "滿意", "喜歡",
    "低", "中", "高", "從不", "從未", "很少", "偶爾", "有時", "經常", "時常", "總是",
    "輕", "重", "差", "好", "優", "劣", "每天", "每週", "每月",
    "never", "rarely", "seldom", "sometimes", "often", "usually", "always",
    "low", "medium", "moderate", "high", "none", "slight", "mild", "severe",
    "poor", "fair", "good", "excellent", "agree", "disagree", "neutral",
    "satisf", "dissatisf", "strongly", "very", "somewhat", "little",
]
ID_PATTERN = re.compile(
    r"^(id|.*_id|person|subject|case|patient|participant|respondent|student|school|class|"
    r"cluster|family|household|group|litter|center|centre|hospital|clinic|crab)$|"
    r"編號|學號|代號|受試|個案|病患|病人|受訪|學生|學校|班級|家庭|家戶|醫院|群組", re.I)
TIME_PATTERN = re.compile(
    r"^(time|visit|week|month|year|wave|occasion|round|period|trial|session|situation|question|"
    r"item|condition|course|t)$|時間|時點|次數|第幾|週|月份|年度|期|回合|題目|情境|科目|課程|學科", re.I)
PAIR_PATTERN = re.compile(r"pre|post|before|after|baseline|follow|^y[0-9]$|^t[0-9]$|前測|後測|之前|之後|第一次|第二次", re.I)
COUNT_PATTERN = re.compile(r"^(n|count|counts|freq|frequency|weight|wt)$|次數|人數|頻數|數量|個數", re.I)
AGE_PATTERN = re.compile(r"^age$|_age$|^age_|年齡|歲", re.I)


def profile_variable(series, name):
    n = len(series)
    miss = int(series.isna().sum())
    x = series.dropna()
    uniq = list(pd.unique(x))
    k = len(uniq)
    num = is_numeric(series)
    int_like = num and k > 0 and all(abs(v - round(v)) < 1e-8 for v in x)
    xmin = x.min() if num and k > 0 else None
    xmax = x.max() if num and k > 0 else None

    guess, confirm, reason = "nominal", False, ""
    if k == 0:
        guess, reason = "empty", "全部缺失"
    elif ID_PATTERN.search(name) and k > 10:
        guess, reason = "id", "欄名像識別碼，且類別很多"
    elif k == len(x) and k > 20 and (int_like or not num):
        guess, reason = "id", "每一列的值都不同"
    elif k == 2:
        guess, reason = "binary", "只有 2 種值"
    elif num and AGE_PATTERN.search(name):
        guess, reason = "continuous", "欄名像年齡，視為數值變數"
    elif num and not int_like:
        guess, reason = "continuous", "含小數的數值"
    elif int_like and k <= 10 and xmax - xmin == k - 1:
        guess, confirm = "ordinal_or_nominal_code", True
        reason = "只有 %d 個連續整數（%s–%s），可能是有序量表或類別代碼" % (k, value_str(xmin), value_str(xmax))
    elif int_like and xmin >= 0 and COUNT_PATTERN.search(name):
        guess, confirm, reason = "frequency_weight", True, "欄名像次數，可能是彙整資料的次數欄"
    elif int_like and xmin >= 0:
        guess, confirm, reason = "count_or_continuous", True, "非負整數且值很多，可能是計數或連續量"
    elif num:
        guess, reason = "continuous", "數值且值很多"
    elif k > 20:
        guess, confirm, reason = "nominal_many_levels", True, "文字類別超過 20 種，可能是自由填答或識別碼"
    else:
        hits = [any(w.lower() in str(u).lower() for w in ORDINAL_WORDS) for u in uniq]
        if sum(hits) / len(hits) >= 0.5:
            guess, confirm, reason = "ordinal_candidate", True, "類別名稱像有順序的量表，請確認順序"
        else:
            reason = "文字類別，看起來沒有順序"

    levels = None
    if k <= 20:
        counts = x.value_counts()
        levels = {value_str(v): int(counts[v]) for v in sorted(counts.index, key=sort_key)}
    rng = [to_json_num(xmin), to_json_num(xmax)] if num and k > 0 else None
    return {
        "name": name, "n": n, "n_missing": miss, "n_unique": k,
        "type_guess": guess, "needs_confirmation": confirm, "reason": reason,
        "levels": levels, "examples": [value_str(u) for u in uniq[:5]], "range": rng,
    }


def to_json_num(v):
    if v is None:
        return None
    v = float(v)
    return int(v) if v.is_integer() else v


def detect_structure(data, variables):
    hints = []
    types = {v["name"]: v["type_guess"] for v in variables}
    cols = list(data.columns)

    # 1. An id-like column with repeated values: repeated measures or clustered data.
    id_cols = [c for c in cols if ID_PATTERN.search(c)]
    if "frequency_weight" in types.values():
        id_cols = []
    for idc in id_cols:
        per_id = data[idc].dropna().value_counts()
        if len(per_id) >= 5 and per_id.max() >= 2:
            within = []
            for tc in [c for c in cols if TIME_PATTERN.search(c) and c != idc]:
                k = data[tc].dropna().nunique()
                no_dup = all(not g.dropna().duplicated().any() for _, g in data.groupby(idc)[tc])
                if 2 <= k <= 20 and no_dup:
                    within.append(tc)
            kind = "repeated_measures" if within else "clustered"
            med = per_id.median()
            evidence = "%s 有 %d 個不同的值，每個值出現 %d–%d 列（中位數 %s）" % (
                idc, len(per_id), per_id.min(), per_id.max(), value_str(float(med)))
            if within:
                evidence += "；%s 在每個 %s 內不重複，像是測量時點或題目" % ("/".join(within), idc)
            question = ("同一個 %s 是否被測量了多次（每次一列）？" % idc if kind == "repeated_measures"
                        else "%s 是否代表群組（例如學校、家庭），同群組內的觀察可能彼此相關？" % idc)
            hints.append({"type": kind, "columns": [idc] + within, "evidence": evidence,
                          "question": question, "book_ref": "§9.1, §10.1"})

    # 2. Wide matched pairs: categorical columns sharing the same set of levels.
    cat_cols = [c for c in cols if types[c] in ("binary", "nominal", "ordinal_candidate", "ordinal_or_nominal_code")]
    long_format = any(h["type"] == "repeated_measures" for h in hints)
    if len(cat_cols) >= 2 and not long_format:
        sets = {c: sorted({value_str(v) for v in data[c].dropna()}, key=sort_key) for c in cat_cols}
        seen = set()
        for c in cat_cols:
            same = [d for d in cat_cols if sets[d] == sets[c]]
            key = "|".join(same)
            if len(same) >= 2 and key not in seen:
                seen.add(key)
                named_like_pairs = sum(bool(PAIR_PATTERN.search(s)) for s in same) >= 2
                text_scale = len(sets[c]) >= 3 and not is_numeric(data[same[0]])
                if not named_like_pairs and not text_scale:
                    continue
                hints.append({
                    "type": "possible_matched_pairs_wide", "columns": same,
                    "evidence": "%s 的類別完全相同（%s）%s" % ("、".join(same), "/".join(sets[c]),
                                                       "，且欄名像前後測或重複測量" if named_like_pairs else ""),
                    "question": "%s 是不是「同一個人」在不同時間或不同題目的回答（配對資料）？還是只是剛好用相同選項的不同變數？" % "、".join(same),
                    "book_ref": "§8.1"})

    # 3. Aggregated data: a frequency column means each row is a cell, not a subject.
    freq_cols = [c for c in cols if types[c] == "frequency_weight"]
    if freq_cols:
        hints.append({
            "type": "aggregated_counts", "columns": freq_cols,
            "evidence": "%s 看起來是次數欄，每一列可能代表一個格子而不是一個人" % "、".join(freq_cols),
            "question": "%s 是否代表「這種組合有幾個人」？" % "、".join(freq_cols),
            "book_ref": "§3.2.5, §5.2.3"})

    return {
        "n_rows": len(data), "hints": hints,
        "default": "independent" if not hints else "needs_confirmation",
        "note": "資料本身無法證明觀察值彼此獨立。第 1–7 章的方法都假設獨立（§1.1.3），請使用者確認每一列是否為不同的獨立個體。",
    }


def cda_profile(data):
    variables = [profile_variable(data[c], c) for c in data.columns]
    return {"n_rows": len(data), "n_cols": data.shape[1], "variables": variables,
            "structure": detect_structure(data, variables)}

# ---------------------------------------------------------------- formatting

def fmt_num(x, digits=2):
    return "%.*f" % (digits, x)


def fmt_count(x):
    x = float(x)
    return "{:,}".format(int(x)) if x.is_integer() else "{:,}".format(x)


def fmt_pct(p):
    return "%.1f%%" % (p * 100)


TYPE_LABEL = {
    "binary": "二元", "nominal": "名目", "ordinal_candidate": "可能有序",
    "ordinal_or_nominal_code": "數字代碼（有序或名目？）", "continuous": "連續",
    "count_or_continuous": "計數或連續", "frequency_weight": "次數欄", "id": "識別碼",
    "nominal_many_levels": "類別很多的文字", "empty": "全部缺失",
}


def weighted_counts(series, weights=None):
    """Counts per value (sorted like R), weighted when the data are aggregated."""
    if isinstance(series.dtype, pd.CategoricalDtype):
        order = list(series.cat.categories)       # keep the order the user or recode set
    else:
        order = sorted(series.dropna().unique(), key=sort_key)
    if weights is None:
        counts = series.dropna().value_counts()
    else:
        counts = weights[series.notna()].groupby(series.dropna(), observed=False).sum()
    return [(value_str(v), counts.get(v, 0)) for v in order]


def overview_md(data, profile, data_name):
    freq_cols = [v["name"] for v in profile["variables"] if v["type_guess"] == "frequency_weight"]
    w = data[freq_cols[0]] if len(freq_cols) == 1 else None
    rows = []
    for v in profile["variables"]:
        x = data[v["name"]]
        if v["type_guess"] in ("continuous", "count_or_continuous", "frequency_weight"):
            detail = "範圍 %s–%s，平均 %s" % (fmt_num(x.min()), fmt_num(x.max()), fmt_num(x.mean()))
        elif v["type_guess"] in ("id", "nominal_many_levels", "empty"):
            detail = "%d 種值" % v["n_unique"]
        else:
            tab = weighted_counts(x, None if v["name"] in freq_cols else w)
            total = sum(c for _, c in tab)
            detail = "；".join("%s：%s（%s）" % (lv, fmt_count(c), fmt_pct(c / total)) for lv, c in tab)
        rows.append("| %s | %s | %d | %s |" % (v["name"], TYPE_LABEL.get(v["type_guess"], v["type_guess"]),
                                              v["n_missing"], detail))
    lines = ["# 資料總覽：%s" % data_name, "", "## 資料結構", "",
             "- %d 列、%d 欄" % (profile["n_rows"], profile["n_cols"])]
    if w is not None:
        lines.append("- 看起來是**已彙整的次數表**：`%s` 可能是次數欄，合計 %s 個觀察值。下表的次數已用它加權，需要使用者確認。"
                     % (freq_cols[0], fmt_count(w.sum())))
    else:
        lines.append("- 看起來是**一列一筆紀錄**的原始資料（不是次數表）")
    lines += ["- 需要確認：" + h["question"] for h in profile["structure"]["hints"]]
    lines += ["", "## 各變數", "",
              "| 欄位 | 型態（猜測，需確認） | 缺失 | 類別與次數（比例）／數值摘要 |",
              "|---|---|---|---|"] + rows
    return lines

# ---------------------------------------------------------------- recode

def cda_recode(data, recode):
    """Same rules and messages as cda_recode() in R/utils.R."""
    notes = []
    data = data.copy()
    for nm, r in recode.items():
        src_name = r.get("from")
        if src_name is None or src_name not in data.columns:
            raise ValueError("recode：找不到來源欄位 %s" % src_name)
        src = data[src_name]
        if r.get("breaks") is not None:
            br = sorted(float(b) for b in (r["breaks"] if isinstance(r["breaks"], list) else [r["breaks"]]))
            labs = r["labels"]
            if len(labs) != len(br) + 1:
                raise ValueError("recode：%s 的 labels 數目必須比 breaks 多 1。" % nm)
            data[nm] = pd.Categorical(pd.cut(pd.to_numeric(src), [-math.inf] + br + [math.inf],
                                             right=False, labels=labs), categories=labs)
            b = [value_str(v) for v in br]
            ranges = ["< %s" % b[0]] + ["%s – < %s" % (b[i], b[i + 1]) for i in range(len(b) - 1)] + ["≥ %s" % b[-1]]
            notes.append("新變數 %s 由 %s 轉換：%s。" % (nm, src_name, "；".join("%s → %s" % p for p in zip(ranges, labs))))
            notes.append(("提醒：把連續的 %s 切成類別會損失資訊，結論可能隨切點改變；看過資料才挑的切點會造成偏誤。"
                          "如果想知道 %s 越大結果怎麼變，較適合用 logistic 等模型（類別模型 Skill）。") % (src_name, src_name))
        elif r.get("map") is not None:
            m = {str(k): v for k, v in r["map"].items()}
            out = src.map(lambda v: m.get(value_str(v)) if pd.notna(v) else None)
            unmapped = sorted({value_str(v) for v in src[out.isna() & src.notna()]}, key=sort_key)
            if unmapped:
                raise ValueError("recode：%s 的這些值沒有對應：%s" % (src_name, ", ".join(unmapped)))
            cats = list(dict.fromkeys(m.values()))
            data[nm] = pd.Categorical(out, categories=cats)
            notes.append("新變數 %s 由 %s 合併類別：%s。" % (nm, src_name, "；".join("%s → %s" % (k, v) for k, v in m.items())))
        else:
            raise ValueError("recode：%s 需要 breaks（依門檻切分）或 map（合併類別）。" % nm)
    return data, notes

# ---------------------------------------------------------------- stage 2: question check

def as_factor(series, levels=None):
    """Like R factor(): given levels keep their order (other values become missing);
    otherwise the sorted distinct values."""
    if isinstance(series.dtype, pd.CategoricalDtype) and levels is None:
        return series
    s = series.map(lambda v: value_str(v) if pd.notna(v) else None)
    if levels is None:
        levels = sorted({value_str(v) for v in series.dropna()}, key=sort_key)
    levels = [str(l) for l in levels]
    return pd.Categorical(s, categories=levels)


def question_check(data, x, y, z=None, count=None):
    vars_ = [v for v in (x, y, z) if v is not None]
    w_all = pd.Series(1.0, index=data.index) if count is None else data[count].astype(float)
    complete = data[vars_].notna().all(axis=1)
    missing_n = w_all[~complete].sum()
    d = data[complete].copy()
    w = w_all[complete]
    for v in vars_:
        d[v] = as_factor(d[v])
        d[v] = d[v].cat.remove_unused_categories()

    def xtab(dd, ww):
        t = ww.groupby([dd[x], dd[y]], observed=False).sum().unstack(fill_value=0)
        return t.reindex(index=d[x].cat.categories, columns=d[y].cat.categories, fill_value=0)

    tab = xtab(d, w)
    n = tab.values.sum()
    rs, cs = tab.sum(axis=1), tab.sum(axis=0)
    expected = pd.DataFrame([[r * c / n for c in cs] for r in rs])
    num = lambda v: int(v) if float(v).is_integer() else float(v)
    facts = {
        "n": num(n),
        "n_missing_dropped": num(missing_n),
        "n_levels": {v: len(d[v].cat.categories) for v in vars_},
        "table": {"rows": list(tab.index.astype(str)), "cols": list(tab.columns.astype(str)),
                  "counts": [[num(v) for v in row] for row in tab.values]},
        "smallest_group": {"variable": x, "level": str(rs.idxmin()), "n": num(rs.min())},
        "smallest_outcome_category": {"variable": y, "level": str(cs.idxmin()), "n": num(cs.min())},
        "min_expected": float(expected.values.min()),
        "cells_expected_below_5": int((expected.values < 5).sum()),
        "cells_total": int(expected.size),
        "zero_cells": int((tab.values == 0).sum()),
    }
    if z is not None:
        strata = []
        for s in d[z].cat.categories:
            keep = d[z] == s
            t2 = xtab(d[keep], w[keep])
            n2 = t2.values.sum()
            if n2 > 0:
                r2, c2 = t2.sum(axis=1), t2.sum(axis=0)
                e2 = min(r * c / n2 for r in r2 for c in c2)
            else:
                e2 = 0
            strata.append({"stratum": str(s), "n": num(n2), "min_expected": float(e2),
                           "zero_cells": int((t2.values == 0).sum())})
        facts["strata"] = strata
    return facts, d, w, tab

# ---------------------------------------------------------------- plots

def setup_fonts():
    """Use a CJK font if one is installed; otherwise fall back to English axis labels."""
    import matplotlib
    matplotlib.use("Agg")
    from matplotlib import font_manager, rcParams
    wanted = ["Microsoft JhengHei", "Noto Sans CJK TC", "Noto Sans CJK JP", "Noto Sans CJK SC",
              "Noto Sans TC", "PingFang TC", "Heiti TC", "WenQuanYi Zen Hei", "WenQuanYi Micro Hei",
              "Source Han Sans TW", "Droid Sans Fallback"]
    have = {f.name for f in font_manager.fontManager.ttflist}
    found = [f for f in wanted if f in have]
    if found:
        rcParams["font.sans-serif"] = found + list(rcParams["font.sans-serif"])
    rcParams["axes.unicode_minus"] = False
    return bool(found)


def plot_bar(d, var, w, path, cjk):
    import matplotlib.pyplot as plt
    tab = weighted_counts(d[var], w)
    fig, ax = plt.subplots(figsize=(6, 4), dpi=150)
    labels = [lv for lv, _ in tab]
    vals = [c for _, c in tab]
    ax.bar(labels, vals, color="#1f3a5f", width=0.65)
    for i, v in enumerate(vals):
        ax.text(i, v, fmt_count(v), ha="center", va="bottom", fontsize=10)
    ax.set_xlabel(var)
    ax.set_ylabel("次數" if cjk else "Count")
    ax.spines[["top", "right"]].set_visible(False)
    ax.margins(y=0.12)
    fig.tight_layout()
    fig.savefig(path, facecolor="white")
    plt.close(fig)


def plot_relation(d, x, y, w, path, cjk, z=None):
    import matplotlib.pyplot as plt
    colors = ["#66c2a5", "#fc8d62", "#8da0cb", "#e78ac3", "#a6d854", "#ffd92f", "#e5c494", "#b3b3b3"]
    panels = list(d[z].cat.categories) if z else [None]
    ncol = min(3, len(panels))
    nrow = math.ceil(len(panels) / ncol)
    fig, axes = plt.subplots(nrow, ncol, figsize=(9 if z else 6, 4 if not z else 3 * nrow + 1), dpi=150,
                             squeeze=False, sharey=True)
    ylevels = list(d[y].cat.categories)
    for i, p in enumerate(panels):
        ax = axes[i // ncol][i % ncol]
        keep = (d[z] == p) if z else pd.Series(True, index=d.index)
        t = w[keep].groupby([d[x][keep], d[y][keep]], observed=False).sum().unstack(fill_value=0)
        t = t.reindex(index=d[x].cat.categories, columns=ylevels, fill_value=0)
        props = t.div(t.sum(axis=1).replace(0, float("nan")), axis=0).fillna(0)
        bottom = [0.0] * len(props)
        for j, lv in enumerate(ylevels):
            vals = list(props[lv])
            ax.bar([str(v) for v in props.index], vals, bottom=bottom, color=colors[j % len(colors)],
                   width=0.65, edgecolor="white", label=str(lv))
            for k, v in enumerate(vals):
                if v >= 0.04:
                    ax.text(k, bottom[k] + v / 2, "%d%%" % round(v * 100), ha="center", va="center",
                            color="white", fontsize=9)
            bottom = [b + v for b, v in zip(bottom, vals)]
        ax.set_ylim(0, 1)
        ax.yaxis.set_major_formatter(lambda v, _: "%d%%" % round(v * 100))
        ax.spines[["top", "right"]].set_visible(False)
        if z:
            ax.set_title("%s: %s" % (z, p), fontsize=10)
        ax.set_xlabel(x)
    for j in range(len(panels), nrow * ncol):
        axes[j // ncol][j % ncol].axis("off")
    axes[0][0].set_ylabel(("各組內 %s 的比例" % y) if cjk else ("Proportion of %s within group" % y))
    handles, labels = axes[0][0].get_legend_handles_labels()
    fig.legend(handles, labels, title=y, loc="center right")
    fig.tight_layout(rect=(0, 0, 0.85, 1))
    fig.savefig(path, facecolor="white")
    plt.close(fig)

# ---------------------------------------------------------------- output helpers

def write_json(obj, path):
    with open(path, "w", encoding="utf-8") as f:
        json.dump(obj, f, ensure_ascii=False, indent=2)


def write_lines(lines, path):
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")


def data_stem(path):
    return os.path.splitext(os.path.basename(path))[0]
