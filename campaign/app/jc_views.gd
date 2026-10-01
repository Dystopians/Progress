## v2 界面视图（docs/57 §15）：把局面整理成各页要显示的数据（只读）。
## 界面只拿这些字典与 JCGame 的命令接口，不直接碰模拟核心。
## 数值口径同核心：钱是厘，数量是千分单位，比例是 ppm；显示格式由界面（JcFmt）负责。
class_name JCViews
extends RefCounted

const PPM: int = 1_000_000
const ERA_STYLE: PackedStringArray = ["agrarian", "agrarian", "agrarian", "industrial", "modern"]

var g: JCGame


func _init(game: JCGame) -> void:
	g = game


# ════════════════════════════ 国情 ════════════════════════════════════════
func overview() -> Dictionary:
	var st: JCState = g.st
	var l: Dictionary = st.last
	var f: Dictionary = g.analyst.fiscal()
	var hist: Array = []
	for h: Dictionary in st.hist:
		hist.append(h)
	var crisis: Array = []
	for t: int in 3:
		crisis.append({"track": t, "stage": st.cr_stage[t],
				"severity": g.sim.soc.severity[t] if g.sim.soc.severity.size() > t else 0,
				"since": st.cr_since[t]})
	return {
		"pop": int(l.get("pop", 0)), "gdp": int(l.get("gdp", 0)), "living": int(l.get("living", 0)),
		"unemp": int(l.get("unemp_ppm", 0)), "treasury": st.treasury, "balance": int(f["balance"]),
		"rev": int(f["rev"]), "exp": int(f["exp"]), "debt": st.debt, "legitimacy": st.legitimacy,
		"prestige": st.prestige, "era": st.era, "world_era": st.world_era, "points": st.points,
		"support": Array(st.support), "classes": Array(g.ct.c_id), "crisis": crisis, "hist": hist,
		"era_plan": g.analyst.era_plan(), "expect": g.sim.econ.expect_mult(),
		"exports": int(l.get("exports", 0)), "imports": int(l.get("imports", 0)),
	}


# ════════════════════════════ 地区与舆图 ══════════════════════════════════
## 各地区一览：人口、生活、民怨、失业、识字、物流、主要产业、配图。
func regions() -> Array:
	var ct: JCContent = g.ct
	var st: JCState = g.st
	var out: Array = []
	var C: int = ct.c_n
	var gdp_r: PackedInt64Array = JCMath.zeros(ct.r_n)
	for i: int in st.stack_count():
		gdp_r[st.s_region[i]] += maxi(0, g.sim.econ.s_rev[i] - g.sim.econ.s_cost_in[i] - g.sim.econ.s_cost_maint[i]) \
				if g.sim.econ.s_rev.size() > i else 0
	var gdp_tot: int = maxi(1, JCMath.sum(gdp_r))
	for r: int in ct.r_n:
		var pop: int = 0
		var liv: int = 0
		var unr: int = 0
		var sup: int = 0
		var emp: int = 0
		for c: int in C:
			var k: int = r * C + c
			var w: int = st.pop[k] / 1000
			pop += st.pop[k]
			liv += st.living[k] * w
			unr += st.unrest[k] * w
			if ct.c_id[c] != "gentry":
				sup += JCMath.mulppm(st.pop[k], g.sim.econ.work_ppm(c))
				emp += mini(st.employed[k], JCMath.mulppm(st.pop[k], g.sim.econ.work_ppm(c)))
		var pw: int = maxi(1, pop / 1000)
		var living: int = liv / pw
		var unrest: int = unr / pw
		var unemp: int = PPM - JCMath.ratio_ppm(emp, maxi(1, sup))
		out.append({"id": ct.r_id[r], "name": ct.r_name[r], "desc": ct.r_desc[r], "pop": pop, "living": living,
				"unrest": unrest, "unemp": unemp, "literacy": st.literacy[r],
				"logistics": st.logistics[r] if st.logistics.size() > r else ct.r_logistics[r],
				"gdp_share": JCMath.ratio_ppm(gdp_r[r], gdp_tot), "harvest": st.harvest[r], "flood": st.flood[r],
				"hidden": st.hidden[r], "coast": ct.r_coast[r] == 1, "river": ct.r_river[r] == 1,
				"capital": ct.r_capital[r] == 1, "top": _top_industries(r, 4),
				"alert": _region_alert(r, living, unrest),
				"art": region_art(r, living, unrest)})
	return out


## 地区警示：缺粮（口粮不到九成）、民怨过半、受灾，按轻重给一个键；没事返回空串。
func _region_alert(r: int, living: int, unrest: int) -> String:
	var st: JCState = g.st
	var ct: JCContent = g.ct
	var staple: int = int(ct.nidx.get("staple", 0))
	var C: int = ct.c_n
	var worst_food: int = PPM
	for c: int in C:
		var k: int = r * C + c
		if st.pop[k] > 0:
			worst_food = mini(worst_food, st.sat[k * ct.n_n + staple])
	if worst_food < 900_000:
		return "hunger"
	if unrest > 500_000:
		return "unrest"
	if st.flood[r] == 1 or st.harvest[r] < 820_000:
		return "disaster"
	if living < 850_000:
		return "hard"
	return ""


## 地区配图：按本国时代选风格（农耕 / 工业 / 现代），按境况选画面（兴旺、平稳、萧条、受灾、残破、重建）。
func region_art(r: int, living: int, unrest: int) -> String:
	var st: JCState = g.st
	var style: String = ERA_STYLE[clampi(st.era, 0, 4)]
	var cond: String = "steady"
	if st.flood[r] == 1 or st.harvest[r] < 820_000:
		cond = "disaster"
	elif unrest > 550_000:
		cond = "damaged"
	elif unrest > 380_000 or living < 850_000:
		cond = "stagnant"
	elif living > 1_020_000:
		cond = "thriving"
	var base: String = "res://assets/regions/%s/%s_%s" % [g.ct.r_id[r], style, cond]
	for suffix: String in ["_v2.png", ".png"]:
		if ResourceLoader.exists(base + suffix):
			return base + suffix
	var fallback: String = "res://assets/regions/%s/%s_steady" % [g.ct.r_id[r], style]
	for suffix2: String in ["_v2.png", ".png"]:
		if ResourceLoader.exists(fallback + suffix2):
			return fallback + suffix2
	return "res://assets/regions/%s/agrarian_steady.png" % g.ct.r_id[r]


