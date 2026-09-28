## v2 轻托管（docs/57 §11）：玩家把不想反复操心的事交给各部门按「取向」代办。
##
## 六个领域：研究、营造、改造、财政、外贸、事件。每个领域三种模式：
##   OFF  手动：托管不动手（顾问照常提建议）
##   ASK  拟办：每季拟好命令，玩家一键批准或逐条驳回
##   AUTO 代办：季末自动执行，结果与理由写进托管记录
## 托管只发普通命令（与玩家一样经 JCCommands 受理），不会绕过任何规则；每条都带理由键与槽位。
## 槽位约定（界面据此格式化）：building / region / good / tech / partner / decree / event / method / class
## 为内容 ID；以 _li 结尾是钱（厘），以 _ppm 结尾是比例，其余是整数。
class_name JCSteward
extends RefCounted

const PPM: int = 1_000_000
const OFF: int = 0
const ASK: int = 1
const AUTO: int = 2
const DOMAINS: PackedStringArray = ["research", "build", "modernize", "fiscal", "trade", "events"]
const STANCES: Dictionary = {
	"research": ["era", "balanced", "agri", "industry", "commerce", "culture"],
	"build": ["balanced", "shortage", "livelihood", "growth", "era"],
	"modernize": ["profit", "all", "careful"],
	"fiscal": ["balanced", "steady", "light"],
	"trade": ["balanced", "open", "protect"],
	"events": ["people", "frugal", "growth"],
}
## 每季至多几条（营造与改造各自计）
const MAX_BUILD_Q: int = 2
const MAX_MOD_Q: int = 2

var mode: Dictionary = {}
var stance: Dictionary = {}
## 托管记录：{q, domain, cmd, reason, slots, ok, why}
var records: Array = []
## 冷却：键 → 到第几季之前不再重复
var cool: Dictionary = {}


func _init() -> void:
	for d: String in DOMAINS:
		mode[d] = OFF
		stance[d] = String(STANCES[d][0])


func to_dict() -> Dictionary:
	return {"mode": mode.duplicate(), "stance": stance.duplicate(), "log": records.slice(maxi(0, records.size() - 300)),
			"cool": cool.duplicate()}


func from_dict(d: Dictionary) -> void:
	var m: Dictionary = d.get("mode", {})
	var s: Dictionary = d.get("stance", {})
	for dom: String in DOMAINS:
		mode[dom] = int(m.get(dom, OFF))
		var sv: String = String(s.get(dom, STANCES[dom][0]))
		stance[dom] = sv if (STANCES[dom] as Array).has(sv) else String(STANCES[dom][0])
	records = (d.get("log", []) as Array).duplicate(true)
	cool = (d.get("cool", {}) as Dictionary).duplicate()


func set_mode(domain: String, m: int) -> bool:
	if not DOMAINS.has(domain) or m < OFF or m > AUTO:
		return false
	mode[domain] = m
	return true


func set_stance(domain: String, s: String) -> bool:
	if not DOMAINS.has(domain) or not (STANCES[domain] as Array).has(s):
		return false
	stance[domain] = s
	return true


func any_on() -> bool:
	for d: String in DOMAINS:
		if int(mode[d]) != OFF:
			return true
	return false


func _cooling(key: String, q: int) -> bool:
	return int(cool.get(key, -1)) > q


func _cool(key: String, q: int, quarters: int) -> void:
	cool[key] = q + quarters


func _p(domain: String, cmd: Dictionary, reason: String, slots: Dictionary) -> Dictionary:
	var c: Dictionary = cmd.duplicate()
	c["source"] = "steward:" + domain
	return {"domain": domain, "cmd": c, "reason": reason, "slots": slots}


# ════════════════════════════ 拟办 ════════════════════════════════════════
## 为处在 which 模式（ASK 或 AUTO）的各领域拟命令。不改状态（冷却在执行时才记）。
func plan(sim: JCSim, an: JCAnalyst, which: int) -> Array:
	var out: Array = []
	for d: String in DOMAINS:
		if int(mode[d]) != which:
			continue
		match d:
			"research":
				out.append_array(_research(sim, an))
			"build":
				out.append_array(_build(sim, an))
			"modernize":
				out.append_array(_modernize(sim, an))
			"fiscal":
				out.append_array(_fiscal(sim, an))
			"trade":
				out.append_array(_trade(sim, an))
			"events":
				out.append_array(_events(sim, an))
	return out


