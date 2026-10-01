## v2 分析（docs/57 §11、§12）：把局面读成「该做什么」的信号，顾问与托管共用同一套判断。
## 只读状态、不改状态；每个信号都尽量带上一条可以直接执行的命令（cmd）。
## 口径：钱是厘，数量是千分单位，比例是 ppm；时间是季。
class_name JCAnalyst
extends RefCounted

const PPM: int = 1_000_000

var sim: JCSim
var ct: JCContent
var st: JCState


func setup(p_sim: JCSim) -> void:
	sim = p_sim
	ct = sim.ct
	st = sim.st


# ════════════════════════════ 基础量 ══════════════════════════════════════
## 某组的闲人（可劳动人口 − 在岗）。
func idle(r: int, c: int) -> int:
	var k: int = r * ct.c_n + c
	return maxi(0, JCMath.mulppm(st.pop[k], sim.econ.work_ppm(c)) - st.employed[k])


func region_pop(r: int) -> int:
	return sim.soc.region_pop(r)


## 商品的需求（上季记账：居民 + 投入 + 公用 + 出口）。
func demand(g: int) -> int:
	return st.f_demand[g]


## 价格相对基准（ppm）。
func price_ppm(g: int) -> int:
	return JCMath.ratio_ppm(st.price[g], maxi(1, ct.g_base[g]))


## 库存可用几季（ppm·季）。
func stock_q(g: int) -> int:
	return JCMath.ratio_ppm(st.stock[g], maxi(1, demand(g)), 0)


## 最近四季的平均国库收支（厘/季）。
func fiscal_avg() -> Dictionary:
	var rev: int = int(st.last.get("gov_rev", 0))
	var ex: int = int(st.last.get("gov_exp", 0))
	var reg: int = int(st.last.get("gov_exp_regular", ex))
	return {"rev": rev, "exp": ex, "regular": reg}


# ════════════════════════════ 商品 ════════════════════════════════════════
## 能产出 g 的「当前」方法（主产品优先；联产品排后）。
func producer_methods(g: int) -> PackedInt64Array:
	var main: PackedInt64Array = PackedInt64Array()
	var side: PackedInt64Array = PackedInt64Array()
	for b: int in ct.b_n:
		if not sim.inv.building_unlocked(b) or ct.b_era[b] > st.era + 1:
			continue
		for m: int in sim.inv.current_methods(b):
			var og: PackedInt64Array = ct.m_out_g[m]
			var k: int = og.find(g)
			if k < 0:
				continue
			if k == 0:
				main.append(m)
			else:
				side.append(m)
	main.append_array(side)
	return main


## 紧缺：缺口或进口占需求一成以上、或价格高出三成。按缺口价值排序，附最佳补法。
func shortages(limit: int = 6) -> Array:
	var out: Array = []
	for g: int in ct.g_n:
		if not ct.good_active(g, st.era):
			continue
		var d: int = demand(g)
		if d <= 0:
			continue
		var gap: int = st.f_unmet[g] + st.f_imp[g]
		var gap_ppm: int = JCMath.ratio_ppm(gap, d)
		var pp: int = price_ppm(g)
		if gap_ppm < 100_000 and pp < 1_300_000:
			continue
		var value: int = JCMath.value(maxi(gap, JCMath.mulppm(d, maxi(0, pp - PPM) / 3)), st.price[g])
		var fix: Dictionary = best_fix(g)
		out.append({"g": g, "id": ct.g_id[g], "gap": gap, "gap_ppm": gap_ppm, "price_ppm": pp,
				"imports": st.f_imp[g], "value": value, "fix": fix})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["value"]) > int(b["value"]) or (int(a["value"]) == int(b["value"]) and int(a["g"]) < int(b["g"])))
	return out.slice(0, limit)


## 积压：库存超过两季需求、或价格低于基准两成五。
func gluts(limit: int = 6) -> Array:
	var out: Array = []
	for g: int in ct.g_n:
		if not ct.good_active(g, st.era) or st.f_prod[g] <= 0:
			continue
		var sq: int = stock_q(g)
		var pp: int = price_ppm(g)
		if sq < 2_000_000 and pp > 750_000:
			continue
		out.append({"g": g, "id": ct.g_id[g], "stock_q": sq, "price_ppm": pp,
				"value": JCMath.value(st.stock[g], st.price[g])})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["value"]) > int(b["value"]) or (int(a["value"]) == int(b["value"]) and int(a["g"]) < int(b["g"])))
	return out.slice(0, limit)


