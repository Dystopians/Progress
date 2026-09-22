## 页面四 · 社会（docs/20 §7.4）：「这条政策，谁受益、谁受损、谁会反对？他们的不满是哪一种不满？」
##
## 36 格群组矩阵（4 地区 × 3 年龄 × 3 技能；`·` 空组 / `—` 该字段不适用）、分布条（P10/P50/均值/P90）、
## 三类民意三个独立数字（不相加、不平均、不合成）、三个集团各自单列、受益受损清单（本季结算 / 当前草案）。
## 不输出基尼系数或任何分配评分；常驻不可关闭的精度说明条（§7.4.5）。
class_name JwSocietyPage
extends JwPage

const FIELDS: PackedStringArray = ["income", "burden", "access", "edu"]
## 集团立场的展示分档（界面暂定，只决定列在「倾向支持 / 倾向反对」哪一栏；否决阈值另取规则参数）。
const STANCE_SUP_PPM: int = 200_000
const STANCE_OPP_PPM: int = -150_000

var field: String = "income"
var source: String = "settled"
var focus_group: int = -1
var _root: VBoxContainer = null


func apply_context(ctx: Dictionary) -> void:
	if ctx.has("source"):
		source = "draft" if String(ctx["source"]) == "draft" else "settled"


func refresh() -> void:
	if _root != null:
		remove_child(_root)
		_root.queue_free()
	_root = JwUi.vbox(12)
	_root.name = "SocietyRoot"
	add_child(_root)
	if session == null or session.game == null:
		_root.add_child(JwUi.empty_state(JwText.t("so.empty.why"), JwText.t("so.empty.when"), JwText.t("so.empty.rule")))
		return
	var note: PanelContainer = JwUi.panel_style(JwTheme.box4("bg.raised", "line.strong", 1, 12, 6, 12, 6))
	JwUi.tag(note, "PrecisionNote")
	note.add_child(JwUi.label(JwText.t("so.precision"), "body", "text.secondary", true))
	_root.add_child(term_strip())
	_root.add_child(note)
	var sc: ScrollContainer = JwUi.scroll(JwUi.vbox(12))
	var inner: VBoxContainer = sc.get_child(0) as VBoxContainer
	_root.add_child(sc)
	var top: HBoxContainer = JwUi.hbox(14)
	inner.add_child(top)
	var left: VBoxContainer = JwUi.vbox(12)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.4
	left.add_child(_matrix())
	top.add_child(left)
	var right: VBoxContainer = JwUi.vbox(12)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_child(_moods())
	right.add_child(_distribution())
	top.add_child(right)
	var bottom: HBoxContainer = JwUi.hbox(14)
	inner.add_child(bottom)
	var bl: Control = _blocs()
	bl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(bl)
	var wl: Control = _winners_losers()
	wl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(wl)


# ── 36 格矩阵 ─────────────────────────────────────────────────────────────

