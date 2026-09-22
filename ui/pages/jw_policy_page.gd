## 页面三 · 政策工作台（docs/20 §7.3）：「我能改什么？要付什么代价？为什么这条现在不能执行？」
##
## 左：12 项政策目录，按状态分组，折叠态即带一句原因（与预算审查、确认框同一渲染函数）。
## 中：政策编辑器（九字段 / 参数 / 动作 / 本政策的原因 / 影响预览两栏 + 群组分解）。
## 右：草案篮（逐条 S02 回执）、常设安排披露、发债、在建项目与取消。
## 参数编辑全程整数（步进器），提交前不改任何状态；草案在确认推进时才提交（JwSession）。
class_name JwPolicyPage
extends JwPage

var selected: int = 0
var edit_params: Dictionary = {}
var launch_region: Dictionary = {}
var launch_scale: Dictionary = {}
var funding_choice: Dictionary = {}
var bond_amount: int = 1_000_000_000
var bond_tenor: int = 8
var bond_holder: int = 0
var _root: HBoxContainer = null
var _show_full_fields: bool = true
var _cost_card_for: int = -1
## 正在展示延期成本卡的项目（R-DEFER-01）。
var _defer_card_for: int = -1


func apply_context(ctx: Dictionary) -> void:
	if ctx.has("p") and int(ctx["p"]) >= 0:
		selected = int(ctx["p"])


func refresh() -> void:
	if _root != null:
		remove_child(_root)
		_root.queue_free()
	_root = JwUi.hbox(14)
	_root.name = "PolicyRoot"
	add_child(_root)
	if session == null or session.game == null:
		_root.add_child(JwUi.empty_state(JwText.t("pol.empty.why"), JwText.t("pol.empty.when"), JwText.t("pol.empty.rule")))
		return
	var wide: bool = wband == JwScale.WBand.WIDE
	var cat_col: Control = _catalog()
	var ts: HFlowContainer = term_strip()
	cat_col.add_child(ts)
	cat_col.move_child(ts, 0)
	cat_col.custom_minimum_size = Vector2(390 if wide else 320, 0)
	_root.add_child(cat_col)
	var ed: ScrollContainer = JwUi.scroll(_editor())
	ed.size_flags_stretch_ratio = 2.2
	_root.add_child(ed)
	var tray: ScrollContainer = JwUi.scroll(_tray())
	tray.custom_minimum_size = Vector2(360 if wide else 300, 0)
	tray.size_flags_horizontal = Control.SIZE_FILL
	_root.add_child(tray)


func on_dryrun() -> void:
	if visible:
		refresh()


# ── 目录 ───────────────────────────────────────────────────────────────

func _catalog() -> Control:
	var m: JwReadModel = session.model
	var cat: JwCatalog = session.catalog
	var outer: VBoxContainer = JwUi.vbox(8)
	JwUi.tag(outer, "PolicyCatalog")
	var blocked: Array[int] = []
	var ok: Array[int] = []
	var reasons: Dictionary = {}
	for p: int in JwReadModel.POLICY_N:
		var r: Dictionary = JwReasons.for_catalog(p, m, cat)
		reasons[p] = r
		if r.is_empty():
			ok.append(p)
		else:
			blocked.append(p)
	var gap_list: Array[int] = []
	var sum: Label = JwUi.label(JwText.render("pol.catalog.summary", {"ok": str(ok.size()), "gap": str(gap_list.size()),
			"block": str(blocked.size())}), "title_sub")
	JwUi.tag(sum, "CatalogSummary")
	outer.add_child(sum)
	var scroll_body: VBoxContainer = JwUi.vbox(6)
	outer.add_child(JwUi.scroll(scroll_body))
	var gb: VBoxContainer = _group(JwText.render("pol.group.block", {"n": str(blocked.size())}), "CatalogGroupBlocked",
			JwInfo.Sev.BLOCK)
	scroll_body.add_child(gb)
	for p2: int in blocked:
		gb.add_child(_catalog_item(p2, reasons[p2]))
	var gg: VBoxContainer = _group(JwText.render("pol.group.gap", {"n": str(gap_list.size())}), "CatalogGroupGap", JwInfo.Sev.GAP)
	scroll_body.add_child(gg)
	if gap_list.is_empty():
		gg.add_child(JwUi.label(JwText.t("pol.group.gap_empty"), "caption", "text.muted", true))
	var go: VBoxContainer = _group(JwText.render("pol.group.ok", {"n": str(ok.size())}), "CatalogGroupOk", -1)
	scroll_body.add_child(go)
	for p3: int in ok:
		go.add_child(_catalog_item(p3, {}))
	return outer


func _group(title: String, id: String, sev: int) -> VBoxContainer:
	var v: VBoxContainer = JwUi.vbox(4)
	JwUi.tag(v, id)
	var h: HBoxContainer = JwUi.hbox(6)
	if sev >= 0:
		h.add_child(JwIcon.make(JwInfo.sev_icon(sev), JwTheme.c(JwInfo.sev_color_token(sev)), 14))
	else:
		h.add_child(JwIcon.make("ok", JwTheme.c("teal.core"), 14))
	h.add_child(JwUi.label(title, "body_bold", "text.secondary"))
	v.add_child(h)
	return v


