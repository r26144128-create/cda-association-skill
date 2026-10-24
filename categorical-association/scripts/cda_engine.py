"""Python version of the analysis engine (R/association.R) for environments without R.

Used by run_analysis.py on claude.ai, where only Python is available. Every function
mirrors its R counterpart, including the wording of facts and warnings, so that the two
give the same result.json; dev/tests/test-python.R compares them on many cases.
"""

import math

import numpy as np
import pandas as pd
from scipy import stats

import cda_describe as cd


class CdaError(Exception):
    """An analysis that cannot be done; the message is shown to the user."""


# ---------------------------------------------------------------- formatting (R/utils.R)

def fmt_num(x, digits=3):
    x = float(x)
    if math.isnan(x):
        return "NaN"
    if math.isinf(x):
        return "Inf" if x > 0 else "-Inf"
    return "%.*f" % (digits, x)


def fmt_p(p):
    if p is None or (isinstance(p, float) and math.isnan(p)):
        return "NA"
    if p < 0.001:
        return "< 0.001"
    return "%.3f" % p


def percent(x, accuracy=0.1):
    """scales::percent(x, accuracy): round to the accuracy, keep its decimals."""
    digits = max(0, -int(math.floor(math.log10(accuracy) + 1e-9)))
    v = round(x * 100 / accuracy) * accuracy
    return "{:,.{d}f}%".format(v, d=digits)


def num_str(v):
    """as.character() of a number: 1 -> '1', 3.5 -> '3.5'."""
    v = float(v)
    if v.is_integer():
        return str(int(v))
    return "%.15g" % v


def warning(code, message, book_ref):
    return {"code": code, "message": message, "book_ref": book_ref}


def div(a, b):
    """R-style division: x/0 is Inf (or NaN for 0/0)."""
    with np.errstate(divide="ignore", invalid="ignore"):
        return float(np.float64(a) / np.float64(b))


# ---------------------------------------------------------------- data preparation

def prepare_categorical(data, vars_, count=None):
    cols = list(vars_) + ([count] if count else [])
    complete = data[cols].notna().all(axis=1)
    w = data[count].astype(float) if count else pd.Series(1.0, index=data.index)
    warnings, facts = [], []
    if (~complete).any():
        n_drop = w[~complete].sum(skipna=True)
        share = n_drop / w.sum(skipna=True)
        facts.append("因 %s 有缺失，排除 %s 個觀察值（占 %s）。" % ("/".join(vars_), cd.fmt_count(n_drop),
                                                       percent(share, 0.1)))
        if share >= 0.2:
            warnings.append(warning(
                "MISSING_HIGH",
                "缺失比例 %s（≥ 20%%），結果可能高度受缺失影響。是否有偏誤取決於缺失的原因，"
                "光看比例無法判斷；請說明資料為什麼缺失。" % percent(share, 0.1), "§9.5.1"))
        elif share >= 0.05:
            warnings.append(warning(
                "MISSING_DROPPED",
                "缺失比例 %s（≥ 5%%），可能影響結果。是否有偏誤取決於缺失的原因"
                "（例如某些人比較不會回答），光看比例無法判斷。" % percent(share, 0.1), "§9.5.1"))
    d = data[complete].copy()
    wd = w[complete]
    for v in vars_:
        d[v] = cd.as_factor(d[v])
        totals = wd.groupby(d[v], observed=False).sum(min_count=1)
        counts = d[v].value_counts()
        empty = [str(lv) for lv in d[v].cat.categories
                 if counts.get(lv, 0) == 0 or pd.isna(totals.get(lv)) or totals.get(lv) == 0]
        if empty:
            warnings.append(warning(
                "EMPTY_CATEGORY",
                "%s 的類別「%s」沒有任何觀察值（整列或整欄都是 0），已從分析中移除。" % (v, "」「".join(empty)),
                "§2.3.3"))
            keep = ~d[v].astype(str).isin(empty)
            d, wd = d[keep], wd[keep]
        d[v] = d[v].cat.remove_unused_categories()
    return d, wd, warnings, facts


def xtab(d, w, x, y):
    t = w.groupby([d[x], d[y]], observed=False).sum().unstack(fill_value=0)
    t = t.reindex(index=d[x].cat.categories, columns=d[y].cat.categories, fill_value=0)
    t.index = [str(i) for i in t.index]
    t.columns = [str(c) for c in t.columns]
    return t.astype(float)


def sparse_table(expected):
    e = np.asarray(expected, dtype=float)
    n_low = int((e < 5).sum())
    share = n_low / e.size
    sparse = (e.min() < 5) if e.shape == (2, 2) else (e.min() < 1 or share > 0.2)
    return {"sparse": bool(sparse), "min": float(e.min()), "n_low": n_low, "n_cells": int(e.size), "share": share}


def sparse_message(sp):
    return ("期望次數最小為 %s，有 %d / %d 格（%s）小於 5：依 Cochran 準則，Pearson 卡方的大樣本近似可能不可靠，"
            "建議以 Fisher 精確檢定為主。" % (fmt_num(sp["min"], 2), sp["n_low"], sp["n_cells"], percent(sp["share"], 1)))


def small_group_reminder(tab, x, limit=10):
    sizes = tab.sum(axis=1)
    small = sizes[sizes < limit]
    if len(small) == 0:
        return []
    return [warning(
        "SMALL_GROUP",
        "%s 有人數很少的組：%s。這是估計穩定性的提醒，不代表方法不能用："
        "這些組的比例與比例差、相對風險、勝算比的信賴區間會很寬，請搭配次數表、期望次數與信賴區間一起判斷。"
        % (x, "、".join("%s（%s 個）" % (k, num_str(v)) for k, v in small.items())), "§2.2.1")]


def chisq(tab):
    o = tab.values
    n = o.sum()
    rs, cs = o.sum(axis=1), o.sum(axis=0)
    e = np.outer(rs, cs) / n
    x2 = float(((o - e) ** 2 / e).sum())
    df = (o.shape[0] - 1) * (o.shape[1] - 1)
    v = np.outer(rs, cs) * np.outer(n - rs, n - cs) / n ** 3
    stdres = (o - e) / np.sqrt(v)
    return {"statistic": x2, "df": df, "p": float(stats.chi2.sf(x2, df)), "expected": e, "stdres": stdres}

# ---------------------------------------------------------------- Fisher's exact test