func _top_industries(r: int, n: int) -> Array:
	var ct: JCContent = g.ct
	var st: JCState = g.st
	var by_b: Dictionary = {}
	for i: int in st.stack_count():
		if st.s_region[i] != r or st.s_level[i] <= 0:
			continue
		var b: int = st.s_b[i]
		if ct.b_cat[b] == JCContent.CAT_PUBLIC or ct.b_cat[b] == JCContent.CAT_INFRA:
			continue
		by_b[b] = int(by_b.get(b, 0)) + st.s_level[i]
	var arr: Array = []
	for b2: Variant in by_b.keys():
		arr.append([int(by_b[b2]), int(b2)])
	arr.sort_custom(func(a: Array, b3: Array) -> bool: return a[0] > b3[0] or (a[0] == b3[0] and a[1] < b3[1]))
	var out: Array = []
	for x: Array in arr.slice(0, n):
		var art: String = ct.building_art(x[1], st.era)
		if art != "" and not art.begins_with("res://"):
			art = "res://" + art
		out.append({"building": ct.b_id[x[1]], "name": ct.b_name[x[1]], "levels": x[0], "art": art})
	return out


## 某地区的建筑：按建筑类型归并（级数、开工、卡在哪、利润、所有者），附每一堆以便操作。
func region_detail(rid: String) -> Dictionary:
	var ct: JCContent = g.ct
	var st: JCState = g.st
	var r: int = int(ct.ridx.get(rid, -1))
	if r < 0:
		return {}
	var groups: Dictionary = {}
	for i: int in st.stack_count():
		if st.s_region[i] != r or (st.s_level[i] <= 0 and st.s_pending[i] <= 0):
			continue
		var b: int = st.s_b[i]
		if not groups.has(b):
			groups[b] = {"building": ct.b_id[b], "name": ct.b_name[b], "cat": JCContent.CATS[ct.b_cat[b]],
					"levels": 0, "pending": 0, "u_acc": 0, "profit": 0, "stacks": []}
		var gr: Dictionary = groups[b]
		gr["levels"] = int(gr["levels"]) + st.s_level[i]
		gr["pending"] = int(gr["pending"]) + st.s_pending[i]
		gr["u_acc"] = int(gr["u_acc"]) + st.s_u[i] * st.s_level[i]
		gr["profit"] = int(gr["profit"]) + st.s_profit[i]
		(gr["stacks"] as Array).append(stack_view(i))
	var list: Array = []
	for b2: Variant in groups.keys():
		var gr2: Dictionary = groups[b2]
		gr2["u"] = int(gr2["u_acc"]) / maxi(1, int(gr2["levels"]))
		gr2.erase("u_acc")
		list.append(gr2)
	list.sort_custom(func(a: Dictionary, b3: Dictionary) -> bool:
		return int(a["levels"]) > int(b3["levels"]) or (int(a["levels"]) == int(b3["levels"]) and String(a["building"]) < String(b3["building"])))
	var land: Array = []
	for lt: int in JCContent.LT_N:
		var cap: int = st.land[r * JCContent.LT_N + lt]
		if cap <= 0:
			continue
		land.append({"type": JCContent.LAND_TYPES[lt], "cap": cap, "used": g.sim.inv.land_in_use(r, lt)})
	var reg: Dictionary = {}
	for rv: Dictionary in regions():
		if String(rv["id"]) == rid:
			reg = rv
	var classes: Array = []
	var C: int = ct.c_n
	for c: int in C:
		var k: int = r * C + c
		var sup: int = JCMath.mulppm(st.pop[k], g.sim.econ.work_ppm(c))
		classes.append({"class": ct.c_id[c], "name": ct.c_name[c], "pop": st.pop[k], "living": st.living[k],
				"comfort": st.comfort[k], "unrest": st.unrest[k], "wage": st.wage[k],
				"income_pc": st.income[k] / maxi(1, st.pop[k] / 1000),
				"unemp": 0 if sup <= 0 else JCMath.ratio_ppm(maxi(0, sup - st.employed[k]), sup)})
	return {"region": reg, "buildings": list, "land": land, "classes": classes,
			"deposits": ct.r_deposit[r].duplicate()}


func stack_view(i: int) -> Dictionary:
	var ct: JCContent = g.ct
	var st: JCState = g.st
	var nm: int = g.sim.inv.newer_method(i)
	return {"uid": st.s_uid[i], "building": ct.b_id[st.s_b[i]], "method": ct.m_id[st.s_m[i]],
			"method_name": ct.m_name[st.s_m[i]], "level": st.s_level[i], "pending": st.s_pending[i],
			"status": st.s_status[i], "u": st.s_u[i], "bind": st.s_bind[i], "profit": st.s_profit[i],
			"owner": "gov" if st.s_owner[i] == JCContent.OWNER_GOV else "private",
			"progress": JCMath.ratio_ppm(st.s_prog[i], maxi(1, st.s_needq[i] * PPM), 0),
			"target": ct.m_id[st.s_target[i]] if st.s_target[i] >= 0 else "",
			"newer": ct.m_id[nm] if nm >= 0 else "",
			"penalty": g.sim.econ.obsolete_penalty(st.s_b[i], st.s_m[i], g.sim.econ.obs_rate(), g.sim.econ.obs_max())}


## 舆图图层：每个地区一个 0—1 的值（ppm）与一个显示用的数。
func map_layer(layer: String) -> Array:
	var out: Array = []
	for rv: Dictionary in regions():
		var v: int = 0
		var raw: int = 0
		match layer:
			"living":
				raw = int(rv["living"])
				v = clampi(JCMath.ratio_ppm(raw - 700_000, 400_000), 0, PPM)
			"unrest":
				raw = int(rv["unrest"])
				v = clampi(raw * 2, 0, PPM)
			"unemp":
				raw = int(rv["unemp"])
				v = clampi(raw * 4, 0, PPM)
			"logistics":
				raw = int(rv["logistics"])
				v = clampi(JCMath.ratio_ppm(raw, 120_000), 0, PPM)
			"literacy":
				raw = int(rv["literacy"])
				v = clampi(raw, 0, PPM)
			"industry":
				raw = int(rv["gdp_share"])
				v = clampi(raw * 2, 0, PPM)
			"pop":
				raw = int(rv["pop"])
				v = clampi(JCMath.ratio_ppm(raw, 15_000_000), 0, PPM)
		out.append({"id": rv["id"], "v": v, "raw": raw})
	return out