func _catalog_item(p: int, reason: Dictionary) -> PanelContainer:
	var m: JwReadModel = session.model
	var pd: Dictionary = session.catalog.policy(p)
	var sel: bool = p == selected
	var sb: StyleBoxFlat = JwTheme.box4("bg.raised" if sel else "bg.panel", "focus.ring" if sel else "line.hair",
			2 if sel else 1, 10, 6, 10, 6)
	var panel: PanelContainer = JwUi.panel_style(sb)
	JwUi.tag(panel, "PolicyItem%02d" % (p + 1))
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	panel.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed \
				and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			selected = p
			session.log_event("ev.policy_selected", {"p": p})
			refresh())
	var v: VBoxContainer = JwUi.vbox(2)
	panel.add_child(v)
	var h: HBoxContainer = JwUi.hbox(8)
	h.add_child(JwUi.label(String(pd.get("code", "")), "num_bold", "text.secondary"))
	h.add_child(JwUi.label(String(pd.get("label", "")), "body_bold" if sel else "body", "text.primary"))
	h.add_child(JwUi.spacer())
	if m.policy_enabled(p):
		h.add_child(JwUi.label(JwText.t("pol.status.active"), "caption", "teal.core"))
	elif session.catalog.is_project(p):
		var n_active: int = 0
		for row: Dictionary in m.project_rows():
			if int(row["policy"]) == p and int(row["status"]) <= JwReadModel.PS_COMPLETED:
				n_active += 1
		if n_active > 0:
			h.add_child(JwUi.label(JwText.render("pol.status.projects", {"n": str(n_active)}), "caption", "teal.core"))
	if _in_draft(p):
		h.add_child(JwUi.label(JwText.t("pol.status.in_draft"), "caption", "warm.text"))
	v.add_child(h)
	if not reason.is_empty():
		var rl: HBoxContainer = JwUi.hbox(6)
		rl.add_child(JwIcon.make("block", JwTheme.c("ochre.hot"), 12))
		var lab: Label = JwUi.label(JwText.t("reason.cat." + String(reason["code"])) + "：" + String(reason["line2"]),
				"caption", "text.secondary", true)
		lab.set_meta("reason_text", JwReasons.render_text(reason))
		rl.add_child(lab)
		v.add_child(rl)
	return panel


func _in_draft(p: int) -> bool:
	for d: Dictionary in session.drafts:
		if int(d.get("p", -1)) == p:
			return true
	return false


# ── 编辑器 ─────────────────────────────────────────────────────────────

func _editor() -> VBoxContainer:
	var m: JwReadModel = session.model
	var cat: JwCatalog = session.catalog
	var p: int = selected
	var pd: Dictionary = cat.policy(p)
	var v: VBoxContainer = JwUi.vbox(12)
	JwUi.tag(v, "PolicyEditor")
	var head: HBoxContainer = JwUi.hbox(12)
	JwUi.tag(head, "Headline")
	head.add_child(JwUi.label(String(pd.get("code", "")) + " " + String(pd.get("label", "")), "title_page"))
	var reason: Dictionary = JwReasons.for_catalog(p, m, cat)
	if reason.is_empty():
		# 「可提交 / 生效中」不是风险：用勾选图标 + 青绿文字，不用赭色风险徽章（§12.2）。
		var okb: HBoxContainer = JwUi.hbox(6)
		okb.add_child(JwIcon.make("ok", JwTheme.c("teal.core"), 14))
		okb.add_child(JwUi.label(JwText.t("pol.status.active") if m.policy_enabled(p) else JwText.t("pol.status.ok"),
				"body_bold", "teal.core"))
		head.add_child(okb)
	else:
		head.add_child(JwUi.risk_badge(JwInfo.Sev.BLOCK, JwText.t("reason.cat." + String(reason["code"]))))
	v.add_child(head)
	v.add_child(_fields(p, pd))
	v.add_child(_params_and_actions(p, pd))
	if not reason.is_empty():
		var rs: Dictionary = JwUi.section(JwText.t("pol.section.why"))
		(rs["body"] as VBoxContainer).add_child(JwReasonView.make(reason, session, root_ui))
		v.add_child(rs["root"])
	for r2: Variant in session.reasons():
		var rd: Dictionary = r2
		if rd.has("draft"):
			var di: int = int(rd["draft"])
			if di >= 0 and di < session.drafts.size() and int(session.drafts[di].get("p", -1)) == p:
				var rs2: Dictionary = JwUi.section(JwText.t("pol.section.why_draft"))
				(rs2["body"] as VBoxContainer).add_child(JwReasonView.make(rd, session, root_ui))
				v.add_child(rs2["root"])
	v.add_child(_impact(p, pd))
	return v


