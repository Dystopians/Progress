## 页面一 · 国家总览（docs/20 §7.1）：「这一季，我该先看哪里？」
##
## 三支柱（实际产出 / 就业与生活 / 财政与承诺）是三个不可互相换算的量纲，各自带分项，不合成分数；
## 左栏：地区横条（地图的降级形态 JwRegionStrip，5 个图层，默认「生产约束定位」）+ 本季已发生条；
## 右栏：最多 3 张四段诊断卡（症状 实 / 证据 / 机制 算 / 干预），另附执政结束判据区块。
class_name JwOverviewPage
extends JwPage

const LAYERS: PackedStringArray = ["constraint", "output", "labor", "power", "housing"]

var layer: String = "constraint"
var _root: VBoxContainer = null
var _scroll: ScrollContainer = null
var _expanded: Dictionary = {}


func refresh() -> void:
	if _scroll != null:
		remove_child(_scroll)
		_scroll.queue_free()
	# 整页纵向滚动（H-short 与降级档下必需；首屏必备区块在上方，见 get_required_above_fold）。
	_root = JwUi.vbox(16)
	_root.name = "OverviewRoot"
	_root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll = JwUi.scroll(_root)
	_scroll.name = "OverviewScroll"
	add_child(_scroll)
	if session == null or session.game == null:
		_root.add_child(JwUi.empty_state(JwText.t("ov.empty.why"), JwText.t("ov.empty.when"),
				JwText.t("ov.empty.rule")))
		return
	var short: bool = hband == JwScale.HBand.SHORT
	_root.add_child(term_strip())
	_root.add_child(_pillars(short))
	var main: HBoxContainer = JwUi.hbox(16)
	main.name = "MainRow"
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_root.add_child(main)
	var left: VBoxContainer = JwUi.vbox(12)
	left.name = "LeftCol"
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.25
	main.add_child(left)
	left.add_child(_region_strip())
	left.add_child(_recent_strip())
	left.add_child(_terminal_block())
	var right_scroll: ScrollContainer = ScrollContainer.new()
	right_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_scroll.size_flags_stretch_ratio = 1.0
	main.add_child(right_scroll)
	var right: VBoxContainer = _diag_stack(short)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_scroll.add_child(right)
	_root.add_child(_trends())
	_root.add_child(_commit_block())


## 承诺时间轴（docs/20 D-02：总览页 L2 区块；T1 先做 12 季静态视窗）。
func _commit_block() -> PanelContainer:
	var sec: Dictionary = JwUi.section(JwText.t("ov.commit.title"))
	JwUi.tag(sec["root"], "CommitBlock")
	var body: VBoxContainer = sec["body"]
	body.add_child(JwUi.class_line(JwInfo.Cls.DERIVED, JwText.t("ct.note")))
	var sched: Dictionary = session.game.commitment_schedule(12) if session.game != null else {}
	if not sched.is_empty():
		body.add_child(JwCommitTimeline.make(sched, 12))
	return sec["root"]


## 约束上界：等于「不适用」哨兵（QTY_MAX）时写「不适用」，不把哨兵当成 1,000,000 Q 显示。
static func _bound_text(v: int) -> String:
	if v >= JwReadModel.BOUND_NA:
		return JwText.t("common.na")
	return JwFormat.qty_num(v)


# ── 走势（docs/20 §13.1 JwLineChart，T1）──────────────────────────────────

