## 季度简报：候选风险 → 归并 → 排序 → 最多 3 张诊断卡（docs/20 §7.1.5、docs/21 §2—§3）。
##
## 检测器只读 JwReadModel 与会话历史，产出候选；同一「根键」（域 | 地区或全国 | 子键）合并为一条，
## 被合并者列为「同一限制因素的其他表现」。排序键字典序（紧迫季数 升、可干预条数 降、影响人口 降），
## 整数编码 rank_int 只用于排序与断言，不渲染给玩家（RT-AC-07）。
## 产出、增长与信任类下降只能是 NOTE（经济下滑不是终局风险，§04）。阈值来自界面配置（待参数登记）。
class_name JwDiagnose
extends RefCounted

## 机制域 → 候选政策集（docs/21 §2.4）。
const DOMAIN_POLICIES: Dictionary = {
	"power": [3, 8],
	"employment": [4, 2, 8, 0],
	"housing": [5, 0],
	"finance": [0, 1, 10, 11],
	"service": [9, 5, 4],
	"supply": [6, 7, 8],
	"external": [7, 8],
	"politics": [11, 2],
}

## 域 → 机制 ID 与规则号（展示用标识；规则卡里给出公式原文）。
const DOMAIN_MECH: Dictionary = {
	"power": ["[M-POWER-01]", "^R-PROD-03"],
	"employment": ["[M-LABOR-01]", "^R-PROD-03"],
	"housing": ["[M-HOUSE-01]", "^R-HOUSE-01"],
	"finance": ["[M-FIN-02]", "^R-FIN-02"],
	"service": ["[M-SERV-01]", "^R-SERV-01"],
	"supply": ["[M-CAP-01]", "^R-PROD-03"],
	"external": ["[M-EXT-01]", "^R-EXT-01"],
	"politics": ["[M-POL-01]", "^R-POL-01"],
}


static func run(s: JwSession) -> Dictionary:
	var m: JwReadModel = s.model
	var cat: JwCatalog = s.catalog
	var th: Dictionary = cat.cfg("diag_thresholds", {})
	var cands: Array[Dictionary] = []
	if s.game == null:
		return {"cards": [], "folded": 0, "total": 0}
	_det_binding(s, m, cat, cands)
	_det_maturity(s, m, cat, cands)
	_det_unemployment(s, m, cat, th, cands)
	_det_housing(s, m, cat, th, cands)
	_det_service(s, m, cat, th, cands)
	_det_cash_path(s, m, cat, cands)
	_det_ext_credit(s, m, cat, th, cands)
	_det_output_drop(s, m, cat, th, cands)
	_det_trust_drop(s, m, cat, th, cands)
	# 归并（RB-01..03）：同 root_key 合并，机制层优先，再按排序键。
	var by_root: Dictionary = {}
	for c: Dictionary in cands:
		_finish(c, m, cat)
		var k: String = String(c["root_key"])
		if not by_root.has(k):
			by_root[k] = c
		else:
			var cur: Dictionary = by_root[k]
			if _before(c, cur):
				var man: Array = c.get("manifestations", [])
				man.append({"label": String(cur.get("title", ""))})
				man.append_array(cur.get("manifestations", []))
				c["manifestations"] = man
				by_root[k] = c
			else:
				var man2: Array = cur.get("manifestations", [])
				man2.append({"label": String(c.get("title", ""))})
				cur["manifestations"] = man2
	var merged: Array[Dictionary] = []
	for k2: Variant in by_root.keys():
		merged.append(by_root[k2])
	merged.sort_custom(_before)
	var horizon: int = int(th.get("urgency_horizon_q", 4))
	var floor_pw: int = int(th.get("pop_weight_floor_ppm", 100000))
	var cards: Array[Dictionary] = []
	var per_domain: Dictionary = {}
	var folded: int = 0
	var domains: Dictionary = {}
	for c2: Dictionary in merged:
		domains[String(c2["domain"])] = true
	for c3: Dictionary in merged:
		var prio: bool = int(c3["urgency_q"]) <= horizon or int(c3["pop_weight_ppm"]) >= floor_pw
		if not prio:
			folded += 1
			continue
		var dn: String = String(c3["domain"])
		var used: int = int(per_domain.get(dn, 0))
		if cards.size() >= 3 or (used >= 2 and domains.size() >= 2):
			folded += 1
			continue
		per_domain[dn] = used + 1
		cards.append(c3)
	return {"cards": cards, "folded": folded, "total": merged.size(), "single_domain": domains.size() == 1,
			"horizon": horizon, "floor_pw": floor_pw}