## 执行后记账：写托管记录、记冷却。
func record(sim: JCSim, prop: Dictionary, result: Dictionary) -> void:
	var q: int = sim.st.q
	var ok: bool = bool(result.get("ok", false))
	records.append({"q": q, "domain": prop["domain"], "cmd": prop["cmd"], "reason": prop["reason"],
			"slots": prop["slots"], "ok": ok, "why": String(result.get("reason", ""))})
	if records.size() > 400:
		records = records.slice(records.size() - 300)
	var key: String = String(prop.get("slots", {}).get("_cool", ""))
	if key != "":
		_cool(key, q, int(prop["slots"].get("_cool_q", 4)))


# ── 研究 ────────────────────────────────────────────────────────────────
func _research(sim: JCSim, an: JCAnalyst) -> Array:
	var st: JCState = sim.st
	if st.focus >= 0 and sim.world.tech_available(st.focus):
		return []
	var t: int = an.best_research(String(stance["research"]))
	if t < 0:
		return []
	var why: String = "stw.research.pick"
	var rep: Dictionary = sim.world.era_gap_report()
	for tid: Variant in rep.get("techs", []):
		var t0: int = int(sim.ct.tidx.get(String(tid), -1))
		if t0 >= 0 and an.tech_path(t0).has(t):
			why = "stw.research.era"
			break
	var bg: int = sim.world.bg_domestic(t) + sim.world.bg_foreign(t)
	return [_p("research", {"kind": "research", "tech": sim.ct.t_id[t]}, why,
			{"tech": sim.ct.t_id[t], "speed_ppm": bg})]


# ── 营造 ────────────────────────────────────────────────────────────────
## 已经答应、还没付完的官府营造款。
func committed(sim: JCSim) -> int:
	var st: JCState = sim.st
	var tot: int = 0
	for i: int in st.stack_count():
		if st.s_fund[i] != 0:
			continue
		var total: int = 0
		if st.s_status[i] == JCState.ST_UPGRADE and st.s_target[i] >= 0:
			total = sim.inv.upgrade_cost(i, st.s_target[i])
		elif st.s_pending[i] > 0:
			total = sim.inv.level_cost(st.s_b[i], st.s_m[i], st.s_owner[i] == JCContent.OWNER_GOV) * st.s_pending[i]
		else:
			continue
		var needq: int = maxi(1, st.s_needq[i])
		var left: int = maxi(0, needq * PPM - st.s_prog[i])
		tot += JCMath.muldiv(total, left, needq * PPM)
	return tot


## 这一季还能新答应多少营造款：国库减去留底与已答应的，并按收入封顶。
func build_budget(sim: JCSim, an: JCAnalyst, domain_stance: String) -> int:
	var f: Dictionary = an.fiscal()
	var reg: int = maxi(1, int(f["regular"]))
	var reserve_q: int = 4
	var share: int = 300_000
	match domain_stance:
		"growth", "era":
			reserve_q = 3
			share = 450_000
		"all":
			reserve_q = 3
			share = 400_000
		"careful":
			reserve_q = 6
			share = 150_000
	var avail: int = sim.st.treasury - reg * reserve_q - committed(sim)
	# 按收入封顶；国库积得多时放宽（闲置的银子一半可以拿来营造）
	var cap: int = maxi(JCMath.mulppm(maxi(0, int(f["rev"])), share) * 6, avail / 2)
	return clampi(avail, 0, cap)


