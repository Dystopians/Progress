## 页面二 · 地区（docs/20 §7.2）：「同一条全国指标，为什么四个地区表现不同？差异出在哪个环节？」
##
## 约束阶梯（本页最重要的控件）：Q_actual = min(计划, 产能, 劳动, 电力, 材料)，五根同量纲横条，
## 最紧项加 ◀紧 + 描边 + 文字（三通道）；条下固定两行：算（解除后的次紧约束）与 预（不利条件下的区间）。
## 禁止合成「瓶颈指数」（B-04）。并排四区模式不打分、不排名（§7.2.4）。
## 拓扑与物流系数从剧本读取（content.region.adjacency / logistics_cost_ppm），界面不硬编码。
class_name JwRegionPage
extends JwPage

var region: int = 2
var sector: int = 1
var compare: bool = false
var _root: VBoxContainer = null


func apply_context(ctx: Dictionary) -> void:
	if ctx.has("region"):
		region = clampi(int(ctx["region"]), 0, 3)


func refresh() -> void:
	if _root != null:
		remove_child(_root)
		_root.queue_free()
	_root = JwUi.vbox(12)
	_root.name = "RegionRoot"
	add_child(_root)
	if session == null or session.game == null:
		_root.add_child(JwUi.empty_state(JwText.t("rg.empty.why"), JwText.t("rg.empty.when"), JwText.t("rg.empty.rule")))
		return
	_root.add_child(term_strip())
	_root.add_child(_tabs())
	var sc: ScrollContainer = JwUi.scroll(JwUi.vbox(0))
	var inner: VBoxContainer = sc.get_child(0) as VBoxContainer
	inner.add_theme_constant_override("separation", 12)
	_root.add_child(sc)
	if compare:
		inner.add_child(_compare_table())
		return
	var main: HBoxContainer = JwUi.hbox(14)
	inner.add_child(main)
	var left: VBoxContainer = JwUi.vbox(12)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_child(_region_card())
	left.add_child(_adjacency())
	left.add_child(_account_strip())
	main.add_child(left)
	var right: VBoxContainer = JwUi.vbox(12)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_stretch_ratio = 1.3
	right.add_child(_ladder())
	main.add_child(right)
	inner.add_child(_quads())


func _tabs() -> HBoxContainer:
	var m: JwReadModel = session.model
	var h: HBoxContainer = JwUi.hbox(8)
	JwUi.tag(h, "RegionTabs")
	for r: int in JwReadModel.R:
		var b: Button = JwUi.button(session.catalog.region_label(r) + " " + JwFormat.persons(m.region_population(r)), "TabBtn")
		b.toggle_mode = true
		b.button_pressed = r == region and not compare
		var rr: int = r
		b.pressed.connect(func() -> void:
			region = rr
			compare = false
			refresh())
		h.add_child(b)
	h.add_child(JwUi.spacer())
	var cb: CheckBox = CheckBox.new()
	cb.text = JwText.t("rg.compare")
	cb.button_pressed = compare
	cb.toggled.connect(func(on: bool) -> void:
		compare = on
		refresh())
	h.add_child(cb)
	return h


func _region_card() -> PanelContainer:
	var m: JwReadModel = session.model
	var cat: JwCatalog = session.catalog
	var sec: Dictionary = JwUi.section(cat.region_label(region), cat.region_theme(region))
	var body: VBoxContainer = sec["body"]
	var un: Dictionary = m.region_unemployment(region)
	var h: HBoxContainer = JwUi.hbox(18)
	var pop_cell: JwNumberCell = num(JwFormat.wan_num(m.region_population(region)), JwText.t("unit.wan_persons"), JwInfo.Cls.ACTUAL,
			"block_num", {"measure": JwText.t("measure.stock"), "period": JwText.t("period.q_end"), "ledger": "household",
			"rule_key": "population"})
	h.add_child(_labeled(JwText.t("rg.pop"), pop_cell))
	var un_cell: JwNumberCell = num(JwFormat.pct_num(int(un["rate_ppm"])), "%", JwInfo.Cls.ACTUAL, "block_num",
			{"measure": JwText.t("measure.ratio"), "period": JwText.t("period.this_q"),
			"denominator": JwText.render("denom.labor_force", {"n": JwFormat.persons(int(un["labor_force"]))}),
			"ledger": "labor", "rule_key": "unemployment"})
	h.add_child(_labeled(JwText.t("rg.unemp"), un_cell))
	var va_cell: JwNumberCell = num(JwFormat.u_num(m.region_va_real(region)), "U", JwInfo.Cls.ACTUAL, "block_num",
			{"measure": JwText.t("measure.flow"), "period": JwText.t("period.this_q"), "price_base": JwText.t("price.base_year"),
			"ledger": "value_added", "rule_key": "real_gdp"})
	h.add_child(_labeled(JwText.t("rg.va"), va_cell))
	body.add_child(h)
	body.add_child(JwUi.caption(JwText.render("rg.card.caption", {"lf": JwFormat.persons(int(un["labor_force"])),
			"un": JwFormat.persons(int(un["unemployed"]))}), un_cell))
	return sec["root"]