## 补某商品缺口的最佳办法：{b, m, r, cmd, cost, roi_ppm, ...}；没有办法时返回空字典。
## 顺着产业链往上游找：要建的作坊主料本身就缺（上季到货不足七成），先补主料（至多往上两层），
## 结果里 via 记下是为了哪样商品（面粉缺 → 根子在麦粟 → 先开旱田）。
func best_fix(g: int, depth: int = 0) -> Dictionary:
	var best: Dictionary = {}
	var best_score: int = -(1 << 62)
	for m: int in producer_methods(g):
		var b: int = ct.m_b[m]
		if (ct.b_owners[b] & 2) == 0 and (ct.b_owners[b] & 1) == 0:
			continue
		var site: Dictionary = best_site(b, m)
		if site.is_empty():
			continue
		var score: int = int(site["score"])
		if ct.m_out_g[m][0] != g:
			score = score / 2
		if score > best_score:
			best_score = score
			best = site
	if best.is_empty():
		return best
	var m2: int = int(best["m"])
	var ig: PackedInt64Array = ct.m_in_g[m2]
	for k: int in ig.size():
		if ct.m_in_share[m2][k] < JCEconomy.MAIN_INPUT_PPM or ct.g_durable[ig[k]] == 1:
			continue
		var gi: int = ig[k]
		var fill: int = sim.econ.in_fill[gi] if sim.econ.in_fill.size() > gi else PPM
		var tight: bool = fill < 700_000 or price_ppm(gi) > 1_300_000
		if not tight:
			continue
		if depth >= 2:
			return {}
		var up: Dictionary = best_fix(gi, depth + 1)
		if up.is_empty():
			return {}
		up["via"] = ct.g_id[g]
		up["input"] = ct.g_id[gi]
		return up
	return best


## 某建筑、某方法在哪个地区建最好：看能不能建、利润回报、本地闲人、原料到货、物流费。
func best_site(b: int, m: int) -> Dictionary:
	var best: Dictionary = {}
	var best_score: int = -(1 << 62)
	for r: int in ct.r_n:
		var rep: Dictionary = site_report(b, m, r)
		if String(rep["block"]) != "":
			continue
		var score: int = int(rep["roi_ppm"]) + int(rep["labor_ok_ppm"]) / 4 - int(rep["logistics_ppm"]) * 3
		for w: Dictionary in rep["warnings"]:
			if String(w["key"]) == "warn.water":
				score -= 500_000
		if score > best_score:
			best_score = score
			best = rep
			best["score"] = score
	return best


## 建造前的提醒（软约束）：造价、工期、按现价的利润与回报、用工与本地闲人、原料到货、销路、物流。
## block 为硬性原因键（不能建）；warnings 是软提醒键的列表（能建，但要知道）。
func site_report(b: int, m: int, r: int) -> Dictionary:
	var owner_gov: bool = (ct.b_owners[b] & 2) != 0
	var block: String = sim.inv.check_site(b, r, 1)
	if block == "" and not sim.inv.method_unlocked(m):
		block = "reason.tech_missing"
	var cost: int = sim.inv.level_cost(b, m, owner_gov)
	var profit: int = sim.inv.level_profit(b, m, r) if ct.b_cat[b] != JCContent.CAT_PUBLIC and ct.b_cat[b] != JCContent.CAT_INFRA else 0
	var roi: int = JCMath.ratio_ppm(profit * 4, maxi(cost, 1), 0)
	var warnings: Array = []
	# 用工
	var C: int = ct.c_n
	var labor_ok: int = PPM
	var labor: Array = []
	for c: int in C:
		var need: int = ct.m_labor[m * C + c]
		if need <= 0:
			continue
		var id: int = idle(r, c)
		labor.append({"class": ct.c_id[c], "need": need, "idle": id})
		labor_ok = mini(labor_ok, JCMath.ratio_ppm(id, need))
	if labor_ok < PPM:
		warnings.append({"key": "warn.few_workers", "pct": labor_ok})
	# 原料
	var inputs: Array = []
	var ig: PackedInt64Array = ct.m_in_g[m]
	for k: int in ig.size():
		var g: int = ig[k]
		var f: int = sim.econ.in_fill[g] if sim.econ.in_fill.size() > g else PPM
		var pp: int = price_ppm(g)
		inputs.append({"g": ct.g_id[g], "fill": f, "price_ppm": pp, "main": ct.m_in_share[m][k] >= JCEconomy.MAIN_INPUT_PPM})
		if f < 800_000 and ct.m_in_share[m][k] >= JCEconomy.MAIN_INPUT_PPM:
			warnings.append({"key": "warn.input_short", "good": ct.g_id[g], "pct": f})
		elif pp > 1_300_000 and ct.m_in_share[m][k] >= JCEconomy.MAIN_INPUT_PPM:
			warnings.append({"key": "warn.input_dear", "good": ct.g_id[g], "pct": pp})
	# 销路
	var og: PackedInt64Array = ct.m_out_g[m]
	var outs: Array = []
	for g2: int in og:
		var sq: int = stock_q(g2)
		var pp2: int = price_ppm(g2)
		outs.append({"g": ct.g_id[g2], "price_ppm": pp2, "stock_q": sq})
	if not og.is_empty():
		var g0: int = og[0]
		if stock_q(g0) > 1_500_000 or price_ppm(g0) < 800_000:
			warnings.append({"key": "warn.glut", "good": ct.g_id[g0], "pct": price_ppm(g0)})
	# 物流
	var lg: int = st.logistics[r] if st.logistics.size() > r else ct.r_logistics[r]
	if lg >= 80_000 and not og.is_empty():
		warnings.append({"key": "warn.logistics", "pct": lg})
	# 水力
	if ct.m_water[m] == 1 and sim.econ.water_cov.size() > r:
		var wl: int = 0
		for i: int in st.stack_count():
			if st.s_region[i] == r and ct.m_water[st.s_m[i]] == 1:
				wl += st.s_level[i]
		if sim.econ.water_cov[r] < (wl + 1) * PPM:
			warnings.append({"key": "warn.water"})
	# 地与矿
	var lt: int = ct.b_land[b]
	if lt >= 0 and block == "":
		var left: int = st.land[r * JCContent.LT_N + lt] - sim.inv.land_in_use(r, lt)
		if left <= 2:
			warnings.append({"key": "warn.land_tight", "left": left})
	if ct.b_deposit[b] != "" and block == "":
		var dleft: int = int(ct.r_deposit[r].get(ct.b_deposit[b], 0)) - sim.inv.deposit_in_use(r, b)
		if dleft <= 2:
			warnings.append({"key": "warn.deposit_tight", "left": dleft})
	# 回报
	var cat: int = ct.b_cat[b]
	if block == "" and (cat == JCContent.CAT_WORKSHOP or cat == JCContent.CAT_MINE or cat == JCContent.CAT_FARM):
		if roi < 50_000:
			warnings.append({"key": "warn.low_return", "pct": roi})
	# 落后：本国已进入更新的时代
	if ct.m_era[m] < st.era and sim.inv.newer_method_exists(b, m):
		warnings.append({"key": "warn.old_method"})
	# 农田、矿、作坊默认「招商」：官府出钱营造，建成归商贾经营（利润留在民间、国库收商税）；
	# 设施与只许官办的建筑由官府经营
	var owner: String = "gov" if owner_gov else "private"
	if (ct.b_owners[b] & 1) != 0 and (cat == JCContent.CAT_FARM or cat == JCContent.CAT_MINE or cat == JCContent.CAT_WORKSHOP):
		owner = "private"
	return {"b": b, "m": m, "r": r, "building": ct.b_id[b], "method": ct.m_id[m], "region": ct.r_id[r],
			"block": block, "cost": cost, "quarters": ct.b_build_q[b], "profit_q": profit, "roi_ppm": roi,
			"labor": labor, "labor_ok_ppm": labor_ok, "inputs": inputs, "outputs": outs, "logistics_ppm": lg,
			"warnings": warnings,
			"cmd": {"kind": "build", "building": ct.b_id[b], "region": ct.r_id[r], "method": ct.m_id[m], "owner": owner}}


