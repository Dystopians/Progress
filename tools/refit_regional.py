# -*- coding: utf-8 -*-
"""tools/refit_regional.py —— 裁定 R-REGION-01 的内容重拟合（OQ-B 结案）。

背景（docs/18 R-REGION-01）：population_init 的逐 cell 在岗人数、cells_init 的逐 cell 基年产量、
io_table 全国统一的用工系数三者不一致。开局 S03 按「产量 × 系数」算出的用工需求远低于在岗人数，
第 0 季即大规模裁员（失业率由锁定的 8% 跳到 12% 以上）；西岭能源在岗 33 万人、工资 0.42 U/季，
产量却只有 0.46 Q/季（增加值 0.29 U/季），开局现金 0.17 U，付不起工资而停产并拖垮全区。

裁定与本脚本的做法（只改 content/scenarios/chengwan/ 下的内容文件）：

  1. **在岗人数是锚**：cells_init 的 employment_persons 与 population_init 的群组就业一个数都不改
     （它们钉住 8% 失业率与分部门劳动报酬）。
  2. **能源产量随就业走**：四个能源 cell 的基年季度产量之和（精确保持）按各地区能源 cell 的
     基年工资总额 Σ_k 在岗_k × wage_uu_per_person_q[k] 的份额，用最大余数法（平权按 cell 下标）重分到地区。
     其余部门的逐 cell 产量不动。产量改变的能源 cell 同步重算：
       - demand_expect_uqs = 新产量；
       - capacity_active_uqs_per_q：利用率 ≈ 900 000 ppm，且部门产能合计与 V-GDP 的产能口径增加值
         合计（25 000 000 μQ_s/季）精确不变——在「floor(产能 × 0.9) == 产量」的整数附近搜索
         偏离最小的组合；
       - capital_value_uu：V-CELL-03 精确（floor(资本 × 55 / 1e6) == 产能），取 1 000 μU 整倍数，
         能源部门资本合计精确不变（逐 cell floor 后的全国折旧也就不变）；
       - inventory_input_uqs：制成品投入库存把能源部门原合计按新产能口径季度耗用（ceil）用最大余数法
         重分（覆盖倍数不变、全国合计 12 120 000 不变）；服务投入存量按 R-SERVICES-01 规则
         （基年季度实耗 ceil × 1.5）由新产量重算；电力不入库存、产成品库存恒为 0。
  3. **用工系数逐 cell**：16 个 cell 全部写成 io_table.json 的单格覆盖 "cell.<region>.<sector>"
     （docs/11 §5.5 既有的覆盖语法，载入器 _expand_labor_coeff 与校验器早已支持，无需改代码）。
     每档 c = floor(在岗 × 1e6 / 产量)，若它使 ceil(产量 × c / 1e6) 恰等于在岗就取它，否则取
     ceil(在岗 × 1e6 / 产量)。后者只在整数系数无法精确命中时出现（产量 > 1 Q_s 时一般如此），
     需求比在岗多出 1…ceil(产量/1e6) 人，方向落在「不裁员」一侧。"*" 默认档保留不动。
  4. **开局营运现金**：每个 cell 的 cash_uu ≥ 一季工资（S03 need_k × 工资率）+ 一季中间投入
     （Σ_行 ceil(产量 × io_coeff / 1e6) × 基年价 1 000 μU/μQ_s，含经电网购入的电力），
     向上取整到 1 000 000 μU。先让富余 cell 把富余转给不足的 cell；全国合计仍不够时提高合计
     （企业现金不是锁定值），scenario.json 的 total_cash_uu 同步重新求和（INV-018）。
  5. regions.json 的电网容量不改（跨区输电由 R-GRID-01 在运行期承担）。

幂等：全部目标只由不随本脚本改变的量决定（在岗、工资率、非能源产量、能源产量合计、能源产能/资本
合计、V-GDP 目标、能源投入库存合计），重跑 --apply 不再改变任何数值。
**次序**：tools/refit_base_year.py 会整段重写 cells_init / io_table 的注释（含本脚本写入的现金与
OQ-B 说明）；重跑它之后必须再跑本脚本。

全部整数算术，拆分一律最大余数法，没有浮点参与任何写回的数值（报告里的比值只用于显示）。
用法：  python tools/refit_regional.py --check    只求解、自检并打印前后对照，不写文件
        python tools/refit_regional.py --apply    自检通过后写回
"""
import hashlib
import itertools
import json
import os
import struct
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCEN = os.path.join(ROOT, "content", "scenarios", "chengwan")

PPM = 1_000_000
Q_SCALE = 1_000_000
U_SCALE = 1_000_000_000
BASE_PRICE_UU_PER_UQS = 1_000                  # 1 000 000 000 μU/Q_s ÷ 1e6（R-SCALE-01）
CASH_QUANTUM_UU = 1_000_000                    # 开局现金取 1 000 000 μU 整倍数
CAPITAL_QUANTUM_UU = 1_000                     # 能源资本取 1 000 μU 整倍数（与原值同粒度，折旧逐 cell 无舍入）
UTIL_PPM = 900_000                             # param.base_year_capacity_utilisation_ppm
UTIL_TOL_PPM = 10                              # 重分后能源 cell 利用率允许偏离 900 000 的上限
CAP_SEARCH = 5                                 # 能源产能在基准整数附近的搜索半径（μQ_s）
VGDP_Q_UQS = 25_000_000                        # V-GDP：Σ_cell 产能口径增加值（μQ_s/季）
INV_TARGET_PPM = 500_000                       # param.inventory_target_ppm（R-SERVICES-01 的 1 + 0.5）
WAGE_CASH_SHARE_PPM = 800_000                  # param.wage_cash_share_ppm（仅用于自检）
WAGE_VA_LIMIT_PPM = 900_000                    # 自检：每个 cell 工资 / 增加值 < 0.9

REGIONS = ["beiyuan", "zhongzhou", "haijia", "xiling"]
REGION_ZH = {"beiyuan": "北原", "zhongzhou": "中州", "haijia": "海岬", "xiling": "西岭"}
SECTORS = ["sector.agri", "sector.manu", "sector.energy", "sector.services"]
SECTOR_ZH = {"sector.agri": "农业", "sector.manu": "制造",
             "sector.energy": "能源", "sector.services": "服务"}
SKILLS = ["low", "mid", "high"]
ENERGY = 2
CELL_IDS = ["cell.%s.%s" % (r, s.split(".")[1]) for r in REGIONS for s in SECTORS]
E_IDX = [i for i in range(16) if i % 4 == ENERGY]

# ── R-REGION-01 之前的快照：只用于注释正文与报告里的「原值」，不参与任何求解 ──────────────
PRE_ENERGY = {  # cell 下标 -> (基年产量, 产能, 资本, 现金)
    2: (828_713, 920_793, 16_741_691_000, 306_931_000),
    6: (652_931, 725_479, 13_190_528_000, 241_826_000),
    10: (759_474, 843_861, 15_342_928_000, 281_287_000),
    14: (458_880, 509_867, 9_270_310_000, 169_956_000),
}
PRE_CELL_CASH_TOTAL_UU = 20_000_000_000
PRE_CELL_CASH_BY_SECTOR_UU = [4_000_000_000, 4_500_000_000, 1_000_000_000, 10_500_000_000]
PRE_TOTAL_CASH_UU = 55_000_000_000

OQB_PREFIX = "OQ-B "
OPEN_ISSUE_OLD_PREFIX = "技术口径的用工需求与实际在岗**结构**不一致"
OPEN_ISSUE_NEW_PREFIX = "【已结案 R-REGION-01】"
IFACE_PREFIX = "cells_init.json：16 个 cell 的 capacity_active"
IFACE_CASH_SPLIT = "cell 现金合计"