def fisher_2x2(tab):
    """fisher.test(), two-sided, for a 2x2 table (same tie rule as R)."""
    o = tab.values
    x = int(round(o[0, 0]))
    m, n, k = int(round(o[0].sum())), int(round(o[1].sum())), int(round(o[:, 0].sum()))
    lo, hi = max(0, k - n), min(k, m)
    support = np.arange(lo, hi + 1)
    logdc = stats.hypergeom.logpmf(support, m + n, m, k)
    d = np.exp(logdc - logdc.max())
    d = d / d.sum()
    return float(d[d <= d[x - lo] * (1 + 1e-7)].sum())


def _log_table_prob(cells, rs, cs, n):
    from math import lgamma
    return (sum(lgamma(r + 1) for r in rs) + sum(lgamma(c + 1) for c in cs) - lgamma(n + 1)
            - sum(lgamma(v + 1) for v in cells))


def fisher_rxc(tab, cap=2_000_000):
    """Exact r x c test by enumerating tables; falls back to simulation like R."""
    o = np.rint(tab.values).astype(int)
    rs, cs, n = list(o.sum(axis=1)), list(o.sum(axis=0)), int(o.sum())
    r, c = o.shape
    p_obs = _log_table_prob(o.ravel(), rs, cs, n)
    tol = p_obs + math.log1p(1e-7)
    total, count = 0.0, [0]

    def fill(col, row_left, cells):
        if count[0] > cap:
            raise OverflowError
        if col == c - 1:
            last = list(row_left)
            lp = _log_table_prob(cells + last, rs, cs, n)
            count[0] += 1
            return math.exp(lp) if lp <= tol else 0.0
        acc = 0.0

        def col_fill(i, left, col_cells):
            nonlocal acc
            if i == r - 1:
                if left <= row_left[i]:
                    new_left = [row_left[j] - col_cells[j] for j in range(r - 1)] + [row_left[r - 1] - left]
                    acc += fill(col + 1, new_left, cells + col_cells + [left])
                return
            for v in range(min(left, row_left[i]) + 1):
                if left - v <= sum(row_left[i + 1:]):
                    col_fill(i + 1, left - v, col_cells + [v])

        col_fill(0, cs[col], [])
        return acc

    # cells are collected column by column; probabilities do not depend on the order
    try:
        total = fill(0, rs, [])
        return min(1.0, total), "Fisher's Exact Test for Count Data"
    except OverflowError:
        rng = np.random.default_rng(20261030)
        sims = stats.random_table(rs, cs, seed=rng).rvs(100000)
        lps = np.array([_log_table_prob(t.ravel(), rs, cs, n) for t in sims])
        p = (1 + (lps <= tol).sum()) / (100000 + 1)
        return float(p), "Fisher's Exact Test for Count Data with simulated p-value\n\t (based on 1e+05 replicates)"

# ---------------------------------------------------------------- score intervals (PropCIs)

def _z2stat(p1x, nx, p1y, ny, dif):
    diff = p1x - p1y - dif
    if abs(diff) == 0:
        return 0.0
    t = ny / nx
    a = 1 + t
    b = -(1 + t + p1x + t * p1y + dif * (t + 2))
    c = dif * dif + dif * (2 * p1x + t + 1) + p1x + t * p1y
    d = -p1x * dif * (1 + dif)
    v = (b / a / 3) ** 3 - b * c / (6 * a * a) + d / a / 2
    s = math.sqrt((b / a / 3) ** 2 - c / a / 3)
    u = s if v > 0 else -s
    w = (3.141592654 + math.acos(max(-1.0, min(1.0, v / u ** 3)))) / 3
    p1d = 2 * u * math.cos(w) - b / a / 3
    p2d = p1d - dif
    nxy = nx + ny
    var = (p1d * (1 - p1d) / nx + p2d * (1 - p2d) / ny) * nxy / (nxy - 1)
    return diff ** 2 / var


def diffscoreci(x1, n1, x2, n2, conf_level):
    px, py = x1 / n1, x2 / n2
    z = stats.chi2.ppf(conf_level, 1)
    proot, dp, niter, ul = px - py, 1 - (px - py), 1, None
    while niter <= 50:
        dp = 0.5 * dp
        up2 = proot + dp
        score = _z2stat(px, n1, py, n2, up2)
        if score < z:
            proot = up2
        niter += 1
        if dp < 1e-07 or abs(z - score) < 1e-06:
            niter, ul = 51, up2
    proot, dp, niter, ll = px - py, 1 + (px - py), 1, None
    while niter <= 50:
        dp = 0.5 * dp
        low2 = proot - dp
        score = _z2stat(px, n1, py, n2, low2)
        if score < z:
            proot = low2
        niter += 1
        if dp < 1e-07 or abs(z - score) < 1e-06:
            ll, niter = low2, 51
    return ll, ul


