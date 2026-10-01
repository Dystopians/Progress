## v2 顾问（docs/57 §12）：户部、工部、学政、民政、市舶五位，按局面提出中肯建议。
##
## 每条建议：{id, ministry, sev（1 留意 / 2 要紧 / 3 紧急）, title, body, slots, cmds, cost_li, score}
##   title/body 是文案键（界面渲染），slots 的约定同 JCSteward；cmds 是「照此办理」要下的命令。
## 同时最多呈上三条（紧急优先）；玩家「不必再提」的建议，同一件事八季内不再提。
## 顾问与托管用同一套分析（JCAnalyst），所以顾问说的就是托管会做的。
class_name JCAdvisors
extends RefCounted

const PPM: int = 1_000_000
const MINISTRIES: PackedStringArray = ["hubu", "gongbu", "xuezheng", "minzheng", "shibo"]
const SHOW_MAX: int = 3

var items: Array = []
## 建议 id → 到第几季之前不再提
var dismissed: Dictionary = {}


func to_dict() -> Dictionary:
	return {"dismissed": dismissed.duplicate()}


func from_dict(d: Dictionary) -> void:
	dismissed = (d.get("dismissed", {}) as Dictionary).duplicate()


func dismiss(id: String, q: int, quarters: int = 8) -> void:
	dismissed[id] = q + quarters


## 当前最该看的几条。
func top(n: int = SHOW_MAX) -> Array:
	return items.slice(0, n)


func find(id: String) -> Dictionary:
	for it: Dictionary in items:
		if String(it["id"]) == id:
			return it
	return {}


func refresh(sim: JCSim, an: JCAnalyst) -> void:
	var st: JCState = sim.st
	var all: Array = []
	all.append_array(_hubu(sim, an))
	all.append_array(_gongbu(sim, an))
	all.append_array(_xuezheng(sim, an))
	all.append_array(_minzheng(sim, an))
	all.append_array(_shibo(sim, an))
	var keep: Array = []
	for it: Dictionary in all:
		if int(dismissed.get(String(it["id"]), -1)) > st.q:
			continue
		# 命令要能办；办不了的建议降为「留意」、不给按钮
		var cmds: Array = it.get("cmds", [])
		var ok_cmds: Array = []
		for c: Variant in cmds:
			if typeof(c) == TYPE_DICTIONARY and bool(sim.cmd.check(c).get("ok", false)):
				ok_cmds.append(c)
		it["cmds"] = ok_cmds
		it["score"] = int(it["sev"]) * 1_000_000 + int(it.get("weight", 0))
		keep.append(it)
	keep.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["score"]) > int(b["score"]) or (int(a["score"]) == int(b["score"]) and String(a["id"]) < String(b["id"])))
	items = keep
	# 过期的「不必再提」清掉
	for k: Variant in dismissed.keys():
		if int(dismissed[k]) <= st.q:
			dismissed.erase(k)


func _item(ministry: String, id: String, sev: int, title: String, body: String, slots: Dictionary, cmds: Array,
		weight: int = 0, cost: int = 0) -> Dictionary:
	var c2: Array = []
	for c: Variant in cmds:
		if typeof(c) == TYPE_DICTIONARY:
			var d: Dictionary = (c as Dictionary).duplicate()
			d["source"] = "advisor:" + ministry
			c2.append(d)
	return {"id": ministry + "." + id, "ministry": ministry, "sev": sev, "title": title, "body": body, "slots": slots,
			"cmds": c2, "weight": clampi(weight, 0, 999_999), "cost_li": cost}


