## 页面五 · 季度报告（docs/20 §7.5；文案规则见 docs/21 §4、§6、§7）。
##
## 纸面底色（档案感），唯一允许长滚动的页面。六个小节顺序固定：
## 一 与上季预期的偏差（永远第一）/ 二 已经发生 / 三 在建项目与时滞 / 四 模型中的限制因素 /
## 五 下季情景 / 六 下季待办。偏差表是唯一允许「预」与「实」同行的地方，分列且列头带类。
## 报告全部由结构化事实经规则模板渲染；不引入快照中不存在的实体（B-14）。
class_name JwReportPage
extends JwPage

var _root: VBoxContainer = null
var _cost_card: int = -1
## 成本卡对应的动作："pause" / "reschedule"（命令 6 延期）或 "withdraw"（命令 5 取消）。
var _cost_action: String = ""


func refresh() -> void:
	JwUi.clear(self)
	var paper_bg: PanelContainer = JwUi.panel("bg.paper", "", 0)
	add_child(paper_bg)
	var sc: ScrollContainer = ScrollContainer.new()
	sc.name = "ReportScroll"
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	paper_bg.add_child(sc)
	_root = JwUi.vbox(18)
	_root.name = "Report"
	_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(JwUi.margin(_root, 40, 24, 40, 32))
	(sc.get_child(0) as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if session == null or session.game == null:
		_root.add_child(JwUi.empty_state(JwText.t("rp.empty.why"), JwText.t("rp.empty.when"), JwText.t("rp.empty.rule"), true))
		return
	var m: JwReadModel = session.model
	var qs: int = m.q - 1
	var head: VBoxContainer = JwUi.vbox(4)
	JwUi.tag(head, "ReportHeader")
	head.add_child(JwUi.label(JwText.render("rp.title", {"quarter": JwFormat.quarter(maxi(qs, 0)) if qs >= 0 else JwFormat.quarter(0)}),
			"title_page", "text.ink"))
	head.add_child(JwUi.label(JwText.render("rp.subtitle", {"country": session.catalog.country_label(),
			"state": JwText.t("rp.state.settled") if qs >= 0 else JwText.t("rp.state.cold")}), "body", "text.ink2"))
	_root.add_child(head)
	_root.add_child(term_strip(true))
	_root.add_child(_variance(qs))
	_root.add_child(_receipt(qs))
	_root.add_child(_lag_block(qs))
	_root.add_child(_binding(qs))
	_root.add_child(_scenarios())
	_root.add_child(_todo())


func _sec(title: String, id: String) -> Dictionary:
	var sec: Dictionary = JwUi.section(title, "", true, 16)
	JwUi.tag(sec["root"], id)
	(sec["root"] as PanelContainer).add_theme_stylebox_override("panel", JwTheme.box("bg.paper", "text.ink2", 1, 2, 16))
	return sec


# ── 一 · 与上季预期的偏差 ─────────────────────────────────────────────────

func _variance(qs: int) -> PanelContainer:
	var m: JwReadModel = session.model
	var sec: Dictionary = _sec(JwText.t("rp.s1"), "VarianceTable")
	var body: VBoxContainer = sec["body"]
	var e: Dictionary = session.expectations.get(str(qs), {})
	if qs < 0 or e.is_empty():
		body.add_child(JwUi.empty_state(JwText.t("rp.s1.empty.why"), JwText.t("rp.s1.empty.when"),
				JwText.t("rp.s1.empty.rule"), true))
	else:
		var t: JwTable = JwTable.make([
			{"title": JwText.t("rp.s1.col.metric"), "w": 200},
			{"title": JwText.t("rp.s1.col.expected"), "w": 260, "align": "r", "expand": true},
			{"title": JwText.t("rp.s1.col.actual"), "w": 200, "align": "r", "expand": true},
			{"title": JwText.t("rp.s1.col.verdict"), "w": 200},
		], true, false)
		body.add_child(t)
		var rows: Array = [
			["rp.m.cash", "cash_end", m.gov_cash(), "u"],
			["rp.m.borrow", "new_borrowing", m.sc("flow.gov.new_borrowing_uu"), "u"],
			["rp.m.arrears", "arrears", m.sc("state.gov.arrears_uu"), "u"],
			["rp.m.receipts", "receipts", m.receipts_total(), "u"],
			["rp.m.unemp", "unemployment_ppm", int(m.unemployment()["rate_ppm"]), "pct"],
		]
		for rd: Array in rows:
			var band: Array = e.get(String(rd[1]), [])
			if band.size() < 2:
				continue
			var lo: int = int(band[0])
			var hi: int = int(band[1])
			var act: int = int(rd[2])
			var is_pct: bool = String(rd[3]) == "pct"
			var verdict: String = JwText.t("rp.v.inside")
			if act > hi:
				verdict = JwText.t("rp.v.above")
			elif act < lo:
				verdict = JwText.t("rp.v.below")
			t.add_row([
				JwText.t(String(rd[0])),
				{"text": JwFormat.range_pct(lo, hi) if is_pct else JwFormat.range_u(lo, hi), "cls": JwInfo.Cls.PROJECTED},
				{"text": JwFormat.pct(act) if is_pct else JwFormat.u(act), "cls": JwInfo.Cls.ACTUAL},
				{"text": verdict, "cls": JwInfo.Cls.DERIVED, "color": "text.ink" if verdict == JwText.t("rp.v.inside") else "ochre.ink"},
			], JwInfo.Cls.DERIVED)
		t.add_note(JwText.t("rp.s1.note"))
	body.add_child(JwUi.label(JwText.t("rp.s1.actions"), "title_sub", "text.ink"))
	var rows2: Array[Dictionary] = []
	for row: Dictionary in m.project_rows():
		var st: int = int(row["status"])
		if st == JwReadModel.PS_IN_PROGRESS or st == JwReadModel.PS_SUSPENDED:
			rows2.append(row)
	if rows2.is_empty():
		body.add_child(JwUi.label(JwText.t("rp.s1.actions_empty"), "body", "text.ink2", true))
	for row2: Dictionary in rows2:
		body.add_child(_action_row(row2))
	return sec["root"]


func _project_name(row: Dictionary) -> String:
	var cat: JwCatalog = session.catalog
	return JwText.render("project.name", {"policy": String(cat.policy(int(row["policy"])).get("label", "")),
			"region": cat.region_label(int(row["region"])), "n": str(int(row["p"]) + 1)})


## 环节 06 的四个承担动作（VT-3）：暂停 / 改期 / 撤回 先渲染成本卡（AC-18c）。
## 暂停 = 合同延期 1 季，改期 = 延期 4 季（不超过该项目剩余的延期季数），都是命令 6（R-DEFER-01）；
## 撤回 = 取消（命令 5）。
func _action_row(row: Dictionary) -> VBoxContainer:
	var v: VBoxContainer = JwUi.vbox(6)
	var h: HBoxContainer = JwUi.hbox(10)
	var pj: int = int(row["p"])
	h.add_child(JwUi.label(_project_name(row), "body_bold", "text.ink"))
	h.add_child(JwUi.spacer())
	for act: String in ["continue", "pause", "reschedule", "withdraw"]:
		var b: Button = JwUi.button(JwText.t("rp.act." + act))
		var a: String = act
		b.pressed.connect(func() -> void:
			if a == "continue":
				session.log_event("ev.project_continue", {"project_id": pj})
				return
			_cost_card = pj
			_cost_action = a
			session.log_event("ev.cost_card_rendered", {"project_id": pj, "action": a})
			refresh())
		h.add_child(b)
	v.add_child(h)
	if _cost_card == pj and (_cost_action == "pause" or _cost_action == "reschedule"):
		v.add_child(_defer_card(row, 1 if _cost_action == "pause" else 4))
	elif _cost_card == pj:
		var wc: Dictionary = session.model.withdraw_cost(row)
		var card: PanelContainer = JwUi.panel_style(JwTheme.box_left_rule("bg.paper2", "ochre.ink", 3, 12))
		JwUi.tag(card, "CostCard")
		var cv: VBoxContainer = JwUi.vbox(4)
		card.add_child(cv)
		cv.add_child(JwUi.label(JwText.t("cost.title"), "body_bold", "text.ink"))
		var grid: GridContainer = GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 24)
		for pair: Array in [["cost.sunk", int(wc["sunk"])], ["cost.residual", int(wc["residual"])],
				["cost.penalty", int(wc["penalty"])], ["cost.remaining_commit", int(wc["remaining_commit"])]]:
			grid.add_child(JwUi.label(JwText.t(String(pair[0])), "body", "text.ink2"))
			grid.add_child(JwUi.label(JwFormat.u(int(pair[1])), "num_bold", "text.ink"))
		cv.add_child(grid)
		var ok: Button = JwUi.button(JwText.t("cost.confirm_cancel"), "AlertButton")
		var name_t: String = _project_name(row)
		ok.pressed.connect(func() -> void:
			_cost_card = -1
			session.add_draft(session.draft_cancel(pj, name_t))
			refresh())
		cv.add_child(ok)
		var no: Button = JwUi.button(JwText.t("common.cancel"))
		no.pressed.connect(func() -> void:
			_cost_card = -1
			refresh())
		cv.add_child(no)
		v.add_child(card)
	return v


