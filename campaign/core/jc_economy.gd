## v2 经济结算（docs/57 §4—§6）：用工、设施能力、居民需要、按次序生产、分配、出口、资金、入库、价格与工钱。
##
## 资金规则（与 tools/content_v2/calib.py 一致）：
##   · 所有买方按市价付款进该商品的「货款池」；居民另付零售加价（归本地区集市）与盐课（归国库，征不上的归私盐贩）；
##   · 货款池先付进口商，其余按本季产量分给各生产堆；生产堆把物流费付给本地区车马行；
##   · 生产堆付工钱、投入（进别的货款池）、维护材料（同上）、税，余下为利润：农田地租份额归士绅、其余归农户，
##     其余民营归商贾，官营归国库；亏损由所有者储蓄承担，承担不起时欠薪；
##   · 居民在季初按手上的钱定预算，收入在季末入账；农户买口粮不付零售加价（自产自食）；
##   · 积蓄规则：积蓄在目标（几个季度的开销）以上时把收入花完、多出来的每季再花 5%；不够时每季最多省下「储蓄率」；
##   · 日用水平（篮子）每季向「预算能负担的水平」靠拢 15%：收入涨了日用跟着涨，价钱涨了日用跟着缩；
##   · 国库不够时按「开支到位率」减员欠饷；季末国库若为负，向商贾强借，记为债务；
##   · 每一厘都有来处和去处：Σ 储蓄 + 国库 == 开局货币 + 累计白银净流入（jc_sim.gd 每季核对）。
class_name JCEconomy
extends RefCounted

const PPM: int = 1_000_000
const QS: int = 1000

const B_OK: int = 0
const B_LABOR: int = 1
const B_INPUT: int = 2
const B_LAND: int = 3
const B_WATER: int = 4
const B_DEMAND: int = 5
const B_FUNDS: int = 6
const B_IDLE: int = 7
const B_UPGRADE: int = 8
## 入不敷出：按现价开工一份亏一份，作坊与矿场自己减产
const B_PRICE: int = 9

## 营造花费里工钱的份额（其余是材料，材料构成按本国时代取 ct.build_g / build_ppm）
const BUILD_WAGE_PPM: int = 500000
## 主料的门槛：占「投入 + 工钱」的份额（ppm）
const MAIN_INPUT_PPM: int = 250_000
## 辅料缺了至少也按这个份额减产（一样没有也不至于一点不受影响）
const MINOR_INPUT_FLOOR: int = 100_000
## 日用水平的上下限（ppm）
const BASKET_MIN: int = 20_000
const BASKET_MAX: int = 6_000_000
## 商贾、士绅这样的富户，日用可以讲究得多（绸缎、瓷器、书籍、家具……）
const BASKET_MAX_RICH: int = 15_000_000

var ct: JCContent
var st: JCState
var mods: JCMods
var R: int = 0
var C: int = 0
var G: int = 0
var N: int = 0
var S: int = 0
var CL_P: int = 0
var CL_A: int = 1
var CL_M: int = 2
var CL_G: int = 3

# ── 地区派生量 ──
var log_r: PackedInt64Array
var margin_r: PackedInt64Array
var cap_commerce: PackedInt64Array
var cap_freight: PackedInt64Array
var irrig_cov: PackedInt64Array
var water_cov: PackedInt64Array
var admin_cap: PackedInt64Array
var edu_seats: PackedInt64Array
var health_cov: PackedInt64Array
var sanit_cov: PackedInt64Array
var amen_cov: PackedInt64Array
var survey_lv: PackedInt64Array
var farm_lv: PackedInt64Array
var land_used: PackedInt64Array
var literacy_bld: PackedInt64Array
var customs_bonus: int = 0
var grain_cap: int = 0
var cap_sea: int = 0
var cap_land: int = 0
var used_sea: int = 0
var used_land: int = 0
var research_bld: int = 0

# ── 用工 ──
var lab_dem: PackedInt64Array
var lab_sup: PackedInt64Array
var lab_fill: PackedInt64Array
var lab_used: PackedInt64Array

# ── 每堆 ──
var s_eff_lv: PackedInt64Array
var s_lfill: PackedInt64Array
var s_ufin: PackedInt64Array
var s_rev: PackedInt64Array
var s_cost_in: PackedInt64Array
var s_cost_maint: PackedInt64Array
var s_outq: Array = []
## 每堆每种维护材料的需要量（与 cur_maint_g 对齐）
var s_maint_q: Array = []
## 本季的维护与营造用料（按本国时代）
var cur_maint_g: PackedInt64Array = PackedInt64Array()
var cur_maint_ppm: PackedInt64Array = PackedInt64Array()
var cur_build_g: PackedInt64Array = PackedInt64Array()
var cur_build_ppm: PackedInt64Array = PackedInt64Array()
## 开局篮子（期待的基准）与各时代的期待倍数
var basket0: PackedInt64Array = PackedInt64Array()
var comfort_expect: PackedInt64Array = PackedInt64Array()

# ── 商品 ──
var avail: PackedInt64Array
var stock0: PackedInt64Array
var prod: PackedInt64Array
var used_in: PackedInt64Array
var pool: PackedInt64Array
var imp_q: PackedInt64Array
var imp_cost: PackedInt64Array
var exp_q: PackedInt64Array
var exp_v: PackedInt64Array
var hh_q: PackedInt64Array
var gov_q: PackedInt64Array
var firm_q: PackedInt64Array
var want_tot: PackedInt64Array
var reserve_ess: PackedInt64Array
var gov_want: PackedInt64Array
var firm_want: PackedInt64Array
var fill_ess: PackedInt64Array
var fill_firm: PackedInt64Array
var fill_non: PackedInt64Array
## 生产投入的缺口（没买到的量），并进商品的「缺口」
var short_in: PackedInt64Array
## 本季各商品作为生产投入的到货比例（ppm；没人用的为 PPM）——民间投资估原料用
var in_fill: PackedInt64Array = PackedInt64Array()

# ── 居民 ──
var budget: PackedInt64Array
var spent: PackedInt64Array
var hh_want: PackedInt64Array      # (R*C)*G
var ess_want: PackedInt64Array     # (R*C)*G
var hh_got: PackedInt64Array       # (R*C)*G
var want_ng: PackedInt64Array      # ((R*C)*N + n)*G：每项需要对各商品的需要量（给满足度折算）
var need_ref: PackedInt64Array     # (R*C)*N
var inc: PackedInt64Array
## 收入来源（(R*C)*SRC_N）：工钱、经营与地租、官府发放、亏损与出资（负数）
const SRC_WAGE: int = 0
const SRC_PROFIT: int = 1
const SRC_GOV: int = 2
const SRC_LOSS: int = 3
const SRC_N: int = 4
var inc_src: PackedInt64Array = PackedInt64Array()
## 真实空缺（招工）：卡在人手上的作坊还缺的人
var vacancy: PackedInt64Array
var margin_pool: PackedInt64Array
var fee_pool: PackedInt64Array
var port_pool: int = 0
var cara_pool: int = 0

# ── 营造（由 JCInvest 填） ──
var job_stack: PackedInt64Array = PackedInt64Array()
var job_landmark: PackedInt64Array = PackedInt64Array()
var job_region: PackedInt64Array = PackedInt64Array()
var job_value: PackedInt64Array = PackedInt64Array()
var job_funder: PackedInt64Array = PackedInt64Array()
var job_fill: PackedInt64Array = PackedInt64Array()
var job_mat_q: Array = []

var prev_demand: PackedInt64Array = PackedInt64Array()
## 上季各商品的供给（产量 + 进口 + 半数库存），新商品普及时看「市面上有没有」
var prev_supply: PackedInt64Array = PackedInt64Array()
## 新时代的商品与需要从进入该时代起，多少季普及到满
const ADOPT_Q: int = 100
var summary: Dictionary = {}
var _imp_left: Dictionary = {}
var _exp_pg: Dictionary = {}


func setup(p_ct: JCContent, p_st: JCState, p_mods: JCMods) -> void:
	ct = p_ct
	st = p_st
	mods = p_mods
	R = ct.r_n
	C = ct.c_n
	G = ct.g_n
	N = ct.n_n
	CL_P = int(ct.cidx.get("peasant", 0))
	CL_A = int(ct.cidx.get("artisan", 1))
	CL_M = int(ct.cidx.get("merchant", 2))
	CL_G = int(ct.cidx.get("gentry", 3))
	basket0 = JCMath.filled(R * C, PPM)
	var bk: Dictionary = ct.scenario.get("basket_ppm", {})
	for r: int in R:
		for c: int in C:
			basket0[r * C + c] = maxi(BASKET_MIN, int(bk.get(ct.r_id[r] + ":" + ct.c_id[c], PPM)))
	comfort_expect = PackedInt64Array([PPM, PPM, 1_300_000, 1_700_000, 2_300_000])
	var ce: Array = ct.scenario.get("gov", {}).get("comfort_expect_ppm", [])
	for e: int in mini(ce.size(), 4):
		comfort_expect[e + 1] = int(ce[e])


func clear_jobs() -> void:
	job_stack = PackedInt64Array()
	job_landmark = PackedInt64Array()
	job_region = PackedInt64Array()
	job_value = PackedInt64Array()
	job_funder = PackedInt64Array()
	job_fill = PackedInt64Array()
	job_mat_q = []


## 登记一项本季营造：value_li 是本季计划花费（已按出资方的钱封顶）。
func add_job(stack: int, landmark: int, region: int, value_li: int, funder: int) -> void:
	job_stack.append(stack)
	job_landmark.append(landmark)
	job_region.append(region)
	job_value.append(value_li)
	job_funder.append(funder)
	job_fill.append(0)


# ════════════════════════════════════════════════════════════════════════
func run() -> void:
	S = st.stack_count()
	prev_supply = JCMath.zeros(G)
	for g: int in G:
		@warning_ignore("integer_division")
		prev_supply[g] = st.f_prod[g] + st.f_imp[g] + st.stock[g] / 2
	_zero()
	_levels()
	_labor()
	_capacities()
	_hh_budgets()
	_firm_wants()
	_produce()
	_allocate()
	_export()
	_settle()
	_stock()
	_prices()
	_wages()
	_fix_negatives()
	_summary()