func _fields(p: int, pd: Dictionary) -> PanelContainer:
	var m: JwReadModel = session.model
	var cat: JwCatalog = session.catalog
	var sec: Dictionary = JwUi.section(JwText.t("pol.section.fields"))
	var root: PanelContainer = sec["root"]
	JwUi.tag(root, "Fields")
	var grid: GridContainer = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 6)
	(sec["body"] as VBoxContainer).add_child(grid)
	var bloc_names: PackedStringArray = PackedStringArray()
	for b: Variant in pd.get("requires_bloc_support", []):
		bloc_names.append(cat.bloc_label(cat.bloc_index(String(b))))
	var authority: String = JwText.render("pol.f.authority", {"auth": JwText.t("authority.bit.%d" % int(pd["authority_bit"])),
			"seats": JwFormat.pct(int(pd["min_seats_ppm"])),
			"window": JwText.t("pol.f.window_yes") if bool(pd["requires_budget_review"]) else JwText.t("pol.f.window_no"),
			"veto": "、".join(bloc_names) if not bloc_names.is_empty() else JwText.t("common.none")})
	var cost: String = JwText.render("pol.f.cost", {"one_off": JwFormat.u(int(pd["one_off_uu"])),
			"per_q": JwFormat.u(int(pd["per_quarter_uu"])), "n": JwFormat.quarters(int(pd["planned_quarters"])),
			"opex": JwFormat.u(int(pd["opex_per_q_uu"])), "toggle": JwFormat.u(int(pd["toggle_cost_uu"]))})
	var pre: PackedStringArray = PackedStringArray()
	for k: String in pd.get("preconditions", PackedStringArray()):
		var t: String = JwText.t("precond." + k)
		if t != "" and not pre.has(t):
			pre.append(t)
	var lag: String = JwText.render("pol.f.lag", {"enact": JwFormat.quarters(int(pd["lag_enact"])),
			"lo": JwFormat.quarters(int(pd["lag_min"])), "hi": JwFormat.quarters(int(pd["lag_max"]))})
	var ex: String = JwText.render("pol.f.exit", {"assets": JwText.t("exit.assets." + String(pd["exit_assets"])),
			"unfinished": JwText.t("exit.unfinished." + String(pd["exit_unfinished"])),
			"comp": JwText.t("exit.comp." + String(pd["exit_comp_rule"])), "pct": JwFormat.pct(int(pd["exit_comp_ppm"])),
			"cool": JwFormat.quarters(int(pd["cooldown_q"]))})
	var react_parts: PackedStringArray = PackedStringArray()
	var react: Dictionary = pd.get("reaction", {})
	for b2: int in cat.blocs.size():
		var bid: String = String(cat.blocs[b2]["id"])
		if react.has(bid):
			react_parts.append(cat.bloc_label(b2) + " " + JwFormat.ppt(int(react[bid])) + JwText.render("pol.f.stance_now",
					{"v": JwFormat.pct(m.at("state.bloc.stance_ppm", b2 * 12 + p))}))
	var fails: PackedStringArray = PackedStringArray()
	for f: String in pd.get("failure_paths", PackedStringArray()):
		var ft: String = JwText.t("fail." + f)
		fails.append(ft if ft != "" else f)
	var rows: Array = [
		["pol.f.problem", JwText.t("policy.problem.%s" % String(pd["code"]))],
		["pol.f.authority_t", authority],
		["pol.f.cost_t", cost],
		["pol.f.pre_t", "；".join(pre) if not pre.is_empty() else JwText.t("common.none")],
		["pol.f.lag_t", lag],
		["pol.f.target_t", JwText.t("policy.target.%s" % String(pd["code"]))],
		["pol.f.exit_t", ex],
		["pol.f.react_t", "；".join(react_parts)],
		["pol.f.fail_t", "、".join(fails)],
	]
	for i: int in rows.size():
		var r: Array = rows[i]
		var k: Label = JwUi.label(JwText.t(String(r[0])), "body_bold", "text.secondary")
		k.custom_minimum_size = Vector2(96, 0)
		grid.add_child(k)
		var val: Label = JwUi.label(String(r[1]), "body", "text.primary", true)
		val.custom_minimum_size = Vector2(360, 0)
		JwUi.tag(val, "Field%d" % i)
		grid.add_child(val)
	return root


func _params_and_actions(p: int, pd: Dictionary) -> PanelContainer:
	var m: JwReadModel = session.model
	var cat: JwCatalog = session.catalog
	var sec: Dictionary = JwUi.section(JwText.t("pol.section.params"))
	var body: VBoxContainer = sec["body"]
	var is_proj: bool = cat.is_project(p)
	if is_proj:
		body.add_child(_project_controls(p, pd))
	else:
		if not edit_params.has(p):
			edit_params[p] = m.policy_params(p) if m.policy_enabled(p) else _defaults(p)
		var params: Array = pd.get("params", [])
		for j: int in mini(params.size(), 4):
			body.add_child(_param_row(p, j, params[j]))
		if not (pd.get("funding", {}) as Dictionary).is_empty():
			body.add_child(_funding_row(p, pd))
		var actions: HBoxContainer = JwUi.hbox(10)
		if m.policy_enabled(p):
			var b1: Button = JwUi.button(JwText.t("pol.act.set_params"), "PrimaryButton")
			b1.name = "SetParamsButton"
			b1.pressed.connect(func() -> void:
				session.add_draft(session.draft_set_params(p, edit_params[p])))
			actions.add_child(b1)
			var b2: Button = JwUi.button(JwText.t("pol.act.repeal"))
			b2.name = "RepealButton"
			b2.pressed.connect(func() -> void: session.add_draft(session.draft_repeal(p)))
			actions.add_child(b2)
		else:
			var b3: Button = JwUi.button(JwText.t("pol.act.enact"), "PrimaryButton")
			b3.name = "EnactButton"
			b3.pressed.connect(func() -> void:
				session.add_draft(session.draft_enact(p, edit_params[p], _funding_code(p, pd))))
			actions.add_child(b3)
		var reset: Button = JwUi.button(JwText.t("pol.act.reset"))
		reset.pressed.connect(func() -> void:
			edit_params[p] = m.policy_params(p) if m.policy_enabled(p) else _defaults(p)
			refresh())
		actions.add_child(reset)
		body.add_child(actions)
		body.add_child(JwUi.para(JwText.t("pol.note.submit"), "text.muted"))
	return sec["root"]


func _defaults(p: int) -> PackedInt64Array:
	var out: PackedInt64Array = PackedInt64Array()
	for j: int in 4:
		out.append(session.model.param_default(p, j))
	return out


func _param_row(p: int, j: int, meta: Dictionary) -> HBoxContainer:
	var m: JwReadModel = session.model
	var h: HBoxContainer = JwUi.hbox(10)
	var key: String = String(meta.get("key", ""))
	var label: String = String(meta.get("label", ""))
	if label == "":
		label = JwText.t("param." + key)
	var lab: Label = JwUi.label(label, "body", "text.secondary", true)
	lab.custom_minimum_size = Vector2(220, 0)
	h.add_child(lab)
	var lo: int = m.param_min(p, j)
	var hi: int = m.param_max(p, j)
	var cur: PackedInt64Array = edit_params[p]
	var typ: String = String(meta.get("type", ""))
	if typ == "mask":
		h.add_child(_mask_editor(p, j, cur[j], int(meta.get("popcount_max", 0))))
	elif typ == "enum" or typ == "int_enum":
		var ob: OptionButton = OptionButton.new()
		var vals: Array = meta.get("values", [])
		for i: int in range(lo, hi + 1):
			var t: String = JwText.t("enum.%s.%d" % [key, i])
			if t == "" and i < vals.size():
				t = String(vals[i])
			ob.add_item(t, i)
		ob.select(clampi(cur[j] - lo, 0, maxi(hi - lo, 0)))
		ob.item_selected.connect(func(idx: int) -> void:
			var a: PackedInt64Array = edit_params[p]
			a[j] = lo + idx
			edit_params[p] = a)
		h.add_child(ob)
	else:
		var step: int = int(meta.get("step", 0))
		if step <= 0:
			step = _default_step(typ, lo, hi)
		h.add_child(_stepper(cur[j], lo, hi, step, typ, key, func(nv: int) -> void:
			var a2: PackedInt64Array = edit_params[p]
			a2[j] = nv
			edit_params[p] = a2
			refresh()))
	h.add_child(JwUi.label(JwText.render("pol.param.range", {"lo": _fmt_param(lo, typ, key), "hi": _fmt_param(hi, typ, key),
			"now": _fmt_param(m.policy_param(p, j), typ, key) if m.policy_enabled(p) else JwText.t("common.none")}),
			"caption", "text.muted", true))
	return h