## 延期成本卡（R-DEFER-01）：赔偿、剩余承诺（不变）、复工季、延期余量；条件不满足给原因卡。
func _defer_card(row: Dictionary, want_q: int) -> PanelContainer:
	var m: JwReadModel = session.model
	var pj: int = int(row["p"])
	var left0: Dictionary = m.defer_cost(row, 1)
	var n: int = clampi(want_q, 1, maxi(int(left0["q_left"]), 1))
	var dc: Dictionary = m.defer_cost(row, n)
	var card: PanelContainer = JwUi.panel_style(JwTheme.box_left_rule("bg.paper2", "ochre.ink", 3, 12))
	JwUi.tag(card, "CostCard")
	var cv: VBoxContainer = JwUi.vbox(4)
	card.add_child(cv)
	cv.add_child(JwUi.label(JwText.render("defer.title", {"n": JwFormat.quarters(n)}), "body_bold", "text.ink"))
	var grid: GridContainer = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	for pair: Array in [["defer.fee", JwFormat.u(int(dc["fee"]))],
			["defer.remaining", JwFormat.u(int(dc["remaining_commit"]))],
			["defer.resume", JwFormat.quarter(int(dc["resume_q"]))],
			["defer.left", JwText.render("defer.left.value", {"count": str(int(dc["count_left"])),
				"quarters": JwFormat.quarters(int(dc["q_left"]))})]]:
		grid.add_child(JwUi.label(JwText.t(String(pair[0])), "body", "text.ink2"))
		grid.add_child(JwUi.label(String(pair[1]), "num_bold", "text.ink"))
	cv.add_child(grid)
	cv.add_child(JwUi.para(JwText.render("defer.rule", {"rate": JwFormat.pct(m.rule("param.defer_fee_ppm_per_q", 0))}),
			"text.ink2"))
	if bool(dc["allowed"]):
		var ok: Button = JwUi.button(JwText.t("defer.confirm"), "AlertButton")
		var name_t: String = _project_name(row)
		ok.pressed.connect(func() -> void:
			_cost_card = -1
			session.add_draft(session.draft_project_defer(pj, n, name_t))
			refresh())
		cv.add_child(ok)
	else:
		var r: Dictionary = JwReasons.from_code(JwReadModel.RJ_PRECONDITION, {"kind": 6, "p": -1, "draft": -1,
				"project": pj, "subject": "project", "subject_label": _project_name(row)}, m, session.catalog)
		cv.add_child(JwReasonView.make(r, session, root_ui, true))
	var no: Button = JwUi.button(JwText.t("common.cancel"))
	no.pressed.connect(func() -> void:
		_cost_card = -1
		refresh())
	cv.add_child(no)
	return card