func _zero() -> void:
	log_r = JCMath.zeros(R)
	margin_r = JCMath.zeros(R)
	cap_commerce = JCMath.zeros(R)
	cap_freight = JCMath.zeros(R)
	irrig_cov = JCMath.zeros(R)
	water_cov = JCMath.zeros(R)
	admin_cap = JCMath.zeros(R)
	edu_seats = JCMath.zeros(R)
	health_cov = JCMath.zeros(R)
	sanit_cov = JCMath.zeros(R)
	amen_cov = JCMath.zeros(R)
	survey_lv = JCMath.zeros(R)
	farm_lv = JCMath.zeros(R)
	land_used = JCMath.zeros(R * JCContent.LT_N)
	literacy_bld = JCMath.zeros(R)
	customs_bonus = 0
	grain_cap = 0
	cap_sea = 0
	cap_land = 0
	used_sea = 0
	used_land = 0
	research_bld = 0
	lab_dem = JCMath.zeros(R * C)
	lab_sup = JCMath.zeros(R * C)
	lab_fill = JCMath.filled(R * C, PPM)
	lab_used = JCMath.zeros(R * C)
	s_eff_lv = JCMath.zeros(S)
	s_lfill = JCMath.zeros(S)
	s_ufin = JCMath.zeros(S)
	s_rev = JCMath.zeros(S)
	s_cost_in = JCMath.zeros(S)
	s_cost_maint = JCMath.zeros(S)
	s_outq = []
	s_maint_q = []
	cur_maint_g = ct.maint_g(st.era)
	cur_maint_ppm = ct.maint_ppm(st.era)
	cur_build_g = ct.build_g(st.era)
	cur_build_ppm = ct.build_ppm(st.era)
	for i: int in S:
		s_outq.append(JCMath.zeros(ct.m_out_g[st.s_m[i]].size()))
		s_maint_q.append(JCMath.zeros(cur_maint_g.size()))
	avail = st.stock.duplicate()
	stock0 = st.stock.duplicate()
	prod = JCMath.zeros(G)
	used_in = JCMath.zeros(G)
	pool = JCMath.zeros(G)
	imp_q = JCMath.zeros(G)
	imp_cost = JCMath.zeros(G)
	exp_q = JCMath.zeros(G)
	exp_v = JCMath.zeros(G)
	hh_q = JCMath.zeros(G)
	gov_q = JCMath.zeros(G)
	firm_q = JCMath.zeros(G)
	want_tot = JCMath.zeros(G)
	reserve_ess = JCMath.zeros(G)
	gov_want = JCMath.zeros(G)
	firm_want = JCMath.zeros(G)
	fill_ess = JCMath.filled(G, PPM)
	fill_firm = JCMath.filled(G, PPM)
	fill_non = JCMath.filled(G, PPM)
	short_in = JCMath.zeros(G)
	in_fill = JCMath.filled(G, PPM)
	budget = JCMath.zeros(R * C)
	spent = JCMath.zeros(R * C)
	hh_want = JCMath.zeros(R * C * G)
	ess_want = JCMath.zeros(R * C * G)
	hh_got = JCMath.zeros(R * C * G)
	want_ng = JCMath.zeros(R * C * N * G)
	need_ref = JCMath.zeros(R * C * N)
	inc = JCMath.zeros(R * C)
	inc_src = JCMath.zeros(R * C * SRC_N)
	vacancy = JCMath.zeros(R * C)
	margin_pool = JCMath.zeros(R)
	fee_pool = JCMath.zeros(R)
	port_pool = 0
	cara_pool = 0
	_exp_pg.clear()
	job_mat_q = []
	for j: int in job_value.size():
		job_mat_q.append(JCMath.zeros(cur_build_g.size()))
	for g: int in G:
		st.f_prod[g] = 0
		st.f_hh[g] = 0
		st.f_use[g] = 0
		st.f_gov[g] = 0
		st.f_exp[g] = 0
		st.f_imp[g] = 0
		st.f_unmet[g] = 0
		st.f_demand[g] = 0
	st.rev.fill(0)
	st.exp.fill(0)
	st.arrears = 0
	for p: int in st.p_exp.size():
		st.p_exp[p] = 0
		st.p_imp[p] = 0


## 有效级数（ppm·级）：在用级数 × 状态系数 × 官办设施的拨款到位比例。
func _levels() -> void:
	for i: int in S:
		var lv: int = st.s_level[i]
		var f: int = PPM
		match st.s_status[i]:
			JCState.ST_MOTHBALL:
				f = 0
			JCState.ST_UPGRADE:
				f = 500_000
			JCState.ST_NEW:
				f = 0
		var b: int = st.s_b[i]
		var cat: int = ct.b_cat[b]
		if st.s_owner[i] == JCContent.OWNER_GOV and (cat == JCContent.CAT_PUBLIC or cat == JCContent.CAT_INFRA):
			f = JCMath.mulppm(f, mini(PPM, st.budget[budget_line(b)]))
			f = JCMath.mulppm(f, st.gov_fund)
		s_eff_lv[i] = lv * f
		if ct.b_land[b] >= 0 and lv > 0:
			land_used[st.s_region[i] * JCContent.LT_N + ct.b_land[b]] += lv
		if cat == JCContent.CAT_FARM and ct.b_land[b] >= 0 and ct.b_land[b] <= 2:
			farm_lv[st.s_region[i]] += lv


func budget_line(b: int) -> int:
	match ct.b_id[b]:
		"yamen", "surveyoffice":
			return JCState.BUD_ADMIN
		"school", "library", "theater":
			return JCState.BUD_EDU
		"clinic", "urbanworks":
			return JCState.BUD_HEALTH
	return JCState.BUD_WORKS


func _exp_line_of(b: int) -> int:
	match budget_line(b):
		JCState.BUD_ADMIN:
			return JCState.EXP_ADMIN
		JCState.BUD_EDU:
			return JCState.EXP_EDU
		JCState.BUD_HEALTH:
			return JCState.EXP_HEALTH
	return JCState.EXP_WORKS


func _is_facility(b: int) -> bool:
	var cat: int = ct.b_cat[b]
	return cat == JCContent.CAT_PUBLIC or cat == JCContent.CAT_INFRA


# ── 用工 ────────────────────────────────────────────────────────────────
func labor_need(i: int, c: int) -> int:
	var m: int = st.s_m[i]
	var per: int = ct.m_labor[m * C + c]
	if per <= 0 or s_eff_lv[i] <= 0:
		return 0
	var need: int = JCMath.muldiv(per, s_eff_lv[i], PPM)
	var cat: int = ct.b_cat[st.s_b[i]]
	if cat == JCContent.CAT_WORKSHOP or cat == JCContent.CAT_MINE:
		need = JCMath.mulppm(need, mods.mult_ppm("workshop_labor"))
	return need


var soldier_r: PackedInt64Array = PackedInt64Array()


func _labor() -> void:
	# 兵员优先：按人口从各地区农户里抽，剩下的农户才去种地做工
	var sc: Dictionary = ct.scenario.get("gov", {})
	var army: int = JCMath.mulppm(mini(PPM, st.budget[JCState.BUD_ARMY]), st.gov_fund)
	var soldiers: int = JCMath.mulppm(st.soldiers, army)
	var sw: PackedInt64Array = JCMath.zeros(R)
	for r0: int in R:
		sw[r0] = st.pop[r0 * C + CL_P]
	soldier_r = JCMath.split(soldiers, sw)
	for i: int in S:
		var r: int = st.s_region[i]
		for c: int in C:
			lab_dem[r * C + c] += labor_need(i, c)
	for j: int in job_value.size():
		var r2: int = job_region[j]
		var w: int = maxi(1, st.wage[r2 * C + CL_A])
		@warning_ignore("integer_division")
		lab_dem[r2 * C + CL_A] += JCMath.mulppm(job_value[j], BUILD_WAGE_PPM) / w
	for r3: int in R:
		for c2: int in C:
			var k: int = r3 * C + c2
			lab_sup[k] = JCMath.mulppm(st.pop[k], ct.c_work[c2])
			var sup: int = lab_sup[k]
			if c2 == CL_P:
				sup = maxi(0, sup - soldier_r[r3])
			lab_fill[k] = PPM if lab_dem[k] <= 0 else mini(PPM, JCMath.ratio_ppm(sup, lab_dem[k]))
			if c2 == CL_P:
				lab_dem[k] += soldier_r[r3]
	for i2: int in S:
		if s_eff_lv[i2] <= 0:
			continue
		var m2: int = st.s_m[i2]
		var r4: int = st.s_region[i2]
		var f: int = PPM
		var tot_l: int = 0
		for c4: int in C:
			tot_l += ct.m_labor[m2 * C + c4]
		for c3: int in C:
			var need_c: int = ct.m_labor[m2 * C + c3]
			if need_c <= 0:
				continue
			var fc: int = lab_fill[r4 * C + c3]
			# 主力阶层缺多少减多少；只占少数的（掌柜、账房）缺了，别的阶层顶上，只按份额减产
			var share: int = JCMath.ratio_ppm(need_c, maxi(1, tot_l))
			if share < MAIN_INPUT_PPM:
				fc = PPM - JCMath.mulppm(share, PPM - fc)
			f = mini(f, fc)
		s_lfill[i2] = f


# ── 设施能力 ────────────────────────────────────────────────────────────
func _capacities() -> void:
	var cut: PackedInt64Array = JCMath.zeros(R)
	for i: int in S:
		if s_eff_lv[i] <= 0:
			continue
		var b: int = st.s_b[i]
		if not _is_facility(b):
			continue
		var r: int = st.s_region[i]
		var m: int = st.s_m[i]
		var eff: int = JCMath.muldiv(JCMath.mulppm(s_eff_lv[i], s_lfill[i]), ct.m_eff[m], PPM)
		# 上季缺投入（纸墨、药材、船只……）也折进来，最低三成
		eff = JCMath.mulppm(eff, maxi(st.s_u[i], 300_000))
		var e: Dictionary = ct.b_effects[b]
		for key: Variant in e.keys():
			var v: int = int(e[key])
			match String(key):
				"commerce":
					cap_commerce[r] += JCMath.muldiv(v * 1000, eff, PPM)
				"freight":
					cap_freight[r] += JCMath.muldiv(v * 1000, eff, PPM)
				"logistics_cut":
					cut[r] += JCMath.muldiv(v, eff, PPM)
				"sea_trade":
					cap_sea += JCMath.muldiv(v * 1000, eff, PPM)
				"land_trade":
					cap_land += JCMath.muldiv(v * 1000, eff, PPM)
				"customs_eff":
					customs_bonus += JCMath.muldiv(v, eff, PPM)
				"irrigate":
					irrig_cov[r] += JCMath.muldiv(v, eff, 1)
				"waterpower":
					water_cov[r] += JCMath.muldiv(v, eff, 1)
				"grain_store":
					grain_cap += JCMath.muldiv(v * QS, eff, PPM)
				"survey":
					survey_lv[r] += eff
				"edu_seats":
					edu_seats[r] += JCMath.muldiv(v, JCMath.mulppm(eff, mods.mult_ppm("edu_eff")), PPM)
				"research":
					research_bld += JCMath.muldiv(v, eff, PPM)
				"literacy":
					literacy_bld[r] += JCMath.muldiv(v, eff, PPM)
				"health":
					health_cov[r] += JCMath.muldiv(v, JCMath.mulppm(eff, mods.mult_ppm("health_eff")), PPM)
				"admin":
					admin_cap[r] += JCMath.muldiv(v, JCMath.mulppm(eff, mods.mult_ppm("admin_eff")), PPM)
				"amenity":
					amen_cov[r] += JCMath.muldiv(v, eff, PPM)
				"sanitation":
					sanit_cov[r] += JCMath.muldiv(v, eff, PPM)
	cap_sea = JCMath.mulppm(cap_sea, mods.mult_ppm("sea_trade_cap"))
	cap_land = JCMath.mulppm(cap_land, mods.mult_ppm("land_trade_cap"))
	var all_cut: int = mods.delta_ppm("logistics_cut_all")
	for r2: int in R:
		var l: int = ct.r_logistics[r2] - cut[r2] - all_cut - mods.delta_ppm("logistics_cut", ct.r_id[r2]) \
				+ mods.delta_ppm("logistics_cut")
		log_r[r2] = maxi(10_000, l)
		st.logistics[r2] = log_r[r2]
		cap_commerce[r2] = JCMath.mulppm(cap_commerce[r2], mods.mult_ppm("commerce_cap"))
		cap_freight[r2] = maxi(cap_freight[r2], 0)


