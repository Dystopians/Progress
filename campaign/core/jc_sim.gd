## v2 每季结算（docs/57）。一季的顺序：
##   命令 → 政令期限与限时修正 → 修正汇总 → 年成 → 国家开支到位率 → 常平仓与垦荒
##   → 营造登记 → 经济结算 → 营造推进 → 常平仓收储、捐纳、所得税 → 治理与征收率
##   → 人口、识字、生活与民怨 → 研究、时代、世界进程 → 民间投资与收缩 → 事件 → 危机 → 记录
## 每季末核对：货币守恒（Σ 储蓄 + 国库 == 开局货币 + 累计白银净流入）、人口与库存非负。
class_name JCSim
extends RefCounted

const PPM: int = 1_000_000

var ct: JCContent
var st: JCState
var mods: JCMods = JCMods.new()
var rng: JCRng = JCRng.new()
var econ: JCEconomy = JCEconomy.new()
var inv: JCInvest = JCInvest.new()
var soc: JCSociety = JCSociety.new()
var world: JCWorld = JCWorld.new()
var cmd: JCCommands = JCCommands.new()
var last_results: Array = []
var last_error: String = ""


func _init(p_ct: JCContent, p_st: JCState) -> void:
	ct = p_ct
	st = p_st
	_wire()


func _wire() -> void:
	econ.setup(ct, st, mods)
	inv.setup(ct, st, mods, econ)
	soc.setup(ct, st, mods, econ, rng)
	world.setup(ct, st, mods, econ, soc, rng)
	cmd.setup(ct, st, mods, inv, world)
	mods.rebuild(st, ct)


## 换一个状态对象（读档后）。
func rebind(p_st: JCState) -> void:
	st = p_st
	_wire()
	rng.state = st.rng_state