static func _before(x: Dictionary, y: Dictionary) -> bool:
	var rx: int = int(x.get("mechanism_rank", 2))
	var ry: int = int(y.get("mechanism_rank", 2))
	var kx: int = int(x.get("rank_int", 0))
	var ky: int = int(y.get("rank_int", 0))
	if kx != ky:
		return kx < ky
	if rx != ry:
		return rx < ry
	return String(x.get("code", "")) < String(y.get("code", ""))


## 补齐可干预条数、影响人口与整数排序键（docs/21 §2.6）。
static func _finish(c: Dictionary, m: JwReadModel, cat: JwCatalog) -> void:
	var n_ok: int = 0
	var inter: Array = []
	for p: Variant in DOMAIN_POLICIES.get(String(c["domain"]), []):
		var pi: int = int(p)
		var r: Dictionary = JwReasons.for_catalog(pi, m, cat)
		var pd: Dictionary = cat.policy(pi)
		var q_fb: int = m.q + int(pd.get("lag_min", 0))
		var item: Dictionary = {"p": pi, "label": String(pd.get("label", "")),
				"capex": int(pd.get("one_off_uu", 0)), "opex": int(pd.get("opex_per_q_uu", 0)),
				"feedback_q": q_fb, "blocked": not r.is_empty(),
				"blocked_line": String(r.get("line2", "")) if not r.is_empty() else ""}
		if r.is_empty():
			n_ok += 1
		inter.append(item)
	inter.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["feedback_q"]) != int(b["feedback_q"]):
			return int(a["feedback_q"]) < int(b["feedback_q"])
		if int(a["capex"]) != int(b["capex"]):
			return int(a["capex"]) < int(b["capex"])
		return int(a["p"]) < int(b["p"]))
	c["interventions"] = inter.slice(0, 3)
	c["intervenability"] = n_ok
	var pw: int = int(c.get("pop_weight_ppm", -1))
	if pw < 0:
		var reg: int = int(c.get("anchor", -1))
		var nat: int = maxi(m.national_population(), 1)
		@warning_ignore("integer_division")
		pw = (m.region_population(reg) * JwReadModel.PPM / nat) if reg >= 0 else JwReadModel.PPM
		c["pop_weight_ppm"] = pw
		c["affected_persons"] = m.region_population(reg) if reg >= 0 else m.national_population()
	@warning_ignore("integer_division")
	c["rank_int"] = clampi(int(c["urgency_q"]), 0, 99) * 1_000_000 \
			+ (999 - mini(n_ok, 999)) * 1_000 + (999 - mini(pw / 1_001, 999))


static func _cand(code: String, domain: String, anchor: int, sub: String, urgency: int,
		sev: int, rank: int) -> Dictionary:
	var anchor_s: String = "region.%d" % anchor if anchor >= 0 else "national"
	return {"code": code, "domain": domain, "anchor": anchor, "urgency_q": urgency, "severity": sev,
			"mechanism_rank": rank, "root_key": domain + "|" + anchor_s + "|" + sub,
			"manifestations": [], "evidence": [], "pop_weight_ppm": -1}


static func _ev(c: Dictionary, ledger: String, count_text: String) -> void:
	var e: Array = c["evidence"]
	if e.size() < 4:
		e.append({"ledger": ledger, "count": count_text})


static func _bound_name(b: int) -> String:
	return JwText.t("binding.%d" % b)


# ── 检测器 ─────────────────────────────────────────────────────────────