# ── 居民预算与需要 ──────────────────────────────────────────────────────
func consumer_price(g: int, r: int, c: int = -1) -> int:
	var p: int = st.price[g]
	if not (c == CL_P and ct.g_own[g] == 1):
		p += JCMath.mulppm(st.price[g], margin_r[r])
	if ct.g_id[g] == "salt":
		p += JCMath.mulppm(st.tax_salt_li, mods.mult_ppm("salt_markup"))
	return p


## 某项需要在某地区、本时代的商品份额（ppm）。
func need_shares(n: int, r: int) -> PackedInt64Array:
	var gs: PackedInt64Array = ct.n_goods[n]
	var out: PackedInt64Array = JCMath.zeros(gs.size())
	var taste: Dictionary = ct.n_taste[n][r]
	var tot: int = 0
	for k: int in gs.size():
		var g: int = gs[k]
		if ct.g_era[g] > st.era or ct.g_era_end[g] + 1 < st.era:
			continue
		var w: int = 0
		if not taste.is_empty():
			w = int(taste.get(g, 0))
			# 口味表里没写的新时代商品：只分一小份（主要靠普及度与市面供给慢慢长）
			if w == 0 and ct.g_era[g] > 1:
				w = 100_000 * ct.g_era[g]
		else:
			var first: bool = true
			for k0: int in k:
				if ct.g_era[gs[k0]] == ct.g_era[g]:
					first = false
					break
			if first:
				w = PPM << ((ct.g_era[g] - 1) * 2)
		# 新时代的商品：进入那个时代后慢慢普及，而且市面上得真有货（没货时只留一成，好让缺口显出来）
		if ct.g_era[g] > 1 and w > 0:
			w = JCMath.mulppm(JCMath.mulppm(w, adoption(ct.g_era[g])), _avail(g))
		out[k] = w
		tot += w
	if tot <= 0:
		return out
	for k2: int in gs.size():
		out[k2] = JCMath.muldiv(out[k2], PPM, tot)
	return out


## 日用需要随篮子伸缩：弹性 0.5 / 1 / 1.5 → √b、b、b√b（ppm）；必需品恒为 1。
func need_mult(n: int, b: int) -> int:
	var a: int = adoption(ct.n_era[n])
	if ct.n_ess[n] == 1:
		return a
	var m: int = b
	match ct.n_el[n]:
		500_000:
			m = JCMath.isqrt(b * PPM)
		1_500_000:
			m = JCMath.muldiv(b, JCMath.isqrt(b * PPM), PPM)
	return JCMath.mulppm(m, a)


## 普及度（ppm）：第一时代的东西恒为满；更晚时代的，本国进入那个时代之前为零，之后 ADOPT_Q 季从一成涨到满。
func adoption(era_x: int) -> int:
	if era_x <= 1:
		return PPM
	if st.era < era_x:
		return 0
	var q0: int = st.era_q[era_x] if st.era_q.size() > era_x and st.era_q[era_x] >= 0 else st.q
	@warning_ignore("integer_division")
	return clampi(100_000 + (st.q - q0) * 900_000 / ADOPT_Q, 100_000, PPM)


## 市面上有没有：上季供给 ÷ 上季需求（一成到满）；本国既造不出、也买不到的为零。
func _avail(g: int) -> int:
	if not _obtainable(g):
		return 0
	var d: int = prev_demand[g] if prev_demand.size() > g else 0
	var s: int = prev_supply[g] if prev_supply.size() > g else 0
	if d <= 0:
		return 100_000 if s <= 0 else PPM
	return clampi(JCMath.ratio_ppm(s, d), 100_000, PPM)


var _obt_q: int = -1
var _obt: PackedInt64Array = PackedInt64Array()


## 有没有来路：有已解锁的生产方式，或有来往的伙伴出售（每季算一次）。
func _obtainable(g: int) -> bool:
	if _obt_q != st.q or _obt.size() != G:
		_obt_q = st.q
		_obt = JCMath.zeros(G)
		for m: int in ct.m_n:
			var b: int = ct.m_b[m]
			if ct.m_tech[m] >= 0 and st.t_done[ct.m_tech[m]] != 1:
				continue
			if ct.b_tech[b] >= 0 and st.t_done[ct.b_tech[b]] != 1:
				continue
			if ct.m_era[m] > st.era + 1:
				continue
			for g2: int in ct.m_out_g[m]:
				_obt[g2] = 1
		for p: int in ct.partners.size():
			if st.p_active[p] != 1:
				continue
			for gk: Variant in ct.partners[p].get("offers", {}).keys():
				var g3: int = int(ct.gidx.get(String(gk), -1))
				if g3 >= 0:
					_obt[g3] = 1
	return _obt[g] == 1


## 某组某项需要的花费；mult 是已经换算好的伸缩倍数（ppm，必需品传 PPM）。
func _need_cost(n: int, r: int, c: int, persons: int, mult: int) -> int:
	var units: int = JCMath.mulppm(persons * ct.n_qty[n * C + c], mult)
	if units <= 0:
		return 0
	var sh: PackedInt64Array = need_shares(n, r)
	var gs: PackedInt64Array = ct.n_goods[n]
	var cv: PackedInt64Array = ct.n_conv[n]
	var cost: int = 0
	for k: int in gs.size():
		if sh[k] <= 0 or cv[k] <= 0:
			continue
		var q: int = JCMath.muldiv(JCMath.mulppm(units, sh[k]), PPM, cv[k])
		cost += JCMath.value(q, consumer_price(gs[k], r, c))
	return cost


## 某组某项需要的「满额」需要单位（非必需品按本组的日用篮子缩放）。
func need_units(k: int, n: int) -> int:
	var c: int = k % C
	return JCMath.mulppm(st.pop[k] * ct.n_qty[n * C + c], need_mult(n, st.basket[k]))


## 篮子为 b 时的日用总花费（三组弹性各自的「篮子为 1」花费已汇总好）。
static func _cost_at(c_half: int, c_one: int, c_3h: int, b: int) -> int:
	var sq: int = JCMath.isqrt(b * PPM)
	return JCMath.mulppm(c_half, sq) + JCMath.mulppm(c_one, b) + JCMath.mulppm(JCMath.mulppm(c_3h, b), sq)


## 除去必需品后还剩 avail，能负担的日用水平（二分）。cost1 是各项需要在篮子为 1 时的花费。
func _afford_basket(cost1: PackedInt64Array, avail: int, cap: int = BASKET_MAX) -> int:
	var c_half: int = 0
	var c_one: int = 0
	var c_3h: int = 0
	for n: int in N:
		if ct.n_ess[n] == 1 or cost1[n] <= 0:
			continue
		match ct.n_el[n]:
			500_000:
				c_half += cost1[n]
			1_500_000:
				c_3h += cost1[n]
			_:
				c_one += cost1[n]
	var lo: int = BASKET_MIN
	var hi: int = cap
	if avail <= _cost_at(c_half, c_one, c_3h, lo):
		return lo
	if avail >= _cost_at(c_half, c_one, c_3h, hi):
		return hi
	for it: int in 24:
		@warning_ignore("integer_division")
		var mid: int = (lo + hi) / 2
		if _cost_at(c_half, c_one, c_3h, mid) > avail:
			hi = mid
		else:
			lo = mid
	return lo


func _hh_budgets() -> void:
	var base_margin: int = int(ct.scenario.get("gov", {}).get("commerce_margin_ppm", 80000))
	for r: int in R:
		var retail: int = 0
		for c: int in C:
			retail += st.spend[r * C + c]
		var over: int = 2_500_000
		if cap_commerce[r] > 0:
			over = clampi(JCMath.ratio_ppm(retail, cap_commerce[r]), PPM, 2_500_000)
		margin_r[r] = JCMath.mulppm(base_margin, over)
	for r2: int in R:
		for c2: int in C:
			var k: int = r2 * C + c2
			if st.pop[k] <= 0:
				continue
			# 各项需要在篮子为 1 时的花费
			var cost1: PackedInt64Array = JCMath.zeros(N)
			var ess_cost: int = 0
			for n: int in N:
				if not ct.need_active(n, st.era):
					continue
				cost1[n] = _need_cost(n, r2, c2, st.pop[k], PPM)
				if ct.n_ess[n] == 1:
					ess_cost += cost1[n]
			# 积蓄规则
			var y: int = st.income[k]
			var target_s: int = JCMath.mulppm(maxi(st.spend[k], ess_cost), ct.c_buffer[c2])
			var b: int = y
			if st.savings[k] >= target_s:
				b += JCMath.mulppm(st.savings[k] - target_s, 80_000)
			else:
				var short: int = PPM - JCMath.ratio_ppm(maxi(0, st.savings[k]), maxi(target_s, 1))
				b -= JCMath.mulppm(JCMath.mulppm(y, ct.c_save[c2]), short)
			if b < ess_cost:
				b += mini(ess_cost - b, JCMath.mulppm(maxi(0, st.savings[k]), 250_000))
			# 手上的积蓄加上本季可望的收入（收入季末才到账，季中可以先赊）
			b = clampi(b, 0, maxi(0, st.savings[k]) + maxi(0, y))
			budget[k] = b
			# 日用水平向「能负担的」靠拢
			var cap_b: int = BASKET_MAX_RICH if (c2 == CL_M or c2 == CL_G) else BASKET_MAX
			st.basket[k] = JCMath.approach(st.basket[k], _afford_basket(cost1, b - ess_cost, cap_b), 150_000)
			# 钱不够时：先保口粮与盐，其余各项按同一比例缩减（不是把排在后面的整项砍光）
			var non_cost: int = 0
			for n1: int in N:
				if ct.n_ess[n1] != 1 and ct.need_active(n1, st.era):
					non_cost += JCMath.mulppm(cost1[n1], need_mult(n1, st.basket[k]))
			var f_ess: int = PPM if ess_cost <= b else JCMath.ratio_ppm(b, ess_cost)
			var left_non: int = maxi(0, b - ess_cost)
			var f_non: int = PPM if non_cost <= left_non else JCMath.ratio_ppm(left_non, non_cost)
			for n2: int in N:
				if not ct.need_active(n2, st.era):
					continue
				var units: int = need_units(k, n2)
				need_ref[k * N + n2] = units
				if units <= 0:
					continue
				var frac: int = f_ess if ct.n_ess[n2] == 1 else f_non
				var sh: PackedInt64Array = need_shares(n2, r2)
				var gs: PackedInt64Array = ct.n_goods[n2]
				var cv: PackedInt64Array = ct.n_conv[n2]
				for kk: int in gs.size():
					if sh[kk] <= 0 or cv[kk] <= 0:
						continue
					var g: int = gs[kk]
					var q_full: int = JCMath.muldiv(JCMath.mulppm(units, sh[kk]), PPM, cv[kk])
					var q: int = JCMath.mulppm(q_full, frac)
					want_ng[(k * N + n2) * G + g] += q_full
					hh_want[k * G + g] += q
					want_tot[g] += q
					if ct.n_ess[n2] == 1:
						ess_want[k * G + g] += q
						reserve_ess[g] += q