## 六张小时序图：只画已结算季（history 里 q ≥ 0 的快照），每张带四标注。
func _trends() -> PanelContainer:
	var sec: Dictionary = JwUi.section(JwText.t("ov.trend.title"))
	JwUi.tag(sec["root"], "TrendCharts")
	var body: VBoxContainer = sec["body"]
	body.add_child(JwUi.caption(JwText.t("ov.trend.note")))
	var qs: PackedInt64Array = PackedInt64Array()
	var cols: Dictionary = {}
	for key: String in ["gdp_real", "unemployment_ppm", "support", "living", "cash", "arrears", "debt", "receipts"]:
		cols[key] = PackedInt64Array()
	for h: Dictionary in session.history:
		var hq: int = int(h.get("q", -1))
		if hq < 0:
			continue
		qs.append(hq)
		for key2: String in cols.keys():
			# PackedInt64Array 是值类型：取出、追加、再写回，直接对 cols[key2] 追加只会改到副本。
			var arr: PackedInt64Array = cols[key2]
			arr.append(int(h.get(key2, 0)))
			cols[key2] = arr
	var tr: String = JwText.t("chart.na")
	if qs.size() >= 1:
		tr = JwText.render("chart.range", {"a": JwFormat.q2(int(qs[0])), "b": JwFormat.q2(int(qs[qs.size() - 1]))})
	var na: String = JwText.t("chart.na")
	var grid: GridContainer = GridContainer.new()
	grid.columns = 3 if wband == JwScale.WBand.WIDE else 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 12)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(grid)
	var specs: Array = [
		["chart.t.gdp", [["chart.s.gdp", "gdp_real", "series.1"]], "u", "chart.unit.u_q", "chart.pb.real", ""],
		["chart.t.unemp", [["chart.s.unemp", "unemployment_ppm", "series.2"]], "pct", "chart.unit.pct", "", "chart.den.labor"],
		["chart.t.social", [["chart.s.support", "support", "series.3"], ["chart.s.living", "living", "series.4"]], "pct",
				"chart.unit.pct_index", "", "chart.den.pop"],
		["chart.t.cash", [["chart.s.cash", "cash", "series.1"], ["chart.s.arrears", "arrears", "series.4"]], "u",
				"chart.unit.u_stock", "chart.pb.nominal", ""],
		["chart.t.debt", [["chart.s.debt", "debt", "series.2"]], "u", "chart.unit.u_stock", "chart.pb.nominal", ""],
		["chart.t.receipts", [["chart.s.receipts", "receipts", "series.3"]], "u", "chart.unit.u_q", "chart.pb.nominal", ""],
	]
	for sp: Array in specs:
		var ser: Array[Dictionary] = []
		for sd: Array in (sp[1] as Array):
			ser.append({"label": JwText.t(String(sd[0])), "values": cols[String(sd[1])], "token": String(sd[2])})
		var pb: String = JwText.t(String(sp[4])) if String(sp[4]) != "" else na
		var den: String = JwText.t(String(sp[5])) if String(sp[5]) != "" else na
		var meta: JwChartMeta = JwChartMeta.make(tr, JwText.t(String(sp[3])), pb, den)
		grid.add_child(JwLineChart.make(JwText.t(String(sp[0])), meta, ser, qs, String(sp[2]), false, 140))
	return sec["root"]


# ── 三支柱 ─────────────────────────────────────────────────────────────

func _pillar_card(id: String, title: String) -> Dictionary:
	var p: PanelContainer = JwUi.panel("bg.panel", "line.hair", 14)
	JwUi.tag(p, id)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v: VBoxContainer = JwUi.vbox(4)
	p.add_child(v)
	v.add_child(JwUi.label(title, "title_sub", "text.secondary"))
	return {"root": p, "body": v}