## 营造用料上季到了几成（按本国时代的用料表、按价值加权）。
func build_material_fill() -> int:
	var e: JCEconomy = sim.econ
	if e.cur_build_g.is_empty() or e.fill_firm.size() != ct.g_n:
		return PPM
	var acc: int = 0
	var w: int = 0
	for k: int in e.cur_build_g.size():
		var g: int = e.cur_build_g[k]
		acc += JCMath.mulppm(e.fill_firm[g], e.cur_build_ppm[k])
		w += e.cur_build_ppm[k]
	return PPM if w <= 0 else JCMath.ratio_ppm(acc, w)


# ════════════════════════════ 设施 ════════════════════════════════════════
## 设施吃紧：集市、车马行、港口、商栈超负荷；水利覆盖不足；学舍、医馆、城政、粮仓、衙署不够。
func infra_needs() -> Array:
	var out: Array = []
	var e: JCEconomy = sim.econ
	var base_margin: int = int(ct.scenario.get("gov", {}).get("commerce_margin_ppm", 80000))
	for r: int in ct.r_n:
		var pop_r: int = maxi(1, region_pop(r))
		if e.margin_r.size() > r and e.margin_r[r] > JCMath.mulppm(base_margin, 1_150_000):
			out.append(_need("market", r, JCMath.ratio_ppm(e.margin_r[r], base_margin), "need.market"))
		if e.cap_freight.size() > r and e.fee_pool.size() > r and e.cap_freight[r] > 0 \
				and e.fee_pool[r] > JCMath.mulppm(e.cap_freight[r], 1_100_000):
			out.append(_need("carrier", r, JCMath.ratio_ppm(e.fee_pool[r], e.cap_freight[r]), "need.carrier"))
		if e.farm_lv.size() > r and e.farm_lv[r] > 0:
			var cov: int = mini(PPM, JCMath.ratio_ppm(e.irrig_cov[r], e.farm_lv[r] * PPM))
			if cov < 500_000:
				out.append(_need("irrigation", r, PPM - cov, "need.irrigation"))
		# 学位满额是人口的 3%（识字率的目标按这个算，见 JCSociety.literacy）
		var seats: int = e.edu_seats[r] if e.edu_seats.size() > r else 0
		if JCMath.ratio_ppm(seats, pop_r) < 30_000:
			out.append(_need("school", r, PPM - JCMath.ratio_ppm(seats, JCMath.mulppm(pop_r, 30_000)), "need.school"))
		var hc: int = mini(PPM, JCMath.ratio_ppm(e.health_cov[r] if e.health_cov.size() > r else 0, pop_r))
		if hc < 500_000:
			out.append(_need("clinic", r, PPM - hc, "need.clinic"))
		var sc: int = mini(PPM, JCMath.ratio_ppm(e.sanit_cov[r] if e.sanit_cov.size() > r else 0, pop_r))
		if sc < 400_000:
			out.append(_need("urbanworks", r, PPM - sc, "need.sanitation"))
		var ad: int = mini(PPM, JCMath.ratio_ppm(e.admin_cap[r] if e.admin_cap.size() > r else 0, pop_r))
		if ad < 800_000:
			out.append(_need("yamen", r, PPM - ad, "need.admin"))
		if st.logistics.size() > r and st.logistics[r] >= 60_000:
			out.append(_need("road", r, st.logistics[r] * 5, "need.road"))
	if e.cap_sea > 0 and e.used_sea >= JCMath.mulppm(e.cap_sea, 900_000):
		var pr: int = -1
		for r2: int in ct.r_n:
			if ct.r_coast[r2] == 1:
				pr = r2
				break
		if pr >= 0:
			out.append(_need("port", pr, JCMath.ratio_ppm(e.used_sea, e.cap_sea), "need.port"))
	if e.cap_land > 0 and e.used_land >= JCMath.mulppm(e.cap_land, 900_000):
		out.append(_need("caravanserai", int(ct.ridx.get("xiling", 0)), JCMath.ratio_ppm(e.used_land, e.cap_land),
				"need.caravan"))
	var staple_d: int = 0
	for g: int in [int(ct.gidx.get("rice", 0)), int(ct.gidx.get("grain", 0))]:
		staple_d += demand(g)
	if e.grain_cap < JCMath.mulppm(staple_d, 50_000):
		out.append(_need("granary", int(ct.ridx.get("zhongzhou", 0)), PPM - JCMath.ratio_ppm(e.grain_cap, JCMath.mulppm(staple_d, 50_000)),
				"need.granary"))
	# 能建、建了有人手的才留下
	var keep: Array = []
	for n: Dictionary in out:
		var b: int = int(ct.bidx.get(String(n["building"]), -1))
		if b < 0 or not sim.inv.building_unlocked(b):
			continue
		var r3: int = int(n["r"])
		if sim.inv.check_site(b, r3, 1) != "":
			continue
		var m: int = sim.inv.best_method(b)
		if _short_handed(b, m, r3):
			continue
		var owner: String = "gov" if (ct.b_owners[b] & 2) != 0 else "private"
		n["cost"] = sim.inv.level_cost(b, m, owner == "gov")
		n["cmd"] = {"kind": "build", "building": ct.b_id[b], "region": ct.r_id[r3], "method": ct.m_id[m], "owner": owner}
		keep.append(n)
	keep.sort_custom(func(a: Dictionary, b2: Dictionary) -> bool:
		return int(a["pressure"]) > int(b2["pressure"]) or (int(a["pressure"]) == int(b2["pressure"]) and String(a["building"]) < String(b2["building"])))
	return keep