func _build(sim: JCSim, an: JCAnalyst) -> Array:
	var st: JCState = sim.st
	var ct: JCContent = sim.ct
	var s: String = String(stance["build"])
	var budget: int = build_budget(sim, an, s)
	if budget <= 0:
		return []
	var cands: Array = []
	# 1) 进入下一时代的标志建筑
	var ep: Dictionary = an.era_plan()
	for it: Dictionary in ep.get("items", []):
		if not it.has("cmd") or String(it["cmd"].get("kind", "")) != "build":
			continue
		# 进入下一时代是全国的大事：均衡取向下也排在最前
		var w: int = 4_000_000 if s == "era" else 2_600_000
		var cost0: int = int(it.get("cost", 0))
		if cost0 <= 0:
			var b0: int = int(ct.bidx.get(String(it["cmd"]["building"]), -1))
			cost0 = sim.inv.level_cost(b0, int(ct.midx.get(String(it["cmd"]["method"]), 0)), true) if b0 >= 0 else 0
		cands.append([w, it["cmd"], "stw.build.era", {"building": String(it["cmd"]["building"]),
				"region": it["cmd"]["region"], "have": int(it["have"]), "need": int(it["need"])}, cost0])
	# 2) 缺口
	for sh: Dictionary in an.shortages(6):
		var fix: Dictionary = sh["fix"]
		if fix.is_empty():
			continue
		var g: int = int(sh["g"])
		var w2: int = 1_000_000 + mini(1_000_000, int(sh["gap_ppm"]))
		if s == "shortage":
			w2 += 1_000_000
		if s == "livelihood" and _is_livelihood_good(ct, g):
			w2 += 1_000_000
		if s == "growth":
			w2 += int(fix["roi_ppm"])
		cands.append([w2, fix["cmd"], "stw.build.shortage", {"good": ct.g_id[g], "building": fix["building"],
				"region": fix["region"], "gap_ppm": int(sh["gap_ppm"])}, int(fix["cost"])])
	# 3) 设施吃紧
	for nd: Dictionary in an.infra_needs():
		var bid: String = String(nd["building"])
		var w3: int = 600_000 + mini(1_000_000, int(nd["pressure"]) / 2)
		if s == "livelihood" and ["school", "clinic", "urbanworks", "granary", "irrigation"].has(bid):
			w3 += 1_000_000
		if s == "growth" and ["market", "carrier", "port", "road", "caravanserai"].has(bid):
			w3 += 800_000
		cands.append([w3, nd["cmd"], "stw.build.infra", {"building": bid, "region": nd["region"],
				"need": String(nd["key"])}, int(nd["cost"])])
	# 4) 失业重的地区：在当地开能用这些闲人的作坊
	for hs: Dictionary in an.hotspots(8):
		if int(hs["unemp"]) < 80_000 or String(hs["class"]) == "gentry":
			continue
		var job: Dictionary = _job_site(sim, an, int(hs["r"]), int(hs["c"]))
		if job.is_empty():
			continue
		var w4: int = 800_000 + mini(1_200_000, int(hs["unemp"]) * 4)
		if s == "livelihood" or s == "growth":
			w4 += 600_000
		cands.append([w4, job["cmd"], "stw.build.jobs", {"building": job["building"], "region": job["region"],
				"class": String(hs["class"]), "unemp_ppm": int(hs["unemp"])}, int(job["cost"])])
	cands.sort_custom(func(a: Array, b: Array) -> bool:
		return int(a[0]) > int(b[0]) or (int(a[0]) == int(b[0]) and str(a[1]) < str(b[1])))
	var out: Array = []
	var used: int = 0
	var seen: Dictionary = {}
	var reg: int = maxi(1, int(an.fiscal()["regular"]))
	var max_n: int = mini(8, MAX_BUILD_Q + st.treasury / (reg * 10))
	# 营造用料（木料、砖瓦、石料、农具……）上季到货不足八成：本季只开一件，免得把料抢光
	if an.build_material_fill() < 800_000:
		max_n = 1
	for c: Array in cands:
		if out.size() >= max_n:
			break
		var cmd: Dictionary = c[1]
		var key: String = "build:%s:%s" % [cmd.get("building", ""), cmd.get("region", "")]
		if seen.has(key) or _cooling(key, st.q):
			continue
		var cost: int = int(c[4])
		if cost <= 0 or used + cost > budget:
			continue
		var chk: Dictionary = sim.cmd.check(cmd)
		if not bool(chk.get("ok", false)):
			continue
		seen[key] = true
		used += cost
		var slots: Dictionary = (c[3] as Dictionary).duplicate()
		slots["cost_li"] = cost
		slots["_cool"] = key
		slots["_cool_q"] = maxi(4, ct.b_build_q[int(ct.bidx.get(String(cmd["building"]), 0))])
		out.append(_p("build", cmd, String(c[2]), slots))
	return out