func _pillars(short: bool) -> HBoxContainer:
	var m: JwReadModel = session.model
	var row: HBoxContainer = JwUi.hbox(16)
	row.name = "PillarRow"
	var prev: Dictionary = JwDiagnose._prev_hist(session)
	var last: Dictionary = session.last_settled()
	var settled: bool = m.settled()
	# A 实际产出
	var a: Dictionary = _pillar_card("PillarOutput", JwText.t("ov.pillar.output"))
	var av: VBoxContainer = a["body"]
	var idx_ppm: int = JwReadModel.PPM
	var base_real: int = _base_real_gdp()
	if settled and base_real > 0:
		@warning_ignore("integer_division")
		idx_ppm = m.dv("derived.gdp.real_uu") * JwReadModel.PPM / base_real
	var out_cell: JwNumberCell = num(JwFormat.index(idx_ppm), JwText.t("unit.index"), JwInfo.Cls.ACTUAL, "hero",
			{"measure": JwText.t("measure.index"), "period": JwText.t("period.this_q"),
			"price_base": JwText.t("price.base_year"), "index_base": JwText.t("index.base_q1"),
			"ledger": "value_added", "rule_key": "real_gdp",
			"citation": JwFormat.citation(JwText.t("ledger.alias.value_added"), maxi(m.q - 1, -1), 1)})
	JwUi.tag(out_cell, "OutputIndex")
	av.add_child(out_cell)
	var om: Label = JwUi.meta_line(PackedStringArray([JwText.t("measure.index"), JwText.t("period.this_q"),
			JwText.t("index.base_q1"), JwText.t("price.base_year")]), out_cell)
	JwUi.tag(om, "OutputMeta")
	av.add_child(om)
	if not settled:
		av.add_child(JwUi.label(JwText.t("ov.first_quarter"), "body", "text.muted"))
	elif not prev.is_empty() and int(prev.get("q", -1)) >= 0 and base_real > 0:
		@warning_ignore("integer_division")
		var prev_idx: int = int(prev.get("gdp_real", 0)) * JwReadModel.PPM / base_real
		av.add_child(_delta_label(JwFormat.delta_index(idx_ppm - prev_idx, true, 5000)))
	else:
		av.add_child(JwUi.label(JwText.t("ov.base_period"), "body", "text.muted"))
	var bc: PackedInt64Array = m.binding_counts()
	var bind_txt: String = JwText.t("ov.binding.none")
	var top_b: int = 0
	for b: int in range(1, 5):
		if bc[b] > 0 and (top_b == 0 or bc[b] > bc[top_b]):
			top_b = b
	if top_b > 0:
		bind_txt = JwText.render("ov.binding.top", {"bound": JwText.t("binding.%d" % top_b), "n": str(bc[top_b])})
	if not settled:
		bind_txt = JwText.t("ov.binding.cold")
	av.add_child(JwUi.class_line(JwInfo.Cls.DERIVED, JwInfo.prefix(JwInfo.Cls.DERIVED) + bind_txt))
	if not short:
		var parts: PackedStringArray = PackedStringArray()
		for sec: int in JwReadModel.S:
			parts.append(JwText.t("sector.%d" % sec) + " " + JwFormat.u_num(m.sector_va_real(sec)))
		av.add_child(JwUi.caption(JwText.render("ov.breakdown.output", {"list": " · ".join(parts)}), out_cell))
	var l1: Button = JwUi.link(JwText.t("ov.link.output"))
	l1.pressed.connect(func() -> void: goto_page("region", {}))
	av.add_child(l1)
	row.add_child(a["root"])
	# B 就业与生活
	var b_: Dictionary = _pillar_card("PillarLabor", JwText.t("ov.pillar.labor"))
	var bv: VBoxContainer = b_["body"]
	var un: Dictionary = m.unemployment()
	var un_cell: JwNumberCell = num(JwFormat.pct_num(int(un["rate_ppm"])), "%", JwInfo.Cls.ACTUAL, "hero",
			{"measure": JwText.t("measure.ratio"), "period": JwText.t("period.this_q"),
			"denominator": JwText.render("denom.labor_force", {"n": JwFormat.persons(int(un["labor_force"]))}),
			"ledger": "labor", "rule_key": "unemployment",
			"citation": JwFormat.citation(JwText.t("ledger.alias.labor"), maxi(m.q - 1, -1), 1)})
	JwUi.tag(un_cell, "Unemployment")
	bv.add_child(un_cell)
	var um: Label = JwUi.meta_line(PackedStringArray([JwText.t("measure.ratio"), JwText.t("period.this_q"),
			JwText.render("denom.labor_force", {"n": JwFormat.persons(int(un["labor_force"]))}),
			JwText.render("ov.unemployed_abs", {"n": JwFormat.persons(int(un["unemployed"]))})]), un_cell)
	JwUi.tag(um, "UnemploymentMeta")
	bv.add_child(um)
	if not settled or prev.is_empty():
		bv.add_child(JwUi.label(JwText.t("ov.first_quarter"), "body", "text.muted"))
	else:
		bv.add_child(_delta_label(JwFormat.delta_ppt(int(un["rate_ppm"]) - int(prev.get("unemployment_ppm", 0)), false, 1000)))
	var living: int = m.living_national()
	bv.add_child(JwUi.class_line(JwInfo.Cls.ACTUAL, JwText.render("ov.living", {"value": JwFormat.index(living)})))
	if not short:
		var parts2: PackedStringArray = PackedStringArray()
		for r: int in JwReadModel.R:
			parts2.append(session.catalog.region_label(r) + " " + JwFormat.pct(int(m.region_unemployment(r)["rate_ppm"])))
		bv.add_child(JwUi.caption(JwText.render("ov.breakdown.labor", {"list": " · ".join(parts2)}), un_cell))
	var l2: Button = JwUi.link(JwText.t("ov.link.labor"))
	l2.pressed.connect(func() -> void: goto_page("society", {}))
	bv.add_child(l2)
	row.add_child(b_["root"])
	# C 财政与承诺
	var c: Dictionary = _pillar_card("PillarFiscal", JwText.t("ov.pillar.fiscal"))
	var cv: VBoxContainer = c["body"]
	var cash_cell: JwNumberCell = num(JwFormat.u_num(m.gov_cash()), "U", JwInfo.Cls.ACTUAL, "hero",
			{"measure": JwText.t("measure.stock"), "period": JwText.t("period.q_end"),
			"price_base": JwText.t("price.nominal"), "ledger": "cash", "rule_key": "fiscal_identity",
			"citation": JwFormat.citation(JwText.t("ledger.alias.cash"), maxi(m.q - 1, -1), 1),
			"raw": JwFormat.uu_raw(m.gov_cash())})
	JwUi.tag(cash_cell, "CashEnd")
	cv.add_child(cash_cell)
	cv.add_child(JwUi.meta_line(PackedStringArray([JwText.t("measure.stock"), JwText.t("period.q_end"),
			JwText.t("price.nominal")]), cash_cell))
	var hr: Dictionary = m.headroom_nodraft(4)
	var hr_row: HBoxContainer = JwUi.hbox(6)
	JwUi.tag(hr_row, "HeadroomNoDraft")
	var hr_text: String = JwText.render("ov.headroom_nodraft", {"value": JwFormat.u(int(hr["value"])),
			"q": JwFormat.quarter(int(hr["q"]))})
	hr_row.set_meta("label_text", hr_text)
	hr_row.set_meta("info_class", JwInfo.Cls.DERIVED)
	hr_row.add_child(JwUi.class_line(JwInfo.Cls.DERIVED, JwInfo.prefix(JwInfo.Cls.DERIVED) + hr_text))
	cv.add_child(hr_row)
	if not short:
		cv.add_child(JwUi.caption(JwText.render("ov.headroom_caliber", {"committed": JwFormat.u(int(hr["committed_4q"]))}), cash_cell))
	cv.add_child(JwUi.class_line(JwInfo.Cls.ACTUAL, JwText.render("ov.debt", {"value": JwFormat.u(m.debt_total())})))
	var l3: Button = JwUi.link(JwText.t("ov.link.fiscal"))
	l3.pressed.connect(func() -> void: _on_ledger("debt", 0))
	cv.add_child(l3)
	row.add_child(c["root"])
	return row