static func _default_step(typ: String, lo: int, hi: int) -> int:
	match typ:
		"ppm":
			return 10000
		"uu":
			return 10_000_000
		"q", "int_q", "quarters":
			return 1
	@warning_ignore("integer_division")
	return maxi(1, (hi - lo) / 20)


func _fmt_param(v: int, typ: String, key: String) -> String:
	match typ:
		"ppm":
			return JwFormat.pct(v)
		"uu":
			return JwFormat.u(v)
		"q", "int_q", "quarters":
			return JwFormat.quarters(v)
		"mask":
			return _mask_text(v)
		"enum", "int_enum":
			var ek: String = "enum.%s.%d" % [key, v]
			return JwText.t(ek) if JwText.has(ek) else str(v)
	if key.contains("_uu"):
		return JwFormat.u(v)
	var unit: String = JwText.t("param.unit." + key) if JwText.has("param.unit." + key) else ""
	return JwFormat.group3(v) + ((" " + unit) if unit != "" else "")


func _mask_text(mask: int) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for r: int in JwReadModel.R:
		if (mask >> r) & 1 == 1:
			parts.append(session.catalog.region_label(r))
	return "、".join(parts) if not parts.is_empty() else JwText.t("common.none")


func _stepper(value: int, lo: int, hi: int, step: int, typ: String, key: String, on_change: Callable) -> HBoxContainer:
	var h: HBoxContainer = JwUi.hbox(4)
	var minus: Button = JwUi.button("−")
	minus.custom_minimum_size = Vector2(36, 32)
	var lab: Label = JwUi.label(_fmt_param(value, typ, key), "num_bold", "text.primary")
	lab.custom_minimum_size = Vector2(120, 0)
	lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var plus: Button = JwUi.button("+")
	plus.custom_minimum_size = Vector2(36, 32)
	minus.pressed.connect(func() -> void: on_change.call(clampi(value - step, lo, hi)))
	plus.pressed.connect(func() -> void: on_change.call(clampi(value + step, lo, hi)))
	h.add_child(minus)
	h.add_child(lab)
	h.add_child(plus)
	return h


func _mask_editor(p: int, j: int, mask: int, popmax: int) -> HBoxContainer:
	var h: HBoxContainer = JwUi.hbox(6)
	for r: int in JwReadModel.R:
		var cb: CheckBox = CheckBox.new()
		cb.text = session.catalog.region_label(r)
		cb.button_pressed = (mask >> r) & 1 == 1
		var rr: int = r
		cb.toggled.connect(func(on: bool) -> void:
			var a: PackedInt64Array = edit_params[p]
			var mm: int = a[j]
			if popmax == 1:
				mm = 0
			if on:
				mm = mm | (1 << rr)
			else:
				mm = mm & ~(1 << rr)
			a[j] = maxi(mm, 0)
			edit_params[p] = a
			refresh())
		h.add_child(cb)
	return h


func _funding_row(p: int, pd: Dictionary) -> HBoxContainer:
	var h: HBoxContainer = JwUi.hbox(10)
	var f: Dictionary = pd.get("funding", {})
	var lab: Label = JwUi.label(String(f.get("label", "")) if String(f.get("label", "")) != "" else JwText.t("param.funding_source"),
			"body", "text.secondary")
	lab.custom_minimum_size = Vector2(220, 0)
	h.add_child(lab)
	var ob: OptionButton = OptionButton.new()
	var vals: Array = f.get("values", [])
	for i: int in vals.size():
		ob.add_item(JwText.t("funding.name." + String(vals[i])), i)
	ob.select(clampi(int(funding_choice.get(p, 0)), 0, maxi(vals.size() - 1, 0)))
	ob.item_selected.connect(func(idx: int) -> void: funding_choice[p] = idx)
	h.add_child(ob)
	h.add_child(JwUi.label(JwText.t("pol.note.funding"), "caption", "text.muted", true))
	return h


## 资金来源：内容包 values 的名字 → 命令层 FundingSource 码（cash 0 / bond 1 / reallocation 2）。
func _funding_code(p: int, pd: Dictionary) -> int:
	var f: Dictionary = pd.get("funding", {})
	var vals: Array = f.get("values", [])
	var idx: int = int(funding_choice.get(p, 0))
	if idx < 0 or idx >= vals.size():
		return 0
	match String(vals[idx]):
		"bond":
			return 1
		"reallocation":
			return 2
	return 0