## det.binding：某 cell 的紧约束不是计划量（docs/21 §2.4：labor→就业，energy→供电，capacity/materials→产能与投入）。
static func _det_binding(s: JwSession, m: JwReadModel, cat: JwCatalog, out: Array[Dictionary]) -> void:
	if not m.settled():
		return
	for c: int in JwReadModel.CELL:
		var b: int = m.at("flow.cell.binding_code", c)
		if b == JwReadModel.BIND_PLAN or b < 0 or b > 4:
			continue
		@warning_ignore("integer_division")
		var r: int = c / JwReadModel.S
		var sec: int = c % JwReadModel.S
		var dom: String = "supply"
		if b == JwReadModel.BIND_LABOR:
			dom = "employment"
		elif b == JwReadModel.BIND_ENERGY:
			dom = "power"
		var sub: String = str(sec) if dom == "supply" else ""
		var cd: Dictionary = _cand("det.binding", dom, r, sub, 0, JwInfo.Sev.GAP, 1)
		var bd: Dictionary = m.cell_bounds(c)
		var prev: Dictionary = _prev_hist(s)
		var prev_out: int = _hist_arr_at(prev, "cell_output", c)
		cd["title"] = JwText.render("diag.title", {"domain": JwText.t("domain." + dom),
				"anchor": cat.region_label(r) + JwText.t("sector.%d" % sec)})
		cd["symptom"] = JwText.render("diag.symptom.output", {"quarter": JwFormat.quarter(m.q - 1),
				"anchor": cat.region_label(r) + JwText.t("sector.%d" % sec),
				"value": JwFormat.qty(int(bd["actual"]), JwText.t("sector.unit.%d" % sec)),
				"change": _change_qty(int(bd["actual"]) - prev_out, prev_out >= 0, JwText.t("sector.unit.%d" % sec)),
				"citation": JwFormat.citation(JwText.t("ledger.alias.constraint"), m.q - 1, c + 1)})
		var gap: int = maxi(int(bd["plan"]) - int(bd["actual"]), 0)
		_ev(cd, "constraint", JwText.render("diag.ev.rows_gap", {"n": "1",
				"gap": JwFormat.qty(gap, JwText.t("sector.unit.%d" % sec))}))
		if dom == "power":
			_ev(cd, "service", JwText.render("diag.ev.avail", {"pct": JwFormat.pct(m.elec_availability(r))}))
		elif dom == "employment":
			_ev(cd, "labor", JwText.render("diag.ev.unemp", {"pct": JwFormat.pct(int(m.region_unemployment(r)["rate_ppm"]))}))
		else:
			_ev(cd, "value_added", JwText.render("diag.ev.va", {"amount": JwFormat.u(m.region_va_real(r))}))
		var n_proj: int = 0
		for row: Dictionary in m.project_rows():
			if int(row["region"]) == r and (int(row["status"]) == JwReadModel.PS_IN_PROGRESS \
					or int(row["status"]) == JwReadModel.PS_SUSPENDED):
				n_proj += 1
		_ev(cd, "project", JwText.render("diag.ev.projects", {"n": str(n_proj)}))
		var mech: Array = DOMAIN_MECH[dom]
		cd["mechanism"] = JwText.render("diag.mech." + dom, {"anchor": cat.region_label(r),
				"sector": JwText.t("sector.%d" % sec), "bound": _bound_name(b),
				"assumption": JwText.t("diag.assume." + dom), "mech_id": String(mech[0]), "rule_id": String(mech[1]),
				"citations": JwFormat.citation(JwText.t("ledger.alias.constraint"), m.q - 1, c + 1)})
		cd["bounds"] = bd
		cd["bounds_sector"] = sec
		out.append(cd)