def riskscoreci(x1, n1, x2, n2, conf_level):
    z = abs(stats.norm.ppf((1 - conf_level) / 2))
    if x2 == 0 and x1 == 0:
        return 0.0, math.inf
    a1 = n2 * (n2 * (n2 + n1) * x1 + n1 * (n2 + x1) * (z ** 2))
    a2 = -n2 * (n2 * n1 * (x2 + x1) + 2 * (n2 + n1) * x2 * x1 + n1 * (n2 + x2 + 2 * x1) * (z ** 2))
    a3 = 2 * n2 * n1 * x2 * (x2 + x1) + (n2 + n1) * (x2 ** 2) * x1 + n2 * n1 * (x2 + x1) * (z ** 2)
    a4 = -n1 * (x2 ** 2) * (x2 + x1)
    b1, b2, b3 = a2 / a1, a3 / a1, a4 / a1
    c1 = b2 - (b1 ** 2) / 3
    c2 = b3 - b1 * b2 / 3 + 2 * (b1 ** 3) / 27
    ceta = math.acos(max(-1.0, min(1.0, math.sqrt(27) * c2 / (2 * c1 * math.sqrt(-c1)))))
    t1 = -2 * math.sqrt(-c1 / 3) * math.cos(math.pi / 3 - ceta / 3)
    t2 = -2 * math.sqrt(-c1 / 3) * math.cos(math.pi / 3 + ceta / 3)
    t3 = 2 * math.sqrt(-c1 / 3) * math.cos(ceta / 3)
    p01, p02, p03 = t1 - b1 / 3, t2 - b1 / 3, t3 - b1 / 3
    p0sum = p01 + p02 + p03
    p0up = min(p01, p02, p03)
    p0low = p0sum - p0up - max(p01, p02, p03)

    def bound(p0):
        return (1 - (n1 - x1) * (1 - p0) / (x2 + n1 - (n2 + n1) * p0)) / p0

    if x2 == 0 and x1 != 0:
        return bound(p0low), math.inf
    if x2 != n2 and x1 == 0:
        return 0.0, bound(p0up)
    if x2 == n2 and x1 == n1:
        return n1 / (n1 + z ** 2), (n2 + z ** 2) / n2
    if x1 == n1 or x2 == n2:
        ll = ul = None
        if x2 == n2 and x1 == 0:
            ll = 0.0
        if x2 == n2 and x1 != 0:
            phihat = (x1 / n1) / (x2 / n2)
            phil, chi2 = 0.95 * phihat, 0.0
            while chi2 <= z:
                a = (n2 + n1) * phil
                b = -((x2 + n1) * phil + x1 + n2)
                c = x2 + x1
                p1hat = (-b - math.sqrt(b ** 2 - 4 * a * c)) / (2 * a)
                p2hat = p1hat * phil
                q2hat = 1 - p2hat
                var = (n2 * n1 * p2hat) / (n1 * (phil - p2hat) + n2 * q2hat)
                chi2 = ((x1 - n1 * p2hat) / q2hat) / math.sqrt(var)
                ll = phil
                phil = ll / 1.0001
        i, j, ni, nj = x2, x1, n2, n1
        if x1 == n1:
            i, j, ni, nj = x1, x2, n1, n2
        phihat = (j / nj) / (i / ni)
        phiu = 1.1 * phihat
        if x2 == n2 and x1 == 0:
            phiu = 0.01 if n2 < 100 else 0.001
        chi1, phiu1 = 0.0, phiu
        while chi1 >= -z:
            a = (ni + nj) * phiu
            b = -((i + nj) * phiu + j + ni)
            c = i + j
            p1hat = (-b - math.sqrt(b ** 2 - 4 * a * c)) / (2 * a)
            p2hat = p1hat * phiu
            q2hat = 1 - p2hat
            var = (ni * nj * p2hat) / (nj * (phiu - p2hat) + ni * q2hat)
            chi1 = ((j - nj * p2hat) / q2hat) / math.sqrt(var)
            phiu1 = phiu
            phiu = 1.0001 * phiu1
        if x1 == n1:
            return 1 / phiu1, bound(p0up)
        return ll, phiu1
    return bound(p0low), bound(p0up)


def _or_limit(x, nx, y, ny, conflev, lim, t):
    z = stats.chi2.ppf(conflev, 1)
    px = x / nx
    score, ci = 0.0, lim
    while score < z:
        a = ny * (lim - 1)
        b = nx * lim + ny - (x + y) * (lim - 1)
        c = -(x + y)
        p2d = (-b + math.sqrt(b ** 2 - 4 * a * c)) / (2 * a)
        p1d = p2d * lim / (1 + p2d * (lim - 1))
        score = ((nx * (px - p1d)) ** 2) * (1 / (nx * p1d * (1 - p1d)) + 1 / (ny * p2d * (1 - p2d))) \
            * (nx + ny - 1) / (nx + ny)
        ci = lim
        lim = ci / 1.001 if t == 0 else ci * 1.001
    return ci


def orscoreci(x1, n1, x2, n2, conf_level):
    px, py = x1 / n1, x2 / n2
    if (x1 == 0 and x2 == 0) or (x1 == n1 and x2 == n2):
        return 0.0, math.inf
    if x1 == 0 or x2 == n2:
        return 0.0, _or_limit(x1, n1, x2, n2, conf_level, 0.01 / n2, 1)
    if x1 == n1 or x2 == 0:
        return _or_limit(x1, n1, x2, n2, conf_level, 100 * n1, 0), math.inf
    theta = px / (1 - px) / (py / (1 - py))
    return (_or_limit(x1, n1, x2, n2, conf_level, theta / 1.1, 0),
            _or_limit(x1, n1, x2, n2, conf_level, theta * 1.1, 1))

# ---------------------------------------------------------------- logistic model (glm)

def glm_binomial(X, succ, fail, offset=None, maxit=25, epsilon=1e-8):
    """IRLS for a binomial GLM with counts, as R's glm.fit (logit link)."""
    m = succ + fail
    keep = m > 0
    X, succ, m = X[keep], succ[keep], m[keep]
    off = np.zeros(len(m)) if offset is None else offset[keep]
    y = succ / m
    mu = (m * y + 0.5) / (m + 1)
    eta = np.log(mu / (1 - mu))
    dev_old = np.inf
    beta = np.zeros(X.shape[1])

    def deviance(mu_):
        with np.errstate(divide="ignore", invalid="ignore"):
            t1 = np.where(y > 0, y * np.log(y / mu_), 0.0)
            t2 = np.where(y < 1, (1 - y) * np.log((1 - y) / (1 - mu_)), 0.0)
        return float(2 * (m * (t1 + t2)).sum())

    for _ in range(maxit):
        mu_eta = mu * (1 - mu)
        z = (eta - off) + (y - mu) / mu_eta
        wts = m * mu_eta
        XtW = X.T * wts
        beta = np.linalg.solve(XtW @ X, XtW @ z)
        eta = X @ beta + off
        mu = 1 / (1 + np.exp(-eta))
        dev = deviance(mu)
        if abs(dev - dev_old) / (abs(dev) + 0.1) < epsilon:
            break
        dev_old = dev
    wts = m * mu * (1 - mu)
    vcov = np.linalg.inv((X.T * wts) @ X)
    return {"coef": beta, "deviance": dev, "vcov": vcov, "df_residual": int(keep.sum()) - X.shape[1]}


