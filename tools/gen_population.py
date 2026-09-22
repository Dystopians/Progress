# -*- coding: utf-8 -*-
"""生成 content/scenarios/chengwan/population.json（36 个人口群组初值）。
全部整数算术；拆分一律最大余数法；不做四舍五入。"""
import json, io, os
from math import gcd

PPM = 1_000_000
REGIONS = ["beiyuan", "zhongzhou", "haijia", "xiling"]
REGION_ZH = {"beiyuan": "北原", "zhongzhou": "中州", "haijia": "海岬", "xiling": "西岭"}
AGES = ["minor", "working", "elder"]
SKILLS = ["low", "mid", "high"]
SECTORS = ["sector.agri", "sector.manu", "sector.energy", "sector.services"]
DESTS = SECTORS + ["pubserv"]

REGION_POP = {"beiyuan": 9_000_000, "zhongzhou": 7_000_000, "haijia": 5_000_000, "xiling": 3_000_000}


def idiv_floor(a, b):
    return a // b if b > 0 else (_ for _ in ()).throw(ZeroDivisionError)


def mul_ppm(x, p):
    # rounding: floor, reason=不凭空多给
    return (x * p) // PPM


def split_lr(total, weights, keys=None):
    """最大余数法：Σ result == total 精确成立。"""
    n = len(weights)
    W = sum(weights)
    if W == 0:
        return [0] * n, total  # 余数显式返回，不静默丢失
    base = [(total * w) // W for w in weights]
    rem = [total * weights[i] - base[i] * W for i in range(n)]
    r = total - sum(base)
    if keys is None:
        keys = list(range(n))
    order = sorted(range(n), key=lambda i: (-rem[i], keys[i]))
    for i in order[:r]:
        base[i] += 1
    assert sum(base) == total
    return base, 0


def gid(r, a, k):
    return "group.%s.%s.%s" % (r, a, k)


# ---------------------------------------------------------------- 1 人口
AGE_SPLIT = {  # 每区 age 人口（整数，和 == 区人口）
    "beiyuan":   {"minor": 2_340_000, "working": 5_670_000, "elder":   990_000},
    "zhongzhou": {"minor": 1_540_000, "working": 4_550_000, "elder":   910_000},
    "haijia":    {"minor": 1_100_000, "working": 3_350_000, "elder":   550_000},
    "xiling":    {"minor":   660_000, "working": 1_860_000, "elder":   480_000},
}
SKILL_SPLIT = {  # 每 (区, age) 的技能/教育准备度人口
    ("beiyuan", "minor"):     (1_053_000, 1_053_000,   234_000),
    ("beiyuan", "working"):   (3_402_000, 1_814_400,   453_600),
    ("beiyuan", "elder"):     (  712_800,   237_600,    39_600),
    ("zhongzhou", "minor"):   (  385_000,   739_200,   415_800),
    ("zhongzhou", "working"): (1_592_500, 1_956_500, 1_001_000),
    ("zhongzhou", "elder"):   (  436_800,   345_800,   127_400),
    ("haijia", "minor"):      (  385_000,   528_000,   187_000),
    ("haijia", "working"):    (1_507_500, 1_407_000,   435_500),
    ("haijia", "elder"):      (  319_000,   187_000,    44_000),
    ("xiling", "minor"):      (  277_200,   297_000,    85_800),
    ("xiling", "working"):    (  967_200,   706_800,   186_000),
    ("xiling", "elder"):      (  307_200,   144_000,    28_800),
}
POP = {}
for r in REGIONS:
    for a in AGES:
        tri = SKILL_SPLIT[(r, a)]
        assert sum(tri) == AGE_SPLIT[r][a], (r, a, sum(tri), AGE_SPLIT[r][a])
        for i, k in enumerate(SKILLS):
            POP[(r, a, k)] = tri[i]
    assert sum(AGE_SPLIT[r].values()) == REGION_POP[r]
assert sum(POP.values()) == 24_000_000

# ---------------------------------------------------------------- 2 劳动参与
PARTICIPATION = {
    "beiyuan":   {"low": 700_000, "mid": 800_000, "high": 860_000},
    "zhongzhou": {"low": 660_000, "mid": 810_000, "high": 880_000},
    "haijia":    {"low": 690_000, "mid": 820_000, "high": 870_000},
    "xiling":    {"low": 670_000, "mid": 790_000, "high": 850_000},
}
LF = {}
for r in REGIONS:
    for k in SKILLS:
        LF[(r, k)] = mul_ppm(POP[(r, "working", k)], PARTICIPATION[r][k])
LF_TOTAL = sum(LF.values())

# ---------------------------------------------------------------- 3 就业
# 逐 (区, 技能) 的在岗人数（设计值；失业人数 = 劳动力 − 在岗，为派生量）
EMPLOYED = {
    ("beiyuan", "low"): 2_117_049, ("beiyuan", "mid"): 1_342_656, ("beiyuan", "high"):   371_372,
    ("zhongzhou", "low"):  948_048, ("zhongzhou", "mid"): 1_494_434, ("zhongzhou", "high"): 845_645,
    ("haijia", "low"):     948_640, ("haijia", "mid"): 1_087_977, ("haijia", "high"):     365_246,
    ("xiling", "low"):     563_781, ("xiling", "mid"):   508_119, ("xiling", "high"):     149_879,
}
for key, e in EMPLOYED.items():
    assert 0 <= e <= LF[key], key
EMP_TOTAL = sum(EMPLOYED.values())
UNEMP_TOTAL = LF_TOTAL - EMP_TOTAL
UNEMP_PPM = (UNEMP_TOTAL * PPM) // LF_TOTAL
assert UNEMP_PPM == 80_000, (UNEMP_TOTAL, LF_TOTAL, UNEMP_PPM)

# 分部门就业：逐 (区, 技能) 的五项去向，Σ == EMPLOYED（残差落在 pubserv）
SECTOR_SHARE = {  # 千分比：agri / manu / energy / services，pubserv = 1000 - Σ
    ("beiyuan", "low"):    (630, 100,  20, 210),
    ("beiyuan", "mid"):    (310, 180,  40, 330),
    ("beiyuan", "high"):   (120, 160,  60, 380),
    ("zhongzhou", "low"):  (140, 140,  10, 570),
    ("zhongzhou", "mid"):  ( 60, 150,  20, 530),
    ("zhongzhou", "high"): ( 30, 130,  30, 470),
    ("haijia", "low"):     (120, 400,  30, 400),
    ("haijia", "mid"):     ( 50, 420,  40, 390),
    ("haijia", "high"):    ( 30, 400,  60, 360),
    ("xiling", "low"):     (210, 120, 240, 370),
    ("xiling", "mid"):     (100, 140, 290, 360),
    ("xiling", "high"):    ( 40, 120, 340, 340),
}
EMP_BY_DEST = {}
for key, tot in EMPLOYED.items():
    sh = list(SECTOR_SHARE[key])
    pub_share = 1000 - sum(sh)
    assert pub_share > 0, key
    # rounding: lr, reason=在岗人数拆到五个去向，各项之和必须精确等于该组在岗人数
    vals, _ = split_lr(tot, sh + [pub_share])
    EMP_BY_DEST[key] = vals
    assert sum(EMP_BY_DEST[key]) == tot

SECTOR_TOTAL = {d: 0 for d in DESTS}
for key, v in EMP_BY_DEST.items():
    for i, d in enumerate(DESTS):
        SECTOR_TOTAL[d] += v[i]
assert sum(SECTOR_TOTAL.values()) == EMP_TOTAL

# ---------------------------------------------------------------- 4 住房
HOUSING = {}
PERSONS_PER_UNIT = 3  # param.persons_per_housing_unit
# regions.json 的 housing_stock_units（外部给定，本文件只读取以满足 V-POP-06）
REGION_HOUSING_STOCK = {"beiyuan": 3_050_000, "zhongzhou": 2_240_000,
                        "haijia": 1_620_000, "xiling": 1_020_000}
for r in REGIONS:
    # rounding: floor, reason=占用不得超过存量；中州与海岬受存量硬约束 -> 实际户均人数 > 3（拥挤）
    region_units = min(REGION_POP[r] // PERSONS_PER_UNIT, REGION_HOUSING_STOCK[r])
    keys = [(a, k) for a in AGES for k in SKILLS]
    w = [POP[(r, a, k)] for (a, k) in keys]
    alloc, _ = split_lr(region_units, w, keys=list(range(len(w))))
    for i, (a, k) in enumerate(keys):
        HOUSING[(r, a, k)] = alloc[i]
HOUSING_BY_REGION = {r: sum(HOUSING[(r, a, k)] for a in AGES for k in SKILLS) for r in REGIONS}

# ---------------------------------------------------------------- 5 财富权重（存款与持股同源）
WEALTH_W = {("minor", "low"): 0, ("minor", "mid"): 0, ("minor", "high"): 0,
            ("working", "low"): 10, ("working", "mid"): 30, ("working", "high"): 80,
            ("elder", "low"): 20, ("elder", "mid"): 50, ("elder", "high"): 120}
REGION_WEALTH = {"beiyuan": 80, "zhongzhou": 120, "haijia": 105, "xiling": 90}
GKEYS = [(r, a, k) for r in REGIONS for a in AGES for k in SKILLS]
wealth_w = [POP[g] * WEALTH_W[(g[1], g[2])] * REGION_WEALTH[g[0]] for g in GKEYS]

INVPOOL_CASH_UU = 9_000_000           # government_init.json: invpool.cash_uu
INVPOOL_BONDHOLD_UU = 34_000_000      # government_init.json: Σ(holder=="invpool") principal_outstanding_uu
DEPOSIT_TOTAL = INVPOOL_CASH_UU + INVPOOL_BONDHOLD_UU   # V-FIN-09 / INV-024，必须精确相等
dep_alloc, _ = split_lr(DEPOSIT_TOTAL, wealth_w)
DEPOSIT = dict(zip(GKEYS, dep_alloc))

EQUITY_PPM, _ = split_lr(PPM, wealth_w)   # 群组持股份额（OQ-205 的剧本侧取值）
EQUITY = dict(zip(GKEYS, EQUITY_PPM))

# ---------------------------------------------------------------- 6 收入（基年，μU/季）
QUARTERLY_GDP_UU = 25_000_000         # 基年季度名义 GDP（= 100 U / 4）
# scenario.json: prices_init.wage_uu_per_person_q（低/中/高）。工资收入 = 工资率 × 在岗人数，
# 与 S04 的算法完全一致，不另做分配，因此这里没有拆分余数。
WAGE_RATE_UU_PER_PERSON_Q = {"low": 1, "mid": 2, "high": 3}
WAGE = {}
for g in GKEYS:
    r, a, k = g
    e = EMPLOYED[(r, k)] if a == "working" else 0
    WAGE[g] = e * WAGE_RATE_UU_PER_PERSON_Q[k]
WAGE_BILL_Q = sum(WAGE.values())

# government_init.json: annual_plan.receipt_lines_uu.profit_tax = 7 200 000 / 年
PROFIT_TAX_Q = 1_800_000
PAYOUT_RATIO_PPM = 300_000            # param.payout_ratio_ppm
GROSS_SURPLUS_Q = QUARTERLY_GDP_UU - WAGE_BILL_Q
BUSINESS_Q = mul_ppm(GROSS_SURPLUS_Q - PROFIT_TAX_Q, PAYOUT_RATIO_PPM)
biz_alloc, _ = split_lr(BUSINESS_Q, wealth_w)
BUSINESS = dict(zip(GKEYS, biz_alloc))

# government_init.json 的 invpool 持债逐批次季度票息之和（8U×8000 + 7U×8500 + 10U×9500 + 9U×11000）
INTEREST_Q = (mul_ppm(8_000_000, 8_000) + mul_ppm(7_000_000, 8_500)
              + mul_ppm(10_000_000, 9_500) + mul_ppm(9_000_000, 11_000))
int_alloc, _ = split_lr(INTEREST_Q, [DEPOSIT[g] for g in GKEYS])
INTEREST = dict(zip(GKEYS, int_alloc))

# government_init.json: annual_plan.expenditure_lines_uu.statutory_transfers = 3 600 000 / 年。
# OQ-225 裁定养老金为 0，故基年法定转移全部是「已存在的基本失业救济」（P03 改的是它的资格与替代率），
# 按各组失业人数分配。若剧本意图是基年零转移，应把 government_init 的该行改为 0，而不是在这里写 0。
TRANSFER_Q = 900_000
transfer_w = [(LF[(g[0], g[2])] - EMPLOYED[(g[0], g[2])]) if g[1] == "working" else 0 for g in GKEYS]
tr_alloc, _ = split_lr(TRANSFER_Q, transfer_w)
TRANSFER = dict(zip(GKEYS, tr_alloc))

# government_init.json: annual_plan.receipt_lines_uu.income_tax = 10 400 000 / 年
INCOME_TAX_Q = 2_600_000
TAX_W = {"low": 60, "mid": 160, "high": 300}
tax_w = []
for g in GKEYS:
    r, a, k = g
    labour_part = WAGE[g] * TAX_W[k]
    capital_part = (BUSINESS[g] + INTEREST[g]) * 200
    tax_w.append(labour_part + capital_part)
tax_alloc, _ = split_lr(INCOME_TAX_Q, tax_w)
TAX = dict(zip(GKEYS, tax_alloc))

GROSS = {g: WAGE[g] + BUSINESS[g] + INTEREST[g] + TRANSFER[g] for g in GKEYS}
DISP_PRE = {g: GROSS[g] - TAX[g] for g in GKEYS}
assert all(v >= 0 for v in DISP_PRE.values())

SUPPORT_OUT_W_PPM = {"beiyuan": 320_000, "zhongzhou": 300_000, "haijia": 290_000, "xiling": 330_000}
SUPPORT_OUT = {g: 0 for g in GKEYS}
SUPPORT_IN = {g: 0 for g in GKEYS}
for r in REGIONS:
    pool = 0
    for k in SKILLS:
        g = (r, "working", k)
        out = mul_ppm(DISP_PRE[g], SUPPORT_OUT_W_PPM[r])   # rounding: floor
        SUPPORT_OUT[g] = out
        pool += out
    deps = [(r, a, k) for a in ("minor", "elder") for k in SKILLS]
    alloc, _ = split_lr(pool, [POP[g] for g in deps])
    for i, g in enumerate(deps):
        SUPPORT_IN[g] = alloc[i]
assert sum(SUPPORT_IN.values()) == sum(SUPPORT_OUT.values())

DISP = {g: DISP_PRE[g] - SUPPORT_OUT[g] + SUPPORT_IN[g] for g in GKEYS}
assert all(v > 0 for v in DISP.values()), [g for g in GKEYS if DISP[g] <= 0]

# 基年人均实际可支配收入基准（μU/人/年，floor；见 open question 关于分辨率）
BASE_PCI = {}
for g in GKEYS:
    BASE_PCI[g] = (DISP[g] * 4) // POP[g]
assert all(v > 0 for v in BASE_PCI.values()), [g for g in GKEYS if BASE_PCI[g] <= 0]

# ---------------------------------------------------------------- 7 现金
CASH_TOTAL = 9_000_000
cash_alloc, _ = split_lr(CASH_TOTAL, [DISP[g] for g in GKEYS])
CASH = dict(zip(GKEYS, cash_alloc))

# ---------------------------------------------------------------- 8 服务可及性（人口加权恒等 1e6）
REGION_ACCESS_DEV = {
    "beiyuan":   {"health": -150_000, "education": -120_000, "utility": -180_000},
    "zhongzhou": {"health":  120_000, "education":  200_000, "utility":   90_000},
    "haijia":    {"health":   60_000, "education":   40_000, "utility":  -60_000},
    "xiling":    {"health":  -60_000, "education":  -80_000, "utility":   40_000},
}
SKILL_ACCESS_DEV = {"low": -80_000, "mid": 0, "high": 100_000}
AGE_ACCESS_DEV = {"minor": 0, "working": 0, "elder": -20_000}

def solve_zero_weighted(dev, pops, keys):
    """调整若干项，使 Σ pop*dev == 0 精确成立；返回修正后的 dev。"""
    dev = dict(dev)
    R = sum(pops[g] * dev[g] for g in keys)
    # 第一步：整体平移
    c = -(R // 24_000_000)
    if c != 0:
        for g in keys:
            dev[g] += c
        R = sum(pops[g] * dev[g] for g in keys)
    # 第二步：按人口降序逐项吸收
    for g in sorted(keys, key=lambda x: -pops[x]):
        if R == 0:
            break
        d = -(R // pops[g])
        if d != 0:
            dev[g] += d
            R = sum(pops[g2] * dev[g2] for g2 in keys)
    if R == 0:
        return dev
    # 第三步：两项扩展欧几里得（|R| < min pop）
    cand = sorted(keys, key=lambda x: -pops[x])
    for i in range(len(cand)):
        for j in range(i + 1, len(cand)):
            a, b = pops[cand[i]], pops[cand[j]]
            gg = gcd(a, b)
            if R % gg:
                continue
            found = None
            for x in range(-20000, 20001):
                rest = -R - a * x
                if rest % b == 0:
                    y = rest // b
                    if abs(y) <= 20000:
                        found = (x, y)
                        break
            if found:
                dev[cand[i]] += found[0]
                dev[cand[j]] += found[1]
                assert sum(pops[g2] * dev[g2] for g2 in keys) == 0
                return dev
    raise AssertionError("no exact solution")

POPS = {g: POP[g] for g in GKEYS}
# state.group.service_access_ppm 的区间是 0..1 000 000（10 号文件 §6.3），
# 而 V-POP-07 要求人口加权值 == 1 000 000。两条同时成立 ⇒ 36 组必须全为 1 000 000。
# 采纳 12 号文件 §7.8 的口径：access = 本组实获服务 / 本组基年基准，基年恒为满值。
ACCESS = {g: {"health": PPM, "education": PPM, "utility": PPM} for g in GKEYS}
# 开局的服务水平差异改由「基年人均交付基准指数」承载（可 > 1e6），
# 它是 §7.8 里 base_delivered_g 的口径，由 pubserv_init 的容量分配复现。
DELIVERY = {}
for kind in ("health", "education", "utility"):
    raw = {g: REGION_ACCESS_DEV[g[0]][kind] + SKILL_ACCESS_DEV[g[2]] + AGE_ACCESS_DEV[g[1]]
           for g in GKEYS}
    fixed = solve_zero_weighted(raw, POPS, GKEYS)
    for g in GKEYS:
        v = PPM + fixed[g]
        assert v > 0, (kind, g, v)
        DELIVERY.setdefault(g, {})[kind] = v
for kind in ("health", "education", "utility"):
    assert sum(POP[g] * DELIVERY[g][kind] for g in GKEYS) == PPM * 24_000_000

# ---------------------------------------------------------------- 9 态度三分量
REGION_TRUST = {"beiyuan": 560_000, "zhongzhou": 620_000, "haijia": 590_000, "xiling": 500_000}
REGION_EXPECT = {"beiyuan": 960_000, "zhongzhou": 1_040_000, "haijia": 1_080_000, "xiling": 880_000}
SKILL_EXPECT = {"low": -60_000, "mid": 0, "high": 70_000}
SKILL_TRUST = {"low": -40_000, "mid": 0, "high": 50_000}
AGE_EXPECT = {"minor": 60_000, "working": 0, "elder": -80_000}
AGE_TRUST = {"minor": 0, "working": 0, "elder": 40_000}
SUPPORT_W = (400_000, 300_000, 300_000)   # 生活 / 预期 / 信任（param.support_weight_ppm 的假设口径）
REGION_SUPPORT = {"beiyuan": 540_000, "zhongzhou": 580_000, "haijia": 560_000, "xiling": 470_000}
SKILL_SUPPORT = {"low": -20_000, "mid": 0, "high": 30_000}
AGE_SUPPORT = {"minor": 0, "working": 0, "elder": 20_000}

EXPECT, TRUST, SUPPORT, SUPPORT_IF_S08 = {}, {}, {}, {}
for g in GKEYS:
    r, a, k = g
    e = REGION_EXPECT[r] + SKILL_EXPECT[k] + AGE_EXPECT[a]
    t = REGION_TRUST[r] + SKILL_TRUST[k] + AGE_TRUST[a]
    EXPECT[g] = max(0, min(2 * PPM, e))
    TRUST[g] = max(0, min(PPM, t))
    # 开局支持度是剧本给定值（与 politics_init 的席位占比同量级），不是 S08 公式的回推值。
    SUPPORT[g] = max(0, min(PPM, REGION_SUPPORT[r] + SKILL_SUPPORT[k] + AGE_SUPPORT[a]))
    # 同时算出「若按 12 号文件 §8 的加权式重算会得到什么」，作为对账证据登记。
    SUPPORT_IF_S08[g] = max(0, min(PPM, (SUPPORT_W[0] * PPM + SUPPORT_W[1] * EXPECT[g]
                                         + SUPPORT_W[2] * TRUST[g]) // PPM))

SUPPORT_NATIONAL = sum(POP[g] * SUPPORT[g] for g in GKEYS) // 24_000_000
ADULT_POP = sum(POP[g] for g in GKEYS if g[1] != "minor")
SUPPORT_ADULT = sum(POP[g] * SUPPORT[g] for g in GKEYS if g[1] != "minor") // ADULT_POP

# ---------------------------------------------------------------- 10 集团归属
BLOC = {}
for g in GKEYS:
    r, a, k = g
    if a == "minor":
        BLOC[g] = [0, 0, 0]
        continue
    emp = EMP_BY_DEST[(r, k)] if a == "working" else None
    tot = EMPLOYED[(r, k)] if a == "working" else 1
    if a == "working":
        agri_sh = (emp[0] * PPM) // tot
        pub_sh = ((emp[1] + emp[4]) * PPM) // tot
    else:
        agri_sh = {"beiyuan": 520_000, "zhongzhou": 120_000, "haijia": 90_000, "xiling": 180_000}[r]
        pub_sh = 200_000
    agri = (agri_sh * 700) // 1000
    biz = {"low": 40_000, "mid": 120_000, "high": 320_000}[k]
    if r in ("haijia", "zhongzhou"):
        biz += 60_000
    if a == "elder":
        biz = (biz * 600) // 1000
    labor = (pub_sh * 800) // 1000
    if a == "elder":
        labor = (labor * 500) // 1000
    BLOC[g] = [min(PPM, agri), min(PPM, biz), min(PPM, labor)]

# ---------------------------------------------------------------- 11 人口队列参数
DEMOGRAPHY = {
    "birth_ppm_per_q": {"region.beiyuan": 5400, "region.zhongzhou": 4400,
                        "region.haijia": 4600, "region.xiling": 4800},
    "death_ppm_per_q": {"minor": 80, "working": 320, "elder": 20000},
    "age_out_ppm_per_q": {"minor": 13889, "working": 5319},
    "birth_target_skill": "low",
}

# ---------------------------------------------------------------- 12 组装 JSON
def region_id(r):
    return "region." + r


groups_json = []
for g in GKEYS:
    r, a, k = g
    working = (a == "working")
    emp_map = {}
    if working:
        for i, d in enumerate(DESTS):
            emp_map[d] = EMP_BY_DEST[(r, k)][i]
    else:
        for d in DESTS:
            emp_map[d] = 0
    groups_json.append({
        "group_id": gid(r, a, k),
        "population_persons": POP[g],
        "participation_ppm": PARTICIPATION[r][k] if working else 0,
        "employed_persons": emp_map,
        "cash_uu": CASH[g],
        "deposit_uu": DEPOSIT[g],
        "housing_units_occupied": HOUSING[g],
        "support_out_weight_ppm": SUPPORT_OUT_W_PPM[r] if working else 0,
        "service_access_ppm": {"health": ACCESS[g]["health"],
                               "education": ACCESS[g]["education"],
                               "utility": ACCESS[g]["utility"]},

        "consumption_index_ppm": PPM,
        "living_index_ppm": PPM,
        "base_per_capita_real_income_uu": BASE_PCI[g],
        "expectation_ppm": EXPECT[g],
        "trust_ppm": TRUST[g],
        "support_ppm": SUPPORT[g],
        "bloc_affiliation_ppm": BLOC[g],
    })

# ---- 住房成本与负担：租金下限 1 μU/套/季（10 号文件 §9.1 要求 > 0）
MIN_RENT = 1   # scenario.json: prices_init.housing_rent_uu_per_unit_q == [1, 1, 1, 1]
HOUSING_COST_MIN = {g: HOUSING[g] * MIN_RENT for g in GKEYS}
HOUSING_BURDEN_MIN = {g: (HOUSING_COST_MIN[g] * PPM) // DISP[g] for g in GKEYS}
HOUSING_BURDEN_TARGET_PPM = {"beiyuan": 140_000, "zhongzhou": 240_000,
                             "haijia": 200_000, "xiling": 150_000}
RENT_IMPLIED_BY_TARGET = {}
for r in REGIONS:
    disp_r = sum(DISP[(r, a, k)] for a in AGES for k in SKILLS)
    RENT_IMPLIED_BY_TARGET[r] = (disp_r * HOUSING_BURDEN_TARGET_PPM[r] // PPM) // HOUSING_BY_REGION[r]

MIGRATION_PROPENSITY = {"low": 1_200_000, "mid": 1_000_000, "high": 800_000}

groups_ext = []
for g in GKEYS:
    r, a, k = g
    working = (a == "working")
    lf = LF[(r, k)] if working else 0
    emp = EMPLOYED[(r, k)] if working else 0
    groups_ext.append({
        "group_id": gid(r, a, k),
        "label_zh": "%s·%s·%s" % (REGION_ZH[r],
                                  {"minor": "未成年", "working": "劳动年龄", "elder": "老年"}[a],
                                  {"low": "低", "mid": "中", "high": "高"}[k]),
        "in_labor_force": 1 if working else 0,
        "labor_force_persons": lf,
        "employed_persons_total": emp,
        "unemployed_persons": lf - emp,
        "unemployment_ppm_derived": ((lf - emp) * PPM) // lf if lf else 0,
        "base_income_lines_uu_per_q": {
            "wage": WAGE[g],
            "business_distribution": BUSINESS[g],
            "transfer": TRANSFER[g],
            "other_property_income": INTEREST[g],
            "household_support_in": SUPPORT_IN[g],
            "household_support_out": SUPPORT_OUT[g],
            "income_tax_paid": TAX[g],
        },
        "base_disposable_income_uu_per_q": DISP[g],
        "base_equity_share_ppm": EQUITY[g],
        "base_service_delivery_index_ppm": {
            "health": DELIVERY[g]["health"],
            "education": DELIVERY[g]["education"],
            "utility": DELIVERY[g]["utility"],
        },
        "housing": {
            "units_occupied": HOUSING[g],
            "persons_per_unit_assumed": PERSONS_PER_UNIT,
            "housing_cost_at_min_rent_uu_per_q": HOUSING_COST_MIN[g],
            "housing_burden_ppm_at_min_rent": HOUSING_BURDEN_MIN[g],
            "housing_burden_design_target_ppm": HOUSING_BURDEN_TARGET_PPM[r],
        },
        "migration": {
            "eligible_for_migration": 1 if working else 0,
            "relative_propensity_ppm": MIGRATION_PROPENSITY[k] if working else 0,
            "housing_gate_units_needed_per_1000_movers": 334,
        },
        "cohort_rates_ppm_per_q": {
            "birth_ppm_per_q": DEMOGRAPHY["birth_ppm_per_q"][region_id(r)] if working else 0,
            "death_ppm_per_q": DEMOGRAPHY["death_ppm_per_q"][a],
            "age_out_ppm_per_q": DEMOGRAPHY["age_out_ppm_per_q"].get(a, 0),
            "age_out_target": {"minor": "group.%s.working.%s" % (r, k),
                               "working": "group.%s.elder.%s" % (r, k),
                               "elder": "none"}[a],
            "age_in_source": {"minor": "birth", "working": "group.%s.minor.%s" % (r, k),
                              "elder": "group.%s.working.%s" % (r, k)}[a],
            "skill_up_ppm_per_q": 0,
            "skill_up_target": ("group.%s.%s.%s" % (r, a, {"low": "mid", "mid": "high"}[k]))
                               if k in ("low", "mid") else "none",
        },
    })

emp_matrix = {}
for r in REGIONS:
    for k in SKILLS:
        for i, d in enumerate(DESTS):
            key = "%s|%s|%s" % (region_id(r), d, k)
            emp_matrix[key] = EMP_BY_DEST[(r, k)][i]

derived_check = {
    "_note_zh": "本块是载入期冗余校验的算据；SimCore 不得从这里读任何值（INV-143）。",
    "total_population_persons": sum(POP.values()),
    "population_by_region_persons": {region_id(r): sum(POP[(r, a, k)] for a in AGES for k in SKILLS)
                                     for r in REGIONS},
    "population_by_age_persons": {a: sum(POP[(r, a, k)] for r in REGIONS for k in SKILLS)
                                  for a in AGES},
    "unemployment": {
        "formula": "labor_force_g = idiv_floor(population_persons_g * participation_ppm_g, 1000000)  [仅 working 组]；"
                   "employed_g = Σ_dest employed_persons[dest]；unemployed_g = labor_force_g - employed_g；"
                   "unemployment_ppm = idiv_floor(Σ_g unemployed_g * 1000000, Σ_g labor_force_g)",
        "numerator_unemployed_persons": UNEMP_TOTAL,
        "denominator_labor_force_persons": LF_TOTAL,
        "product_numerator_times_1e6": UNEMP_TOTAL * PPM,
        "unemployment_ppm": UNEMP_PPM,
        "expect_ppm": 80000,
        "labor_force_by_region_skill_persons": {"%s|%s" % (region_id(r), k): LF[(r, k)]
                                                for r in REGIONS for k in SKILLS},
        "employed_by_region_skill_persons": {"%s|%s" % (region_id(r), k): EMPLOYED[(r, k)]
                                             for r in REGIONS for k in SKILLS},
        "participation_rate_national_ppm": (LF_TOTAL * PPM) // sum(
            POP[(r, "working", k)] for r in REGIONS for k in SKILLS),
        "employment_rate_of_population_ppm": (EMP_TOTAL * PPM) // 24_000_000,
    },
    "employment_cross_check_for_cells_init": {
        "_note_zh": "V-POP-08 的对账表：cells_init.employment_persons 与 pubserv_init.employment_persons 必须逐项等于此表。",
        "by_region_dest_skill_persons": emp_matrix,
        "by_dest_persons": {d: SECTOR_TOTAL[d] for d in DESTS},
        "total_employed_persons": EMP_TOTAL,
    },
    "housing_cross_check_for_regions_init": {
        "_note_zh": "V-POP-06 要求逐地区 Σ housing_units_occupied ≤ regions.json 的 housing_stock_units。",
        "occupied_units_by_region": {region_id(r): HOUSING_BY_REGION[r] for r in REGIONS},
        "total_occupied_units": sum(HOUSING_BY_REGION.values()),
        "persons_per_housing_unit_assumed": PERSONS_PER_UNIT,
    },
    "index_base_check": {
        "_note_zh": "V-POP-07：三项服务可及性与两个指数的人口加权值必须精确等于 1000000。"
                    "因 service_access_ppm 的区间上限也是 1000000（10 号文件 §6.3），"
                    "两条约束联立的唯一解是 36 组全为 1000000；开局服务不平等改由 "
                    "extensions.groups_ext[].base_service_delivery_index_ppm 承载。",
        "weighted_sum_population_persons": 24_000_000,
        "weighted_service_access_ppm": {
            kind: sum(POP[g] * ACCESS[g][kind] for g in GKEYS) // 24_000_000
            for kind in ("health", "education", "utility")},
        "weighted_service_access_numerator": {
            kind: sum(POP[g] * ACCESS[g][kind] for g in GKEYS)
            for kind in ("health", "education", "utility")},
        "weighted_base_service_delivery_index_ppm": {
            kind: sum(POP[g] * DELIVERY[g][kind] for g in GKEYS) // 24_000_000
            for kind in ("health", "education", "utility")},
        "weighted_consumption_index_ppm": PPM,
        "weighted_living_index_ppm": PPM,
    },
    "housing_rent_resolution_check": {
        "_note_zh": "state.price.housing_rent_uu_per_unit_q 必须 > 0（10 号文件 §9.1）。"
                    "取最小可表达值 1 μU/套/季 时，全国住房支出已经占居民可支配收入的下列比重，"
                    "远高于设计目标 14%—24%，且没有更小的取值可选。这是 μU 刻度相对 2400 万人口过粗的直接后果。",
        "min_representable_rent_uu_per_unit_q": MIN_RENT,
        "total_occupied_units": sum(HOUSING_BY_REGION.values()),
        "national_housing_cost_at_min_rent_uu_per_q": sum(HOUSING_COST_MIN.values()),
        "national_disposable_income_uu_per_q": sum(DISP.values()),
        "national_housing_burden_ppm_at_min_rent":
            (sum(HOUSING_COST_MIN.values()) * PPM) // sum(DISP.values()),
        "design_target_burden_ppm_by_region": {region_id(r): HOUSING_BURDEN_TARGET_PPM[r]
                                               for r in REGIONS},
        "rent_implied_by_design_target_uu_per_unit_q": {region_id(r): RENT_IMPLIED_BY_TARGET[r]
                                                        for r in REGIONS},
        "rent_implied_numerator_uu_per_q": {
            region_id(r): (sum(DISP[(r, a, k)] for a in AGES for k in SKILLS)
                           * HOUSING_BURDEN_TARGET_PPM[r]) // PPM for r in REGIONS},
        "rent_implied_denominator_units": {region_id(r): HOUSING_BY_REGION[r] for r in REGIONS},
        "_note_squeeze_zh": "设计目标折算出的租金逐地区都 floor 成 0，而合法下限是 1，两者不相交："
                            "在当前货币刻度下，住房负担只能是 0%（租金 0，违反 > 0 的硬约束）"
                            "或 national_housing_burden_ppm_at_min_rent（租金 1，已远超设计目标），"
                            "没有第三种取值。租金是整数 μU/套/季，8 百万套住房与 25 U 的季度 GDP 之间"
                            "没有可用的中间刻度。",
    },
    "per_capita_resolution_check": {
        "_note_zh": "base_per_capita_real_income_uu 必须 > 0。基年全国可支配收入 / 人口 / 年 的量级见下，"
                    "只有个位数 μU，意味着 living_index 的人均归一化只有约 1 位有效数字。"
                    "建议改用融合表达式 real_income_norm_ppm = (income * base_pop * 1000000) / (base_income * pop)，"
                    "避免人均中间取整。",
        "national_annual_disposable_income_uu": sum(DISP.values()) * 4,
        "national_population_persons": 24_000_000,
        "base_per_capita_real_income_uu_min": min(BASE_PCI.values()),
        "base_per_capita_real_income_uu_max": max(BASE_PCI.values()),
        "distinct_values_count": len(set(BASE_PCI.values())),
    },
    "deposit_cross_check_for_government_init": {
        "_note_zh": "V-FIN-09 / INV-024：Σ group.deposit_uu 必须等于 invpool.cash_uu + Σ(holder==invpool) principal_outstanding_uu。",
        "sum_group_deposit_uu": sum(DEPOSIT.values()),
        "required_invpool_cash_plus_bondhold_uu": DEPOSIT_TOTAL,
    },
    "cash_cross_check_for_scenario": {
        "_note_zh": "INV-018：scenario.total_cash_uu 必须包含此项。",
        "sum_group_cash_uu": sum(CASH.values()),
    },
    "cross_file_check": {
        "_note_zh": "本块登记本文件读取过的兄弟文件取值；任一方改动而另一方未改，这里就会对不上。"
                    "SimCore 不得从这里读值（INV-143）。",
        "from_regions_json": {
            "housing_stock_units": {region_id(r): REGION_HOUSING_STOCK[r] for r in REGIONS},
            "occupied_units_written_here": {region_id(r): HOUSING_BY_REGION[r] for r in REGIONS},
            "occupancy_ratio_ppm": {region_id(r): (HOUSING_BY_REGION[r] * PPM) // REGION_HOUSING_STOCK[r]
                                    for r in REGIONS},
            "implied_persons_per_occupied_unit_ppm": {
                region_id(r): (REGION_POP[r] * PPM) // HOUSING_BY_REGION[r] for r in REGIONS},
            "migration_cap_housing_persons": {
                region_id(r): max(0, REGION_HOUSING_STOCK[r] * PERSONS_PER_UNIT - REGION_POP[r])
                for r in REGIONS},
            "_note_zh": "中州与海岬的住房存量低于「人口 / 3」，占用被存量顶住，实际户均人数 > 3；"
                        "同时 12 号文件 §7.5 的 cap_housing = stock×3 − 人口 在这两区为 0，"
                        "即开局不接受任何净迁入。这是 regions.json 取值的直接后果，登记备查。",
        },
        "from_government_init_json": {
            "invpool_cash_uu": INVPOOL_CASH_UU,
            "invpool_bondhold_uu": INVPOOL_BONDHOLD_UU,
            "required_sum_group_deposit_uu": DEPOSIT_TOTAL,
            "actual_sum_group_deposit_uu": sum(DEPOSIT.values()),
            "invpool_quarterly_coupon_uu": INTEREST_Q,
            "income_tax_quarter_uu": INCOME_TAX_Q,
            "profit_tax_quarter_uu": PROFIT_TAX_Q,
            "statutory_transfers_quarter_uu": TRANSFER_Q,
        },
        "from_scenario_json": {
            "wage_uu_per_person_q": [WAGE_RATE_UU_PER_PERSON_Q[k] for k in SKILLS],
            "housing_rent_uu_per_unit_q": [MIN_RENT] * 4,
            "implied_wage_bill_uu_per_q": WAGE_BILL_Q,
            "implied_labor_share_of_quarterly_gdp_ppm": (WAGE_BILL_Q * PPM) // QUARTERLY_GDP_UU,
            "residual_gross_operating_surplus_uu_per_q": GROSS_SURPLUS_Q,
            "sum_group_cash_uu_for_total_cash_reconciliation": sum(CASH.values()),
            "_note_zh": "工资率 [1,2,3] μU/人/季 是当前刻度下的最小可表达阶梯，"
                        "它把劳动报酬份额顶到 74.6%，只给营业盈余留下 25.4%；"
                        "相邻技能档的工资差是 100% 与 50%，没有中间值可调。",
        },
    },
    "base_income_identity_uu_per_q": {
        "_note_zh": "基年每季居民收入分解；各项之和逐项精确对账（拆分均用最大余数法）。",
        "wage": sum(WAGE.values()),
        "business_distribution": sum(BUSINESS.values()),
        "transfer": sum(TRANSFER.values()),
        "other_property_income": sum(INTEREST.values()),
        "gross_household_income": sum(GROSS.values()),
        "income_tax_paid": sum(TAX.values()),
        "household_support_in": sum(SUPPORT_IN.values()),
        "household_support_out": sum(SUPPORT_OUT.values()),
        "disposable_income": sum(DISP.values()),
        "quarterly_nominal_gdp_reference_uu": QUARTERLY_GDP_UU,
        "wage_share_of_quarterly_gdp_ppm": (sum(WAGE.values()) * PPM) // QUARTERLY_GDP_UU,
    },
    "support_national_check": {
        "population_weighted_support_ppm": SUPPORT_NATIONAL,
        "adult_weighted_support_ppm": SUPPORT_ADULT,
        "support_ppm_if_recomputed_by_s08_formula": {
            "population_weighted": sum(POP[g] * SUPPORT_IF_S08[g] for g in GKEYS) // 24_000_000,
            "adult_weighted": sum(POP[g] * SUPPORT_IF_S08[g] for g in GKEYS if g[1] != "minor")
                              // ADULT_POP,
            "_note_zh": "12 号文件 §8 的 support = Σ w_i × (living, expectation, trust)。"
                        "因 living_index_ppm 的基年值就是 1000000（满分口径），该式在第 0 季末会把支持度"
                        "从剧本给定的约 54% 直接推到约 87%，与 politics_init 的席位占比脱节。"
                        "这是公式口径问题，不是本文件的初值问题，已登记为待决问题。",
        },
        "seats_reference": {"seats_total": 101, "seats_gov": 56,
                            "seats_gov_share_ppm": (56 * PPM) // 101},
        "_note_zh": "与 politics_init.seats_gov / seats_total 的席位占比应处在同一量级；"
                    "未成年组是否计入支持度加权见待决问题（本文件同时给出含/不含未成年的两个口径）。",
    },
    "demography_flow_check_persons_per_q": {
        "births": sum(mul_ppm(sum(POP[(r, "working", k)] for k in SKILLS),
                              DEMOGRAPHY["birth_ppm_per_q"][region_id(r)]) for r in REGIONS),
        "deaths": sum(mul_ppm(POP[g], DEMOGRAPHY["death_ppm_per_q"][g[1]]) for g in GKEYS),
        "minor_to_working": sum(mul_ppm(POP[g], DEMOGRAPHY["age_out_ppm_per_q"]["minor"])
                                for g in GKEYS if g[1] == "minor"),
        "working_to_elder": sum(mul_ppm(POP[g], DEMOGRAPHY["age_out_ppm_per_q"]["working"])
                                for g in GKEYS if g[1] == "working"),
        "_note_zh": "首版人口不要求平稳：净自然增长为正、老年组缓慢变大，是剧本有意保留的结构压力。",
    },
}

source_cards = [
    {"card_id": "card.population_region_split", "scope": "groups[].population_persons（地区层）",
     "value": [9000000, 7000000, 5000000, 3000000], "unit": "persons",
     "source_type": "design_assumption",
     "source_ref": "计划书 §05「地区 人口：北原 900 万 / 中州 700 万 / 海岬 500 万 / 西岭 300 万」",
     "reference_year": 0,
     "definition": "四地区常住人口，合计 2400 万；是剧本硬约束，不是可调参数。",
     "valid_range": [[9000000, 9000000], [7000000, 7000000], [5000000, 5000000], [3000000, 3000000]],
     "confidence": "high",
     "calibration_note": "计划书锁定值，任何改动都是剧本变更而非校准；由 V-POP-02 与 assert.region_population 守住。"},
    {"card_id": "card.age_structure", "scope": "groups[].population_persons（年龄层）",
     "value": [5640000, 15430000, 2930000], "unit": "persons",
     "source_type": "design_assumption",
     "source_ref": "计划书 §08「年龄层为未成年、劳动年龄与老年」；§14「宽年龄组只适合首版近似」",
     "reference_year": 0,
     "definition": "全国未成年 / 劳动年龄 / 老年人口（分别 23.50% / 64.29% / 12.21%），按地区经济性质差异化：北原最年轻、西岭最老。",
     "valid_range": [[4800000, 6600000], [14400000, 16800000], [1920000, 4080000]],
     "confidence": "low",
     "calibration_note": "校准顺序：先固定 age_out_ppm_per_q 对应的年龄跨度（18 年 / 47 年），再看 40 季末老年占比是否落在 15%—18%；偏离则先动本卡而非动死亡率。"},
    {"card_id": "card.skill_structure", "scope": "groups[].population_persons（技能/教育准备度层）",
     "value": [0, 0, 0], "unit": "persons",
     "source_type": "design_assumption",
     "source_ref": "计划书 §05 各地区「优势」与「开局主要约束」；§08「儿童档位代表教育准备程度，不代表劳动技能」",
     "reference_year": 0,
     "definition": "劳动年龄组按受教育程度分低/中/高；未成年组的档位是教育准备程度；老年组反映历史受教育水平（低于当前劳动年龄组）。具体逐组取值见 groups[]。",
     "valid_range": [[0, 24000000], [0, 24000000], [0, 24000000]],
     "confidence": "low",
     "calibration_note": "与 io_table 的 labor_coeff_persons_per_qs 联调：若某 cell 的 bound_labor 在 q=0 就是最紧约束且不是剧本有意设计的瓶颈，先查本卡而非改系数。"},
    {"card_id": "card.participation", "scope": "groups[].participation_ppm",
     "value": [660000, 880000], "unit": "ppm",
     "source_type": "design_assumption",
     "source_ref": "计划书 §05「失业率 8%，分母是劳动力，不是总人口；由初始就业分配反算」；[3] ILOSTAT 作为口径来源（数据尚未导入）",
     "reference_year": 0,
     "definition": "劳动年龄组的劳动参与率（劳动力 / 该组人口）区间；非劳动年龄组恒为 0。全国加权参与率见 derived_check。",
     "valid_range": [400000, 950000],
     "confidence": "low",
     "calibration_note": "本卡与 card.employment_allocation 共同决定失业率；调参时先固定参与率，再调就业分配，避免两头同时动导致 8% 反算失效。"},
    {"card_id": "card.employment_allocation", "scope": "groups[].employed_persons",
     "value": 10742846, "unit": "persons",
     "source_type": "design_assumption",
     "source_ref": "计划书 §05「由初始就业分配反算」；§03「36 群组；就业在组内用比例记录」",
     "reference_year": 0,
     "definition": "全国在岗人数；逐 (地区, 技能) 按部门比例分配到 4 个市场部门与 pubserv，残差显式落在 pubserv，不做静默丢弃。",
     "valid_range": [9000000, 12000000],
     "confidence": "low",
     "calibration_note": "改动本卡必须同步改 cells_init / pubserv_init（V-POP-08 逐项交叉校验），并重跑失业率反算（V-POP-05）。"},
    {"card_id": "card.wage_income_base_year",
     "scope": "extensions.groups_ext[].base_income_lines_uu_per_q.wage",
     "value": [1, 2, 3], "unit": "μU/人/季",
     "source_type": "derived",
     "source_ref": "scenario.json prices_init.wage_uu_per_person_q；计划书 §06 收入法分解",
     "reference_year": 0,
     "definition": "基年群组工资收入。derivation_expr: wage[g] = employed_persons_total[g] × wage_uu_per_person_q[skill]，与 12 号文件 S04 的算法逐字一致，因此不产生任何拆分余数。由此得出的劳动报酬份额见 derived_check.cross_file_check。",
     "valid_range": [[1, 20000000], [1, 20000000], [1, 20000000]],
     "confidence": "low",
     "calibration_note": "本卡的值不是本文件选的，而是 scenario.json 给的；工资率一改，本文件必须重新生成。当前刻度下相邻技能档只能差 100% / 50%，没有中间值——这是货币刻度问题，不要靠改工资率掩盖。"},
    {"card_id": "card.household_wealth_weight", "scope": "groups[].deposit_uu 与 extensions.groups_ext[].base_equity_share_ppm",
     "value": 43000000, "unit": "μU",
     "source_type": "design_assumption",
     "source_ref": "计划书 §07「居民投资池或外部债权人买入政府债券」；11 号文件 V-FIN-09",
     "reference_year": 0,
     "definition": "居民对投资池的存款债权总额（= 43 U = invpool.cash_uu 9 U + invpool 持债 34 U，约为基年名义 GDP 的 43%）；按 (人口 × 年龄技能财富权重 × 地区财富权重) 最大余数法分配。同一组权重也用作企业持股份额（OQ-205）。",
     "valid_range": [20000000, 80000000],
     "confidence": "low",
     "calibration_note": "必须与 government_init 的 invpool.cash_uu 与 invpool 持债之和逐 μU 相等；两边不一致时改 government_init，不改本卡的分配方式。"},
    {"card_id": "card.household_cash", "scope": "groups[].cash_uu",
     "value": 9000000, "unit": "μU",
     "source_type": "design_assumption",
     "source_ref": "12 号文件 S-14「居民可支配预算 = 已到手工资 + 转移 + 赡养净额 + dissave 比例的存款，且不超过当前现金」",
     "reference_year": 0,
     "definition": "开局居民手持现金合计（约等于基年一个季度可支配收入的 48%），按各组可支配收入最大余数法分配。必须计入 scenario.total_cash_uu（INV-018）。",
     "valid_range": [2000000, 15000000],
     "confidence": "low",
     "calibration_note": "若 q=0 出现大量 flow.group.unmet_consumption_uu 且原因是现金不足而非配给，先提高本卡再查消费规则。"},
    {"card_id": "card.income_tax_base_year", "scope": "extensions.groups_ext[].base_income_lines_uu_per_q.income_tax_paid",
     "value": 2600000, "unit": "μU",
     "source_type": "derived",
     "source_ref": "government_init.json annual_plan.receipt_lines_uu.income_tax = 10 400 000 / 年；计划书 §05「全年收入 20 U」",
     "reference_year": 0,
     "definition": "基年每季个人所得税。derivation_expr: idiv_floor(government_init.annual_plan.receipt_lines_uu.income_tax, 4)。按 (工资 × 技能累进权重 60/160/300 + 资本性收入 × 200) 最大余数法分配到组，实际累进程度为派生结果。",
     "valid_range": [1500000, 4000000],
     "confidence": "low",
     "calibration_note": "本卡取值必须与 government_init.annual_plan.receipt_lines_uu.income_tax 一致；P01 生效后此值不再使用，只作为基年对账基准。"},
    {"card_id": "card.statutory_transfer_base_year",
     "scope": "extensions.groups_ext[].base_income_lines_uu_per_q.transfer",
     "value": 900000, "unit": "μU",
     "source_type": "derived",
     "source_ref": "government_init.json annual_plan.expenditure_lines_uu.statutory_transfers = 3 600 000 / 年；OQ-225「养老金为 0」；计划书 §09 P03「失业保障：资格、替代比例与持续期」",
     "reference_year": 0,
     "definition": "基年每季法定转移支付。derivation_expr: idiv_floor(statutory_transfers, 4)。按 OQ-225 老年组养老金为 0，故基年转移全部解释为已存在的基本失业救济（P03 改的是它的参数，不是从零创设），按各组失业人数最大余数法分配。",
     "valid_range": [0, 4000000],
     "confidence": "low",
     "calibration_note": "若剧本意图是基年零转移，必须把 government_init 的该行改为 0 并重新生成本文件；两边不能一边有预算一边无受益人。"},
    {"card_id": "card.business_distribution_base_year",
     "scope": "extensions.groups_ext[].base_income_lines_uu_per_q.business_distribution",
     "value": 300000, "unit": "ppm",
     "source_type": "derived",
     "source_ref": "param.payout_ratio_ppm（11 号文件 §5.15）；government_init.json receipt_lines_uu.profit_tax",
     "reference_year": 0,
     "definition": "企业向居民分配的经营性收入。derivation_expr: mul_ppm(季度名义 GDP − 工资总额 − 季度利润税, param.payout_ratio_ppm)，再按财富权重最大余数法分配。",
     "valid_range": [100000, 600000],
     "confidence": "low",
     "calibration_note": "工资率一改，残差营业盈余随之变化；本卡只固定分配比例，不固定金额。若 q=0 结算出的 flow.cell.distributed_uu 与此偏离，先查 io_table 与工资率。"},
    {"card_id": "card.support_out_weight", "scope": "groups[].support_out_weight_ppm",
     "value": [290000, 330000], "unit": "ppm",
     "source_type": "design_assumption",
     "source_ref": "10 号文件 §6.2 裁定「显式的组间赡养转移」；OQ-225「养老金为 0，老年组消费能力完全来自组间赡养转移」",
     "reference_year": 0,
     "definition": "劳动年龄组每季转出给同地区未成年与老年组的可支配收入比例；按地区抚养比差异化（北原 320000 / 中州 300000 / 海岬 290000 / 西岭 330000）。",
     "valid_range": [100000, 500000],
     "confidence": "low",
     "calibration_note": "OQ-225 的验证口径：40 季跑完后若 elder 组 living_index_ppm 系统性塌陷，先提高本卡，再考虑引入养老金政策（走 §03 范围闸门）。"},
    {"card_id": "card.service_access_init", "scope": "groups[].service_access_ppm",
     "value": 1000000, "unit": "ppm",
     "source_type": "derived",
     "source_ref": "10 号文件 §6.3（区间 0..1000000）与 11 号文件 V-POP-07（人口加权 == 1000000）联立",
     "reference_year": 0,
     "definition": "基年三项服务可及率。derivation_expr: 区间上限 == 加权均值 ⇒ 逐组唯一解 1000000。口径同 12 号文件 §7.8：access = 本组实获服务 / 本组基年基准，基年恒为满值。",
     "valid_range": [1000000, 1000000],
     "confidence": "high",
     "calibration_note": "本值不可调：任何一组低于 1000000 都会使 V-POP-07 失败。要表达开局服务不平等，改 card.service_delivery_dispersion，不要改这里。"},
    {"card_id": "card.service_delivery_dispersion",
     "scope": "extensions.groups_ext[].base_service_delivery_index_ppm",
     "value": [660000, 1240000], "unit": "ppm",
     "source_type": "design_assumption",
     "source_ref": "计划书 §05 各地区开局约束（北原技能岗位少、中州公共服务承压、海岬电网可靠性不足）；§08「公共服务可及性在组内记录」",
     "reference_year": 0,
     "definition": "基年人均服务交付基准指数，1000000 = 全国人均水平，人口加权和精确等于 1000000。地区效应 + 技能效应 + 年龄效应三项叠加后做整数修正。它是 12 号文件 §7.8 里 base_delivered_g 的口径，也是 pubserv_init 容量与地区分配必须复现的目标。",
     "valid_range": [300000, 1800000],
     "confidence": "low",
     "calibration_note": "改动任一组即破坏人口加权恒等式；必须用同一段修正程序重算全部 36 组，不得手工改单组。与 pubserv_init.service_capacity_split_ppm 联调。"},
    {"card_id": "card.housing_burden_target",
     "scope": "extensions.groups_ext[].housing.housing_burden_design_target_ppm",
     "value": [140000, 240000], "unit": "ppm",
     "source_type": "design_assumption",
     "source_ref": "计划书 §05「中州：住房容量紧张」；§04「查原因：地区差异、家庭负担」；OQ-244「租金固定，由剧本给出」",
     "reference_year": 0,
     "definition": "设计目标的住房支出占可支配收入比重（北原 140000 / 西岭 150000 / 海岬 200000 / 中州 240000）。当前 μU 刻度下无法用 > 0 的整数租金实现，实测值见 derived_check.housing_rent_resolution_check。",
     "valid_range": [80000, 350000],
     "confidence": "low",
     "calibration_note": "在货币刻度问题解决前，本卡只是设计意图，不是可实现值；解决后 scenario.json 的 housing_rent_uu_per_unit_q 应取 rent_implied_by_design_target_uu_per_unit_q。"},
    {"card_id": "card.attitude_init", "scope": "groups[].expectation_ppm / trust_ppm / support_ppm",
     "value": [880000, 1150000], "unit": "ppm",
     "source_type": "design_assumption",
     "source_ref": "计划书 §08「民众不是一个『满意度』：至少区分当期生活、未来预期与程序信任」",
     "reference_year": 0,
     "definition": "开局未来预期区间（信任区间 460000—710000，支持度区间 450000—630000）。三者分开存储，不合成为单一满意度。support_ppm 是剧本直接给定值，与 politics_init 的席位占比同量级；它不由 living/expectation/trust 回推，原因见 derived_check.support_national_check。",
     "valid_range": [0, 2000000],
     "confidence": "low",
     "calibration_note": "本卡假定的三项权重必须与 param.support_weight_ppm 一致（OQ-222）；不一致时以 param 为准并重生成本文件，不要在文件里手工对齐。"},
    {"card_id": "card.bloc_affiliation", "scope": "groups[].bloc_affiliation_ppm",
     "value": [0, 1000000], "unit": "ppm",
     "source_type": "design_assumption",
     "source_ref": "计划书 §08 三个利益集团及「成员可同时属于其他利益网络」",
     "reference_year": 0,
     "definition": "该组人口分别属于 [农业合作联盟, 工商业联盟, 劳动与公共服务联盟] 的比例；三项之和允许超过 1000000。农合比例由该组农业就业占比折出，劳公比例由制造业与公共部门就业占比折出，工商比例按技能档与地区给定。未成年组一律为 0。",
     "valid_range": [0, 1000000],
     "confidence": "low",
     "calibration_note": "OQ-223 登记了重叠计数问题；若 derived.bloc.membership_persons 之和明显超过成年人口且导致组织力失真，先改本卡的折算系数。"},
    {"card_id": "card.birth_rate", "scope": "demography_rates.birth_ppm_per_q",
     "value": [4400, 5400], "unit": "ppm/季",
     "source_type": "design_assumption",
     "source_ref": "计划书 §08「出生、死亡、成年、退休、技能转变和迁移必须有来源与去向」；§14「宽年龄组只适合首版近似，不用于精确人口预测」",
     "reference_year": 0,
     "definition": "每季出生人数 = 该地区劳动年龄人口 × 本率（分母是劳动年龄人口，不是总人口）。对应全国粗出生率约 12.5‰/年。新生儿全部落入 group.<r>.minor.low。",
     "valid_range": [1000, 12000],
     "confidence": "low",
     "calibration_note": "校验方式：derived_check.demography_flow_check_persons_per_q 的 births 与 deaths 之差应在 ±0.5%/年 之内；超出先查本卡与 card.death_rate 的搭配。"},
    {"card_id": "card.death_rate", "scope": "demography_rates.death_ppm_per_q",
     "value": [80, 320, 20000], "unit": "ppm/季",
     "source_type": "design_assumption",
     "source_ref": "计划书 §08；§17 质量门槛「出生死亡单独登记」",
     "reference_year": 0,
     "definition": "未成年 / 劳动年龄 / 老年的季度死亡率。老年 20000 ppm/季 对应约 8%/年，即 65 岁后余命约 12.5 年。死亡是唯一允许的净流出。",
     "valid_range": [[0, 500], [0, 1500], [5000, 40000]],
     "confidence": "low",
     "calibration_note": "粗死亡率目标 8‰—11‰/年；若 120 季压测中老年组人口单调爆炸，先提高老年死亡率，再考虑改年龄跨度。"},
    {"card_id": "card.age_out_rate", "scope": "demography_rates.age_out_ppm_per_q",
     "value": [13889, 5319], "unit": "ppm/季",
     "source_type": "derived",
     "source_ref": "由「未成年 18 年 = 72 季、劳动年龄 47 年 = 188 季」的年龄跨度假设倒算",
     "reference_year": 0,
     "definition": "成年转出（minor→working）与退休转出（working→elder）的季度比例。derivation_expr: idiv_floor(1000000 * 1, 72) 与 idiv_floor(1000000 * 1, 188)，分别得 13888.9→13889（向上取整以免年龄跨度被拉长）与 5319。",
     "valid_range": [[8000, 20000], [3000, 9000]],
     "confidence": "low",
     "calibration_note": "derivation_expr 可复算：72 季 ≈ 18 岁成年，188 季 ≈ 65 岁退休。改年龄跨度必须同时改本卡与 card.age_structure，否则年龄结构会与流量率相互矛盾。"},
    {"card_id": "card.housing_occupancy", "scope": "groups[].housing_units_occupied",
     "value": 3, "unit": "persons/unit",
     "source_type": "design_assumption",
     "source_ref": "param.persons_per_housing_unit（11 号文件 §5.15 首版必备参数最小集）",
     "reference_year": 0,
     "definition": "每套住房居住人数。逐地区占用套数 = idiv_floor(地区人口, 3)，再按各组人口用最大余数法分到 9 个组；未成年与老年组同样占用套数，其住房支出由组间赡养转移覆盖。",
     "valid_range": [2, 5],
     "confidence": "low",
     "calibration_note": "本卡必须与 param.persons_per_housing_unit 取同一个值，否则迁移的 cap_housing 闸与初始占用会自相矛盾；regions.json 的 housing_stock_units 必须 ≥ derived_check 给出的逐地区占用数。"},
]

payload = {
    "schema_kind": "population_init",
    "schema_version": 1,
    "_note_schema_kind": "结构按 11_data_contract.md §5.7 PopulationInit；文件名与契约的 population_init.json 不一致，见 open_questions。",
    "_note_extensions": "groups[] 与 demography_rates 严格只含 §5.7 已声明的键；derived_check 与 extensions 是本文件新增的两个顶层键，SimCore 不得读取（INV-143）。",
    "groups": groups_json,
    "demography_rates": DEMOGRAPHY,
    "derived_check": derived_check,
    "extensions": {
        "_note_zh": "本块不进 SimCore 状态。它承载计划书 §08 要求、而 §5.7 schema 目前没有位置安放的内容："
                    "收入来源构成、住房负担、迁移倾向、队列参数的逐组落点，以及每一族数值的身份证。",
        "extension_version": 1,
        "_note_base_service_delivery_index_zh":
            "12 号文件 §7.8 的 base_delivered_g 口径：1000000 = 基年全国人均交付水平，人口加权和精确等于 1000000。"
            "本指数承载开局的服务不平等；state.group.service_access_ppm 本身受 0..1000000 区间与 V-POP-07 "
            "双重约束，基年只能恒为 1000000。pubserv_init 的容量与地区分配应复现本指数。",
        "_note_housing_zh":
            "租金由 scenario.json 的 housing_rent_uu_per_unit_q 给出（OQ-244：首版固定不更新）。"
            "租金下限 1 μU/套/季 已经使住房负担远超设计目标，证据见 derived_check.housing_rent_resolution_check。",
        "_note_migration_zh":
            "迁移的拉力/推力权重与阈值是全局 param.migration_*（12 号文件 §7.5 只按地区对计算）。"
            "relative_propensity_ppm 是逐组的相对迁移倾向乘数，首版 SimCore 未消费，登记为待决扩展。",
        "_note_cohort_zh":
            "skill_up_ppm_per_q 恒为 0：计划书 §08「教育按队列结业，不在拨款当季让全民升级」，"
            "12 号文件 §7.6 规定技能档变化只能来自 education_cohort 的到期配对。"
            "该字段保留为口径说明，不是可调速率。出生/死亡/成年/退休的实际速率在 demography_rates，"
            "此处逐组重列只为满足「每组的队列参数都有来源与去向」的可读性要求。",
        "groups_ext": groups_ext,
        "source_cards": source_cards,
    },
}

out = "C:/Users/Fiber Memory/Documents/Jingwei/content/scenarios/chengwan/population.json"
os.makedirs(os.path.dirname(out), exist_ok=True)
text = json.dumps(payload, ensure_ascii=False, indent=2) + "\n"
with io.open(out, "w", encoding="utf-8", newline="\n") as f:
    f.write(text)

# ---- 自检：JSON 中不得出现浮点字面量 / null
import re
bad = re.findall(r':\s*-?\d+\.\d+', text)
assert not bad, bad[:5]
assert "null" not in text
print("written:", out, len(text), "bytes")
print("labor_force", LF_TOTAL, "employed", EMP_TOTAL, "unemployed", UNEMP_TOTAL, "ppm", UNEMP_PPM)
print("sector totals", SECTOR_TOTAL)
print("housing by region", HOUSING_BY_REGION, "total", sum(HOUSING_BY_REGION.values()))
print("support national ppm", SUPPORT_NATIONAL, "adult", SUPPORT_ADULT)
print("disposable total/q", sum(DISP.values()), "base_pci range",
      min(BASE_PCI.values()), max(BASE_PCI.values()))
print("access ranges", {kind: (min(ACCESS[g][kind] for g in GKEYS),
                               max(ACCESS[g][kind] for g in GKEYS))
                        for kind in ("health", "education", "utility")})
