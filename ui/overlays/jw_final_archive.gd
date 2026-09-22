## 发展档案（docs/20 §10.2；文案见 docs/21 §8）：第 40 季或提前结束。
##
## 五个不可互相换算的分区：生活 / 分配 / 能力 / 韧性 / 政治；每区 ≥1 个分布或分项（4 地区 / 4 部门 /
## ≥3 分位点），不合成单一国力分数，也不做跨维加权。提前结束时首屏写出触发条款、触发季与判定数值。
## 档案里的变化一律是「实」；不出现「预」（游戏已结束，没有下季）。
class_name JwFinalArchive
extends JwOverlay


func _init() -> void:
	paper = true
	width_ratio = 0.9
	height_ratio = 0.92


func build() -> void:
	var m: JwReadModel = session.model
	var qs: int = maxi(m.q - 1, 0)
	set_title(JwText.render("fa.title", {"quarter": JwFormat.quarter(qs)}))
	body.add_child(JwUi.label(JwText.render("fa.headline", {"country": session.catalog.country_label(), "quarter": JwFormat.quarter(qs)}),
			"title_page", "text.ink"))
	body.add_child(JwUi.para(JwText.t("fa.no_score"), "text.ink2"))
	var reason: int = m.sc("state.meta.termination_reason")
	var early: VBoxContainer = JwUi.vbox(4)
	JwUi.tag(early, "TerminationBlock")
	if reason != 1 and m.terminated:
		early.add_child(JwUi.class_line(JwInfo.Cls.ACTUAL, JwText.render("fa.early", {"quarter": JwFormat.quarter(qs),
				"rule": JwText.t("rule.termination.%d" % reason), "reason": JwText.t("termination.%d" % reason),
				"value": _trigger_value(reason), "citation": JwFormat.citation(JwText.t("ledger.alias.politics"), qs, 1)}), true))
	elif m.terminated:
		early.add_child(JwUi.class_line(JwInfo.Cls.ACTUAL, JwText.render("fa.horizon", {"quarter": JwFormat.quarter(qs)}), true))
	else:
		early.add_child(JwUi.class_line(JwInfo.Cls.ACTUAL, JwText.render("fa.ongoing", {"quarter": JwFormat.quarter(qs)}), true))
	early.add_child(JwUi.para(JwText.render("fa.rule_sentence", {"r1": JwText.t("rule.termination.2"), "r2": JwText.t("rule.termination.3"),
			"r3": JwText.t("rule.termination.4")}), "text.ink2"))
	body.add_child(early)
	body.add_child(_living())
	body.add_child(_distribution())
	body.add_child(_capacity())
	body.add_child(_resilience())
	body.add_child(_politics())
	if session != null:
		session.log_event("ev.overlay_opened", {"overlay": "overlay.final_archive"})


func _trigger_value(reason: int) -> String:
	var m: JwReadModel = session.model
	match reason:
		2:
			return JwText.render("fa.val.seats", {"seats": str(m.sc("state.politics.seats_gov")), "total": str(m.sc("state.politics.seats_total"))})
		3:
			return JwText.render("fa.val.confidence", {"n": str(m.sc("state.politics.lost_streak_q")),
					"lim": JwFormat.quarters(m.rule("param.no_confidence_q", 0))})
		4:
			return JwText.render("fa.val.restructure", {"arrears": JwFormat.u(m.sc("state.gov.arrears_uu")),
					"grace": JwFormat.quarters(m.rule("param.default_grace_q", 0))})
	return JwText.t("common.none")


func _dim_section(title_key: String, id: String) -> Dictionary:
	var sec: Dictionary = JwUi.section(JwText.t(title_key), "", true, 14)
	JwUi.tag(sec["root"], id)
	(sec["root"] as PanelContainer).add_theme_stylebox_override("panel", JwTheme.box("bg.paper", "text.ink2", 1, 2, 14))
	return sec


func _end_dim(body2: VBoxContainer) -> void:
	body2.add_child(JwUi.label(JwText.t("fa.dim_no_score"), "caption", "text.ink2"))


## 4 地区分解表（分布控件：每区 ≥1 个）。
func _region_table(label_key: String, values: Array, fmt: String) -> JwTable:
	var cols: Array = [{"title": JwText.t(label_key), "w": 200}]
	for r: int in JwReadModel.R:
		cols.append({"title": session.catalog.region_label(r), "w": 130, "align": "r", "expand": true})
	var t: JwTable = JwTable.make(cols, true, false)
	t.set_meta("distribution", true)
	var row: Array = [JwText.t("fa.row.by_region")]
	for v: Variant in values:
		var iv: int = int(v)
		var s: String = JwText.t("common.na")
		if iv >= 0:
			match fmt:
				"pct":
					s = JwFormat.pct(iv)
				"index":
					s = JwFormat.index(iv)
				"uu_pc":
					s = JwFormat.uu_pc(iv)
				_:
					s = JwFormat.u(iv)
		row.append({"text": s, "cls": JwInfo.Cls.ACTUAL})
	t.add_row(row, JwInfo.Cls.ACTUAL)
	return t