# ── 国家与企业的需要：军粮军衣、维护材料、营造材料 ────────────────────────
func _firm_wants() -> void:
	var sc: Dictionary = ct.scenario.get("gov", {})
	var army: int = JCMath.mulppm(mini(PPM, st.budget[JCState.BUD_ARMY]), st.gov_fund)
	var soldiers: int = JCMath.mulppm(st.soldiers, army)
	var ration: int = int(sc.get("soldier_ration_milli", 600))
	var cloth: int = int(sc.get("soldier_cloth_milli", 200))
	var gr: int = int(ct.gidx.get("grain", -1))
	var ri: int = int(ct.gidx.get("rice", -1))
	var fb: int = int(ct.gidx.get("fabric", -1))
	var tot: int = soldiers * ration
	@warning_ignore("integer_division")
	var half: int = tot / 2
	gov_want[ri] += half
	gov_want[gr] += tot - half
	reserve_ess[ri] += half
	reserve_ess[gr] += tot - half
	gov_want[fb] += soldiers * cloth
	var lt: int = int(ct.gidx.get("leather", -1))
	if lt >= 0:
		gov_want[lt] += soldiers * int(sc.get("soldier_leather_milli", 0))
	for g: int in G:
		want_tot[g] += gov_want[g]
	# 营造材料
	for j: int in job_value.size():
		var mat: int = JCMath.mulppm(job_value[j], PPM - BUILD_WAGE_PPM)
		var arr: PackedInt64Array = job_mat_q[j]
		for kk: int in cur_build_g.size():
			var g2: int = cur_build_g[kk]
			var q: int = JCMath.qty_of(JCMath.mulppm(mat, cur_build_ppm[kk]), st.price[g2])
			arr[kk] = q
			firm_want[g2] += q
			want_tot[g2] += q
		job_mat_q[j] = arr
	# 维护材料
	for i: int in S:
		if st.s_level[i] <= 0 or st.s_status[i] == JCState.ST_NEW:
			continue
		var mv: int = ct.b_maint[st.s_b[i]] * st.s_level[i]
		if st.s_status[i] == JCState.ST_MOTHBALL:
			@warning_ignore("integer_division")
			mv = mv / 10
		var mq: PackedInt64Array = s_maint_q[i]
		for k: int in cur_maint_g.size():
			var g3: int = cur_maint_g[k]
			var q2: int = JCMath.qty_of(JCMath.mulppm(mv, cur_maint_ppm[k]), st.price[g3])
			mq[k] = q2
			firm_want[g3] += q2
			want_tot[g3] += q2
		s_maint_q[i] = mq


# ── 生产（按秩） ────────────────────────────────────────────────────────
func _produce() -> void:
	_init_import_caps()
	var obs_per_year: int = obs_rate()
	var obs_cap: int = obs_max()
	var water_lv: PackedInt64Array = JCMath.zeros(R)
	for i: int in S:
		if s_eff_lv[i] > 0 and ct.m_water[st.s_m[i]] == 1:
			water_lv[st.s_region[i]] += s_eff_lv[i]
	var ranks_now: Dictionary = _active_ranks()
	var by_rank: Dictionary = {}
	for i2: int in S:
		if s_eff_lv[i2] <= 0:
			continue
		var rk: int = int(ranks_now.get(st.s_m[i2], 0))
		if not by_rank.has(rk):
			by_rank[rk] = PackedInt64Array()
		var arr: PackedInt64Array = by_rank[rk]
		arr.append(i2)
		by_rank[rk] = arr
	var ranks: Array = by_rank.keys()
	ranks.sort()
	for rk2: Variant in ranks:
		var group: PackedInt64Array = by_rank[rk2]
		var uplan: PackedInt64Array = JCMath.zeros(group.size())
		var req: Dictionary = {}
		for gi: int in group.size():
			var i3: int = group[gi]
			var m: int = st.s_m[i3]
			var r: int = st.s_region[i3]
			var u: int = s_lfill[i3]
			var bind: int = B_LABOR if u < PPM else B_OK
			if ct.m_water[m] == 1 and water_lv[r] > 0:
				var wf: int = maxi(500_000, mini(PPM, JCMath.ratio_ppm(water_cov[r], water_lv[r])))
				if wf < u:
					u = wf
					bind = B_WATER
			var dc: int = _demand_cap(m)
			if dc < u:
				u = dc
				bind = B_DEMAND
			var pc: int = _price_cap(i3)
			if pc < u:
				u = pc
				bind = B_PRICE
			uplan[gi] = u
			st.s_bind[i3] = bind
			var ig: PackedInt64Array = ct.m_in_g[m]
			var iq: PackedInt64Array = ct.m_in_q[m]
			for k: int in ig.size():
				var need: int = JCMath.muldiv(JCMath.mulppm(iq[k], u), s_eff_lv[i3], PPM)
				req[ig[k]] = int(req.get(ig[k], 0)) + need
		var fill: Dictionary = {}
		for gk: Variant in req.keys():
			var g: int = int(gk)
			var need2: int = int(req[gk])
			var free: int = maxi(0, avail[g] - reserve_ess[g])
			if free < need2:
				free += _import(g, need2 - free, true)
			fill[g] = PPM if need2 <= 0 else mini(PPM, JCMath.ratio_ppm(free, need2))
			short_in[g] += maxi(0, need2 - free)
			in_fill[g] = mini(in_fill[g], int(fill[g]))
		for gi2: int in group.size():
			var i4: int = group[gi2]
			var m2: int = st.s_m[i4]
			var r2: int = st.s_region[i4]
			var u2: int = uplan[gi2]
			var ig2: PackedInt64Array = ct.m_in_g[m2]
			var iq2: PackedInt64Array = ct.m_in_q[m2]
			var sh2: PackedInt64Array = ct.m_in_share[m2]
			for k2: int in ig2.size():
				var f: int = int(fill.get(ig2[k2], PPM))
				# 主料（占投入价值四分之一以上）缺多少减多少；辅料只按它的份额减产
				if sh2[k2] < MAIN_INPUT_PPM:
					f = PPM - JCMath.mulppm(maxi(sh2[k2], MINOR_INPUT_FLOOR), PPM - f)
				var uf: int = JCMath.mulppm(uplan[gi2], f)
				if uf < u2:
					u2 = uf
					st.s_bind[i4] = B_INPUT
			s_ufin[i4] = u2
			for k3: int in ig2.size():
				var g2: int = ig2[k3]
				var use: int = JCMath.muldiv(JCMath.mulppm(iq2[k3], u2), s_eff_lv[i4], PPM)
				use = mini(use, avail[g2])
				avail[g2] -= use
				used_in[g2] += use
				var v: int = JCMath.value(use, st.price[g2])
				s_cost_in[i4] += v
				pool[g2] += v
			var og: PackedInt64Array = ct.m_out_g[m2]
			if og.is_empty():
				continue
			var oq: PackedInt64Array = ct.m_out_q[m2]
			var b: int = st.s_b[i4]
			var mult: int = PPM
			if ct.b_cat[b] == JCContent.CAT_FARM:
				mult = mods.mult_ppm("farm_yield", ct.r_id[r2])
				if ct.b_land[b] >= 0 and ct.b_land[b] <= 2:
					mult = JCMath.mulppm(mult, st.harvest[r2])
					if farm_lv[r2] > 0:
						var cov: int = mini(PPM, JCMath.ratio_ppm(irrig_cov[r2], farm_lv[r2] * PPM))
						var bonus: int = JCMath.mulppm(250_000, mods.mult_ppm("irrigation_eff"))
						mult = JCMath.mulppm(mult, PPM + JCMath.mulppm(bonus, cov))
			var pen: int = obsolete_penalty(b, m2, obs_per_year, obs_cap)
			if pen > 0:
				mult = JCMath.mulppm(mult, PPM - pen)
			if ct.g_id[og[0]] == "ships":
				mult = JCMath.mulppm(mult, mods.mult_ppm("ships_output"))
			if ct.g_id[og[0]] == "electricity":
				mult = JCMath.mulppm(mult, mods.mult_ppm("electricity_bonus"))
			var outs: PackedInt64Array = s_outq[i4]
			for k4: int in og.size():
				var q: int = JCMath.muldiv(JCMath.mulppm(JCMath.mulppm(oq[k4], u2), mult), s_eff_lv[i4], PPM)
				outs[k4] = q
				prod[og[k4]] += q
				avail[og[k4]] += q
			s_outq[i4] = outs
	for g3: int in G:
		st.f_prod[g3] = prod[g3]


## 本季在用生产方式的次序：只看在用方法之间的投入关系（耐用投入不算），有环时按迭代上限截断。
func _active_ranks() -> Dictionary:
	var ms: Dictionary = {}
	for i: int in S:
		if s_eff_lv[i] > 0:
			ms[st.s_m[i]] = true
	var producers: Dictionary = {}
	for m: Variant in ms.keys():
		var og: PackedInt64Array = ct.m_out_g[int(m)]
		for k: int in og.size():
			if not producers.has(og[k]):
				producers[og[k]] = []
			producers[og[k]].append(int(m))
	var rank: Dictionary = {}
	for m2: Variant in ms.keys():
		rank[int(m2)] = 0
	var limit: int = ms.size() + 1
	for it: int in limit:
		var changed: bool = false
		for m3: Variant in ms.keys():
			var mi: int = int(m3)
			var r: int = 0
			var ig: PackedInt64Array = ct.m_in_g[mi]
			for k2: int in ig.size():
				var g: int = ig[k2]
				if ct.g_durable[g] == 1 or not producers.has(g):
					continue
				for pm: Variant in producers[g]:
					if int(pm) != mi:
						r = maxi(r, int(rank[int(pm)]) + 1)
			if r != int(rank[mi]) and r <= limit:
				rank[mi] = r
				changed = true
		if not changed:
			break
	return rank