## 这类设施在本地区已经招不满人（现有的卡在人手上），或本地主力阶层没有闲人。
func _short_handed(b: int, m: int, r: int) -> bool:
	for i: int in st.stack_count():
		if st.s_b[i] == b and st.s_region[i] == r and st.s_bind[i] == JCEconomy.B_LABOR and st.s_status[i] == JCState.ST_ACTIVE:
			return true
	var C: int = ct.c_n
	var tot: int = 0
	for c0: int in C:
		tot += ct.m_labor[m * C + c0]
	for c: int in C:
		var need: int = ct.m_labor[m * C + c]
		if need <= 0 or JCMath.ratio_ppm(need, maxi(1, tot)) < JCEconomy.MAIN_INPUT_PPM:
			continue
		if idle(r, c) < need / 2:
			return true
	return false


func _need(building: String, r: int, pressure: int, key: String) -> Dictionary:
	return {"building": building, "r": r, "region": ct.r_id[r], "pressure": pressure, "key": key}


# ════════════════════════════ 改造 ════════════════════════════════════════
## 过时、值得改造的建筑堆：新方法按现价的增益与造价、年回报。
func obsolete(limit: int = 8) -> Array:
	var out: Array = []
	var counts: Dictionary = sim.inv.upgrade_counts()
	for i: int in st.stack_count():
		if st.s_status[i] != JCState.ST_ACTIVE or st.s_pending[i] > 0 or st.s_level[i] <= 0:
			continue
		var nm: int = sim.inv.newer_method(i)
		if nm < 0:
			continue
		var b: int = st.s_b[i]
		var r: int = st.s_region[i]
		if not sim.inv.upgrade_sane(st.s_m[i], nm, st.s_level[i]):
			continue
		var gain: int = 0
		if ct.b_cat[b] == JCContent.CAT_PUBLIC or ct.b_cat[b] == JCContent.CAT_INFRA:
			gain = JCMath.mulppm(ct.b_maint[b], maxi(0, ct.m_eff[nm] - ct.m_eff[st.s_m[i]])) * st.s_level[i]
		else:
			gain = (sim.inv.level_profit(b, nm, r) - sim.inv.level_profit(b, st.s_m[i], r)) * st.s_level[i]
		var cost: int = sim.inv.upgrade_cost(i, nm)
		var roi: int = JCMath.ratio_ppm(gain * 4, maxi(cost, 1), 0)
		var pen: int = sim.econ.obsolete_penalty(b, st.s_m[i], sim.econ.obs_rate(), sim.econ.obs_max())
		var sl: int = JCInvest.upgrade_slice(st.s_level[i])
		out.append({"i": i, "uid": st.s_uid[i], "b": b, "r": r, "building": ct.b_id[b], "region": ct.r_id[r],
				"from": ct.m_id[st.s_m[i]], "to": ct.m_id[nm], "levels": st.s_level[i], "gain_q": gain,
				"cost": cost, "roi_ppm": roi, "penalty_ppm": pen, "owner": "gov" if st.s_owner[i] == JCContent.OWNER_GOV else "private",
				"labor_ok": sim.inv.labor_ok(i, nm), "room": JCInvest.upgrade_room(counts, b, r), "slice": sl,
				"slice_cost": JCMath.muldiv(cost, sl, maxi(1, st.s_level[i])),
				"cmd": {"kind": "upgrade", "uid": st.s_uid[i], "method": ct.m_id[nm]},
				"cmd_slice": {"kind": "upgrade", "uid": st.s_uid[i], "method": ct.m_id[nm], "levels": sl}})
	out.sort_custom(func(a: Dictionary, b2: Dictionary) -> bool:
		return int(a["roi_ppm"]) > int(b2["roi_ppm"]) or (int(a["roi_ppm"]) == int(b2["roi_ppm"]) and int(a["uid"]) < int(b2["uid"])))
	return out.slice(0, limit)