# ═══════════════════════════════════════════════════════════════════════════
# 整数工具（与 tools/refit_base_year.py 同口径）
# ═══════════════════════════════════════════════════════════════════════════
def ceil_div(a, b):
    return -((-a) // b)


def split_lr(total, weights):
    """最大余数法：Σ result == total 精确成立；平权按下标序破平。"""
    n = len(weights)
    w_sum = sum(weights)
    if w_sum == 0:
        return [0] * n
    base = [(total * w) // w_sum for w in weights]
    rem = [total * weights[i] - base[i] * w_sum for i in range(n)]
    r = total - sum(base)
    order = sorted(range(n), key=lambda i: (-rem[i], i))
    for i in order[:r]:
        base[i] += 1
    assert sum(base) == total
    return base


def num(n):
    """1234567 -> 1 234 567（与现有注释正文同格式）。"""
    s = str(abs(n))
    out = []
    while len(s) > 3:
        out.insert(0, s[-3:])
        s = s[:-3]
    out.insert(0, s)
    return ("-" if n < 0 else "") + " ".join(out)


def u_text(v_uu):
    """μU -> 「x.xxx U」，只用于正文（整数截断到 0.001 U，不参与任何数值）。"""
    whole, frac = divmod(v_uu, U_SCALE)
    return "%d.%03d U" % (whole, frac // 1_000_000)


def load(name):
    with open(os.path.join(SCEN, name), encoding="utf-8") as fh:
        return json.load(fh)


def read_raw(name):
    with open(os.path.join(SCEN, name), encoding="utf-8", newline="") as fh:
        return fh.read()


def dump(name, data):
    with open(os.path.join(SCEN, name), "w", encoding="utf-8", newline="\n") as fh:
        fh.write(json.dumps(data, ensure_ascii=False, indent=2))
        fh.write("\n")


# ═══════════════════════════════════════════════════════════════════════════
# 读入
# ═══════════════════════════════════════════════════════════════════════════
cells_j = load("cells_init.json")
io_j = load("io_table.json")
scen_j = load("scenario.json")
pop_j = load("population_init.json")
gov_j = load("government_init.json")
assert_raw = read_raw("assertions.json")
assert_j = json.loads(assert_raw)

CELLS = cells_j["cells"]
assert [c["cell_id"] for c in CELLS] == CELL_IDS, "cells_init 的 cell 顺序不是地区外层、部门内层"
A = io_j["io_coeff_uqs_per_qs"]
CPC = io_j["capacity_per_capital_uu_ppm"]
DEP = io_j["depreciation_ppm_per_q"]
WAGE = scen_j["prices_init"]["wage_uu_per_person_q"]
assert scen_j["prices_init"]["base_uu_per_qs"] == [BASE_PRICE_UU_PER_UQS * Q_SCALE] * 4


def sec(i):
    return SECTORS[i % 4]


def emp(i):
    return [CELLS[i]["employment_persons"][k] for k in SKILLS]


def va_cap(cap, s):
    """V-GDP 的产能口径增加值（μQ_s/季），逐行 floor——与 tools/validate_content.py 同式。"""
    return cap - sum((cap * A[r][s]) // PPM for r in SECTORS)


def input_uqs(out, s):
    """基年产量下逐行投入（ceil，与 S03/S05 的「不得少算」同向），含能源行。"""
    return {r: ceil_div(out * A[r][s], PPM) for r in SECTORS}


def wage_bill(persons):
    return sum(persons[j] * WAGE[j] for j in range(3))


# ═══════════════════════════════════════════════════════════════════════════
# 求解
# ═══════════════════════════════════════════════════════════════════════════
OUT0 = [c["demand_expect_uqs"] for c in CELLS]
CAP0 = [c["capacity_active_uqs_per_q"] for c in CELLS]
KAP0 = [c["capital_value_uu"] for c in CELLS]
CASH0 = [c["cash_uu"] for c in CELLS]
INV0 = [dict(c["inventory_input_uqs"]) for c in CELLS]
WB = [wage_bill(emp(i)) for i in range(16)]

# ── 2a 能源产量：按地区能源工资总额的份额重分，合计精确保持 ─────────────────────
E_TOTAL = sum(OUT0[i] for i in E_IDX)
OUT = list(OUT0)
for i, v in zip(E_IDX, split_lr(E_TOTAL, [WB[i] for i in E_IDX])):
    OUT[i] = v

# ── 2b 能源产能：利用率 ≈ 900 000，部门合计与 V-GDP 精确不变 ─────────────────────
VA_TARGET_E = VGDP_Q_UQS - sum(va_cap(CAP0[i], sec(i)) for i in range(16) if i not in E_IDX)
CAP_SUM_E = sum(CAP0[i] for i in E_IDX)
CAP_BASE = {i: ceil_div(OUT[i] * PPM, UTIL_PPM) for i in E_IDX}   # floor(产能 × 0.9) == 产量 的最小整数
_cands = []
for d in itertools.product(range(-CAP_SEARCH, CAP_SEARCH + 1), repeat=len(E_IDX)):
    caps = [CAP_BASE[i] + d[j] for j, i in enumerate(E_IDX)]
    if sum(caps) != CAP_SUM_E:
        continue
    if sum(va_cap(c, "sector.energy") for c in caps) != VA_TARGET_E:
        continue
    if any(abs((OUT[i] * PPM) // caps[j] - UTIL_PPM) > UTIL_TOL_PPM for j, i in enumerate(E_IDX)):
        continue
    _cands.append(((sum(abs(x) for x in d), max(abs(x) for x in d), d), caps))
if not _cands:
    sys.stderr.write("能源产能：在 ±%d μQ_s 内找不到同时满足部门合计与 V-GDP 的组合。\n" % CAP_SEARCH)
    sys.exit(2)
_cands.sort()
CAP = list(CAP0)
for j, i in enumerate(E_IDX):
    CAP[i] = _cands[0][1][j]

# ── 2c 能源资本：V-CELL-03 精确、1 000 μU 整倍数、部门合计精确不变 ───────────────
KAP_SUM_E = sum(KAP0[i] for i in E_IDX)
KAP = list(KAP0)
_lo, _hi = {}, {}
for i in E_IDX:
    c = CPC[ENERGY]
    lo = ceil_div(CAP[i] * PPM, c)                 # floor(k × c / 1e6) >= cap 的最小 k
    hi = ceil_div((CAP[i] + 1) * PPM, c) - 1       # floor(k × c / 1e6) <= cap 的最大 k
    _lo[i] = ceil_div(lo, CAPITAL_QUANTUM_UU) * CAPITAL_QUANTUM_UU
    _hi[i] = (hi // CAPITAL_QUANTUM_UU) * CAPITAL_QUANTUM_UU
    assert _lo[i] <= _hi[i]
_rest = KAP_SUM_E - sum(_lo[i] for i in E_IDX)
_slack = [(_hi[i] - _lo[i]) // CAPITAL_QUANTUM_UU for i in E_IDX]
if _rest % CAPITAL_QUANTUM_UU != 0 or _rest < 0 or _rest // CAPITAL_QUANTUM_UU > sum(_slack):
    sys.stderr.write("能源资本：部门合计 %d 落不进各 cell 的 V-CELL-03 可行区间。\n" % KAP_SUM_E)
    sys.exit(2)
for j, (i, add) in enumerate(zip(E_IDX, split_lr(_rest // CAPITAL_QUANTUM_UU, _slack))):
    assert add <= _slack[j]
    KAP[i] = _lo[i] + add * CAPITAL_QUANTUM_UU

# ── 2d 能源投入库存 ─────────────────────────────────────────────────────────────
INV = [dict(x) for x in INV0]
# 可库存投入（农产品、制成品）：能源部门原合计按新产能口径的季度耗用（ceil）最大余数重分，
# 覆盖倍数与原分法（cells_init step_6）一致、全国合计不变。能源列的农产品系数为 0，合计也为 0。
_stock_total_e = {}
for _row in ("sector.agri", "sector.manu"):
    _stock_total_e[_row] = sum(INV0[i].get(_row, 0) for i in E_IDX)
    _w = [ceil_div(CAP[i] * A[_row]["sector.energy"], PPM) for i in E_IDX]
    if sum(_w) == 0:
        assert _stock_total_e[_row] == 0, "能源列系数为 0 却持有 %s 投入库存" % _row
        continue
    for i, v in zip(E_IDX, split_lr(_stock_total_e[_row], _w)):
        INV[i][_row] = v
_manu_total_e = _stock_total_e["sector.manu"]


def services_stock(out, s):
    base = ceil_div(out * A["sector.services"][s], PPM)
    return base + (base * INV_TARGET_PPM) // PPM


for i in E_IDX:
    INV[i]["sector.services"] = services_stock(OUT[i], "sector.energy")

# ── 3 用工系数：逐 cell 由在岗 ÷ 基年产量反推 ─────────────────────────────────
COEFF = []
NEED = []
for i in range(16):
    row_c, row_n = [], []
    for e in emp(i):
        o = OUT[i]
        c_floor = (e * PPM) // o
        if c_floor > 0 and ceil_div(o * c_floor, PPM) == e:
            c = c_floor
        else:
            c = ceil_div(e * PPM, o)
        row_c.append(c)
        row_n.append(ceil_div(o * c, PPM) if c > 0 else 0)
    COEFF.append(row_c)
    NEED.append(row_n)

# ── 4 开局现金 ───────────────────────────────────────────────────────────────
INPUT_UU = [sum(input_uqs(OUT[i], sec(i)).values()) * BASE_PRICE_UU_PER_UQS for i in range(16)]
WAGE_NEED_UU = [wage_bill(NEED[i]) for i in range(16)]
Q_NEED_UU = [WAGE_NEED_UU[i] + INPUT_UU[i] for i in range(16)]
REQ = [ceil_div(Q_NEED_UU[i], CASH_QUANTUM_UU) * CASH_QUANTUM_UU for i in range(16)]
if sum(REQ) >= sum(CASH0):
    # 全国合计不够：富余 cell 的富余全部转给不足的 cell 之后仍不够，于是每个 cell 恰为其一季所需。
    CASH = list(REQ)
    CASH_MODE = "raise"
else:
    # 合计够：不足的 cell 补到所需，全国富余按各 cell 现有富余的份额（1 000 000 μU 为单位）分回。
    _total = ceil_div(sum(CASH0), CASH_QUANTUM_UU) * CASH_QUANTUM_UU
    _pool_units = (_total - sum(REQ)) // CASH_QUANTUM_UU
    _share = split_lr(_pool_units, [max(0, CASH0[i] - REQ[i]) for i in range(16)])
    CASH = [REQ[i] + _share[i] * CASH_QUANTUM_UU for i in range(16)]
    CASH_MODE = "redistribute"

CASH_BY_SECTOR = [sum(CASH[i] for i in range(16) if i % 4 == s) for s in range(4)]
GOV_CASH = gov_j["gov"]["cash_uu"]
INVPOOL_CASH = gov_j["invpool"]["cash_uu"]
ROW_CASH = scen_j["world_init"]["cash_uu"]
GROUP_CASH = sum(g["cash_uu"] for g in pop_j["groups"])
TOTAL_CASH = GOV_CASH + INVPOOL_CASH + ROW_CASH + GROUP_CASH + sum(CASH)


# ═══════════════════════════════════════════════════════════════════════════
# 自检
# ═══════════════════════════════════════════════════════════════════════════
FAILED = []


def chk(name, ok, detail=""):
    if not ok:
        FAILED.append(name + ("：" + detail if detail else ""))


def group_employment():
    out = {}
    for g in pop_j["groups"]:
        _, region, age, skill = g["group_id"].split(".")
        if age != "working":
            continue
        for s in SECTORS:
            out[("cell.%s.%s" % (region, s.split(".")[1]), skill)] = g["employed_persons"][s]
    return out


def selfcheck():
    gemp = group_employment()
    for i in range(16):
        for k in SKILLS:
            chk("在岗 == 群组侧就业 " + CELL_IDS[i] + "/" + k,
                CELLS[i]["employment_persons"][k] == gemp[(CELL_IDS[i], k)])
    chk("能源产量合计精确不变", sum(OUT[i] for i in E_IDX) == E_TOTAL)
    chk("非能源产量不变", all(OUT[i] == OUT0[i] for i in range(16) if i not in E_IDX))
    for i in range(16):
        chk("V-CELL-03 " + CELL_IDS[i], (KAP[i] * CPC[i % 4]) // PPM == CAP[i])
        chk("产量 <= 产能 " + CELL_IDS[i], OUT[i] <= CAP[i])
    chk("V-GDP 产能口径增加值 == 25 000 000 μQ_s/季",
        sum(va_cap(CAP[i], sec(i)) for i in range(16)) == VGDP_Q_UQS)
    chk("能源产能合计不变", sum(CAP[i] for i in E_IDX) == CAP_SUM_E)
    chk("能源资本合计不变", sum(KAP[i] for i in E_IDX) == KAP_SUM_E)
    dep0 = sum((KAP0[i] * DEP[i % 4]) // PPM for i in range(16))
    dep1 = sum((KAP[i] * DEP[i % 4]) // PPM for i in range(16))
    chk("全国季度折旧不变", dep0 == dep1, "%d -> %d" % (dep0, dep1))
    for i in E_IDX:
        u = (OUT[i] * PPM) // CAP[i]
        chk("能源利用率 ≈ 900 000 " + CELL_IDS[i], abs(u - UTIL_PPM) <= UTIL_TOL_PPM, str(u))
    for s in ("sector.agri", "sector.manu"):
        chk("全国投入库存合计不变 " + s,
            sum(x.get(s, 0) for x in INV) == sum(x.get(s, 0) for x in INV0))
    for i in range(16):
        chk("服务投入存量 = 实耗 × 1.5 " + CELL_IDS[i],
            INV[i].get("sector.services") == services_stock(OUT[i], sec(i)))
        chk("电力不入库存 " + CELL_IDS[i], "sector.energy" not in INV[i])
        if i % 4 in (ENERGY, 3):
            chk("不可库存部门产成品库存为 0 " + CELL_IDS[i], CELLS[i]["inventory_output_uqs"] == 0)
    for i in range(16):
        for j, k in enumerate(SKILLS):
            e, n = emp(i)[j], NEED[i][j]
            chk("基年需求 >= 在岗 " + CELL_IDS[i] + "/" + k, n >= e, "%d < %d" % (n, e))
            chk("取整余量 <= ceil(产量/1e6) " + CELL_IDS[i] + "/" + k,
                n - e <= ceil_div(OUT[i], Q_SCALE), str(n - e))
            chk("系数 >= 1 " + CELL_IDS[i] + "/" + k, COEFF[i][j] >= 1)
            # 招满 need 之后，劳动约束 floor(need × 1e6 / c) 不低于基年产量（docs/12 §5.3）
            chk("劳动约束 >= 基年产量 " + CELL_IDS[i] + "/" + k,
                (n * PPM) // COEFF[i][j] >= OUT[i])
    for i in range(16):
        va_uu = OUT[i] * BASE_PRICE_UU_PER_UQS - INPUT_UU[i]
        chk("工资 / 增加值 < 0.9 " + CELL_IDS[i], WB[i] * PPM < WAGE_VA_LIMIT_PPM * va_uu,
            "%d / %d" % (WB[i], va_uu))
        chk("现金 >= 一季工资 + 投入 " + CELL_IDS[i], CASH[i] >= Q_NEED_UU[i])
        chk("现金为 1 000 000 μU 整倍数 " + CELL_IDS[i], CASH[i] % CASH_QUANTUM_UU == 0)
        chk("80% 现金够付 need 工资 " + CELL_IDS[i],
            (CASH[i] * WAGE_CASH_SHARE_PPM) // PPM >= WAGE_NEED_UU[i])
    chk("INV-018 total_cash_uu 重新求和", TOTAL_CASH == GOV_CASH + INVPOOL_CASH + ROW_CASH
        + GROUP_CASH + sum(CASH))


# ═══════════════════════════════════════════════════════════════════════════
# 报告
# ═══════════════════════════════════════════════════════════════════════════
def io_card_value(labor_rows):
    """param.io_table_set 的 value（params_core.json 该卡 calibration_note 的口径，逐字复现）。"""
    io_arr = [A[SECTORS[f]][SECTORS[t]] for f in range(4) for t in range(4)]
    lab = [labor_rows[i][j] for i in range(16) for j in range(3)]
    en = io_j["energy_coeff_uqs_per_qs"]
    arrs = {
        "content.io.io_coeff_uqs_per_qs": io_arr,
        "content.io.labor_coeff_persons_per_qs": lab,
        "content.io.energy_coeff_uqs_per_qs": [en[i % 4] for i in range(16)],
        "content.io.spoilage_ppm": io_j["spoilage_ppm"],
        "content.io.depreciation_ppm_per_q": io_j["depreciation_ppm_per_q"],
        "content.io.capacity_per_capital_uu_ppm": io_j["capacity_per_capital_uu_ppm"],
        "content.io.emission_ppm": io_j["emission_ppm"],
        "content.storable": io_j["storable"],
    }
    buf = b""
    for k in sorted(arrs, key=lambda x: x.encode("utf-8")):
        kb = k.encode("utf-8")
        a = arrs[k]
        buf += struct.pack("<H", len(kb)) + kb + struct.pack("<B", 2) + struct.pack("<I", len(a))
        buf += b"".join(struct.pack("<q", v) for v in a)
    digest = hashlib.sha256(buf).hexdigest()
    return int(str(int(digest, 16)).rjust(78, "0")[:16]), digest


def expanded_labor_current():
    lab = io_j["labor_coeff_persons_per_qs"]
    rows = []
    for i in range(16):
        row = lab.get(CELL_IDS[i]) or lab["*"][sec(i)]
        rows.append([row[k] for k in SKILLS])
    return rows


def report():
    w = sys.stdout.write
    w("R-REGION-01 重拟合（%s）\n\n" % ("--apply" if "--apply" in sys.argv else "--check"))
    w("能源：全国基年产量 %s μQ_s/季（精确保持），按地区能源工资总额分摊\n" % num(E_TOTAL))
    w("%-22s %10s %10s %9s %10s %10s %8s %16s %16s %9s %9s %14s %14s\n" % (
        "cell", "工资/季", "产量旧", "产量新", "产能旧", "产能新", "利用率", "资本旧", "资本新",
        "制成品库存", "服务库存", "现金旧", "现金新"))
    for i in E_IDX:
        w("%-22s %10s %10s %9s %10s %10s %8d %16s %16s %9s %9s %14s %14s\n" % (
            CELL_IDS[i], num(WB[i]), num(PRE_ENERGY[i][0]), num(OUT[i]), num(PRE_ENERGY[i][1]),
            num(CAP[i]), (OUT[i] * PPM) // CAP[i], num(PRE_ENERGY[i][2]), num(KAP[i]),
            num(INV[i]["sector.manu"]), num(INV[i]["sector.services"]), num(PRE_ENERGY[i][3]),
            num(CASH[i])))
    w("  产能合计 %s、资本合计 %s μU、V-GDP 产能口径增加值 %s μQ_s/季、全国季度折旧 %s μU\n\n" % (
        num(sum(CAP[i] for i in E_IDX)), num(sum(KAP[i] for i in E_IDX)),
        num(sum(va_cap(CAP[i], sec(i)) for i in range(16))),
        num(sum((KAP[i] * DEP[i % 4]) // PPM for i in range(16)))))

    w("逐 cell（系数 = io_table 单格覆盖；need = ceil(产量 × 系数 / 1e6)；比值 ppm）\n")
    w("%-4s %-22s %9s %-26s %-24s %-9s %8s %8s %13s %13s %8s\n" % (
        "#", "cell", "产量", "在岗 l/m/h", "系数 l/m/h", "need-在岗", "工资/VA", "旧工资/VA",
        "现金", "一季所需", "现金/所需"))
    old_rows = expanded_labor_current()
    for i in range(16):
        va_uu = OUT[i] * BASE_PRICE_UU_PER_UQS - INPUT_UU[i]
        va0 = OUT0[i] * BASE_PRICE_UU_PER_UQS - sum(input_uqs(OUT0[i], sec(i)).values()) * BASE_PRICE_UU_PER_UQS
        e = emp(i)
        w("%-4d %-22s %9s %-26s %-24s %-9s %8d %8d %13s %13s %8d\n" % (
            i, CELL_IDS[i], num(OUT[i]), "/".join(str(x) for x in e),
            "/".join(str(x) for x in COEFF[i]),
            "/".join(str(NEED[i][j] - e[j]) for j in range(3)),
            (WB[i] * PPM) // va_uu, (WB[i] * PPM) // va0, num(CASH[i]), num(Q_NEED_UU[i]),
            (CASH[i] * PPM) // Q_NEED_UU[i]))
    ex = [NEED[i][j] - emp(i)[j] for i in range(16) for j in range(3)]
    w("  取整余量：48 档中 %d 档精确相等，合计多 %d 人，单档最多 %d 人\n" % (
        sum(1 for x in ex if x == 0), sum(ex), max(ex)))
    old_need_gap = sum(ceil_div(OUT0[i] * old_rows[i][j], PPM) - emp(i)[j]
                       for i in range(16) for j in range(3))
    w("  （重拟合前按现行系数与原产量：Σ(need − 在岗) = %s 人）\n\n" % num(old_need_gap))

    w("现金（%s）：16 个 cell 合计 %s → %s μU；一季所需合计 %s μU\n" % (
        "全国不够，每个 cell 取恰好一季所需" if CASH_MODE == "raise" else "全国够，重分富余",
        num(sum(CASH0)), num(sum(CASH)), num(sum(Q_NEED_UU))))
    w("  按部门：%s\n" % "、".join("%s %s" % (SECTOR_ZH[SECTORS[s]], num(CASH_BY_SECTOR[s]))
                                  for s in range(4)))
    w("  scenario.total_cash_uu：%s → %s μU（gov %s + invpool %s + row %s + 群组 %s + cell %s）\n\n" % (
        num(scen_j["total_cash_uu"]), num(TOTAL_CASH), num(GOV_CASH), num(INVPOOL_CASH),
        num(ROW_CASH), num(GROUP_CASH), num(sum(CASH))))

    # 基年电力：各区本地发电可交付量 vs 本区生产用电（生命线另计，运行期由 R-GRID-01 输电平衡）
    a_ee = A["sector.energy"]["sector.energy"]
    w("基年电力（μQ/季，生产用电不含居民与公共服务生命线）：\n")
    for r, region in enumerate(REGIONS):
        e_cell = r * 4 + ENERGY
        gen = OUT[e_cell] - ceil_div(OUT[e_cell] * a_ee, PPM)
        use = sum(ceil_div(OUT[r * 4 + s] * A["sector.energy"][SECTORS[s]], PPM)
                  for s in range(4) if s != ENERGY)
        w("  %s 可交付 %s（原 %s），本区生产用电 %s\n" % (
            REGION_ZH[region], num(gen),
            num(PRE_ENERGY[e_cell][0] - ceil_div(PRE_ENERGY[e_cell][0] * a_ee, PPM)), num(use)))

    card_now, _ = io_card_value(old_rows)
    card_new, dig = io_card_value(COEFF)
    w("\nparam.io_table_set（params_core.json，本脚本不写）：按现行 io_table 算 %016d，"
      "重拟合后应为 %016d（sha256 %s）\n" % (card_now, card_new, dig))

    changed = []
    for i in range(16):
        c = CELLS[i]
        for key, new in (("demand_expect_uqs", OUT[i]), ("capacity_active_uqs_per_q", CAP[i]),
                         ("capital_value_uu", KAP[i]), ("cash_uu", CASH[i]),
                         ("inventory_input_uqs", INV[i])):
            if c[key] != new:
                changed.append(c["cell_id"] + "/" + key)
    lab = io_j["labor_coeff_persons_per_qs"]
    for i in range(16):
        cur = lab.get(CELL_IDS[i])
        if cur is None or [cur[k] for k in SKILLS] != COEFF[i]:
            changed.append("io_table labor " + CELL_IDS[i])
    if scen_j["total_cash_uu"] != TOTAL_CASH:
        changed.append("scenario total_cash_uu")
    w("待写数值字段：%d 个%s\n" % (len(changed), "（已是目标状态，幂等）" if not changed else ""))


# ═══════════════════════════════════════════════════════════════════════════
# 注释正文
# ═══════════════════════════════════════════════════════════════════════════
def need_summary():
    ex = [NEED[i][j] - emp(i)[j] for i in range(16) for j in range(3)]
    return sum(1 for x in ex if x == 0), sum(ex), max(ex)


def cell_note(i):
    cid = CELL_IDS[i]
    _, region, _ = cid.split(".")
    s = sec(i)
    cap, kap, out = CAP[i], KAP[i], OUT[i]
    e = emp(i)
    diff = [NEED[i][j] - e[j] for j in range(3)]
    if any(diff):
        diff_txt = "比在岗多 %s 人，是整数系数的取整余量，方向落在不裁员一侧" % "/".join(str(x) for x in diff)
    else:
        diff_txt = "逐档与在岗人数精确相等"
    va_uu = out * BASE_PRICE_UU_PER_UQS - INPUT_UU[i]
    inv_txt = ""
    for row in ("sector.agri", "sector.manu"):
        need = ceil_div(cap * A[row][s], PPM)
        if need > 0 and INV[i].get(row, 0) > 0:
            inv_txt += "%s %s ppm、" % (row, num((INV[i][row] * PPM) // need))
    inv_txt = ("投入库存覆盖产能口径季度耗用：" + inv_txt.rstrip("、") + "；") if inv_txt else ""
    inv_txt += "服务投入存量 %s μQ = 基年季度实耗 × 1.5（R-SERVICES-01）。" % num(INV[i]["sector.services"])
    store = "" if io_j["storable"][i % 4] else " storable == 0，产成品库存恒为 0（INV-049）。"
    extra = ""
    if i in E_IDX:
        o0, c0, k0, m0 = PRE_ENERGY[i]
        extra = ("R-REGION-01：全国能源基年产量按各地区能源工资总额的份额重分，本 cell 季度工资 %s μU，"
                 "分得 %s μQ_s（原 %s；原产能 %s、资本 %s μU、现金 %s μU），产能、资本、投入库存随之重算，"
                 "能源部门的产能、资本与全国折旧合计不变。" % (
                     num(WB[i]), num(out), num(o0), num(c0), num(k0), num(m0)))
    return (
        "%s·%s。产能 %s μQ_s/季 = floor(资本 %s μU × capacity_per_capital_uu_ppm %d / 1e6)"
        "（该系数是 ppm 定标的「μQ_s 每 μU 资本」，V-CELL-03 精确相等，差 0）。"
        "基年季度产量 %s μQ_s（= demand_expect_uqs，产能利用率 %s ppm）。%s"
        "群组侧在岗 low/mid/high = %s/%s/%s 人，是本 cell 的锚（R-REGION-01，不随系数改）；"
        "用工系数取 io_table.json labor_coeff_persons_per_qs 的单格覆盖 %s = %s/%s/%s 人/Q_s"
        "（在岗 × 1e6 ÷ 基年产量的整数取法），基年产量下 S03 用工需求 ceil(产量 × 系数 / 1e6) = %s/%s/%s 人，"
        "%s；开局不裁员，劳动约束不低于基年产量。季度工资总额 %s μU，占产量口径增加值 %s μU 的 %s ppm。"
        "开局现金 %s μU ≥ 一季工资 %s + 基年价中间投入（含电力）%s = %s μU（R-REGION-01，"
        "向上取整到 1 000 000 μU）。%s%s"
        % (REGION_ZH[region], SECTOR_ZH[s], num(cap), num(kap), CPC[i % 4],
           num(out), num((out * PPM) // cap), extra,
           num(e[0]), num(e[1]), num(e[2]),
           cid, num(COEFF[i][0]), num(COEFF[i][1]), num(COEFF[i][2]),
           num(NEED[i][0]), num(NEED[i][1]), num(NEED[i][2]), diff_txt,
           num(WB[i]), num(va_uu), num((WB[i] * PPM) // va_uu),
           num(CASH[i]), num(WAGE_NEED_UU[i]), num(INPUT_UU[i]), num(Q_NEED_UU[i]),
           inv_txt, store))


def oqb_text():
    n_exact, n_sum, n_max = need_summary()
    return (
        "OQ-B 【已结案，R-REGION-01】原问题：io_table 全国统一的用工系数 × 各 cell 基年产量，与 population_init "
        "的逐 cell 在岗人数**结构**不一致——西岭能源在岗是系数所需的 5.8–19.7 倍、工资总额 0.42 U/季 > 增加值 "
        "0.29 U/季、开局现金 0.17 U；开局 S03 即按系数裁员（失业率由锁定的 8%% 跳到 12%% 以上），西岭能源付不起工资、"
        "第 6 季停产并拖垮全区。裁定：在岗人数是锚（本文件与 population_init 的就业一个数都没改）；"
        "能源的全国基年产量按各地区能源工资总额重分到地区（_note_derivation_zh.step_4_energy_split）；"
        "16 个 cell 的用工系数全部改为 io_table.json 的单格覆盖 cell.<region>.<sector>，取「在岗 × 1e6 ÷ 基年产量」"
        "的整数（见该文件 _note_labor_coeff_persons_per_qs），基年产量下 S03 的用工需求 48 档中 %d 档与在岗精确相等，"
        "其余只多出整数系数的取整余量（合计 %d 人，单档最多 %d 人）；每个 cell 开局现金不少于一季工资 + 中间投入"
        "（step_7_cash）。重拟合工具 tools/refit_regional.py（幂等，--check 只自检）。"
        % (n_exact, n_sum, n_max))


def energy_split_text():
    parts = "、".join("%s %s" % (REGION_ZH[REGIONS[i // 4]], num(OUT[i])) for i in E_IDX)
    olds = " / ".join(num(PRE_ENERGY[i][0]) for i in E_IDX)
    wbs = "、".join("%s %s" % (REGION_ZH[REGIONS[i // 4]], num(WB[i])) for i in E_IDX)
    return (
        "R-REGION-01（取代原「各区发电自给」的分法）：能源的全国基年季度产量 %s μQ_s（= 四个能源 cell 原 "
        "demand_expect_uqs 之和，精确保持）按各地区能源 cell 的基年季度工资总额 Σ_k 在岗_k × wage_uu_per_person_q[k]"
        "（%s μU）的份额用最大余数法分到地区（平权按 cell 下标破平）：%s μQ_s/季（原 %s）。"
        "在岗人数是锚：西岭是剧本设定的能源与资源供给区、产业单一，能源在岗 %s 人；原分法让它的产量只够本区用电，"
        "工资总额超过增加值。原分法要求每区发电覆盖本区用电，是因为当时没有跨区输电；R-GRID-01 起各区本地发电先供本区，"
        "余量经全国输电池补给他区缺口，电网容量只约束交付给本区用户的电量、不约束发电与外送，西岭的富余电力因此可以送出。"
        "regions.json 的电网容量未改；基年各区的电力平衡与电网是否偏紧由运行期实测（tools/diag_baseline.gd）。"
        "产能、资本与投入库存按 step_2 / step_5 / step_6 同步重算。"
        % (num(E_TOTAL), wbs, parts, olds, num(sum(emp(CELL_IDS.index("cell.xiling.energy"))))))


def patch_cells():
    d = cells_j
    for i, c in enumerate(d["cells"]):
        c["cash_uu"] = CASH[i]
        c["capacity_active_uqs_per_q"] = CAP[i]
        c["capital_value_uu"] = KAP[i]
        c["inventory_input_uqs"] = INV[i]
        c["demand_expect_uqs"] = OUT[i]
        c["_note_zh"] = cell_note(i)
    d["_note_authority_zh"] = (
        "本文件是基年生产侧的权威初值。上游只有三处是事实来源：(1) io_table.json 的技术系数、用工系数"
        "（R-REGION-01 起 16 个 cell 全部为单格覆盖，由本文件的在岗人数与基年产量反推）、产能折算率与 "
        "_note_base_year_accounting 附录给出的基年部门总产出与增加值；(2) population_init.json 的 36 组就业分配"
        "（V-POP-08 逐项交叉校验，本文件的 employment_persons 逐字抄自它的汇总，不得另写一套；R-REGION-01 以它为锚）；"
        "(3) scenario.json 的 total_cash_uu 拆分（16 个 cell 现金合计 %s μU，R-REGION-01 起每个 cell 不少于"
        "一季工资 + 中间投入）。本文件不引入任何未经登记的新口径，也不做「平衡修正项」（计划书 §13）。"
        "数值依次由 tools/refit_base_year.py 与 tools/refit_regional.py 写出；前者会整段重写本文件的注释，"
        "重跑它之后必须再跑后者。" % num(sum(CASH)))
    der = d["_note_derivation_zh"]
    utils = "、".join("%s %s" % (REGION_ZH[REGIONS[i // 4]], num((OUT[i] * PPM) // CAP[i])) for i in E_IDX)
    der["step_2_capacity"] = (
        "产能 = 产量 ÷ 基年产能利用率 900 000 ppm。io_table 附录取的是 867 598—926 243 ppm 的"
        "逐部门利用率，本文件统一取 900 000 ppm：这是唯一能让「产能口径的增加值」与"
        "「产量口径的 GDP 目标」同时等于 25 000 000 000 μU/季的取值，其余取值必有一侧对不上"
        "（见 open_questions 第 1 条）。部门产能合计：农业 6 972 222、制造 16 777 777、"
        "能源 3 000 000、服务 17 583 292 μQ_s/季。R-REGION-01 重分能源产量后，四个能源 cell 的产能取"
        "「floor(产能 × 0.9) == 产量」的整数附近偏离最小、且使能源产能合计仍为 3 000 000、V-GDP 的产能口径"
        "增加值合计仍精确为 25 000 000 μQ_s/季的组合，逐 cell 利用率为 %s ppm（偏离 900 000 至多 %d ppm）。"
        % (utils, max(abs((OUT[i] * PPM) // CAP[i] - UTIL_PPM) for i in E_IDX)))
    der["step_4_energy_split"] = energy_split_text()
    der["step_5_capital"] = (
        "资本 = 使 floor(capital_value_uu × capacity_per_capital_uu_ppm / 1 000 000) "
        "精确等于本 cell 产能的最小整数（V-CELL-03 的容差是 ±1 μQ_s，本文件 16 个 cell 的实际误差全部为 0）。"
        "capacity_per_capital_uu_ppm 已按 R-SCALE-01 修正为 [200, 180, 55, 160]（μQ_s 每 μU 资本）。"
        "部门资本合计：农业 34 861 110 000、制造 93 209 874 000、能源 %s、"
        "服务 109 895 576 000 μU，合计 292 512 017 000 μU。"
        "io_table 附录的 299 000 000 000 μU 对应它自己的产能口径，"
        "两者之差 6 487 983 000 μU 就是统一利用率带来的差额。R-REGION-01：四个能源 cell 的资本改为在 V-CELL-03 "
        "可行区间内取 1 000 μU 整倍数，并使能源部门资本合计精确不变（逐 cell floor 后的全国季度折旧 %s μU 也不变）。"
        % (num(sum(KAP[i] for i in E_IDX)), num(sum((KAP[i] * DEP[i % 4]) // PPM for i in range(16)))))
    s6 = der["step_6_inventory"].rstrip()
    tag = "R-REGION-01（能源 cell）："
    for t in (tag, "R-REGION-01："):          # 后者是本脚本早先写入的标记，重跑时一并替换
        if t in s6:
            s6 = s6[:s6.index(t)].rstrip()
    der["step_6_inventory"] = s6 + (
        "%s制成品投入库存把能源部门原合计 %s μQ 按新产能的季度耗用（ceil）用最大余数法重分，"
        "全国合计 12 120 000 不变、覆盖倍数与其余 cell 一致；服务投入存量按 R-SERVICES-01 的规则"
        "（基年季度实耗 × 1.5，见 _note_services_input_stock）由新产量重算。" % (tag, num(_manu_total_e)))
    der["step_7_cash"] = (
        "R-REGION-01：每个 cell 的开局现金不少于「一季基年工资 + 一季基年中间投入」。工资 = Σ_k "
        "ceil(基年产量 × 用工系数 / 1e6) × wage_uu_per_person_q[k]（S03 的 need_k 口径，不低于在岗口径）；"
        "中间投入 = Σ_行 ceil(基年产量 × io_coeff[行][本部门] / 1e6) × 基年价 1 000 μU/μQ_s（含经电网购入的电力）；"
        "向上取整到 1 000 000 μU。原 16 个 cell 合计 20 000 000 000 μU（按 io_table 附录 operating_cash_uu "
        "分部门：农业 4 000 000 000、制造 4 500 000 000、能源 1 000 000 000、服务 10 500 000 000，部门内按产能份额分摊）"
        "只有全国一季所需 %s μU 的 %s ppm；把富余 cell 的富余全部转给不足的 cell 之后仍不够，故提高合计：每个 cell "
        "恰为其一季所需，新合计 %s μU（农业 %s、制造 %s、能源 %s、服务 %s）。企业现金不是锁定值（锁定的是国库现金 2 U、"
        "债务 50 U、年收入 20 U / 支出 22 U、GDP 100 U、失业率 8%%）；scenario.json 的 total_cash_uu 已同步重新求和"
        "（INV-018），io_table 附录的逐部门 operating_cash_uu 同步更新。"
        % (num(sum(Q_NEED_UU)), num((PRE_CELL_CASH_TOTAL_UU * PPM) // sum(Q_NEED_UU)), num(sum(CASH)),
           num(CASH_BY_SECTOR[0]), num(CASH_BY_SECTOR[1]), num(CASH_BY_SECTOR[2]), num(CASH_BY_SECTOR[3])))
    idn = d["_note_identities_zh"]
    idn["cash_total"] = "Σ 16 cell 的 cash_uu = %s μU（INV-018；R-REGION-01 之前为 20 000 000 000）。" % num(sum(CASH))
    n_exact, n_sum, n_max = need_summary()
    idn["labor_need_at_base_output"] = (
        "R-REGION-01：每个 cell 每档技能在基年产量下的 S03 用工需求 ceil(demand_expect_uqs × labor_coeff / 1e6) "
        "≥ 在岗人数，且只在整数系数无法精确命中时多出 1…ceil(产量 / 1e6) 人：48 档中 %d 档精确相等，合计多 %d 人，"
        "单档最多 %d 人。招满之后 floor(需求 × 1e6 / 系数) ≥ 基年产量，劳动约束在基年不紧。" % (n_exact, n_sum, n_max))
    st = d["_note_sector_totals"]
    st["cash_uu"] = {SECTORS[s]: CASH_BY_SECTOR[s] for s in range(4)}
    st["capacity_active_uqs_per_q"]["sector.energy"] = sum(CAP[i] for i in E_IDX)
    st["capital_value_uu"]["sector.energy"] = sum(KAP[i] for i in E_IDX)
    oq = d["_note_open_questions_zh"]
    idx = [k for k, t in enumerate(oq) if t.startswith(OQB_PREFIX)]
    assert len(idx) == 1, "cells_init 的 _note_open_questions_zh 里找不到唯一的 OQ-B 条目"
    oq[idx[0]] = oqb_text()
    dump("cells_init.json", d)


def patch_io_table():
    d = io_j
    lab = d["labor_coeff_persons_per_qs"]
    new_lab = {"*": lab["*"]}
    for k, v in lab.items():
        if k.startswith("_"):
            new_lab[k] = v
    for i in range(16):
        new_lab[CELL_IDS[i]] = {SKILLS[j]: COEFF[i][j] for j in range(3)}
    d["labor_coeff_persons_per_qs"] = new_lab
    n_exact, n_sum, n_max = need_summary()
    d["_note_labor_coeff_persons_per_qs"] = (
        "R-REGION-01（OQ-B 结案）起，16 个 cell 全部用单格覆盖 \"cell.<region>.<sector>\"——这是 docs/11 §5.5 "
        "既有的覆盖语法，载入器（systems/content_loader.gd 的 _expand_labor_coeff）与校验器（V-IO-06）早已支持，"
        "加载期展开成定长数组，无需改代码。每格每档的系数由剧本的在岗人数（population_init / cells_init 的 "
        "employment_persons，锚）与基年季度产量（cells_init 的 demand_expect_uqs）反推：c = floor(在岗 × 1e6 ÷ 产量)，"
        "若它在基年产量下使 S03 的 ceil(产量 × c / 1e6) 恰等于在岗人数就取它（不超过真实比值的最大整数），"
        "否则取 ceil(在岗 × 1e6 ÷ 产量)——后者只在整数系数无法精确命中时出现（产量大于 1 Q_s 时区间长度不足 1），"
        "需求比在岗多出 1…ceil(产量 / 1e6) 人，方向落在「不裁员」一侧。本版 48 档中 %d 档精确相等，合计多 %d 人、"
        "单档最多 %d 人。系数因此随地区不同：同一部门的地区差异来自剧本的在岗结构（例如西岭能源是劳动密集的资源型产能），"
        "而不再是「全国统一技术 × 各区产量」——原取法与 population_init 的就业结构无法同时成立（见 cells_init 的 OQ-B）。"
        "\"*\" 默认档保留为按部门的全国参考值（农业低技能 270 708 见 _note_labor_coeff_agri_low_calibration），"
        "本剧本 16 格全部被覆盖、运行期不再读它，只在新增 cell 或另建剧本时作回退值。改在岗人数或基年产量必须重跑 "
        "tools/refit_regional.py；改系数会让 params_core.json 的 param.io_table_set 过期（V-PC-07）。"
        % (n_exact, n_sum, n_max))
    agri_low = "、".join("%s %s" % (REGION_ZH[REGIONS[i // 4]], num(COEFF[i][0])) for i in range(0, 16, 4))
    cal = d["_note_labor_coeff_agri_low_calibration"]
    tag = "（R-REGION-01 之后："
    if tag in cal:
        cal = cal[:cal.index(tag)]
    d["_note_labor_coeff_agri_low_calibration"] = cal + (
        "%s该值只留在 \"*\" 默认档作全国参考；16 个 cell 的实际系数由单格覆盖按「在岗 ÷ 基年产量」逐格给出，"
        "四个农业 cell 的低技能系数为 %s 人/Q_s。）" % (tag, agri_low))

    acc = d["_note_base_year_accounting"]
    for sa in acc["sector_accounts"]:
        sa["operating_cash_uu"] = CASH_BY_SECTOR[SECTORS.index(sa["sector_id"])]
    lab_blk = acc["labor"]
    req = {}
    for s in SECTORS:
        row = {}
        for j, k in enumerate(SKILLS):
            row[k] = sum(NEED[i][j] for i in range(16) if sec(i) == s)
        row["total"] = row["low"] + row["mid"] + row["high"]
        req[s] = row
    lab_blk["labor_requirement_at_base_output_persons"] = req
    lab_blk["_note"] = (
        "本块区分两件过去被混在一起的事：**在岗人数**（谁真的在工作，权威在 population_init.json，逐 (地区, 部门, 技能) "
        "由 V-POP-08 与 cells_init / pubserv_init 交叉校验）与**技术口径的用工需求**（按基年产量与用工系数算出来的 "
        "ceil(产量 × 用工系数 / 1e6)）。R-REGION-01 之后用工系数逐 cell 由在岗人数与基年产量反推，"
        "labor_requirement_at_base_output_persons 是 16 个 cell 按各自单格系数的需求逐格求和：与在岗人数逐 (部门, 技能) "
        "相等或只多出整数系数的取整余量（全国合计多 %d 人），基年不再有 bound_labor 缺口，开局也不再按系数裁员。"
        "失业率必须由 population_init 反算（V-POP-05、INV-143），本附录只复述它必须落在哪里。" % n_sum)
    issues = acc["open_issues"]
    idx = [k for k, t in enumerate(issues)
           if t.startswith(OPEN_ISSUE_OLD_PREFIX) or t.startswith(OPEN_ISSUE_NEW_PREFIX)]
    assert len(idx) == 1, "io_table 附录 open_issues 里找不到唯一的用工结构条目"
    issues[idx[0]] = (
        "%s技术口径的用工需求与实际在岗结构不一致（原：全国统一系数 × 各 cell 产量，农业低技能短缺、"
        "能源富余几十万人且堆在西岭，开局按系数裁员）。按裁定 R-REGION-01，在岗人数为锚：能源全国产量按地区能源工资总额"
        "重分到地区，16 个 cell 的用工系数改为「在岗 ÷ 基年产量」的单格覆盖，labor_requirement_at_base_output_persons "
        "已与在岗人数对齐（取整余量合计 %d 人）。见 cells_init.json 的 OQ-B 与 tools/refit_regional.py。"
        % (OPEN_ISSUE_NEW_PREFIX, n_sum))
    ifx = [k for k, t in enumerate(acc["interface_requirements"]) if t.startswith(IFACE_PREFIX)]
    assert len(ifx) == 1, "io_table 附录 interface_requirements 里找不到 cells_init 条目"
    t = acc["interface_requirements"][ifx[0]]
    acc["interface_requirements"][ifx[0]] = t[:t.index(IFACE_CASH_SPLIT)] + (
        "%s %s μU 计入 scenario.total_cash_uu（INV-018；R-REGION-01 起每个 cell 不少于一季工资 + 中间投入，"
        "sector_accounts 的 operating_cash_uu 是它的逐部门合计）。" % (IFACE_CASH_SPLIT, num(sum(CASH))))
    dump("io_table.json", d)


def cash_breakdown_text(sep):
    return sep.join([num(GOV_CASH), num(INVPOOL_CASH), num(ROW_CASH), num(GROUP_CASH), num(sum(CASH))])


def patch_scenario():
    d = scen_j
    d["total_cash_uu"] = TOTAL_CASH
    by_sector = "、".join("%s %s" % (SECTOR_ZH[SECTORS[s]], num(CASH_BY_SECTOR[s])) for s in range(4))
    d["_note_total_cash_uu"] = (
        "%s。全经济现金总量恒定（INV-018）。本字段不是可自由选取的参数，而是全部现金科目初值的求和结果，"
        "source_type = derived，单位 μU：agent.gov %s（government_init.json /gov/cash_uu，计划书 §05 锁定的国库现金 2 U）"
        "加 agent.invpool %s（government_init.json /invpool/cash_uu，OQ-201 取值）加 agent.row %s"
        "（本文件 /world_init/cash_uu，OQ-201 取值）加 36 个 agent.group 合计 %s（population_init.json /groups[*]/cash_uu "
        "实测求和）加 16 个 agent.cell 合计 %s（cells_init.json /cells[*]/cash_uu 实测求和；按部门为%s，"
        "与 io_table.json 基年核算的逐部门 operating_cash_uu 相等；R-REGION-01 之前为 20 000 000 000）加 agent.opening 0"
        "（OQ-217：开账分录的现金腿不经 agent.opening，其现金科目恒为 0），合计 %s μU。"
        "上一版的六项数字是旧刻度值，已按 R-SCALE-01 全部重算（更早的一版曾把本字段写成 80 000 000 000、"
        "群组记为 30 000 000 000、cell 记为 24 000 000 000，与实测各差 21 U 与 4 U，即凭空多出 25 U 现金；"
        "现金总量若不是一个可对账的常数，「没有无来源资金」这条底座——计划书 §15 G1 门槛、§16 人工评审要点——"
        "就没有检验手段）。**状态变化**：cells_init.json 落地后本条对账由「无法核对」转为通过，校验器现在真的在"
        "逐文件求和后与本字段比对；R-REGION-01 提高 cell 开局现金后本字段由 55 000 000 000 重新求和为当前值。"
        % (u_text(TOTAL_CASH), num(GOV_CASH), num(INVPOOL_CASH), num(ROW_CASH), num(GROUP_CASH),
           num(sum(CASH)), by_sector, num(TOTAL_CASH)))
    mkt_wage = sum(WB)
    d["_note_total_cash_uu_headroom"] = (
        "对账已通过，充足性是另一件事——不要混为一谈。%s 约为基年全年名义 GDP 100 U 的 %s ppm。"
        "原 cell 侧 20 U（约为市场部门一季工资单的 1.77 倍）在 G1 无命令基线里被证明不够：全国一季工资 + 中间投入需 "
        "%s μU，西岭能源开局现金 0.17 U 而季度工资 0.42 U，付不起工资而停产（docs/18 R-REGION-01）。"
        "按 R-REGION-01，每个 cell 的开局现金不少于一季工资 + 中间投入（cells_init.json 的 step_7_cash）："
        "先把富余 cell 的富余转给不足的 cell，仍不够才提高合计，cell 侧现在是 %s μU，约为市场部门一季工资单 %s μU "
        "的 %s ppm。这是开局的**下限**，不保证此后各季的现金流为正；运行期是否出现虚假欠付仍只能由 G1 的无命令基线"
        "检验（tools/diag_baseline.gd、tools/diag_cashflow.gd）。这也不是为消除欠付而直接调高本值（那等于凭空造钱，"
        "属于计划书 §13 禁止的后处理补丁）：改的是 cells_init.json 的初值分配规则，本字段只是重新求和。"
        "注意 cell 侧的逐部门拆分同时写在 io_table.json 的 _note_base_year_accounting（注释键，载入器不读、"
        "不进 content_hash），那份副本由 tools/refit_regional.py 同步写出，但不被任何校验器自动传导，"
        "只能靠 cells_init.json 与本字段这一对被机器核对。"
        % (u_text(TOTAL_CASH), num((TOTAL_CASH * PPM) // 100_000_000_000), num(sum(Q_NEED_UU)),
           num(sum(CASH)), num(mkt_wage), num((sum(CASH) * PPM) // mkt_wage)))
    dump("scenario.json", d)


def patch_assertions():
    """只替换 assert.cash_total 的 _note_zh 字符串本身，保留本文件的手排版式（数组单行）。"""
    raw = assert_raw
    target = [c for c in assert_j["checks"] if c["id"] == "assert.cash_total"]
    assert len(target) == 1
    old = target[0]["_note_zh"]
    new = (
        "INV-018：全经济现金总量恒定，等于 scenario.total_cash_uu。这条断言是「没有无来源资金」（计划书 §16 "
        "人工评审要点、§15 G1 门槛）在载入期的锚点：它把 56 个现金科目的初值和钉死在一个可对账的常数上，之后任何一季"
        "现金总量变动都会被同一个恒等式抓住。expect 写成字段路径而非字面量是有意的——总量本身是 derived，不该在本文件"
        "再抄一遍数字，否则就出现第二个事实来源。当前 scenario.json /total_cash_uu = %d（R-SCALE-01 刻度），其构成为 "
        "gov %d + invpool %d + row %d + 36 个群组合计 %d + 16 个 cell 合计 %d + agent.opening 0（OQ-217 裁定开账分录的"
        "现金腿不经 agent.opening，其现金科目恒为 0）。cells_init.json /cells[*]/cash_uu 实测求和 = %d，已核对一致；"
        "R-REGION-01 之前 cell 合计为 20000000000、总量为 55000000000（每个 cell 的开局现金改为不少于一季工资 + "
        "中间投入后重新求和）。"
        % (TOTAL_CASH, GOV_CASH, INVPOOL_CASH, ROW_CASH, GROUP_CASH, sum(CASH), sum(CASH)))
    enc_old = json.dumps(old, ensure_ascii=False)
    enc_new = json.dumps(new, ensure_ascii=False)
    assert raw.count(enc_old) == 1, "assertions.json 里 assert.cash_total 的注释不是唯一匹配"
    raw = raw.replace(enc_old, enc_new)
    assert json.loads(raw)["checks"] is not None
    with open(os.path.join(SCEN, "assertions.json"), "w", encoding="utf-8", newline="") as fh:
        fh.write(raw)


if __name__ == "__main__":
    # 报告里有「−」等非 GBK 字符：中文 Windows 控制台默认 GBK，不改就在打印时崩。
    for _stream in (sys.stdout, sys.stderr):
        try:
            _stream.reconfigure(encoding="utf-8")
        except (AttributeError, OSError):
            pass
    if "--check" not in sys.argv and "--apply" not in sys.argv:
        sys.stderr.write(__doc__)
        sys.exit(2)
    selfcheck()
    report()
    if FAILED:
        sys.stderr.write("\n自检失败（%d 项），不写文件：\n  %s\n" % (len(FAILED), "\n  ".join(FAILED[:40])))
        sys.exit(1)
    sys.stdout.write("\n自检全部通过。\n")
    if "--apply" in sys.argv:
        patch_cells()
        patch_io_table()
        patch_scenario()
        patch_assertions()
        sys.stdout.write("已写回 cells_init.json / io_table.json / scenario.json / assertions.json\n")
    else:
        sys.stdout.write("--check：未写文件\n")