## 入不敷出：作坊与矿场按现价算，每开一份工的收入（扣物流）低于投入加工钱时减产：
## 亏一成开九成…亏四成以上只开两成。农田、牧场、渔场不减（农户照种）。
func _price_cap(i: int) -> int:
	var b: int = st.s_b[i]
	var cat: int = ct.b_cat[b]
	if cat != JCContent.CAT_WORKSHOP and cat != JCContent.CAT_MINE:
		return PPM
	var m: int = st.s_m[i]
	var r: int = st.s_region[i]
	var rev: int = 0
	var og: PackedInt64Array = ct.m_out_g[m]
	var oq: PackedInt64Array = ct.m_out_q[m]
	for k: int in og.size():
		rev += JCMath.value(oq[k], st.price[og[k]])
	rev -= JCMath.mulppm(rev, log_r[r])
	var cost: int = 0
	var ig: PackedInt64Array = ct.m_in_g[m]
	var iq: PackedInt64Array = ct.m_in_q[m]
	for k2: int in ig.size():
		if ct.g_durable[ig[k2]] == 1:
			continue
		cost += JCMath.value(iq[k2], st.price[ig[k2]])
	for c: int in C:
		cost += ct.m_labor[m * C + c] * st.wage[r * C + c]
	if cost <= 0 or rev >= cost:
		return PPM
	var loss: int = JCMath.ratio_ppm(cost - rev, cost)
	return clampi(PPM - loss * 2, 200_000, PPM)


## 销路上限：库存超过一季半的需求（耐用品三季）起逐步减产，到四季（耐用品六季）停工。
## 联产品按「最缺的那样」开工：只要有一样还缺，就照常开工（多出来的其余产品压价入库）。
func _demand_cap(m: int) -> int:
	var og: PackedInt64Array = ct.m_out_g[m]
	if og.is_empty():
		return PPM
	var best: int = 0
	for g: int in og:
		var d: int = prev_demand[g] if prev_demand.size() > g else 0
		if d <= 0:
			if stock0[g] <= 0:
				return PPM
			continue
		var lo: int = 3_000_000 if ct.g_durable[g] == 1 else 1_500_000
		var hi: int = lo * 2 + 1_000_000
		var glut: int = JCMath.ratio_ppm(stock0[g], d)
		if glut <= lo:
			return PPM
		best = maxi(best, JCMath.muldiv(maxi(0, hi - glut), PPM, hi - lo))
	return best


## 过时减产的速度与上限（ppm）：内容里给的是每年几个百分点与封顶。
func obs_rate() -> int:
	return int(ct.obsolescence.get("per_year_ppm", 15_000))


func obs_max() -> int:
	return int(ct.obsolescence.get("cap_ppm", 150_000))


## 过时：本国时代高于该方法时代、同建筑已有更新的可用方法时，每年少产几个百分点（封顶）。
func obsolete_penalty(b: int, m: int, per_year: int, cap: int) -> int:
	var me: int = ct.m_era[m]
	if st.era <= me:
		return 0
	var newer: bool = false
	for mm: int in ct.b_methods[b]:
		if ct.m_era[mm] > me and ct.m_era[mm] <= st.era and (ct.m_tech[mm] < 0 or st.t_done[ct.m_tech[mm]] == 1):
			newer = true
			break
	if not newer:
		return 0
	var since_q: int = st.q - st.era_q[mini(me + 1, st.era_q.size() - 1)]
	@warning_ignore("integer_division")
	return mini(cap, maxi(0, since_q) * per_year / 4)


# ── 进口 ────────────────────────────────────────────────────────────────
func _init_import_caps() -> void:
	_imp_left.clear()
	for p: int in ct.partners.size():
		if st.p_active[p] != 1 or st.p_rel[p] < -30:
			continue
		var offers: Dictionary = ct.partners[p].get("offers", {})
		for gk: Variant in offers.keys():
			var g: int = int(ct.gidx.get(String(gk), -1))
			if g < 0:
				continue
			var cap: int = int(offers[gk][1])
			if st.p_treaty[p] == 1:
				@warning_ignore("integer_division")
				cap = cap * 3 / 2
			_imp_left["%d:%d" % [p, g]] = cap


func import_price(p: int, g: int) -> int:
	var pd: Dictionary = ct.partners[p]
	var mult: int = int(pd.get("offers", {}).get(ct.g_id[g], [PPM, 0])[0])
	var mp: int = PPM + mods.delta_ppm("import_price", "partner:%s:%s" % [pd["id"], ct.g_id[g]])
	return JCMath.mulppm(JCMath.mulppm(ct.g_base[g], mult), maxi(mp, 100_000))


func _import(g: int, want: int, essential: bool) -> int:
	if want <= 0:
		return 0
	var got: int = 0
	var offers: Array = []
	for p: int in ct.partners.size():
		var key: String = "%d:%d" % [p, g]
		if int(_imp_left.get(key, 0)) > 0:
			offers.append([import_price(p, g), p])
	offers.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
	for o: Array in offers:
		if got >= want:
			break
		var ip: int = o[0]
		var p2: int = o[1]
		var landed: int = ip + JCMath.mulppm(ip, st.tax_customs_ppm)
		if not essential and landed > JCMath.mulppm(st.price[g], 1_250_000):
			continue
		var sea: bool = String(ct.partners[p2].get("route", "sea")) == "sea"
		var cap_left: int = (cap_sea - used_sea) if sea else (cap_land - used_land)
		if cap_left <= 0:
			continue
		var key2: String = "%d:%d" % [p2, g]
		var q: int = mini(want - got, int(_imp_left[key2]))
		q = mini(q, JCMath.qty_of(cap_left, ip))
		if q <= 0:
			continue
		var v: int = JCMath.value(q, ip)
		if sea:
			used_sea += v
		else:
			used_land += v
		_imp_left[key2] = int(_imp_left[key2]) - q
		imp_q[g] += q
		imp_cost[g] += v
		st.p_imp[p2] += v
		avail[g] += q
		got += q
	return got


# ── 分配：口粮与军需 → 营造与维护 → 其余居民需要 ─────────────────────────
func _allocate() -> void:
	for g: int in G:
		var total: int = want_tot[g]
		if total <= 0:
			continue
		if avail[g] < total:
			_import(g, total - avail[g], reserve_ess[g] > 0)
		var a: int = avail[g]
		var t1: int = reserve_ess[g]
		var f1: int = PPM if t1 <= 0 else mini(PPM, JCMath.ratio_ppm(a, t1))
		a -= JCMath.mulppm(t1, f1)
		var t2: int = firm_want[g]
		# 耐用品（农具、役畜、机械……）先留足下季生产要用的量，余下的才给营造与维护
		var a2: int = a
		if ct.g_durable[g] == 1:
			a2 = a - used_in[g]
		var f2: int = PPM if t2 <= 0 else mini(PPM, JCMath.ratio_ppm(maxi(a2, 0), t2))
		a -= JCMath.mulppm(t2, f2)
		var t3: int = total - t1 - t2
		var f3: int = PPM if t3 <= 0 else mini(PPM, JCMath.ratio_ppm(maxi(a, 0), t3))
		fill_ess[g] = f1
		fill_firm[g] = f2
		fill_non[g] = f3
		var used_g: int = 0
		gov_q[g] = JCMath.mulppm(gov_want[g], f1)
		used_g += gov_q[g]
		for k: int in R * C:
			var w: int = hh_want[k * G + g]
			if w <= 0:
				continue
			var e: int = ess_want[k * G + g]
			var got: int = JCMath.mulppm(e, f1) + JCMath.mulppm(w - e, f3)
			hh_got[k * G + g] = got
			hh_q[g] += got
			used_g += got
		# 维护与营造材料按到货比例（数量在结算时逐个出资方算）
		var firm_got: int = JCMath.mulppm(t2, f2)
		used_g += firm_got
		avail[g] = maxi(0, avail[g] - used_g)
		st.f_unmet[g] = maxi(0, total - used_g)
	for g2: int in G:
		st.f_unmet[g2] += short_in[g2]
	_substitute()
	_satisfaction()


## 口粮替代：缺某种粮时，用同类里还有余量的粮补上（按各组缺口比例分）。
func _substitute() -> void:
	for n: int in N:
		if ct.n_ess[n] != 1 or not ct.need_active(n, st.era):
			continue
		var gs: PackedInt64Array = ct.n_goods[n]
		var cv: PackedInt64Array = ct.n_conv[n]
		var gap: PackedInt64Array = JCMath.zeros(R * C)
		var gap_tot: int = 0
		for k: int in R * C:
			var got_units: int = 0
			for i: int in gs.size():
				got_units += JCMath.mulppm(hh_got[k * G + gs[i]], cv[i])
			var d: int = maxi(0, need_ref[k * N + n] - got_units)
			# 预算不够的部分不算缺口（买不起不是缺货）
			var afford: int = _afford_units(k, n)
			d = mini(d, afford)
			gap[k] = d
			gap_tot += d
		if gap_tot <= 0:
			continue
		for i2: int in gs.size():
			var g: int = gs[i2]
			if ct.g_era[g] > st.era or avail[g] <= 0 or cv[i2] <= 0:
				continue
			var need_q: int = JCMath.muldiv(gap_tot, PPM, cv[i2])
			var give: int = mini(need_q, avail[g])
			if give <= 0:
				continue
			var parts: PackedInt64Array = JCMath.split(give, gap)
			var given_units: int = 0
			for k2: int in R * C:
				if parts[k2] <= 0:
					continue
				hh_got[k2 * G + g] += parts[k2]
				hh_q[g] += parts[k2]
				var u: int = JCMath.mulppm(parts[k2], cv[i2])
				gap[k2] = maxi(0, gap[k2] - u)
				given_units += u
			avail[g] -= give
			gap_tot = maxi(0, gap_tot - given_units)
			if gap_tot <= 0:
				break


## 某组某项必需品按预算能买的需要单位。
func _afford_units(k: int, n: int) -> int:
	var gs: PackedInt64Array = ct.n_goods[n]
	var cv: PackedInt64Array = ct.n_conv[n]
	var units: int = 0
	for i: int in gs.size():
		units += JCMath.mulppm(ess_want[k * G + gs[i]], cv[i])
	return units