## det.maturity：已签批次某季「到期本金 + 票息」超过当前国库现金（规则推断的到期表）。
static func _det_maturity(s: JwSession, m: JwReadModel, cat: JwCatalog, out: Array[Dictionary]) -> void:
	var sch: Array[Dictionary] = m.debt_schedule(4)
	var cash: int = m.gov_cash()
	for t: int in sch.size():
		var due: int = int(sch[t]["principal"]) + int(sch[t]["coupon"])
		if due > cash:
			var cd: Dictionary = _cand("det.maturity", "finance", -1, "", t, JwInfo.Sev.GAP, 1)
			cd["title"] = JwText.render("diag.title", {"domain": JwText.t("domain.finance"),
					"anchor": JwText.t("diag.anchor.national")})
			cd["symptom"] = JwText.render("diag.symptom.cash", {"quarter": JwFormat.quarter(maxi(m.q - 1, -1)),
					"value": JwFormat.u(cash),
					"citation": JwFormat.citation(JwText.t("ledger.alias.cash"), maxi(m.q - 1, -1), 1)})
			_ev(cd, "debt", JwText.render("diag.ev.batches", {"n": str(m.sc("state.bond.count")),
					"due": JwFormat.u(due)}))
			_ev(cd, "cash", JwText.render("diag.ev.cash", {"amount": JwFormat.u(cash)}))
			_ev(cd, "commit", JwText.render("diag.ev.commit", {"amount": JwFormat.u(m.sc("state.gov.committed_memo_uu"))}))
			var mech: Array = DOMAIN_MECH["finance"]
			cd["mechanism"] = JwText.render("diag.mech.finance", {"trigger_q": JwFormat.quarter(m.q + t),
					"need": JwFormat.u(due), "avail": JwFormat.u(cash), "gap": JwFormat.u(due - cash),
					"assumption": JwText.t("diag.assume.finance"), "mech_id": String(mech[0]),
					"rule_id": String(mech[1]),
					"citations": JwFormat.citation(JwText.t("ledger.alias.debt"), maxi(m.q - 1, -1), 1)})
			cd["pop_weight_ppm"] = JwReadModel.PPM
			cd["affected_persons"] = m.national_population()
			out.append(cd)
			return


static func _det_unemployment(s: JwSession, m: JwReadModel, cat: JwCatalog, th: Dictionary,
		out: Array[Dictionary]) -> void:
	if not m.settled():
		return
	var un: Dictionary = m.unemployment()
	var rate: int = int(un["rate_ppm"])
	var prev: Dictionary = _prev_hist(s)
	var prev_rate: int = int(prev.get("unemployment_ppm", rate))
	var limit: int = int(th.get("unemployment_ppm", 100000))
	var rise: int = int(th.get("unemployment_rise_ppm", 5000))
	if rate < limit and rate - prev_rate < rise:
		return
	var worst: int = 0
	var worst_rate: int = -1
	for r: int in JwReadModel.R:
		var rr: int = int(m.region_unemployment(r)["rate_ppm"])
		if rr > worst_rate:
			worst_rate = rr
			worst = r
	var cd: Dictionary = _cand("det.unemployment", "employment", worst, "", 0 if rate >= limit else 2,
			JwInfo.Sev.GAP, 1)
	cd["title"] = JwText.render("diag.title", {"domain": JwText.t("domain.employment"),
			"anchor": cat.region_label(worst)})
	cd["symptom"] = JwText.render("diag.symptom.unemp", {"quarter": JwFormat.quarter(m.q - 1),
			"anchor": cat.region_label(worst), "value": JwFormat.pct(worst_rate),
			"change": _change_ppt(rate - prev_rate),
			"citation": JwFormat.citation(JwText.t("ledger.alias.labor"), m.q - 1, worst + 1)})
	_ev(cd, "labor", JwText.render("diag.ev.lf", {"n": JwFormat.persons(int(m.region_unemployment(worst)["labor_force"]))}))
	_ev(cd, "constraint", JwText.render("diag.ev.labor_bind", {"n": str(int(m.binding_counts()[JwReadModel.BIND_LABOR]))}))
	_ev(cd, "household", JwText.render("diag.ev.groups", {"n": "9"}))
	var mech: Array = DOMAIN_MECH["employment"]
	cd["mechanism"] = JwText.render("diag.mech.unemployment", {"anchor": cat.region_label(worst),
			"rate": JwFormat.pct(worst_rate), "assumption": JwText.t("diag.assume.employment"),
			"mech_id": String(mech[0]), "rule_id": String(mech[1]),
			"citations": JwFormat.citation(JwText.t("ledger.alias.labor"), m.q - 1, worst + 1)})
	out.append(cd)