## 贸易路线：每个来往伙伴的出入货值与走海路还是陆路。
func routes() -> Array:
	var ct: JCContent = g.ct
	var st: JCState = g.st
	var out: Array = []
	for p: int in ct.partners.size():
		if st.p_active[p] != 1:
			continue
		out.append({"partner": String(ct.partners[p]["id"]), "name": String(ct.partners[p]["name"]),
				"route": String(ct.partners[p].get("route", "sea")), "exports": st.p_exp[p], "imports": st.p_imp[p],
				"relation": st.p_rel[p], "treaty": st.p_treaty[p] == 1})
	return out


# ════════════════════════════ 产业 ════════════════════════════════════════
const SECTOR_ORDER: PackedStringArray = ["agri", "manu", "energy", "serv"]


## 商品一览（本时代可见的）：价、产、需、缺、进出口、库存季数，以及状态（紧缺 / 积压 / 平稳）。
func goods() -> Array:
	var ct: JCContent = g.ct
	var st: JCState = g.st
	var out: Array = []
	for gi: int in ct.g_n:
		if not ct.good_active(gi, st.era) and st.f_prod[gi] == 0 and st.f_hh[gi] == 0:
			continue
		var d: int = st.f_demand[gi]
		var pp: int = JCMath.ratio_ppm(st.price[gi], maxi(1, ct.g_base[gi]))
		var sq: int = JCMath.ratio_ppm(st.stock[gi], maxi(1, d), 0)
		var gap: int = st.f_unmet[gi] + st.f_imp[gi]
		# 想要的货里有几成靠进口或没买到（给人看，最多 100%）
		var want: int = st.f_hh[gi] + st.f_use[gi] + st.f_gov[gi] + st.f_exp[gi] + st.f_unmet[gi]
		var short: int = mini(JCMath.PPM, JCMath.ratio_ppm(gap, maxi(1, want)))
		var state: String = "ok"
		if d > 0 and (JCMath.ratio_ppm(gap, d) > 100_000 or pp > 1_300_000):
			state = "short"
		elif st.f_prod[gi] > 0 and (sq > 2_000_000 or pp < 750_000):
			state = "glut"
		out.append({"g": gi, "id": ct.g_id[gi], "name": ct.g_name[gi], "unit": ct.g_unit[gi],
				"sector": JCContent.SECTORS[ct.g_sector[gi]], "tier": ct.g_tier[gi], "era": ct.g_era[gi],
				"art": ct.g_art[gi], "price": st.price[gi], "price_ppm": pp, "base": ct.g_base[gi],
				"prod": st.f_prod[gi], "hh": st.f_hh[gi], "use": st.f_use[gi], "gov": st.f_gov[gi],
				"exp": st.f_exp[gi], "imp": st.f_imp[gi], "unmet": st.f_unmet[gi], "demand": d, "stock": st.stock[gi],
				"stock_q": sq, "short_ppm": short, "state": state})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var sa: int = SECTOR_ORDER.find(String(a["sector"]))
		var sb: int = SECTOR_ORDER.find(String(b["sector"]))
		if sa != sb:
			return sa < sb
		if int(a["tier"]) != int(b["tier"]):
			return int(a["tier"]) < int(b["tier"])
		return int(a["g"]) < int(b["g"]))
	return out


## 一样商品的来龙去脉：谁在产（用什么料）、谁在用（居民哪项需要、哪些作坊、官府、出口）。
func goods_chain(gid: String) -> Dictionary:
	var ct: JCContent = g.ct
	var st: JCState = g.st
	var gi: int = int(ct.gidx.get(gid, -1))
	if gi < 0:
		return {}
	var producers: Dictionary = {}
	var consumers: Dictionary = {}
	for i: int in st.stack_count():
		if st.s_level[i] <= 0:
			continue
		var m: int = st.s_m[i]
		if ct.m_out_g[m].has(gi):
			var key: String = ct.m_id[m]
			if not producers.has(key):
				var ins: Array = []
				var ig: PackedInt64Array = ct.m_in_g[m]
				for k: int in ig.size():
					var g2: int = ig[k]
					ins.append({"id": ct.g_id[g2], "name": ct.g_name[g2], "qty": ct.m_in_q[m][k],
							"fill": g.sim.econ.in_fill[g2] if g.sim.econ.in_fill.size() > g2 else PPM,
							"main": ct.m_in_share[m][k] >= JCEconomy.MAIN_INPUT_PPM,
							"price_ppm": JCMath.ratio_ppm(st.price[g2], maxi(1, ct.g_base[g2]))})
				producers[key] = {"building": ct.b_id[st.s_b[i]], "building_name": ct.b_name[st.s_b[i]],
						"art": ct.building_art(st.s_b[i], maxi(st.era, ct.m_era[m])),
						"method": key, "method_name": ct.m_name[m], "levels": 0, "u_acc": 0, "inputs": ins,
						"out_q": ct.m_out_q[m][ct.m_out_g[m].find(gi)]}
			var pr: Dictionary = producers[key]
			pr["levels"] = int(pr["levels"]) + st.s_level[i]
			pr["u_acc"] = int(pr["u_acc"]) + st.s_u[i] * st.s_level[i]
		if ct.m_in_g[m].has(gi):
			var key2: String = ct.m_id[m]
			if not consumers.has(key2):
				consumers[key2] = {"kind": "method", "building": ct.b_id[st.s_b[i]], "building_name": ct.b_name[st.s_b[i]],
						"art": ct.building_art(st.s_b[i], maxi(st.era, ct.m_era[m])),
						"method": key2, "method_name": ct.m_name[m], "levels": 0,
						"out": ct.g_id[ct.m_out_g[m][0]] if not ct.m_out_g[m].is_empty() else ""}
			consumers[key2]["levels"] = int(consumers[key2]["levels"]) + st.s_level[i]
	var prod_list: Array = []
	for v: Variant in producers.values():
		var pv: Dictionary = v
		pv["u"] = int(pv["u_acc"]) / maxi(1, int(pv["levels"]))
		pv.erase("u_acc")
		prod_list.append(pv)
	var cons_list: Array = consumers.values()
	var needs: Array = []
	for n: int in ct.n_n:
		if ct.n_goods[n].has(gi) and ct.need_active(n, st.era):
			needs.append({"need": ct.n_id[n], "name": ct.n_name[n], "essential": ct.n_ess[n] == 1})
	var buyers: Array = []
	for p: int in ct.partners.size():
		if st.p_active[p] == 1 and ct.partners[p].get("wants", {}).has(gid):
			buyers.append({"partner": String(ct.partners[p]["id"]), "name": String(ct.partners[p]["name"])})
	var sellers: Array = []
	for p2: int in ct.partners.size():
		if st.p_active[p2] == 1 and ct.partners[p2].get("offers", {}).has(gid):
			sellers.append({"partner": String(ct.partners[p2]["id"]), "name": String(ct.partners[p2]["name"])})
	# 能产它、但还没建的：给「在哪建」的入口
	var options: Array = []
	for m2: int in g.analyst.producer_methods(gi):
		options.append({"building": ct.b_id[ct.m_b[m2]], "building_name": ct.b_name[ct.m_b[m2]], "method": ct.m_id[m2],
				"method_name": ct.m_name[m2], "art": ct.building_art(ct.m_b[m2], maxi(st.era, ct.m_era[m2]))})
	var fix: Dictionary = g.analyst.best_fix(gi)
	var row: Dictionary = {}
	for gv: Dictionary in goods():
		if String(gv["id"]) == gid:
			row = gv
	return {"good": row, "producers": prod_list, "consumers": cons_list, "needs": needs, "buyers": buyers,
			"sellers": sellers, "options": options, "fix": fix}