func _project_controls(p: int, pd: Dictionary) -> VBoxContainer:
	var m: JwReadModel = session.model
	var cat: JwCatalog = session.catalog
	var v: VBoxContainer = JwUi.vbox(8)
	if not launch_region.has(p):
		var dm: int = m.param_default(p, 0)
		var r0: int = 0
		for r: int in JwReadModel.R:
			if (dm >> r) & 1 == 1:
				r0 = r
				break
		launch_region[p] = r0
	if not launch_scale.has(p):
		launch_scale[p] = clampi(m.param_default(p, 1), 250000, JwReadModel.PPM)
	var reg: int = int(launch_region[p])
	var h1: HBoxContainer = JwUi.hbox(10)
	var l1: Label = JwUi.label(JwText.t("pol.launch.region"), "body", "text.secondary")
	l1.custom_minimum_size = Vector2(220, 0)
	h1.add_child(l1)
	var ob: OptionButton = OptionButton.new()
	for r2: int in JwReadModel.R:
		ob.add_item(JwText.render("pol.launch.region_item", {"region": cat.region_label(r2), "used": str(m.slots_used(r2)),
				"total": str(m.slots_total(r2))}), r2)
	ob.select(reg)
	ob.item_selected.connect(func(i: int) -> void:
		launch_region[p] = i
		refresh())
	h1.add_child(ob)
	v.add_child(h1)
	var lo: int = maxi(m.param_min(p, 1), 250000)
	var hi: int = mini(m.param_max(p, 1), JwReadModel.PPM)
	var h2: HBoxContainer = JwUi.hbox(10)
	var l2: Label = JwUi.label(JwText.t("pol.launch.scale"), "body", "text.secondary")
	l2.custom_minimum_size = Vector2(220, 0)
	h2.add_child(l2)
	h2.add_child(_stepper(int(launch_scale[p]), lo, hi, 250000, "ppm", "scale_ppm", func(nv: int) -> void:
		launch_scale[p] = nv
		refresh()))
	h2.add_child(JwUi.label(JwText.render("pol.launch.scale_note", {"hi": JwFormat.pct(hi)}), "caption", "text.muted", true))
	v.add_child(h2)
	if not (pd.get("funding", {}) as Dictionary).is_empty():
		v.add_child(_funding_row(p, pd))
	var scale: int = int(launch_scale[p])
	@warning_ignore("integer_division")
	var total: int = int(pd["one_off_uu"]) * scale / JwReadModel.PPM
	@warning_ignore("integer_division")
	var per: int = total / maxi(int(pd["planned_quarters"]), 1)
	v.add_child(JwUi.class_line(JwInfo.Cls.DERIVED, JwText.render("pol.launch.summary", {"total": JwFormat.u(total),
			"per": JwFormat.u(per), "n": JwFormat.quarters(int(pd["planned_quarters"])),
			"slot": JwText.render("dock.slot", {"region": cat.region_label(reg), "used": str(m.slots_used(reg)),
				"total": str(m.slots_total(reg))})})))
	var el: Dictionary = m.eligibility(p, true, reg)
	if int(el.get("code", 0)) != 0:
		var r: Dictionary = JwReasons.from_code(int(el["code"]), {"p": p, "region": reg, "draft": -1,
				"subject": String(pd["code"]), "subject_label": String(pd["label"])}, m, cat)
		v.add_child(JwReasonView.make(r, session, root_ui))
	var act: HBoxContainer = JwUi.hbox(10)
	var b: Button = JwUi.button(JwText.t("pol.act.launch"), "PrimaryButton")
	b.name = "LaunchButton"
	b.pressed.connect(func() -> void:
		session.add_draft(session.draft_launch(p, int(launch_region[p]), int(launch_scale[p]), _funding_code(p, pd))))
	act.add_child(b)
	v.add_child(act)
	v.add_child(JwUi.para(JwText.t("pol.note.launch_rules"), "text.muted"))
	# 本政策的在建与已完成项目（可取消）
	var rows: Array[Dictionary] = []
	for row: Dictionary in m.project_rows():
		if int(row["policy"]) == p:
			rows.append(row)
	if not rows.is_empty():
		v.add_child(JwUi.label(JwText.t("pol.projects.title"), "body_bold", "text.secondary"))
		for row2: Dictionary in rows:
			v.add_child(_project_row(row2))
	return v


func _project_row(row: Dictionary) -> VBoxContainer:
	var m: JwReadModel = session.model
	var cat: JwCatalog = session.catalog
	var v: VBoxContainer = JwUi.vbox(4)
	var h: HBoxContainer = JwUi.hbox(10)
	var name_t: String = JwText.render("project.name", {"policy": String(cat.policy(int(row["policy"])).get("label", "")),
			"region": cat.region_label(int(row["region"])), "n": str(int(row["p"]) + 1)})
	h.add_child(JwUi.label(name_t, "body", "text.primary"))
	h.add_child(JwUi.label(JwText.t("project_status.%d" % int(row["status"])), "caption", "text.secondary"))
	h.add_child(JwUi.label(JwText.render("pol.projects.paid", {"paid": JwFormat.u(int(row["paid"])),
			"total": JwFormat.u(int(row["total"]))}), "caption", "text.muted"))
	var st: int = int(row["status"])
	if st == JwReadModel.PS_IN_PROGRESS or st == JwReadModel.PS_SUSPENDED or st == JwReadModel.PS_PLANNED:
		var pj: int = int(row["p"])
		var b: Button = JwUi.button(JwText.t("pol.act.cancel"))
		b.pressed.connect(func() -> void:
			_cost_card_for = pj
			_defer_card_for = -1
			session.log_event("ev.cost_card_rendered", {"project_id": pj, "action": "cancel"})
			refresh())
		h.add_child(b)
		var bd: Button = JwUi.button(JwText.t("pol.act.defer"))
		bd.name = "DeferButton"
		bd.pressed.connect(func() -> void:
			_defer_card_for = pj
			_cost_card_for = -1
			session.log_event("ev.cost_card_rendered", {"project_id": pj, "action": "defer"})
			refresh())
		h.add_child(bd)
	v.add_child(h)
	if _cost_card_for == int(row["p"]):
		v.add_child(_cost_card(row, name_t))
	if _defer_card_for == int(row["p"]):
		v.add_child(_defer_card(row, name_t))
	return v