# ── 二 · 已经发生 ────────────────────────────────────────────────────────

func _receipt(qs: int) -> PanelContainer:
	var m: JwReadModel = session.model
	var sec: Dictionary = _sec(JwText.t("rp.s2"), "SettlementReceipt")
	var body: VBoxContainer = sec["body"]
	if qs < 0:
		body.add_child(JwUi.empty_state(JwText.t("rp.s2.empty.why"), JwText.t("rp.s2.empty.when"), JwText.t("rp.s2.empty.rule"), true))
		return sec["root"]
	var counts: PackedInt64Array = _ledger_step_counts()
	var facts: Array = [
		JwText.render("rp.step.1", {"n": str(counts[1])}),
		JwText.render("rp.step.2", {"n": str(counts[2]), "interest": JwFormat.u(m.sc("flow.gov.interest_paid_uu")),
			"principal": JwFormat.u(m.sc("flow.gov.principal_paid_uu")), "borrow": JwFormat.u(m.sc("flow.gov.new_borrowing_uu")),
			"rollover": JwFormat.u(m.sc("flow.gov.rollover_uu"))}),
		JwText.render("rp.step.3", {"n": str(counts[3]), "unemp": JwFormat.pct(int(m.unemployment()["rate_ppm"]))}),
		JwText.render("rp.step.4", {"n": str(counts[4]), "wages": JwFormat.u(m.sc("flow.gov.pay_public_wages_uu")),
			"proc": JwFormat.u(m.sc("flow.gov.pay_procurement_uu")),
			"transfers": JwFormat.u(JwSession._sum(m.ar("flow.gov.pay_transfers_uu"))),
			"projects": JwFormat.u(JwSession._sum(m.ar("flow.gov.pay_project_uu"))),
			"opex": JwFormat.u(JwSession._sum(m.ar("flow.gov.pay_opex_uu")))}),
		JwText.render("rp.step.5", {"n": str(counts[5]), "exports": JwFormat.u(m.sc("flow.world.exports_uu")),
			"imports": JwFormat.u(m.sc("flow.world.imports_uu"))}),
		JwText.render("rp.step.6", {"n": str(counts[6]), "receipts": JwFormat.u(m.receipts_total()),
			"gdp": JwFormat.u(m.dv("derived.gdp.production_uu"))}),
		JwText.render("rp.step.7", {"n": str(counts[7])}),
		JwText.render("rp.step.8", {"n": str(counts[8]), "support": JwFormat.pct(m.support_national())}),
	]
	for i: int in facts.size():
		var l: HBoxContainer = JwUi.class_line(JwInfo.Cls.ACTUAL, String(facts[i]), true)
		JwUi.tag(l, "Step%d" % (i + 1))
		body.add_child(l)
	# R-EVENT-01：本季触发的事件（第 8 步落地；效果只写主观量、行政能力或集团立场）。
	# E17（policy_P12.json）：采购透明通道的逐项中间量——为什么行政执行能力这样变。
	var tx: Dictionary = session.game.transparency_explained()
	if not tx.is_empty():
		var lt: HBoxContainer = JwUi.class_line(JwInfo.Cls.ACTUAL, JwText.render("rp.p12.explain", {
			"policy": String(session.catalog.policy(int(tx.get("policy", 11))).get("label", "")),
			"coverage": JwFormat.pct(int(tx.get("coverage", 0))), "audit": JwFormat.pct(int(tx.get("audit", 0))),
			"progress": JwFormat.pct(int(tx.get("progress", 0))), "ramp": JwFormat.pct(int(tx.get("ramp", 0))),
			"avail": JwFormat.pct(int(tx.get("avail", 0))), "load": JwFormat.pct(int(tx.get("load", 0))),
			"gain": JwFormat.pct(int(tx.get("gain", 0))), "delta": JwFormat.pct_signed(int(tx.get("delta", 0)))}), true)
		JwUi.tag(lt, "TransparencyExplained")
		body.add_child(lt)
	for ev: Dictionary in session.game.fired_events_last():
		var le: HBoxContainer = JwUi.class_line(JwInfo.Cls.ACTUAL, JwText.render("rp.event.fired",
				{"id": String(ev.get("id", "")).substr(6), "label": String(ev.get("label", ""))}), true)
		JwUi.tag(le, "EventFired")
		body.add_child(le)
	var ident: HBoxContainer = _identity(qs)
	JwUi.tag(ident, "IdentityCheck")
	body.add_child(ident)
	var lk: Button = JwUi.link(JwText.t("rp.s2.cmd_log"))
	lk.pressed.connect(func() -> void: _on_ledger("command", 0))
	body.add_child(lk)
	return sec["root"]