## 改造合不合时宜：新方法的主料眼下紧缺（到货不足七成或价高三成）不改；
## 产品已经积压、新方法每级还多产的不改（省人的改造照样可以）。
func _upgrade_sane(m_old: int, m_new: int) -> bool:
	var ig: PackedInt64Array = ct.m_in_g[m_new]
	for k: int in ig.size():
		if ct.m_in_share[m_new][k] < JCEconomy.MAIN_INPUT_PPM or ct.g_durable[ig[k]] == 1:
			continue
		var g: int = ig[k]
		if ct.m_in_g[m_old].has(g):
			continue
		var fill: int = sim.econ.in_fill[g] if sim.econ.in_fill.size() > g else PPM
		if fill < 700_000 or price_ppm(g) > 1_300_000:
			return false
	var og: PackedInt64Array = ct.m_out_g[m_new]
	if og.is_empty():
		return true
	var g0: int = og[0]
	var old_q: int = 0
	var k0: int = ct.m_out_g[m_old].find(g0)
	if k0 >= 0:
		old_q = ct.m_out_q[m_old][k0]
	if ct.m_out_q[m_new][0] > old_q and (stock_q(g0) > 1_500_000 or price_ppm(g0) < 800_000):
		return false
	return true


## 可合并的：同地区、同类型、同所有者有两堆以上，且其中有过时的。
func merge_candidates() -> Array:
	var groups: Dictionary = {}
	for i: int in st.stack_count():
		if st.s_status[i] != JCState.ST_ACTIVE or st.s_level[i] <= 0:
			continue
		var key: String = "%d:%d:%d" % [st.s_region[i], st.s_b[i], st.s_owner[i]]
		if not groups.has(key):
			groups[key] = []
		groups[key].append(i)
	var out: Array = []
	var keys: Array = groups.keys()
	keys.sort()
	for key2: Variant in keys:
		var rows: Array = groups[key2]
		if rows.size() < 2:
			continue
		var i0: int = int(rows[0])
		var n_old: int = sim.inv._merge_rows(st.s_b[i0], st.s_region[i0], st.s_owner[i0]).size()
		var b: int = st.s_b[i0]
		if ct.b_cat[b] == JCContent.CAT_FARM:
			continue
		var r: int = st.s_region[i0]
		var owner: String = "gov" if st.s_owner[i0] == JCContent.OWNER_GOV else "private"
		var cost: int = sim.inv.consolidate_cost(b, r, st.s_owner[i0])
		if cost <= 0:
			continue
		out.append({"b": b, "r": r, "building": ct.b_id[b], "region": ct.r_id[r], "stacks": n_old, "cost": cost,
				"owner": owner, "cmd": {"kind": "consolidate", "building": ct.b_id[b], "region": ct.r_id[r], "owner": owner}})
	return out


## 官办的长期亏损、开工很低的建筑：可以封存。
func losers() -> Array:
	var out: Array = []
	for i: int in st.stack_count():
		if st.s_owner[i] != JCContent.OWNER_GOV or st.s_status[i] != JCState.ST_ACTIVE:
			continue
		var b: int = st.s_b[i]
		if ct.b_cat[b] == JCContent.CAT_PUBLIC or ct.b_cat[b] == JCContent.CAT_INFRA:
			continue
		if st.s_profit[i] < 0 and st.s_u[i] < 400_000:
			out.append({"i": i, "uid": st.s_uid[i], "building": ct.b_id[b], "region": ct.r_id[st.s_region[i]],
					"loss_q": -st.s_profit[i], "cmd": {"kind": "mothball", "uid": st.s_uid[i]}})
	return out


# ════════════════════════════ 财政 ════════════════════════════════════════
## 财政概况：收支、余额、还能撑几季、债务与利息、隐田、征收率。
func fiscal() -> Dictionary:
	var f: Dictionary = fiscal_avg()
	var bal: int = int(f["rev"]) - int(f["exp"])
	var runway: int = 999
	if bal < 0:
		runway = st.treasury / maxi(1, -bal)
	var hid: int = 0
	for r: int in ct.r_n:
		hid += st.hidden[r]
	hid = hid / maxi(1, ct.r_n)
	var rate: int = JCMath.mulppm(st.debt_rate_ppm, sim.mods.mult_ppm("interest_rate"))
	return {"rev": f["rev"], "exp": f["exp"], "regular": f["regular"], "balance": bal, "runway_q": runway,
			"treasury": st.treasury, "debt": st.debt, "interest_q": JCMath.mulppm(st.debt, rate), "hidden_ppm": hid,
			"coll_eff": st.coll_eff, "arrears": st.arrears}