def _fmm_spline(x, y):
    """Forsythe-Malcolm-Moler cubic spline coefficients, as R's spline(method = "fmm")."""
    n = len(x)
    b, c, d = np.zeros(n), np.zeros(n), np.zeros(n)
    if n < 3:
        t = (y[1] - y[0]) / (x[1] - x[0])
        b[:] = t
        return b, c, d
    nm1 = n - 1
    d[0] = x[1] - x[0]
    c[1] = (y[1] - y[0]) / d[0]
    for i in range(1, nm1):
        d[i] = x[i + 1] - x[i]
        b[i] = 2.0 * (d[i - 1] + d[i])
        c[i + 1] = (y[i + 1] - y[i]) / d[i]
        c[i] = c[i + 1] - c[i]
    b[0] = -d[0]
    b[nm1] = -d[n - 2]
    c[0] = c[nm1] = 0.0
    if n > 3:
        c[0] = c[2] / (x[3] - x[1]) - c[1] / (x[2] - x[0])
        c[nm1] = c[n - 2] / (x[nm1] - x[n - 3]) - c[n - 3] / (x[n - 2] - x[n - 4])
        c[0] = c[0] * d[0] * d[0] / (x[3] - x[0])
        c[nm1] = -c[nm1] * d[n - 2] * d[n - 2] / (x[nm1] - x[n - 4])
    for i in range(1, n):
        t = d[i - 1] / b[i - 1]
        b[i] = b[i] - t * d[i - 1]
        c[i] = c[i] - t * c[i - 1]
    c[nm1] = c[nm1] / b[nm1]
    for i in range(n - 2, -1, -1):
        c[i] = (c[i] - d[i] * c[i + 1]) / b[i]
    b[nm1] = (y[nm1] - y[n - 2]) / d[n - 2] + d[n - 2] * (c[n - 2] + 2.0 * c[nm1])
    for i in range(nm1):
        b[i] = (y[i + 1] - y[i]) / d[i] - d[i] * (c[i + 1] + 2.0 * c[i])
        d[i] = (c[i + 1] - c[i]) / d[i]
        c[i] = 3.0 * c[i]
    c[nm1] = 3.0 * c[nm1]
    d[nm1] = d[n - 2]
    return b, c, d


def _spline_eval(x, y, b, c, d, u):
    i = np.clip(np.searchsorted(x, u, side="right") - 1, 0, len(x) - 1)
    dx = u - x[i]
    return y[i] + dx * (b[i] + dx * (c[i] + dx * d[i]))


def profile_ci(X, succ, fail, j, fit, conf_level):
    """confint() of glm coefficient j: R's profile.glm + spline/approx interpolation."""
    alpha = (1 - conf_level) / 4
    zmax = math.sqrt(stats.chi2.ppf(1 - alpha, 1))
    delta = zmax / 5
    se = math.sqrt(fit["vcov"][j, j])
    b0 = fit["coef"][j]
    Xi = np.delete(X, j, axis=1)
    zs, pars = [0.0], [b0]
    for sgn in (-1, 1):
        step, z = 0, 0.0
        while True:
            step += 1
            if not (step < 10 and abs(z) < zmax):
                break
            bi = b0 + sgn * step * delta * se
            fm = glm_binomial(Xi, succ, fail, offset=X[:, j] * bi)
            zz = fm["deviance"] - fit["deviance"]
            if zz > -0.001:
                zz = max(zz, 0.0)
            else:
                raise CdaError("profiling found a better solution")
            z = sgn * math.sqrt(zz)
            zs.append(z)
            pars.append(bi)
    order = np.argsort(zs, kind="stable")
    px = np.array(pars)[order]
    pz = np.array(zs)[order]
    # spline(x = par, y = z): sorted unique x, n = 3 * length(x) points
    ox = np.argsort(px, kind="stable")
    sx, sy = px[ox], pz[ox]
    ux, idx = np.unique(sx, return_index=True)
    uy = np.array([sy[sx == v].mean() for v in ux])
    b, c, d = _fmm_spline(ux, uy)
    xout = np.linspace(ux[0], ux[-1], 3 * len(px))
    yout = _spline_eval(ux, uy, b, c, d, xout)
    # approx(sp$y, sp$x, xout = cutoff): sort by y, average ties, linear, NA outside
    oy = np.argsort(yout, kind="stable")
    ay, ax = yout[oy], xout[oy]
    uay = np.unique(ay)
    uax = np.array([ax[ay == v].mean() for v in uay])
    out = []
    for cut in (stats.norm.ppf((1 - conf_level) / 2), stats.norm.ppf(1 - (1 - conf_level) / 2)):
        out.append(float(np.interp(cut, uay, uax)) if uay[0] <= cut <= uay[-1] else float("nan"))
    return out

# ---------------------------------------------------------------- analyses