## 本季账本行按结算步计数（会话在结算完成时缓存；结算进行中不读活账本）。
func _ledger_step_counts() -> PackedInt64Array:
	var c: PackedInt64Array = session.step_counts
	if c.size() < 9:
		c = PackedInt64Array([0, 0, 0, 0, 0, 0, 0, 0, 0])
	return c


## 现金恒等式核对（计划书 §07）：期末 = 期初 + 实收 + 新增借款 − 基本支出 − 利息 − 本金。
func _identity(qs: int) -> HBoxContainer:
	var m: JwReadModel = session.model
	var prev: Dictionary = JwDiagnose._prev_hist(session)
	var start: int = int(prev.get("cash", m.gov_cash()))
	var expect: int = start + m.receipts_total() + m.sc("flow.gov.new_borrowing_uu") - m.sc("flow.gov.primary_paid_uu") \
			- m.sc("flow.gov.interest_paid_uu") - m.sc("flow.gov.principal_paid_uu")
	var resid: int = m.gov_cash() - expect
	if resid == 0:
		return JwUi.class_line(JwInfo.Cls.ACTUAL, JwText.render("rp.identity.ok", {"quarter": JwFormat.quarter(qs),
				"citation": JwFormat.citation(JwText.t("ledger.alias.cash"), qs, 1)}), true)
	return JwUi.class_line(JwInfo.Cls.ACTUAL, JwText.render("rp.identity.fail", {"quarter": JwFormat.quarter(qs),
			"resid": JwFormat.uu_raw(resid), "citation": JwFormat.citation(JwText.t("ledger.alias.cash"), qs, 1)}), true, "ochre.ink")


