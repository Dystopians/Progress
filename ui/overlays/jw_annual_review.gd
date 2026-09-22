## 年度审查（docs/20 §10.1；§04 新手第 4 季：辨认收入改善和公共服务负担并存）。
##
## 首屏两块并列，禁止折叠、禁止合成单值：左 本年收入（实，按税种分解，征收覆盖率），
## 右 本年公共服务负担（实，已投运资产运行费明细；算，下一年运行费）。
## 下方结论行三槽位必填；再下一行 债务 · 名义 GDP（四季滚动）· 债务/GDP，并紧跟「不替代偿付能力分析」。
class_name JwAnnualReview
extends JwOverlay


func _init() -> void:
	width_ratio = 0.86
	height_ratio = 0.9


func build() -> void:
	var m: JwReadModel = session.model
	var qs: int = m.q - 1
	set_title(JwText.render("ar.title", {"quarter": JwFormat.quarter(maxi(qs, 0)), "year": str(JwFormat.year_of(maxi(qs, 0)))}))
	var year_rows: Array[Dictionary] = _year(qs)
	var prev_rows: Array[Dictionary] = _year(qs - 4)
	var cols: HBoxContainer = JwUi.hbox(16)
	JwUi.tag(cols, "AnnualReview")
	body.add_child(cols)
	var left: PanelContainer = _left(year_rows, prev_rows)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(left)
	var right: PanelContainer = _right(year_rows, qs)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(right)
	var x: int = _sum(year_rows, "receipts") - _base_receipts(prev_rows)
	var y: int = m.sc("state.gov.service_opex_committed_uu") - _opex_committed_at(qs - 4)
	var z: int = y * 4 - x
	var concl: HBoxContainer = JwUi.class_line(JwInfo.Cls.DERIVED, JwText.render("ar.conclusion", {"x": JwFormat.u_signed(x),
			"y": JwFormat.u(y), "z": JwFormat.u(z), "base": JwText.t("ar.base.prev") if prev_rows.size() == 4 else JwText.t("ar.base.plan")}))
	JwUi.tag(concl, "Conclusion")
	body.add_child(concl)
	var debt_box: VBoxContainer = JwUi.vbox(4)
	JwUi.tag(debt_box, "DebtGdp")
	var h: HBoxContainer = JwUi.hbox(24)
	h.add_child(num(JwFormat.u_num(m.debt_total()), "U", JwInfo.Cls.ACTUAL, "block_num", {"measure": JwText.t("measure.stock"),
			"period": JwText.t("period.q_end"), "price_base": JwText.t("price.nominal"), "ledger": "debt", "rule_key": "bond_rules"}))
	h.add_child(num(JwFormat.u_num(m.dv("derived.gdp.annual_nominal_uu")), "U", JwInfo.Cls.ACTUAL, "block_num",
			{"measure": JwText.t("measure.flow"), "period": JwText.t("period.four_q"), "price_base": JwText.t("price.nominal"),
			"ledger": "value_added", "rule_key": "real_gdp"}))
	h.add_child(num(JwFormat.pct_num(m.dv("derived.fiscal.debt_to_gdp_ppm")), "%", JwInfo.Cls.ACTUAL, "block_num",
			{"measure": JwText.t("measure.ratio"), "period": JwText.t("period.four_q"), "denominator": JwText.t("denom.gdp4q"),
			"ledger": "debt", "rule_key": "bond_rules"}))
	debt_box.add_child(JwUi.label(JwText.t("ar.debt.labels"), "body", "text.secondary"))
	debt_box.add_child(h)
	debt_box.add_child(JwUi.label(JwText.t("ar.debt.caption"), "caption", "text.muted"))
	debt_box.add_child(JwUi.label(JwText.t("ar.debt.disclaimer"), "body_bold", "text.primary", true))
	body.add_child(debt_box)
	body.add_child(_review_verdict())
	body.add_child(JwUi.para(JwText.t("ar.no_score"), "text.muted"))
	var close_b: Button = JwUi.button(JwText.t("ar.done"), "PrimaryButton")
	close_b.pressed.connect(close)
	body.add_child(close_b)
	if session != null:
		session.log_event("ev.overlay_opened", {"overlay": "overlay.annual_review", "left_block_visible": true,
				"right_block_visible": true})