## 在 r 地区找一门用 c 阶层人手、回报最好的营生（农田、矿、作坊），返回 site_report。
func _job_site(sim: JCSim, an: JCAnalyst, r: int, c: int) -> Dictionary:
	var ct: JCContent = sim.ct
	var best: Dictionary = {}
	var best_score: int = 0
	for b: int in ct.b_n:
		var cat: int = ct.b_cat[b]
		if cat != JCContent.CAT_WORKSHOP and cat != JCContent.CAT_MINE and cat != JCContent.CAT_FARM:
			continue
		if not sim.inv.building_unlocked(b) or (ct.b_owners[b] & 2) == 0:
			continue
		for m: int in sim.inv.current_methods(b):
			var need: int = ct.m_labor[m * ct.c_n + c]
			if need <= 0:
				continue
			# 为了安置人手开农田：作物本来就不贵（价不到九五折）就别再添
			if cat == JCContent.CAT_FARM and not ct.m_out_g[m].is_empty() and an.price_ppm(ct.m_out_g[m][0]) < 950_000:
				continue
			var rep: Dictionary = an.site_report(b, m, r)
			if String(rep["block"]) != "" or int(rep["roi_ppm"]) < 50_000:
				continue
			var glut: bool = false
			for w: Dictionary in rep["warnings"]:
				if String(w["key"]) == "warn.glut" or String(w["key"]) == "warn.input_short":
					glut = true
			if glut:
				continue
			# 回报与用人都看：每两银子能安置多少人
			var score: int = int(rep["roi_ppm"]) + JCMath.muldiv(need, 1_000_000_000, maxi(1, int(rep["cost"])))
			if score > best_score:
				best_score = score
				best = rep
	return best


static func _is_livelihood_good(ct: JCContent, g: int) -> bool:
	for n: int in ct.n_n:
		if (ct.n_ess[n] == 1 or ct.n_weight[n] >= 6) and ct.n_goods[n].has(g):
			return true
	return false


# ── 改造 ────────────────────────────────────────────────────────────────
func _modernize(sim: JCSim, an: JCAnalyst) -> Array:
	var st: JCState = sim.st
	var s: String = String(stance["modernize"])
	var budget: int = build_budget(sim, an, s)
	var out: Array = []
	var used: int = 0
	var min_roi: int = 150_000
	match s:
		"all":
			min_roi = 0
		"careful":
			min_roi = 300_000
	# 合并（打七折）优先
	for mc: Dictionary in an.merge_candidates():
		if out.size() >= MAX_MOD_Q:
			break
		if String(mc["owner"]) != "gov" and s != "all":
			continue
		var key: String = "merge:%s:%s" % [mc["building"], mc["region"]]
		if _cooling(key, st.q) or used + int(mc["cost"]) > budget:
			continue
		if not bool(sim.cmd.check(mc["cmd"]).get("ok", false)):
			continue
		used += int(mc["cost"])
		out.append(_p("modernize", mc["cmd"], "stw.mod.merge", {"building": mc["building"], "region": mc["region"],
				"count": int(mc["stacks"]), "cost_li": int(mc["cost"]), "_cool": key, "_cool_q": 8}))
	for ob: Dictionary in an.obsolete(12):
		if out.size() >= MAX_MOD_Q:
			break
		if int(ob["roi_ppm"]) < min_roi:
			continue
		var key2: String = "up:%d" % int(ob["uid"])
		if _cooling(key2, st.q) or used + int(ob["cost"]) > budget:
			continue
		if not bool(sim.cmd.check(ob["cmd"]).get("ok", false)):
			continue
		used += int(ob["cost"])
		out.append(_p("modernize", ob["cmd"], "stw.mod.upgrade", {"building": ob["building"], "region": ob["region"],
				"method": ob["to"], "roi_ppm": int(ob["roi_ppm"]), "cost_li": int(ob["cost"]), "_cool": key2, "_cool_q": 8}))
	if s != "all":
		for lo: Dictionary in an.losers():
			if out.size() >= MAX_MOD_Q + 1:
				break
			var key3: String = "moth:%d" % int(lo["uid"])
			if _cooling(key3, st.q):
				continue
			out.append(_p("modernize", lo["cmd"], "stw.mod.mothball", {"building": lo["building"], "region": lo["region"],
					"loss_li": int(lo["loss_q"]), "_cool": key3, "_cool_q": 12}))
	return out