# ── 三 · 在建项目与时滞（§04 第 2 季教学的唯一落点） ───────────────────────

func _lag_block(qs: int) -> PanelContainer:
	var m: JwReadModel = session.model
	var sec: Dictionary = _sec(JwText.t("rp.s3"), "LagBlock")
	var body: VBoxContainer = sec["body"]
	var rows: Array[Dictionary] = m.project_rows()
	if rows.is_empty():
		body.add_child(JwUi.empty_state(JwText.t("rp.s3.empty.why"), JwText.t("rp.s3.empty.when"), JwText.t("rp.s3.empty.rule"), true))
		_add_commit_timeline(body)
		return sec["root"]
	var t: JwTable = JwTable.make([
		{"title": JwText.t("rp.s3.col.project"), "w": 190, "expand": true, "wrap": true},
		{"title": JwText.t("rp.s3.col.paid"), "w": 110, "align": "r"},
		{"title": JwText.t("rp.s3.col.delivery"), "w": 90, "align": "r"},
		{"title": JwText.t("rp.s3.col.construction"), "w": 90, "align": "r"},
		{"title": JwText.t("rp.s3.col.new_cap"), "w": 110, "align": "r"},
		{"title": JwText.t("rp.s3.col.earliest"), "w": 120, "align": "r"},
		{"title": JwText.t("rp.s3.col.withdraw"), "w": 210, "wrap": true, "expand": true},
		{"title": JwText.t("rp.s3.col.source"), "w": 80},
	], true, true)
	body.add_child(t)
	var i: int = 0
	for row: Dictionary in rows:
		var st: int = int(row["status"])
		if st == JwReadModel.PS_CANCELLED:
			continue
		var new_cap: int = int(row["capacity_effect"]) if int(row["commissioned_q"]) == qs + 1 and st == JwReadModel.PS_COMMISSIONED else 0
		var wc: Dictionary = m.withdraw_cost(row)
		var h: HBoxContainer = t.add_row([
			_project_name(row) + " · " + JwText.t("project_status.%d" % st),
			{"text": JwFormat.u_num(int(row["paid"])), "cls": JwInfo.Cls.ACTUAL},
			{"text": JwFormat.pct(int(row["delivery_ppm"])), "cls": JwInfo.Cls.ACTUAL},
			{"text": JwFormat.pct(int(row["construction_ppm"])), "cls": JwInfo.Cls.ACTUAL},
			{"text": JwFormat.qty_num(new_cap), "cls": JwInfo.Cls.ACTUAL},
			{"text": JwFormat.quarter(m.earliest_commission_q(row)), "cls": JwInfo.Cls.DERIVED},
			{"text": JwText.render("rp.s3.withdraw", {"sunk": JwFormat.u_num(int(wc["sunk"])), "residual": JwFormat.u_num(int(wc["residual"])),
				"penalty": JwFormat.u_num(int(wc["penalty"]))}), "cls": JwInfo.Cls.DERIVED, "wrap": true},
			JwText.t("ledger.alias.project"),
		], JwInfo.Cls.ACTUAL, {"clickable": true, "project": int(row["p"])})
		(h.get_parent() as Control).set_meta("paid", int(row["paid"]))
		(h.get_parent() as Control).set_meta("new_capacity", new_cap)
		JwUi.tag(h.get_parent() as Control, "Row%d" % i)
		i += 1
	t.row_activated.connect(func(_idx: int, meta: Dictionary) -> void:
		note_expand("Report/LagBlock/Row%d" % _idx)
		_on_ledger("project", int(meta.get("project", 0)) + 1))
	t.add_note(JwText.t("rp.s3.note_units"))
	body.add_child(JwUi.class_line(JwInfo.Cls.DERIVED, JwText.render("tpl.derived.no_capacity_this_q", {"mech_id": "[M-PROJ-01]",
			"rule_id": "^R-ASSET-01", "citations": JwFormat.citation(JwText.t("ledger.alias.project"), maxi(qs, -1), 1)}), true))
	var rule: Button = JwUi.link(JwText.t("rp.s3.rule"))
	rule.pressed.connect(func() -> void: _on_rule("commission"))
	body.add_child(rule)
	_add_commit_timeline(body)
	return sec["root"]