func _base_real_gdp() -> int:
	for h: Dictionary in session.history:
		if int(h.get("q", -1)) >= 0 and int(h.get("gdp_real", 0)) > 0:
			return int(h["gdp_real"])
	return session.model.dv("derived.gdp.real_uu")


func _delta_label(d: Dictionary) -> Label:
	var dir: int = int(d["dir"])
	var tok: String = "teal.core" if dir > 0 else ("ochre.core" if dir < 0 else "text.secondary")
	return JwUi.label(String(d["text"]), "body_bold", tok)


# ── 地区横条（JwRegionStrip，地图降级形态） ───────────────────────────────

func _region_strip() -> PanelContainer:
	var m: JwReadModel = session.model
	var cat: JwCatalog = session.catalog
	var p: PanelContainer = JwUi.panel("bg.panel", "line.hair", 12)
	JwUi.tag(p, "RegionStrip")
	var v: VBoxContainer = JwUi.vbox(8)
	p.add_child(v)
	var use_map: bool = wband == JwScale.WBand.WIDE and hband != JwScale.HBand.SHORT
	var head: HBoxContainer = JwUi.hbox(10)
	head.add_child(JwUi.title(JwText.t("ov.region.title_map" if use_map else "ov.region.title")))
	head.add_child(JwUi.spacer())
	head.add_child(JwUi.label(JwText.t("ov.layer"), "body", "text.secondary"))
	var ob: OptionButton = OptionButton.new()
	ob.name = "LayerSwitcher"
	for i: int in LAYERS.size():
		ob.add_item(JwText.t("layer." + LAYERS[i]), i)
	ob.select(LAYERS.find(layer))
	ob.item_selected.connect(func(i: int) -> void:
		layer = LAYERS[i]
		refresh())
	head.add_child(ob)
	v.add_child(head)
	# 宽屏且不矮：地区多边形图（docs/20 §7.2.5，T1）；矮屏或窄屏：四格横条（地图的降级形态）。
	if use_map:
		var mp: JwRegionMap = _region_map()
		if mp != null:
			v.add_child(mp)
			v.add_child(JwUi.label(JwText.t("ov.map.edge_legend"), "caption", "text.muted", true))
			var legend0: Label = JwUi.label(JwText.t("legend." + layer), "caption", "text.muted", true)
			JwUi.tag(legend0, "MapLegend")
			v.add_child(legend0)
			if layer == "constraint" and not m.settled():
				v.add_child(JwUi.label(JwText.t("ov.layer.cold"), "caption", "text.muted", true))
			return p
	# W-wide 一行四格；W-mid 与降级档 2×2（四格仍并列、不排序，只是换行）。
	var cells: GridContainer = GridContainer.new()
	cells.columns = 4 if wband == JwScale.WBand.WIDE else 2
	cells.add_theme_constant_override("h_separation", 8)
	cells.add_theme_constant_override("v_separation", 8)
	v.add_child(cells)
	for r: int in JwReadModel.R:
		var info: Dictionary = _layer_value(r)
		var cell: PanelContainer = JwUi.panel_style(JwTheme.box_left_rule("bg.raised", String(info["token"]), 4, 10))
		JwUi.tag(cell, "Region%d" % r)
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.mouse_filter = Control.MOUSE_FILTER_STOP
		cell.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var rr: int = r
		cell.gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventMouseButton and (ev as InputEventMouseButton).double_click:
				goto_page("region", {"region": rr}))
		var cv: VBoxContainer = JwUi.vbox(2)
		cell.add_child(cv)
		cv.add_child(JwUi.label(cat.region_label(r) + " · " + JwFormat.persons(m.region_population(r)), "title_sub"))
		var th: Label = JwUi.label(cat.region_theme(r), "body", "text.secondary")
		JwUi.tag(th, "Theme%d" % r)
		cv.add_child(th)
		var vh: HBoxContainer = JwUi.hbox(6)
		vh.add_child(JwUi.badge(int(info["cls"])))
		if String(info["icon"]) != "":
			vh.add_child(JwIcon.make(String(info["icon"]), JwTheme.c(String(info["token"])), 14))
		var vl: Label = JwUi.label(String(info["text"]), "num_bold", "text.primary")
		vh.add_child(vl)
		cv.add_child(vh)
		cells.add_child(cell)
	var legend: Label = JwUi.label(JwText.t("legend." + layer), "caption", "text.muted", true)
	JwUi.tag(legend, "MapLegend")
	v.add_child(legend)
	if layer == "constraint" and not m.settled():
		v.add_child(JwUi.label(JwText.t("ov.layer.cold"), "caption", "text.muted", true))
	return p