# ════════════════════════════ 开局 ════════════════════════════════════════
static func new_state(ct: JCContent, seed: int) -> JCState:
	var st: JCState = JCState.new()
	var sc: Dictionary = ct.scenario
	var gov: Dictionary = sc.get("gov", {})
	var R: int = ct.r_n
	var C: int = ct.c_n
	var G: int = ct.g_n
	var N: int = ct.n_n
	st.seed = seed
	st.start_year = int(sc.get("start_year", 1600))
	st.content_hash = ct.content_hash
	var rng: JCRng = JCRng.seeded(seed)
	st.rng_state = rng.state
	st.land = ct.r_land.duplicate()
	st.hidden = JCMath.filled(R, int(gov.get("hidden_land_ppm", 120000)))
	st.literacy = JCMath.filled(R, int(gov.get("literacy_ppm", 80000)))
	st.harvest = JCMath.filled(R, PPM)
	st.flood = JCMath.zeros(R)
	st.logistics = ct.r_logistics.duplicate()
	st.pop = ct.r_pop.duplicate()
	st.savings = JCMath.zeros(R * C)
	st.basket = JCMath.filled(R * C, PPM)
	var sv: Dictionary = sc.get("savings_li", {})
	var bk: Dictionary = sc.get("basket_ppm", {})
	for r: int in R:
		for c: int in C:
			var key: String = ct.r_id[r] + ":" + ct.c_id[c]
			st.savings[r * C + c] = int(sv.get(key, 0))
			st.basket[r * C + c] = int(bk.get(key, PPM))
	st.income = JCMath.zeros(R * C)
	st.spend = JCMath.zeros(R * C)
	st.employed = JCMath.zeros(R * C)
	st.jobs = JCMath.zeros(R * C)
	st.wage = JCMath.zeros(R * C)
	for r2: int in R:
		for c2: int in C:
			st.wage[r2 * C + c2] = ct.c_wage[c2]
	st.living = JCMath.filled(R * C, PPM)
	st.comfort = JCMath.filled(R * C, PPM)
	st.unrest = JCMath.filled(R * C, 30_000)
	st.sat = JCMath.filled(R * C * N, PPM)
	st.support = JCMath.filled(C, 600_000)
	# 建筑堆
	for s: Dictionary in sc.get("stacks", []):
		var b: int = int(ct.bidx[String(s["building"])])
		var m: int = int(ct.midx[String(s["method"])])
		var r3: int = int(ct.ridx[String(s["region"])])
		var owner: int = JCContent.OWNER_GOV if String(s.get("owner", "private")) == "gov" else JCContent.OWNER_PRIVATE
		st.add_stack(r3, b, m, owner, int(s["level"]), JCState.ST_ACTIVE, 0, 0)
	# 商品
	st.price = ct.g_base.duplicate()
	st.premium = JCMath.zeros(G)
	st.stock = JCMath.zeros(G)
	for f: String in ["f_prod", "f_hh", "f_use", "f_gov", "f_exp", "f_imp", "f_unmet", "f_demand"]:
		st.set(f, JCMath.zeros(G))
	# 国家
	st.treasury = int(gov.get("treasury_li", 0))
	st.tax_land_ppm = int(gov.get("land_tax_ppm", 90000))
	st.tax_salt_li = int(gov.get("salt_tax_li", 600))
	st.tax_commerce_ppm = int(gov.get("commerce_tax_ppm", 20000))
	st.tax_customs_ppm = int(gov.get("customs_ppm", 50000))
	st.debt_rate_ppm = 30_000
	st.budget = JCMath.filled(JCState.BUD_N, PPM)
	st.soldiers = int(gov.get("soldiers", 0))
	st.rev = JCMath.zeros(JCState.REV_N)
	st.exp = JCMath.zeros(JCState.EXP_N)
	# 政令
	var D: int = ct.decrees.size()
	st.d_level = JCMath.zeros(D)
	st.d_since = JCMath.zeros(D)
	st.d_until = JCMath.zeros(D)
	st.d_cool = JCMath.zeros(D)
	for d: int in D:
		if String(ct.decrees[d].get("kind", "")) == "level":
			st.d_level[d] = int(ct.decrees[d].get("default", 0))
	# 研究
	st.t_prog = JCMath.zeros(ct.t_n)
	st.t_done = JCMath.zeros(ct.t_n)
	# 世界
	var P: int = ct.partners.size()
	st.p_dev = JCMath.zeros(P)
	st.p_rel = JCMath.zeros(P)
	st.p_treaty = JCMath.zeros(P)
	st.p_active = JCMath.zeros(P)
	st.p_noise = JCMath.filled(P, PPM)
	st.p_exp = JCMath.zeros(P)
	st.p_imp = JCMath.zeros(P)
	for p: int in P:
		st.p_dev[p] = int(ct.partners[p].get("dev_ppm", PPM))
		st.p_rel[p] = int(ct.partners[p].get("relation", 0))
		st.p_active[p] = 1 if int(ct.partners[p].get("appear_era", 1)) <= 1 else 0
	st.world_era_q = JCMath.filled(5, -1)
	st.era_q = JCMath.filled(5, -1)
	st.world_era_q[1] = 0
	st.era_q[1] = 0
	st.led = JCMath.zeros(5)
	# 地标、事件、危机
	var L: int = ct.landmarks.size()
	st.l_state = JCMath.zeros(L)
	st.l_prog = JCMath.zeros(L)
	st.l_needq = JCMath.zeros(L)
	st.l_region = JCMath.zeros(L)
	st.lead_pick = JCMath.filled(5, -1)
	st.e_cool = JCMath.zeros(ct.events.size())
	st.cr_stage = JCMath.zeros(3)
	st.cr_since = JCMath.zeros(3)
	st.cr_bad = JCMath.zeros(3)
	_seed_flows(ct, st)
	st.money0 = JCMath.sum(st.savings) + st.treasury
	return st


## 开局的库存、收入与开支估计：让第一季不缺农具、居民按开局均衡花钱。
static func _seed_flows(ct: JCContent, st: JCState) -> void:
	var G: int = ct.g_n
	var C: int = ct.c_n
	var prod: PackedInt64Array = JCMath.zeros(G)
	var need: PackedInt64Array = JCMath.zeros(G)
	for i: int in st.stack_count():
		var m: int = st.s_m[i]
		var lv: int = st.s_level[i]
		var og: PackedInt64Array = ct.m_out_g[m]
		var oq: PackedInt64Array = ct.m_out_q[m]
		for k: int in og.size():
			prod[og[k]] += oq[k] * lv
		var ig: PackedInt64Array = ct.m_in_g[m]
		var iq: PackedInt64Array = ct.m_in_q[m]
		for k2: int in ig.size():
			need[ig[k2]] += iq[k2] * lv
	for g: int in G:
		var s: int = JCMath.mulppm(prod[g], 500_000)
		if ct.g_durable[g] == 1:
			s = maxi(s, JCMath.mulppm(need[g], 1_500_000))
		else:
			s = maxi(s, JCMath.mulppm(need[g], 400_000))
		if ct.g_perish[g] >= PPM:
			s = 0
		st.stock[g] = s
	# 收入：按开局篮子在基准价下的花费反推（花费 = 收入 ×（1 − 储蓄率））
	var e: JCEconomy = JCEconomy.new()
	var mods: JCMods = JCMods.new()
	e.setup(ct, st, mods)
	e.R = ct.r_n
	e.C = C
	e.N = ct.n_n
	e.margin_r = JCMath.filled(ct.r_n, int(ct.scenario.get("gov", {}).get("commerce_margin_ppm", 80000)))
	e.basket0 = st.basket.duplicate()
	for r: int in ct.r_n:
		for c: int in C:
			var k3: int = r * C + c
			var cost: int = 0
			for n: int in ct.n_n:
				if not ct.need_active(n, st.era):
					continue
				cost += e._need_cost(n, r, c, st.pop[k3], e.need_mult(n, st.basket[k3]))
			# 开局是稳态：收入全部花掉，积蓄正好在目标上
			st.spend[k3] = cost
			st.income[k3] = cost
	for g2: int in G:
		st.f_demand[g2] = maxi(prod[g2], need[g2])