func _labeled(t: String, c: Control) -> VBoxContainer:
	var v: VBoxContainer = JwUi.vbox(2)
	v.add_child(JwUi.label(t, "body", "text.secondary"))
	v.add_child(c)
	return v


## 邻接与物流成本（剧本数据；每条边显示系数与基准定义，§7.2.5）。
func _adjacency() -> PanelContainer:
	var m: JwReadModel = session.model
	var cat: JwCatalog = session.catalog
	var sec: Dictionary = JwUi.section(JwText.t("rg.adj.title"))
	var body: VBoxContainer = sec["body"]
	JwUi.tag(sec["root"], "Adjacency")
	for r2: int in JwReadModel.R:
		if r2 == region:
			continue
		var adj: int = m.at("content.region.adjacency", region * 4 + r2)
		var cost: int = m.at("content.region.logistics_cost_ppm", region * 4 + r2)
		var txt: String = JwText.render("rg.adj.edge", {"to": cat.region_label(r2), "cost": JwFormat.pct(cost)}) if adj == 1 \
				else JwText.render("rg.adj.none", {"to": cat.region_label(r2)})
		body.add_child(JwUi.class_line(JwInfo.Cls.ACTUAL, txt))
	body.add_child(JwUi.caption(JwText.t("rg.adj.basis")))
	return sec["root"]


func _account_strip() -> PanelContainer:
	var m: JwReadModel = session.model
	var sec: Dictionary = JwUi.section(JwText.t("rg.acct.title"))
	JwUi.tag(sec["root"], "RegionAccountStrip")
	var body: VBoxContainer = sec["body"]
	if not m.settled():
		body.add_child(JwUi.label(JwText.t("rg.acct.cold"), "body", "text.muted", true))
		return sec["root"]
	var w: int = 0
	var tr: int = 0
	var tx: int = 0
	var hc: int = 0
	for g: int in m.region_groups(region):
		w += m.at("flow.group.wage_income_uu", g)
		tr += m.at("flow.group.transfer_income_uu", g)
		tx += m.at("flow.group.income_tax_paid_uu", g)
		hc += m.at("flow.group.housing_cost_uu", g)
	body.add_child(JwUi.class_line(JwInfo.Cls.ACTUAL, JwText.render("rg.acct.line", {"quarter": JwFormat.quarter(m.q - 1),
			"wages": JwFormat.u(w), "transfers": JwFormat.u(tr), "tax": JwFormat.u(tx), "housing": JwFormat.u(hc),
			"citation": JwFormat.citation(JwText.t("ledger.alias.household"), m.q - 1, region + 1)})))
	return sec["root"]


# ── 约束阶梯 ───────────────────────────────────────────────────────────

