## 台账抽屉（docs/20 §5.4 L3）：Tree 实现（只绘制可视行，满足虚拟化），打开即定位并高亮目标行。
##
## 首版专用视图：cash / transaction / debt / commit / project / constraint / command；其余别名走通用列。
## 台账与调试导出显示内部记账原值（μU），不受「非零显示为零」禁令约束（docs/21 §1.5）。
class_name JwLedgerDrawer
extends JwOverlay

var ledger: String = ""
var tree: Tree = null
var highlighted_row: int = -1


func _init() -> void:
	width_ratio = 0.72
	height_ratio = 0.9


func build() -> void:
	ledger = String(ctx.get("ledger", "cash"))
	set_title(JwText.render("ld.title", {"name": JwText.t("ledger.name." + ledger), "alias": JwText.t("ledger.alias." + ledger)}))
	tree = Tree.new()
	tree.name = "LedgerTree"
	tree.hide_root = true
	tree.custom_minimum_size = Vector2(0, 520)
	tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tree.column_titles_visible = true
	tree.select_mode = Tree.SELECT_ROW
	tree.add_theme_font_override("font", JwTheme.font("dense"))
	tree.add_theme_font_size_override("font_size", 16)
	tree.add_theme_font_override("title_button_font", JwTheme.font("title_sub"))
	body.add_child(JwUi.label(JwText.t("ld.caliber." + ledger) if JwText.has("ld.caliber." + ledger) else JwText.t("ld.caliber.generic"),
			"body", "text.secondary", true))
	body.add_child(tree)
	_populate()
	var target: int = int(ctx.get("row", 0))
	if target > 0:
		_highlight(target)


func _cols(titles: Array) -> void:
	tree.columns = titles.size()
	for i: int in titles.size():
		tree.set_column_title(i, JwText.t(String(titles[i])))
		tree.set_column_expand(i, i == 1 or titles.size() <= 2)
		tree.set_column_clip_content(i, false)
		# 引用码列按「ldg.transaction#Q01.001」宽度留足，其余列 110。
		tree.set_column_custom_minimum_width(i, 230 if i == 0 else 110)


func _row(root: TreeItem, vals: Array) -> TreeItem:
	var it: TreeItem = tree.create_item(root)
	for i: int in vals.size():
		it.set_text(i, str(vals[i]))
	return it