## 能拉回民心的长期政令：还没施行、眼下能施行、各阶层民心有加有减之后威信净涨的（按各阶层在威信里的分量折算）。
## 附带「减民怨」的（工厂法、社会保险）把减掉的民怨也折进去。净民心为负、该由玩家权衡的（所得税、遣使译书……）
## 不在其内；赈济按有没有人挨饿开关，也不在其内。
## 返回 [{decree, gain_ppm（威信约涨多少）, cost_q（每季开支，厘）, cmd}]，不花钱的排最前，其余按每两银子换来的威信排。
func support_decrees() -> Array:
	var out: Array = []
	var C: int = ct.c_n
	var unrest_c: PackedInt64Array = JCMath.zeros(C)
	var pw: PackedInt64Array = JCMath.zeros(C)
	for k: int in st.pop.size():
		var w: int = st.pop[k] / 1000
		unrest_c[k % C] += st.unrest[k] * w
		pw[k % C] += w
	for c: int in C:
		unrest_c[c] = unrest_c[c] / maxi(1, pw[c])
	for d: int in ct.decrees.size():
		var dd: Dictionary = ct.decrees[d]
		var id: String = String(dd["id"])
		if String(dd.get("kind", "toggle")) != "toggle" or st.d_level[d] != 0 or id == "famine_relief":
			continue
		var sup_list: Array = dd.get("support", [])
		var gain: int = 0
		if not sup_list.is_empty():
			var sup: Dictionary = sup_list[0]
			for ck: Variant in sup.keys():
				gain += JCMath.mulppm(int(sup[ck]) * 10_000, int(JCSociety.INFLUENCE.get(String(ck), 250_000)))
		# 减民怨：民心约按 0.6 × 民怨往下拉，所以民怨减两成，民心约涨 0.6 × 当前民怨 × 两成
		var effs: Array = dd.get("effects", [])
		if not effs.is_empty():
			for e: Dictionary in effs[0]:
				if String(e.get("target", "")) != "unrest" or float(e.get("value", 0)) >= 0.0:
					continue
				var cut: int = int(-float(e.get("value", 0)) * 10_000.0)
				var scope: String = String(e.get("scope", ""))
				for c2: int in C:
					if scope == "all" or scope == "" or scope == ct.c_id[c2]:
						var dsup: int = JCMath.mulppm(JCMath.mulppm(unrest_c[c2], cut), 600_000)
						gain += JCMath.mulppm(dsup, int(JCSociety.INFLUENCE.get(ct.c_id[c2], 250_000)))
		if gain <= 0:
			continue
		var cmd: Dictionary = {"kind": "decree", "decree": id, "level": 1}
		if not bool(sim.cmd.check(cmd).get("ok", false)):
			continue
		var cq: int = int(dd.get("cost_q_li", 0))
		out.append({"decree": id, "gain_ppm": gain, "cost_q": cq, "cmd": cmd,
				"score": JCMath.muldiv(gain, 1_000_000_000, maxi(1, cq))})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["score"]) > int(b["score"]) or (int(a["score"]) == int(b["score"]) and String(a["decree"]) < String(b["decree"])))
	return out


# ════════════════════════════ 民生 ════════════════════════════════════════
## 民怨最重的几组：地区、阶层、生活、民怨、失业，以及主因（缺粮、日用太紧、失业、税重）。
func hotspots(limit: int = 4) -> Array:
	var out: Array = []
	var C: int = ct.c_n
	var staple: int = int(ct.nidx.get("staple", 0))
	for k: int in st.pop.size():
		if st.pop[k] <= 0:
			continue
		var r: int = k / C
		var c: int = k % C
		var sup: int = JCMath.mulppm(st.pop[k], sim.econ.work_ppm(c))
		var unemp: int = 0 if sup <= 0 or ct.c_id[c] == "gentry" else JCMath.ratio_ppm(maxi(0, sup - st.employed[k]), sup)
		var cause: String = "cause.comfort"
		if st.sat[k * ct.n_n + staple] < 900_000:
			cause = "cause.hunger"
		elif unemp > 120_000:
			cause = "cause.jobless"
		elif st.comfort[k] >= 900_000:
			cause = "cause.tax"
		out.append({"k": k, "r": r, "c": c, "region": ct.r_id[r], "class": ct.c_id[c], "living": st.living[k],
				"unrest": st.unrest[k], "unemp": unemp, "cause": cause, "pop": st.pop[k]})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["unrest"]) * (int(a["pop"]) / 1000 + 1) > int(b["unrest"]) * (int(b["pop"]) / 1000 + 1) \
				or (int(a["unrest"]) == int(b["unrest"]) and int(a["k"]) < int(b["k"])))
	return out.slice(0, limit)


