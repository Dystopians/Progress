## 预算审查与推进确认框共用的三张表（docs/20 §8.3、§8.4；同一函数，两处逐字一致）。
##
## A1 四季现金预测：口径写死「含本季，共 4 列」。逐格单值分类（BR-2）：
##   期初现金只有本季是实（点值），其后全部是预（区间）；按已签合同与已发行批次的到期额是算；
##   依赖未来经济结果的收入、一般支出、自动融资与期末现金是预（区间）。
## A2 情景对照：基线 / 不利条件同屏并列，三行 × 四季，每格两个区间（BR-8，禁止切换器代替）。
## B 本草案新增长期承诺：永续行写「— (永续)」，必有取消代价列与三项合计。
class_name JwFiscalTables
extends RefCounted


static func _cell_u(v: int, cls: int) -> Dictionary:
	return {"text": JwFormat.u_num(v), "cls": cls}


static func _cell_r(lo: int, hi: int) -> Dictionary:
	return {"text": JwFormat.range_u_num(lo, hi), "cls": JwInfo.Cls.PROJECTED}


static func _cols(s: JwSession, first: String) -> Array:
	var q: int = s.model.q
	var n: int = int(s.catalog.cfg("preview_quarters", 4))
	var cols: Array = [{"title": first, "w": 180}]
	for t: int in n:
		cols.append({"title": JwFormat.quarter(q + t), "w": 160, "align": "r", "expand": true})
	return cols


## A1：返回表格控件；session.dry 未就绪时返回「重算中」提示。
static func a1(s: JwSession, paper: bool = false) -> Control:
	var v: VBoxContainer = JwUi.vbox(6)
	JwUi.tag(v, "CashProjectionTable")
	var m: JwReadModel = s.model
	var n: int = int(s.catalog.cfg("preview_quarters", 4))
	v.add_child(JwUi.label(JwText.t("fis.a1.title"), "title_sub", "text.ink" if paper else "text.primary"))
	v.add_child(JwUi.label(JwText.t("fis.a1.caliber"), "body", "text.ink2" if paper else "text.secondary", true))
	if s.dry.is_empty():
		v.add_child(JwUi.label(JwText.t("common.recalc"), "body", "warm.text"))
		return v
	var t: JwTable = JwTable.make(_cols(s, JwText.t("fis.col.item")), paper, true)
	v.add_child(t)
	var cash0: Array[Dictionary] = s.band("nodraft_lo", "nodraft_hi", "cash_end")
	var rec: Array[Dictionary] = s.band("nodraft_lo", "nodraft_hi", "receipts")
	var borrow: Array[Dictionary] = s.band("nodraft_lo", "nodraft_hi", "new_borrowing")
	var sch: Array[Dictionary] = m.debt_schedule(n)
	var inst: PackedInt64Array = m.project_installments(n)
	# 段一 · 现行承诺（不含本草案）
	t.add_group_title(JwText.t("fis.a1.seg1"))
	var r_open: Array = [JwText.t("fis.row.cash_open")]
	for i: int in n:
		if i == 0:
			r_open.append(_cell_u(m.gov_cash(), JwInfo.Cls.ACTUAL))
		elif i - 1 < cash0.size():
			r_open.append(_cell_r(int(cash0[i - 1]["lo"]), int(cash0[i - 1]["hi"])))
		else:
			r_open.append("")
	# 本行逐格单值分类：本季是实、其后是预（BR-3）；行级类列留空，不给整行统一取值（BR-2）。
	t.add_row(r_open, JwInfo.Cls.NONE)
	t.add_row(_band_row(JwText.t("fis.row.receipts"), rec, n, 1), JwInfo.Cls.PROJECTED)
	var gen: Array = [JwText.t("fis.row.general")]
	var g_lo: PackedInt64Array = _general(s.run("nodraft_lo"))
	var g_hi: PackedInt64Array = _general(s.run("nodraft_hi"))
	for i2: int in n:
		if i2 < g_lo.size() and i2 < g_hi.size():
			gen.append(_cell_r(-maxi(g_lo[i2], g_hi[i2]), -mini(g_lo[i2], g_hi[i2])))
		else:
			gen.append("")
	t.add_row(gen, JwInfo.Cls.PROJECTED)
	var r_int: Array = [JwText.t("fis.row.interest")]
	var r_pri: Array = [JwText.t("fis.row.principal")]
	var r_proj: Array = [JwText.t("fis.row.projects")]
	var r_opex: Array = [JwText.t("fis.row.opex")]
	for i3: int in n:
		r_int.append(_cell_u(-int(sch[i3]["coupon"]), JwInfo.Cls.DERIVED))
		r_pri.append(_cell_u(-int(sch[i3]["principal"]), JwInfo.Cls.DERIVED))
		r_proj.append(_cell_u(-inst[i3], JwInfo.Cls.DERIVED))
		r_opex.append(_cell_u(-m.sc("state.gov.service_opex_committed_uu"), JwInfo.Cls.DERIVED))
	t.add_row(r_int, JwInfo.Cls.DERIVED)
	t.add_row(r_pri, JwInfo.Cls.DERIVED)
	t.add_row(r_proj, JwInfo.Cls.DERIVED)
	t.add_row(r_opex, JwInfo.Cls.DERIVED)
	t.add_row(_band_row(JwText.t("fis.row.borrowing"), borrow, n, 1), JwInfo.Cls.PROJECTED)
	# 段二 · 本草案新增
	t.add_group_title(JwText.t("fis.a1.seg2"))
	if s.drafts.is_empty():
		var empty_row: Array = [JwText.t("fis.row.no_draft")]
		for i4: int in n:
			empty_row.append(_cell_r(0, 0))
		t.add_row(empty_row, JwInfo.Cls.PROJECTED)
	else:
		t.add_row(_delta_row(s, JwText.t("fis.row.draft_spend"), "primary_paid", n, -1), JwInfo.Cls.PROJECTED)
		t.add_row(_delta_row(s, JwText.t("fis.row.draft_borrow"), "new_borrowing", n, 1), JwInfo.Cls.PROJECTED)
	# 段三 · 合计
	t.add_group_title(JwText.t("fis.a1.seg3"))
	var cash_end: Array[Dictionary] = s.band("draft_lo", "draft_hi", "cash_end")
	var floor_uu: int = int(s.catalog.cfg("cash_floor_uu", 0))
	var r_end: Array = [JwText.t("fis.row.cash_end")]
	for i5: int in n:
		if i5 < cash_end.size():
			var lo: int = int(cash_end[i5]["lo"])
			var hi: int = int(cash_end[i5]["hi"])
			var cell: Dictionary = _cell_r(lo, hi)
			if lo < floor_uu:
				cell["text"] = JwText.render("fis.gap_cell", {"range": String(cell["text"])})
				cell["color"] = "ochre.ink" if paper else "ochre.core"
				cell["icon"] = "warn"
			r_end.append(cell)
		else:
			r_end.append("")
	t.add_row(r_end, JwInfo.Cls.PROJECTED)
	t.add_row(_band_row(JwText.t("fis.row.arrears"), s.band("draft_lo", "draft_hi", "arrears"), n, 1), JwInfo.Cls.PROJECTED)
	t.add_note(JwText.render("fis.a1.footer", {"floor": JwFormat.u(floor_uu)}))
	return v