## 产业链图（产业页上方）：原料的原料 → 原料 → 这样货 → 拿它做原料的货 → 百姓的哪项需要。
## 只看眼下在开工的做法（没人产时看能产它的做法）；每格带状态（紧缺 / 积压 / 平稳），各列最多 6 格。
func chain_graph(gid: String) -> Dictionary:
	var ct: JCContent = g.ct
	var st: JCState = g.st
	var gi: int = int(ct.gidx.get(gid, -1))
	if gi < 0:
		return {}
	var state: Dictionary = {}
	var names: Dictionary = {}
	for gv: Dictionary in goods():
		state[String(gv["id"])] = String(gv["state"])
		names[String(gv["id"])] = String(gv["name"])
	# 商品 → 在用的产出它的做法；商品 → 在用的拿它做原料的做法
	var makers: Dictionary = {}
	var users: Dictionary = {}
	for i: int in st.stack_count():
		if st.s_level[i] <= 0:
			continue
		var m: int = st.s_m[i]
		for og: int in ct.m_out_g[m]:
			if not makers.has(og):
				makers[og] = {}
			makers[og][m] = true
		for ig: int in ct.m_in_g[m]:
			if not users.has(ig):
				users[ig] = {}
			users[ig][m] = true
	var up1: Array = _inputs_of(gi, makers)
	var up2: Array = []
	var seen: Dictionary = {gi: true}
	for x: int in up1:
		seen[x] = true
	var links2: Array = []
	for x2: int in up1:
		for y: int in _inputs_of(x2, makers):
			if not seen.has(y) and up2.size() < 6:
				seen[y] = true
				up2.append(y)
			if up2.has(y):
				links2.append([ct.g_id[y], ct.g_id[x2]])
	var down: Array = []
	var down_via: Dictionary = {}
	for m2: Variant in users.get(gi, {}).keys():
		var mm: int = int(m2)
		for og2: int in ct.m_out_g[mm]:
			if og2 != gi and not down.has(og2) and down.size() < 6:
				down.append(og2)
				down_via[og2] = ct.b_name[ct.m_b[mm]]
	var needs: Array = []
	for n: int in ct.n_n:
		if ct.n_goods[n].has(gi) and ct.need_active(n, st.era):
			needs.append({"id": ct.n_id[n], "name": ct.n_name[n], "essential": ct.n_ess[n] == 1})
	var cell: Callable = func(x3: int) -> Dictionary:
		var id3: String = ct.g_id[x3]
		return {"id": id3, "name": String(names.get(id3, ct.g_name[x3])), "state": String(state.get(id3, "ok")),
				"fill": g.sim.econ.in_fill[x3] if g.sim.econ.in_fill.size() > x3 else PPM, "art": ct.g_art[x3]}
	var o_up1: Array = []
	for a: int in up1.slice(0, 6):
		o_up1.append(cell.call(a))
	var o_up2: Array = []
	for a2: int in up2:
		o_up2.append(cell.call(a2))
	var o_down: Array = []
	for a3: int in down:
		var c3: Dictionary = cell.call(a3)
		c3["via"] = String(down_via.get(a3, ""))
		o_down.append(c3)
	return {"center": cell.call(gi), "up1": o_up1, "up2": o_up2, "links2": links2, "down": o_down,
			"needs": needs.slice(0, 6)}


## 某商品的原料：在用的做法里的原料（没人产时看能产它的做法），主料在前。
func _inputs_of(gi: int, makers: Dictionary) -> Array:
	var ct: JCContent = g.ct
	var ms: Array = makers.get(gi, {}).keys()
	if ms.is_empty():
		for m0: int in g.analyst.producer_methods(gi):
			ms.append(m0)
	var main: Array = []
	var minor: Array = []
	for m: Variant in ms:
		var mi: int = int(m)
		var ig: PackedInt64Array = ct.m_in_g[mi]
		for k: int in ig.size():
			var x: int = ig[k]
			if x == gi or main.has(x) or minor.has(x):
				continue
			if ct.m_in_share[mi][k] >= JCEconomy.MAIN_INPUT_PPM:
				main.append(x)
			else:
				minor.append(x)
	for x2: Variant in minor:
		if main.has(x2):
			continue
		main.append(x2)
	return main


## 可建的建筑目录（按类别）：已解锁的与下一时代将解锁的，带造价与每级说明。
func catalog() -> Array:
	var ct: JCContent = g.ct
	var st: JCState = g.st
	var out: Array = []
	for b: int in ct.b_n:
		if ct.b_era[b] > st.era + 1:
			continue
		var unlocked: bool = g.sim.inv.building_unlocked(b)
		var methods: Array = []
		for m: int in ct.b_methods[b]:
			methods.append({"method": ct.m_id[m], "name": ct.m_name[m], "era": ct.m_era[m],
					"unlocked": g.sim.inv.method_unlocked(m), "current": g.sim.inv.current_methods(b).has(m),
					"tech": ct.t_id[ct.m_tech[m]] if ct.m_tech[m] >= 0 else ""})
		out.append({"building": ct.b_id[b], "name": ct.b_name[b], "note": ct.b_note[b], "cat": JCContent.CATS[ct.b_cat[b]],
				"sector": JCContent.SECTORS[ct.b_sector[b]], "unlocked": unlocked,
				"tech": ct.t_id[ct.b_tech[b]] if ct.b_tech[b] >= 0 else "", "gov_only": (ct.b_owners[b] & 1) == 0,
				"art": ct.building_art(b, st.era), "methods": methods})
	return out