def cda_crosstab(data, x, y, count=None, success=None, ordinal=(), design="unknown", conf_level=0.95):
    if design not in ("unknown", "cohort", "cross-sectional", "experiment", "case-control"):
        raise CdaError("'arg' should be one of “unknown”, “cohort”, “cross-sectional”, "
                       "“experiment”, “case-control”")
    facts = []
    d, w, warnings, prep_facts = prepare_categorical(data, [x, y], count)
    tab = xtab(d, w, x, y)
    n = tab.values.sum()
    r, c = tab.shape
    if r < 2 or c < 2:
        raise CdaError("每個變數至少要有 2 個類別才能分析關聯。")
    ch = chisq(tab)
    o, e = tab.values, ch["expected"]
    with np.errstate(divide="ignore", invalid="ignore"):
        g2 = float(2 * np.where(o > 0, o * np.log(o / e), 0.0).sum())
    df = ch["df"]
    tests = [
        {"test": "Pearson X2", "statistic": ch["statistic"], "df": df, "p_value": ch["p"], "book_ref": "§2.4.3"},
        {"test": "Likelihood-ratio G2", "statistic": g2, "df": df,
         "p_value": float(stats.chi2.sf(g2, df)), "book_ref": "§2.4.3"}]
    facts += ["樣本數 n = %d；%s 有 %d 類，%s 有 %d 類。" % (int(n), x, r, y, c),
              "Pearson 卡方 X² = %s（df = %d），P = %s；概似比 G² = %s。"
              % (fmt_num(ch["statistic"], 2), df, fmt_p(ch["p"]), fmt_num(g2, 2))]
    sp = sparse_table(e)
    facts.append("獨立假設下的期望次數最小為 %s；小於 5 的格子 %d / %d。" % (fmt_num(sp["min"], 2), sp["n_low"], sp["n_cells"]))
    if sp["sparse"]:
        warnings.append(warning("LOW_EXPECTED", sparse_message(sp), "§2.4.7"))
    if r == 2 and c == 2:
        fp = fisher_2x2(tab)
        tests.append({"test": "Fisher exact (two-sided)", "statistic": None, "df": None, "p_value": fp, "book_ref": "§2.6"})
        facts.append("Fisher 精確檢定雙尾 P = %s。" % fmt_p(fp))
    elif sp["sparse"]:
        fp, method = fisher_rxc(tab)
        tests.append({"test": "Fisher exact: " + method, "statistic": None, "df": None, "p_value": fp, "book_ref": "§2.6"})
        facts.append("Fisher 精確檢定 P = %s。" % fmt_p(fp))

    warnings += small_group_reminder(tab, x)

    stdres = ch["stdres"]
    big = [(i, j) for j in range(c) for i in range(r) if abs(stdres[i, j]) > 2]   # column-major, as which()
    if r == 2 and c == 2:
        big = [ij for ij in big if ij == (0, 0)]
    if big:
        big.sort(key=lambda ij: -abs(stdres[ij]))
        cells = ["%s=%s、%s=%s（%s，實際次數比獨立時預期的%s）" % (
            x, tab.index[i], y, tab.columns[j], fmt_num(stdres[i, j], 2), "多" if stdres[i, j] > 0 else "少")
            for i, j in big]
        prefix = "2×2 表四格的標準化殘差絕對值相同，以其中一格為代表：" if (r == 2 and c == 2) else "標準化殘差絕對值大於 2 的格子："
        facts.append(prefix + "；".join(cells) + "。")
    else:
        facts.append("所有格子的標準化殘差絕對值都不超過 2。")

    estimates = []
    if r == 2 and c == 2:
        s = tab.columns[0] if success is None else str(success)
        if s not in tab.columns:
            raise CdaError("success 必須是 %s 的其中一個類別。" % y)
        fail = [k for k in tab.columns if k != s][0]
        x1, n1 = tab.iloc[0][s], tab.iloc[0].sum()
        x2, n2 = tab.iloc[1][s], tab.iloc[1].sum()
        p1, p2 = x1 / n1, x2 / n2
        g1, g2name = tab.index[0], tab.index[1]
        orr = div(tab.iloc[0][s] * tab.iloc[1][fail], tab.iloc[0][fail] * tab.iloc[1][s])
        or_ci = orscoreci(x1, n1, x2, n2, conf_level)
        estimates = [{"measure": "odds ratio", "estimate": orr, "lower": or_ci[0], "upper": or_ci[1],
                      "ci_method": "score", "book_ref": "§2.3.3"}]
        pct_conf = int(round(conf_level * 100))
        if design != "case-control":
            diff_ci = diffscoreci(x1, n1, x2, n2, conf_level)
            rr_ci = riskscoreci(x1, n1, x2, n2, conf_level)
            rr = div(p1, p2)
            estimates = [
                {"measure": "difference of proportions", "estimate": p1 - p2, "lower": diff_ci[0], "upper": diff_ci[1],
                 "ci_method": "score", "book_ref": "§2.2.2"},
                {"measure": "relative risk", "estimate": rr, "lower": rr_ci[0], "upper": rr_ci[1],
                 "ci_method": "score", "book_ref": "§2.2.3"}] + estimates
            facts += ["%s=%s 的比例：%s 組為 %s（%d/%d），%s 組為 %s（%d/%d）。" % (
                          y, s, g1, fmt_num(p1), int(x1), int(n1), g2name, fmt_num(p2), int(x2), int(n2)),
                      "比例差（%s − %s）= %s，%d%% CI [%s, %s]。" % (
                          g1, g2name, fmt_num(p1 - p2, 4), pct_conf, fmt_num(diff_ci[0], 4), fmt_num(diff_ci[1], 4)),
                      "相對風險 RR（%s / %s）= %s，%d%% CI [%s, %s]。" % (
                          g1, g2name, fmt_num(rr, 2), pct_conf, fmt_num(rr_ci[0], 2), fmt_num(rr_ci[1], 2))]
        else:
            warnings.append(warning(
                "CASE_CONTROL", "case-control 研究中結果的比例由研究設計決定，不能估計比例差或相對風險，只能報告勝算比。", "§2.3.5"))
        facts.append("勝算比 OR（%s 相對於 %s，%s=%s 的勝算）= %s，%d%% CI [%s, %s]。" % (
            g1, g2name, y, s, fmt_num(orr, 2), pct_conf, fmt_num(or_ci[0], 2), fmt_num(or_ci[1], 2)))
        if (o == 0).any():
            zero = [(i, j) for j in range(c) for i in range(r) if o[i, j] == 0]
            warnings.append(warning(
                "ZERO_CELL",
                "次數為 0 的格子：%s。勝算比或相對風險可能變成 0、∞、無法計算或非常不穩定，"
                "實際影響取決於是哪一格為 0，請看原始次數表。這裡不使用 Wald 信賴區間，"
                "改用 score 信賴區間，也沒有加 0.5 修正。" % "；".join(
                    "%s=%s、%s=%s" % (x, tab.index[i], y, tab.columns[j]) for i, j in zero), "§2.3.3"))
        if max(p1, p2) > 0.2 and design != "case-control":
            warnings.append(warning("OR_NOT_RR", "比例不算小，勝算比不能當成相對風險來解釋（「幾倍的機率」要看 RR）。", "§2.3.4"))

    if set(ordinal) & {x, y}:
        warnings.append(warning(
            "ORDINAL_IGNORED", "卡方檢定把變數當成無順序（nominal），忽略了類別順序；有序變數可以用檢定力較高的趨勢檢定（M²）。",
            "§2.4.7, §2.5"))

    return {
        "method": "crosstab", "method_label": "列聯表分析：卡方獨立性檢定（chi-squared test of independence）",
        "book_ref": "§2.1–2.4, §2.6", "tier": "A", "estimates": estimates, "tests": tests,
        "tables": {"counts": tab, "expected": _round_table(tab, e, 2),
                   "row_proportions": _round_table(tab, o / o.sum(axis=1, keepdims=True), 4),
                   "standardized_residuals": _round_table(tab, stdres, 2)},
        "warnings": warnings, "facts": prep_facts + facts,
        "notes": {"variables": {"x": x, "y": y},
                  "reminder": "卡方檢定只回答「有沒有證據顯示有關聯」，不代表關聯有多強；強度要看比例、勝算比與殘差（§2.4.7）。"}}


def _round_table(tab, values, digits):
    return pd.DataFrame(np.round(values, digits), index=tab.index, columns=tab.columns)