# ── 户部：钱粮 ──────────────────────────────────────────────────────────
func _hubu(sim: JCSim, an: JCAnalyst) -> Array:
	var st: JCState = sim.st
	var ct: JCContent = sim.ct
	var out: Array = []
	var f: Dictionary = an.fiscal()
	var reg: int = maxi(1, int(f["regular"]))
	if st.arrears > 0:
		out.append(_item("hubu", "arrears", 3, "adv.hubu.arrears.t", "adv.hubu.arrears.b",
				{"arrears_li": st.arrears, "debt_li": st.debt}, [], 500_000))
	if int(f["balance"]) < 0 and int(f["runway_q"]) < 10:
		var cmds: Array = []
		var peasant: int = int(ct.cidx.get("peasant", 0))
		if st.tax_land_ppm < 110_000 and st.support[peasant] >= 450_000:
			cmds.append({"kind": "tax", "tax": "land", "value": st.tax_land_ppm + 10_000})
		elif st.budget[JCState.BUD_COURT] > 700_000:
			cmds.append({"kind": "budget", "line": JCState.BUD_COURT, "level": st.budget[JCState.BUD_COURT] - 200_000})
		var sev: int = 3 if int(f["runway_q"]) < 4 else 2
		out.append(_item("hubu", "deficit", sev, "adv.hubu.deficit.t", "adv.hubu.deficit.b",
				{"runway": int(f["runway_q"]), "deficit_li": -int(f["balance"])}, cmds, 400_000 - int(f["runway_q"]) * 10_000))
	if int(f["hidden_ppm"]) > 180_000:
		var cmds2: Array = []
		var sv: int = int(ct.didx.get("land_survey", -1))
		if sv >= 0 and st.d_level[sv] == 0:
			cmds2.append({"kind": "decree", "decree": "land_survey", "level": 1})
		var t: int = int(ct.tidx.get("survey", -1))
		if t >= 0 and st.t_done[t] != 1:
			cmds2.append({"kind": "research", "tech": "survey"})
		out.append(_item("hubu", "hidden", 2, "adv.hubu.hidden.t", "adv.hubu.hidden.b",
				{"hidden_ppm": int(f["hidden_ppm"])}, cmds2, int(f["hidden_ppm"]) / 2))
	if st.debt > int(f["rev"]) * 6:
		var cmds3: Array = []
		if st.treasury > reg * 4 and st.debt > 0:
			cmds3.append({"kind": "repay", "amount": mini(st.debt, st.treasury - reg * 4)})
		out.append(_item("hubu", "debt", 2, "adv.hubu.debt.t", "adv.hubu.debt.b",
				{"debt_li": st.debt, "interest_li": int(f["interest_q"])}, cmds3, 200_000))
	if st.treasury > reg * 12 and int(f["balance"]) >= 0:
		var cmds4: Array = []
		var sh: Array = an.shortages(1)
		if not sh.is_empty() and not (sh[0]["fix"] as Dictionary).is_empty():
			cmds4.append(sh[0]["fix"]["cmd"])
		out.append(_item("hubu", "idle_silver", 1, "adv.hubu.idle.t", "adv.hubu.idle.b",
				{"treasury_li": st.treasury, "quarters": st.treasury / reg}, cmds4, 100_000))
	return out


# ── 工部：营造与产业 ────────────────────────────────────────────────────
func _gongbu(sim: JCSim, an: JCAnalyst) -> Array:
	var ct: JCContent = sim.ct
	var out: Array = []
	var shs: Array = an.shortages(3)
	for i: int in shs.size():
		var sh: Dictionary = shs[i]
		var g: int = int(sh["g"])
		var fix: Dictionary = sh["fix"]
		var essential: bool = JCSteward._is_livelihood_good(ct, g)
		var sev: int = 2 if (essential or int(sh["gap_ppm"]) > 250_000) else 1
		var slots: Dictionary = {"good": ct.g_id[g], "gap_ppm": int(sh["short_ppm"]), "price_ppm": int(sh["price_ppm"])}
		var cmds: Array = []
		var body: String = "adv.gongbu.shortage.b_none"
		if not fix.is_empty():
			slots["building"] = fix["building"]
			slots["region"] = fix["region"]
			slots["cost_li"] = int(fix["cost"])
			cmds.append(fix["cmd"])
			body = "adv.gongbu.shortage.b"
		out.append(_item("gongbu", "short." + ct.g_id[g], sev, "adv.gongbu.shortage.t", body, slots, cmds,
				mini(900_000, int(sh["value"]) / 10_000), int(fix.get("cost", 0))))
	var needs: Array = an.infra_needs()
	var seen: Dictionary = {}
	for nd: Dictionary in needs:
		var bid: String = String(nd["building"])
		if seen.has(bid) or seen.size() >= 2:
			continue
		seen[bid] = true
		var sev2: int = 2 if int(nd["pressure"]) > 1_300_000 else 1
		out.append(_item("gongbu", "infra." + bid + "." + String(nd["region"]), sev2, String(nd["key"]) + ".t",
				String(nd["key"]) + ".b", {"building": bid, "region": nd["region"], "cost_li": int(nd["cost"])},
				[nd["cmd"]], mini(900_000, int(nd["pressure"]) / 4), int(nd["cost"])))
	var obs: Array = an.obsolete(3)
	if not obs.is_empty() and int(obs[0]["roi_ppm"]) > 150_000:
		var ob: Dictionary = obs[0]
		out.append(_item("gongbu", "upgrade." + String(ob["building"]), 1, "adv.gongbu.upgrade.t", "adv.gongbu.upgrade.b",
				{"building": ob["building"], "region": ob["region"], "method": ob["to"], "roi_ppm": int(ob["roi_ppm"]),
				"cost_li": int(ob["cost"]), "count": obs.size()}, [ob["cmd"]], mini(900_000, int(ob["roi_ppm"]) / 2),
				int(ob["cost"])))
	var gl: Array = an.gluts(1)
	if not gl.is_empty() and int(gl[0]["price_ppm"]) < 700_000:
		out.append(_item("gongbu", "glut." + String(gl[0]["id"]), 1, "adv.gongbu.glut.t", "adv.gongbu.glut.b",
				{"good": gl[0]["id"], "price_ppm": int(gl[0]["price_ppm"])}, [], 50_000))
	return out