## 建造提醒：某建筑、某方法（空串 = 眼下最好的）、某地区的软约束与预计。
func site(building: String, method: String, region: String) -> Dictionary:
	var ct: JCContent = g.ct
	var b: int = int(ct.bidx.get(building, -1))
	var r: int = int(ct.ridx.get(region, -1))
	if b < 0 or r < 0:
		return {}
	var m: int = int(ct.midx.get(method, -1)) if method != "" else g.sim.inv.best_method(b)
	if m < 0:
		return {}
	return g.analyst.site_report(b, m, r)


## 某建筑（某方法，空串 = 眼下最好的）在各地区的建造提醒，附推荐地区与允许的经营方式。
func sites(building: String, method: String) -> Dictionary:
	var ct: JCContent = g.ct
	var b: int = int(ct.bidx.get(building, -1))
	if b < 0:
		return {}
	# 推荐做法：眼下能用的做法里，最好地区一年回报最高的那种（设施、公共建筑不看回报，取最新的）
	var rec: int = g.sim.inv.best_method(b)
	var cat: int = ct.b_cat[b]
	if cat == JCContent.CAT_FARM or cat == JCContent.CAT_MINE or cat == JCContent.CAT_WORKSHOP:
		var best_roi: int = -(1 << 62)
		for m0: int in g.sim.inv.current_methods(b):
			var bs: Dictionary = g.analyst.best_site(b, m0)
			if bs.is_empty():
				continue
			if int(bs["roi_ppm"]) > best_roi:
				best_roi = int(bs["roi_ppm"])
				rec = m0
	var m: int = int(ct.midx.get(method, -1)) if method != "" else rec
	if m < 0:
		return {}
	var list: Array = []
	for r: int in ct.r_n:
		var rep: Dictionary = g.analyst.site_report(b, m, r)
		rep["region_name"] = ct.r_name[r]
		list.append(rep)
	var best: Dictionary = g.analyst.best_site(b, m)
	return {"method": ct.m_id[m], "recommended": ct.m_id[rec], "list": list, "best": String(best.get("region", "")),
			"private_ok": (ct.b_owners[b] & 1) != 0, "gov_ok": (ct.b_owners[b] & 2) != 0,
			"cat": JCContent.CATS[ct.b_cat[b]], "treasury": g.st.treasury}


## 改造中心：过时可改的、可合并的、亏损可封存的，以及按建筑类型汇总（一键「全部改造」）。
func modernize() -> Dictionary:
	var obs: Array = g.analyst.obsolete(60)
	var by_b: Dictionary = {}
	for ob: Dictionary in obs:
		var key: String = String(ob["building"]) + ":" + String(ob["owner"])
		if not by_b.has(key):
			by_b[key] = {"building": ob["building"], "owner": ob["owner"], "count": 0, "levels": 0, "cost": 0, "gain_q": 0,
					"to": ob["to"]}
		var e: Dictionary = by_b[key]
		e["count"] = int(e["count"]) + 1
		e["levels"] = int(e["levels"]) + int(ob["levels"])
		e["cost"] = int(e["cost"]) + int(ob["cost"])
		e["gain_q"] = int(e["gain_q"]) + int(ob["gain_q"])
	var groups: Array = by_b.values()
	for gr: Dictionary in groups:
		gr["roi_ppm"] = JCMath.ratio_ppm(int(gr["gain_q"]) * 4, maxi(1, int(gr["cost"])), 0)
		gr["cmd"] = {"kind": "upgrade_all", "building": gr["building"], "region": "", "owner": gr["owner"]}
	groups.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["roi_ppm"]) > int(b["roi_ppm"]) or (int(a["roi_ppm"]) == int(b["roi_ppm"]) and String(a["building"]) < String(b["building"])))
	# 合并改造按建筑类型归拢：一个按钮把各地区的都办了
	var merges: Array = g.analyst.merge_candidates()
	var mg: Dictionary = {}
	for mc: Dictionary in merges:
		var k2: String = String(mc["building"]) + ":" + String(mc["owner"])
		if not mg.has(k2):
			mg[k2] = {"building": mc["building"], "owner": mc["owner"], "regions": [], "stacks": 0, "cost": 0, "cmds": []}
		var e2: Dictionary = mg[k2]
		(e2["regions"] as Array).append(mc["region"])
		e2["stacks"] = int(e2["stacks"]) + int(mc["stacks"])
		e2["cost"] = int(e2["cost"]) + int(mc["cost"])
		(e2["cmds"] as Array).append(mc["cmd"])
	var merge_groups: Array = mg.values()
	merge_groups.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["stacks"]) > int(b["stacks"]) or (int(a["stacks"]) == int(b["stacks"]) and String(a["building"]) < String(b["building"])))
	return {"stacks": obs, "groups": groups, "merge": merges, "merge_groups": merge_groups, "losers": g.analyst.losers()}