## 一般支出（逐季）= 基本支出实付 − 项目履约款 − 服务运行费（同一次试算内相减，再取两次试算的区间）。
static func _general(run: Dictionary) -> PackedInt64Array:
	var p: PackedInt64Array = JwReasons._series(run, "primary_paid")
	var j: PackedInt64Array = JwReasons._series(run, "project_paid")
	var o: PackedInt64Array = JwReasons._series(run, "opex_paid")
	var out: PackedInt64Array = PackedInt64Array()
	for t: int in p.size():
		out.append(p[t] - (j[t] if t < j.size() else 0) - (o[t] if t < o.size() else 0))
	return out


static func _band_row(label: String, b: Array[Dictionary], n: int, sign: int) -> Array:
	var row: Array = [label]
	for i: int in n:
		if i < b.size():
			var lo: int = int(b[i]["lo"]) * sign
			var hi: int = int(b[i]["hi"]) * sign
			row.append(_cell_r(mini(lo, hi), maxi(lo, hi)))
		else:
			row.append("")
	return row


## 含草案 − 不含草案（基线两次试算的逐季差，区间）。
static func _delta_row(s: JwSession, label: String, key: String, n: int, sign: int) -> Array:
	var row: Array = [label]
	var a: Array[Dictionary] = s.band("draft_lo", "draft_lo", key)
	var b: Array[Dictionary] = s.band("nodraft_lo", "nodraft_lo", key)
	var c: Array[Dictionary] = s.band("draft_hi", "draft_hi", key)
	var d: Array[Dictionary] = s.band("nodraft_hi", "nodraft_hi", key)
	for i: int in n:
		if i < a.size() and i < b.size() and i < c.size() and i < d.size():
			var x: int = (int(a[i]["lo"]) - int(b[i]["lo"])) * sign
			var y: int = (int(c[i]["lo"]) - int(d[i]["lo"])) * sign
			row.append(_cell_r(mini(x, y), maxi(x, y)))
		else:
			row.append("")
	return row