func _ladder() -> PanelContainer:
	var m: JwReadModel = session.model
	var cat: JwCatalog = session.catalog
	var sec: Dictionary = JwUi.section(JwText.t("rg.ladder.title"))
	var root: PanelContainer = sec["root"]
	JwUi.tag(root, "ConstraintLadder")
	var body: VBoxContainer = sec["body"]
	var sh: HBoxContainer = JwUi.hbox(6)
	for s2: int in JwReadModel.S:
		var b: Button = JwUi.button(JwText.t("sector.%d" % s2), "TabBtn")
		b.toggle_mode = true
		b.button_pressed = s2 == sector
		var ss: int = s2
		b.pressed.connect(func() -> void:
			sector = ss
			note_expand("ConstraintLadder", "sector.%d" % ss)
			refresh())
		sh.add_child(b)
	body.add_child(sh)
	var c: int = JwReadModel.idx_cell(region, sector)
	var bd: Dictionary = m.cell_bounds(c)
	var unit: String = JwText.t("sector.unit.%d" % sector)
	body.add_child(JwUi.class_line(JwInfo.Cls.DERIVED, JwText.render("rg.ladder.head", {"region": cat.region_label(region),
			"sector": JwText.t("sector.%d" % sector), "unit": unit})))
	if not m.settled():
		body.add_child(JwUi.empty_state(JwText.t("rg.ladder.cold.why"), JwText.t("rg.ladder.cold.when"), JwText.t("rg.ladder.cold.rule")))
		return root
	var keys: Array = ["plan", "capacity", "labor", "energy", "materials"]
	var vmax: int = 1
	for k: String in keys:
		if int(bd[k]) < JwReadModel.U * 1000:
			vmax = maxi(vmax, int(bd[k]))
	var binding: int = int(bd["binding"])
	var grid: GridContainer = GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 8)
	for i: int in keys.size():
		var val: int = int(bd[String(keys[i])])
		var tight: bool = i == binding
		var lab: VBoxContainer = JwUi.vbox(0)
		lab.add_child(JwUi.label(JwText.t("binding.%d" % i), "body_bold" if tight else "body", "text.primary"))
		lab.add_child(JwUi.label(JwText.t("binding.sym.%d" % i), "caption", "text.muted"))
		lab.custom_minimum_size = Vector2(90, 0)
		grid.add_child(lab)
		var coeff_zero: bool = val >= JwReadModel.U * 1000
		var bar: JwBar = JwBar.make(0.0 if coeff_zero else float(val) / float(vmax), "series.3" if not tight else "teal.core",
				"ochre.core" if tight else "", 20)
		grid.add_child(bar)
		var vl: Label = JwUi.label(JwText.t("rg.ladder.na") if coeff_zero else JwFormat.qty_num(val), "num", "text.primary")
		vl.custom_minimum_size = Vector2(110, 0)
		vl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		grid.add_child(vl)
		var mk: HBoxContainer = JwUi.hbox(4)
		mk.custom_minimum_size = Vector2(110, 0)
		if tight:
			mk.add_child(JwIcon.make("warn", JwTheme.c("ochre.core"), 14))
			mk.add_child(JwUi.label(JwText.t("rg.ladder.tight"), "body_bold", "ochre.core"))
		grid.add_child(mk)
	body.add_child(grid)
	body.add_child(JwUi.class_line(JwInfo.Cls.DERIVED, JwText.render("rg.ladder.actual", {"actual": JwFormat.qty(int(bd["actual"]), unit),
			"rule_id": "^R-PROD-03"})))
	# 解除当前紧约束后的次紧约束（规则推断，假设其余四项不变；计划量也参与 min）。
	var next_b: int = -1
	var next_v: int = 0
	for j: int in keys.size():
		if j == binding:
			continue
		var vv: int = int(bd[String(keys[j])])
		if next_b < 0 or vv < next_v:
			next_b = j
			next_v = vv
	var ties: PackedStringArray = JwRegionPage.tie_names(bd, binding)
	if binding == JwReadModel.BIND_PLAN:
		body.add_child(JwUi.class_line(JwInfo.Cls.DERIVED, JwText.render("rg.ladder.plan", {"rule_id": "^R-PROD-03"})))
	else:
		body.add_child(JwUi.class_line(JwInfo.Cls.DERIVED, JwText.render("tpl.derived.next_binding", {
			"bound_name": JwText.t("binding.%d" % binding), "next_bound_name": JwText.t("binding.%d" % next_b),
			"next_output_qty": JwFormat.qty(next_v, unit) + JwText.render("rg.ladder.delta", {"d": JwFormat.qty(next_v - int(bd["actual"]), unit)}),
			"rule_id": "^R-PROD-03", "citations": JwFormat.citation(JwText.t("ledger.alias.constraint"), m.q - 1, c + 1)})))
	if not ties.is_empty():
		body.add_child(JwUi.class_line(JwInfo.Cls.DERIVED, JwText.render("rg.ladder.ties", {"list": "、".join(ties),
				"rule_id": "^R-PROD-03"})))
	var adv: Dictionary = session.run("adv_lo")
	var adv2: Dictionary = session.run("adv_hi")
	var a1: PackedInt64Array = adv.get("cell_output_q0", PackedInt64Array())
	var a2: PackedInt64Array = adv2.get("cell_output_q0", PackedInt64Array())
	if a1.size() > c and a2.size() > c:
		body.add_child(JwUi.class_line(JwInfo.Cls.PROJECTED, JwText.render("rg.ladder.adverse", {"range": JwText.render("rg.ladder.range",
				{"lo": JwFormat.qty_num(mini(a1[c], a2[c])), "hi": JwFormat.qty_num(maxi(a1[c], a2[c])), "unit": unit}),
				"q": JwFormat.quarter(m.q)})))
	else:
		body.add_child(JwUi.label(JwText.t("rg.ladder.adverse_pending"), "body", "warm.text"))
	body.add_child(JwUi.caption(JwText.t("rg.ladder.note")))
	return root