## 承诺时间轴（docs/20 D-02：季度报告区块）：项目时滞之外的全部已签承诺，按季排开。
func _add_commit_timeline(body: VBoxContainer) -> void:
	if session.game == null:
		return
	var sched: Dictionary = session.game.commitment_schedule(12)
	if sched.is_empty():
		return
	body.add_child(JwUi.class_line(JwInfo.Cls.DERIVED, JwText.t("ct.note"), true))
	body.add_child(JwCommitTimeline.make(sched, 12, true))


# ── 四 · 模型中的限制因素 ─────────────────────────────────────────────────

func _binding(qs: int) -> PanelContainer:
	var m: JwReadModel = session.model
	var sec: Dictionary = _sec(JwText.t("rp.s4"), "BindingFactors")
	var body: VBoxContainer = sec["body"]
	if qs < 0:
		body.add_child(JwUi.empty_state(JwText.t("rp.s4.empty.why"), JwText.t("rp.s4.empty.when"), JwText.t("rp.s4.empty.rule"), true))
		return sec["root"]
	var bc: PackedInt64Array = m.binding_counts()
	var parts: PackedStringArray = PackedStringArray()
	for b: int in 5:
		parts.append(JwText.t("binding.%d" % b) + " " + str(bc[b]))
	var r0: HBoxContainer = JwUi.class_line(JwInfo.Cls.DERIVED, JwText.render("rp.s4.counts", {"list": "、".join(parts),
			"rule_id": "^R-PROD-03", "citations": JwFormat.citation(JwText.t("ledger.alias.constraint"), qs, 1)}), true)
	JwUi.tag(r0, "Row0")
	body.add_child(r0)
	for c: int in JwReadModel.CELL:
		var b2: int = m.at("flow.cell.binding_code", c)
		if b2 == JwReadModel.BIND_PLAN:
			continue
		@warning_ignore("integer_division")
		var r: int = c / 4
		var ties: PackedStringArray = JwRegionPage.tie_names(m.cell_bounds(c), b2)
		var slots: Dictionary = {
			"region_name": session.catalog.region_label(r), "sector_name": JwText.t("sector.%d" % (c % 4)),
			"bound_name": JwText.t("binding.%d" % b2), "rule_id": "^R-PROD-03",
			"citations": JwFormat.citation(JwText.t("ledger.alias.constraint"), qs, c + 1)}
		if ties.is_empty():
			body.add_child(JwUi.class_line(JwInfo.Cls.DERIVED, JwText.render("tpl.derived.binding", slots), true))
		else:
			slots["tie_names"] = "、".join(ties)
			body.add_child(JwUi.class_line(JwInfo.Cls.DERIVED, JwText.render("tpl.derived.binding_tie", slots), true))
	body.add_child(JwUi.class_line(JwInfo.Cls.DERIVED, JwText.render("tpl.derived.bounds_not_additive", {"rule_id": "^R-PROD-03"}), true))
	body.add_child(JwUi.para(JwText.t("rp.s4.wording"), "text.ink2"))
	return sec["root"]