# ════════════════════════════ 时代 ════════════════════════════════════════
## 进入下一时代还差什么，每一项都配上办法：研究哪门、在哪建什么、社会条件靠什么。
func era_plan() -> Dictionary:
	var rep: Dictionary = sim.world.era_gap_report()
	var items: Array = []
	for tid: Variant in rep.get("techs", []):
		var t: int = int(ct.tidx.get(String(tid), -1))
		if t < 0:
			continue
		var path: Array = tech_path(t)
		var first: int = t if path.is_empty() else int(path[0])
		items.append({"kind": "tech", "id": String(tid), "next": ct.t_id[first],
				"cmd": {"kind": "research", "tech": ct.t_id[first]}})
	var bl: Dictionary = rep.get("buildings", {})
	var bkeys: Array = bl.keys()
	bkeys.sort()
	for bk: Variant in bkeys:
		var pair: Array = bl[bk]
		if int(pair[0]) >= int(pair[1]):
			continue
		var b: int = int(ct.bidx.get(String(bk), -1))
		var item: Dictionary = {"kind": "building", "id": String(bk), "have": int(pair[0]), "need": int(pair[1])}
		if b >= 0 and sim.inv.building_unlocked(b):
			var site: Dictionary = best_site(b, sim.inv.best_method(b))
			if not site.is_empty():
				# 时代的标志建筑官办：不会因为一时亏本被东家关掉
				var cmd0: Dictionary = (site["cmd"] as Dictionary).duplicate()
				if (ct.b_owners[b] & 2) != 0:
					cmd0["owner"] = "gov"
				item["cmd"] = cmd0
				item["cost"] = sim.inv.level_cost(b, int(site["m"]), cmd0["owner"] == "gov")
		else:
			item["locked"] = true
			if b >= 0 and ct.b_tech[b] >= 0:
				item["tech"] = ct.t_id[ct.b_tech[b]]
		items.append(item)
	var so: Dictionary = rep.get("social", {})
	var skeys: Array = so.keys()
	skeys.sort()
	for sk: Variant in skeys:
		var pr: Array = so[sk]
		if int(pr[0]) >= int(pr[1]):
			continue
		var it: Dictionary = {"kind": "social", "id": String(sk), "have": int(pr[0]), "need": int(pr[1])}
		if String(sk) == "urban":
			# 城里人（工匠、商贾）不够：在人最多的地区开最能用工匠的作坊
			var big: int = 0
			for r0: int in ct.r_n:
				if region_pop(r0) > region_pop(big):
					big = r0
			var job: Dictionary = artisan_site(big)
			if not job.is_empty():
				it["cmd"] = job["cmd"]
				it["cost"] = job["cost"]
		if String(sk) == "literacy":
			var worst: int = 0
			for r: int in ct.r_n:
				if st.literacy[r] < st.literacy[worst]:
					worst = r
			var b2: int = int(ct.bidx.get("school", -1))
			if b2 >= 0 and sim.inv.check_site(b2, worst, 1) == "":
				it["cmd"] = {"kind": "build", "building": "school", "region": ct.r_id[worst],
						"method": ct.m_id[sim.inv.best_method(b2)], "owner": "gov"}
		items.append(it)
	return {"era": st.era, "next": st.era + 1, "ok": bool(rep.get("ok", false)), "items": items,
			"world_era": st.world_era}


## 在 r 地区找一门最能用工匠、回报过得去、原料不缺、产品不积压的作坊（城市化用）。
func artisan_site(r: int) -> Dictionary:
	var best: Dictionary = {}
	var best_score: int = 0
	var A: int = int(ct.cidx.get("artisan", 1))
	for b: int in ct.b_n:
		if ct.b_cat[b] != JCContent.CAT_WORKSHOP or not sim.inv.building_unlocked(b):
			continue
		for m: int in sim.inv.current_methods(b):
			var need: int = ct.m_labor[m * ct.c_n + A]
			if need <= 0:
				continue
			var rep: Dictionary = site_report(b, m, r)
			if String(rep["block"]) != "" or int(rep["roi_ppm"]) < 80_000:
				continue
			var bad: bool = false
			for w: Dictionary in rep["warnings"]:
				if ["warn.glut", "warn.input_short", "warn.water"].has(String(w["key"])):
					bad = true
			if bad:
				continue
			var score: int = JCMath.muldiv(need, 1_000_000_000, maxi(1, int(rep["cost"]))) + int(rep["roi_ppm"]) / 4
			if score > best_score:
				best_score = score
				best = rep
	return best


## 为了研究 t 还要先研究的前置（按可研究的先后），含 t 本身；已完成的不列。
func tech_path(t: int) -> Array:
	var out: Array = []
	_path_rec(t, out, {})
	return out


func _path_rec(t: int, out: Array, seen: Dictionary) -> void:
	if seen.has(t) or st.t_done[t] == 1:
		return
	seen[t] = true
	for p: int in ct.t_prereq[t]:
		if p >= 0:
			_path_rec(p, out, seen)
	out.append(t)


# ════════════════════════════ 科技 ════════════════════════════════════════
## 科技的方向标签（按背景建筑与效果粗分）：agri、industry、commerce、culture、state。
func tech_tags(t: int) -> PackedStringArray:
	var tags: PackedStringArray = PackedStringArray()
	for b: int in ct.t_bg[t]:
		if b < 0:
			continue
		match ct.b_cat[b]:
			JCContent.CAT_FARM:
				_add_tag(tags, "agri")
			JCContent.CAT_WORKSHOP, JCContent.CAT_MINE:
				_add_tag(tags, "industry")
			JCContent.CAT_INFRA:
				_add_tag(tags, "commerce" if ["market", "port", "caravanserai", "carrier", "road", "canal"].has(ct.b_id[b]) else "agri")
			JCContent.CAT_PUBLIC:
				_add_tag(tags, "culture" if ["school", "library", "theater"].has(ct.b_id[b]) else "state")
	return tags