def m2_statistic(tab, u, v):
    p = tab.values / tab.values.sum()
    pr, pc = p.sum(axis=1), p.sum(axis=0)
    u, v = np.asarray(u, float), np.asarray(v, float)
    ubar, vbar = (u * pr).sum(), (v * pc).sum()
    r = float((np.outer(u - ubar, v - vbar) * p).sum() / math.sqrt(((u - ubar) ** 2 * pr).sum() * ((v - vbar) ** 2 * pc).sum()))
    m2 = (tab.values.sum() - 1) * r ** 2
    return {"r": r, "m2": float(m2), "p": float(stats.chi2.sf(m2, 1))}


def cda_trend(data, x, y, count=None, ordinal=(), x_scores=None, y_scores=None, success=None):
    d, w, warnings, prep_facts = prepare_categorical(data, [x, y], count)
    tab = xtab(d, w, x, y)
    r, c = tab.shape
    if r < 2 or c < 2:
        raise CdaError("每個變數至少要有 2 個類別。")
    is_ord = lambda v: v in ordinal
    if c == 2:
        if r == 2:
            raise CdaError("X 與 Y 都只有 2 類，這是 2×2 表，請改用列聯表分析（crosstab）。")
        if not is_ord(x):
            raise CdaError("%s 沒有經使用者確認為有序變數。Cochran–Armitage 趨勢檢定需要 X 有自然順序（§2.5.5）；"
                           "名目變數請改用列聯表分析（crosstab）。" % x)
        trend_type = "cochran_armitage"
    else:
        if r == 2 and not is_ord(x):
            raise CdaError("%s 是二元名目變數、%s 是有序變數：本 Skill 第一版不對這種情況做趨勢檢定，"
                           "需要先確認分析目的。可以先用列聯表分析（crosstab）看有沒有關聯。" % (x, y))
        not_ord = [v for v in (x, y) if not is_ord(v)]
        if not_ord:
            raise CdaError("%s 沒有經使用者確認為有序變數。Linear-by-linear association 檢定需要 X 與 Y 都有自然順序（§2.5.1）；"
                           "名目變數請改用列聯表分析（crosstab）。" % "、".join(not_ord))
        trend_type = "linear_by_linear"
    custom = x_scores is not None or y_scores is not None
    u = list(range(1, r + 1)) if x_scores is None else [float(s) for s in x_scores]
    s = None
    if c == 2:
        s = tab.columns[0] if success is None else str(success)
        if s not in tab.columns:
            raise CdaError("success 必須是 %s 的其中一個類別。" % y)
        v = [1.0 if col == s else 0.0 for col in tab.columns]
    else:
        v = list(range(1, c + 1)) if y_scores is None else [float(t) for t in y_scores]
    if len(u) != r or len(v) != c:
        raise CdaError("分數的個數必須等於類別數。")
    if any(np.diff(u) < 0) or (c > 2 and any(np.diff(v) < 0)):
        raise CdaError("分數必須依類別順序遞增（§2.5.1）。")

    main = m2_statistic(tab, u, v)
    ch = chisq(tab)
    ca = trend_type == "cochran_armitage"
    label = "Cochran–Armitage 趨勢檢定（M²）" if ca else "Linear-by-linear association 檢定（M²）"
    test_name = "Cochran-Armitage trend (M2)" if ca else "Linear-by-linear association (M2)"
    dfx = (r - 1) * (c - 1)
    tests = [{"test": test_name, "statistic": main["m2"], "df": 1, "p_value": main["p"], "book_ref": "§2.5.1"},
             {"test": "Pearson X2 (ignores order)", "statistic": ch["statistic"], "df": dfx, "p_value": ch["p"],
              "book_ref": "§2.4.3"}]
    m = math.copysign(math.sqrt(main["m2"]), main["r"]) if main["r"] != 0 else 0.0
    us = ", ".join(num_str(t) for t in u)
    facts = ["樣本數 n = %d；%s 有 %d 類，%s 有 %d 類。" % (int(tab.values.sum()), x, r, y, c),
             ("方法：Cochran–Armitage 趨勢檢定（%s 為二元結果、%s 為有序解釋變數）。" % (y, x)) if ca
             else ("方法：Linear-by-linear association 檢定（%s 與 %s 都是有序變數）。" % (x, y)),
             ("%s 的分數：%s；%s 是二元變數（%s = 1，其他 = 0）。" % (x, us, y, s)) if c == 2
             else ("%s 的分數：%s；%s 的分數：%s。" % (x, us, y, ", ".join(num_str(t) for t in v))),
             "相關係數 R = %s；M² = (n − 1)R² = %s（df = 1），P = %s。" % (fmt_num(main["r"], 4), fmt_num(main["m2"], 2), fmt_p(main["p"])),
             "單尾檢定（%s）：M = %s，P = %s。" % (
                 ("%s 越高，%s=%s 的比例越%s" % (x, y, s, "高" if m > 0 else "低")) if c == 2
                 else ("%s 越高，%s 越%s" % (x, y, "高" if m > 0 else "低")),
                 fmt_num(m, 2), fmt_p(float(stats.norm.cdf(-abs(m))))),
             "對照：忽略順序的卡方檢定 X² = %s（df = %d），P = %s。有真正的線性趨勢時，M² 只用 1 個自由度，通常檢定力較高（§2.5.3）。"
             % (fmt_num(ch["statistic"], 2), dfx, fmt_p(ch["p"]))]
    if c == 2:
        prop = tab[s] / tab.sum(axis=1)
        facts.append("%s=%s 的比例：%s。" % (y, s, "、".join("%s %s" % (k, percent(pv, 0.01)) for k, pv in prop.items())))
    if custom:
        eq = m2_statistic(tab, list(range(1, r + 1)), list(range(1, c + 1)))
        tests.append({"test": "M2 (equally spaced scores)", "statistic": eq["m2"], "df": 1, "p_value": eq["p"], "book_ref": "§2.5.4"})
        facts.append("敏感度分析：改用等距分數時 M² = %s，P = %s。" % (fmt_num(eq["m2"], 2), fmt_p(eq["p"])))
        if (main["p"] < 0.05) != (eq["p"] < 0.05):
            warnings.append(warning("SCORE_SENSITIVE", "不同分數設定得到不同結論；資料不平衡時 M² 對分數很敏感，應說明分數的選擇理由並謹慎解讀。", "§2.5.4"))
    else:
        facts.append("使用等距分數。若類別間距離不相等，應依實際意義設定分數並做敏感度分析（§2.5.4）。")
    warnings += small_group_reminder(tab, x)
    sp = sparse_table(ch["expected"])
    if sp["sparse"]:
        warnings.append(warning(
            "LOW_EXPECTED",
            "期望次數最小為 %s，有 %d / %d 格小於 5：用來對照的 Pearson 卡方可能不可靠；M² 也是大樣本方法，請謹慎解讀。"
            % (fmt_num(sp["min"], 2), sp["n_low"], sp["n_cells"]), "§2.4.7, §2.5.2"))
    o = tab.values
    return {
        "method": "trend", "method_label": label, "book_ref": "§2.5", "tier": "A", "estimates": [], "tests": tests,
        "tables": {"counts": tab, "row_proportions": _round_table(tab, o / o.sum(axis=1, keepdims=True), 4)},
        "warnings": warnings, "facts": prep_facts + facts,
        "notes": {"variables": {"x": x, "y": y}, "scores": {"x": u, "y": v}, "trend_type": trend_type,
                  "reminder": "M² 只檢定「線性趨勢」；R 的大小受邊際分配影響，不適合單獨描述關聯強度（§2.5.2）。"}}