## 成本卡（docs/20 §7.5.3）：四项分列，渲染之后才允许把撤回放进草案（AC-18c）。
func _cost_card(row: Dictionary, name_t: String) -> PanelContainer:
	var m: JwReadModel = session.model
	var wc: Dictionary = m.withdraw_cost(row)
	var p: PanelContainer = JwUi.panel_style(JwTheme.box_left_rule("bg.raised", "ochre.core", 3, 12))
	JwUi.tag(p, "CostCard")
	var v: VBoxContainer = JwUi.vbox(4)
	p.add_child(v)
	v.add_child(JwUi.label(JwText.t("cost.title"), "body_bold"))
	v.add_child(JwUi.class_line(JwInfo.Cls.DERIVED, JwText.render("tpl.derived.withdraw_cost", {"project_name": name_t,
			"sunk_u": JwFormat.u(int(wc["sunk"])), "residual_u": JwFormat.u(int(wc["residual"])),
			"penalty_u": JwFormat.u(int(wc["penalty"])), "rule_id": "^R-PROJ-CANCEL",
			"citations": JwFormat.citation(JwText.t("ledger.alias.project"), maxi(m.q - 1, -1), int(row["p"]) + 1)})))
	v.add_child(JwUi.label(JwText.render("cost.remaining", {"amount": JwFormat.u(int(wc["remaining_commit"]))}), "body", "text.secondary"))
	var h: HBoxContainer = JwUi.hbox(10)
	var ok: Button = JwUi.button(JwText.t("cost.confirm_cancel"), "AlertButton")
	var pj: int = int(row["p"])
	ok.pressed.connect(func() -> void:
		_cost_card_for = -1
		session.add_draft(session.draft_cancel(pj, name_t)))
	h.add_child(ok)
	var no: Button = JwUi.button(JwText.t("common.cancel"))
	no.pressed.connect(func() -> void:
		_cost_card_for = -1
		refresh())
	h.add_child(no)
	v.add_child(h)
	return p


## 延期成本卡（R-DEFER-01）：1 / 2 / 4 季三档各列赔偿与复工季，渲染后才可放进草案（AC-18c 同口径）。
func _defer_card(row: Dictionary, name_t: String) -> PanelContainer:
	var m: JwReadModel = session.model
	var pj: int = int(row["p"])
	var p: PanelContainer = JwUi.panel_style(JwTheme.box_left_rule("bg.raised", "ochre.core", 3, 12))
	JwUi.tag(p, "DeferCard")
	var v: VBoxContainer = JwUi.vbox(4)
	p.add_child(v)
	var base: Dictionary = m.defer_cost(row, 1)
	v.add_child(JwUi.label(JwText.t("defer.card_title"), "body_bold"))
	v.add_child(JwUi.para(JwText.render("defer.rule", {"rate": JwFormat.pct(m.rule("param.defer_fee_ppm_per_q", 0))}),
			"text.secondary"))
	v.add_child(JwUi.label(JwText.render("defer.left.line", {"count": str(int(base["count_left"])),
			"quarters": JwFormat.quarters(int(base["q_left"])),
			"remaining": JwFormat.u(int(base["remaining_commit"]))}), "body", "text.secondary"))
	var any_ok: bool = false
	for n: int in [1, 2, 4]:
		var dc: Dictionary = m.defer_cost(row, n)
		if not bool(dc["allowed"]):
			continue
		any_ok = true
		var h: HBoxContainer = JwUi.hbox(10)
		h.add_child(JwUi.label(JwText.render("defer.option", {"n": JwFormat.quarters(n),
				"fee": JwFormat.u(int(dc["fee"])), "resume": JwFormat.quarter(int(dc["resume_q"]))}),
				"body", "text.primary"))
		var ok: Button = JwUi.button(JwText.t("defer.confirm"), "AlertButton")
		var nn: int = n
		ok.pressed.connect(func() -> void:
			_defer_card_for = -1
			session.add_draft(session.draft_project_defer(pj, nn, name_t)))
		h.add_child(ok)
		v.add_child(h)
	if not any_ok:
		var r: Dictionary = JwReasons.from_code(JwReadModel.RJ_PRECONDITION, {"kind": 6, "p": -1, "draft": -1,
				"project": pj, "subject": "project", "subject_label": name_t}, m, session.catalog)
		v.add_child(JwReasonView.make(r, session, root_ui, true))
	var no: Button = JwUi.button(JwText.t("common.cancel"))
	no.pressed.connect(func() -> void:
		_defer_card_for = -1
		refresh())
	v.add_child(no)
	return p


# ── 影响预览（环节 04 的一半） ─────────────────────────────────────────────