func _matrix() -> PanelContainer:
	var m: JwReadModel = session.model
	var cat: JwCatalog = session.catalog
	var sec: Dictionary = JwUi.section(JwText.t("so.matrix.title"))
	var root: PanelContainer = sec["root"]
	JwUi.tag(root, "GroupMatrix")
	var body: VBoxContainer = sec["body"]
	var fh: HBoxContainer = JwUi.hbox(8)
	JwUi.tag(fh, "MatrixHeader")
	fh.add_child(JwUi.label(JwText.t("so.matrix.field"), "body", "text.secondary"))
	var ob: OptionButton = OptionButton.new()
	ob.name = "FieldSwitcher"
	for i: int in FIELDS.size():
		ob.add_item(JwText.t("so.field." + FIELDS[i]), i)
	ob.select(FIELDS.find(field))
	ob.item_selected.connect(func(i: int) -> void:
		field = FIELDS[i]
		session.log_event("ev.matrix_field_changed", {"field": field})
		refresh())
	fh.add_child(ob)
	body.add_child(fh)
	var grid: GridContainer = GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	for head: String in [JwText.t("so.col.region"), JwText.t("so.col.age"), JwText.t("skill.0"), JwText.t("skill.1"),
			JwText.t("skill.2")]:
		var hl: Label = JwUi.label(head, "title_sub", "text.primary")
		hl.custom_minimum_size = Vector2(80, 0)
		grid.add_child(hl)
	var n_cells: int = 0
	var prev: Dictionary = _base_hist()
	for r: int in JwReadModel.R:
		for age: int in 3:
			grid.add_child(JwUi.label(cat.region_label(r) if age == 0 else "", "body_bold", "text.secondary"))
			grid.add_child(JwUi.label(JwText.t("age.%d" % age), "body", "text.secondary"))
			for sk: int in 3:
				var g: int = JwReadModel.idx_group(r, age, sk)
				grid.add_child(_cell(g, prev))
				n_cells += 1
	body.add_child(grid)
	root.set_meta("cell_count", n_cells)
	var foot: Label = JwUi.label(JwText.render("so.matrix.footer." + field, {"base_q": _base_label(prev)}), "caption", "text.muted", true)
	JwUi.tag(foot, "MatrixFooter")
	body.add_child(foot)
	return root


func _base_hist() -> Dictionary:
	for h: Dictionary in session.history:
		if int(h.get("q", -1)) >= 0:
			return h
	return {}


func _base_label(h: Dictionary) -> String:
	if h.is_empty():
		return JwText.t("so.base.none")
	return JwFormat.quarter(int(h.get("q", 0)))


func _cell(g: int, base: Dictionary) -> PanelContainer:
	var m: JwReadModel = session.model
	var pop: int = m.group_population(g)
	var age: int = JwReadModel.age_of_group(g)
	var sel: bool = g == focus_group
	var p: PanelContainer = JwUi.panel_style(JwTheme.box4("bg.raised", "focus.ring" if sel else "line.hair", 2 if sel else 1, 6, 4, 6, 4))
	p.custom_minimum_size = Vector2(150, 64)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.set_meta("group", g)
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	p.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed:
			focus_group = g
			session.log_event("ev.group_focused", {"group_id": g})
			refresh())
	var v: VBoxContainer = JwUi.vbox(0)
	p.add_child(v)
	if pop <= 0:
		p.set_meta("symbol", "empty")
		v.add_child(JwUi.label(JwText.t("common.empty_group"), "num_bold", "text.muted"))
		v.add_child(JwUi.label(JwText.t("so.cell.empty"), "caption", "text.muted"))
		return p
	v.add_child(JwUi.label(JwFormat.persons(pop), "num", "text.primary"))
	var er: String = JwText.t("common.none")
	if age == JwReadModel.AGE_WORKING:
		var lf: int = m.group_labor_force(g)
		if lf > 0:
			@warning_ignore("integer_division")
			er = JwFormat.pct(mini(m.group_employed(g), lf) * JwReadModel.PPM / lf)
	var val: String = _field_value(g, base)
	p.set_meta("symbol", "na" if val == JwText.t("common.none") else "value")
	v.add_child(JwUi.label(JwText.render("so.cell.line", {"emp": er, "val": val}), "caption", "text.secondary"))
	return p


func _field_value(g: int, base: Dictionary) -> String:
	var m: JwReadModel = session.model
	var age: int = JwReadModel.age_of_group(g)
	match field:
		"income":
			if age == JwReadModel.AGE_MINOR or not m.settled():
				return JwText.t("common.none")
			var now_pc: int = m.group_disposable_pc(g)
			var gd: Variant = base.get("group_disp_pc", [])
			var was: int = int((gd as Array)[g]) if gd is Array and g < (gd as Array).size() else -1
			if was <= 0 or now_pc < 0:
				return JwText.t("common.none")
			@warning_ignore("integer_division")
			var dpp: int = (now_pc - was) * JwReadModel.PPM / was
			var sp: String = JwFormat.pct(dpp)
			return ("+" + sp) if dpp > 0 else sp
		"burden":
			var b: int = m.group_burden(g)
			return JwFormat.pct(b) if b >= 0 else JwText.t("common.none")
		"access":
			return JwFormat.pct(m.group_service_access(g))
		"edu":
			var e: int = m.group_edu_readiness(g)
			return JwFormat.pct(e) if e >= 0 else JwText.t("common.none")
	return JwText.t("common.none")