# ── 五 · 下季情景 ───────────────────────────────────────────────────────

func _scenarios() -> PanelContainer:
	var m: JwReadModel = session.model
	var sec: Dictionary = _sec(JwText.t("rp.s5"), "Scenarios")
	var body: VBoxContainer = sec["body"]
	if session.dry.is_empty():
		body.add_child(JwUi.label(JwText.t("common.recalc"), "body", "warm.ink"))
		return sec["root"]
	var cols: HBoxContainer = JwUi.hbox(24)
	body.add_child(cols)
	# 两栏同口径：有草案时两栏都含草案（draft_* 无草案时回落到 nodraft_*），与 adv_* 一致。
	for pair: Array in [["draft_lo", "draft_hi", "scen.base", "Baseline"], ["adv_lo", "adv_hi", "scen.adverse", "Adverse"]]:
		var v: VBoxContainer = JwUi.vbox(6)
		JwUi.tag(v, String(pair[3]))
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.add_child(JwUi.label(JwText.t(String(pair[2])), "title_sub", "text.ink"))
		var cb: Array[Dictionary] = session.band(String(pair[0]), String(pair[1]), "cash_end")
		var ub: Array[Dictionary] = session.band(String(pair[0]), String(pair[1]), "unemployment_ppm")
		if not cb.is_empty():
			var t: int = cb.size() - 1
			v.add_child(JwUi.class_line(JwInfo.Cls.PROJECTED, JwText.render("tpl.projected.cash_path", {"scenario": JwText.t(String(pair[2])),
				"q_from": JwFormat.quarter(m.q), "q_to": JwFormat.quarter(m.q + t),
				"range_u": JwFormat.range_u(_min_lo(cb), _max_hi(cb)), "worst_quarter": JwFormat.quarter(m.q + _worst_t(cb)),
				"assumption_count": "2"}), true))
		if not ub.is_empty():
			var t2: int = ub.size() - 1
			v.add_child(JwUi.class_line(JwInfo.Cls.PROJECTED, JwText.render("tpl.projected.unemployment", {"scenario": JwText.t(String(pair[2])),
				"horizon_quarter": JwFormat.quarter(m.q + t2), "range_pct": JwFormat.range_pct(int(ub[t2]["lo"]), int(ub[t2]["hi"])),
				"assumption_count": "2"}), true))
		cols.add_child(v)
	var slots: Dictionary = session.catalog.scenario_slots()
	slots["draft"] = JwText.t("rp.s5.with_draft") if not session.drafts.is_empty() else ""
	body.add_child(JwUi.para(JwText.render("rp.s5.assume", slots), "text.ink2"))
	return sec["root"]