static func _det_housing(s: JwSession, m: JwReadModel, cat: JwCatalog, th: Dictionary,
		out: Array[Dictionary]) -> void:
	if not m.settled():
		return
	var limit: int = int(th.get("burden_ppm", 300000))
	for r: int in JwReadModel.R:
		var b: Dictionary = m.region_burden(r)
		if int(b["ppm"]) < limit:
			continue
		var cd: Dictionary = _cand("det.housing", "housing", r, "", 0, JwInfo.Sev.GAP, 1)
		cd["title"] = JwText.render("diag.title", {"domain": JwText.t("domain.housing"), "anchor": cat.region_label(r)})
		cd["symptom"] = JwText.render("diag.symptom.burden", {"quarter": JwFormat.quarter(m.q - 1),
				"anchor": cat.region_label(r), "value": JwFormat.pct(int(b["ppm"])),
				"citation": JwFormat.citation(JwText.t("ledger.alias.household"), m.q - 1, r + 1)})
		_ev(cd, "household", JwText.render("diag.ev.housing", {"amount": JwFormat.u(int(b["housing_uu"]))}))
		_ev(cd, "project", JwText.render("diag.ev.stock", {"stock": JwFormat.group3(m.at("state.region.housing_stock_units", r)),
				"cap": JwFormat.group3(m.at("state.region.housing_capacity_units", r))}))
		var mech: Array = DOMAIN_MECH["housing"]
		cd["mechanism"] = JwText.render("diag.mech.housing", {"anchor": cat.region_label(r),
				"burden_pct": JwFormat.pct(int(b["ppm"])), "assumption": JwText.t("diag.assume.housing"),
				"mech_id": String(mech[0]), "rule_id": String(mech[1]),
				"citations": JwFormat.citation(JwText.t("ledger.alias.household"), m.q - 1, r + 1)})
		out.append(cd)


static func _det_service(s: JwSession, m: JwReadModel, cat: JwCatalog, th: Dictionary,
		out: Array[Dictionary]) -> void:
	var limit: int = int(th.get("service_avail_ppm", 900000))
	for r: int in JwReadModel.R:
		var av: int = m.pubserv_availability(r)
		if av >= limit:
			continue
		var cd: Dictionary = _cand("det.service_avail", "service", r, "", 0, JwInfo.Sev.GAP, 1)
		cd["title"] = JwText.render("diag.title", {"domain": JwText.t("domain.service"), "anchor": cat.region_label(r)})
		cd["symptom"] = JwText.render("diag.symptom.service", {"quarter": JwFormat.quarter(maxi(m.q - 1, -1)),
				"anchor": cat.region_label(r), "value": JwFormat.pct(av),
				"citation": JwFormat.citation(JwText.t("ledger.alias.service"), maxi(m.q - 1, -1), r + 1)})
		var queue: int = 0
		for k: int in 3:
			queue += m.at("state.pubserv.queue_persons", r * 3 + k)
		_ev(cd, "service", JwText.render("diag.ev.queue", {"n": JwFormat.persons(queue)}))
		_ev(cd, "opex", JwText.render("diag.ev.opex", {"amount": JwFormat.u(m.sc("state.gov.service_opex_committed_uu"))}))
		var mech: Array = DOMAIN_MECH["service"]
		cd["mechanism"] = JwText.render("diag.mech.service", {"anchor": cat.region_label(r),
				"avail_pct": JwFormat.pct(av), "queue": JwFormat.persons(queue),
				"assumption": JwText.t("diag.assume.service"), "mech_id": String(mech[0]),
				"rule_id": String(mech[1]),
				"citations": JwFormat.citation(JwText.t("ledger.alias.service"), maxi(m.q - 1, -1), r + 1)})
		out.append(cd)