## 整局各季的历史序列（只取已结算季）：{"quarters": PackedInt64Array, key: PackedInt64Array…}。
## PackedInt64Array 是值类型：先在局部数组里追加，最后整体写回字典。
func _hist_series(keys: Array) -> Dictionary:
	var qs: PackedInt64Array = PackedInt64Array()
	var cols: Array = []
	for _k: Variant in keys:
		cols.append(PackedInt64Array())
	for h: Dictionary in session.history:
		var q: int = int(h.get("q", -1))
		if q < 0:
			continue
		qs.append(q)
		for i: int in keys.size():
			var arr: PackedInt64Array = cols[i]
			arr.append(int(h.get(String(keys[i]), 0)))
			cols[i] = arr
	var out: Dictionary = {"quarters": qs}
	for i2: int in keys.size():
		out[String(keys[i2])] = cols[i2]
	return out


func _series_meta(hs: Dictionary, unit_key: String, pb_key: String, den_key: String) -> JwChartMeta:
	var qs: PackedInt64Array = hs["quarters"]
	var tr: String = JwText.t("chart.na")
	if qs.size() >= 1:
		tr = JwText.render("chart.range", {"a": JwFormat.q2(int(qs[0])), "b": JwFormat.q2(int(qs[qs.size() - 1]))})
	var na: String = JwText.t("chart.na")
	return JwChartMeta.make(tr, JwText.t(unit_key), JwText.t(pb_key) if pb_key != "" else na,
			JwText.t(den_key) if den_key != "" else na)


func _living() -> PanelContainer:
	var m: JwReadModel = session.model
	var sec: Dictionary = _dim_section("fa.dim.living", "DimLiving")
	var b: VBoxContainer = sec["body"]
	var queue: int = 0
	for i: int in 12:
		queue += m.at("state.pubserv.queue_persons", i)
	var burden_med: Array = []
	b.add_child(JwUi.class_line(JwInfo.Cls.ACTUAL, JwText.render("fa.living", {"living": JwFormat.index(m.living_national()),
			"access": JwFormat.pct(_avg_access()), "queue": JwFormat.person_times(queue),
			"citation": JwFormat.citation(JwText.t("ledger.alias.household"), maxi(m.q - 1, 0), 1)}), true))
	b.add_child(JwDistributionBar.make(JwText.t("fa.dist.living"),
			m.group_quantiles(m.group_field("state.group.living_index_ppm"), m.all_groups(), false), "index", true))
	var vals: Array = []
	for r: int in JwReadModel.R:
		vals.append(int(m.region_burden(r)["ppm"]))
		burden_med.append(m.weighted("state.group.living_index_ppm", m.region_groups(r)))
	b.add_child(_region_table("fa.row.burden", vals, "pct"))
	b.add_child(_region_table("fa.row.living", burden_med, "index"))
	var peak: Dictionary = _peak("burden_region")
	if not peak.is_empty():
		b.add_child(JwUi.class_line(JwInfo.Cls.ACTUAL, JwText.render("fa.living_span", {"peak_q": JwFormat.quarter(int(peak["q"])),
				"peak": JwFormat.pct(int(peak["v"]))}), true))
	_end_dim(b)
	return sec["root"]


func _avg_access() -> int:
	var m: JwReadModel = session.model
	var num: int = 0
	var den: int = 0
	for g: int in JwReadModel.GROUP:
		var p: int = m.group_population(g)
		num += m.group_service_access(g) * p
		den += p
	@warning_ignore("integer_division")
	return num / den if den > 0 else 0


## 历史中某地区数组的峰值（最高的一个地区值及其季）。
func _peak(key: String) -> Dictionary:
	var best: Dictionary = {}
	for h: Dictionary in session.history:
		if int(h.get("q", -1)) < 0:
			continue
		var arr: Variant = h.get(key, [])
		if arr is Array:
			for v: Variant in arr as Array:
				if best.is_empty() or int(v) > int(best["v"]):
					best = {"q": int(h["q"]), "v": int(v)}
	return best