# ── 财政 ────────────────────────────────────────────────────────────────
func _fiscal(sim: JCSim, an: JCAnalyst) -> Array:
	var st: JCState = sim.st
	var ct: JCContent = sim.ct
	var s: String = String(stance["fiscal"])
	var f: Dictionary = an.fiscal()
	var out: Array = []
	var reg: int = maxi(1, int(f["regular"]))
	var rev: int = maxi(1, int(f["rev"]))
	var runway_target: int = 8
	var land_cap: int = 110_000
	var land_floor: int = 80_000
	match s:
		"steady":
			runway_target = 12
			land_cap = 120_000
			land_floor = 90_000
		"light":
			runway_target = 6
			land_cap = 100_000
			land_floor = 70_000
	var bal: int = int(f["balance"])
	var q: int = st.q
	var peasant_sup: int = st.support[int(ct.cidx.get("peasant", 0))]
	if bal < 0 and int(f["runway_q"]) < runway_target:
		if st.tax_land_ppm < land_cap and peasant_sup >= 450_000 and not _cooling("tax:land", q):
			var v: int = mini(land_cap, st.tax_land_ppm + 5_000)
			out.append(_p("fiscal", {"kind": "tax", "tax": "land", "value": v}, "stw.fiscal.raise_land",
					{"from_ppm": st.tax_land_ppm, "to_ppm": v, "runway": int(f["runway_q"]), "_cool": "tax:land", "_cool_q": 4}))
		elif st.tax_commerce_ppm < 40_000 and not _cooling("tax:commerce", q):
			var v2: int = mini(40_000, st.tax_commerce_ppm + 5_000)
			out.append(_p("fiscal", {"kind": "tax", "tax": "commerce", "value": v2}, "stw.fiscal.raise_commerce",
					{"from_ppm": st.tax_commerce_ppm, "to_ppm": v2, "_cool": "tax:commerce", "_cool_q": 4}))
		elif st.budget[JCState.BUD_COURT] > 700_000 and not _cooling("bud:court", q):
			var v3: int = st.budget[JCState.BUD_COURT] - 100_000
			out.append(_p("fiscal", {"kind": "budget", "line": JCState.BUD_COURT, "level": v3}, "stw.fiscal.cut_court",
					{"to_ppm": v3, "_cool": "bud:court", "_cool_q": 4}))
		elif int(f["runway_q"]) < 3 and not _cooling("loan", q):
			var amt: int = mini(sim.cmd.loan_limit(), -bal * 4)
			if amt > 0:
				out.append(_p("fiscal", {"kind": "loan", "amount": amt}, "stw.fiscal.loan",
						{"amount_li": amt, "_cool": "loan", "_cool_q": 4}))
	elif bal > JCMath.mulppm(rev, 100_000) and st.treasury > reg * (12 if s == "steady" else 8):
		# 国库积得太多：田赋可以再往下放（银子压在库里，民间就缺钱花）
		if st.treasury > reg * 16:
			land_floor = 30_000
			if st.tax_commerce_ppm > 10_000 and not _cooling("tax:commerce", q):
				var vc: int = maxi(10_000, st.tax_commerce_ppm - 5_000)
				out.append(_p("fiscal", {"kind": "tax", "tax": "commerce", "value": vc}, "stw.fiscal.lower_commerce",
						{"from_ppm": st.tax_commerce_ppm, "to_ppm": vc, "_cool": "tax:commerce", "_cool_q": 4}))
		if st.treasury > reg * 30:
			var rm: int = int(ct.didx.get("tax_remission", -1))
			if rm >= 0 and st.d_level[rm] == 0 and not _cooling("decree:remission", q):
				var cmdr: Dictionary = {"kind": "decree", "decree": "tax_remission", "level": 1}
				if bool(sim.cmd.check(cmdr).get("ok", false)):
					out.append(_p("fiscal", cmdr, "stw.fiscal.remission", {"treasury_li": st.treasury,
							"_cool": "decree:remission", "_cool_q": 8}))
		if st.debt > 0 and not _cooling("repay", q):
			var pay: int = mini(st.debt, st.treasury - reg * 6)
			if pay > 0:
				out.append(_p("fiscal", {"kind": "repay", "amount": pay}, "stw.fiscal.repay",
						{"amount_li": pay, "_cool": "repay", "_cool_q": 2}))
		elif st.tax_land_ppm > land_floor and not _cooling("tax:land", q):
			var step: int = 20_000 if st.treasury > reg * 24 else (10_000 if st.treasury > reg * 16 else 5_000)
			var v4: int = maxi(land_floor, st.tax_land_ppm - step)
			out.append(_p("fiscal", {"kind": "tax", "tax": "land", "value": v4}, "stw.fiscal.lower_land",
					{"from_ppm": st.tax_land_ppm, "to_ppm": v4, "_cool": "tax:land", "_cool_q": 4}))
		else:
			for line: int in JCState.BUD_N:
				if st.budget[line] < PPM and not _cooling("bud:%d" % line, q):
					out.append(_p("fiscal", {"kind": "budget", "line": line, "level": PPM}, "stw.fiscal.restore_budget",
							{"line": line, "_cool": "bud:%d" % line, "_cool_q": 4}))
					break
	# 隐田：清丈
	var sv: int = int(ct.didx.get("land_survey", -1))
	if sv >= 0 and int(f["hidden_ppm"]) > 200_000 and st.d_level[sv] == 0 and not _cooling("decree:land_survey", q):
		var cmd: Dictionary = {"kind": "decree", "decree": "land_survey", "level": 1}
		if bool(sim.cmd.check(cmd).get("ok", false)) and st.treasury > reg * 4:
			out.append(_p("fiscal", cmd, "stw.fiscal.survey", {"hidden_ppm": int(f["hidden_ppm"]),
					"_cool": "decree:land_survey", "_cool_q": 12}))
	# 常平仓
	var gn: int = int(ct.didx.get("ever_normal_granary", -1))
	if gn >= 0 and st.d_level[gn] == 0 and not _cooling("decree:granary", q):
		var cmd2: Dictionary = {"kind": "decree", "decree": "ever_normal_granary", "level": 1}
		if bool(sim.cmd.check(cmd2).get("ok", false)):
			out.append(_p("fiscal", cmd2, "stw.fiscal.granary", {"_cool": "decree:granary", "_cool_q": 16}))
	# 赈济：某地口粮满足不到八成五
	var fr: int = int(ct.didx.get("famine_relief", -1))
	if fr >= 0:
		var worst: int = PPM
		var staple: int = int(ct.nidx.get("staple", 0))
		for k: int in st.pop.size():
			if st.pop[k] > 0:
				worst = mini(worst, st.sat[k * ct.n_n + staple])
		if worst < 850_000 and st.d_level[fr] == 0 and not _cooling("decree:relief", q):
			var cmd3: Dictionary = {"kind": "decree", "decree": "famine_relief", "level": 1}
			if bool(sim.cmd.check(cmd3).get("ok", false)):
				out.append(_p("fiscal", cmd3, "stw.fiscal.relief_on", {"worst_ppm": worst, "_cool": "decree:relief", "_cool_q": 8}))
		elif worst > 970_000 and st.d_level[fr] == 1 and st.q - st.d_since[fr] >= 8 and not _cooling("decree:relief", q):
			var cmd4: Dictionary = {"kind": "decree", "decree": "famine_relief", "level": 0}
			if bool(sim.cmd.check(cmd4).get("ok", false)):
				out.append(_p("fiscal", cmd4, "stw.fiscal.relief_off", {"_cool": "decree:relief", "_cool_q": 8}))
	return out