func _satisfaction() -> void:
	for k: int in R * C:
		for n: int in N:
			var idx: int = k * N + n
			var ref: int = need_ref[idx]
			if not ct.need_active(n, st.era) or ref <= 0:
				st.sat[idx] = PPM
				continue
			var gs: PackedInt64Array = ct.n_goods[n]
			var cv: PackedInt64Array = ct.n_conv[n]
			var units: int = 0
			for i: int in gs.size():
				var g: int = gs[i]
				var got: int = hh_got[k * G + g]
				if got <= 0:
					continue
				# 同一商品满足多项需要（瓷器既是器用也是奢侈）：按各项需要量的比例分摊
				var w_this: int = want_ng[idx * G + g]
				var w_all: int = 0
				for n2: int in N:
					w_all += want_ng[(k * N + n2) * G + g]
				if w_all <= 0:
					continue
				var part: int = JCMath.muldiv(got, w_this, w_all)
				units += JCMath.mulppm(part, cv[i])
			st.sat[idx] = mini(PPM, JCMath.ratio_ppm(units, ref))
	_comfort()


## 世人期待的日用倍数：只跟着外面的世界走——世界进入新时代后，四十年里从上一档涨到这一档。
## 本国自己先进了新时代，百姓不会因此更不满（日子本来就在变好）；落后于世界才会。
func expect_mult() -> int:
	var e: int = clampi(st.world_era, 1, 4)
	if e <= 1:
		return comfort_expect[1]
	var q0: int = st.world_era_q[e] if st.world_era_q.size() > e and st.world_era_q[e] >= 0 else st.q
	var ramp: int = clampi(JCMath.ratio_ppm(st.q - q0, 160), 0, PPM)
	return comfort_expect[e - 1] + JCMath.mulppm(comfort_expect[e] - comfort_expect[e - 1], ramp)


## 日用水平相对期待：实际买到的日用 ÷（开局篮子 × 本时代期待倍数）下该买到的量，按权重平均。
func _comfort() -> void:
	var em: int = expect_mult()
	for k: int in R * C:
		var c: int = k % C
		var ref_b: int = JCMath.mulppm(basket0[k], em)
		var acc: int = 0
		var wsum: int = 0
		for n: int in N:
			if ct.n_ess[n] == 1 or not ct.need_active(n, st.era):
				continue
			var full: int = JCMath.mulppm(st.pop[k] * ct.n_qty[n * C + c], need_mult(n, ref_b))
			if full <= 0:
				continue
			var idx: int = k * N + n
			var got: int = JCMath.mulppm(need_ref[idx], st.sat[idx])
			acc += ct.n_weight[n] * mini(2 * PPM, JCMath.ratio_ppm(got, full))
			wsum += ct.n_weight[n]
		@warning_ignore("integer_division")
		st.comfort[k] = PPM if wsum <= 0 else acc / wsum


# ── 出口 ────────────────────────────────────────────────────────────────
func partner_era(p: int) -> int:
	@warning_ignore("integer_division")
	return clampi(st.p_dev[p] / PPM, 1, 4)


func export_price(p: int, g: int) -> int:
	var pd: Dictionary = ct.partners[p]
	var mult: int = int(pd.get("wants", {}).get(ct.g_id[g], [PPM, 0])[0])
	var sea: bool = String(pd.get("route", "sea")) == "sea"
	var m: int = PPM + mods.delta_ppm("export_price", "all") \
			+ mods.delta_ppm("export_price", "partner:%s:%s" % [pd["id"], ct.g_id[g]])
	if sea:
		m += mods.delta_ppm("export_price", "sea")
	m -= maxi(0, partner_era(p) - st.era) * 100_000
	var ge: int = ct.g_era[g]
	if ge >= 2 and ge < st.led.size() and st.led[ge] == 1:
		var bonus: int = 200_000
		if st.world_era_q[ge] >= 0:
			bonus = maxi(0, 200_000 - (st.q - st.world_era_q[ge]) * 2500)
		m += bonus
	return JCMath.mulppm(JCMath.mulppm(ct.g_base[g], mult), maxi(m, 200_000))


func _export() -> void:
	var offers: Array = []
	for p: int in ct.partners.size():
		if st.p_active[p] != 1 or st.p_rel[p] < -30:
			continue
		var wants: Dictionary = ct.partners[p].get("wants", {})
		for gk: Variant in wants.keys():
			var g: int = int(ct.gidx.get(String(gk), -1))
			if g < 0:
				continue
			var cap: int = int(wants[gk][1])
			cap = JCMath.mulppm(cap, clampi(700_000 + st.p_rel[p] * 6000, 400_000, 1_300_000))
			if st.p_treaty[p] == 1:
				@warning_ignore("integer_division")
				cap = cap * 3 / 2
			offers.append([export_price(p, g), p, g, cap])
	offers.sort_custom(func(a: Array, b: Array) -> bool:
		return a[0] > b[0] or (a[0] == b[0] and (a[1] < b[1] or (a[1] == b[1] and a[2] < b[2]))))
	for o: Array in offers:
		var price: int = o[0]
		var p2: int = o[1]
		var g2: int = o[2]
		var cap2: int = o[3]
		# 只有卖价不低于国内价的八成才出口；留四成作为下季库存
		if price < JCMath.mulppm(st.price[g2], 800_000):
			continue
		var dom: int = hh_q[g2] + used_in[g2] + gov_q[g2] + JCMath.mulppm(firm_want[g2], fill_firm[g2])
		var spare: int = avail[g2] - JCMath.mulppm(dom, 400_000)
		if spare <= 0:
			continue
		var sea: bool = String(ct.partners[p2].get("route", "sea")) == "sea"
		var cap_left: int = (cap_sea - used_sea) if sea else (cap_land - used_land)
		if cap_left <= 0:
			continue
		var key: String = "%d:%d" % [p2, g2]
		var q: int = mini(spare, cap2 - int(_exp_pg.get(key, 0)))
		q = mini(q, JCMath.qty_of(cap_left, price))
		if q <= 0:
			continue
		var v: int = JCMath.value(q, price)
		if sea:
			used_sea += v
		else:
			used_land += v
		avail[g2] -= q
		exp_q[g2] += q
		exp_v[g2] += v
		st.p_exp[p2] += v
		_exp_pg[key] = int(_exp_pg.get(key, 0)) + q