## A2：三行 × 四季 × 两情景（每格两个区间，基线在上、不利在下）。
static func a2(s: JwSession, paper: bool = false) -> Control:
	var v: VBoxContainer = JwUi.vbox(6)
	JwUi.tag(v, "ScenarioTable")
	var n: int = int(s.catalog.cfg("preview_quarters", 4))
	var m: JwReadModel = s.model
	v.add_child(JwUi.label(JwText.t("fis.a2.title"), "title_sub", "text.ink" if paper else "text.primary"))
	if s.dry.is_empty():
		v.add_child(JwUi.label(JwText.t("common.recalc"), "body", "warm.text"))
		return v
	var t: JwTable = JwTable.make(_cols(s, JwText.t("fis.col.item")), paper, true)
	v.add_child(t)
	var floor_uu: int = int(s.catalog.cfg("cash_floor_uu", 0))
	var rows: Array = [
		["fis.a2.cash", "cash_end", 0],
		["fis.a2.commit", "committed", 0],
		["fis.a2.floor", "cash_end", floor_uu],
	]
	for rd: Array in rows:
		var base: Array[Dictionary] = s.band("draft_lo", "draft_hi", String(rd[1]))
		var adv: Array[Dictionary] = s.band("adv_lo", "adv_hi", String(rd[1]))
		var off: int = int(rd[2])
		var row: Array = [JwText.t(String(rd[0]))]
		for i: int in n:
			if i < base.size() and i < adv.size():
				var txt: String = JwText.render("fis.a2.pair", {
					"base": JwFormat.range_u_num(int(base[i]["lo"]) - off, int(base[i]["hi"]) - off),
					"adverse": JwFormat.range_u_num(int(adv[i]["lo"]) - off, int(adv[i]["hi"]) - off)})
				var cell: Dictionary = {"text": txt, "cls": JwInfo.Cls.PROJECTED, "wrap": true}
				if int(adv[i]["lo"]) - off < 0 and String(rd[0]) != "fis.a2.commit":
					cell["color"] = "ochre.ink" if paper else "ochre.core"
				row.append(cell)
			else:
				row.append("")
		t.add_row(row, JwInfo.Cls.PROJECTED)
	v.add_child(JwUi.label(JwText.render("fis.a2.defs", s.catalog.scenario_slots()), "caption",
			"text.ink2" if paper else "text.muted", true))
	v.add_child(JwUi.label(JwText.render("fis.a2.hidden", {"q": JwFormat.quarter(m.q + n - 1)}), "caption",
			"text.ink2" if paper else "text.muted", true))
	return v


## B：本草案新增长期承诺全量 + 三项合计（缺一不渲染）。
static func b_table(s: JwSession, paper: bool = false) -> Control:
	var v: VBoxContainer = JwUi.vbox(6)
	JwUi.tag(v, "CommitmentTable")
	v.add_child(JwUi.label(JwText.t("fis.b.title"), "title_sub", "text.ink" if paper else "text.primary"))
	var com: Dictionary = s.draft_commitments()
	var rows: Array = com["rows"]
	var cols: Array = [
		{"title": JwText.t("fis.b.col.item"), "w": 200, "expand": true, "wrap": true},
		{"title": JwText.t("fis.b.col.type"), "w": 90},
		{"title": JwText.t("fis.b.col.party"), "w": 100},
		{"title": JwText.t("fis.b.col.from"), "w": 80},
		{"title": JwText.t("fis.b.col.to"), "w": 90},
		{"title": JwText.t("fis.b.col.per_q"), "w": 110, "align": "r"},
		{"title": JwText.t("fis.b.col.cum"), "w": 110, "align": "r"},
		{"title": JwText.t("fis.b.col.cancel"), "w": 200, "wrap": true, "expand": true},
		{"title": JwText.t("fis.b.col.source"), "w": 80},
	]
	var t: JwTable = JwTable.make(cols, paper, false)
	v.add_child(t)
	if rows.is_empty():
		v.add_child(JwUi.label(JwText.t("fis.b.empty"), "body", "text.ink2" if paper else "text.muted"))
	for r: Variant in rows:
		var rd: Dictionary = r
		var perpetual: bool = bool(rd.get("perpetual", false))
		var party: String = String(rd.get("counterparty", ""))
		var party_t: String = JwText.t("fis.party." + party) if not party.begins_with("holder.") else JwText.t(party)
		t.add_row([
			String(rd.get("label", "")),
			JwText.t("fis.type." + String(rd.get("type", ""))),
			party_t,
			JwFormat.quarter(int(rd.get("start_q", 0))),
			JwText.t("fis.perpetual_to") if int(rd.get("end_q", -1)) < 0 else JwFormat.quarter(int(rd["end_q"])),
			{"text": JwFormat.u_num(int(rd.get("per_q", 0))), "cls": JwInfo.Cls.DERIVED},
			{"text": JwText.t("fis.perpetual") if perpetual else JwFormat.u_num(int(rd.get("cum", 0))),
				"cls": JwInfo.Cls.DERIVED},
			String(rd.get("cancel", "")),
			JwText.t("ledger.alias." + String(rd.get("source", "commit"))),
		], JwInfo.Cls.DERIVED)
	var totals: Label = JwUi.label(JwText.render("fis.b.totals", {"four_q": JwFormat.u(int(com["four_q"])),
			"steady": JwFormat.u(int(com["steady"])), "irrev": JwFormat.u(int(com["irreversible"]))}),
			"body_bold", "text.ink" if paper else "text.primary", true)
	JwUi.tag(totals, "CommitTotals")
	v.add_child(totals)
	v.add_child(JwUi.label(JwText.t("fis.b.perpetual_note"), "caption", "text.ink2" if paper else "text.muted", true))
	v.add_child(JwUi.label(JwText.t("fis.b.caliber"), "caption", "text.ink2" if paper else "text.muted", true))
	return v