## 地区多边形图：轮廓取界面登记的抽象几何，邻接边与成本取剧本；任一轮廓缺失即退回四格横条（返回 null）。
func _region_map() -> JwRegionMap:
	var m: JwReadModel = session.model
	var cat: JwCatalog = session.catalog
	var regs: Array[Dictionary] = []
	for r: int in JwReadModel.R:
		var poly: PackedVector2Array = cat.region_polygon(r)
		if poly.size() < 3:
			return null
		var info: Dictionary = _layer_value(r)
		regs.append({"poly": poly, "token": String(info["token"]),
				"label": JwText.render("ov.map.label", {"region": cat.region_label(r), "value": String(info["text"]),
					"pop": JwFormat.persons(m.region_population(r))})})
	var mp: JwRegionMap = JwRegionMap.make(regs, cat.adjacency_edges(), cat.map_coord_space())
	mp.region_opened.connect(func(r2: int) -> void:
		goto_page("region", {"region": r2}))
	return mp


## 图层值（逐区）：{text, cls, token, icon}。着色 token 只用系列色与中性色（赭色不做图层色）。
func _layer_value(r: int) -> Dictionary:
	var m: JwReadModel = session.model
	match layer:
		"constraint":
			var b: int = m.region_binding(r)
			return {"text": JwText.t("binding.%d" % b) if m.settled() else JwText.t("ov.layer.cold_value"),
					"cls": JwInfo.Cls.DERIVED, "token": "series.%d" % (b % 4 + 1) if b > 0 else "line.strong",
					"icon": "region"}
		"output":
			return {"text": JwFormat.u(m.region_va_real(r)), "cls": JwInfo.Cls.ACTUAL,
					"token": "series.%d" % (r + 1), "icon": ""}
		"labor":
			var u: int = int(m.region_unemployment(r)["rate_ppm"])
			return {"text": JwFormat.pct(u), "cls": JwInfo.Cls.ACTUAL, "token": _band_token(u, [40000, 70000, 100000, 140000]),
					"icon": ""}
		"power":
			var e: int = m.elec_availability(r)
			return {"text": JwFormat.pct(e), "cls": JwInfo.Cls.ACTUAL,
					"token": _band_token(JwReadModel.PPM - e, [20000, 50000, 100000, 200000]), "icon": ""}
		"housing":
			var bd: int = int(m.region_burden(r)["ppm"])
			return {"text": JwFormat.pct(bd) if bd >= 0 else JwText.t("common.na"), "cls": JwInfo.Cls.ACTUAL,
					"token": _band_token(bd, [150000, 200000, 250000, 300000]), "icon": ""}
	return {"text": "", "cls": JwInfo.Cls.ACTUAL, "token": "line.strong", "icon": ""}