# ════════════════════════════ 科技 ════════════════════════════════════════
func techs() -> Dictionary:
	var ct: JCContent = g.ct
	var st: JCState = g.st
	var key_set: Dictionary = {}
	for tid: Variant in g.sim.world.era_gap_report().get("techs", []):
		var t0: int = int(ct.tidx.get(String(tid), -1))
		if t0 >= 0:
			for p: Variant in g.analyst.tech_path(t0):
				key_set[int(p)] = true
	# 每项科技解锁什么：建筑、新做法、政令（给科技树上的小图标与详情）
	var unlocks: Array = []
	for t0: int in ct.t_n:
		unlocks.append([])
	for b: int in ct.b_n:
		if ct.b_tech[b] >= 0:
			(unlocks[ct.b_tech[b]] as Array).append({"kind": "building", "id": ct.b_id[b], "name": ct.b_name[b],
					"art": ct.building_art(b, maxi(ct.t_era[ct.b_tech[b]], ct.b_era[b]))})
	for m: int in ct.m_n:
		if ct.m_tech[m] >= 0 and ct.b_tech[ct.m_b[m]] != ct.m_tech[m]:
			var bm: int = ct.m_b[m]
			(unlocks[ct.m_tech[m]] as Array).append({"kind": "method", "id": ct.m_id[m], "name": ct.m_name[m],
					"building": ct.b_name[bm], "art": ct.building_art(bm, maxi(ct.t_era[ct.m_tech[m]], ct.m_era[m]))})
	for d: int in ct.decrees.size():
		var dt: int = int(ct.tidx.get(String(ct.decrees[d].get("tech", "")), -1))
		if dt >= 0:
			(unlocks[dt] as Array).append({"kind": "decree", "id": String(ct.decrees[d]["id"]),
					"name": String(ct.decrees[d]["name"]), "art": ""})
		# 分档政令里要某项科技才能选的那几档（如政体：活字印刷后可行开明君主）
		var lt: Array = ct.decrees[d].get("level_tech", [])
		var lvn: Array = ct.decrees[d].get("levels", [])
		for lv: int in lt.size():
			var lt_i: int = int(ct.tidx.get(String(lt[lv]), -1))
			if lt_i >= 0 and lv < lvn.size():
				(unlocks[lt_i] as Array).append({"kind": "decree", "id": String(ct.decrees[d]["id"]), "level": lv,
						"name": String(ct.decrees[d]["name"]), "level_name": String(lvn[lv]), "art": ""})
	var list: Array = []
	for t: int in ct.t_n:
		var prereq: Array = []
		for p2: int in ct.t_prereq[t]:
			if p2 >= 0:
				prereq.append(ct.t_id[p2])
		var cost: int = g.sim.world.tech_cost(t)
		var dom: int = g.sim.world.bg_domestic(t)
		var fo: int = g.sim.world.bg_foreign(t)
		var speed: int = JCMath.mulppm(maxi(1, st.points), PPM + dom + fo)
		var left: int = maxi(0, cost - st.t_prog[t])
		var bg_names: Array = []
		for b: int in ct.t_bg[t]:
			if b >= 0:
				bg_names.append(ct.b_id[b])
		list.append({"id": ct.t_id[t], "name": ct.t_name[t], "desc": ct.t_desc[t], "era": ct.t_era[t], "cost": cost,
				"progress": st.t_prog[t], "done": st.t_done[t] == 1, "available": g.sim.world.tech_available(t),
				"focus": st.focus == t, "key": ct.t_key[t] == 1, "era_key": key_set.has(t), "prereq": prereq,
				"bg_domestic": dom, "bg_foreign": fo, "bg": bg_names, "eta_q": (left + speed - 1) / maxi(1, speed),
				"known_abroad": _known_abroad(t), "unlocks": unlocks[t]})
	return {"list": list, "points": st.points, "pool": st.rpool, "focus": ct.t_id[st.focus] if st.focus >= 0 else "",
			"era": st.era}


func _known_abroad(t: int) -> Array:
	var out: Array = []
	for p: int in g.ct.partners.size():
		if g.st.p_active[p] == 1 and g.sim.world.partner_knows(p, t):
			out.append(String(g.ct.partners[p]["id"]))
	return out


# ════════════════════════════ 政令与财政 ══════════════════════════════════
func policy() -> Dictionary:
	var ct: JCContent = g.ct
	var st: JCState = g.st
	var sc: Dictionary = ct.scenario.get("gov", {})
	var taxes: Array = [
		{"tax": "land", "value": st.tax_land_ppm, "base": int(sc.get("land_tax_ppm", 90000)),
				"lo": JCCommands.TAX_BOUNDS["land"][0], "hi": JCCommands.TAX_BOUNDS["land"][1], "rev": st.rev[JCState.REV_LAND]},
		{"tax": "salt", "value": st.tax_salt_li, "base": int(sc.get("salt_tax_li", 600)),
				"lo": JCCommands.TAX_BOUNDS["salt"][0], "hi": JCCommands.TAX_BOUNDS["salt"][1], "rev": st.rev[JCState.REV_SALT]},
		{"tax": "commerce", "value": st.tax_commerce_ppm, "base": int(sc.get("commerce_tax_ppm", 20000)),
				"lo": JCCommands.TAX_BOUNDS["commerce"][0], "hi": JCCommands.TAX_BOUNDS["commerce"][1], "rev": st.rev[JCState.REV_COMMERCE]},
		{"tax": "customs", "value": st.tax_customs_ppm, "base": int(sc.get("customs_ppm", 50000)),
				"lo": JCCommands.TAX_BOUNDS["customs"][0], "hi": JCCommands.TAX_BOUNDS["customs"][1], "rev": st.rev[JCState.REV_CUSTOMS]},
	]
	var lines: Array = []
	for line: int in JCState.BUD_N:
		lines.append({"line": line, "level": st.budget[line]})
	var decrees: Array = []
	for d: int in ct.decrees.size():
		var dd: Dictionary = ct.decrees[d]
		var tech: String = String(dd.get("tech", ""))
		var locked: bool = st.era < int(dd.get("era", 1)) or (tech != "" and st.t_done[int(ct.tidx.get(tech, 0))] != 1)
		# 分档政令每一档的门槛：{era, tech, locked}
		var lv_gate: Array = []
		var lera: Array = dd.get("level_era", [])
		var ltech: Array = dd.get("level_tech", [])
		for li: int in (dd.get("levels", []) as Array).size():
			var le: int = int(lera[li]) if li < lera.size() else 1
			var lt: String = String(ltech[li]) if li < ltech.size() else ""
			var lk: bool = st.era < le or (lt != "" and st.t_done[int(ct.tidx.get(lt, 0))] != 1)
			lv_gate.append({"era": le, "tech": lt, "locked": lk})
		decrees.append({"id": String(dd["id"]), "name": String(dd["name"]), "desc": String(dd.get("desc", "")),
				"kind": String(dd.get("kind", "toggle")), "levels": dd.get("levels", []), "level": st.d_level[d],
				"cost_once": int(dd.get("cost_once_li", 0)), "cost_q": int(dd.get("cost_q_li", 0)),
				"duration": int(dd.get("duration", 0)), "until": st.d_until[d], "cool": st.d_cool[d], "locked": locked,
				"tech": tech, "era": int(dd.get("era", 1)), "support": dd.get("support", []), "level_gate": lv_gate})
	return {"taxes": taxes, "budget": lines, "decrees": decrees, "regime": g.analyst.regime_profile(),
			"rev": Array(st.rev), "exp": Array(st.exp),
			"fiscal": g.analyst.fiscal(), "loan_limit": g.sim.cmd.loan_limit(), "debt": st.debt,
			"rate": JCMath.mulppm(st.debt_rate_ppm, g.sim.mods.mult_ppm("interest_rate"))}