# ── 外贸 ────────────────────────────────────────────────────────────────
func _trade(sim: JCSim, an: JCAnalyst) -> Array:
	var st: JCState = sim.st
	var s: String = String(stance["trade"])
	var out: Array = []
	var f: Dictionary = an.fiscal()
	var reg: int = maxi(1, int(f["regular"]))
	for tc: Dictionary in an.treaty_candidates():
		var key: String = "treaty:" + String(tc["partner"])
		if _cooling(key, st.q):
			continue
		var worth: bool = int(tc["volume_q"]) * 4 >= int(tc["cost"]) / (1 if s == "open" else 2)
		if worth and st.treasury > int(tc["cost"]) + reg * 4:
			out.append(_p("trade", tc["cmd"], "stw.trade.treaty", {"partner": tc["partner"], "cost_li": int(tc["cost"]),
					"volume_li": int(tc["volume_q"]), "_cool": key, "_cool_q": 8}))
			break
	var want: int = 50_000
	match s:
		"open":
			want = 30_000
		"protect":
			want = 120_000
	if st.tax_customs_ppm != want and not _cooling("tax:customs", st.q):
		var step: int = clampi(want - st.tax_customs_ppm, -10_000, 10_000)
		var v: int = st.tax_customs_ppm + step
		out.append(_p("trade", {"kind": "tax", "tax": "customs", "value": v}, "stw.trade.tariff",
				{"from_ppm": st.tax_customs_ppm, "to_ppm": v, "_cool": "tax:customs", "_cool_q": 4}))
	var sp: int = int(sim.ct.didx.get("sea_policy", -1))
	if sp >= 0:
		var lvl: int = 2 if s == "open" else 1
		if st.d_level[sp] != lvl and not _cooling("decree:sea_policy", st.q):
			var cmd: Dictionary = {"kind": "decree", "decree": "sea_policy", "level": lvl}
			if bool(sim.cmd.check(cmd).get("ok", false)):
				out.append(_p("trade", cmd, "stw.trade.sea_policy", {"level": lvl, "_cool": "decree:sea_policy", "_cool_q": 16}))
	return out