func _distribution() -> PanelContainer:
	var m: JwReadModel = session.model
	var sec: Dictionary = _dim_section("fa.dim.dist", "DimDistribution")
	var b: VBoxContainer = sec["body"]
	var qd: Dictionary = m.income_quantiles(m.all_groups())
	var base: Dictionary = {}
	for h: Dictionary in session.history:
		if int(h.get("q", -1)) >= 0:
			base = h
			break
	var gainers: int = 0
	var losers: int = 0
	var gd: Variant = base.get("group_disp_pc", [])
	if gd is Array and (gd as Array).size() == JwReadModel.GROUP:
		for g: int in JwReadModel.GROUP:
			var was: int = int((gd as Array)[g])
			var now_v: int = m.group_disposable_pc(g)
			if was <= 0 or now_v < 0:
				continue
			if now_v > was:
				gainers += 1
			elif now_v < was:
				losers += 1
	var ratio: String = JwText.t("common.na")
	if int(qd.get("p20", -1)) > 0:
		@warning_ignore("integer_division")
		ratio = JwFormat.ratio(int(qd["p80"]) * JwReadModel.PPM / int(qd["p20"]))
	b.add_child(JwUi.class_line(JwInfo.Cls.ACTUAL, JwText.render("fa.dist", {"p20": JwFormat.uu_pc(int(qd.get("p20", 0))),
			"p50": JwFormat.uu_pc(int(qd.get("p50", 0))), "p80": JwFormat.uu_pc(int(qd.get("p80", 0))), "ratio": ratio,
			"gainers": str(gainers), "losers": str(losers),
			"citation": JwFormat.citation(JwText.t("ledger.alias.household"), maxi(m.q - 1, 0), 1)}), true))
	var q3: JwTable = JwTable.make([{"title": JwText.t("fa.row.quantile"), "w": 200},
			{"title": "P10", "w": 120, "align": "r", "expand": true}, {"title": "P50", "w": 120, "align": "r", "expand": true},
			{"title": JwText.t("so.dist.mean"), "w": 120, "align": "r", "expand": true}, {"title": "P90", "w": 120, "align": "r", "expand": true}],
			true, false)
	q3.set_meta("distribution", true)
	q3.add_row([JwText.t("fa.row.disp_pc"), {"text": JwFormat.uu_pc_num(int(qd.get("p10", 0))), "cls": JwInfo.Cls.ACTUAL},
			{"text": JwFormat.uu_pc_num(int(qd.get("p50", 0))), "cls": JwInfo.Cls.ACTUAL},
			{"text": JwFormat.uu_pc_num(int(qd.get("mean", 0))), "cls": JwInfo.Cls.ACTUAL},
			{"text": JwFormat.uu_pc_num(int(qd.get("p90", 0))), "cls": JwInfo.Cls.ACTUAL}], JwInfo.Cls.ACTUAL)
	b.add_child(q3)
	b.add_child(JwDistributionBar.make(JwText.t("fa.dist.income"), qd, "uu_pc", true))
	var reg: Array = []
	for r: int in JwReadModel.R:
		reg.append(int(m.income_quantiles(m.region_groups(r)).get("p50", -1)))
	b.add_child(_region_table("fa.row.region_p50", reg, "uu_pc"))
	b.add_child(JwUi.para(JwText.t("fa.dist_caveat"), "text.ink2"))
	_end_dim(b)
	return sec["root"]


func _capacity() -> PanelContainer:
	var m: JwReadModel = session.model
	var sec: Dictionary = _dim_section("fa.dim.capacity", "DimCapacity")
	var b: VBoxContainer = sec["body"]
	var caps: PackedStringArray = PackedStringArray()
	var cols: Array = [{"title": JwText.t("fa.row.sector_cap"), "w": 200}]
	var row: Array = [JwText.t("fa.row.cap_q")]
	for s: int in JwReadModel.S:
		var t: int = 0
		for r: int in JwReadModel.R:
			t += m.at("state.cell.capacity_active_uqs_per_q", JwReadModel.idx_cell(r, s))
		caps.append(JwText.t("sector.%d" % s) + " " + JwFormat.qty(t, JwText.t("sector.unit.%d" % s)))
		cols.append({"title": JwText.t("sector.%d" % s), "w": 140, "align": "r", "expand": true})
		row.append({"text": JwFormat.qty_num(t), "cls": JwInfo.Cls.ACTUAL})
	var tb: JwTable = JwTable.make(cols, true, false)
	tb.set_meta("distribution", true)
	tb.add_row(row, JwInfo.Cls.ACTUAL)
	b.add_child(tb)
	var sk: PackedInt64Array = PackedInt64Array([0, 0, 0])
	for g: int in JwReadModel.GROUP:
		if JwReadModel.age_of_group(g) == JwReadModel.AGE_WORKING:
			sk[JwReadModel.skill_of_group(g)] += m.group_population(g)
	b.add_child(JwUi.class_line(JwInfo.Cls.ACTUAL, JwText.render("fa.capacity", {"low": JwFormat.persons(sk[0]),
			"mid": JwFormat.persons(sk[1]), "high": JwFormat.persons(sk[2]), "coverage": JwFormat.pct(m.sc("state.gov.tax_capacity_ppm")),
			"citation": JwFormat.citation(JwText.t("ledger.alias.labor"), maxi(m.q - 1, 0), 1)}), true))
	b.add_child(JwDistributionBar.make(JwText.t("fa.dist.access"), m.group_quantiles(m.group_access_values(), m.all_groups(), false),
			"pct", true))
	_end_dim(b)
	return sec["root"]