# ════════════════════════════ 民生 ════════════════════════════════════════
func society() -> Dictionary:
	var ct: JCContent = g.ct
	var st: JCState = g.st
	var e: JCEconomy = g.sim.econ
	var C: int = ct.c_n
	var N: int = ct.n_n
	var classes: Array = []
	for c: int in C:
		var pop: int = 0
		var inc: int = 0
		var src: PackedInt64Array = JCMath.zeros(JCEconomy.SRC_N)
		var liv: int = 0
		var com: int = 0
		var unr: int = 0
		var sup: int = 0
		var emp: int = 0
		var needs: PackedInt64Array = JCMath.zeros(N)
		for r: int in ct.r_n:
			var k: int = r * C + c
			var w: int = st.pop[k] / 1000
			pop += st.pop[k]
			inc += st.income[k]
			if e.inc_src.size() >= (k + 1) * JCEconomy.SRC_N:
				for s: int in JCEconomy.SRC_N:
					src[s] += e.inc_src[k * JCEconomy.SRC_N + s]
			liv += st.living[k] * w
			com += st.comfort[k] * w
			unr += st.unrest[k] * w
			sup += JCMath.mulppm(st.pop[k], g.sim.econ.work_ppm(c))
			emp += mini(st.employed[k], JCMath.mulppm(st.pop[k], g.sim.econ.work_ppm(c)))
			for n: int in N:
				needs[n] += st.sat[k * N + n] * w
		var pw: int = maxi(1, pop / 1000)
		var need_list: Array = []
		for n2: int in N:
			if ct.need_active(n2, st.era) and ct.n_qty[n2 * C + c] > 0:
				# 分组（民生页按组排图标）：温饱、衣食住用、讲究、新时代才有的
				var grp: String = "ess" if ct.n_ess[n2] == 1 else ("new" if ct.n_era[n2] > 1 else
						("daily" if ct.n_weight[n2] >= 3 else "fine"))
				need_list.append({"need": ct.n_id[n2], "name": ct.n_name[n2], "sat": needs[n2] / pw,
						"essential": ct.n_ess[n2] == 1, "group": grp, "weight": ct.n_weight[n2]})
		classes.append({"class": ct.c_id[c], "name": ct.c_name[c], "note": ct.c_note[c], "pop": pop,
				"income_pc": inc / pw, "src": Array(src), "living": liv / pw, "comfort": com / pw, "unrest": unr / pw,
				"support": st.support[c], "unemp": PPM - JCMath.ratio_ppm(emp, maxi(1, sup)), "needs": need_list})
	var hot: Array = []
	for h: Dictionary in g.analyst.hotspots(5):
		hot.append({"region": h["region"], "class": h["class"], "living": h["living"], "unrest": h["unrest"],
				"unemp": h["unemp"], "cause": h["cause"], "pop": h["pop"]})
	# 民心地图：每个地区、每个阶层一格
	var cells: Array = []
	for h2: Dictionary in g.analyst.hotspots(ct.r_n * C):
		cells.append({"region": h2["region"], "class": h2["class"], "living": h2["living"], "unrest": h2["unrest"],
				"unemp": h2["unemp"], "cause": h2["cause"], "pop": h2["pop"]})
	return {"classes": classes, "expect": e.expect_mult(), "legitimacy": st.legitimacy, "regions": regions(),
			"hotspots": hot, "cells": cells, "world_era": st.world_era, "era": st.era}


# ════════════════════════════ 外贸 ════════════════════════════════════════
func trade() -> Dictionary:
	var ct: JCContent = g.ct
	var st: JCState = g.st
	var e: JCEconomy = g.sim.econ
	var partners: Array = []
	for p: int in ct.partners.size():
		var pd: Dictionary = ct.partners[p]
		var wants: Array = []
		for gk: Variant in pd.get("wants", {}).keys():
			var gi: int = int(ct.gidx.get(String(gk), -1))
			if gi < 0:
				continue
			wants.append({"good": String(gk), "name": ct.g_name[gi], "price": e.export_price(p, gi),
					"home": st.price[gi], "cap": int(pd["wants"][gk][1])})
		var offers: Array = []
		for gk2: Variant in pd.get("offers", {}).keys():
			var gi2: int = int(ct.gidx.get(String(gk2), -1))
			if gi2 < 0:
				continue
			offers.append({"good": String(gk2), "name": ct.g_name[gi2], "price": e.import_price(p, gi2),
					"home": st.price[gi2], "cap": int(pd["offers"][gk2][1])})
		partners.append({"partner": String(pd["id"]), "name": String(pd["name"]), "desc": String(pd.get("desc", "")),
				"art": String(pd.get("art", "")), "route": String(pd.get("route", "sea")), "active": st.p_active[p] == 1,
				"appear_era": int(pd.get("appear_era", 1)), "dev": st.p_dev[p], "era": e.partner_era(p),
				"relation": st.p_rel[p], "treaty": st.p_treaty[p] == 1, "treaty_cost": g.sim.cmd.treaty_cost(p),
				"exports": st.p_exp[p], "imports": st.p_imp[p], "wants": wants, "offers": offers})
	# 运力取上一季结算记下的（读档后经济步还没跑，e 上的临时量是 0）
	var lt: Dictionary = st.last
	return {"partners": partners, "sea_cap": int(lt.get("sea_cap", e.cap_sea)), "sea_used": int(lt.get("sea_used", e.used_sea)),
			"land_cap": int(lt.get("land_cap", e.cap_land)), "land_used": int(lt.get("land_used", e.used_land)), "customs": st.tax_customs_ppm, "world_era": st.world_era, "era": st.era}


# ════════════════════════════ 纪事 ════════════════════════════════════════
func chronicle(limit: int = 200) -> Array:
	var st: JCState = g.st
	var out: Array = []
	var n: int = st.chron.size()
	for i: int in range(n - 1, maxi(-1, n - 1 - limit), -1):
		out.append(st.chron[i])
	return out