func _populate() -> void:
	var m: JwReadModel = session.model
	var cat: JwCatalog = session.catalog
	var root: TreeItem = tree.create_item()
	if session.settling:
		_cols(["ld.col.item"])
		_row(root, [JwText.t("ld.settling")])
		return
	match ledger:
		"cash", "transaction":
			var v: JWGame.StateView = session.game.view()
			var rows: PackedInt64Array = v.ledger_rows(0, v.ledger_row_count())
			if ledger == "cash":
				_cols(["ld.col.row", "ld.col.kind", "ld.col.step", "ld.col.txn", "ld.col.delta", "ld.col.raw"])
			else:
				_cols(["ld.col.row", "ld.col.kind", "ld.col.step", "ld.col.txn", "ld.col.agent", "ld.col.account", "ld.col.delta"])
			var k: int = 0
			var i: int = 0
			while i + 12 < rows.size():
				var account: int = rows[i + 4]
				if ledger == "transaction" or account == 0:
					k += 1
					var kind: int = rows[i + 3]
					var delta: int = rows[i + 5]
					if ledger == "cash":
						_row(root, [JwFormat.citation(JwText.t("ledger.alias.cash"), rows[i + 1], k), JwText.t_or("ledger.kind.%d" % kind, "ledger.kind.other"),
								"S%02d" % rows[i + 2], str(rows[i]), JwFormat.u_signed(delta), JwFormat.uu_raw(delta)])
					else:
						@warning_ignore("integer_division")
						var agent: int = account / 15
						_row(root, [JwFormat.citation(JwText.t("ledger.alias.transaction"), rows[i + 1], k), JwText.t_or("ledger.kind.%d" % kind, "ledger.kind.other"),
								"S%02d" % rows[i + 2], str(rows[i]), _agent_name(agent), JwText.t("ledger.acc.%d" % (account % 15)),
								JwFormat.u_signed(delta)])
					if k >= 4000:
						break
				i += 13
			if k == 0:
				_row(root, [JwText.t("ld.empty")])
		"debt":
			_cols(["ld.col.batch", "ld.col.holder", "ld.col.outstanding", "ld.col.initial", "ld.col.coupon", "ld.col.issue", "ld.col.maturity"])
			for b: Dictionary in m.bond_rows():
				_row(root, [str(int(b["b"]) + 1), JwText.t("holder.%d" % int(b["holder"])), JwFormat.u(int(b["outstanding"])),
						JwFormat.u(int(b["initial"])), JwFormat.pct(int(b["coupon_ppm"])), JwFormat.quarter(int(b["issue_q"])) if int(b["issue_q"]) >= 0 else JwText.t("ld.pre_start"),
						JwFormat.quarter(int(b["maturity_q"]))])
			var sch: Array[Dictionary] = m.debt_schedule(8)
			for s: Dictionary in sch:
				_row(root, [JwText.t("ld.schedule"), JwFormat.quarter(int(s["q"])), JwFormat.u(int(s["principal"])), "",
						JwFormat.u(int(s["coupon"])), "", ""])
		"commit", "project":
			_cols(["ld.col.project", "ld.col.region", "ld.col.status", "ld.col.paid", "ld.col.total", "ld.col.delivery", "ld.col.construction", "ld.col.suspend"])
			for r: Dictionary in m.project_rows():
				_row(root, [String(cat.policy(int(r["policy"])).get("label", "")) + " #" + str(int(r["p"]) + 1), cat.region_label(int(r["region"])),
						JwText.t("project_status.%d" % int(r["status"])), JwFormat.u(int(r["paid"])), JwFormat.u(int(r["total"])),
						JwFormat.pct(int(r["delivery_ppm"])), JwFormat.pct(int(r["construction_ppm"])), JwText.t("suspend.%d" % int(r["suspension"]))])
			if ledger == "commit":
				for p: int in JwReadModel.POLICY_N:
					var c: int = m.at("state.policy.budget_committed_uu", p)
					if c > 0:
						_row(root, [String(cat.policy(p).get("label", "")), JwText.t("ld.national"), JwText.t("pol.status.active") if m.policy_enabled(p) else "",
								JwFormat.u(m.at("state.policy.budget_spent_uu", p)), JwFormat.u(c), "", "", ""])
				_row(root, [JwText.t("ld.commit_total"), "", "", "", JwFormat.u(m.sc("state.gov.committed_memo_uu")), "", "", ""])
		"constraint":
			_cols(["ld.col.cell", "binding.0", "binding.1", "binding.2", "binding.3", "binding.4", "ld.col.actual", "ld.col.binding"])
			for c2: int in JwReadModel.CELL:
				var bd: Dictionary = m.cell_bounds(c2)
				@warning_ignore("integer_division")
				var rr: int = c2 / 4
				_row(root, [cat.region_label(rr) + JwText.t("sector.%d" % (c2 % 4)), _q(int(bd["plan"])), _q(int(bd["capacity"])), _q(int(bd["labor"])),
						_q(int(bd["energy"])), _q(int(bd["materials"])), _q(int(bd["actual"])), JwText.t("binding.%d" % int(bd["binding"]))])
		"command":
			_cols(["ld.col.row", "ld.col.issued", "ld.col.cmd", "ld.col.args", "ld.col.accepted", "ld.col.reject"])
			var cl: Dictionary = m.cmdlog
			var n2: int = int(cl.get("count", 0))
			var kd: PackedInt64Array = cl.get("kind", PackedInt64Array())
			var iq: PackedInt64Array = cl.get("issued_q", PackedInt64Array())
			var ac: PackedInt64Array = cl.get("accepted", PackedInt64Array())
			var rj: PackedInt64Array = cl.get("reject_code", PackedInt64Array())
			var ag: PackedInt64Array = cl.get("args", PackedInt64Array())
			for i2: int in n2:
				_row(root, [str(i2 + 1), JwFormat.quarter(iq[i2]), JwText.t_or("cmd.kind.%d" % kd[i2], "cmd.kind.other") if kd[i2] != 99 else JwText.t("ld.marker"),
						str(ag.slice(i2 * 6, i2 * 6 + 6)), JwText.t("common.yes") if ac[i2] == 1 else JwText.t("common.no"),
						JwText.t_or("reject.name.%d" % rj[i2], "reject.name.other") if rj[i2] != 0 else JwText.t("common.none")])
			if n2 == 0:
				_row(root, [JwText.t("ld.empty")])
		"labor":
			_cols(["ld.col.region", "skill.0", "skill.1", "skill.2", "ld.col.rate"])
			for r2: int in JwReadModel.R:
				var parts: Array = [cat.region_label(r2)]
				for sk: int in 3:
					var g: int = JwReadModel.idx_group(r2, JwReadModel.AGE_WORKING, sk)
					parts.append(JwText.render("ld.labor_cell", {"emp": JwFormat.group3(m.group_employed(g)), "lf": JwFormat.group3(m.group_labor_force(g))}))
				parts.append(JwFormat.pct(int(m.region_unemployment(r2)["rate_ppm"])))
				_row(root, parts)
		"household", "politics":
			_cols(["ld.col.group", "ld.col.pop", "ld.col.disp", "ld.col.housing", "ld.col.living", "ld.col.trust", "ld.col.support"])
			for g2: int in JwReadModel.GROUP:
				_row(root, [session.group_label(g2), JwFormat.group3(m.group_population(g2)), JwFormat.u(m.group_disposable(g2)),
						JwFormat.u(m.at("flow.group.housing_cost_uu", g2)), JwFormat.index(m.at("state.group.living_index_ppm", g2)),
						JwFormat.pct(m.at("state.group.trust_ppm", g2)), JwFormat.pct(m.at("state.group.support_ppm", g2))])
		"service", "opex":
			_cols(["ld.col.region", "ld.col.avail", "ld.col.teachers", "ld.col.health", "ld.col.queue", "ld.col.opex_paid"])
			for r3: int in JwReadModel.R:
				var qn: int = 0
				var op: int = 0
				for kk: int in 3:
					qn += m.at("state.pubserv.queue_persons", r3 * 3 + kk)
					op += m.at("flow.gov.pay_opex_uu", r3 * 3 + kk)
				_row(root, [cat.region_label(r3), JwFormat.pct(m.pubserv_availability(r3)), JwFormat.group3(m.at("state.pubserv.teachers_persons", r3)),
						JwFormat.group3(m.at("state.pubserv.health_staff_persons", r3)), JwFormat.group3(qn), JwFormat.u(op)])
		"tax":
			_cols(["ld.col.item", "ld.col.value"])
			_row(root, [JwText.t("ar.tax.income"), JwFormat.u(m.sc("flow.gov.receipts_income_tax_uu"))])
			_row(root, [JwText.t("ar.tax.profit"), JwFormat.u(m.sc("flow.gov.receipts_profit_tax_uu"))])
			_row(root, [JwText.t("ar.tax.other"), JwFormat.u(m.sc("flow.gov.receipts_other_uu"))])
			_row(root, [JwText.t("ld.tax_capacity"), JwFormat.pct(m.sc("state.gov.tax_capacity_ppm"))])
			_row(root, [JwText.t("ld.tax_receivable"), JwFormat.u(m.sc("state.gov.tax_receivable_uu"))])
		"external":
			_cols(["ld.col.item", "ld.col.value"])
			_row(root, [JwText.t("ld.ext.limit"), JwFormat.u(m.sc("state.world.credit_limit_uu"))])
			_row(root, [JwText.t("ld.ext.used"), JwFormat.u(m.sc("state.world.credit_used_uu"))])
			_row(root, [JwText.t("ld.ext.exports"), JwFormat.u(m.sc("flow.world.exports_uu"))])
			_row(root, [JwText.t("ld.ext.imports"), JwFormat.u(m.sc("flow.world.imports_uu"))])
			for sh: Dictionary in m.active_shocks():
				_row(root, [String(cat.shocks[int(sh["k"])]["label"]), JwText.t("ld.ext.shock_active")])
		"value_added":
			_cols(["ld.col.cell", "ld.col.va", "ld.col.va_real", "ld.col.gross", "ld.col.wages"])
			for c3: int in JwReadModel.CELL:
				@warning_ignore("integer_division")
				var r4: int = c3 / 4
				_row(root, [cat.region_label(r4) + JwText.t("sector.%d" % (c3 % 4)), JwFormat.u(m.at("flow.cell.value_added_uu", c3)),
						JwFormat.u(m.at("flow.cell.value_added_real_uu", c3)), JwFormat.u(m.at("flow.cell.gross_output_uu", c3)),
						JwFormat.u(m.at("flow.cell.wage_bill_uu", c3))])
		_:
			_cols(["ld.col.item", "ld.col.value"])
			_row(root, [JwText.t("ld.generic"), ""])


func _q(v: int) -> String:
	if v >= JwReadModel.U * 1000:
		return JwText.t("rg.ladder.na")
	return JwFormat.qty_num(v)


func _agent_name(a: int) -> String:
	var cat: JwCatalog = session.catalog
	if a == 0:
		return JwText.t("agent.gov")
	if a >= 1 and a <= 16:
		@warning_ignore("integer_division")
		var r: int = (a - 1) / 4
		return cat.region_label(r) + JwText.t("sector.%d" % ((a - 1) % 4))
	if a >= 17 and a <= 20:
		return cat.region_label(a - 17) + JwText.t("agent.pubserv")
	if a >= 21 and a <= 56:
		return session.group_label(a - 21)
	if a == 57:
		return JwText.t("agent.invpool")
	if a == 58:
		return JwText.t("agent.row")
	return JwText.t("agent.opening")


## 定位并高亮第 row 行（1 基）。
func _highlight(row: int) -> void:
	var root: TreeItem = tree.get_root()
	if root == null:
		return
	var it: TreeItem = root.get_first_child()
	var i: int = 1
	while it != null:
		if i == row:
			tree.set_selected(it, 0)
			tree.scroll_to_item(it, true)
			highlighted_row = row
			return
		it = it.get_next()
		i += 1