static func _min_lo(b: Array[Dictionary]) -> int:
	var v: int = int(b[0]["lo"])
	for x: Dictionary in b:
		v = mini(v, int(x["lo"]))
	return v


static func _max_hi(b: Array[Dictionary]) -> int:
	var v: int = int(b[0]["hi"])
	for x: Dictionary in b:
		v = maxi(v, int(x["hi"]))
	return v


static func _worst_t(b: Array[Dictionary]) -> int:
	var w: int = 0
	for i: int in b.size():
		if int(b[i]["lo"]) < int(b[w]["lo"]):
			w = i
	return w


# ── 六 · 下季待办 ───────────────────────────────────────────────────────

func _todo() -> PanelContainer:
	var m: JwReadModel = session.model
	var sec: Dictionary = _sec(JwText.t("rp.s6"), "Todo")
	var body: VBoxContainer = sec["body"]
	var n: int = 0
	for i: int in session.deferred.size():
		var d: Dictionary = session.deferred[i]
		var h: HBoxContainer = JwUi.hbox(10)
		h.add_child(JwUi.class_line(JwInfo.Cls.DERIVED, JwText.render("rp.todo.deferred", {"label": String(d.get("label", "")),
				"q": JwFormat.quarter(int(d.get("deferred_to_q", m.q)))}), true))
		var b: Button = JwUi.button(JwText.t("rp.todo.bring"))
		var ii: int = i
		b.pressed.connect(func() -> void: session.restore_deferred(ii))
		h.add_child(b)
		body.add_child(h)
		n += 1
	for row: Dictionary in m.project_rows():
		if int(row["status"]) == JwReadModel.PS_SUSPENDED:
			body.add_child(JwUi.class_line(JwInfo.Cls.DERIVED, JwText.render("rp.todo.suspended", {"project": _project_name(row),
					"why": JwText.t("suspend.%d" % int(row["suspension"]))}), true))
			n += 1
	if m.q % 4 == 3:
		body.add_child(JwUi.class_line(JwInfo.Cls.DERIVED, JwText.t("rp.todo.review_now"), true))
		n += 1
	elif (m.q + 1) % 4 == 3:
		body.add_child(JwUi.class_line(JwInfo.Cls.DERIVED, JwText.render("rp.todo.review_next", {"q": JwFormat.quarter(m.q + 1)}), true))
		n += 1
	if n == 0:
		body.add_child(JwUi.empty_state(JwText.t("rp.s6.empty.why"), JwText.t("rp.s6.empty.when"), JwText.t("rp.s6.empty.rule"), true))
	return sec["root"]


func get_required_above_fold(band: int) -> Array[StringName]:
	if band == JwScale.HBand.SHORT:
		return [&"ReportHeader", &"VarianceTable", &"LagBlock"]
	return [&"ReportHeader", &"VarianceTable", &"SettlementReceipt"]