## det.cash_path：不含草案的基线试算下界出现欠付（情景预测进入机制段之前先由试算给出触发季）。
static func _det_cash_path(s: JwSession, m: JwReadModel, cat: JwCatalog, out: Array[Dictionary]) -> void:
	var run: Dictionary = s.run("nodraft_lo")
	if run.is_empty() or not bool(run.get("ok", false)):
		return
	var arr: PackedInt64Array = JwReasons._series(run, "arrears")
	var cash: PackedInt64Array = JwReasons._series(run, "cash_end")
	for t: int in arr.size():
		if arr[t] > m.sc("state.gov.arrears_uu"):
			var cd: Dictionary = _cand("det.cash_path", "finance", -1, "", t, JwInfo.Sev.GAP, 1)
			cd["title"] = JwText.render("diag.title", {"domain": JwText.t("domain.finance"),
					"anchor": JwText.t("diag.anchor.national")})
			cd["symptom"] = JwText.render("diag.symptom.cash", {"quarter": JwFormat.quarter(maxi(m.q - 1, -1)),
					"value": JwFormat.u(m.gov_cash()),
					"citation": JwFormat.citation(JwText.t("ledger.alias.cash"), maxi(m.q - 1, -1), 1)})
			_ev(cd, "cash", JwText.render("diag.ev.cash", {"amount": JwFormat.u(m.gov_cash())}))
			_ev(cd, "debt", JwText.render("diag.ev.batches", {"n": str(m.sc("state.bond.count")),
					"due": JwFormat.u(m.dv("derived.fiscal.next4q_debt_service_uu"))}))
			var mech: Array = DOMAIN_MECH["finance"]
			cd["mechanism"] = JwText.render("diag.mech.finance", {"trigger_q": JwFormat.quarter(m.q + t),
					"need": JwFormat.u(arr[t] + (cash[t] if t < cash.size() else 0)),
					"avail": JwFormat.u(cash[t] if t < cash.size() else 0), "gap": JwFormat.u(arr[t]),
					"assumption": JwText.t("diag.assume.cash_path"), "mech_id": "[M-FIN-01]", "rule_id": "^R-FIN-01",
					"citations": JwFormat.citation(JwText.t("ledger.alias.cash"), maxi(m.q - 1, -1), 1)})
			cd["pop_weight_ppm"] = JwReadModel.PPM
			cd["affected_persons"] = m.national_population()
			out.append(cd)
			return


static func _det_ext_credit(s: JwSession, m: JwReadModel, cat: JwCatalog, th: Dictionary,
		out: Array[Dictionary]) -> void:
	var lim: int = m.sc("state.world.credit_limit_uu")
	if lim <= 0:
		return
	var left: int = m.credit_left()
	@warning_ignore("integer_division")
	var share: int = left * JwReadModel.PPM / lim
	if share >= int(th.get("credit_left_ppm", 200000)):
		return
	var cd: Dictionary = _cand("det.ext_credit", "external", -1, "", 1, JwInfo.Sev.GAP, 1)
	cd["title"] = JwText.render("diag.title", {"domain": JwText.t("domain.external"),
			"anchor": JwText.t("diag.anchor.national")})
	cd["symptom"] = JwText.render("diag.symptom.credit", {"quarter": JwFormat.quarter(maxi(m.q - 1, -1)),
			"value": JwFormat.u(left), "citation": JwFormat.citation(JwText.t("ledger.alias.external"), maxi(m.q - 1, -1), 1)})
	_ev(cd, "external", JwText.render("diag.ev.credit", {"left": JwFormat.u(left), "lim": JwFormat.u(lim)}))
	_ev(cd, "debt", JwText.render("diag.ev.batches", {"n": str(m.sc("state.bond.count")),
			"due": JwFormat.u(m.dv("derived.fiscal.next4q_debt_service_uu"))}))
	var mech: Array = DOMAIN_MECH["external"]
	cd["mechanism"] = JwText.render("diag.mech.external", {"credit": JwFormat.u(left),
			"assumption": JwText.t("diag.assume.external"), "mech_id": String(mech[0]), "rule_id": String(mech[1]),
			"citations": JwFormat.citation(JwText.t("ledger.alias.external"), maxi(m.q - 1, -1), 1)})
	cd["pop_weight_ppm"] = JwReadModel.PPM
	cd["affected_persons"] = m.national_population()
	out.append(cd)