# ── 三类民意（分列，禁止相加、平均、合成） ─────────────────────────────────

func _moods() -> PanelContainer:
	var m: JwReadModel = session.model
	var cat: JwCatalog = session.catalog
	var sec: Dictionary = JwUi.section(JwText.t("so.moods.title"))
	var body: VBoxContainer = sec["body"]
	var h: HBoxContainer = JwUi.hbox(16)
	var ids: Array = [["MoodLiving", "mood.living", "state.group.living_index_ppm"],
			["MoodExpectation", "mood.expectation", "state.group.expectation_ppm"],
			["MoodTrust", "mood.trust", "state.group.trust_ppm"]]
	for it: Array in ids:
		var v: VBoxContainer = JwUi.vbox(2)
		JwUi.tag(v, String(it[0]))
		v.add_child(JwUi.label(JwText.t(String(it[1])), "body_bold", "text.secondary"))
		var val: int = m.weighted(String(it[2]), m.all_groups())
		v.add_child(num(JwFormat.index(val) if String(it[0]) != "MoodTrust" else JwFormat.pct_num(val),
				JwText.t("unit.index") if String(it[0]) != "MoodTrust" else "%", JwInfo.Cls.ACTUAL, "block_num",
				{"measure": JwText.t("measure.index"), "period": JwText.t("period.this_q"),
				"index_base": JwText.t("so.mood_base"), "ledger": "politics", "rule_key": "subjective"}))
		var parts: PackedStringArray = PackedStringArray()
		for r: int in JwReadModel.R:
			var rv: int = m.weighted(String(it[2]), m.region_groups(r))
			parts.append(cat.region_label(r) + " " + (JwFormat.index(rv) if String(it[0]) != "MoodTrust" else JwFormat.pct(rv)))
		v.add_child(JwUi.label("\n".join(parts), "caption", "text.muted"))
		h.add_child(v)
	body.add_child(h)
	body.add_child(JwUi.para(JwText.render("so.moods.note", {"support": JwFormat.pct(m.support_national())}), "text.muted"))
	return sec["root"]


func _distribution() -> PanelContainer:
	var m: JwReadModel = session.model
	var sec: Dictionary = JwUi.section(JwText.t("so.dist.title"))
	var root: PanelContainer = sec["root"]
	JwUi.tag(root, "DistributionBar")
	var body: VBoxContainer = sec["body"]
	var qd: Dictionary = m.income_quantiles(m.all_groups())
	if int(qd["p50"]) < 0:
		body.add_child(JwUi.empty_state(JwText.t("so.dist.cold.why"), JwText.t("so.dist.cold.when"), JwText.t("so.dist.cold.rule")))
		return root
	var vmax: int = maxi(int(qd["p90"]), 1)
	var bar: JwBar = JwBar.make(float(int(qd["p90"])) / float(vmax), "teal.dim", "", 22)
	bar.markers = [
		{"at": float(int(qd["p10"])) / float(vmax), "token": "text.secondary"},
		{"at": float(int(qd["p50"])) / float(vmax), "token": "text.primary", "w": 3.0},
		{"at": float(int(qd["mean"])) / float(vmax), "token": "warm.text"},
	]
	body.add_child(bar)
	body.add_child(JwUi.class_line(JwInfo.Cls.ACTUAL, JwText.render("so.dist.line", {"p10": JwFormat.uu_pc(int(qd["p10"])),
			"p50": JwFormat.uu_pc(int(qd["p50"])), "mean": JwFormat.uu_pc(int(qd["mean"])), "p90": JwFormat.uu_pc(int(qd["p90"]))})))
	var lo_g: int = -1
	var hi_g: int = -1
	for g: int in JwReadModel.GROUP:
		if m.group_population(g) <= 0 or JwReadModel.age_of_group(g) == JwReadModel.AGE_MINOR:
			continue
		var v: int = m.group_disposable_pc(g)
		if lo_g < 0 or v < m.group_disposable_pc(lo_g):
			lo_g = g
		if hi_g < 0 or v > m.group_disposable_pc(hi_g):
			hi_g = g
	if lo_g >= 0 and m.group_disposable_pc(lo_g) > 0:
		@warning_ignore("integer_division")
		var ratio_ppm: int = m.group_disposable_pc(hi_g) * JwReadModel.PPM / m.group_disposable_pc(lo_g)
		body.add_child(JwUi.class_line(JwInfo.Cls.ACTUAL, JwText.render("so.dist.gap", {"hi": session.group_label(hi_g),
				"lo": session.group_label(lo_g), "ratio": JwFormat.ratio(ratio_ppm)})))
	body.add_child(JwUi.caption(JwText.t("so.dist.caption")))
	return root