# ════════════════════════════ 推进一季 ════════════════════════════════════
func advance(cmds: Array) -> Dictionary:
	last_error = ""
	if st.over == 1:
		return {"ok": false, "reason": "reason.game_over", "results": []}
	rng.state = st.rng_state
	mods.rebuild(st, ct)
	last_results = cmd.apply_all(cmds)
	world.decree_timers()
	world.expire_timed()
	mods.rebuild(st, ct)
	soc.roll_weather()
	_gov_fund()
	world.pre_economy()
	var prev_demand: PackedInt64Array = st.f_demand.duplicate()
	inv.plan_jobs()
	econ.prev_demand = prev_demand
	econ.run()
	inv.after_economy()
	world.post_economy()
	econ.cover_treasury()
	soc.governance()
	soc.demography()
	soc.literacy()
	soc.living_and_unrest()
	world.research()
	world.check_era()
	world.world_year()
	inv.closures()
	inv.private_invest()
	world.events()
	econ.cover_treasury()
	soc.crisis()
	_record()
	st.compact_stacks()
	st.rng_state = rng.state
	var chk: String = check()
	if chk != "":
		last_error = chk
		push_error("JCSim: " + chk)
	st.q += 1
	return {"ok": chk == "", "reason": chk, "results": last_results}


## 国家开支到位率：国库 + 上季收入够不够付上季的经常开支。
func _gov_fund() -> void:
	var need: int = int(st.last.get("gov_exp_regular", 0))
	var have: int = maxi(0, st.treasury) + int(st.last.get("gov_rev", 0))
	if need <= 0 or have >= need:
		st.gov_fund = PPM
	else:
		st.gov_fund = clampi(JCMath.ratio_ppm(have, need), 300_000, PPM)


func _record() -> void:
	var s: Dictionary = econ.summary.duplicate()
	var rev_tot: int = JCMath.sum(st.rev)
	var exp_tot: int = JCMath.sum(st.exp)
	var regular: int = exp_tot - st.exp[JCState.EXP_BUILD] - st.exp[JCState.EXP_RELIEF] - st.exp[JCState.EXP_EVENT]
	s["gov_rev"] = rev_tot
	s["gov_exp"] = exp_tot
	s["gov_exp_regular"] = regular
	s["pop"] = soc.total_pop()
	s["points"] = st.points
	s["coll_eff"] = st.coll_eff
	s["severity"] = Array(soc.severity)
	var silver_before: int = int(st.last.get("silver_total", st.silver))
	s["silver_flow"] = st.silver - silver_before
	s["silver_total"] = st.silver
	var liv: int = 0
	var pw: int = 0
	for k: int in st.pop.size():
		liv += st.living[k] * (st.pop[k] / 1000)
		pw += st.pop[k] / 1000
	s["living"] = liv / maxi(pw, 1)
	st.last = s
	if st.season() == 0:
		st.hist.append({"year": st.year(), "gdp": s["gdp"], "pop": s["pop"], "treasury": st.treasury,
				"debt": st.debt, "living": s["living"], "era": st.era, "world_era": st.world_era,
				"unemp": s["unemp_ppm"], "legitimacy": st.legitimacy, "rev": rev_tot, "exp": exp_tot,
				"exports": s["exports"], "imports": s["imports"], "points": st.points})
		if st.hist.size() > 420:
			st.hist = st.hist.slice(st.hist.size() - 420)


## 每季末的自检；返回空串表示通过。
func check() -> String:
	var money: int = JCMath.sum(st.savings) + st.treasury
	if money != st.money0 + st.silver:
		return "货币不守恒：%d ≠ %d（差 %d）" % [money, st.money0 + st.silver, money - st.money0 - st.silver]
	for k: int in st.pop.size():
		if st.pop[k] < 0:
			return "人口为负：组 %d" % k
		if st.savings[k] < 0:
			return "储蓄为负：组 %d（%d）" % [k, st.savings[k]]
	for g: int in st.stock.size():
		if st.stock[g] < 0:
			return "库存为负：%s" % ct.g_id[g]
	if st.treasury < 0:
		return "国库为负：%d" % st.treasury
	return ""