## 五档分级 → 系列色（低 → 高）。断点写在图例里。
static func _band_token(v: int, cuts: Array) -> String:
	var i: int = 0
	while i < cuts.size() and v >= int(cuts[i]):
		i += 1
	return ["series.1", "series.2", "series.3", "series.4", "warm.text"][i]


# ── 本季已发生条 ─────────────────────────────────────────────────────────

func _recent_strip() -> PanelContainer:
	var m: JwReadModel = session.model
	var p: PanelContainer = JwUi.panel("bg.panel", "line.hair", 12)
	JwUi.tag(p, "RecentLedgerStrip")
	var v: VBoxContainer = JwUi.vbox(6)
	p.add_child(v)
	if not m.settled():
		v.add_child(JwUi.empty_state(JwText.t("ov.recent.cold.why"), JwText.t("ov.recent.cold.when"),
				JwText.t("ov.recent.cold.rule")))
		return p
	var completed: int = 0
	for row: Dictionary in m.project_rows():
		if int(row["commissioned_q"]) == m.q - 1 or (int(row["status"]) == JwReadModel.PS_COMPLETED):
			completed += 1
	var txt: String = JwText.render("tpl.actual.quarter_summary", {"quarter": JwFormat.quarter(m.q - 1),
			"receipts_u": JwFormat.u(m.receipts_total()), "outlays_u": JwFormat.u(m.outlays_total()),
			"new_debt_u": JwFormat.u(m.sc("flow.gov.new_borrowing_uu")), "completed_count": str(completed),
			"citation": JwFormat.citation(JwText.t("ledger.alias.transaction"), m.q - 1, 1)})
	v.add_child(JwUi.class_line(JwInfo.Cls.ACTUAL, txt))
	var h: HBoxContainer = JwUi.hbox(10)
	var l1: Button = JwUi.link(JwText.t("ov.recent.link_tx"))
	l1.pressed.connect(func() -> void: _on_ledger("transaction", 0))
	h.add_child(l1)
	var l2: Button = JwUi.link(JwText.t("ov.recent.link_report"))
	l2.pressed.connect(func() -> void: goto_page("report", {}))
	h.add_child(l2)
	v.add_child(h)
	return p


# ── 执政结束判据（RB-15：唯二允许终局措辞者，独立区块，不占诊断名额） ────────

func _terminal_block() -> PanelContainer:
	var p: PanelContainer = JwUi.panel("bg.panel", "line.hair", 12)
	JwUi.tag(p, "TerminalBlock")
	var v: VBoxContainer = JwUi.vbox(4)
	p.add_child(v)
	v.add_child(JwUi.label(JwText.t("ov.terminal.title"), "title_sub", "text.secondary"))
	for t: Dictionary in JwDiagnose.terminal_block(session):
		v.add_child(JwUi.class_line(JwInfo.Cls.DERIVED, String(t["text"])))
	v.add_child(JwUi.para(JwText.t("brief.terminal_note"), "text.muted"))
	return p


# ── 诊断卡 ─────────────────────────────────────────────────────────────