# ── 资金结算 ────────────────────────────────────────────────────────────
func _settle() -> void:
	var sc: Dictionary = ct.scenario.get("gov", {})
	var port_fee: int = int(sc.get("port_fee_ppm", 30000))
	var coll: int = st.coll_eff
	var salt: int = int(ct.gidx.get("salt", -1))
	var salt_ex: int = JCMath.mulppm(st.tax_salt_li, mods.mult_ppm("salt_markup"))
	# 1) 居民付款
	for k: int in R * C:
		var r: int = k / C
		var pay: int = 0
		for g: int in G:
			var q: int = hh_got[k * G + g]
			if q <= 0:
				continue
			var v: int = JCMath.value(q, st.price[g])
			pool[g] += v
			var mg: int = 0 if (k % C == CL_P and ct.g_own[g] == 1) else JCMath.mulppm(v, margin_r[r])
			margin_pool[r] += mg
			pay += v + mg
			if g == salt:
				var ex: int = JCMath.value(q, salt_ex)
				var got_tax: int = mini(ex, JCMath.mulppm(JCMath.mulppm(ex, coll), mods.mult_ppm("salt_tax_eff")))
				st.rev[JCState.REV_SALT] += got_tax
				st.treasury += got_tax
				_pay(_salt_region(), CL_M, ex - got_tax)
				pay += ex
		spent[k] = pay
		st.savings[k] -= pay
		st.spend[k] = pay
	# 2) 军粮军衣
	var army_goods: int = 0
	for g2: int in G:
		if gov_q[g2] > 0:
			var v2: int = JCMath.value(gov_q[g2], st.price[g2])
			pool[g2] += v2
			army_goods += v2
	_gov_pay(JCState.EXP_ARMY, army_goods)
	# 3) 维护材料：各堆按到货量付
	for i: int in S:
		var mq: PackedInt64Array = s_maint_q[i]
		for k2: int in cur_maint_g.size():
			var g3: int = cur_maint_g[k2]
			var q3: int = JCMath.mulppm(mq[k2], fill_firm[g3])
			if q3 <= 0:
				continue
			var v3: int = JCMath.value(q3, st.price[g3])
			pool[g3] += v3
			s_cost_maint[i] += v3
			firm_q[g3] += q3
	# 4) 营造：出资方付材料（按到货量）与工钱（按工匠到位率）；缺料按缺的价值份额放慢
	for j: int in job_value.size():
		var r4: int = job_region[j]
		var mat_v: int = 0
		var want_v: int = 0
		var arr: PackedInt64Array = job_mat_q[j]
		for kk: int in cur_build_g.size():
			var g4: int = cur_build_g[kk]
			if arr[kk] <= 0:
				continue
			var f: int = fill_firm[g4]
			want_v += JCMath.value(arr[kk], st.price[g4])
			var q4: int = JCMath.mulppm(arr[kk], f)
			var v4: int = JCMath.value(q4, st.price[g4])
			pool[g4] += v4
			mat_v += v4
			firm_q[g4] += q4
		var mat_fill: int = JCMath.ratio_ppm(mat_v, want_v)
		var lf: int = lab_fill[r4 * C + CL_A]
		var wage_v: int = JCMath.mulppm(JCMath.mulppm(job_value[j], BUILD_WAGE_PPM), lf)
		var total: int = mat_v + wage_v
		if job_funder[j] == 0:
			_gov_pay(JCState.EXP_BUILD, total)
		else:
			# 民间出资：全国商贾与士绅按各自储蓄的比例共同出资
			_private_pay(total)
		_pay(r4, CL_A, wage_v, SRC_WAGE)
		lab_used[r4 * C + CL_A] += JCMath.mulppm(JCMath.mulppm(job_value[j], BUILD_WAGE_PPM), lf) / maxi(1, st.wage[r4 * C + CL_A])
		job_fill[j] = mini(mat_fill, lf)
	# 5) 出口：外面按出口价付；出口关税一半、港口费从货款里出
	var cus_eff: int = mini(PPM, JCMath.mulppm(JCMath.mulppm(coll, mods.mult_ppm("customs_eff")), PPM + customs_bonus))
	var tariff: int = JCMath.mulppm(st.tax_customs_ppm, mods.mult_ppm("tariff"))
	var sea_share: int = JCMath.ratio_ppm(used_sea, maxi(used_sea + used_land, 1), 0)
	for g5: int in G:
		if exp_v[g5] <= 0:
			continue
		pool[g5] += exp_v[g5]
		st.silver += exp_v[g5]
		@warning_ignore("integer_division")
		var duty: int = JCMath.mulppm(JCMath.mulppm(exp_v[g5], tariff), cus_eff) / 2
		var fee: int = JCMath.mulppm(exp_v[g5], port_fee)
		pool[g5] -= duty + fee
		st.rev[JCState.REV_CUSTOMS] += duty
		st.treasury += duty
		var fs: int = JCMath.mulppm(fee, sea_share)
		port_pool += fs
		cara_pool += fee - fs
	# 6) 进口商：从货款池取回进口货的卖价，付进口成本、关税、港口费，差价归口岸商贾
	for g6: int in G:
		if imp_q[g6] <= 0:
			continue
		var sold: int = mini(imp_q[g6], hh_q[g6] + used_in[g6] + gov_q[g6] + firm_q[g6])
		var rev_imp: int = mini(JCMath.value(sold, st.price[g6]), pool[g6])
		pool[g6] -= rev_imp
		var cost: int = imp_cost[g6]
		var duty2: int = JCMath.mulppm(JCMath.mulppm(cost, tariff), cus_eff)
		var fee2: int = JCMath.mulppm(cost, port_fee)
		st.silver -= cost
		st.rev[JCState.REV_CUSTOMS] += duty2
		st.treasury += duty2
		var fs2: int = JCMath.mulppm(fee2, sea_share)
		port_pool += fs2
		cara_pool += fee2 - fs2
		_pay(_port_region(), CL_M, rev_imp - cost - duty2 - fee2)
		st.f_imp[g6] = imp_q[g6]
	# 7) 货款池按本季产量分给各生产堆；本季没产的按产能分；完全没有生产者的归首府商贾
	for g7: int in G:
		if pool[g7] <= 0:
			continue
		var weights: PackedInt64Array = JCMath.zeros(S)
		var any: bool = false
		for i2: int in S:
			var og: PackedInt64Array = ct.m_out_g[st.s_m[i2]]
			for k3: int in og.size():
				if og[k3] != g7:
					continue
				var outs: PackedInt64Array = s_outq[i2]
				var w: int = outs[k3] if prod[g7] > 0 else st.s_level[i2]
				if w > 0:
					weights[i2] += w
					any = true
		if not any:
			_pay(_capital_region(), CL_M, pool[g7])
			continue
		var parts: PackedInt64Array = JCMath.split(pool[g7], weights)
		for i3: int in S:
			s_rev[i3] += parts[i3]
	# 8) 物流费：各生产堆把收入的物流费率付给本地区运费池
	for i5: int in S:
		if s_rev[i5] <= 0 or _is_facility(st.s_b[i5]):
			continue
		var r5: int = st.s_region[i5]
		var fee3: int = JCMath.mulppm(s_rev[i5], log_r[r5])
		fee_pool[r5] += fee3
		s_rev[i5] -= fee3
	# 9) 服务业：集市分零售加价池，车马行分运费池，港口与商栈分贸易费
	var market_w: PackedInt64Array = JCMath.zeros(R)
	var carrier_w: PackedInt64Array = JCMath.zeros(R)
	var port_w: int = 0
	var cara_w: int = 0
	for i6: int in S:
		var w6: int = JCMath.mulppm(s_eff_lv[i6], s_lfill[i6])
		match ct.b_id[st.s_b[i6]]:
			"market":
				market_w[st.s_region[i6]] += w6
			"carrier":
				carrier_w[st.s_region[i6]] += w6
			"port":
				port_w += w6
			"caravanserai":
				cara_w += w6
	var given_m: PackedInt64Array = JCMath.zeros(R)
	var given_c: PackedInt64Array = JCMath.zeros(R)
	var given_p: int = 0
	var given_cara: int = 0
	for i7: int in S:
		var w7: int = JCMath.mulppm(s_eff_lv[i7], s_lfill[i7])
		if w7 <= 0:
			continue
		var r7: int = st.s_region[i7]
		match ct.b_id[st.s_b[i7]]:
			"market":
				var a: int = JCMath.muldiv(margin_pool[r7], w7, market_w[r7])
				s_rev[i7] += a
				given_m[r7] += a
			"carrier":
				var a2: int = JCMath.muldiv(fee_pool[r7], w7, carrier_w[r7])
				s_rev[i7] += a2
				given_c[r7] += a2
			"port":
				var a3: int = JCMath.muldiv(port_pool, w7, port_w)
				s_rev[i7] += a3
				given_p += a3
			"caravanserai":
				var a4: int = JCMath.muldiv(cara_pool, w7, cara_w)
				s_rev[i7] += a4
				given_cara += a4
	# 分剩的零头与没有设施的地区：加价归本地区商贾，运费归本地区农户（挑夫），贸易费归口岸商贾
	for r8: int in R:
		_pay(r8, CL_M, margin_pool[r8] - given_m[r8])
		_pay(r8, CL_P, fee_pool[r8] - given_c[r8])
	_pay(_port_region(), CL_M, port_pool - given_p + cara_pool - given_cara)
	# 10) 各堆核算：工钱、税、利润
	var land_eff: int = JCMath.mulppm(coll, mods.mult_ppm("land_tax_eff"))
	var com_eff: int = JCMath.mulppm(coll, mods.mult_ppm("tax_eff"))
	for i8: int in S:
		_settle_stack(i8, ct.r_rent[st.s_region[i8]], land_eff, com_eff)
	# 11) 国家的其余开支
	_gov_other(sc)
	# 12) 收入入账
	for k9: int in R * C:
		st.savings[k9] += inc[k9]
		st.income[k9] = inc[k9]
		st.employed[k9] = lab_used[k9]
		# 职位 = 在岗 + 真实空缺（给阶层流动看）；营造的工匠需求算在 lab_used 里
		st.jobs[k9] = lab_used[k9] + vacancy[k9]


func _settle_stack(i: int, rent_share: int, land_eff: int, com_eff: int) -> void:
	var b: int = st.s_b[i]
	var cat: int = ct.b_cat[b]
	var m: int = st.s_m[i]
	var r: int = st.s_region[i]
	var facility: bool = _is_facility(b)
	# 在岗人数：生产类随开工率，设施按人手到位率
	var u: int = s_lfill[i] if facility else s_ufin[i]
	var wages: PackedInt64Array = JCMath.zeros(C)
	var wage_tot: int = 0
	for c: int in C:
		var persons: int = JCMath.mulppm(labor_need(i, c), u)
		# 真实空缺：只有卡在人手上的，缺的那部分才算招工（缺原料、没销路的空位不算）
		if not facility and st.s_bind[i] == B_LABOR:
			vacancy[r * C + c] += maxi(0, labor_need(i, c) - persons)
		if persons <= 0:
			continue
		lab_used[r * C + c] += persons
		wages[c] = persons * st.wage[r * C + c]
		wage_tot += wages[c]
	var rev: int = s_rev[i]
	var tax: int = 0
	if cat == JCContent.CAT_FARM and ct.b_land[b] >= 0 and ct.b_land[b] <= 2:
		# 田赋按本季产量折常年价（基准价）征收，不随市价涨落：丰年谷贱伤农，国库却稳；歉收时产量少、赋也少
		var base_v: int = 0
		var outs: PackedInt64Array = s_outq[i]
		var og: PackedInt64Array = ct.m_out_g[m]
		for k: int in og.size():
			base_v += JCMath.value(outs[k], ct.g_base[og[k]])
		base_v -= JCMath.mulppm(base_v, log_r[r])
		tax = JCMath.mulppm(JCMath.mulppm(JCMath.mulppm(base_v, st.tax_land_ppm), PPM - st.hidden[r]), land_eff)
		st.rev[JCState.REV_LAND] += tax
	elif (cat == JCContent.CAT_WORKSHOP or cat == JCContent.CAT_MINE) and rev > 0:
		tax = JCMath.mulppm(JCMath.mulppm(rev, st.tax_commerce_ppm), com_eff)
		st.rev[JCState.REV_COMMERCE] += tax
	st.treasury += tax
	var profit: int = rev - wage_tot - s_cost_in[i] - s_cost_maint[i] - tax
	var short: int = 0
	if st.s_owner[i] == JCContent.OWNER_GOV:
		if profit >= 0:
			st.rev[JCState.REV_STATE] += profit
			st.treasury += profit
		else:
			var line: int = _exp_line_of(b) if facility else JCState.EXP_STATE_LOSS
			_gov_pay(line, -profit)
	else:
		if profit >= 0:
			if cat == JCContent.CAT_FARM:
				var rent: int = JCMath.mulppm(profit, rent_share)
				_pay(r, CL_G, rent)
				_pay(r, CL_P, profit - rent)
			else:
				_pay(r, CL_M, profit)
		else:
			var owner_c: int = CL_G if cat == JCContent.CAT_FARM else CL_M
			var k: int = r * C + owner_c
			var can: int = maxi(0, st.savings[k] + inc[k])
			var cover: int = mini(-profit, can)
			if cover < -profit:
				short = mini(wage_tot, -profit - cover)
			# 东家的积蓄和欠下的工钱都填不上的亏空：照样记在东家账上（储蓄成负），
			# 季末由同地区其他人家垫付、再不够由国库兜底（_fix_negatives），一厘也不凭空出现
			var rest: int = -profit - cover - short
			_pay(r, owner_c, -(cover + rest), SRC_LOSS)
	st.s_profit[i] = profit
	if profit < 0 and st.s_owner[i] != JCContent.OWNER_GOV and not facility:
		st.s_loss[i] += 1
	elif profit >= 0:
		st.s_loss[i] = 0
	# 工钱：欠薪时少发 short，按各阶层工钱比例精确拆分
	var parts: PackedInt64Array = JCMath.split(wage_tot - short, wages)
	for c2: int in C:
		_pay(r, c2, parts[c2], SRC_WAGE)
	st.s_u[i] = s_ufin[i]


## 国库付款：一律照付；国库为负由季末强借补上（见 _fix_negatives）。
func _gov_pay(line: int, amount: int) -> int:
	if amount <= 0:
		return 0
	st.treasury -= amount
	st.exp[line] += amount
	return amount


## 民间出资：按各地区商贾、士绅储蓄的比例分摊（记为他们本季收入的减项）。
func _private_pay(total: int) -> void:
	if total <= 0:
		return
	var w: PackedInt64Array = JCMath.zeros(R * 2)
	for r: int in R:
		w[r * 2] = maxi(0, st.savings[r * C + CL_M] + inc[r * C + CL_M])
		w[r * 2 + 1] = maxi(0, st.savings[r * C + CL_G] + inc[r * C + CL_G])
	var parts: PackedInt64Array = JCMath.split(total, w)
	for r2: int in R:
		_pay(r2, CL_M, -parts[r2 * 2], SRC_LOSS)
		_pay(r2, CL_G, -parts[r2 * 2 + 1], SRC_LOSS)