# ── 事件 ────────────────────────────────────────────────────────────────
func _events(sim: JCSim, an: JCAnalyst) -> Array:
	var st: JCState = sim.st
	var ct: JCContent = sim.ct
	var s: String = String(stance["events"])
	var out: Array = []
	var rev: int = maxi(1, int(an.fiscal()["rev"]))
	for pe: Dictionary in st.pend:
		var e: int = int(pe["e"])
		var ed: Dictionary = ct.events[e]
		var opts: Array = ed.get("options", [])
		var best: int = -1
		var best_score: int = -(1 << 62)
		for i: int in opts.size():
			var o: Dictionary = opts[i]
			var cost: int = int(o.get("cost_li", 0))
			if cost > st.treasury:
				continue
			var sup: int = 0
			var sd: Dictionary = o.get("support", {})
			for ck: Variant in sd.keys():
				sup += int(sd[ck])
			var growth: int = 0
			for m: Dictionary in o.get("effects", []):
				var tg: String = String(m.get("target", ""))
				var v: float = float(m.get("value", 0))
				if ["farm_yield", "research_speed", "commerce_cap", "sea_trade_cap", "export_price", "invest_prop"].has(tg):
					growth += int(v)
				elif ["unrest", "mortality", "construction_cost"].has(tg):
					growth -= int(v)
			var cost_pts: int = JCMath.ratio_ppm(cost, rev, 0) / 10_000
			var score: int = 0
			match s:
				"people":
					score = sup * 100 + growth * 20 - cost_pts * 20
				"frugal":
					score = -cost_pts * 200 + sup * 30 + growth * 10
				"growth":
					score = growth * 100 + sup * 30 - cost_pts * 30
			if score > best_score:
				best_score = score
				best = i
		if best >= 0:
			out.append(_p("events", {"kind": "event", "event": String(ed["id"]), "option": best}, "stw.events.pick",
					{"event": String(ed["id"]), "option": best}))
	return out