## 与紧约束持平（等于实际产出）的其余约束名（取 min 时并列）。
static func tie_names(bd: Dictionary, binding: int) -> PackedStringArray:
	var keys: Array = ["plan", "capacity", "labor", "energy", "materials"]
	var out: PackedStringArray = PackedStringArray()
	for j: int in keys.size():
		if j == binding:
			continue
		var v: int = int(bd[String(keys[j])])
		if v < JwReadModel.U * 1000 and v == int(bd["actual"]):
			out.append(JwText.t("binding.%d" % j))
	return out


# ── 四象限 ─────────────────────────────────────────────────────────────

func _quads() -> GridContainer:
	var g: GridContainer = GridContainer.new()
	g.columns = 2 if wband == JwScale.WBand.WIDE else 1
	g.add_theme_constant_override("h_separation", 12)
	g.add_theme_constant_override("v_separation", 12)
	g.add_child(_q1())
	g.add_child(_q2())
	g.add_child(_q3())
	g.add_child(_q4())
	return g


func _q1() -> PanelContainer:
	var m: JwReadModel = session.model
	var sec: Dictionary = JwUi.section(JwText.t("rg.q1"))
	JwUi.tag(sec["root"], "Quad1")
	(sec["root"] as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var t: JwTable = JwTable.make([
		{"title": JwText.t("rg.q1.col.sector"), "w": 90},
		{"title": JwText.t("rg.q1.col.output"), "w": 130, "align": "r"},
		{"title": JwText.t("rg.q1.col.va"), "w": 170, "align": "r"},
		{"title": JwText.t("rg.q1.col.binding"), "w": 110, "expand": true},
	], false, false)
	for s2: int in JwReadModel.S:
		var c: int = JwReadModel.idx_cell(region, s2)
		t.add_row([JwText.t("sector.%d" % s2),
			{"text": JwFormat.qty_num(m.at("flow.cell.output_actual_uqs", c)), "cls": JwInfo.Cls.ACTUAL},
			{"text": JwFormat.u_num(m.at("flow.cell.value_added_real_uu", c)), "cls": JwInfo.Cls.ACTUAL},
			{"text": JwText.t("binding.%d" % m.at("flow.cell.binding_code", c)) if m.settled() else JwText.t("ov.layer.cold_value"),
				"cls": JwInfo.Cls.DERIVED}], JwInfo.Cls.ACTUAL)
	t.add_note(JwText.t("rg.q1.note"))
	(sec["body"] as VBoxContainer).add_child(t)
	return sec["root"]


func _q2() -> PanelContainer:
	var m: JwReadModel = session.model
	var sec: Dictionary = JwUi.section(JwText.t("rg.q2"))
	JwUi.tag(sec["root"], "Quad2")
	(sec["root"] as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var t: JwTable = JwTable.make([
		{"title": JwText.t("rg.q2.col.group"), "w": 150},
		{"title": JwText.t("rg.q2.col.pop"), "w": 120, "align": "r"},
		{"title": JwText.t("rg.q2.col.emp"), "w": 120, "align": "r"},
		{"title": JwText.t("rg.q2.col.burden"), "w": 120, "align": "r", "expand": true},
	], false, false)
	for g: int in m.region_groups(region):
		var age: int = JwReadModel.age_of_group(g)
		var lf: int = m.group_labor_force(g)
		var er: String = JwText.t("common.na")
		if age == JwReadModel.AGE_WORKING and lf > 0:
			@warning_ignore("integer_division")
			er = JwFormat.pct(mini(m.group_employed(g), lf) * JwReadModel.PPM / lf)
		var bd: int = m.group_burden(g)
		t.add_row([JwText.t("age.%d" % age) + "·" + JwText.t("skill.short.%d" % JwReadModel.skill_of_group(g)),
			{"text": JwFormat.group3(m.group_population(g)) if m.group_population(g) > 0 else JwText.t("common.empty_group"),
				"cls": JwInfo.Cls.ACTUAL},
			{"text": er, "cls": JwInfo.Cls.ACTUAL},
			{"text": JwFormat.pct(bd) if bd >= 0 else JwText.t("common.none"), "cls": JwInfo.Cls.ACTUAL}], JwInfo.Cls.ACTUAL)
	t.add_note(JwText.t("rg.q2.note"))
	(sec["body"] as VBoxContainer).add_child(t)
	return sec["root"]


func _q3() -> PanelContainer:
	var m: JwReadModel = session.model
	var sec: Dictionary = JwUi.section(JwText.t("rg.q3"))
	JwUi.tag(sec["root"], "Quad3")
	(sec["root"] as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var body: VBoxContainer = sec["body"]
	var bd: Dictionary = m.region_burden(region)
	var hb: HBoxContainer = JwUi.hbox(8)
	JwUi.tag(hb, "HouseholdBurden")
	hb.add_child(JwUi.label(JwText.t("rg.q3.burden"), "body_bold", "text.secondary"))
	var burden_cell: JwNumberCell = num(JwFormat.pct_num(int(bd["ppm"])) if int(bd["ppm"]) >= 0 else JwText.t("common.na"), "%",
			JwInfo.Cls.ACTUAL, "block_num", {"measure": JwText.t("measure.ratio"), "period": JwText.t("period.this_q"),
			"denominator": JwText.t("denom.disposable"), "ledger": "household", "rule_key": "household_burden"})
	hb.add_child(burden_cell)
	body.add_child(hb)
	body.add_child(JwUi.caption(JwText.render("rg.q3.burden_abs", {"housing": JwFormat.u(int(bd["housing_uu"])),
			"disp": JwFormat.u(int(bd["disposable_uu"]))}), burden_cell))
	body.add_child(JwUi.class_line(JwInfo.Cls.ACTUAL, JwText.render("rg.q3.power", {"avail": JwFormat.pct(m.elec_availability(region)),
			"cap": JwFormat.qty(m.at("state.region.grid_capacity_uqs_per_q", region), JwText.t("sector.unit.2")),
			"pending": JwFormat.qty(m.at("state.region.grid_capacity_pending_uqs_per_q", region), JwText.t("sector.unit.2"))})))
	body.add_child(JwUi.class_line(JwInfo.Cls.ACTUAL, JwText.render("rg.q3.service", {"avail": JwFormat.pct(m.pubserv_availability(region)),
			"teachers": JwFormat.persons(m.at("state.pubserv.teachers_persons", region)),
			"health": JwFormat.persons(m.at("state.pubserv.health_staff_persons", region))})))
	body.add_child(JwUi.class_line(JwInfo.Cls.ACTUAL, JwText.render("rg.q3.housing", {
			"stock": JwFormat.group3(m.at("state.region.housing_stock_units", region)),
			"cap": JwFormat.group3(m.at("state.region.housing_capacity_units", region)),
			"pending": JwFormat.group3(m.at("state.region.housing_pending_units", region))})))
	return sec["root"]


func _q4() -> PanelContainer:
	var m: JwReadModel = session.model
	var cat: JwCatalog = session.catalog
	var sec: Dictionary = JwUi.section(JwText.t("rg.q4"))
	JwUi.tag(sec["root"], "Quad4")
	(sec["root"] as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var body: VBoxContainer = sec["body"]
	body.add_child(JwUi.class_line(JwInfo.Cls.ACTUAL, JwText.render("rg.q4.slots", {"used": str(m.slots_used(region)),
			"total": str(m.slots_total(region))})))
	var n: int = 0
	for row: Dictionary in m.project_rows():
		if int(row["region"]) != region:
			continue
		n += 1
		body.add_child(JwUi.class_line(JwInfo.Cls.ACTUAL, JwText.render("rg.q4.project", {
			"name": String(cat.policy(int(row["policy"])).get("label", "")), "status": JwText.t("project_status.%d" % int(row["status"])),
			"paid": JwFormat.u(int(row["paid"])), "total": JwFormat.u(int(row["total"])),
			"prog": JwFormat.pct(mini(int(row["delivery_ppm"]), int(row["construction_ppm"])))})))
	if n == 0:
		body.add_child(JwUi.label(JwText.t("rg.q4.none"), "body", "text.muted", true))
	var lk: Button = JwUi.link(JwText.t("rg.q4.link"))
	lk.pressed.connect(func() -> void: _on_ledger("project", 0))
	body.add_child(lk)
	return sec["root"]


## 并排四区（不打分、不排名；列头写明「未排序」）。
func _compare_table() -> PanelContainer:
	var m: JwReadModel = session.model
	var cat: JwCatalog = session.catalog
	var sec: Dictionary = JwUi.section(JwText.t("rg.cmp.title"), JwText.t("rg.cmp.note"))
	var cols: Array = [{"title": JwText.t("rg.cmp.col.metric"), "w": 200}]
	for r: int in JwReadModel.R:
		cols.append({"title": cat.region_label(r), "w": 160, "align": "r", "expand": true})
	var t: JwTable = JwTable.make(cols, false, true)
	var rows: Array = []
	var r_pop: Array = [JwText.t("rg.pop")]
	var r_un: Array = [JwText.t("rg.unemp")]
	var r_va: Array = [JwText.t("rg.va")]
	var r_el: Array = [JwText.t("layer.power")]
	var r_bd: Array = [JwText.t("layer.housing")]
	var r_bind: Array = [JwText.t("layer.constraint")]
	for r2: int in JwReadModel.R:
		r_pop.append({"text": JwFormat.persons(m.region_population(r2)), "cls": JwInfo.Cls.ACTUAL})
		r_un.append({"text": JwFormat.pct(int(m.region_unemployment(r2)["rate_ppm"])), "cls": JwInfo.Cls.ACTUAL})
		r_va.append({"text": JwFormat.u(m.region_va_real(r2)), "cls": JwInfo.Cls.ACTUAL})
		r_el.append({"text": JwFormat.pct(m.elec_availability(r2)), "cls": JwInfo.Cls.ACTUAL})
		var b: int = int(m.region_burden(r2)["ppm"])
		r_bd.append({"text": JwFormat.pct(b) if b >= 0 else JwText.t("common.na"), "cls": JwInfo.Cls.ACTUAL})
		r_bind.append({"text": JwText.t("binding.%d" % m.region_binding(r2)), "cls": JwInfo.Cls.DERIVED})
	rows = [[r_pop, JwInfo.Cls.ACTUAL], [r_un, JwInfo.Cls.ACTUAL], [r_va, JwInfo.Cls.ACTUAL], [r_el, JwInfo.Cls.ACTUAL],
			[r_bd, JwInfo.Cls.ACTUAL], [r_bind, JwInfo.Cls.DERIVED]]
	for rw: Array in rows:
		t.add_row(rw[0], int(rw[1]))
	(sec["body"] as VBoxContainer).add_child(t)
	return sec["root"]


func get_required_above_fold(band: int) -> Array[StringName]:
	if band == JwScale.HBand.SHORT:
		return [&"RegionTabs", &"ConstraintLadder"]
	return [&"RegionTabs", &"ConstraintLadder", &"RegionAccountStrip"]