# ── 学政：读书、研究与时代 ──────────────────────────────────────────────
func _xuezheng(sim: JCSim, an: JCAnalyst) -> Array:
	var st: JCState = sim.st
	var ct: JCContent = sim.ct
	var out: Array = []
	if st.focus < 0:
		var t: int = an.best_research("era")
		if t >= 0:
			out.append(_item("xuezheng", "focus", 2, "adv.xue.focus.t", "adv.xue.focus.b",
					{"tech": ct.t_id[t], "points": st.points}, [{"kind": "research", "tech": ct.t_id[t]}], 600_000))
	var ep: Dictionary = an.era_plan()
	var parts: Array = []
	for it: Dictionary in ep.get("items", []):
		parts.append(it)
	if not parts.is_empty():
		var first: Dictionary = parts[0]
		var cmds: Array = []
		if first.has("cmd"):
			cmds.append(first["cmd"])
		out.append(_item("xuezheng", "era", 1, "adv.xue.era.t", "adv.xue.era.b",
				{"era": st.era + 1, "left": parts.size(), "first_kind": String(first["kind"]), "first": String(first["id"])},
				cmds, 300_000))
	var so: Dictionary = sim.world.era_gap_report().get("social", {})
	if so.has("literacy"):
		var pr: Array = so["literacy"]
		if int(pr[0]) < int(pr[1]):
			var cmds2: Array = []
			for it2: Dictionary in ep.get("items", []):
				if String(it2["kind"]) == "social" and it2.has("cmd"):
					cmds2.append(it2["cmd"])
			out.append(_item("xuezheng", "literacy", 1, "adv.xue.literacy.t", "adv.xue.literacy.b",
					{"have_ppm": int(pr[0]), "need_ppm": int(pr[1])}, cmds2, 200_000))
	return out


# ── 民政：温饱与民心 ────────────────────────────────────────────────────
func _minzheng(sim: JCSim, an: JCAnalyst) -> Array:
	var st: JCState = sim.st
	var ct: JCContent = sim.ct
	var out: Array = []
	var staple: int = int(ct.nidx.get("staple", 0))
	var worst: int = PPM
	var worst_r: int = 0
	for k: int in st.pop.size():
		if st.pop[k] > 0 and st.sat[k * ct.n_n + staple] < worst:
			worst = st.sat[k * ct.n_n + staple]
			worst_r = k / ct.c_n
	if worst < 900_000:
		var cmds: Array = []
		var fr: int = int(ct.didx.get("famine_relief", -1))
		if fr >= 0 and st.d_level[fr] == 0:
			cmds.append({"kind": "decree", "decree": "famine_relief", "level": 1})
		if st.budget[JCState.BUD_RELIEF] < 1_500_000:
			cmds.append({"kind": "budget", "line": JCState.BUD_RELIEF, "level": 1_500_000})
		out.append(_item("minzheng", "hunger", 3, "adv.min.hunger.t", "adv.min.hunger.b",
				{"region": ct.r_id[worst_r], "pct": worst}, cmds, 800_000))
	for hs: Dictionary in an.hotspots(2):
		if int(hs["unrest"]) < 300_000:
			continue
		var cause: String = String(hs["cause"])
		var cmds2: Array = []
		match cause:
			"cause.tax":
				if st.tax_land_ppm > 70_000:
					cmds2.append({"kind": "tax", "tax": "land", "value": st.tax_land_ppm - 10_000})
			"cause.jobless":
				var job: Dictionary = _job_build(sim, an, int(hs["r"]), int(hs["c"]))
				if not job.is_empty():
					cmds2.append(job)
			"cause.hunger":
				pass
			_:
				if st.budget[JCState.BUD_RELIEF] < 1_500_000:
					cmds2.append({"kind": "budget", "line": JCState.BUD_RELIEF, "level": 1_500_000})
		# 失业那半句只在跟失业有关时才说（士绅没有失业一说，写「失业 0%」反而让人糊涂）
		var sl2: Dictionary = {"region": hs["region"], "class": hs["class"], "unrest_ppm": int(hs["unrest"]), "cause": cause}
		if cause == "cause.jobless" or int(hs["unemp"]) >= 50_000:
			sl2["unemp_ppm"] = int(hs["unemp"])
		out.append(_item("minzheng", "unrest.%s.%s" % [hs["region"], hs["class"]], 2, "adv.min.unrest.t",
				"adv.min.unrest.b", sl2, cmds2, int(hs["unrest"]) / 2))
	# 威信不到五成：推荐每两银子换来威信最多的长期政令（与托管用的是同一份清单）
	if st.legitimacy < 500_000:
		var sds: Array = an.support_decrees()
		if not sds.is_empty():
			var sd: Dictionary = sds[0]
			var sl: Dictionary = {"decree": sd["decree"], "gain_ppm": int(sd["gain_ppm"]), "legit_ppm": st.legitimacy}
			if int(sd["cost_q"]) > 0:
				sl["cost_li"] = int(sd["cost_q"])
			out.append(_item("minzheng", "support." + String(sd["decree"]), 2 if st.legitimacy < 400_000 else 1,
					"adv.min.support.t", "adv.min.support.b", sl, [sd["cmd"]], 300_000 + (500_000 - st.legitimacy),
					int(sd["cost_q"])))
	var sev: int = st.cr_stage[JCState.CR_LIVELIHOOD] if st.cr_stage.size() > JCState.CR_LIVELIHOOD else 0
	if sev >= 2:
		out.append(_item("minzheng", "crisis", 3, "adv.min.crisis.t", "adv.min.crisis.b", {"stage": sev}, [], 900_000))
	return out