func _diag_stack(short: bool) -> VBoxContainer:
	var v: VBoxContainer = JwUi.vbox(12)
	JwUi.tag(v, "DiagnosticStack")
	var res: Dictionary = JwDiagnose.run(session)
	var cards: Array = res["cards"]
	v.add_child(JwUi.label(JwText.render("tpl.brief.header", {"quarter": JwFormat.quarter(session.model.q),
			"shown_count": str(cards.size()), "total_count": str(int(res["total"]))}), "title_block", "text.primary", true))
	if cards.is_empty():
		var p: PanelContainer = JwUi.panel("bg.panel", "line.hair", 14)
		JwUi.tag(p, "DiagEmpty")
		p.add_child(JwUi.empty_state(JwText.render("tpl.brief.empty", {"horizon_quarters": JwFormat.quarters(int(res["horizon"])),
				"weight_floor_pct": JwFormat.pct(int(res["floor_pw"])), "total_count": str(int(res["total"]))}),
				JwText.t("ov.diag.empty.when"), JwText.t("ov.diag.empty.rule")))
		v.add_child(p)
	for i: int in cards.size():
		var full: bool = not short or i == 0 or bool(_expanded.get(i, false))
		v.add_child(_diag_card(cards[i], i, full))
	if int(res["folded"]) > 0:
		var th: Dictionary = session.catalog.cfg("diag_thresholds", {})
		v.add_child(JwUi.label(JwText.render("tpl.brief.folded", {"folded_count": str(int(res["folded"])),
				"horizon_quarters": JwFormat.quarters(int(th.get("urgency_horizon_q", 4))),
				"weight_floor_pct": JwFormat.pct(int(th.get("pop_weight_floor_ppm", 100000)))}), "body", "text.muted", true))
	if bool(res.get("single_domain", false)) and cards.size() > 1:
		v.add_child(JwUi.para(JwText.render("tpl.brief.single_domain", {"domain_name":
				JwText.t("domain." + String((cards[0] as Dictionary)["domain"]))}), "text.muted"))
	return v


