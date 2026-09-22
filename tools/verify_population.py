# -*- coding: utf-8 -*-
"""独立校验：只读 population.json，不复用生成脚本的任何中间量。"""
import json, io, re, sys
P = "C:/Users/Fiber Memory/Documents/Jingwei/content/scenarios/chengwan/population.json"
raw = io.open(P, "rb").read()
ok = True


def chk(name, cond, detail=""):
    global ok
    print(("PASS " if cond else "FAIL ") + name + ("  " + str(detail) if detail else ""))
    if not cond:
        ok = False


chk("E_FILE_FORMAT: 无 BOM", not raw.startswith(b"\xef\xbb\xbf"))
chk("E_FILE_FORMAT: LF 换行", b"\r\n" not in raw)
chk("E_FILE_FORMAT: 末尾单换行", raw.endswith(b"\n") and not raw.endswith(b"\n\n"))
text = raw.decode("utf-8")
chk("E_FLOAT_IN_CONTENT: 无浮点字面量", not re.search(r'[:\[,]\s*-?\d+\.\d+', text))
chk("E_FLOAT_IN_CONTENT: 无指数记号", not re.search(r'[:\[,]\s*-?\d+[eE][+-]?\d+', text))
chk("E_NULL_NOT_ALLOWED", not re.search(r':\s*null', text))
chk("无负零", not re.search(r'[:\[,]\s*-0\b', text))

d = json.loads(text)
chk("schema_kind", d["schema_kind"] == "population_init", d["schema_kind"])
chk("schema_version", d["schema_version"] == 1)

REG = ["beiyuan", "zhongzhou", "haijia", "xiling"]
AGES = ["minor", "working", "elder"]
SK = ["low", "mid", "high"]
DEST = ["sector.agri", "sector.manu", "sector.energy", "sector.services", "pubserv"]
gs = d["groups"]
chk("V-POP-01 恰好 36 条", len(gs) == 36, len(gs))
ids = [g["group_id"] for g in gs]
want = set("group.%s.%s.%s" % (r, a, k) for r in REG for a in AGES for k in SK)
chk("V-POP-01 ID 覆盖且无重复", len(set(ids)) == 36 and set(ids) == want)

G = {g["group_id"]: g for g in gs}


def all_bad(o, path=""):
    if isinstance(o, bool):
        return [path]
    if isinstance(o, float):
        return [path]
    if isinstance(o, dict):
        r = []
        for k, v in o.items():
            r += all_bad(v, path + "/" + k)
        return r
    if isinstance(o, list):
        r = []
        for i, v in enumerate(o):
            r += all_bad(v, path + "/%d" % i)
        return r
    return []


bad = all_bad(gs)
chk("groups 内无浮点/布尔", not bad, bad[:3])

tot = sum(g["population_persons"] for g in gs)
chk("V-POP-02 全国 == 24 000 000", tot == 24_000_000, tot)
byr = {r: sum(G["group.%s.%s.%s" % (r, a, k)]["population_persons"] for a in AGES for k in SK)
       for r in REG}
chk("V-POP-02 分地区 9/7/5/3 百万",
    [byr[r] for r in REG] == [9_000_000, 7_000_000, 5_000_000, 3_000_000], byr)

bad3 = []
for gid, g in G.items():
    age = gid.split(".")[2]
    if age != "working":
        if g["participation_ppm"] != 0:
            bad3.append((gid, "participation"))
        if any(v != 0 for v in g["employed_persons"].values()):
            bad3.append((gid, "employed"))
        if g["support_out_weight_ppm"] != 0:
            bad3.append((gid, "support_out"))
chk("V-POP-03 非劳动年龄组三项为 0", not bad3, bad3[:3])

LFs = {}
EMPs = {}
for gid, g in G.items():
    LFs[gid] = (g["population_persons"] * g["participation_ppm"]) // 1_000_000
    EMPs[gid] = sum(g["employed_persons"][x] for x in DEST)
bad4 = [gid for gid in G if EMPs[gid] > LFs[gid]]
chk("V-POP-04 逐组 employed <= labor_force", not bad4, bad4[:3])
L = sum(LFs.values())
U = L - sum(EMPs.values())
ppm = (U * 1_000_000) // L
chk("V-POP-05 反算失业率 == 80000 ppm", ppm == 80000, "U=%d L=%d ppm=%d" % (U, L, ppm))
chk("V-POP-05 落在 [79500,80500]", 79500 <= ppm <= 80500)

dc = d["derived_check"]["unemployment"]
chk("derived_check 分子一致", dc["numerator_unemployed_persons"] == U, dc["numerator_unemployed_persons"])
chk("derived_check 分母一致", dc["denominator_labor_force_persons"] == L)
chk("derived_check 乘积一致", dc["product_numerator_times_1e6"] == U * 1_000_000)
chk("derived_check ppm 一致", dc["unemployment_ppm"] == ppm == dc["expect_ppm"])
chk("derived_check 总人口一致", d["derived_check"]["total_population_persons"] == tot)
chk("derived_check 地区人口一致",
    all(d["derived_check"]["population_by_region_persons"]["region." + r] == byr[r] for r in REG))

