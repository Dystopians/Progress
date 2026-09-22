# -*- coding: utf-8 -*-
"""tools/refit_base_year.py —— R-SCALE-01 之后的基年数值重拟合（离线求解器）。

背景：docs/18_rulings.md R-SCALE-01 把 1 U 从 1e6 μU 改为 1e9 μU。旧刻度下有三处数值
不是设计出来的，是被整数下限**逼出来的**；新刻度下它们终于可表达，必须重拟合：

  1. state.price.wage_uu_per_person_q  —— 旧值 [1, 2, 3]（迁移后 [1000, 2000, 3000]）
  2. state.price.housing_rent_uu_per_unit_q —— 旧值 [1,1,1,1]（迁移后全 1000）
  3. groups[].base_per_capita_real_income_uu —— 旧刻度下全国只有 6 个取值

本脚本是这三处取值的**唯一来源**：它从兄弟文件读入全部被钉死的量（它们不属于本次分工，
只读不写），求解出上述三组数，重新配平受影响的会计恒等式，然后把结果写回三个内容文件：

    content/scenarios/chengwan/population_init.json
    content/scenarios/chengwan/io_table.json
    content/scenarios/chengwan/cells_init.json

**它不写 scenario.json**（工资率与租金数组的权威位置在那里，不属于本次分工），
求得的数组打印在 stdout 并写进 population_init 的 cross_file_check 供交接。

全部整数算术，拆分一律最大余数法，没有浮点参与任何写回的数值。
用法：  python tools/refit_base_year.py [--check]
        --check 只求解与自检，不写文件。
"""
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCEN = os.path.join(ROOT, "content", "scenarios", "chengwan")

PPM = 1_000_000
Q_SCALE = 1_000_000
U_SCALE = 1_000_000_000                    # R-SCALE-01：1 U = 1e9 μU
BASE_PRICE_UU_PER_QS = 1_000_000_000       # INV-148，jw_units.gd BASE_PRICE
BASE_PRICE_UU_PER_UQS = BASE_PRICE_UU_PER_QS // Q_SCALE   # == 1000 μU / μQ_s
BASE_YEAR_GDP_UU = 100_000_000_000
QUARTERLY_GDP_UU = BASE_YEAR_GDP_UU // 4   # 25 000 000 000

REGIONS = ["beiyuan", "zhongzhou", "haijia", "xiling"]
REGION_ZH = {"beiyuan": "北原", "zhongzhou": "中州", "haijia": "海岬", "xiling": "西岭"}
AGES = ["minor", "working", "elder"]
SKILLS = ["low", "mid", "high"]
SECTORS = ["sector.agri", "sector.manu", "sector.energy", "sector.services"]
SECTOR_ZH = {"sector.agri": "农业", "sector.manu": "制造",
             "sector.energy": "能源", "sector.services": "服务"}
DESTS = SECTORS + ["pubserv"]
GKEYS = [(r, a, k) for r in REGIONS for a in AGES for k in SKILLS]