func _impact(p: int, pd: Dictionary) -> PanelContainer:
	var m: JwReadModel = session.model
	var cat: JwCatalog = session.catalog
	var sec: Dictionary = JwUi.section(JwText.t("pol.section.impact"))
	var root: PanelContainer = sec["root"]
	JwUi.tag(root, "ImpactPreview")
	var cols: HBoxContainer = JwUi.hbox(16)
	(sec["body"] as VBoxContainer).add_child(cols)
	# 左栏：算 确定性后果
	var left: VBoxContainer = JwUi.vbox(6)
	JwUi.tag(left, "Left")
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_child(JwUi.label(JwText.t("pol.impact.left"), "body_bold", "text.secondary"))
	var q: int = m.q
	var is_proj: bool = cat.is_project(p)
	var scale: int = int(launch_scale.get(p, JwReadModel.PPM)) if is_proj else JwReadModel.PPM
	@warning_ignore("integer_division")
	var total: int = int(pd["one_off_uu"]) * scale / JwReadModel.PPM
	var pq: int = maxi(int(pd["planned_quarters"]), 1)
	@warning_ignore("integer_division")
	var per: int = total / pq
	@warning_ignore("integer_division")
	var opex: int = int(pd["opex_per_q_uu"]) * scale / JwReadModel.PPM
	left.add_child(JwUi.class_line(JwInfo.Cls.DERIVED, JwText.render("pol.impact.cash", {"q_from": JwFormat.quarter(q),
			"q_to": JwFormat.quarter(q + pq - 1), "per": JwFormat.u(per), "total": JwFormat.u(total)})))
	left.add_child(JwUi.class_line(JwInfo.Cls.DERIVED, JwText.render("pol.impact.opex", {
			"q": JwFormat.quarter(q + (pq + int(pd["commission_delay"]) - 1 if is_proj else 1)), "opex": JwFormat.u(opex)})))
	if not is_proj:
		left.add_child(JwUi.class_line(JwInfo.Cls.DERIVED, JwText.render("pol.impact.toggle", {
				"toggle": JwFormat.u(int(pd["toggle_cost_uu"])), "cool": JwFormat.quarters(int(pd["cooldown_q"]))})))
	left.add_child(JwUi.class_line(JwInfo.Cls.DERIVED, JwText.render("tpl.derived.lag_range", {"policy_name": String(pd["label"]),
			"lag_range": JwText.render("pol.impact.lag_range", {"lo": JwFormat.quarter(q + int(pd["lag_min"])),
				"hi": JwFormat.quarter(q + int(pd["lag_max"]))}), "rule_id": "^R-LAG-" + String(pd["code"])})))
	left.add_child(JwUi.para(JwText.t("pol.impact.left_assume"), "text.muted"))
	cols.add_child(left)
	# 右栏：预 情景（基线 / 不利条件）
	var right: VBoxContainer = JwUi.vbox(6)
	JwUi.tag(right, "Right")
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_child(JwUi.label(JwText.t("pol.impact.right"), "body_bold", "text.secondary"))
	var in_draft: bool = _in_draft(p)
	if not in_draft:
		right.add_child(JwUi.para(JwText.t("pol.impact.need_draft"), "text.secondary"))
	elif not session.dry_is_current():
		right.add_child(JwUi.label(JwText.t("common.recalc"), "body", "warm.text"))
	else:
		var n_q: int = int(cat.cfg("preview_quarters", 4))
		var hq: int = q + n_q - 1
		var bb: Array[Dictionary] = session.band("draft_lo", "draft_hi", "cash_end")
		var ba: Array[Dictionary] = session.band("adv_lo", "adv_hi", "cash_end")
		if not bb.is_empty() and not ba.is_empty():
			var t: int = mini(bb.size(), ba.size()) - 1
			right.add_child(JwUi.class_line(JwInfo.Cls.PROJECTED, JwText.render("tpl.projected.two_column", {
				"range_base": JwFormat.range_u(int(bb[t]["lo"]), int(bb[t]["hi"])),
				"range_adverse": JwFormat.range_u(int(ba[t]["lo"]), int(ba[t]["hi"])),
				"horizon_quarter": JwFormat.quarter(q + t), "assumption_count": "2"})))
		var ub: Array[Dictionary] = session.band("draft_lo", "draft_hi", "unemployment_ppm")
		if not ub.is_empty():
			var t2: int = ub.size() - 1
			right.add_child(JwUi.class_line(JwInfo.Cls.PROJECTED, JwText.render("tpl.projected.unemployment", {
				"scenario": JwText.t("scen.base"), "horizon_quarter": JwFormat.quarter(q + t2),
				"range_pct": JwFormat.range_pct(int(ub[t2]["lo"]), int(ub[t2]["hi"])), "assumption_count": "2"})))
		right.add_child(_group_breakdown(hq))
	right.add_child(JwUi.para(JwText.t("pol.impact.hidden_shocks"), "text.muted"))
	cols.add_child(right)
	return root


func _group_breakdown(hq: int) -> VBoxContainer:
	var v: VBoxContainer = JwUi.vbox(4)
	JwUi.tag(v, "GroupBreakdown")
	v.set_meta("info_class", JwInfo.Cls.PROJECTED)
	var gi: Dictionary = session.group_impact()
	v.add_child(JwUi.label(JwText.t("pol.impact.groups"), "body_bold", "text.secondary"))
	if not bool(gi.get("ready", false)):
		v.add_child(JwUi.label(JwText.t("common.recalc"), "body", "warm.text"))
		return v
	var h: HBoxContainer = JwUi.hbox(16)
	var gv: VBoxContainer = JwUi.vbox(2)
	gv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gv.add_child(JwUi.label(JwText.t("pol.impact.gainers"), "body_bold", "teal.core"))
	for r: Variant in gi["gainers"]:
		gv.add_child(_group_line(r, hq))
	if (gi["gainers"] as Array).is_empty():
		gv.add_child(JwUi.label(JwText.t("pol.impact.none"), "caption", "text.muted"))
	var lv: VBoxContainer = JwUi.vbox(2)
	lv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lv.add_child(JwUi.label(JwText.t("pol.impact.losers"), "body_bold", "ochre.core"))
	for r2: Variant in gi["losers"]:
		lv.add_child(_group_line(r2, hq))
	if (gi["losers"] as Array).is_empty():
		lv.add_child(JwUi.label(JwText.t("pol.impact.none"), "caption", "text.muted"))
	h.add_child(gv)
	h.add_child(lv)
	v.add_child(h)
	v.add_child(JwUi.para(JwText.t("pol.impact.not_additive"), "text.muted"))
	var expand: Button = JwUi.link(JwText.t("pol.impact.more"))
	expand.pressed.connect(func() -> void:
		note_expand("PolicyEditor/ImpactPreview/GroupBreakdown")
		goto_page("society", {"source": "draft"}))
	v.add_child(expand)
	return v


func _group_line(r: Variant, hq: int) -> HBoxContainer:
	var d: Dictionary = r
	return JwUi.class_line(JwInfo.Cls.PROJECTED, JwText.render("pol.impact.group_line", {
		"group": session.group_label(int(d["g"])), "range": JwFormat.range_index(int(d["lo"]), int(d["hi"])),
		"q": JwFormat.quarter(hq), "scenario": JwText.t("scen.base.short")}))


# ── 草案篮与右栏 ─────────────────────────────────────────────────────────