## 将提交的命令清单（含逐条的按规则试算回执）。
static func command_list(s: JwSession) -> Control:
	var v: VBoxContainer = JwUi.vbox(4)
	JwUi.tag(v, "CommandList")
	v.add_child(JwUi.label(JwText.render("fis.cmd.title", {"n": str(s.drafts.size())}), "title_sub"))
	if s.drafts.is_empty():
		v.add_child(JwUi.label(JwText.t("fis.cmd.empty"), "body", "text.secondary", true))
	var verdicts: Array[Dictionary] = s.draft_verdicts()
	for i: int in s.drafts.size():
		var d: Dictionary = s.drafts[i]
		var ok: bool = i < verdicts.size() and int(verdicts[i]["code"]) == 0
		var h: HBoxContainer = JwUi.hbox(8)
		h.add_child(JwIcon.make("ok" if ok else "block", JwTheme.c("teal.core" if ok else "ochre.hot"), 14))
		h.add_child(JwUi.label("%d. " % (i + 1) + String(d.get("label", "")), "body", "text.primary", true))
		h.add_child(JwUi.label(JwText.t("fis.cmd.ok") if ok else JwText.t("fis.cmd.block"), "caption",
				"text.secondary" if ok else "ochre.core"))
		v.add_child(h)
	v.add_child(JwUi.label(JwText.t("fis.cmd.marker"), "caption", "text.muted", true))
	return v


## 本季将发生的全部不可逆动作（开关成本、首季履约款、新增债务）。
static func irreversible_list(s: JwSession) -> Control:
	var v: VBoxContainer = JwUi.vbox(4)
	JwUi.tag(v, "IrreversibleList")
	var com: Dictionary = s.draft_commitments()
	var items: Array = com["irreversible_items"]
	v.add_child(JwUi.label(JwText.render("fis.irrev.title", {"n": str(items.size())}), "title_sub"))
	if items.is_empty():
		v.add_child(JwUi.label(JwText.t("fis.irrev.empty"), "body", "text.secondary", true))
	for it: Variant in items:
		var d: Dictionary = it
		v.add_child(JwUi.class_line(JwInfo.Cls.DERIVED, JwText.render("fis.irrev.item", {"label": String(d["label"]),
				"text": String(d["text"])})))
	return v


## 原因清单（BLOCK 与 GAP 永不折叠；NOTE 超过 3 条折叠）。
static func reason_list(s: JwSession, root_ui: Node, fold_notes: bool, paper: bool = false) -> Control:
	var v: VBoxContainer = JwUi.vbox(8)
	JwUi.tag(v, "ReasonList")
	var rs: Array = s.reasons()
	var c: Dictionary = JwReasons.counts(rs)
	v.add_child(JwUi.label(JwText.render("fis.reasons.title", {"block": str(int(c["block"])), "gap": str(int(c["gap"])),
			"note": str(int(c["note"]))}), "title_sub", "text.ink" if paper else "text.primary"))
	if rs.is_empty():
		v.add_child(JwUi.label(JwText.t("fis.reasons.empty"), "body", "text.secondary", true))
	var notes_shown: int = 0
	var folded: int = 0
	for r: Variant in rs:
		var rd: Dictionary = r
		if int(rd.get("severity", 0)) == JwInfo.Sev.NOTE and fold_notes:
			if notes_shown >= 3:
				folded += 1
				continue
			notes_shown += 1
		v.add_child(JwReasonView.make(rd, s, root_ui, paper))
	if folded > 0:
		v.add_child(JwUi.label(JwText.render("fis.reasons.more", {"n": str(folded)}), "body", "text.muted"))
	return v