func _blocs() -> PanelContainer:
	var m: JwReadModel = session.model
	var cat: JwCatalog = session.catalog
	var sec: Dictionary = JwUi.section(JwText.t("so.blocs.title"))
	var root: PanelContainer = sec["root"]
	JwUi.tag(root, "Blocs")
	var body: VBoxContainer = sec["body"]
	for b: int in cat.blocs.size():
		var p: PanelContainer = JwUi.panel("bg.raised", "", 10)
		var v: VBoxContainer = JwUi.vbox(2)
		p.add_child(v)
		v.add_child(JwUi.label(cat.bloc_label(b), "title_sub"))
		v.add_child(JwUi.class_line(JwInfo.Cls.ACTUAL, JwText.render("so.bloc.line", {"org": JwFormat.pct(m.at("state.bloc.org_power_ppm", b)),
				"res": JwFormat.u(m.at("state.bloc.resource_uu", b))})))
		var sup: Array = []
		var opp: Array = []
		for p2: int in JwReadModel.POLICY_N:
			var st: int = m.at("state.bloc.stance_ppm", b * 12 + p2)
			if st >= STANCE_SUP_PPM:
				sup.append(String(cat.policy(p2).get("code", "")))
			elif st <= STANCE_OPP_PPM:
				opp.append(String(cat.policy(p2).get("code", "")))
		v.add_child(JwUi.label(JwText.render("so.bloc.stance", {"sup_th": JwFormat.pct_signed(STANCE_SUP_PPM),
				"opp_th": JwFormat.pct_signed(STANCE_OPP_PPM),
				"sup": "、".join(PackedStringArray(sup)) if not sup.is_empty() else JwText.t("common.none"),
				"opp": "、".join(PackedStringArray(opp)) if not opp.is_empty() else JwText.t("common.none")}), "body", "text.secondary", true))
		var vd: PackedStringArray = PackedStringArray()
		for d: Variant in cat.blocs[b].get("veto_domains", []):
			vd.append(JwText.t("veto." + String(d)))
		v.add_child(JwUi.label(JwText.render("so.bloc.veto", {"domains": "、".join(vd) if not vd.is_empty() else JwText.t("common.none"),
				"veto": JwFormat.pct_signed(m.rule("politics.veto_stance_threshold_ppm", 0))}), "caption", "text.muted", true))
		body.add_child(p)
	body.add_child(JwUi.para(JwText.t("so.blocs.note"), "text.muted"))
	return root