func _add_tag(tags: PackedStringArray, t: String) -> void:
	if not tags.has(t):
		tags.append(t)


## 口粮里有哪样比常价贵过一成：粮食开始紧了（还不一定有人挨饿）。
func food_tight() -> bool:
	var n: int = int(ct.nidx.get("staple", -1))
	if n < 0:
		return false
	for g: int in ct.n_goods[n]:
		if st.f_demand[g] > 0 and price_ppm(g) > 1_100_000:
			return true
	return false


## 全国吃得最差的一组，口粮满足了几成（ppm）。
func hunger_ppm() -> int:
	var staple: int = int(ct.nidx.get("staple", 0))
	var worst: int = PPM
	for k: int in st.pop.size():
		if st.pop[k] > 0:
			worst = mini(worst, st.sat[k * ct.n_n + staple])
	return worst


## 眼下最值得研究的一门（按取向）：下一时代的关键科技及其前置最优先，再看方向、背景加速与价钱。
func best_research(stance: String) -> int:
	var key_set: Dictionary = {}
	var rep: Dictionary = sim.world.era_gap_report()
	for tid: Variant in rep.get("techs", []):
		var t0: int = int(ct.tidx.get(String(tid), -1))
		if t0 >= 0:
			for p: Variant in tech_path(t0):
				key_set[int(p)] = true
	# 标志建筑被锁住的，也把解锁科技算进来
	var bl: Dictionary = rep.get("buildings", {})
	for bk: Variant in bl.keys():
		var b: int = int(ct.bidx.get(String(bk), -1))
		if b >= 0 and ct.b_tech[b] >= 0 and st.t_done[ct.b_tech[b]] != 1:
			for p2: Variant in tech_path(ct.b_tech[b]):
				key_set[int(p2)] = true
	# 有人吃不饱（口粮不到九成五）或口粮涨价过一成：不管取向，先研究增产粮食的
	var hungry: bool = hunger_ppm() < 950_000 or food_tight()
	var best: int = -1
	var best_score: int = -(1 << 62)
	for t: int in ct.t_n:
		if not sim.world.tech_available(t):
			continue
		var cost: int = maxi(1, sim.world.tech_cost(t) - st.t_prog[t])
		var speed: int = PPM + sim.world.bg_domestic(t) + sim.world.bg_foreign(t)
		# 分数：越快出成果越好（点数 / 有效成本），按取向加权
		var score: int = JCMath.muldiv(speed, 1_000_000, cost)
		var w: int = PPM
		if key_set.has(t):
			w += 2_000_000 if stance == "era" else 1_000_000
		var tags: PackedStringArray = tech_tags(t)
		match stance:
			"agri":
				if tags.has("agri"):
					w += 1_000_000
			"industry":
				if tags.has("industry"):
					w += 1_000_000
			"commerce":
				if tags.has("commerce"):
					w += 1_000_000
			"culture":
				if tags.has("culture") or tags.has("state"):
					w += 1_000_000
		if ct.t_key[t] == 1:
			w += 300_000
		if hungry and tags.has("agri"):
			w += 3_000_000
		score = JCMath.mulppm(score, w)
		if score > best_score:
			best_score = score
			best = t
	return best


# ════════════════════════════ 外贸 ════════════════════════════════════════
## 值得签商约的伙伴：关系不差、往来货值大、国库付得起。
func treaty_candidates() -> Array:
	var out: Array = []
	for p: int in ct.partners.size():
		if st.p_active[p] != 1 or st.p_treaty[p] == 1 or st.p_rel[p] < 0:
			continue
		var vol: int = st.p_exp[p] + st.p_imp[p]
		var cost: int = sim.cmd.treaty_cost(p)
		out.append({"p": p, "partner": String(ct.partners[p]["id"]), "volume_q": vol, "cost": cost,
				"cmd": {"kind": "treaty", "partner": String(ct.partners[p]["id"])}})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["volume_q"]) > int(b["volume_q"]) or (int(a["volume_q"]) == int(b["volume_q"]) and int(a["p"]) < int(b["p"])))
	return out


## 海外想要、本国有富余的商品（出口机会）。
func export_room() -> Array:
	var out: Array = []
	for p: int in ct.partners.size():
		if st.p_active[p] != 1:
			continue
		var wants: Dictionary = ct.partners[p].get("wants", {})
		var gks: Array = wants.keys()
		gks.sort()
		for gk: Variant in gks:
			var g: int = int(ct.gidx.get(String(gk), -1))
			if g < 0:
				continue
			var price: int = sim.econ.export_price(p, g)
			if price < JCMath.mulppm(st.price[g], 900_000):
				continue
			out.append({"p": p, "partner": String(ct.partners[p]["id"]), "g": g, "good": ct.g_id[g],
					"price_ppm": JCMath.ratio_ppm(price, maxi(1, st.price[g])), "cap": int(wants[gk][1])})
	return out