func _diag_card(c: Dictionary, i: int, full: bool) -> PanelContainer:
	var sev: int = int(c.get("severity", JwInfo.Sev.NOTE))
	var p: PanelContainer = JwUi.panel_style(JwTheme.box_left_rule("bg.panel", JwInfo.sev_color_token(sev), 3, 14))
	JwUi.tag(p, "DiagCard%d" % i)
	p.set_meta("diag_code", String(c.get("code", "")))
	p.set_meta("severity", sev)
	var v: VBoxContainer = JwUi.vbox(6)
	p.add_child(v)
	var head: HBoxContainer = JwUi.hbox(10)
	JwUi.tag(head, "Header")
	head.add_child(JwUi.risk_badge(sev, JwInfo.sev_word(sev)))
	head.add_child(JwUi.label(String(c.get("title", "")), "title_sub", "text.primary", true))
	if not full:
		var ex: Button = JwUi.button(JwText.t("common.expand"))
		ex.pressed.connect(func() -> void:
			_expanded[i] = true
			note_expand("DiagCard%d" % i)
			refresh())
		head.add_child(ex)
	v.add_child(head)
	if not full:
		return p
	var sym: HBoxContainer = JwUi.class_line(JwInfo.Cls.ACTUAL, String(c.get("symptom", "")))
	JwUi.tag(sym, "Symptom")
	v.add_child(sym)
	var evb: HBoxContainer = JwUi.hbox(8)
	JwUi.tag(evb, "Evidence")
	evb.add_child(JwUi.label(JwText.t("diag.evidence_head"), "body_bold", "text.secondary"))
	var flow: HFlowContainer = HFlowContainer.new()
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for e: Variant in c.get("evidence", []):
		var ed: Dictionary = e
		var b: Button = JwUi.link(JwText.render("tpl.diag.evidence_item", {"ledger_name": JwText.t("ledger.name." + String(ed["ledger"])),
				"count_text": String(ed["count"])}))
		var led: String = String(ed["ledger"])
		b.pressed.connect(func() -> void: _on_ledger(led, 0))
		flow.add_child(b)
	evb.add_child(flow)
	v.add_child(evb)
	var mech: VBoxContainer = JwUi.vbox(4)
	JwUi.tag(mech, "Mechanism")
	mech.name = "MechanismSection"
	mech.add_child(JwUi.class_line(JwInfo.Cls.DERIVED, String(c.get("mechanism", ""))))
	if c.has("bounds"):
		var bd: Dictionary = c["bounds"]
		var unit: String = JwText.t("sector.unit.%d" % int(c.get("bounds_sector", 0)))
		mech.add_child(JwUi.class_line(JwInfo.Cls.DERIVED, JwText.render("tpl.diag.bounds_list", {
			"b_plan": _bound_text(int(bd["plan"])), "b_capacity": _bound_text(int(bd["capacity"])),
			"b_labor": _bound_text(int(bd["labor"])), "b_energy": _bound_text(int(bd["energy"])),
			"b_materials": _bound_text(int(bd["materials"])), "q_actual": JwFormat.qty(int(bd["actual"]), unit)})))
	var mans: Array = c.get("manifestations", [])
	if not mans.is_empty():
		mech.add_child(JwUi.para(JwText.render("tpl.brief.manifestations", {"items": mans}), "text.secondary"))
	var urg: int = int(c.get("urgency_q", 99))
	var ut: String = JwText.render("tpl.brief.urgency_now", {"threshold_name": JwText.t("diag.threshold." + String(c["domain"])),
			"rule_id": "^R-DIAG-" + String(c["domain"]).to_upper()}) if urg == 0 else \
			(JwText.render("tpl.brief.urgency_soon", {"trigger_quarter": JwFormat.quarter(session.model.q + urg),
			"remaining_quarters": JwFormat.quarters(urg), "threshold_name": JwText.t("diag.threshold." + String(c["domain"])),
			"rule_id": "^R-DIAG-" + String(c["domain"]).to_upper()}) if urg < 99 else \
			JwText.render("tpl.brief.urgency_unknown", {"rule_id": "^R-DIAG-" + String(c["domain"]).to_upper()}))
	mech.add_child(JwUi.para(JwInfo.prefix(JwInfo.Cls.DERIVED) + ut, "text.secondary"))
	mech.add_child(JwUi.para(JwText.render("tpl.brief.scope", {"affected_persons": JwFormat.persons(int(c.get("affected_persons", 0))),
			"share_pct": JwFormat.pct(int(c.get("pop_weight_ppm", 0)))}), "text.muted"))
	v.add_child(mech)
	var inter: VBoxContainer = JwUi.vbox(4)
	JwUi.tag(inter, "Intervention")
	inter.add_child(JwUi.label(JwText.t("diag.intervention_head"), "body_bold", "text.secondary"))
	var items: Array = c.get("interventions", [])
	if items.is_empty():
		inter.add_child(JwUi.para(JwText.render("tpl.brief.no_tool", {"explain": JwText.t("diag.no_tool." + String(c["domain"]))}), "text.secondary"))
	else:
		inter.add_child(JwUi.para(JwText.t("tpl.diag.order_note"), "text.muted"))
		for it: Variant in items:
			var itd: Dictionary = it
			var txt: String = JwText.render("tpl.diag.action", {"action_label": String(itd["label"]),
					"capex_u": JwFormat.u(int(itd["capex"])), "opex_u": JwFormat.u(int(itd["opex"])),
					"feedback_quarter": JwFormat.quarter(int(itd["feedback_q"]))})
			if bool(itd.get("blocked", false)):
				txt = JwText.render("tpl.diag.action_blocked", {"action_label": txt, "reason_line2": String(itd["blocked_line"])})
			var b2: Button = JwUi.button(txt)
			b2.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b2.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			b2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var pp: int = int(itd["p"])
			b2.pressed.connect(func() -> void:
				session.log_event("ev.intervention_opened", {"p": pp})
				goto_page("policy", {"p": pp}))
			inter.add_child(b2)
		var hold: Button = JwUi.button(JwText.t("diag.action.hold"))
		hold.alignment = HORIZONTAL_ALIGNMENT_LEFT
		hold.pressed.connect(func() -> void: note_expand("DiagCard%d/Hold" % i))
		inter.add_child(hold)
		inter.add_child(JwUi.para(JwText.t("tpl.diag.no_guarantee"), "text.muted"))
	v.add_child(inter)
	return p


func get_required_above_fold(band: int) -> Array[StringName]:
	if band == JwScale.HBand.SHORT:
		return [&"PillarOutput", &"PillarLabor", &"PillarFiscal", &"HeadroomNoDraft", &"RegionStrip",
				&"Theme0", &"Theme1", &"Theme2", &"Theme3"]
	return [&"PillarOutput", &"PillarLabor", &"PillarFiscal", &"OutputMeta", &"UnemploymentMeta",
			&"HeadroomNoDraft", &"RegionStrip", &"MapLegend", &"Theme0", &"Theme1", &"Theme2", &"Theme3",
			&"RecentLedgerStrip"]