## 国史：大事（新的在前），每条带上配图的来历（内容表里的图给路径，按约定命名的图给类型与 id），
## 以及逐年的统计（给年代评语与小曲线）。
## 每条：{q, year, season, kind, key, args, big, tone, art_path, art_type, art_id}
func annals() -> Dictionary:
	var ct: JCContent = g.ct
	var st: JCState = g.st
	var out: Array = []
	# 世界进入各时代的那一季（判断本国是不是领先世界进入新时代）
	var world_q: Dictionary = {}
	for e0: Dictionary in st.annals:
		if String(e0["key"]) == "chron.world_era":
			var we: int = int((e0.get("args", {}) as Dictionary).get("era", 0))
			if not world_q.has(we):
				world_q[we] = int(e0["q"])
	for i: int in range(st.annals.size() - 1, -1, -1):
		var e: Dictionary = st.annals[i]
		var key: String = String(e["key"])
		var a: Dictionary = e.get("args", {})
		var qq: int = int(e["q"])
		@warning_ignore("integer_division")
		var yy: int = st.start_year + qq / 4
		var it: Dictionary = {"q": qq, "year": yy, "season": qq % 4,
				"kind": String(e["kind"]), "key": key, "args": a, "big": false, "tone": "text.secondary",
				"art_path": "", "art_type": "", "art_id": ""}
		if String(e["kind"]) == "milestone":
			it["big"] = true
			it["tone"] = "teal.core"
			it["art_type"] = "milestone"
			it["art_id"] = String(a.get("art", ""))
		match key:
			"chron.era_enter":
				var en: int = int(a.get("era", 1))
				it["big"] = true
				it["tone"] = "teal.core"
				it["art_path"] = String(ct.eras[en - 1].get("art", "")) if en >= 1 and en <= ct.eras.size() else ""
				# 比世界先进这个时代：换成「领先世界」那张（本国新物博览会）
				if en >= 2 and (not world_q.has(en) or int(world_q[en]) > qq):
					it["art_path"] = ""
					it["art_type"] = "milestone"
					it["art_id"] = "lead_era"
			"chron.world_era":
				it["big"] = true
				it["art_type"] = "milestone"
				it["art_id"] = "world_era%d" % int(a.get("era", 2))
			"chron.landmark_done":
				it["big"] = true
				it["tone"] = "teal.core"
				var l: int = -1
				for li: int in ct.landmarks.size():
					if String(ct.landmarks[li]["id"]) == String(a.get("landmark", "")):
						l = li
				it["art_path"] = String(ct.landmarks[l].get("art", "")) if l >= 0 else ""
			"chron.event_answered":
				it["tone"] = "ochre.core"
				var ev: int = -1
				for ei: int in ct.events.size():
					if String(ct.events[ei]["id"]) == String(a.get("event", "")):
						ev = ei
				it["art_path"] = String(ct.events[ev].get("art", "")) if ev >= 0 else ""
			"chron.crisis_up":
				it["big"] = true
				it["tone"] = "ochre.hot"
				it["art_type"] = "milestone"
				it["art_id"] = ["bankruptcy", "revolt", "mandate_shaken"][clampi(int(a.get("track", 0)), 0, 2)]
				if int(a.get("track", 0)) == 1 and String(a.get("why", "")) == "hunger":
					it["art_id"] = "famine"
			"chron.crisis_down":
				it["tone"] = "teal.core"
			"chron.game_over":
				it["big"] = true
				var why: String = String(a.get("reason", "complete"))
				it["tone"] = "teal.core" if why == "complete" else "ochre.hot"
				it["art_type"] = "milestone"
				it["art_id"] = "complete_2000" if why == "complete" else "gameover_" + why
			"chron.tech_done":
				it["art_type"] = "tech"
				it["art_id"] = String(a.get("tech", ""))
			"chron.decree":
				it["art_type"] = "decree"
				it["art_id"] = String(a.get("decree", ""))
				# 改政体是大事：大卡，配「政体更替」
				if String(a.get("decree", "")) == "regime":
					it["big"] = true
					it["tone"] = "teal.core"
					it["art_type"] = "milestone"
					it["art_id"] = "regime_change"
			"chron.treaty":
				it["art_type"] = "milestone"
				it["art_id"] = "treaty"
			"chron.partner_appear":
				for p: int in ct.partners.size():
					if String(ct.partners[p]["id"]) == String(a.get("partner", "")):
						it["art_path"] = String(ct.partners[p].get("art", ""))
		out.append(it)
	return {"list": out, "hist": st.hist, "start_year": st.start_year, "year": st.year(), "era": st.era,
			"world_era": st.world_era, "end_year": int(ct.scenario.get("end_year", 2000))}


func steward_log(limit: int = 120) -> Array:
	var recs: Array = g.steward.records
	var out: Array = []
	for i: int in range(recs.size() - 1, maxi(-1, recs.size() - 1 - limit), -1):
		out.append(recs[i])
	return out


## 待决事件：名字、说明、配图、各选项（花费、效果、民心）。
func pending_events() -> Array:
	var ct: JCContent = g.ct
	var out: Array = []
	for pe: Dictionary in g.st.pend:
		var ed: Dictionary = ct.events[int(pe["e"])]
		var r: int = int(pe["r"])
		var opts: Array = []
		for o: Dictionary in ed.get("options", []):
			opts.append({"text": String(o.get("text", "")), "cost": int(o.get("cost_li", 0)), "effects": o.get("effects", []),
					"support": o.get("support", {}), "duration": int(o.get("duration", 0))})
		out.append({"event": String(ed["id"]), "name": String(ed["name"]), "text": String(ed.get("text", "")),
				"art": String(ed.get("art", "")), "region": ct.r_id[r] if r >= 0 else "", "until": int(pe["until"]),
				"options": opts})
	return out


## 时代与地标：各时代门槛、本国与世界时代、可建的地标。
func eras() -> Dictionary:
	var ct: JCContent = g.ct
	var st: JCState = g.st
	var list: Array = []
	for i: int in ct.eras.size():
		var ed: Dictionary = ct.eras[i]
		list.append({"id": int(ed["id"]), "name": String(ed["name"]), "subtitle": String(ed.get("subtitle", "")),
				"art": String(ed.get("art", "")), "reached_q": st.era_q[i + 1] if st.era_q.size() > i + 1 else -1,
				"world_q": st.world_era_q[i + 1] if st.world_era_q.size() > i + 1 else -1,
				"led": st.led.size() > i + 1 and st.led[i + 1] == 1})
	var lms: Array = []
	for l: int in ct.landmarks.size():
		var ld: Dictionary = ct.landmarks[l]
		lms.append({"id": String(ld["id"]), "name": String(ld["name"]), "era": int(ld["era"]), "kind": String(ld.get("kind", "")),
				"desc": String(ld.get("desc", "")), "art": String(ld.get("art", "")), "cost": int(ld["cost_li"]),
				"state": st.l_state[l], "progress": st.l_prog[l], "need_q": int(ld["build_q"]),
				"region": ct.r_id[st.l_region[l]] if st.l_state[l] > 0 else "",
				"full_ok": g.sim.world.landmark_check(l, true) == "", "lite_ok": g.sim.world.landmark_check(l, false) == "",
				"why": g.sim.world.landmark_check(l, false)})
	return {"eras": list, "era": st.era, "world_era": st.world_era, "landmarks": lms, "plan": g.analyst.era_plan()}