def cda_stratified(data, x, y, z, count=None, success=None, conf_level=0.95):
    d, w, warnings, prep_facts = prepare_categorical(data, [x, y, z], count)
    if len(d[x].cat.categories) != 2 or len(d[y].cat.categories) != 2:
        raise CdaError("目前只支援 X 與 Y 都是二元的 2×2×K 表（§2.7）。")
    ylev = [str(l) for l in d[y].cat.categories]
    s = ylev[0] if success is None else str(success)
    if s not in ylev:
        raise CdaError("success 必須是 %s 的其中一個類別。" % y)
    fail = [l for l in ylev if l != s][0]
    xl = [str(l) for l in d[x].cat.categories]
    zl = [str(l) for l in d[z].cat.categories]
    K = len(zl)
    if K < 2:
        raise CdaError("%s 至少要有 2 個類別才能做分層分析。" % z)
    tabs = {}
    for k in zl:
        keep = d[z].astype(str) == k
        tabs[k] = xtab(d[keep], w[keep], x, y)[[s, fail]]
        tabs[k] = tabs[k].reindex(index=xl, fill_value=0)

    def odds_ratio(t):
        return div(t[0, 0] * t[1, 1], t[0, 1] * t[1, 0])

    def stratum_row(t, label):
        ci = orscoreci(t[0, 0], t[0].sum(), t[1, 0], t[1].sum(), conf_level)
        return {"stratum": label, "n": float(t.sum()), "p1": div(t[0, 0], t[0].sum()), "p2": div(t[1, 0], t[1].sum()),
                "odds_ratio": odds_ratio(t), "lower": ci[0], "upper": ci[1]}

    strata = [stratum_row(tabs[k].values, k) for k in zl]
    tsum = sum(tabs[k].values for k in zl)
    marginal = stratum_row(tsum, "合併（忽略 %s）" % z)

    # logistic model: rows x varies fastest within z (expand.grid); baseline x = xl[1]
    rows = [(a, b) for b in zl for a in xl]
    succ = np.array([tabs[b].loc[a, s] for a, b in rows], float)
    fl = np.array([tabs[b].loc[a, fail] for a, b in rows], float)
    X = np.column_stack([np.ones(len(rows)), [1.0 if a == xl[0] else 0.0 for a, _ in rows]] +
                        [[1.0 if b == zk else 0.0 for _, b in rows] for zk in zl[1:]])
    X0 = np.delete(X, 1, axis=1)
    fit = glm_binomial(X, succ, fl)
    fit0 = glm_binomial(X0, succ, fl)
    beta = float(fit["coef"][1])
    se = math.sqrt(fit["vcov"][1, 1])
    try:
        ci = profile_ci(X, succ, fl, 1, fit, conf_level)
    except (CdaError, np.linalg.LinAlgError, ValueError, FloatingPointError):
        ci = [float("nan"), float("nan")]
    lr = fit0["deviance"] - fit["deviance"]
    # Cochran-Mantel-Haenszel without continuity correction
    num, var = 0.0, 0.0
    for k in zl:
        t = tabs[k].values
        nk = t.sum()
        if nk < 2:
            raise CdaError("sample size in each stratum must be > 1")
        r1, r2, c1, c2 = t[0].sum(), t[1].sum(), t[:, 0].sum(), t[:, 1].sum()
        num += t[0, 0] - r1 * c1 / nk
        var += r1 * r2 * c1 * c2 / (nk ** 2 * (nk - 1))
    cmh = num ** 2 / var
    cmh_p = float(stats.chi2.sf(cmh, 1))
    homog_p = float(stats.chi2.sf(fit["deviance"], fit["df_residual"]))
    wald = (beta / se) ** 2
    tests = [
        {"test": "LR test of conditional independence (beta = 0)", "statistic": lr, "df": 1,
         "p_value": float(stats.chi2.sf(lr, 1)), "book_ref": "§4.3.4"},
        {"test": "Wald test (beta = 0)", "statistic": wald, "df": 1, "p_value": float(stats.chi2.sf(wald, 1)), "book_ref": "§4.3.4"},
        {"test": "Cochran-Mantel-Haenszel (score test, beta = 0)", "statistic": cmh, "df": 1, "p_value": cmh_p, "book_ref": "§4.3.4"},
        {"test": "Homogeneous association (residual deviance)", "statistic": fit["deviance"], "df": fit["df_residual"],
         "p_value": homog_p, "book_ref": "§4.3.4, §5.2.1"}]
    estimates = [{"measure": "conditional odds ratio (%s = %s)" % (z, st["stratum"]), "estimate": st["odds_ratio"],
                  "lower": st["lower"], "upper": st["upper"], "ci_method": "score", "book_ref": "§2.7.4"} for st in strata]
    estimates += [{"measure": "marginal odds ratio", "estimate": marginal["odds_ratio"], "lower": marginal["lower"],
                   "upper": marginal["upper"], "ci_method": "score", "book_ref": "§2.7.4"},
                  {"measure": "common odds ratio (logistic model)", "estimate": math.exp(beta), "lower": math.exp(ci[0]),
                   "upper": math.exp(ci[1]), "ci_method": "profile likelihood", "book_ref": "§4.3.4"}]

    pct = lambda p: percent(p, 0.1)
    or_txt = lambda o: "無法計算" if math.isnan(o) else (fmt_num(o, 2) if math.isfinite(o) else "∞")

    def direction_txt(o):
        if math.isnan(o):
            return "方向無法判斷"
        if o > 1:
            return "%s=%s 的勝算 %s 組較高" % (y, s, xl[0])
        if o < 1:
            return "%s=%s 的勝算 %s 組較低" % (y, s, xl[0])
        return "兩組相同"

    conf = int(round(conf_level * 100))
    facts = ["樣本數 n = %d；比較 %s（%s vs %s）在 %s=%s 的比例，控制 %s（%d 層）。" % (int(tsum.sum()), x, xl[0], xl[1], y, s, z, K)]
    facts += ["%s=%s：%s 組 %s、%s 組 %s，條件勝算比 = %s，%d%% CI [%s, %s]（%s）。" % (
        z, st["stratum"], xl[0], pct(st["p1"]), xl[1], pct(st["p2"]), or_txt(st["odds_ratio"]), conf,
        or_txt(st["lower"]), or_txt(st["upper"]), direction_txt(st["odds_ratio"])) for st in strata]
    facts.append("忽略 %s 合併後：%s 組 %s、%s 組 %s，邊際勝算比 = %s。" % (
        z, xl[0], pct(marginal["p1"]), xl[1], pct(marginal["p2"]), or_txt(marginal["odds_ratio"])))
    if all(math.isfinite(v) for v in ci):
        facts.append("控制 %s 後的共同勝算比（logistic 模型）= %s，%d%% CI [%s, %s]。" % (
            z, fmt_num(math.exp(beta), 2), conf, fmt_num(math.exp(ci[0]), 2), fmt_num(math.exp(ci[1]), 2)))
    else:
        facts.append("控制 %s 後的共同勝算比（logistic 模型）= %s；信賴區間無法計算（常見原因是 0 次數的格子），不改用 Wald 區間。"
                     % (z, fmt_num(math.exp(beta), 2)))
    facts.append("條件獨立檢定：概似比 LR = %s（df = 1），P = %s；CMH = %s，P = %s。" % (
        fmt_num(lr, 2), fmt_p(tests[0]["p_value"]), fmt_num(cmh, 2), fmt_p(cmh_p)))
    facts.append("同質關聯檢定（各層勝算比是否相同）：deviance = %s（df = %d），P = %s。" % (
        fmt_num(fit["deviance"], 2), fit["df_residual"], fmt_p(homog_p)))

    def side(o):
        return None if math.isnan(o) else (0 if o == 1 else (1 if o > 1 else -1))

    cond_sides = [v for v in (side(st["odds_ratio"]) for st in strata) if v not in (None, 0)]
    marg_side = side(marginal["odds_ratio"])
    if cond_sides and len(set(cond_sides)) == 1 and marg_side not in (None, 0) and marg_side != cond_sides[0]:
        warnings.append(warning("SIMPSON", "Simpson 悖論：控制 %s 後，每一層的關聯方向都和合併後相反。只看合併的表會得到錯誤方向的結論。" % z, "§2.7.3"))
    if cond_sides and len(set(cond_sides)) > 1:
        warnings.append(warning(
            "OPPOSITE_DIRECTIONS",
            "各層勝算比的方向不一致（有的 > 1、有的 < 1）：%s 和 %s 的關係可能因 %s 而不同，"
            "不能只報共同勝算比，要逐層報告並看各層的信賴區間。" % (x, y, z), "§2.7.5"))
    if homog_p < 0.05:
        warnings.append(warning(
            "HETEROGENEITY", "同質關聯檢定顯著（P = %s）：各層勝算比可能不同，共同勝算比不能單獨代表全部，要逐層報告。" % fmt_p(homog_p),
            "§4.3.4, §5.2.1"))
    if any((tabs[k].values == 0).any() for k in zl):
        warnings.append(warning(
            "ZERO_CELL", "有分層表出現 0 次的格子，該層勝算比可能是 0、∞、無法計算或非常不穩定，請看原始次數表；"
            "這裡使用 score 信賴區間，沒有加 0.5 修正。", "§2.3.3, §5.3.3"))
    mu = 1 / (1 + np.exp(-(X @ fit["coef"])))
    n_cell = succ + fl
    if min(np.concatenate([mu * n_cell, (1 - mu) * n_cell])) < 5:
        warnings.append(warning("SMALL_FITTED", "模型的配適次數有小於 5 的格子，同質關聯檢定（deviance）的卡方近似可能不準。", "§5.2.2"))

    partial = [{x: a, y: b, z: k, "count": float(tabs[k].loc[a, b])} for k in zl for b in (s, fail) for a in xl]
    return {
        "method": "stratified", "method_label": "三因子表：分層勝算比、Simpson 悖論與 CMH 檢定",
        "book_ref": "§2.7, §4.3.4", "tier": "A", "estimates": estimates, "tests": tests,
        "tables": {"partial_tables": partial, "strata": strata + [marginal]},
        "warnings": warnings, "facts": prep_facts + facts,
        "notes": {"variables": {"x": x, "y": y, "z": z}, "success": s,
                  "reminder": "同質關聯檢定只是輔助：P > 0.05 不代表共同勝算比一定適合（小樣本時檢定力可能不足），"
                              "請一併檢視各層勝算比、信賴區間與分層圖。控制變數只能排除「有測量到的」第三變數；"
                              "觀察資料中仍可能有其他混淆因子（§2.7）。"}}

# ---------------------------------------------------------------- JSON (cda_to_json)

def _json_value(v):
    if isinstance(v, (np.floating, float)):
        v = float(v)
        if math.isnan(v):
            return None
        if math.isinf(v):
            return "Inf" if v > 0 else "-Inf"
        return v
    if isinstance(v, (np.integer,)):
        return int(v)
    if isinstance(v, dict):
        return {k: _json_value(x) for k, x in v.items()}
    if isinstance(v, (list, tuple)):
        return [_json_value(x) for x in v]
    if isinstance(v, pd.DataFrame):
        return {"rows": list(v.index), "cols": list(v.columns), "values": [[_json_value(x) for x in row] for row in v.values]}
    return v


def to_json(result):
    return _json_value(result)