## det.output_drop（NOTE，症状层）：部门实际增加值环比下降超过阈值。
static func _det_output_drop(s: JwSession, m: JwReadModel, cat: JwCatalog, th: Dictionary,
		out: Array[Dictionary]) -> void:
	var prev: Dictionary = _prev_hist(s)
	if prev.is_empty() or not m.settled() or int(prev.get("q", -1)) < 0:
		return
	var lim: int = int(th.get("output_drop_ppm", 10000))
	for c: int in JwReadModel.CELL:
		var now_v: int = m.at("flow.cell.value_added_real_uu", c)
		var was: int = _hist_arr_at(prev, "cell_va_real", c)
		if was <= 0:
			continue
		@warning_ignore("integer_division")
		var drop: int = (was - now_v) * JwReadModel.PPM / was
		if drop < lim:
			continue
		@warning_ignore("integer_division")
		var r: int = c / JwReadModel.S
		var sec: int = c % JwReadModel.S
		var b: int = m.at("flow.cell.binding_code", c)
		var dom: String = "supply"
		if b == JwReadModel.BIND_LABOR:
			dom = "employment"
		elif b == JwReadModel.BIND_ENERGY:
			dom = "power"
		var sub: String = str(sec) if dom == "supply" else ""
		var cd: Dictionary = _cand("det.output_drop", dom, r, sub, 99, JwInfo.Sev.NOTE, 2)
		cd["title"] = JwText.render("diag.title.output_drop", {"anchor": cat.region_label(r) + JwText.t("sector.%d" % sec)})
		cd["symptom"] = JwText.render("diag.symptom.va", {"quarter": JwFormat.quarter(m.q - 1),
				"anchor": cat.region_label(r) + JwText.t("sector.%d" % sec), "value": JwFormat.u(now_v),
				"change": _change_u(now_v - was),
				"citation": JwFormat.citation(JwText.t("ledger.alias.value_added"), m.q - 1, c + 1)})
		_ev(cd, "value_added", JwText.render("diag.ev.va", {"amount": JwFormat.u(now_v)}))
		_ev(cd, "constraint", JwText.render("diag.ev.bind_name", {"bound": _bound_name(b)}))
		cd["mechanism"] = JwText.render("diag.mech_plan", {"rule_id": "^R-PROD-03",
				"citations": JwFormat.citation(JwText.t("ledger.alias.constraint"), m.q - 1, c + 1)}) \
				if b == JwReadModel.BIND_PLAN else JwText.render("diag.mech.supply", {"anchor": cat.region_label(r),
				"sector": JwText.t("sector.%d" % sec), "bound": _bound_name(b),
				"assumption": JwText.t("diag.assume.supply"), "mech_id": "[M-CAP-01]", "rule_id": "^R-PROD-03",
				"citations": JwFormat.citation(JwText.t("ledger.alias.constraint"), m.q - 1, c + 1)})
		out.append(cd)