em = d["derived_check"]["employment_cross_check_for_cells_init"]
m = em["by_region_dest_skill_persons"]
s1 = sum(m.values())
chk("就业交叉表合计 == 在岗总数", s1 == sum(EMPs.values()) == em["total_employed_persons"], s1)
recon = True
for r in REG:
    for k in SK:
        g = G["group.%s.working.%s" % (r, k)]
        for dst in DEST:
            if m["region.%s|%s|%s" % (r, dst, k)] != g["employed_persons"][dst]:
                recon = False
chk("就业交叉表与 groups 逐项一致", recon)
chk("by_dest 合计一致", sum(em["by_dest_persons"].values()) == s1)

for kind in ("health", "education", "utility"):
    w = sum(G[i]["service_access_ppm"][kind] * G[i]["population_persons"] for i in G)
    chk("V-POP-07 %s 人口加权 == 1e6" % kind, w == 1_000_000 * 24_000_000, w // 24_000_000)
chk("V-POP-07 consumption_index 全 1e6", all(g["consumption_index_ppm"] == 1_000_000 for g in gs))
chk("V-POP-07 living_index 全 1e6", all(g["living_index_ppm"] == 1_000_000 for g in gs))

rng = True
det = []
for gid, g in G.items():
    if not (0 <= g["participation_ppm"] <= 1_000_000):
        rng = False; det.append((gid, "part"))
    for kind in ("health", "education", "utility"):
        if not (0 <= g["service_access_ppm"][kind] <= 1_000_000):
            rng = False; det.append((gid, kind))
    if not (0 <= g["expectation_ppm"] <= 2_000_000):
        rng = False; det.append((gid, "exp"))
    if not (0 <= g["trust_ppm"] <= 1_000_000):
        rng = False; det.append((gid, "trust"))
    if not (0 <= g["support_ppm"] <= 1_000_000):
        rng = False; det.append((gid, "support"))
    if g["base_per_capita_real_income_uu"] <= 0:
        rng = False; det.append((gid, "pci"))
    if len(g["bloc_affiliation_ppm"]) != 3 or any(not (0 <= v <= 1_000_000)
                                                  for v in g["bloc_affiliation_ppm"]):
        rng = False; det.append((gid, "bloc"))
    for f in ("cash_uu", "deposit_uu", "housing_units_occupied"):
        if g[f] < 0:
            rng = False; det.append((gid, f))
chk("区间全部合法", rng, det[:5])

KEYS = {"group_id", "population_persons", "participation_ppm", "employed_persons", "cash_uu",
        "deposit_uu", "housing_units_occupied", "support_out_weight_ppm", "service_access_ppm",
        "consumption_index_ppm", "living_index_ppm", "base_per_capita_real_income_uu",
        "expectation_ppm", "trust_ppm", "support_ppm", "bloc_affiliation_ppm"}
extra = set()
for g in gs:
    extra |= (set(g.keys()) - KEYS)
chk("groups[] 键集合严格等于 §5.7", not extra, extra)
chk("employed_persons 键集合", all(set(g["employed_persons"].keys()) == set(DEST) for g in gs))
chk("service_access_ppm 键集合",
    all(set(g["service_access_ppm"].keys()) == {"health", "education", "utility"} for g in gs))

dr = d["demography_rates"]
chk("demography_rates 键集合",
    set(dr.keys()) == {"birth_ppm_per_q", "death_ppm_per_q", "age_out_ppm_per_q",
                       "birth_target_skill"}, set(dr.keys()))
chk("birth 四地区齐全", set(dr["birth_ppm_per_q"].keys()) == {"region." + r for r in REG})
chk("death 三年龄齐全", set(dr["death_ppm_per_q"].keys()) == set(AGES))
chk("age_out 两项", set(dr["age_out_ppm_per_q"].keys()) == {"minor", "working"})
chk("birth_target_skill", dr["birth_target_skill"] in SK)

chk("顶层键", set(d.keys()) == {"schema_kind", "schema_version", "_note_schema_kind",
                               "_note_extensions", "groups", "demography_rates",
                               "derived_check", "extensions"}, set(d.keys()))

ge = {x["group_id"]: x for x in d["extensions"]["groups_ext"]}
chk("groups_ext 36 条且 ID 对齐", len(ge) == 36 and set(ge) == want)
bad5 = []
for gid, x in ge.items():
    g = G[gid]
    if x["labor_force_persons"] != LFs[gid]:
        bad5.append((gid, "lf"))
    if x["employed_persons_total"] != EMPs[gid]:
        bad5.append((gid, "emp"))
    if x["unemployed_persons"] != LFs[gid] - EMPs[gid]:
        bad5.append((gid, "unemp"))
    if x["housing"]["units_occupied"] != g["housing_units_occupied"]:
        bad5.append((gid, "house"))
    li = x["base_income_lines_uu_per_q"]
    disp = (li["wage"] + li["business_distribution"] + li["transfer"] + li["other_property_income"]
            - li["income_tax_paid"] + li["household_support_in"] - li["household_support_out"])
    if disp != x["base_disposable_income_uu_per_q"]:
        bad5.append((gid, "disp"))
    if (x["base_disposable_income_uu_per_q"] * 4) // g["population_persons"] != \
            g["base_per_capita_real_income_uu"]:
        bad5.append((gid, "pci"))
chk("groups_ext 与 groups 逐项自洽", not bad5, bad5[:5])
chk("Σ support_in == Σ support_out",
    sum(ge[i]["base_income_lines_uu_per_q"]["household_support_in"] for i in ge) ==
    sum(ge[i]["base_income_lines_uu_per_q"]["household_support_out"] for i in ge))
chk("Σ base_equity_share_ppm == 1e6", sum(ge[i]["base_equity_share_ppm"] for i in ge) == 1_000_000)
for kind in ("health", "education", "utility"):
    w = sum(ge[i]["base_service_delivery_index_ppm"][kind] * G[i]["population_persons"] for i in ge)
    chk("交付基准指数 %s 人口加权 == 1e6" % kind, w == 1_000_000 * 24_000_000, w // 24_000_000)
bi = d["derived_check"]["base_income_identity_uu_per_q"]
RATE = d["derived_check"]["cross_file_check"]["from_scenario_json"]["wage_uu_per_person_q"]
wage_recomputed = sum(EMPs["group.%s.working.%s" % (r, k)] * RATE[SK.index(k)]
                      for r in REG for k in SK)
chk("收入恒等式 wage 合计 == 工资率 × 在岗人数",
    bi["wage"] == sum(ge[i]["base_income_lines_uu_per_q"]["wage"] for i in ge) == wage_recomputed,
    (bi["wage"], wage_recomputed))
chk("Σ deposit == invpool 现金 + invpool 持债",
    sum(g["deposit_uu"] for g in gs) ==
    d["derived_check"]["cross_file_check"]["from_government_init_json"]["invpool_cash_uu"] +
    d["derived_check"]["cross_file_check"]["from_government_init_json"]["invpool_bondhold_uu"])
cf = d["derived_check"]["cross_file_check"]["from_regions_json"]
chk("V-POP-06 逐地区占用 <= regions.json 住房存量",
    all(cf["occupied_units_written_here"]["region." + r] <= cf["housing_stock_units"]["region." + r]
        for r in REG),
    {r: (cf["occupied_units_written_here"]["region." + r],
         cf["housing_stock_units"]["region." + r]) for r in REG})
chk("收入恒等式 disposable 合计",
    bi["disposable_income"] == sum(ge[i]["base_disposable_income_uu_per_q"] for i in ge))
chk("Σ deposit == 交叉校验值",
    sum(g["deposit_uu"] for g in gs) ==
    d["derived_check"]["deposit_cross_check_for_government_init"]["required_invpool_cash_plus_bondhold_uu"])
chk("Σ cash == 交叉校验值",
    sum(g["cash_uu"] for g in gs) ==
    d["derived_check"]["cash_cross_check_for_scenario"]["sum_group_cash_uu"])
hc = d["derived_check"]["housing_cross_check_for_regions_init"]
chk("住房交叉校验一致",
    all(hc["occupied_units_by_region"]["region." + r] ==
        sum(G["group.%s.%s.%s" % (r, a, k)]["housing_units_occupied"] for a in AGES for k in SK)
        for r in REG)
    and hc["total_occupied_units"] == sum(g["housing_units_occupied"] for g in gs))

NINE = {"value", "unit", "source_type", "source_ref", "reference_year", "definition",
        "valid_range", "confidence", "calibration_note"}
cards = d["extensions"]["source_cards"]
missing = [c.get("card_id") for c in cards if not NINE.issubset(set(c.keys()))]
chk("每张身份证九字段齐全", not missing, missing)
badsrc = [c["card_id"] for c in cards if c["source_type"] not in
          ("observed", "literature", "design_assumption", "derived")]
chk("source_type 合法", not badsrc, badsrc)
chk("V-PC-04 observed 条目为 0",
    not [c["card_id"] for c in cards if c["source_type"] == "observed"])
chk("derived 卡带 derivation 说明",
    all("derivation_expr" in c["definition"] for c in cards if c["source_type"] == "derived"),
    [c["card_id"] for c in cards if c["source_type"] == "derived"])

print()
print("group count check:", len(gs))
print("ALL PASS" if ok else "HAS FAILURES")
sys.exit(0 if ok else 1)