func _winners_losers() -> PanelContainer:
	var m: JwReadModel = session.model
	var sec: Dictionary = JwUi.section(JwText.t("so.wl.title"))
	var root: PanelContainer = sec["root"]
	JwUi.tag(root, "WinnersLosers")
	var body: VBoxContainer = sec["body"]
	var sh: HBoxContainer = JwUi.hbox(8)
	sh.add_child(JwUi.label(JwText.t("so.wl.source"), "body", "text.secondary"))
	var ob: OptionButton = OptionButton.new()
	ob.add_item(JwText.t("so.wl.src.settled"), 0)
	ob.add_item(JwText.t("so.wl.src.draft"), 1)
	ob.select(1 if source == "draft" else 0)
	ob.item_selected.connect(func(i: int) -> void:
		source = "draft" if i == 1 else "settled"
		session.log_event("ev.impact_source_changed", {"source": "current_draft" if i == 1 else "settled"})
		refresh())
	sh.add_child(ob)
	body.add_child(sh)
	var cols: HBoxContainer = JwUi.hbox(16)
	var gv: VBoxContainer = JwUi.vbox(2)
	JwUi.tag(gv, "Benefit")
	gv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gv.add_child(JwUi.label(JwText.t("pol.impact.gainers"), "body_bold", "teal.core"))
	var lv: VBoxContainer = JwUi.vbox(2)
	JwUi.tag(lv, "Harm")
	lv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lv.add_child(JwUi.label(JwText.t("pol.impact.losers"), "body_bold", "ochre.core"))
	cols.add_child(gv)
	cols.add_child(lv)
	body.add_child(cols)
	if source == "draft":
		var gi: Dictionary = session.group_impact()
		if not bool(gi.get("ready", false)):
			body.add_child(JwUi.para(JwText.t("so.wl.draft_pending"), "text.muted"))
		else:
			var hq: int = int(gi.get("horizon_q", m.q))
			for r: Variant in gi["gainers"]:
				gv.add_child(_wl_line_p(r, hq))
			for r2: Variant in gi["losers"]:
				lv.add_child(_wl_line_p(r2, hq))
	else:
		var prev: Dictionary = JwDiagnose._prev_hist(session)
		var gl: Variant = prev.get("group_living", [])
		if not m.settled() or not (gl is Array) or (gl as Array).size() != JwReadModel.GROUP:
			body.add_child(JwUi.para(JwText.t("so.wl.settled_pending"), "text.muted"))
		else:
			var rows: Array = []
			for g: int in JwReadModel.GROUP:
				if m.group_population(g) <= 0:
					continue
				rows.append([g, m.at("state.group.living_index_ppm", g) - int((gl as Array)[g])])
			rows.sort_custom(func(x: Array, y: Array) -> bool:
				if int(x[1]) != int(y[1]):
					return int(x[1]) > int(y[1])
				return int(x[0]) < int(y[0]))
			var n_g: int = 0
			for rr: Array in rows:
				if int(rr[1]) > 0 and n_g < 5:
					gv.add_child(JwUi.class_line(JwInfo.Cls.ACTUAL, JwText.render("so.wl.line", {"group": session.group_label(int(rr[0])),
							"d": JwFormat.delta_index(int(rr[1]), true)["text"], "q": JwFormat.quarter(m.q - 1)})))
					n_g += 1
			var n_l: int = 0
			for i: int in range(rows.size() - 1, -1, -1):
				var rr2: Array = rows[i]
				if int(rr2[1]) < 0 and n_l < 5:
					lv.add_child(JwUi.class_line(JwInfo.Cls.ACTUAL, JwText.render("so.wl.line", {"group": session.group_label(int(rr2[0])),
							"d": JwFormat.delta_index(int(rr2[1]), true)["text"], "q": JwFormat.quarter(m.q - 1)})))
					n_l += 1
	body.add_child(JwUi.para(JwText.t("pol.impact.not_additive"), "text.muted"))
	return root


func _wl_line_p(r: Variant, hq: int) -> HBoxContainer:
	var d: Dictionary = r
	return JwUi.class_line(JwInfo.Cls.PROJECTED, JwText.render("pol.impact.group_line", {"group": session.group_label(int(d["g"])),
			"range": JwFormat.range_index(int(d["lo"]), int(d["hi"])), "q": JwFormat.quarter(hq), "scenario": JwText.t("scen.base.short")}))


func get_required_above_fold(band: int) -> Array[StringName]:
	return [&"GroupMatrix", &"MatrixHeader", &"MoodLiving", &"MoodExpectation", &"MoodTrust", &"PrecisionNote"]