func _pay(r: int, c: int, amount: int, src: int = SRC_PROFIT) -> void:
	if amount != 0:
		inc[r * C + c] += amount
		inc_src[(r * C + c) * SRC_N + src] += amount


func _capital_region() -> int:
	for r: int in R:
		if ct.r_capital[r] == 1:
			return r
	return 0


func _port_region() -> int:
	for r: int in R:
		if ct.r_coast[r] == 1:
			return r
	return _capital_region()


func _salt_region() -> int:
	var r: int = int(ct.ridx.get("haijia", -1))
	return r if r >= 0 else _port_region()


func _gov_other(sc: Dictionary) -> void:
	var fund: int = st.gov_fund
	var army: int = JCMath.mulppm(mini(1_500_000, st.budget[JCState.BUD_ARMY]), fund)
	var soldiers: int = JCMath.mulppm(st.soldiers, mini(PPM, army))
	var pay_all: int = soldiers * int(sc.get("soldier_wage_li", 1800))
	_spread_class(CL_P, _gov_pay(JCState.EXP_ARMY, pay_all))
	for r0: int in R:
		lab_used[r0 * C + CL_P] += soldier_r[r0] if soldier_r.size() > r0 else 0
	var court: int = JCMath.mulppm(JCMath.mulppm(int(sc.get("court_li", 0)), st.budget[JCState.BUD_COURT]), fund)
	_pay(_capital_region(), CL_G, _gov_pay(JCState.EXP_COURT, court), SRC_GOV)
	if st.debt > 0:
		var rate: int = JCMath.mulppm(st.debt_rate_ppm, mods.mult_ppm("interest_rate"))
		_pay(_capital_region(), CL_M, _gov_pay(JCState.EXP_INTEREST, JCMath.mulppm(st.debt, rate)), SRC_GOV)
	# 赈济：口粮满足度低于 85% 的组，按缺口价值补贴
	var relief_cap: int = JCMath.mulppm(JCMath.mulppm(int(sc.get("relief_li", 0)), st.budget[JCState.BUD_RELIEF]), fund)
	if mods.flag("relief"):
		relief_cap *= 4
	relief_cap = JCMath.mulppm(relief_cap, mods.mult_ppm("relief_eff"))
	var staple: int = int(ct.nidx.get("staple", 0))
	var gaps: PackedInt64Array = JCMath.zeros(R * C)
	var gap_tot: int = 0
	for k: int in R * C:
		var s: int = st.sat[k * N + staple]
		if s < 850_000 and st.pop[k] > 0:
			var gap: int = JCMath.mulppm(_need_cost(staple, k / C, k % C, st.pop[k], PPM), 850_000 - s)
			gaps[k] = gap
			gap_tot += gap
	if gap_tot > 0 and relief_cap > 0:
		var give: int = _gov_pay(JCState.EXP_RELIEF, mini(gap_tot, relief_cap))
		var parts: PackedInt64Array = JCMath.split(give, gaps)
		for k2: int in R * C:
			inc[k2] += parts[k2]
			inc_src[k2 * SRC_N + SRC_GOV] += parts[k2]
	# 政令的每季开支（办事的吏员与士绅）
	for d: int in ct.decrees.size():
		if st.d_level[d] > 0:
			var cq: int = int(ct.decrees[d].get("cost_q_li", 0))
			if cq > 0:
				_spread_class(CL_G, _gov_pay(JCState.EXP_DECREE, JCMath.mulppm(cq, fund)))


func _spread_class(c: int, amount: int) -> void:
	if amount <= 0:
		return
	var w: PackedInt64Array = JCMath.zeros(R)
	for r: int in R:
		w[r] = st.pop[r * C + c]
	var parts: PackedInt64Array = JCMath.split(amount, w)
	for r2: int in R:
		inc[r2 * C + c] += parts[r2]
		inc_src[(r2 * C + c) * SRC_N + SRC_GOV] += parts[r2]


# ── 入库与损耗 ──────────────────────────────────────────────────────────
func _stock() -> void:
	for g: int in G:
		var s: int = maxi(0, avail[g])
		s -= JCMath.mulppm(s, ct.g_perish[g])
		st.stock[g] = s
		st.f_hh[g] = hh_q[g]
		st.f_use[g] = used_in[g]
		st.f_gov[g] = gov_q[g] + firm_q[g]
		st.f_exp[g] = exp_q[g]
		st.f_demand[g] = want_tot[g] + used_in[g] + exp_q[g]


# ── 价格 ────────────────────────────────────────────────────────────────
func _prices() -> void:
	var stable: bool = mods.flag("price_stability")
	var lvl: int = PPM + mods.delta_ppm("price_level")
	for g: int in G:
		var flow_in: int = prod[g] + imp_q[g]
		var demand: int = want_tot[g] + used_in[g] + exp_q[g]
		# 库存目标：可储存的商品留四分之一季的需求，易腐的不留；库存偏离只按四分之一算进紧张度
		var tgt_stock: int = 0 if ct.g_perish[g] >= 200_000 else JCMath.mulppm(demand, 250_000)
		@warning_ignore("integer_division")
		var excess: int = demand - flow_in - (stock0[g] - tgt_stock) / 4
		var target: int = 0
		var big: int = maxi(demand, flow_in)
		if big > 0:
			var tight: int = JCMath.muldiv(excess, PPM, big)
			target = clampi(JCMath.mulppm(tight, 1_200_000), -500_000, 1_500_000)
		st.premium[g] = JCMath.approach(st.premium[g], target, 150_000 if stable else 250_000)
		st.price[g] = maxi(1, JCMath.mulppm(JCMath.mulppm(ct.g_base[g], PPM + st.premium[g]), lvl))


# ── 工钱 ────────────────────────────────────────────────────────────────
func _wages() -> void:
	var ri: int = int(ct.gidx.get("rice", 0))
	var gr: int = int(ct.gidx.get("grain", 0))
	@warning_ignore("integer_division")
	var idx: int = (JCMath.ratio_ppm(st.price[ri], ct.g_base[ri]) + JCMath.ratio_ppm(st.price[gr], ct.g_base[gr])) / 2
	@warning_ignore("integer_division")
	var index_part: int = PPM + (idx - PPM) / 2
	for r: int in R:
		for c: int in C:
			var k: int = r * C + c
			var tight: int = 0
			if lab_sup[k] > 0:
				tight = clampi(JCMath.muldiv(lab_dem[k] - lab_sup[k], PPM, lab_sup[k]), -PPM, PPM)
			if c == CL_G and tight < 0:
				tight = 0
			var target_mult: int = clampi(PPM + JCMath.mulppm(tight, 800_000), 600_000, 2_000_000)
			var target: int = JCMath.mulppm(JCMath.mulppm(ct.c_wage[c], target_mult), index_part)
			st.wage[k] = maxi(1, JCMath.approach(st.wage[k], target, 80_000))


## 季末之后的开支（事件、粮仓）使国库为负时：向商贾、士绅借，记为债务（不算欠饷）。
func cover_treasury() -> void:
	if st.treasury >= 0:
		return
	# 先向商贾、士绅借，再摊派到工匠、农户（都记为国债）；只要民间还有一厘就不让国库为负
	for c: int in [CL_M, CL_G, CL_A, CL_P]:
		var need: int = -st.treasury
		if need <= 0:
			break
		var w: PackedInt64Array = JCMath.zeros(R)
		var have: int = 0
		for r: int in R:
			w[r] = maxi(0, st.savings[r * C + c])
			have += w[r]
		var take: int = mini(need, have)
		var parts: PackedInt64Array = JCMath.split(take, w)
		for r2: int in R:
			st.savings[r2 * C + c] -= parts[r2]
		st.treasury += take
		st.debt += take
		if c == CL_A or c == CL_P:
			st.arrears += take


# ── 负数处理：居民赊账、国库强借 ────────────────────────────────────────
func _fix_negatives() -> void:
	for k: int in R * C:
		if st.savings[k] >= 0:
			continue
		# 赊账：本地区商贾（不够再找士绅）垫付，记为他们的损失
		var need: int = -st.savings[k]
		var r: int = k / C
		for c: int in [CL_M, CL_G, CL_A, CL_P]:
			var kk: int = r * C + c
			if kk == k or need <= 0:
				continue
			var take: int = mini(need, maxi(0, st.savings[kk]))
			st.savings[kk] -= take
			need -= take
		st.savings[k] = -need
		if need > 0:
			# 全地区都没钱了：由国库垫付
			st.treasury -= need
			st.savings[k] = 0
	if st.treasury < 0:
		# 国库亏空：向各地商贾强借，记为债务并算作欠付
		var need2: int = -st.treasury
		var w: PackedInt64Array = JCMath.zeros(R)
		var avail_m: int = 0
		for r2: int in R:
			w[r2] = maxi(0, st.savings[r2 * C + CL_M])
			avail_m += w[r2]
		var take2: int = mini(need2, avail_m)
		var parts: PackedInt64Array = JCMath.split(take2, w)
		for r3: int in R:
			st.savings[r3 * C + CL_M] -= parts[r3]
		st.treasury += take2
		st.debt += take2
		st.arrears += need2
		if st.treasury < 0:
			# 连商贾也借不到：再向士绅借
			var need3: int = -st.treasury
			var w2: PackedInt64Array = JCMath.zeros(R)
			var avail_g: int = 0
			for r4: int in R:
				w2[r4] = maxi(0, st.savings[r4 * C + CL_G])
				avail_g += w2[r4]
			var take3: int = mini(need3, avail_g)
			var parts2: PackedInt64Array = JCMath.split(take3, w2)
			for r5: int in R:
				st.savings[r5 * C + CL_G] -= parts2[r5]
			st.treasury += take3
			st.debt += take3


# ── 摘要 ────────────────────────────────────────────────────────────────
func _summary() -> void:
	var gdp: int = 0
	var by_sector: PackedInt64Array = JCMath.zeros(4)
	for i: int in S:
		var va: int = s_rev[i] - s_cost_in[i] - s_cost_maint[i]
		if _is_facility(st.s_b[i]) and st.s_owner[i] == JCContent.OWNER_GOV:
			va = maxi(0, va)
		gdp += va
		by_sector[ct.b_sector[st.s_b[i]]] += va
	var sup: int = 0
	var used: int = 0
	for r: int in R:
		for c: int in C:
			if c == CL_G:
				continue
			sup += lab_sup[r * C + c]
			used += mini(lab_used[r * C + c], lab_sup[r * C + c])
	summary = {
		"gdp": gdp, "sector_va": Array(by_sector), "unemp_ppm": PPM - JCMath.ratio_ppm(used, sup),
		"sea_cap": cap_sea, "sea_used": used_sea, "land_cap": cap_land, "land_used": used_land,
		"exports": JCMath.sum(exp_v), "imports": JCMath.sum(imp_cost), "retail": JCMath.sum(spent),
		"research_bld": research_bld,
	}