## 给某地区某阶层找份活计：在该地区最赚钱、用这个阶层的作坊。
func _job_build(sim: JCSim, an: JCAnalyst, r: int, c: int) -> Dictionary:
	var ct: JCContent = sim.ct
	var best: Dictionary = {}
	var best_roi: int = 0
	for b: int in ct.b_n:
		if ct.b_cat[b] != JCContent.CAT_WORKSHOP and ct.b_cat[b] != JCContent.CAT_MINE:
			continue
		if not sim.inv.building_unlocked(b) or (ct.b_owners[b] & 2) == 0:
			continue
		for m: int in sim.inv.current_methods(b):
			if ct.m_labor[m * ct.c_n + c] <= 0:
				continue
			var rep: Dictionary = an.site_report(b, m, r)
			if String(rep["block"]) != "":
				continue
			var roi: int = int(rep["roi_ppm"])
			if roi > best_roi:
				best_roi = roi
				best = rep["cmd"]
	return best


# ── 市舶：外贸 ──────────────────────────────────────────────────────────
func _shibo(sim: JCSim, an: JCAnalyst) -> Array:
	var st: JCState = sim.st
	var ct: JCContent = sim.ct
	var out: Array = []
	for nd: Dictionary in an.infra_needs():
		if String(nd["building"]) == "port" or String(nd["building"]) == "caravanserai":
			out.append(_item("shibo", "cap." + String(nd["building"]), 2, String(nd["key"]) + ".t", String(nd["key"]) + ".b",
					{"building": nd["building"], "region": nd["region"], "cost_li": int(nd["cost"])}, [nd["cmd"]], 400_000,
					int(nd["cost"])))
	var tcs: Array = an.treaty_candidates()
	if not tcs.is_empty():
		var tc: Dictionary = tcs[0]
		if int(tc["volume_q"]) * 4 >= int(tc["cost"]) / 2:
			out.append(_item("shibo", "treaty." + String(tc["partner"]), 1, "adv.shibo.treaty.t", "adv.shibo.treaty.b",
					{"partner": tc["partner"], "cost_li": int(tc["cost"]), "volume_li": int(tc["volume_q"])}, [tc["cmd"]],
					150_000, int(tc["cost"])))
	if st.world_era > st.era:
		var cmds: Array = []
		var fl: int = int(ct.didx.get("foreign_learning", -1))
		if fl >= 0 and st.d_level[fl] == 0:
			cmds.append({"kind": "decree", "decree": "foreign_learning", "level": 1})
		out.append(_item("shibo", "world_ahead", 2, "adv.shibo.ahead.t", "adv.shibo.ahead.b",
				{"world_era": st.world_era, "era": st.era}, cmds, 500_000))
	return out