func _tray() -> VBoxContainer:
	var m: JwReadModel = session.model
	var v: VBoxContainer = JwUi.vbox(12)
	JwUi.tag(v, "DraftTray")
	var sec: Dictionary = JwUi.section(JwText.render("pol.tray.title", {"n": str(session.drafts.size())}))
	var body: VBoxContainer = sec["body"]
	var verdicts: Array[Dictionary] = session.draft_verdicts()
	if session.drafts.is_empty():
		body.add_child(JwUi.para(JwText.t("pol.tray.empty"), "text.muted"))
	for i: int in session.drafts.size():
		var d: Dictionary = session.drafts[i]
		var row: HBoxContainer = JwUi.hbox(6)
		var code: int = int(verdicts[i]["code"]) if i < verdicts.size() else 0
		if code == 0:
			row.add_child(JwIcon.make("ok", JwTheme.c("teal.core"), 14))
		else:
			row.add_child(JwIcon.make("block", JwTheme.c("ochre.hot"), 14))
		row.add_child(JwUi.label("%d. " % (i + 1) + String(d.get("label", "")), "body", "text.primary", true))
		var rm: Button = JwUi.button(JwText.t("pol.tray.remove"))
		var ii: int = i
		rm.pressed.connect(func() -> void: session.remove_draft(ii))
		row.add_child(rm)
		body.add_child(row)
		var src: String = String(verdicts[i]["source"]) if i < verdicts.size() else "mirror"
		body.add_child(JwUi.label(JwText.t("pol.tray.verdict.ok." + src) if code == 0 else
				JwText.t("pol.tray.verdict.block." + src), "caption", "text.muted", true))
	var com: Dictionary = session.draft_commitments()
	var totals: VBoxContainer = JwUi.vbox(2)
	JwUi.tag(totals, "Totals")
	totals.add_child(JwUi.class_line(JwInfo.Cls.DERIVED, JwText.render("pol.tray.first_q", {"amount": JwFormat.u(int(com["first_q"]))})))
	totals.add_child(JwUi.class_line(JwInfo.Cls.DERIVED, JwText.render("pol.tray.commit", {"amount": JwFormat.u(int(com["cumulative"]))})))
	body.add_child(totals)
	var hb: HBoxContainer = JwUi.hbox(8)
	var br: Button = JwUi.button(JwText.t("pol.tray.review"), "PrimaryButton")
	br.pressed.connect(func() -> void: open_overlay("budget", {}))
	hb.add_child(br)
	if not session.drafts.is_empty():
		var cl: Button = JwUi.button(JwText.t("pol.tray.clear"))
		cl.pressed.connect(func() -> void: session.clear_drafts())
		hb.add_child(cl)
	body.add_child(hb)
	if not session.deferred.is_empty():
		body.add_child(JwUi.label(JwText.render("pol.tray.deferred", {"n": str(session.deferred.size())}), "body_bold", "text.secondary"))
		for j: int in session.deferred.size():
			var dd: Dictionary = session.deferred[j]
			var r2: HBoxContainer = JwUi.hbox(6)
			r2.add_child(JwUi.label(JwText.render("pol.tray.deferred_item", {"label": String(dd.get("label", "")),
					"q": JwFormat.quarter(int(dd.get("deferred_to_q", m.q)))}), "caption", "text.secondary", true))
			var back: Button = JwUi.button(JwText.t("pol.tray.restore"))
			var jj: int = j
			back.pressed.connect(func() -> void: session.restore_deferred(jj))
			r2.add_child(back)
			body.add_child(r2)
	v.add_child(sec["root"])
	v.add_child(_standing())
	v.add_child(_bond_panel())
	return v


## 常设安排披露（docs/22 §4.4 SO-1）：列出由结算规则自动执行的维护性支出，并说明玩家自定义常设指令的现状。
func _standing() -> PanelContainer:
	var sec: Dictionary = JwUi.section(JwText.t("pol.standing.title"))
	var root: PanelContainer = sec["root"]
	JwUi.tag(root, "StandingOrders")
	var body: VBoxContainer = sec["body"]
	for k: String in ["opex", "debt", "unemployment", "restock"]:
		body.add_child(JwUi.class_line(JwInfo.Cls.DERIVED, JwText.t("pol.standing." + k)))
	body.add_child(JwUi.para(JwText.t("pol.standing.custom"), "text.muted"))
	return root


func _bond_panel() -> PanelContainer:
	var m: JwReadModel = session.model
	var sec: Dictionary = JwUi.section(JwText.t("pol.bond.title"))
	var root: PanelContainer = sec["root"]
	JwUi.tag(root, "BondPanel")
	var body: VBoxContainer = sec["body"]
	body.add_child(_stepper(bond_amount, 100_000_000, 20_000_000_000, 250_000_000, "uu", "bond_amount",
			func(nv: int) -> void:
				bond_amount = nv
				refresh()))
	body.add_child(_stepper(bond_tenor, 4, 40, 1, "q", "bond_tenor", func(nv: int) -> void:
		bond_tenor = nv
		refresh()))
	var ob: OptionButton = OptionButton.new()
	ob.add_item(JwText.t("holder.0"), 0)
	ob.add_item(JwText.t("holder.1"), 1)
	ob.select(bond_holder)
	ob.item_selected.connect(func(i: int) -> void: bond_holder = i)
	body.add_child(ob)
	body.add_child(JwUi.class_line(JwInfo.Cls.ACTUAL, JwText.render("pol.bond.capacity", {"pool": JwFormat.u(m.invpool_cash()),
			"ext": JwFormat.u(m.credit_left()), "rate": JwFormat.pct(m.sc("state.world.sovereign_rate_ppm_per_q"))})))
	var b: Button = JwUi.button(JwText.t("pol.bond.add"), "PrimaryButton")
	b.pressed.connect(func() -> void: session.add_draft(session.draft_bond(bond_amount, bond_tenor, bond_holder)))
	body.add_child(b)
	body.add_child(JwUi.para(JwText.t("pol.bond.note"), "text.muted"))
	return root


func get_required_above_fold(band: int) -> Array[StringName]:
	if band == JwScale.HBand.SHORT:
		return [&"CatalogSummary", &"CatalogGroupBlocked", &"CatalogGroupGap", &"Headline", &"Totals"]
	return [&"CatalogSummary", &"CatalogGroupBlocked", &"CatalogGroupGap", &"CatalogGroupOk", &"Fields",
			&"ImpactPreview", &"DraftTray", &"Totals"]