## det.trust_drop（NOTE，症状层）：全国程序信任环比下降超过阈值。
static func _det_trust_drop(s: JwSession, m: JwReadModel, cat: JwCatalog, th: Dictionary,
		out: Array[Dictionary]) -> void:
	var prev: Dictionary = _prev_hist(s)
	if prev.is_empty() or not m.settled():
		return
	var now_t: int = m.trust_national()
	var was: int = int(prev.get("trust", now_t))
	if was - now_t < int(th.get("trust_drop_ppm", 5000)):
		return
	var cd: Dictionary = _cand("det.trust_drop", "politics", -1, "", 99, JwInfo.Sev.NOTE, 2)
	cd["title"] = JwText.render("diag.title", {"domain": JwText.t("domain.politics"),
			"anchor": JwText.t("diag.anchor.national")})
	cd["symptom"] = JwText.render("diag.symptom.trust", {"quarter": JwFormat.quarter(m.q - 1),
			"value": JwFormat.pct(now_t), "change": _change_ppt(now_t - was),
			"citation": JwFormat.citation(JwText.t("ledger.alias.politics"), m.q - 1, 1)})
	_ev(cd, "politics", JwText.render("diag.ev.support", {"pct": JwFormat.pct(m.support_national())}))
	_ev(cd, "household", JwText.render("diag.ev.groups", {"n": "36"}))
	var mech: Array = DOMAIN_MECH["politics"]
	cd["mechanism"] = JwText.render("diag.mech.politics", {"subjective": JwText.t("mood.trust"),
			"assumption": JwText.t("diag.assume.politics"), "mech_id": String(mech[0]), "rule_id": String(mech[1]),
			"citations": JwFormat.citation(JwText.t("ledger.alias.politics"), m.q - 1, 1)})
	cd["pop_weight_ppm"] = JwReadModel.PPM
	cd["affected_persons"] = m.national_population()
	out.append(cd)


# ── 执政结束判据（唯二允许终局措辞的两项，RB-15） ─────────────────────────

static func terminal_block(s: JwSession) -> Array[Dictionary]:
	var m: JwReadModel = s.model
	var out: Array[Dictionary] = []
	var ne: int = m.next_election_q()
	var seats: int = m.sc("state.politics.seats_gov")
	var total: int = m.sc("state.politics.seats_total")
	out.append({"kind": "retention", "text": JwText.render("brief.terminal_retention", {
		"rule_id": JwText.t("rule.termination.2"),
		"current_value": JwText.render("brief.seats_value", {"seats": str(seats), "total": str(total)}),
		"threshold_value": JwText.render("brief.seats_threshold", {"n": str(total / 2 + 1)}),
		"next_q": JwFormat.quarter(ne) if ne >= 0 else JwText.t("common.na"),
		"status": JwText.t("mandate_status.%d" % m.sc("state.politics.mandate_status")),
		"fails": str(m.sc("state.politics.review_fail_streak")),
		"fail_lim": str(m.rule("politics.budget_review_fail_to_lost_count", 2)),
	})})
	out.append({"kind": "restructure", "text": JwText.render("brief.terminal_restructure", {
		"rule_id": JwText.t("rule.termination.4"),
		"current_value": JwFormat.u(m.sc("state.gov.arrears_uu")),
		"threshold_value": JwFormat.quarters(m.rule("param.default_grace_q", 2)),
	})})
	return out


# ── 工具 ───────────────────────────────────────────────────────────────

static func _prev_hist(s: JwSession) -> Dictionary:
	# 历史最后一条是刚结算的季；上一条是再前一季（首季为开局基准 q = −1）。
	if s.history.size() >= 2:
		return s.history[s.history.size() - 2]
	return {}


static func _hist_arr_at(h: Dictionary, key: String, i: int) -> int:
	var v: Variant = h.get(key, [])
	if v is Array and i < (v as Array).size():
		return int((v as Array)[i])
	if v is PackedInt64Array and i < (v as PackedInt64Array).size():
		return (v as PackedInt64Array)[i]
	return -1


static func _change_u(d: int) -> String:
	return String(JwFormat.delta_u(d, true)["text"])


static func _change_ppt(d: int) -> String:
	return String(JwFormat.delta_ppt(d, false)["text"])


static func _change_qty(d: int, known: bool, unit: String) -> String:
	if not known:
		return JwText.t("diag.first_quarter")
	var word: String = JwText.t("dir.flat")
	var arrow: String = "▸"
	if d > 0:
		word = JwText.t("dir.better")
		arrow = "▲"
	elif d < 0:
		word = JwText.t("dir.worse")
		arrow = "▼"
	var sgn: String = "+" if d >= 0 else ""
	return word + " " + arrow + " " + sgn + JwFormat.qty(d, unit)