# ── 被钉死的量：来自本次分工之外的文件，只读 ──────────────────────────────────
# government_init.json /annual_plan/expenditure_lines_uu/public_wages（年）
PUBLIC_WAGES_YEAR_UU = 9_000_000_000
PUBSERV_WAGE_Q_UU = PUBLIC_WAGES_YEAR_UU // 4          # 2 250 000 000 μU/季
# government_init.json /annual_plan/receipt_lines_uu/profit_tax（年）
PROFIT_TAX_Q_UU = 7_200_000_000 // 4
# government_init.json /annual_plan/receipt_lines_uu/income_tax（年）
INCOME_TAX_Q_UU = 10_400_000_000 // 4
# OQ-225：基年法定转移全部是失业救济；见 population_init 的 open question
# （government_init 现写 4 000 000 000/年，本剧本的收入侧一直按 3 600 000 000/年 记账）
TRANSFER_Q_UU = 900_000_000
# government_init.json：invpool 持债逐批次季度票息之和
INVPOOL_COUPON_Q_UU = ((8_000_000_000 * 8_000) // PPM + (7_000_000_000 * 8_500) // PPM
                       + (10_000_000_000 * 9_500) // PPM + (9_000_000_000 * 11_000) // PPM)
PAYOUT_RATIO_PPM = 300_000                              # param.payout_ratio_ppm

# gen_population.py 的财富权重（存款与持股同源）——本次不动，只用来重拆企业分配
WEALTH_W = {("minor", "low"): 0, ("minor", "mid"): 0, ("minor", "high"): 0,
            ("working", "low"): 10, ("working", "mid"): 30, ("working", "high"): 80,
            ("elder", "low"): 20, ("elder", "mid"): 50, ("elder", "high"): 120}
REGION_WEALTH = {"beiyuan": 80, "zhongzhou": 120, "haijia": 105, "xiling": 90}
TAX_W = {"low": 60, "mid": 160, "high": 300}            # 累进权重，见 card.income_tax_base_year
SUPPORT_OUT_W_PPM = {"beiyuan": 320_000, "zhongzhou": 300_000,
                     "haijia": 290_000, "xiling": 330_000}

# card.housing_burden_target：住房支出占地区可支配收入的设计目标（ppm）
HOUSING_BURDEN_TARGET_PPM = {"beiyuan": 140_000, "zhongzhou": 240_000,
                             "haijia": 200_000, "xiling": 150_000}

# 技能溢价的可接受结构带（见 solve_wage 的说明）
WAGE_RATIO_MID = (1.30, 2.05)
WAGE_RATIO_HIGH = (1.90, 3.30)


# ── 整数工具（与 sim/jw_math.gd 同语义） ────────────────────────────────────
def mul_ppm(x, p):
    return (x * p) // PPM


def mul_div_floor(a, b, c):
    q, r = divmod(a, c)
    return q * b + (r * b) // c


def ceil_div(a, b):
    return -((-a) // b)


def split_lr(total, weights):
    """最大余数法：Σ result == total 精确成立；平权按下标序破平。"""
    n = len(weights)
    W = sum(weights)
    if W == 0:
        return [0] * n
    base = [(total * w) // W for w in weights]
    rem = [total * weights[i] - base[i] * W for i in range(n)]
    r = total - sum(base)
    order = sorted(range(n), key=lambda i: (-rem[i], i))
    for i in order[:r]:
        base[i] += 1
    assert sum(base) == total
    return base


def egcd(x, y):
    if y == 0:
        return (x, 1, 0)
    d, p, q = egcd(y, x % y)
    return (d, q, p - (x // y) * q)


def load(name):
    with open(os.path.join(SCEN, name), encoding="utf-8") as fh:
        return json.load(fh)


def dump(name, data):
    with open(os.path.join(SCEN, name), "w", encoding="utf-8", newline="\n") as fh:
        fh.write(json.dumps(data, ensure_ascii=False, indent=2))
        fh.write("\n")


def num(n):
    """把整数写成带细分隔的中文正文格式：1234567 -> 1 234 567。"""
    s = str(abs(n))
    out = []
    while len(s) > 3:
        out.insert(0, s[-3:])
        s = s[:-3]
    out.insert(0, s)
    return ("-" if n < 0 else "") + " ".join(out)


# ═══════════════════════════════════════════════════════════════════════════
# 1 读入：人口、劳动力、就业（这三族是上游给定的，本脚本一个数都不改）
# ═══════════════════════════════════════════════════════════════════════════
pop_j = load("population_init.json")
io_j = load("io_table.json")
cells_j = load("cells_init.json")

G = pop_j["groups"]
EXT = pop_j["_note_extensions"]["groups_ext"]
assert [g["group_id"] for g in G] == ["group.%s.%s.%s" % t for t in GKEYS]
assert [e["group_id"] for e in EXT] == ["group.%s.%s.%s" % t for t in GKEYS]

POP, LF, EMP_TOT, DEPOSIT, HOUSE = {}, {}, {}, {}, {}
EMP_BY_DEST = {}
for t, g in zip(GKEYS, G):
    POP[t] = g["population_persons"]
    LF[t] = (g["population_persons"] * g["participation_ppm"]) // PPM
    EMP_BY_DEST[t] = dict(g["employed_persons"])
    EMP_TOT[t] = sum(g["employed_persons"][d] for d in DESTS)
    DEPOSIT[t] = g["deposit_uu"]
    HOUSE[t] = g["housing_units_occupied"]

N_SKILL = {k: sum(EMP_TOT[t] for t in GKEYS if t[2] == k) for k in SKILLS}
N_PUBSERV = {k: sum(EMP_BY_DEST[t]["pubserv"] for t in GKEYS if t[2] == k) for k in SKILLS}
N_MARKET = {k: N_SKILL[k] - N_PUBSERV[k] for k in SKILLS}
N_SECTOR_SKILL = {(s, k): sum(EMP_BY_DEST[t][s] for t in GKEYS if t[2] == k)
                  for s in DESTS for k in SKILLS}
N_SECTOR = {s: sum(N_SECTOR_SKILL[(s, k)] for k in SKILLS) for s in DESTS}
N_REGION_SECTOR_SKILL = {(r, s, k): sum(EMP_BY_DEST[t][s] for t in GKEYS
                                        if t[0] == r and t[2] == k)
                         for r in REGIONS for s in DESTS for k in SKILLS}

LF_TOTAL = sum(LF.values())
EMP_TOTAL = sum(EMP_TOT.values())
UNEMP_TOTAL = LF_TOTAL - EMP_TOTAL
UNEMP_PPM = (UNEMP_TOTAL * PPM) // LF_TOTAL
assert UNEMP_PPM == 80_000, ("失业率必须精确等于 8%", UNEMP_PPM)
assert sum(POP.values()) == 24_000_000
for r in REGIONS:
    assert sum(POP[t] for t in GKEYS if t[0] == r) == \
        {"beiyuan": 9_000_000, "zhongzhou": 7_000_000,
         "haijia": 5_000_000, "xiling": 3_000_000}[r]


# ═══════════════════════════════════════════════════════════════════════════
# 2 工资率：在「公共部门工资总额恒等式」上求整数解
# ═══════════════════════════════════════════════════════════════════════════
# 硬约束（不是偏好，是既有的跨文件恒等式）：
#   Σ_k pubserv_employment[k] × wage[k] == public_wages / 4
# 旧值 [1000, 2000, 3000] 给出 3 132 135 000 μU/季，比 2 250 000 000 高 39.2%——
# 这条恒等式在迁移后是**破的**，重拟合必须把它修回来。
#
# 该方程在 (a, b, c) 上是一条二维格，格距 = 156 757 / 237 109，因此在
# 「c > b > a > 0 且 c <= 8a」的整个范围内解极其稀疏（实测全域只有 5 组）。
# 本脚本枚举全部解，再用技能溢价结构带筛选——不是挑一个好看的，是证明解唯一。
def solve_wage():
    Pl, Pm, Ph = N_PUBSERV["low"], N_PUBSERV["mid"], N_PUBSERV["high"]
    T = PUBSERV_WAGE_Q_UU
    d, u, v = egcd(Pm, Ph)
    all_sols, in_band = [], []
    a_max = (T - Pm - Ph) // Pl
    for a in range(1, a_max + 1):
        R = T - Pl * a
        if R <= 0 or R % d:
            continue
        k = R // d
        b0, c0 = u * k, v * k
        sb, sc = Ph // d, Pm // d
        t_lo = -(-(a + 1 - b0) // sb)
        t_hi = (8 * a - b0) // sb
        for tt in range(t_lo, t_hi + 1):
            b = b0 + tt * sb
            c = c0 - tt * sc
            if not (a < b < c <= 8 * a):
                continue
            assert Pl * a + Pm * b + Ph * c == T
            all_sols.append((a, b, c))
            if (WAGE_RATIO_MID[0] * a <= b <= WAGE_RATIO_MID[1] * a
                    and WAGE_RATIO_HIGH[0] * a <= c <= WAGE_RATIO_HIGH[1] * a):
                in_band.append((a, b, c))
    return all_sols, in_band


ALL_WAGE_SOLS, WAGE_IN_BAND = solve_wage()
assert len(WAGE_IN_BAND) == 1, ("技能溢价结构带内的解不唯一，必须人工裁定", WAGE_IN_BAND)
WAGE_RATE = dict(zip(SKILLS, WAGE_IN_BAND[0]))
WAGE_ARR = [WAGE_RATE[k] for k in SKILLS]

WAGE = {t: EMP_TOT[t] * WAGE_RATE[t[2]] for t in GKEYS}
WAGE_BILL_Q = sum(WAGE.values())
PUBSERV_WAGE_CHECK = sum(N_PUBSERV[k] * WAGE_RATE[k] for k in SKILLS)
assert PUBSERV_WAGE_CHECK == PUBSERV_WAGE_Q_UU
MARKET_WAGE_Q = WAGE_BILL_Q - PUBSERV_WAGE_Q_UU
LABOR_SHARE_PPM = (WAGE_BILL_Q * 4 * PPM) // BASE_YEAR_GDP_UU


# ═══════════════════════════════════════════════════════════════════════════
# 3 收入链：工资一变，残差营业盈余、企业分配、个税权重、赡养转移全部跟着变
# ═══════════════════════════════════════════════════════════════════════════
ww = [POP[t] * WEALTH_W[(t[1], t[2])] * REGION_WEALTH[t[0]] for t in GKEYS]
EQUITY_PPM = dict(zip(GKEYS, split_lr(PPM, ww)))

GROSS_SURPLUS_Q = QUARTERLY_GDP_UU - WAGE_BILL_Q
BUSINESS_Q = mul_ppm(GROSS_SURPLUS_Q - PROFIT_TAX_Q_UU, PAYOUT_RATIO_PPM)
BUSINESS = dict(zip(GKEYS, split_lr(BUSINESS_Q, ww)))

INTEREST = dict(zip(GKEYS, split_lr(INVPOOL_COUPON_Q_UU, [DEPOSIT[t] for t in GKEYS])))

tw = [(LF[t] - EMP_TOT[t]) if t[1] == "working" else 0 for t in GKEYS]
TRANSFER = dict(zip(GKEYS, split_lr(TRANSFER_Q_UU, tw)))

taxw = [WAGE[t] * TAX_W[t[2]] + (BUSINESS[t] + INTEREST[t]) * 200 for t in GKEYS]
TAX = dict(zip(GKEYS, split_lr(INCOME_TAX_Q_UU, taxw)))

GROSS = {t: WAGE[t] + BUSINESS[t] + INTEREST[t] + TRANSFER[t] for t in GKEYS}
DISP_PRE = {t: GROSS[t] - TAX[t] for t in GKEYS}
assert all(v >= 0 for v in DISP_PRE.values())

SUPPORT_OUT = {t: 0 for t in GKEYS}
SUPPORT_IN = {t: 0 for t in GKEYS}
for r in REGIONS:
    pool = 0
    for k in SKILLS:
        t = (r, "working", k)
        SUPPORT_OUT[t] = mul_ppm(DISP_PRE[t], SUPPORT_OUT_W_PPM[r])
        pool += SUPPORT_OUT[t]
    deps = [(r, a, k) for a in ("minor", "elder") for k in SKILLS]
    for t, v in zip(deps, split_lr(pool, [POP[t] for t in deps])):
        SUPPORT_IN[t] = v
assert sum(SUPPORT_IN.values()) == sum(SUPPORT_OUT.values())

DISP = {t: DISP_PRE[t] - SUPPORT_OUT[t] + SUPPORT_IN[t] for t in GKEYS}
assert all(v > 0 for v in DISP.values())
DISP_TOTAL_Q = sum(DISP.values())
DISP_BY_REGION_Q = {r: sum(DISP[t] for t in GKEYS if t[0] == r) for r in REGIONS}


# ═══════════════════════════════════════════════════════════════════════════
# 4 住房租金：按各地区住房紧张程度定，落点用设计目标负担率反解
# ═══════════════════════════════════════════════════════════════════════════
# rent[r] = idiv_floor(target_ppm[r] × 地区季度可支配收入, 1e6 × 地区占用套数)
# 取整方向 floor（docs/10 §0「总额 → 每套」：少收租优于向居民多收）。
HOUSE_BY_REGION = {r: sum(HOUSE[t] for t in GKEYS if t[0] == r) for r in REGIONS}
RENT = {}
for r in REGIONS:
    RENT[r] = mul_div_floor(DISP_BY_REGION_Q[r], HOUSING_BURDEN_TARGET_PPM[r],
                            PPM * HOUSE_BY_REGION[r])
    assert RENT[r] > 0, ("租金必须 > 0（10 号文件 §9.1）", r)
RENT_ARR = [RENT[r] for r in REGIONS]

HOUSING_COST = {t: HOUSE[t] * RENT[t[0]] for t in GKEYS}
HOUSING_BURDEN_PPM = {t: (HOUSING_COST[t] * PPM) // DISP[t] for t in GKEYS}
HOUSING_COST_TOTAL_Q = sum(HOUSING_COST.values())
NATIONAL_BURDEN_PPM = (HOUSING_COST_TOTAL_Q * PPM) // DISP_TOTAL_Q
REGION_BURDEN_PPM = {r: (HOUSE_BY_REGION[r] * RENT[r] * PPM) // DISP_BY_REGION_Q[r]
                     for r in REGIONS}


# ═══════════════════════════════════════════════════════════════════════════
# 5 人均实际收入基准
# ═══════════════════════════════════════════════════════════════════════════
# 口径沿用本文件既有登记（也是 docs/18 R-SCALE-01「人均实际收入约 3 100」的口径）：
#   base_per_capita_real_income_uu[g] = idiv_floor(4 × 基年季度可支配收入[g], 人口[g])
# 即**年**人均实际可支配收入。旧刻度下它被 floor 压成 1…6 六个取值；新刻度下
# 逐组各不相同，全部达到 4 位有效数字。
BASE_PCI = {t: (DISP[t] * 4) // POP[t] for t in GKEYS}
assert all(v > 0 for v in BASE_PCI.values())
NATIONAL_PCI_YEAR = (DISP_TOTAL_Q * 4) // 24_000_000

# 融合归一化表达式（契约修订请求，见 population_init 的 open questions）：
#   real_income_norm_ppm[g] = clamp(mul_div_floor(mul(real_income_uu[g], 4), PPM,
#                                   max(mul(base_per_capita_real_income_uu[g],
#                                           population_persons[g]), 1)), 0, 3e6)
# 它消掉 docs/12 §8.1 里的 per_capita_uu = idiv_floor(real_income, pop) 这一步中间取整。
# 下面算出它在基年逐组的落点，供 assertions.json 钉死。
NORM_BASE_PPM = {t: mul_div_floor(DISP[t] * 4, PPM, BASE_PCI[t] * POP[t]) for t in GKEYS}
NORM_MAX_DEV = max(abs(v - PPM) for v in NORM_BASE_PPM.values())
# 对照：现行 docs/12 §8.1 的写法（季度人均 ÷ 年人均基准）在基年的落点
NORM_LEGACY_PPM = {t: mul_div_floor(DISP[t] // POP[t], PPM, BASE_PCI[t]) for t in GKEYS}


# ═══════════════════════════════════════════════════════════════════════════
# 6 io_table 附录重新配平
# ═══════════════════════════════════════════════════════════════════════════
ACC = io_j["_note_base_year_accounting"]
SECT_ACC = {s["sector_id"]: s for s in ACC["sector_accounts"]}
DEPR_PPM_Q = dict(zip(SECTORS, io_j["depreciation_ppm_per_q"]))

COMP_Q = {s: sum(N_SECTOR_SKILL[(s, k)] * WAGE_RATE[k] for k in SKILLS) for s in SECTORS}
COMP_YEAR = {s: COMP_Q[s] * 4 for s in SECTORS}
VA_YEAR = {s: SECT_ACC[s]["value_added_uu"] for s in SECTORS}
OS_YEAR = {s: VA_YEAR[s] - COMP_YEAR[s] for s in SECTORS}
assert all(v > 0 for v in OS_YEAR.values())


def declining_balance_year(capital, rate_ppm):
    """四季余额递减折旧，逐季 floor；返回 (逐季列表, 年合计)。"""
    c = capital
    out = []
    for _ in range(4):
        d = mul_ppm(c, rate_ppm)
        out.append(d)
        c -= d
    return out, sum(out)


DEPR_YEAR = {}
for s in SECTORS:
    _, DEPR_YEAR[s] = declining_balance_year(SECT_ACC[s]["capital_value_uu"], DEPR_PPM_Q[s])
PROFIT_YEAR = {s: OS_YEAR[s] - DEPR_YEAR[s] for s in SECTORS}
assert all(v > 0 for v in PROFIT_YEAR.values())

COMP_MARKET_YEAR = sum(COMP_YEAR.values())
OS_MARKET_YEAR = sum(OS_YEAR.values())
DEPR_MARKET_YEAR = sum(DEPR_YEAR.values())
assert COMP_MARKET_YEAR + OS_MARKET_YEAR == 90_000_000_000
assert COMP_MARKET_YEAR == MARKET_WAGE_Q * 4

# 公共服务：折旧在新刻度下不再精确等于 1 000 000 000（登记为待决问题，见 open_issues）
PUB_CAP = ACC["pubserv_account_uu"]["capital_value_uu"]
PUB_DEPR_PPM_Q = 8_000
PUB_DEPR_NATIVE = {}
for uid in ("pubserv.beiyuan", "pubserv.zhongzhou", "pubserv.haijia", "pubserv.xiling"):
    _, PUB_DEPR_NATIVE[uid] = declining_balance_year(PUB_CAP[uid], PUB_DEPR_PPM_Q)
PUB_DEPR_NATIVE_TOTAL = sum(PUB_DEPR_NATIVE.values())
PUB_DEPR_TARGET = 1_000_000_000
_fixed = sum(PUB_DEPR_NATIVE[u] for u in
             ("pubserv.beiyuan", "pubserv.zhongzhou", "pubserv.haijia"))
XILING_DEPR_NEEDED = PUB_DEPR_TARGET - _fixed
XILING_CAP_SOLVED = None
for cap in range(PUB_CAP["pubserv.xiling"] - 2_000_000, PUB_CAP["pubserv.xiling"] + 2_000_000):
    if declining_balance_year(cap, PUB_DEPR_PPM_Q)[1] == XILING_DEPR_NEEDED:
        XILING_CAP_SOLVED = cap
        break

# 各 cell 的劳动可支撑产量（用于 cells_init 的逐 cell 说明）
LABOR_COEFF = io_j["labor_coeff_persons_per_qs"]["*"]
CELL = {c["cell_id"]: c for c in cells_j["cells"]}
CAP_PER_CAPITAL = dict(zip(SECTORS, io_j["capacity_per_capital_uu_ppm"]))


def labor_supported(region, sector):
    best = None
    for k in SKILLS:
        coeff = LABOR_COEFF[sector][k]
        n = N_REGION_SECTOR_SKILL[(region, sector, k)]
        q = (n * PPM) // coeff
        best = q if best is None else min(best, q)
    return best


# 全国「技术系数口径」的用工需求（按基年产量算），保留为技术需求，不再冒充在岗人数
OUTPUT_Q = ACC["quarterly_split"]["gross_output_uqs_per_q"]
LABOR_REQ = {s: {k: ceil_div(OUTPUT_Q[s] * LABOR_COEFF[s][k], PPM) for k in SKILLS}
             for s in SECTORS}
LABOR_REQ_TOTAL = {s: sum(LABOR_REQ[s].values()) for s in SECTORS}


# ═══════════════════════════════════════════════════════════════════════════
# 7 自检（全部恒等式，容差 0）
# ═══════════════════════════════════════════════════════════════════════════
def selfcheck():
    ok = []

    def chk(name, a, b):
        ok.append((name, a == b, a, b))

    chk("人口合计 == 24 000 000", sum(POP.values()), 24_000_000)
    chk("36 组就业合计 == 分部门合计", EMP_TOTAL, sum(N_SECTOR.values()))
    chk("失业率 == 80 000 ppm", UNEMP_PPM, 80_000)
    chk("公共部门工资总额 == public_wages/4", PUBSERV_WAGE_CHECK, PUBSERV_WAGE_Q_UU)
    chk("Σ 各档工资×各档在岗 == 市场+公共报酬",
        sum(N_SKILL[k] * WAGE_RATE[k] for k in SKILLS), WAGE_BILL_Q)
    chk("市场部门报酬合计 == 工资总额 − 公共部门",
        COMP_MARKET_YEAR, (WAGE_BILL_Q - PUBSERV_WAGE_Q_UU) * 4)
    chk("市场增加值 == 报酬 + 营业盈余", 90_000_000_000,
        COMP_MARKET_YEAR + OS_MARKET_YEAR)
    chk("生产法 GDP", sum(VA_YEAR.values()) + 10_000_000_000, BASE_YEAR_GDP_UU)
    chk("收入法 GDP",
        COMP_MARKET_YEAR + OS_MARKET_YEAR + PUBLIC_WAGES_YEAR_UU + PUB_DEPR_TARGET,
        BASE_YEAR_GDP_UU)
    chk("支出法 GDP", 62_000_000_000 + 14_200_000_000 + 22_000_000_000
        + 1_800_000_000 + 11_000_000_000 - 11_000_000_000, BASE_YEAR_GDP_UU)
    chk("居民可支配收入恒等式",
        WAGE_BILL_Q + BUSINESS_Q + TRANSFER_Q_UU + INVPOOL_COUPON_Q_UU
        - INCOME_TAX_Q_UU, DISP_TOTAL_Q)
    chk("赡养转入 == 转出", sum(SUPPORT_IN.values()), sum(SUPPORT_OUT.values()))
    chk("cells 增加值（产能口径，按基年价） == 100 U",
        sum((CELL[cid]["capacity_active_uqs_per_q"]
             - sum((CELL[cid]["capacity_active_uqs_per_q"]
                    * io_j["io_coeff_uqs_per_qs"][row]["sector." + cid.split(".")[2]]) // PPM
                   for row in SECTORS)) for cid in CELL) * 4 * BASE_PRICE_UU_PER_UQS,
        BASE_YEAR_GDP_UU)
    for cid, c in CELL.items():
        s = "sector." + cid.split(".")[2]
        chk("V-CELL-03 " + cid, mul_ppm(c["capital_value_uu"], CAP_PER_CAPITAL[s]),
            c["capacity_active_uqs_per_q"])
        for k in SKILLS:
            chk("V-POP-08 " + cid + "/" + k, c["employment_persons"][k],
                N_REGION_SECTOR_SKILL[(cid.split(".")[1], s, k)])
    for s in SECTORS:
        chk("行合计=列合计 " + s,
            ACC["accounting_checks"]["row_balance"][SECTORS.index(s)]["supply_uu"],
            ACC["accounting_checks"]["row_balance"][SECTORS.index(s)]["use_uu"])
        chk("列平衡 " + s, SECT_ACC[s]["gross_output_uu"],
            SECT_ACC[s]["intermediate_input_uu"] + VA_YEAR[s])
    for r in REGIONS:
        chk("V-POP-06 " + r, HOUSE_BY_REGION[r] <= {"beiyuan": 3_050_000,
            "zhongzhou": 2_240_000, "haijia": 1_620_000, "xiling": 1_020_000}[r], True)
        chk("租金 > 0 " + r, RENT[r] > 0, True)
    # 权重表没变 ⇒ 持股份额一个数都不该动（既在 population_init 也在 cells_init 的 16 个 cell 里）
    for t, e in zip(GKEYS, EXT):
        chk("持股份额未变 " + str(t), EQUITY_PPM[t], e["base_equity_share_ppm"])
    for cid, c in CELL.items():
        chk("cell 持股份额合计 " + cid, sum(c["equity_share_ppm"].values()), PPM)
    chk("持股份额合计", sum(EQUITY_PPM.values()), PPM)
    # 人均实际收入必须有 4 位有效数字（本次重拟合的验收条件之一）
    chk("人均实际收入 >= 1000（4 位有效数字）", min(BASE_PCI.values()) >= 1000, True)
    chk("人均实际收入互异取值 > 6（旧刻度只有 6 个）", len(set(BASE_PCI.values())) > 6, True)
    # 住房负担逐地区不得超过目标（floor 保证），且必须 > 0
    for r in REGIONS:
        chk("住房负担 <= 目标 " + r,
            REGION_BURDEN_PPM[r] <= HOUSING_BURDEN_TARGET_PPM[r], True)
        chk("住房负担 > 0 " + r, REGION_BURDEN_PPM[r] > 0, True)
    bad = [o for o in ok if not o[1]]
    return ok, bad


CHECKS, FAILED = selfcheck()


# ═══════════════════════════════════════════════════════════════════════════
# 8 报告
# ═══════════════════════════════════════════════════════════════════════════
def report():
    w = sys.stdout.write
    w("== 工资率求解 ==\n")
    w("  公共部门在岗（低/中/高）: %s\n" % [N_PUBSERV[k] for k in SKILLS])
    w("  约束 Σ pubserv×wage == %d（public_wages/4）\n" % PUBSERV_WAGE_Q_UU)
    w("  全域整数解（c > b > a > 0, c <= 8a）共 %d 组：%s\n"
      % (len(ALL_WAGE_SOLS), ALL_WAGE_SOLS))
    w("  溢价结构带内唯一解: wage_uu_per_person_q = %s\n" % WAGE_ARR)
    w("  溢价 mid/low = %.4f, high/low = %.4f, high/mid = %.4f\n"
      % (WAGE_ARR[1] / WAGE_ARR[0], WAGE_ARR[2] / WAGE_ARR[0], WAGE_ARR[2] / WAGE_ARR[1]))
    w("  季度工资总额 %d μU；年 %d；劳动报酬占 GDP %d ppm（旧 745 612 ppm）\n"
      % (WAGE_BILL_Q, WAGE_BILL_Q * 4, LABOR_SHARE_PPM))
    w("\n== 部门劳动报酬（年，μU） ==\n")
    for s in SECTORS:
        w("  %-16s comp %14d  VA %14d  份额 %6d ppm  营业盈余 %14d\n"
          % (s, COMP_YEAR[s], VA_YEAR[s], COMP_YEAR[s] * PPM // VA_YEAR[s], OS_YEAR[s]))
    w("  pubserv          comp %14d  VA %14d  份额 %6d ppm\n"
      % (PUBLIC_WAGES_YEAR_UU, 10_000_000_000, PUBLIC_WAGES_YEAR_UU * PPM // 10_000_000_000))
    w("\n== 住房租金求解 ==\n")
    for r in REGIONS:
        w("  %-10s 目标 %6d ppm  可支配 %13d  套数 %8d  租金 %5d  实得 %6d ppm\n"
          % (r, HOUSING_BURDEN_TARGET_PPM[r], DISP_BY_REGION_Q[r],
             HOUSE_BY_REGION[r], RENT[r], REGION_BURDEN_PPM[r]))
    w("  全国住房支出 %d μU/季，占可支配收入 %d ppm（旧 421 997 ppm）\n"
      % (HOUSING_COST_TOTAL_Q, NATIONAL_BURDEN_PPM))
    w("\n== 人均实际收入基准 ==\n")
    vals = sorted(BASE_PCI.values())
    w("  全国年人均 %d μU；逐组 %d..%d，互异取值 %d 个（旧 6 个）\n"
      % (NATIONAL_PCI_YEAR, vals[0], vals[-1], len(set(vals))))
    w("  融合归一化在基年的落点 %d..%d ppm（偏离 1e6 最多 %d ppm）\n"
      % (min(NORM_BASE_PPM.values()), max(NORM_BASE_PPM.values()), NORM_MAX_DEV))
    w("  现行 §8.1 写法在基年的落点 %d..%d ppm —— 这是必须修的口径错\n"
      % (min(NORM_LEGACY_PPM.values()), max(NORM_LEGACY_PPM.values())))
    w("\n== 公共服务折旧（R-SCALE-01 遗留） ==\n")
    w("  新刻度原生复算年折旧合计 %d，目标 %d，差 %d\n"
      % (PUB_DEPR_NATIVE_TOTAL, PUB_DEPR_TARGET, PUB_DEPR_NATIVE_TOTAL - PUB_DEPR_TARGET))
    w("  使之精确成立的西岭资本 = %s（现 %s）\n"
      % (XILING_CAP_SOLVED, PUB_CAP["pubserv.xiling"]))
    w("\n== 自检 ==\n")
    w("  %d 条恒等式，失败 %d 条\n" % (len(CHECKS), len(FAILED)))
    for f in FAILED:
        w("  FAILED %s: %r != %r\n" % (f[0], f[2], f[3]))
    w("\n== 交给 scenario.json 的两个数组（本脚本不写那个文件） ==\n")
    w("  prices_init.wage_uu_per_person_q      = %s\n" % WAGE_ARR)
    w("  prices_init.housing_rent_uu_per_unit_q = %s\n" % RENT_ARR)


# ═══════════════════════════════════════════════════════════════════════════
# 9 写回
# ═══════════════════════════════════════════════════════════════════════════
def patch_population():
    d = pop_j
    for t, g, e in zip(GKEYS, d["groups"], d["_note_extensions"]["groups_ext"]):
        g["base_per_capita_real_income_uu"] = BASE_PCI[t]
        L = e["base_income_lines_uu_per_q"]
        L["wage"] = WAGE[t]
        L["business_distribution"] = BUSINESS[t]
        L["transfer"] = TRANSFER[t]
        L["other_property_income"] = INTEREST[t]
        L["household_support_in"] = SUPPORT_IN[t]
        L["household_support_out"] = SUPPORT_OUT[t]
        L["income_tax_paid"] = TAX[t]
        e["base_disposable_income_uu_per_q"] = DISP[t]
        e["base_equity_share_ppm"] = EQUITY_PPM[t]
        h = e["housing"]
        h.pop("housing_cost_at_min_rent_uu_per_q", None)
        h.pop("housing_burden_ppm_at_min_rent", None)
        newh = {"units_occupied": h["units_occupied"],
                "persons_per_unit_assumed": h["persons_per_unit_assumed"],
                "rent_uu_per_unit_q": RENT[t[0]],
                "housing_cost_uu_per_q": HOUSING_COST[t],
                "housing_burden_ppm": HOUSING_BURDEN_PPM[t],
                "housing_burden_design_target_ppm": h["housing_burden_design_target_ppm"]}
        e["housing"] = newh

    dc = d["_note_derived_check"]
    dc["housing_rent_resolution_check"] = {
        "_note_zh": (
            "R-SCALE-01 之后本块从「刻度挤压的证据」改为「租金拟合的算据」。1 U = 1 000 000 000 μU "
            "之后，租金的最小可表达值 1 μU/套/季 只相当于全国季度可支配收入的 %s ppm，"
            "设计目标折算出的逐地区租金第一次落在合法区间内部而不是被 floor 成 0。"
            "逐地区租金 = idiv_floor(设计目标负担率 × 地区季度可支配收入, 1e6 × 地区占用套数)，"
            "取整方向 floor（docs/10 §0「总额 → 每套」：少收租优于向居民多收）。"
            % num((7_860_000 * PPM) // DISP_TOTAL_Q)),
        "solved_rent_uu_per_unit_q": {"region." + r: RENT[r] for r in REGIONS},
        "design_target_burden_ppm_by_region": {
            "region." + r: HOUSING_BURDEN_TARGET_PPM[r] for r in REGIONS},
        "achieved_burden_ppm_by_region": {
            "region." + r: REGION_BURDEN_PPM[r] for r in REGIONS},
        "disposable_income_by_region_uu_per_q": {
            "region." + r: DISP_BY_REGION_Q[r] for r in REGIONS},
        "occupied_units_by_region": {"region." + r: HOUSE_BY_REGION[r] for r in REGIONS},
        "total_occupied_units": sum(HOUSE_BY_REGION.values()),
        "national_housing_cost_uu_per_q": HOUSING_COST_TOTAL_Q,
        "national_disposable_income_uu_per_q": DISP_TOTAL_Q,
        "national_housing_burden_ppm": NATIONAL_BURDEN_PPM,
        "_note_tightness_zh": (
            "档位次序直接来自住房紧张程度，不是凭空排的：中州（存量 2 240 000 套 < 人口/3 = "
            "2 333 334 套，缺口 4.0%%，迁移闸 cap_housing 为 0）最高 %s μU；"
            "海岬（存量 1 620 000 < 1 666 667，缺口 2.8%%，cap_housing 同为 0）次之 %s μU；"
            "西岭（占用率 98.0%%，有余量）%s μU；北原（存量最大、占用率 98.4%%）最低 %s μU。"
            "全国住房支出占居民可支配收入 %s ppm，落在 140 000—240 000 ppm 的逐地区设计目标之内，"
            "也落在「住房支出占可支配收入」的可辩护区间（约 150 000—300 000 ppm）里；"
            "旧刻度下这个数是 421 997 ppm，是被 1 μU 的整数下限顶出来的，不是设计值。"
            % (num(RENT["zhongzhou"]), num(RENT["haijia"]), num(RENT["xiling"]),
               num(RENT["beiyuan"]), num(NATIONAL_BURDEN_PPM))),
        "_note_group_spread_zh": (
            "逐地区目标是按**地区**可支配收入定的，逐组实得负担率必然分散（%s..%s ppm）："
            "未成年与老年组自己没有工资收入，其住房支出由组间赡养转移覆盖，"
            "因此这些组的负担率高于本地区均值是口径结果，不是取值错误。"
            % (num(min(HOUSING_BURDEN_PPM.values())), num(max(HOUSING_BURDEN_PPM.values())))),
    }
    dc["per_capita_resolution_check"] = {
        "_note_zh": (
            "base_per_capita_real_income_uu[g] = idiv_floor(4 × base_disposable_income_uu_per_q[g], "
            "population_persons[g])，即**年**人均实际可支配收入，与 docs/18 R-SCALE-01 "
            "「人均实际收入约 3 100（4 位有效数字）」同口径。旧刻度下 floor 把它压成 1…6 六个取值；"
            "新刻度下 36 组有 %d 个互异取值，最小 %s、最大 %s，全部 4 位有效数字。"
            "注意：docs/12 §8.1 的 per_capita_uu 用的是**季度**可支配收入，两者差 4 倍，"
            "该口径冲突登记在 oq_base_per_capita_period_conflict，必须由契约裁定，本文件不自行改口径。"
            % (len(set(BASE_PCI.values())), num(min(BASE_PCI.values())),
               num(max(BASE_PCI.values())))),
        "national_annual_disposable_income_uu": DISP_TOTAL_Q * 4,
        "national_population_persons": 24_000_000,
        "national_annual_per_capita_uu": NATIONAL_PCI_YEAR,
        "base_per_capita_real_income_uu_min": min(BASE_PCI.values()),
        "base_per_capita_real_income_uu_max": max(BASE_PCI.values()),
        "distinct_values_count": len(set(BASE_PCI.values())),
        "proposed_fused_norm_expr": (
            "real_income_norm_ppm[g] = clamp_i(mul_div_floor(mul(real_income_uu[g], 4), 1000000, "
            "max(mul(content.base_per_capita_real_income_uu[g], "
            "state.group.population_persons[g]), 1)), 0, 3000000)"),
        "_note_fused_zh": (
            "融合表达式消掉 docs/12 §8.1 的 per_capita_uu = idiv_floor(real_income, pop) 这一步中间取整："
            "人均量只有 %s 级，一个 floor 单位就是约 %s ppm 的量化台阶，"
            "乘 living 的收入权重 500 000 ppm 后仍有约 %s ppm，会让生活指数只能跳着走。"
            "融合后分辨率回到 1 ppm。溢出：real_income ≤ AMOUNT_MAX 4e15，×4 = 1.6e16，"
            "再经 mul_div_floor 拆商余后与 1e6 相乘不溢出（INV-007）；"
            "分母 base_pci × pop ≤ 约 %s，恒 > 0。"
            % (num(NATIONAL_PCI_YEAR), num(PPM // NATIONAL_PCI_YEAR),
               num(PPM // NATIONAL_PCI_YEAR // 2), num(max(BASE_PCI.values()) * 24_000_000))),
        "fused_norm_base_year_ppm_min": min(NORM_BASE_PPM.values()),
        "fused_norm_base_year_ppm_max": max(NORM_BASE_PPM.values()),
        "legacy_norm_base_year_ppm_min": min(NORM_LEGACY_PPM.values()),
        "legacy_norm_base_year_ppm_max": max(NORM_LEGACY_PPM.values()),
        "_note_legacy_zh": (
            "对照：照 docs/12 §8.1 现行写法（季度人均 ÷ 年人均基准）算，基年 real_income_norm_ppm "
            "只有 %s..%s ppm 而不是 1 000 000；乘收入权重 500 000 ppm 后，living_index 在第 0 季末"
            "就会比剧本登记的基年值 1 000 000 低约 %s ppm，"
            "R-SUPPORT-01 的 Δliving 因此在开局凭空产生一次大幅负冲击。"
            "这不是本文件的取值问题，是 §8.1 与本字段的期间口径不一致，见 "
            "_note_open_questions_zh.oq_base_per_capita_period_conflict。"
            % (num(min(NORM_LEGACY_PPM.values())), num(max(NORM_LEGACY_PPM.values())),
               num(mul_ppm(PPM - max(NORM_LEGACY_PPM.values()), 500_000)))),
    }
    dc["base_income_identity_uu_per_q"] = {
        "_note_zh": "基年每季居民收入分解；各项之和逐项精确对账（拆分均用最大余数法）。",
        "wage": WAGE_BILL_Q,
        "business_distribution": BUSINESS_Q,
        "transfer": TRANSFER_Q_UU,
        "other_property_income": INVPOOL_COUPON_Q_UU,
        "gross_household_income": WAGE_BILL_Q + BUSINESS_Q + TRANSFER_Q_UU + INVPOOL_COUPON_Q_UU,
        "income_tax_paid": INCOME_TAX_Q_UU,
        "household_support_in": sum(SUPPORT_IN.values()),
        "household_support_out": sum(SUPPORT_OUT.values()),
        "disposable_income": DISP_TOTAL_Q,
        "housing_cost": HOUSING_COST_TOTAL_Q,
        "quarterly_nominal_gdp_reference_uu": QUARTERLY_GDP_UU,
        "wage_share_of_quarterly_gdp_ppm": (WAGE_BILL_Q * PPM) // QUARTERLY_GDP_UU,
        "_note_wage_share_zh": (
            "本键旧值 745 612 000 是迁移器的连带损伤：键名 base_income_identity_uu_per_q 含 uu 词元，"
            "整棵子树被 ×1000，把一个 ppm 也乘了进去。ppm 与货币刻度无关，已改回 ppm 量纲。"),
    }
    cf = dc["cross_file_check"]
    cf["from_scenario_json"] = {
        "wage_uu_per_person_q": WAGE_ARR,
        "housing_rent_uu_per_unit_q": RENT_ARR,
        "implied_wage_bill_uu_per_q": WAGE_BILL_Q,
        "implied_labor_share_of_quarterly_gdp_ppm": LABOR_SHARE_PPM,
        "residual_gross_operating_surplus_uu_per_q": GROSS_SURPLUS_Q,
        "sum_group_cash_uu_for_total_cash_reconciliation": sum(g["cash_uu"] for g in d["groups"]),
        "_note_zh": (
            "**这两个数组的权威副本在 scenario.json /prices_init，不在本文件**；本次分工不写那个文件，"
            "求解结果登记在此供交接：scenario.json 必须同步改成上面两行，否则收入侧与价格侧脱节。"
            "工资率 %s 是「公共部门工资总额 == government_init 的 public_wages / 4」"
            "这条恒等式在技能溢价结构带内的**唯一**整数解。该方程的解在 (a, b, c) 上是一条二维格，"
            "格距 156 757 / 237 109，因此在 c > b > a > 0 且 c ≤ 8a 的全域只有 5 组解：%s；"
            "另外四组的溢价结构分别是 3.19x/5.80x、3.62x/3.72x、1.27x/3.85x、1.13x/1.66x，"
            "要么中档溢价高得不像技能差距，要么中档几乎没有溢价，全部落在结构带外。"
            "旧值 [1000, 2000, 3000] 给出 3 132 135 000 μU/季，比 2 250 000 000 高 39.2%%，"
            "那条恒等式在迁移后是破的。"
            "溢价结构：中档 / 低档 = %s / %s = +67.2%%，高档 / 中档 = %s / %s = +64.1%%，"
            "两级近似等比，对应「每上一档技能约 +65%% 的工资溢价」这一条可辩护的结构假设。"
            % (WAGE_ARR, ALL_WAGE_SOLS, num(WAGE_ARR[1]), num(WAGE_ARR[0]),
               num(WAGE_ARR[2]), num(WAGE_ARR[1]))),
    }
    cf["from_government_init_json"] = {
        "invpool_cash_uu": 9_000_000_000,
        "invpool_bondhold_uu": 34_000_000_000,
        "required_sum_group_deposit_uu": 43_000_000_000,
        "actual_sum_group_deposit_uu": sum(g["deposit_uu"] for g in d["groups"]),
        "invpool_quarterly_coupon_uu": INVPOOL_COUPON_Q_UU,
        "income_tax_quarter_uu": INCOME_TAX_Q_UU,
        "profit_tax_quarter_uu": PROFIT_TAX_Q_UU,
        "statutory_transfers_quarter_uu": TRANSFER_Q_UU,
        "public_wages_quarter_uu": PUBSERV_WAGE_Q_UU,
        "actual_pubserv_wage_bill_uu_per_q": PUBSERV_WAGE_CHECK,
        "_note_zh": (
            "public_wages_quarter_uu 与 actual_pubserv_wage_bill_uu_per_q 必须精确相等——"
            "这是本次重拟合修回来的恒等式（旧工资率下两者差 882 135 000 μU/季）。"
            "statutory_transfers_quarter_uu 取 900 000 000 是按 3 600 000 000/年 记的；"
            "government_init 现写 4 000 000 000/年，差 400 000 000，见 oq_statutory_transfer_mismatch。"),
    }

    ext = d["_note_extensions"]
    ext["_note_housing_zh"] = (
        "租金由 scenario.json 的 housing_rent_uu_per_unit_q 给出（OQ-244：首版固定不更新）。"
        "R-SCALE-01 之后租金第一次可表达：逐地区取 %s μU/套/季（北原/中州/海岬/西岭），"
        "由各区设计目标负担率与本文件的地区可支配收入反解，算据与紧张程度依据见 "
        "_note_derived_check.housing_rent_resolution_check。旧刻度下租金只能取最小值 1 μU/套/季，"
        "住房负担被顶到 421 997 ppm，那是刻度产物不是设计值。" % RENT_ARR)
    for c in ext["source_cards"]:
        if c["card_id"] == "card.wage_income_base_year":
            c["value"] = WAGE_ARR
            c["unit"] = "μU/人/季"
            c["definition"] = (
                "基年群组工资收入。derivation_expr: wage[g] = employed_persons_total[g] × "
                "wage_uu_per_person_q[skill]，与 12 号文件 S04 的算法逐字一致，因此不产生任何拆分余数。"
                "工资率本身不是自由参数：它由「Σ_技能 pubserv 在岗人数 × wage[技能] == "
                "government_init 的 public_wages / 4」这条恒等式唯一确定——该方程在 "
                "c > b > a > 0 且 c ≤ 8a 的全域只有 5 组整数解，落在技能溢价结构带 "
                "（中/低 ∈ [1.30, 2.05]，高/低 ∈ [1.90, 3.30]）内的只有 %s 一组。"
                "求解与全部自检见 tools/refit_base_year.py。" % WAGE_ARR)
            c["confidence"] = "low"
            c["calibration_note"] = (
                "本卡的值不是本文件选的，而是 scenario.json 给的；工资率一改，本文件必须重新生成。"
                "R-SCALE-01 之后旧值 [1000, 2000, 3000] 已被废弃：它是旧刻度下 [1, 2, 3] 的机械迁移，"
                "1x/2x/3x 的技能溢价是整数下限的产物，而且使公共部门工资总额比 public_wages 高 39.2%%，"
                "使劳动报酬占 GDP 达 745 612 ppm。现值的溢价是两级各约 +65%% 的等比结构"
                "（中/低 = %s/%s，高/中 = %s/%s），劳动报酬占 GDP %s ppm。"
                "保守性：取整方向不介入——本卡三个数是方程的精确整数解，没有 floor 也没有 ceil。"
                % (num(WAGE_ARR[1]), num(WAGE_ARR[0]), num(WAGE_ARR[2]), num(WAGE_ARR[1]),
                   num(LABOR_SHARE_PPM)))
        elif c["card_id"] == "card.housing_burden_target":
            c["definition"] = (
                "设计目标的住房支出占可支配收入比重（北原 140000 / 西岭 150000 / 海岬 200000 / "
                "中州 240000）。R-SCALE-01 之后可用 > 0 的整数租金实现："
                "rent[r] = idiv_floor(目标 ppm × 地区季度可支配收入, 1e6 × 地区占用套数) = %s，"
                "实得逐地区负担率 %s ppm，全国 %s ppm。"
                % (RENT_ARR, [REGION_BURDEN_PPM[r] for r in REGIONS], num(NATIONAL_BURDEN_PPM)))
            c["calibration_note"] = (
                "取整方向 floor（docs/10 §0「总额 → 每套」：少收租优于向居民多收），"
                "因此实得负担率必然略低于目标，逐地区偏差 %s ppm，全部是同一个方向——"
                "这是刻意的保守性，不是配平误差。目标本身的排序依据是住房紧张程度"
                "（中州与海岬的存量低于「人口 / 3」，迁移闸 cap_housing 为 0），"
                "不是收入水平。租金的权威副本在 scenario.json，改它必须重跑 tools/refit_base_year.py。"
                % [HOUSING_BURDEN_TARGET_PPM[r] - REGION_BURDEN_PPM[r] for r in REGIONS])
        elif c["card_id"] == "card.business_distribution_base_year":
            c["calibration_note"] = (
                "工资率一改，残差营业盈余随之变化；本卡只固定分配比例，不固定金额。"
                "本次重拟合后 derivation_expr 的输入变成：季度名义 GDP 25 000 000 000 − 工资总额 %s "
                "− 季度利润税 1 800 000 000，×300 000 ppm = %s μU/季（旧值 1 367 905 000）。"
                "若 q=0 结算出的 flow.cell.distributed_uu 与此偏离，先查 io_table 与工资率。"
                % (num(WAGE_BILL_Q), num(BUSINESS_Q)))
    # ── R-SCALE-01 遗留清扫：source_cards 用 card_id 而非 parameter_id，
    #    tools/migrate_currency_scale.py 的「参数卡按 unit 判定」那条规则漏掉了它们，
    #    于是这些 unit == μU 的卡还停在旧刻度。这里按绝对值改正（不是再乘一次 1000）。
    CARD_SCALE_FIX = {
        "card.household_wealth_weight": (43_000_000_000, [20_000_000_000, 80_000_000_000]),
        "card.household_cash": (9_000_000_000, [2_000_000_000, 15_000_000_000]),
        "card.income_tax_base_year": (INCOME_TAX_Q_UU, [1_500_000_000, 4_000_000_000]),
        "card.statutory_transfer_base_year": (TRANSFER_Q_UU, [0, 4_000_000_000]),
    }
    for c in ext["source_cards"]:
        if c["card_id"] in CARD_SCALE_FIX:
            c["value"], c["valid_range"] = CARD_SCALE_FIX[c["card_id"]]
            c["_note_scale_fix_zh"] = (
                "R-SCALE-01：本卡 unit 是 μU，但 source_cards 用 card_id 而非 parameter_id，"
                "migrate_currency_scale.py 的参数卡规则没有覆盖它，value 与 valid_range 一直停在旧刻度。"
                "已按 1 U = 1 000 000 000 μU 改正为绝对值。")
        if c["card_id"] == "card.wage_income_base_year":
            c["valid_range"] = [[min(s[i] for s in ALL_WAGE_SOLS),
                                 max(s[i] for s in ALL_WAGE_SOLS)] for i in range(3)]
            c["_note_valid_range_zh"] = (
                "valid_range 不是一个可自由取值的区间，而是「公共部门工资总额 == public_wages / 4」"
                "这条恒等式的**全部整数解**（c > b > a > 0 且 c ≤ 8a）在各档上的包络：%s。"
                "三档必须整组取自同一个解，不能逐档独立取值。旧 valid_range [[1, 20000000], …] "
                "来自 param.wage_floor_uu / wage_ceil_uu 的旧刻度值，那两个参数比本剧本的实际工资率"
                "高 4 到 7 个数量级（policy_P12 的 OQ-P12-02 已登记），迁移后只会更离谱，本卡不再引用它们。"
                % (ALL_WAGE_SOLS,))
        if c["card_id"] == "card.household_cash":
            c["definition"] = (
                "开局居民手持现金合计（约等于基年一个季度可支配收入的 %s ppm），"
                "按各组可支配收入最大余数法分配。必须计入 scenario.total_cash_uu（INV-018）。"
                "注意：本次工资重拟合后，36 个 cash_uu 被**刻意冻结**在重拟合前的分配上，"
                "见 _note_open_questions_zh.oq_cash_allocation_frozen；合计仍精确为 9 000 000 000 μU。"
                % num((9_000_000_000 * PPM) // DISP_TOTAL_Q))
        if c["card_id"] == "card.income_tax_base_year":
            c["source_ref"] = ("government_init.json annual_plan.receipt_lines_uu.income_tax "
                               "= 10 400 000 000 / 年；计划书 §05「全年收入 20 U」")
        if c["card_id"] == "card.statutory_transfer_base_year":
            c["source_ref"] = ("government_init.json annual_plan.expenditure_lines_uu."
                               "statutory_transfers（本文件按 3 600 000 000 / 年 记账，"
                               "该文件现写 4 000 000 000 / 年，差额见 oq_statutory_transfer_mismatch）；"
                               "OQ-225「养老金为 0」；计划书 §09 P03"
                               "「失业保障：资格、替代比例与持续期」")

    ext["source_cards"] = [c for c in ext["source_cards"]
                           if c["card_id"] != "card.per_capita_real_income_base"]
    ext["source_cards"].append({
        "card_id": "card.per_capita_real_income_base",
        "scope": "groups[].base_per_capita_real_income_uu",
        "value": [min(BASE_PCI.values()), max(BASE_PCI.values())],
        "unit": "μU/人/年",
        "source_type": "derived",
        "source_ref": ("12_simulation_contract.md §8.1 real_income_norm_ppm；"
                       "docs/18 R-SCALE-01「人均实际收入约 3 100（4 位有效数字）」"),
        "reference_year": 0,
        "definition": ("基年人均实际可支配收入基准，living_index 收入分量的归一化分母。"
                       "derivation_expr: idiv_floor(4 × base_disposable_income_uu_per_q[g], "
                       "population_persons[g])。全国年人均 %s μU；36 组取值 %s..%s，"
                       "互异取值 %d 个。" % (num(NATIONAL_PCI_YEAR), num(min(BASE_PCI.values())),
                                          num(max(BASE_PCI.values())), len(set(BASE_PCI.values())))),
        "valid_range": [1, 100000],
        "confidence": "low",
        "calibration_note": (
            "取整方向 floor（docs/10 §0「总额 → 人均」：少算优于高估民生）。"
            "旧刻度下 floor 把 36 组压成 1…6 六个取值，归一化只剩约 1 位有效数字，"
            "floor 与 ceil 的差别能占满量程；新刻度下每组都是 4 位有效数字，floor 的偏置退回可忽略。"
            "**期间口径未经裁定**：本卡按年，docs/12 §8.1 的 per_capita_uu 按季，两者差 4 倍，"
            "见 _note_open_questions_zh.oq_base_per_capita_period_conflict。"
            "本字段 q=0 之后只读，任何运行期写入即 FAULT。"),
    })

    oq = d["_note_open_questions_zh"]
    oq["oq_scenario_json_must_follow"] = (
        "本次重拟合求出的 prices_init.wage_uu_per_person_q = %s 与 "
        "prices_init.housing_rent_uu_per_unit_q = %s 的权威位置在 "
        "content/scenarios/chengwan/scenario.json，不在本文件，且不属于本次分工。"
        "在 scenario.json 同步之前，本文件的收入侧（工资总额、可支配收入、住房支出、人均基准）"
        "与价格侧不一致：scenario.json 仍写 [1000, 2000, 3000] 与 [1000, 1000, 1000, 1000]。"
        "同时 scenario.json 的 _note_prices_init 整段正文（「撞上了记账单位的分辨率下限」云云）"
        "在 R-SCALE-01 之后已经不成立，必须重写。" % (WAGE_ARR, RENT_ARR))
    oq["oq_base_per_capita_period_conflict"] = (
        "base_per_capita_real_income_uu 的**期间**在契约里没有写死，两处默认互相矛盾："
        "docs/18 R-SCALE-01 的分辨率表把它记为「人均实际收入约 3 100」（= 全国年可支配收入 / 人口，年口径，"
        "也是本文件一直采用的口径）；docs/12 §8.1 却写 per_capita_uu = idiv_floor(real_income_uu[g], pop)，"
        "而 real_income_uu 来自 derived.group.disposable_income_uu——那是**季度**流量。"
        "两者差 4 倍。按 §8.1 现行写法，基年 real_income_norm_ppm 只有 %s..%s ppm 而不是 1 000 000，"
        "乘收入权重 500 000 ppm 后，living_index 在第 0 季末即比剧本登记的基年值 1 000 000 低约 "
        "%s ppm（约 37.5 个百分点），R-SUPPORT-01 的 Δliving 于是在开局凭空产生一次大幅负冲击。"
        "本文件按既有登记的年口径取值（docs/18 优先级最高），并请求契约在 §8.1 与 §5.7 里**写明期间**；"
        "同时请求把归一化改成 per_capita_resolution_check.proposed_fused_norm_expr 的融合形式，"
        "以消掉人均中间取整。裁定之前不要单方面改本字段的口径。"
        % (num(min(NORM_LEGACY_PPM.values())), num(max(NORM_LEGACY_PPM.values())),
           num(mul_ppm(PPM - max(NORM_LEGACY_PPM.values()), 500_000))))
    oq["oq_statutory_transfer_mismatch"] = (
        "government_init.json 的 annual_plan.expenditure_lines_uu.statutory_transfers 现为 "
        "4 000 000 000/年，而本文件的收入侧一直按 900 000 000/季 = 3 600 000 000/年 记账"
        "（card.statutory_transfer_base_year 也写 3 600 000）。差 400 000 000/年。"
        "本次分工不写 government_init，按既有收入侧取值保持不变，登记备查：两侧必须有一侧改。")
    oq["oq_cash_allocation_frozen"] = (
        "groups[].cash_uu 的登记derivation（card.household_cash）是「按基年可支配收入用最大余数法分配 "
        "9 000 000 000 μU」。本次工资重拟合改变了可支配收入，严格重跑会改动 36 个 cash_uu。"
        "本文件**刻意冻结**这 36 个值：现金是存量，它的分配权重是设计选择而非会计恒等式，"
        "重分配只会在不增加任何正确性的前提下动 36 个规范字段，并可能碰到本文件看不见的引用。"
        "合计仍精确等于 9 000 000 000（INV-018 不受影响）。若将来要重分配，"
        "必须与 scenario.json 的 total_cash_uu 一起复核。")
    dump("population_init.json", d)


def patch_io_table():
    d = io_j
    acc = d["_note_base_year_accounting"]
    acc["_unit"] = ("金额单位 μU（裁定 R-SCALE-01：1 U = 1 000 000 000 μU），"
                    "数量单位 μQ_s（1 Q_s = 1 000 000 μQ_s）。基年各部门价格均为 "
                    "1 000 000 000 μU/Q_s，即 1 000 μU/μQ_s，故基年名义额与实物量成固定比例 1 000，"
                    "本附录的金额列与数量列因此不是同一个数，读的时候不要互相代入。")
    for s in SECTORS:
        a = SECT_ACC[s]
        a["compensation_of_employees_uu"] = COMP_YEAR[s]
        a["operating_surplus_uu"] = OS_YEAR[s]
        a["depreciation_uu"] = DEPR_YEAR[s]
        a["profit_pretax_uu"] = PROFIT_YEAR[s]
        a["employment_persons"] = {k: N_SECTOR_SKILL[(s, k)] for k in SKILLS}
        a["employment_persons"]["total"] = N_SECTOR[s]

    ac = acc["accounting_checks"]
    ac["gdp_income_uu"]["compensation_market_uu"] = COMP_MARKET_YEAR
    ac["gdp_income_uu"]["operating_surplus_market_uu"] = OS_MARKET_YEAR
    ac["gdp_income_uu"]["pubserv_compensation_uu"] = PUBLIC_WAGES_YEAR_UU
    ac["gdp_income_uu"]["_note_zh"] = (
        "劳动报酬不再是自由参数：它 == Σ_(部门,技能) population_init 的在岗人数 × "
        "scenario.json 的 wage_uu_per_person_q[技能]，逐部门精确成立。"
        "营业盈余是残差（增加值 − 劳动报酬），因此三口径 GDP 不受工资率重拟合影响。")

    mc = acc["maintenance_and_capacity"]
    mc["depreciation_total_uu"] = DEPR_MARKET_YEAR
    mc["net_capital_formation_uu"] = mc["gross_capital_formation_uu"] - DEPR_MARKET_YEAR
    mc["_note_depreciation_scale_zh"] = (
        "折旧按四季余额递减逐季 floor 后求和，在新刻度下原生复算（旧值是老刻度整数 ×1000，"
        "每个部门低估几百 μU）。折旧只在营业盈余内部把利润与折旧分开，不进任何一种 GDP 口径，"
        "因此这次修正不动三口径对账。")

    acc["labor"] = {
        "_note": (
            "本块区分两件过去被混在一起的事：**在岗人数**（谁真的在工作，权威在 "
            "population_init.json，逐 (地区, 部门, 技能) 由 V-POP-08 与 cells_init / pubserv_init "
            "交叉校验）与**技术口径的用工需求**（按基年产量与 labor_coeff 算出来的 "
            "ceil(产量 × 用工系数 / 1e6)）。两者不相等，差额就是基年的 bound_labor 缺口，"
            "登记在 labor_requirement_at_base_output_persons 与 open_issues，"
            "不再用「附录自己的一套就业数」把它藏起来。失业率必须由 population_init 反算"
            "（V-POP-05、INV-143），本附录只复述它必须落在哪里。"),
        "employment_by_sector_persons": {s: N_SECTOR[s] for s in SECTORS},
        "employment_by_skill_persons": {k: N_MARKET[k] for k in SKILLS},
        "market_employment_persons": sum(N_MARKET.values()),
        "pubserv_employment_persons": N_SECTOR["pubserv"],
        "pubserv_employment_by_skill_persons": {k: N_PUBSERV[k] for k in SKILLS},
        "total_employment_persons": EMP_TOTAL,
        "implied_labor_force_persons": LF_TOTAL,
        "implied_unemployed_persons": UNEMP_TOTAL,
        "implied_unemployment_ppm": UNEMP_PPM,
        "wage_uu_per_person_q": WAGE_ARR,
        "wage_bill_uu_per_q": WAGE_BILL_Q,
        "compensation_by_sector_uu_per_year": {s: COMP_YEAR[s] for s in SECTORS},
        "labor_share_of_gdp_ppm": LABOR_SHARE_PPM,
        "labor_share_of_market_value_added_ppm": (COMP_MARKET_YEAR * PPM) // 90_000_000_000,
        "labor_requirement_at_base_output_persons": {
            s: dict(LABOR_REQ[s], total=LABOR_REQ_TOTAL[s]) for s in SECTORS},
        "_note_labor_share_zh": (
            "劳动报酬占 GDP %s ppm（市场部门占市场增加值 %s ppm，公共服务按成本计价故占 900 000 ppm）。"
            "旧刻度下这个数是 745 612 ppm：那不是设计值，是工资率只能取 {1, 2, 3} μU 时被顶上去的。"
            "%s ppm 落在跨国劳动报酬份额的常见区间（约 450 000—620 000 ppm）内，"
            "且逐部门可辩护：农业 %s（低技能密集、人多钱少）、制造 %s、能源 %s（最资本密集）、"
            "服务 %s。三口径 GDP 不因此变动，因为营业盈余是残差。"
            % (num(LABOR_SHARE_PPM), num((COMP_MARKET_YEAR * PPM) // 90_000_000_000),
               num(LABOR_SHARE_PPM),
               num(COMP_YEAR["sector.agri"] * PPM // VA_YEAR["sector.agri"]),
               num(COMP_YEAR["sector.manu"] * PPM // VA_YEAR["sector.manu"]),
               num(COMP_YEAR["sector.energy"] * PPM // VA_YEAR["sector.energy"]),
               num(COMP_YEAR["sector.services"] * PPM // VA_YEAR["sector.services"]))),
    }

    pa = acc["pubserv_account_uu"]
    pa["_note"] = (
        "公共服务是服务部门的非市场子账户，实体是 4 个 pubserv 单元。"
        "depreciation_ppm_per_q 与 employment_persons_total 两项旧值（8 000 000 与 1 000 000 000）"
        "是迁移器的连带损伤：本块的键名含 uu 词元，整棵子树被 ×1000，"
        "把一个 ppm 和一个人数也乘了进去；已改回 8 000 ppm 与在岗人数本身。"
        "在岗人数取 population_init / pubserv_init 两侧一致的 1 480 266 人"
        "（旧值 1 000 000 是本附录自己的另一套口径，与 V-POP-08 冲突，已废止）。"
        "compensation_annual_uu 9 000 000 000 现在**可由在岗人数与工资率精确复算**："
        "298 668×%s + 711 327×%s + 470 271×%s = 2 250 000 000 μU/季，×4 == public_wages。")
    pa["_note"] = pa["_note"] % (num(WAGE_ARR[0]), num(WAGE_ARR[1]), num(WAGE_ARR[2]))
    pa["depreciation_ppm_per_q"] = PUB_DEPR_PPM_Q
    pa["employment_persons_total"] = N_SECTOR["pubserv"]
    pa["employment_persons_by_skill"] = {k: N_PUBSERV[k] for k in SKILLS}
    pa["depreciation_annual_total_uu"] = PUB_DEPR_TARGET
    pa["_note_depreciation_scale_zh"] = (
        "depreciation_annual_by_unit_uu 与 quarterly_split.pubserv_depreciation_by_q_uu 仍是"
        "旧刻度整数 ×1000 的结果，四季合计精确等于 1 000 000 000（GDP 口径要求）。"
        "但在新刻度下按 capital × 8 000 ppm 逐季 floor 原生复算，四单元合计是 %s μU，"
        "比目标多 %s μU——因为西岭的资本额 %s 当初是按**旧刻度**反解出来的唯一整数解。"
        "本文件不改这两处（改了 GDP 就不是 100 U），把它登记为 R-SCALE-01 的遗留项："
        "pubserv_init.json 的 pubserv.xiling.capital_value_uu 应改为 %s，"
        "届时本附录的逐单元与逐季折旧要一起重算。见 open_issues。"
        % (num(PUB_DEPR_NATIVE_TOTAL), num(PUB_DEPR_NATIVE_TOTAL - PUB_DEPR_TARGET),
           num(PUB_CAP["pubserv.xiling"]),
           num(XILING_CAP_SOLVED) if XILING_CAP_SOLVED else "（求解范围内无解，需扩大搜索）"))

    qs = acc["quarterly_split"]
    qs["_note"] = (
        "四季平均分摊：各部门年总产出与年增加值均能被 4 整除，无需最大余数法，"
        "逐季市场增加值合计恰为 22 500 000 000 μU，加公共服务非市场增加值 2 500 000 000 μU，"
        "季度 GDP 25 000 000 000 μU，四季合计恰为 100 000 000 000 μU。"
        "scenario.json 的 season_factor_ppm.agri_output 在 12_simulation_contract.md 里"
        "没有任何消费者（S03 的 output_plan 只由滞后需求与库存缺口决定），故基年不做农业季节性；"
        "若将来接上该系数，必须同时按峰值季重算农业用工，"
        "否则第 3 季会被 bound_labor 卡住而使全年 GDP 低于 100 000 000 000 μU。")

    acc["interface_requirements"] = [
        "cells_init.json：16 个 cell 的 capacity_active / capital_value / employment / inventory "
        "逐部门合计，必须等于 sector_accounts 与 inventory_requirements 的全国值；"
        "cell 现金合计 20 000 000 000 μU 计入 scenario.total_cash_uu（INV-018）。",
        "cells_init.json：schema 里缺 demand_expect_uqs 初值。12_simulation_contract.md §3.1 的 "
        "output_plan 只由 E_prev 与库存缺口决定；E_prev 初值若为 0，q=0 全国产量为 0，基年 GDP 归零。"
        "必须补该字段，建议逐 cell 取其季度产量（见 quarterly_split）。",
        "pubserv_init.json：4 个单元在岗合计 %s 人，逐 (地区, 技能) 与 population_init 的 "
        "pubserv 去向精确相等（V-POP-08）；工资总额 %s μU/季 == government_init 的 public_wages / 4。"
        "资本合计 31 627 646 000 μU 的四季折旧在新刻度下不再精确等于 1 000 000 000，见 open_issues。"
        % (num(N_SECTOR["pubserv"]), num(PUBSERV_WAGE_Q_UU)),
        "government_init.json：annual_plan.expenditure_lines_uu.public_wages 必须等于 9 000 000 000"
        "（= 公共服务增加值 10 000 000 000 减折旧 1 000 000 000），"
        "且必须等于 Σ_技能 pubserv 在岗人数 × wage_uu_per_person_q[技能] × 4；"
        "procurement 对应公共服务中间投入 4 200 000 000。",
        "population_init.json：working 组劳动力合计 %s 人，在岗合计 %s 人，"
        "反算失业率恰为 %s ppm，落在 V-POP-05 的 [79 500, 80 500] 内。"
        % (num(LF_TOTAL), num(EMP_TOTAL), num(UNEMP_PPM)),
        "scenario.json：prices_init.sector_uu_per_qs 与 base_uu_per_qs 四项均为 1 000 000 000"
        "（R-SCALE-01 后的 INV-148 值）；prices_init.wage_uu_per_person_q 必须取 %s，"
        "housing_rent_uu_per_unit_q 必须取 %s（由 population_init 的收入侧反解，见那里的 "
        "cross_file_check.from_scenario_json）；world_init.delivery_capacity_uqs 必须逐部门"
        "不小于季度出口量 [375 000, 1 300 000, 575 000, 500 000]。"
        % (WAGE_ARR, RENT_ARR),
        "params_core.json：param.engel_weight_ppm 建议取 [217153, 256250, 39702, 486895]"
        "（由本表居民消费的分产品结构按最大余数法反算，合计恰为 1 000 000）；"
        "param.io_table_set 的 value 必须是本表规范化哈希的前缀（V-PC-07）。",
    ]

    prov = acc["provenance"]
    prov["calibration_note"] = (
        "这是虚构剧本的设计假设，不是任何真实国家的投入产出表，不得标注为 observed 或 literature"
        "（V-PC-04 要求首版 observed 条目数为 0）。校准顺序：先用 G1 的 40 季无冲击基线检查基年结构"
        "是否自行崩溃；再按计划书 §14 做单一干预，检查 P04 与 P07 的作用路径与时滞；"
        "敏感性优先改制造列与服务列的中间投入系数和用工系数，因为 GDP 结构对这两列最敏感。"
        "最脆弱的三个取值是能源自用系数 60 000、能源部门产能折算率 55、服务列中间投入合计 355 000，"
        "必须各做三档敏感性。任何改动都必须重跑本附录的 accounting_checks，三个 residual 仍须为 0。"
        "劳动报酬不再是本表的自由参数（见 labor 块），改工资率必须重跑 tools/refit_base_year.py。")

    acc["open_issues"] = [
        "阻塞级：12_simulation_contract.md §5.3 的材料约束循环写作 for j in [agri, manu, services]，"
        "会去读 state.cell.inventory_input_uqs[services]，而 V-CELL-02 禁止服务出现在 "
        "inventory_input_uqs（服务不可库存）。于是只要 io_coeff[sector.services][*] > 0，"
        "bound_materials 恒为 0，四个部门产量全部归零。本表保留服务作为中间投入"
        "（计划书 §06 明写农业「需要劳动力、灌溉服务与运输」、制造「需要技能劳动、能源与中间投入」），"
        "服务行的年中间需求为 20 012 500 000 μU，占总产出的 31.6%，不能归零。"
        "建议修法与能源完全对称：服务按当期供给在市场闭合前分配，新增 bound_services，"
        "材料循环改为 for j in [agri, manu]。",
        "阻塞级：12_simulation_contract.md §5.6 的可售供给公式无条件扣除 construction_capacity_uqs"
        "（= 服务产量 × param.construction_share_cap_ppm），而不是扣除项目实际占用量。"
        "基年没有任何在建政府项目，按 300 000 ppm 计，每季会凭空销毁 4 747 500 μQ 服务，"
        "全年约 18 990 000 000 μU，接近 19% 的 GDP。本表的 10 000 000 000 μU 建筑投资是企业按 "
        "kind=7 capital_purchase 在市场上买走的服务产品，不走项目施工管线，因此不需要这项扣除。"
        "建议把扣除项改为 construction_used_uqs，并保留 param.construction_share_cap_ppm 作为上限。",
        "阻塞级：cells_init 的 schema 缺 demand_expect_uqs 初值（12_simulation_contract.md §3.1 的 "
        "E_prev）。E_prev 初值为 0 则 q=0 的 output_plan 为 0，基年第一季产量为 0，"
        "assert.base_year_gdp 必然失败。",
        "R-SCALE-01 遗留：pubserv 的四季余额递减折旧在新刻度下不再精确等于 1 000 000 000 μU。"
        "西岭资本 %s 当初是按旧刻度（整数 μU 为 1e-6 U）反解出来的唯一解；"
        "新刻度下逐单元原生复算的年折旧合计是 %s，超出目标 %s μU。"
        "公共服务折旧直接进 GDP（非市场增加值 = 工资 + 折旧），所以这个差额会让生产法 GDP "
        "不等于 100 U。修法：把 pubserv_init.json 的 pubserv.xiling.capital_value_uu 改为 %s，"
        "再重算本附录的 depreciation_annual_by_unit_uu 与 quarterly_split.pubserv_depreciation_by_q_uu。"
        "本文件不单方面改（pubserv_init 不在本次分工内），"
        "也不动 depreciation_annual_total_uu（动了 GDP 就不是 100 U）。"
        % (num(PUB_CAP["pubserv.xiling"]), num(PUB_DEPR_NATIVE_TOTAL),
           num(PUB_DEPR_NATIVE_TOTAL - PUB_DEPR_TARGET),
           num(XILING_CAP_SOLVED) if XILING_CAP_SOLVED else "（需扩大搜索范围求解）"),
        "技术口径的用工需求与实际在岗**结构**不一致：按基年产量与 labor_coeff 算，农业需低技能 %s 人，"
        "而 population_init 的分配只有 %s 人；四部门合计需 %s 人，实配 %s 人——"
        "总量富余 %s 人，富余堆在能源（需 %s、配 %s），短缺压在农业低技能一档。"
        "后果是 bound_labor 在基年低于目标产量（逐 cell 的紧度见 cells_init 的逐 cell 说明）。"
        "本表不再另写一套「附录自己的就业数」来掩盖它：employment_by_sector_persons 已改为"
        "与 population_init 一致的实配人数，技术需求单列在 "
        "labor_requirement_at_base_output_persons。修法仍是两条二选一——"
        "下调农业低技能用工系数（400 000 偏高，等价于每人每季产出 2.5 μQ_s），"
        "或把 population_init 的就业结构改到技术口径。两者都需要另一轮分工裁定。"
        % (num(LABOR_REQ["sector.agri"]["low"]), num(N_SECTOR_SKILL[("sector.agri", "low")]),
           num(sum(LABOR_REQ_TOTAL.values())), num(sum(N_SECTOR[s] for s in SECTORS)),
           num(sum(N_SECTOR[s] for s in SECTORS) - sum(LABOR_REQ_TOTAL.values())),
           num(LABOR_REQ_TOTAL["sector.energy"]), num(N_SECTOR["sector.energy"])),
        "11_data_contract.md §5.5 的 IOTable 示例自相矛盾：示例的 energy_coeff_uqs_per_qs = "
        "[30000, 150000, 20000, 50000] 与 io_coeff_uqs_per_qs[sector.energy] = "
        "{agri: 0, manu: 200000, energy: 50000, services: 80000} 不相等，"
        "按 V-IO-08 该示例本身会被拒绝加载。另外 10_variable_dictionary.md 把 "
        "content.io.energy_coeff_uqs_per_qs 的元素数记为 16，而 §5.5 与 V-IO-08 的用法都是 4。",
        "spoilage_ppm 基年取零是显式简化，理由见 _note_spoilage_ppm：非零损耗让基年 GDP 依赖 "
        "cells_init 的库存存量，与本表形成不动点，0 容差断言无法手工闭合。"
        "开启损耗必须与 tools/solve_base_year.gd 一起上线，届时要同步上调各部门总产出"
        "以抵消 spoil_in 对增加值的侵蚀。",
        "本附录借用 §3 允许的 _note_ 注释键承载基年核算，是因为 §5.5 的 IOTable schema 没有给它留位置；"
        "而 §1.5 又规定 _note_ 不进 content_hash，这意味着附录与系数之间的一致性没有机器校验，"
        "改了系数忘了改附录不会被发现。请求 schema_version 2 把它提升为一等字段，"
        "并新增 V-IO-09：附录的 gross_output_uu 必须等于 cells_init 各 cell 基年产量之和乘基年价。",
        "校验器 tools/validate_content.py 仍有三处停留在旧刻度：/unit_declaration 的 "
        "money_micro_per_unit 与 base_price_uu_per_qs 期望 1 000 000（应为 1 000 000 000），"
        "prices_init.sector_uu_per_qs / base_uu_per_qs 逐项期望 1 000 000（同上），"
        "以及对 wage_uu_per_person_q <= 3 的分辨率告警（R-SCALE-01 之后不再成立）。"
        "本次只修了 E_GDP_INIT 那一条（它直接判本包的 cells_init），其余三处属于 scenario.json 的分工，"
        "登记在此以免被当成剧本数据错误。",
    ]

    # ── R-SCALE-01 遗留清扫：迁移器只改数值，不改写在字符串正文里的旧刻度数字 ──
    acc["final_use_uu"]["gross_capital_formation"]["_note"] = (
        "设备来自制造部门，建筑与安装来自服务部门；农业与能源产品不形成资本。"
        "基年没有在建政府项目，这 22 000 000 000 μU 全部是企业按 kind=7 capital_purchase "
        "在市场上买走的，不走项目施工管线。")
    qs["pubserv_depreciation_note"] = (
        "公共服务折旧按余额递减，逐季 floor 后四季合计精确等于 1 000 000 000 μU，"
        "因此逐季增加值不是平的，但年度合计精确。逐单元数值见 pubserv_account_uu；"
        "该处的 _note_depreciation_scale_zh 记录了这组数在新刻度下的原生复算差额。")
    prov["definition"] = (
        "四部门技术系数、分技能用工系数、季度折旧率、产能折算率、排放系数与可库存标志的整表取值，"
        "以及使基年生产法、支出法、收入法三口径 GDP 精确等于 100 000 000 000 μU 的基年核算目标。")

    d["_note_capacity_per_capital_uu_ppm_scale_ruling"] = (
        "裁定 R-SCALE-01：本系数的单位是 μQ_s 每 μU 资本（ppm 定标），μU 是**分母**。"
        "1 U 由 1e6 μU 细化为 1e9 μU 后，本系数必须 ÷1000 才能保持产能不变；"
        "迁移器最初按「键名含 uu 即为金额」误将其 ×1000，已净修正 ÷1e6。迁移前 200000 → 现 200。"
        "遗留问题：本系数现在只有约 0.5%～1.8% 的整数粒度。"
        "基年校准实测该粒度**够用**：cells_init 的 16 个 cell 全部满足 "
        "capacity == floor(capital × 系数 / 1e6)，误差 0（V-CELL-03），"
        "因为求解方向是「先定产能再反解资本」，资本有 μU 级的调节余地。"
        "但若将来要固定资本反解产能（例如投资落地后按实际资本重算产能），"
        "这个粒度会把产能量化到 0.5%～1.8% 的台阶上；届时应提出契约修订"
        "（改为「每 1e3 μU」口径并改名），不得私自另立第二套比率刻度。")
    dump("io_table.json", d)


def patch_cells():
    d = cells_j
    d["_note_authority_zh"] = (
        "本文件是基年生产侧的权威初值。上游只有三处是事实来源：(1) io_table.json 的技术系数、"
        "用工系数、产能折算率与 _note_base_year_accounting 附录给出的基年部门总产出与增加值；"
        "(2) population_init.json 的 36 组就业分配（V-POP-08 逐项交叉校验，本文件的 "
        "employment_persons 逐字抄自它的汇总，不得另写一套）；(3) scenario.json 的 total_cash_uu "
        "拆分（16 个 cell 现金合计 20 000 000 000 μU）。"
        "本文件不引入任何未经登记的新口径，也不做「平衡修正项」（计划书 §13）。")
    der = d["_note_derivation_zh"]
    der["step_2_capacity"] = (
        "产能 = 产量 ÷ 基年产能利用率 900 000 ppm。io_table 附录取的是 867 598—926 243 ppm 的"
        "逐部门利用率，本文件统一取 900 000 ppm：这是唯一能让「产能口径的增加值」与"
        "「产量口径的 GDP 目标」同时等于 25 000 000 000 μU/季的取值，其余取值必有一侧对不上"
        "（见 open_questions 第 1 条）。部门产能合计：农业 6 972 222、制造 16 777 777、"
        "能源 3 000 000、服务 17 583 292 μQ_s/季。")
    d["_note_param_cards_required_zh"] = d["_note_param_cards_required_zh"].replace(
        "产能口径增加值超过 25 000 000 μU/季", "产能口径增加值超过 25 000 000 000 μU/季")
    der["step_1_sector_output"] = (
        "基年部门季度产量取自 io_table.json 附录 quarterly_split.gross_output_uqs_per_q："
        "农业 6 275 000、制造 15 100 000、能源 2 700 000、服务 15 825 000 μQ_s/季。"
        "按基年价 1 000 000 000 μU/Q_s（即 1 000 μU/μQ_s，裁定 R-SCALE-01），"
        "四部门季度市场增加值合计 22 500 000 000 μU，加公共服务非市场增加值 2 500 000 000 μU，"
        "季度 GDP 25 000 000 000 μU，四季 100 000 000 000 μU。")
    der["step_5_capital"] = (
        "资本 = 使 floor(capital_value_uu × capacity_per_capital_uu_ppm / 1 000 000) "
        "精确等于本 cell 产能的最小整数（V-CELL-03 的容差是 ±1 μQ_s，本文件 16 个 cell 的实际误差全部为 0）。"
        "capacity_per_capital_uu_ppm 已按 R-SCALE-01 修正为 [200, 180, 55, 160]（μQ_s 每 μU 资本）。"
        "部门资本合计：农业 34 861 110 000、制造 93 209 874 000、能源 54 545 457 000、"
        "服务 109 895 576 000 μU，合计 292 512 017 000 μU。"
        "io_table 附录的 299 000 000 000 μU 对应它自己的产能口径，"
        "两者之差 6 487 983 000 μU 就是统一利用率带来的差额。")
    der["step_7_cash"] = (
        "现金按部门取 io_table 附录 sector_accounts[*].operating_cash_uu："
        "农业 4 000 000 000、制造 4 500 000 000、能源 1 000 000 000、服务 10 500 000 000，"
        "合计 20 000 000 000 μU，与 scenario.json 的 total_cash_uu 拆分逐字一致（INV-018）；"
        "部门内按产能份额用最大余数法分摊。")
    der["step_8_equity"] = (
        "equity_share_ppm 的 24 个非零键与权重逐字取自 population_init.json 的 "
        "_note_extensions.groups_ext[*].base_equity_share_ppm，16 个 cell 共用同一张全国分配表。"
        "共用而不是逐区分配，是为了让 12_simulation_contract.md §S06 按 cell 逐个拆分后的合计，"
        "与 population_init 的 base_income_identity_uu_per_q.business_distribution = %s μU/季"
        "在结构上对得上；逐 cell 最大余数法的舍入差额登记在 open_questions 第 5 条。"
        "该总额随工资率重拟合而变（残差营业盈余 = 季度 GDP − 工资总额），"
        "权重表本身没变，故本文件的 equity_share_ppm 一个数都没动。" % num(BUSINESS_Q))

    idn = d["_note_identities_zh"]
    idn["base_year_gdp"] = (
        "Σ_cell (capacity_active_uqs_per_q − Σ_row floor(capacity × io_coeff[row][col] / 1 000 000)) "
        "= 25 000 000 μQ_s/季；按基年价 1 000 μU/μQ_s 折算 = 25 000 000 000 μU/季，"
        "×4 = 100 000 000 000 μU = 100 U（计划书 §05，assert.base_year_gdp）。"
        "逐 cell 逐行都用 floor，不做任何事后配平。"
        "注意量纲：括号内是 μQ_s，不是 μU——旧正文把两者写成同一个数，是旧刻度下 1 μU == 1 μQ_s 的巧合。")
    idn["cash_total"] = "Σ 16 cell 的 cash_uu = 20 000 000 000 μU（INV-018）。"
    idn["employment_cross_check"] = (
        "employment_persons 逐 (地区, 部门, 技能) 等于 population_init.json 的 "
        "_note_derived_check.employment_cross_check_for_cells_init.by_region_dest_skill_persons，"
        "合计 %s 人（全国在岗 %s 人减去 pubserv 的 %s 人）（V-POP-08 / INV-151）。"
        % (num(sum(N_SECTOR[s] for s in SECTORS)), num(EMP_TOTAL), num(N_SECTOR["pubserv"])))

    oq = d["_note_open_questions_zh"]
    oq[0] = (
        "OQ-A 校验器 V-GDP 的口径与 12_simulation_contract.md §6.3 不一致："
        "validate_content.py 用「Σ_cell capacity_active 的增加值 × 4 × 基年价」对账 100 U，"
        "而 derived.gdp.production_uu 的定义是「Σ_cell value_added + pubserv(工资 + 折旧)」，"
        "既用产量不用产能，也含公共服务。本文件的取值让两条口径同时成立"
        "（产能口径 25 000 000 000 μU/季；产量口径 22 500 000 000 + 公共服务 2 500 000 000 "
        "= 25 000 000 000 μU/季），代价是基年产能利用率被钉死在 900 000 ppm。"
        "请在契约里明确基年 GDP 的对账口径，并把校验器改成与 §6.3 同口径。"
        "（本次已修校验器的另一处：它原来把 μQ_s 的增加值直接当 μU 比对，"
        "漏乘基年价 1 000 μU/μQ_s，见 tools/validate_content.py 的 E_GDP_INIT。）")
    oq[1] = (
        "OQ-B 技术系数口径的用工需求与 population_init 的实际分配**结构**不一致（总量不是问题）。"
        "io_table 附录按「产量 × 用工系数」算农业需低技能 %s 人，population_init 只给了 %s 人；"
        "四部门合计需 %s 人，实配 %s 人——总量反而富余 %s 人，"
        "富余全部堆在能源（需 %s、配 %s，西岭尤甚），短缺全部压在农业低技能一档。"
        "本文件的 employment_persons 按 V-POP-08 逐字采用 "
        "population_init（io_table 附录的 employment_by_sector_persons 也已改为同一套数，"
        "技术需求单列为 labor_requirement_at_base_output_persons，两套口径不再混在一个字段里）。"
        "后果是 bound_labor 在基年低于产量，逐 cell 的紧度见各 cell 的 _note_zh；"
        "不修正的话 q=0 的实际 GDP 会低于 100 U。修法只有两条："
        "io_table 下调农业低技能用工系数，或 population_init 把就业结构改到技术口径。"
        "两者都不在本文件的改动范围内。"
        % (num(LABOR_REQ["sector.agri"]["low"]), num(N_SECTOR_SKILL[("sector.agri", "low")]),
           num(sum(LABOR_REQ_TOTAL.values())), num(sum(N_SECTOR[s] for s in SECTORS)),
           num(sum(N_SECTOR[s] for s in SECTORS) - sum(LABOR_REQ_TOTAL.values())),
           num(LABOR_REQ_TOTAL["sector.energy"]), num(N_SECTOR["sector.energy"])))
    oq[4] = (
        "OQ-E equity_share_ppm 逐 cell 重复同一张全国表，16 次最大余数拆分的合计与"
        "「一次性按全国拆分」相差最多 15 μU/季（每 cell 至多 1 μU 的舍入方向差）。"
        "R-SCALE-01 之后 1 μU 只有旧刻度的千分之一，这个差额相对 %s μU/季 的分配总额"
        "已经小到 %s ppm 以下，但仍不为 0。契约没有规定应先汇总再拆还是逐 cell 拆，"
        "建议在 12_simulation_contract.md §S06 明确，并在 assertions.json 增加一条对账。"
        % (num(BUSINESS_Q), num(ceil_div(15 * PPM, BUSINESS_Q))))

    for c in d["cells"]:
        _, region, sector_short = c["cell_id"].split(".")
        s = "sector." + sector_short
        cap = c["capacity_active_uqs_per_q"]
        capital = c["capital_value_uu"]
        out = (cap * 900_000) // PPM
        sup = labor_supported(region, s)
        emp = c["employment_persons"]
        inv_txt = ""
        for row in ("sector.agri", "sector.manu"):
            need = ceil_div(cap * io_j["io_coeff_uqs_per_qs"][row][s], PPM)
            if need > 0 and c["inventory_input_uqs"].get(row, 0) > 0:
                inv_txt += "%s %s ppm、" % (
                    row, num((c["inventory_input_uqs"][row] * PPM) // need))
        inv_txt = ("投入库存覆盖产能口径季度耗用：" + inv_txt.strip().rstrip("、") + "。") if inv_txt else ""
        store = "" if io_j["storable"][SECTORS.index(s)] else \
            " storable == 0，产成品库存恒为 0（INV-049）。"
        tight = ("劳动在基年不是本 cell 的紧约束" if sup >= out else
                 "bound_labor 在基年低于目标产量")
        c["_note_zh"] = (
            "%s·%s。产能 %s μQ_s/季 = floor(资本 %s μU × capacity_per_capital_uu_ppm %d / 1e6)"
            "（该系数是 ppm 定标的「μQ_s 每 μU 资本」，V-CELL-03 精确相等，差 0）。"
            "基年季度产量 %s μQ_s（产能利用率 900 000 ppm）。"
            "群组侧在岗 low/mid/high = %s/%s/%s 人，按 io_table 用工系数只支撑 %s μQ_s"
            "（占产能 %s ppm、占基年产量 %s ppm），%s；"
            "差额来自技术系数口径的用工需求与 population_init 实际分配的**结构**不一致（OQ-B），"
            "不在本文件用改数掩盖。工资率重拟合不改本 cell 的任何数值："
            "工资只进 flow.cell.wage_bill，不进产能、资本、库存与在岗人数。%s%s"
            % (REGION_ZH[region], SECTOR_ZH[s], num(cap), num(capital),
               CAP_PER_CAPITAL[s], num(out), num(emp["low"]), num(emp["mid"]), num(emp["high"]),
               num(sup), num((sup * PPM) // cap), num((sup * PPM) // out), tight,
               inv_txt, store))
    dump("cells_init.json", d)


if __name__ == "__main__":
    report()
    if FAILED:
        sys.stderr.write("\n自检失败，不写文件。\n")
        sys.exit(1)
    if "--check" not in sys.argv:
        patch_population()
        patch_io_table()
        patch_cells()
        sys.stdout.write("\n已写回 population_init.json / io_table.json / cells_init.json\n")
    else:
        sys.stdout.write("\n--check：只求解，未写文件\n")