## 截至 qs 的四个已结算季（按历史快照；不足四季时有多少取多少）。
func _year(qs: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for h: Dictionary in session.history:
		var q: int = int(h.get("q", -1))
		if q >= 0 and q <= qs and q > qs - 4:
			out.append(h)
	return out


static func _sum(rows: Array[Dictionary], key: String) -> int:
	var t: int = 0
	for h: Dictionary in rows:
		t += int(h.get(key, 0))
	return t


## 比较基准：上一年四季实收；首次审查没有上一年，取剧本的基年年度计划收入（口径写在结论行）。
func _base_receipts(prev_rows: Array[Dictionary]) -> int:
	if prev_rows.size() == 4:
		return _sum(prev_rows, "receipts")
	return int(session.catalog.base_plan.get("receipts_uu", 0))


func _opex_committed_at(q: int) -> int:
	for h: Dictionary in session.history:
		if int(h.get("q", -99)) == q:
			return int(h.get("opex_committed", 0))
	if not session.history.is_empty():
		return int(session.history[0].get("opex_committed", 0))
	return 0


func _left(rows: Array[Dictionary], prev_rows: Array[Dictionary]) -> PanelContainer:
	var m: JwReadModel = session.model
	var sec: Dictionary = JwUi.section(JwText.t("ar.left.title"))
	JwUi.tag(sec["root"], "Left")
	var body2: VBoxContainer = sec["body"]
	var t: JwTable = JwTable.make([
		{"title": JwText.t("ar.col.item"), "w": 170},
		{"title": JwText.t("ar.col.year"), "w": 150, "align": "r", "expand": true},
		{"title": JwText.t("ar.col.base"), "w": 150, "align": "r", "expand": true},
	], false, true)
	var plan: Dictionary = session.catalog.base_plan.get("receipt_lines_uu", {})
	var items: Array = [["ar.tax.income", "receipts_income", "income_tax"], ["ar.tax.profit", "receipts_profit", "profit_tax"],
			["ar.tax.other", "receipts_other", "other"], ["ar.tax.total", "receipts", ""]]
	for it: Array in items:
		var base_v: int = _sum(prev_rows, String(it[1])) if prev_rows.size() == 4 else \
				(int(plan.get(String(it[2]), 0)) if String(it[2]) != "" else int(session.catalog.base_plan.get("receipts_uu", 0)))
		t.add_row([JwText.t(String(it[0])), {"text": JwFormat.u_num(_sum(rows, String(it[1]))), "cls": JwInfo.Cls.ACTUAL},
				{"text": JwFormat.u_num(base_v), "cls": JwInfo.Cls.ACTUAL if prev_rows.size() == 4 else JwInfo.Cls.DERIVED}],
				JwInfo.Cls.ACTUAL)
	t.add_note(JwText.render("ar.left.note", {"n": str(rows.size()), "base": JwText.t("ar.base.prev") if prev_rows.size() == 4 else JwText.t("ar.base.plan")}))
	body2.add_child(t)
	body2.add_child(JwUi.class_line(JwInfo.Cls.DERIVED, JwText.render("ar.capacity", {"pct": JwFormat.pct(m.sc("state.gov.tax_capacity_ppm")),
			"receivable": JwFormat.u(m.sc("state.gov.tax_receivable_uu"))})))
	var lk: Button = JwUi.link(JwText.t("ar.link.tax"))
	lk.pressed.connect(func() -> void:
		if root_ui != null:
			root_ui.call("open_ledger", "tax", 0))
	body2.add_child(lk)
	return sec["root"]


func _right(rows: Array[Dictionary], qs: int) -> PanelContainer:
	var m: JwReadModel = session.model
	var cat: JwCatalog = session.catalog
	var sec: Dictionary = JwUi.section(JwText.t("ar.right.title"))
	JwUi.tag(sec["root"], "Right")
	var body2: VBoxContainer = sec["body"]
	var wages: int = _sum(rows, "public_wages")
	var proc: int = _sum(rows, "procurement")
	var opex: int = _sum(rows, "opex_paid")
	body2.add_child(JwUi.class_line(JwInfo.Cls.ACTUAL, JwText.render("ar.opex.paid", {"n": str(rows.size()),
			"total": JwFormat.u(wages + proc + opex), "wages": JwFormat.u(wages), "proc": JwFormat.u(proc),
			"opex": JwFormat.u(opex)})))
	var n: int = 0
	var inprog_opex: int = 0
	for row: Dictionary in m.project_rows():
		var st: int = int(row["status"])
		if st == JwReadModel.PS_COMMISSIONED:
			body2.add_child(JwUi.class_line(JwInfo.Cls.ACTUAL, JwText.render("ar.opex.asset", {"name": String(cat.policy(int(row["policy"])).get("label", "")),
					"region": cat.region_label(int(row["region"])), "opex": JwFormat.u(int(row["opex"]))})))
			n += 1
		elif st == JwReadModel.PS_IN_PROGRESS or st == JwReadModel.PS_SUSPENDED or st == JwReadModel.PS_COMPLETED:
			var cq: int = m.earliest_commission_q(row)
			var quarters_in_year: int = clampi(m.q + 4 - cq, 0, 4)
			inprog_opex += int(row["opex"]) * quarters_in_year
	if n == 0:
		body2.add_child(JwUi.label(JwText.t("ar.opex.none"), "body", "text.muted", true))
	var next_year: int = m.sc("state.gov.service_opex_committed_uu") * 4 + inprog_opex
	var nx: HBoxContainer = JwUi.class_line(JwInfo.Cls.DERIVED, JwText.render("ar.opex.next", {"amount": JwFormat.u(next_year),
			"committed": JwFormat.u(m.sc("state.gov.service_opex_committed_uu")), "new": JwFormat.u(inprog_opex)}))
	JwUi.tag(nx, "NextYearOpex")
	body2.add_child(nx)
	var lk: Button = JwUi.link(JwText.t("ar.link.opex"))
	lk.pressed.connect(func() -> void:
		session.log_event("ev.section_expanded", {"node": "AnnualReview/Right/NextYearOpex"})
		if root_ui != null:
			root_ui.call("open_ledger", "opex", 0))
	body2.add_child(lk)
	return sec["root"]


func _review_verdict() -> PanelContainer:
	var m: JwReadModel = session.model
	var sec: Dictionary = JwUi.section(JwText.t("ar.verdict.title"))
	var body2: VBoxContainer = sec["body"]
	body2.add_child(JwUi.class_line(JwInfo.Cls.ACTUAL, JwText.render("ar.verdict.state", {
		"status": JwText.t("mandate_status.%d" % m.sc("state.politics.mandate_status")),
		"fails": str(m.sc("state.politics.review_fail_streak")), "passes": str(m.sc("state.politics.review_pass_streak"))})))
	body2.add_child(JwUi.class_line(JwInfo.Cls.DERIVED, JwText.render("ar.verdict.rule", {
		"deficit": JwFormat.pct(m.rule("politics.budget_review_deficit_limit_ppm", 0)),
		"arrears": JwFormat.u(m.rule("politics.budget_review_arrears_limit_uu", 0)),
		"lost": str(m.rule("politics.budget_review_fail_to_lost_count", 0)),
		"noconf": JwFormat.quarters(m.rule("param.no_confidence_q", 0))})))
	return sec["root"]