func _resilience() -> PanelContainer:
	var m: JwReadModel = session.model
	var sec: Dictionary = _dim_section("fa.dim.resilience", "DimResilience")
	var b: VBoxContainer = sec["body"]
	var arrears_q: int = 0
	var peak_q: int = -1
	var peak_v: int = 0
	var cols: Array = [{"title": JwText.t("fa.row.series"), "w": 130}]
	var row_cash: Array = [JwText.t("fa.row.cash")]
	var n: int = 0
	for h: Dictionary in session.history:
		var q: int = int(h.get("q", -1))
		if q < 0:
			continue
		if int(h.get("arrears", 0)) > 0:
			arrears_q += 1
		var ds: int = int(h.get("interest", 0)) + int(h.get("principal", 0))
		if ds > peak_v:
			peak_v = ds
			peak_q = q
		if n < 12:
			cols.append({"title": JwFormat.q2(q), "w": 64, "align": "r"})
			row_cash.append({"text": JwFormat.u_num(int(h.get("cash", 0))), "cls": JwInfo.Cls.ACTUAL})
			n += 1
	b.add_child(JwUi.class_line(JwInfo.Cls.ACTUAL, JwText.render("fa.resilience", {"floor_q": JwFormat.quarters(arrears_q),
			"peak_q": JwFormat.quarter(maxi(peak_q, 0)), "peak": JwFormat.u(peak_v), "credit": JwFormat.u(m.credit_left()),
			"citation": JwFormat.citation(JwText.t("ledger.alias.debt"), maxi(m.q - 1, 0), 1)}), true))
	if n > 0:
		var t: JwTable = JwTable.make(cols, true, false)
		t.set_meta("distribution", true)
		t.add_row(row_cash, JwInfo.Cls.ACTUAL)
		t.add_note(JwText.t("fa.series_note"))
		b.add_child(t)
	var hs: Dictionary = _hist_series(["cash", "arrears"])
	b.add_child(JwLineChart.make(JwText.t("fa.chart.fiscal"), _series_meta(hs, "chart.unit.u_stock", "chart.pb.nominal", ""),
			[{"label": JwText.t("chart.s.cash"), "values": hs["cash"], "token": "series.1"},
			{"label": JwText.t("chart.s.arrears"), "values": hs["arrears"], "token": "series.4"}] as Array[Dictionary],
			hs["quarters"], "u", true, 150))
	var any_shock: bool = false
	for h2: Dictionary in session.history:
		var sa: Variant = h2.get("shocks", [])
		if sa is Array:
			for v: Variant in sa as Array:
				if int(v) == 1:
					any_shock = true
	b.add_child(JwUi.class_line(JwInfo.Cls.ACTUAL, JwText.t("fa.shock_seen") if any_shock else JwText.t("fa.shock_none"), true))
	_end_dim(b)
	return sec["root"]


func _politics() -> PanelContainer:
	var m: JwReadModel = session.model
	var cat: JwCatalog = session.catalog
	var sec: Dictionary = _dim_section("fa.dim.politics", "DimPolitics")
	var b: VBoxContainer = sec["body"]
	var sup: Array = []
	for r: int in JwReadModel.R:
		sup.append(m.support_region(r))
	b.add_child(_region_table("fa.row.support", sup, "pct"))
	b.add_child(JwDistributionBar.make(JwText.t("fa.dist.support"),
			m.group_quantiles(m.group_field("state.group.support_ppm"), m.all_groups()), "pct", true))
	var hs: Dictionary = _hist_series(["support"])
	b.add_child(JwLineChart.make(JwText.t("fa.chart.support"), _series_meta(hs, "chart.unit.pct", "", "chart.den.pop"),
			[{"label": JwText.t("chart.s.support"), "values": hs["support"], "token": "series.3"}] as Array[Dictionary],
			hs["quarters"], "pct", true, 150))
	var blocs: PackedStringArray = PackedStringArray()
	for bi: int in cat.blocs.size():
		blocs.append(cat.bloc_label(bi) + " " + JwFormat.pct(m.at("state.bloc.org_power_ppm", bi)))
	b.add_child(JwUi.class_line(JwInfo.Cls.ACTUAL, JwText.render("fa.politics", {"trust": JwFormat.pct(m.trust_national()),
			"blocs": "、".join(blocs), "seats": str(m.sc("state.politics.seats_gov")), "total": str(m.sc("state.politics.seats_total")),
			"citation": JwFormat.citation(JwText.t("ledger.alias.politics"), maxi(m.q - 1, 0), 1)}), true))
	_end_dim(b)
	return sec["root"]
