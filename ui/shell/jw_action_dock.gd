## 底部固定区（docs/20 §8.1）：政策草案 → 预算审查 → 推进季度，五页共用，永不隐藏。
##
## 承诺摘要三行常驻：预 四季最窄余量（含本季草案，区间）/ 算 新增长期承诺累计 / 实 施工槽位占用。
## 推进按钮的文案与行为由 JwSession.dock_state() 决定（§6.2），任何状态下都不做无原因的置灰：
## BLOCKED 态按钮可点，点击 = 打开预算审查并定位到第一条阻断原因。
class_name JwActionDock
extends PanelContainer

var session: JwSession = null
var root_ui: Node = null
var _stage1: VBoxContainer = null
var _stage2: VBoxContainer = null
var _summary: VBoxContainer = null
var _advance: Button = null
var _status: Label = null
var _style_ok: StyleBoxFlat = null
var _style_alert: StyleBoxFlat = null
var compact: bool = false
var wband: int = JwScale.WBand.WIDE
var _right: VBoxContainer = null


func setup(s: JwSession, r: Node) -> void:
	session = s
	root_ui = r
	name = "ActionDock"
	set_meta("jw_id", "ActionDock")
	_style_ok = JwTheme.box4("bg.panel", "", 0, 16, 8, 16, 8)
	_style_ok.border_color = JwTheme.c("line.strong")
	_style_ok.border_width_top = 1
	_style_alert = JwTheme.box4("bg.panel", "", 0, 16, 8, 16, 8)
	_style_alert.border_color = JwTheme.c("ochre.core")
	_style_alert.border_width_left = 3
	_style_alert.border_width_top = 1
	add_theme_stylebox_override("panel", _style_ok)
	var h: HBoxContainer = JwUi.hbox(20)
	add_child(h)
	_stage1 = JwUi.vbox(2)
	_stage1.custom_minimum_size = Vector2(210, 0)
	h.add_child(_stage1)
	h.add_child(VSeparator.new())
	_stage2 = JwUi.vbox(2)
	_stage2.custom_minimum_size = Vector2(250, 0)
	h.add_child(_stage2)
	h.add_child(VSeparator.new())
	_summary = JwUi.vbox(0)
	_summary.name = "CommitSummary"
	_summary.set_meta("jw_id", "CommitSummary")
	_summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_summary.custom_minimum_size = Vector2(260, 0)
	h.add_child(_summary)
	var right: VBoxContainer = JwUi.vbox(4)
	_right = right
	right.custom_minimum_size = Vector2(300, 0)
	right.alignment = BoxContainer.ALIGNMENT_CENTER
	_advance = JwUi.button("", "PrimaryButton")
	_advance.name = "AdvanceButton"
	_advance.set_meta("jw_id", "AdvanceButton")
	_advance.custom_minimum_size = Vector2(280, 40)
	_advance.pressed.connect(_on_advance)
	right.add_child(_advance)
	_status = JwUi.label("", "caption", "text.secondary", true)
	# 换行标签给出最小宽度：外壳首帧宽度为 0 时不至于逐字换行、把底部固定区的最小高度撑到上千（Godot 容器不回缩）。
	_status.custom_minimum_size = Vector2(200, 0)
	_status.name = "DockStatus"
	right.add_child(_status)
	h.add_child(right)


## 宽度档：W-mid 档收窄三段的最小宽度，摘要行允许换行（不再撑宽整个外壳）。
func set_width_band(wb: int) -> void:
	var changed: bool = wb != wband
	wband = wb
	var mid: bool = wb != JwScale.WBand.WIDE
	_stage1.custom_minimum_size = Vector2(150 if mid else 210, 0)
	_stage2.custom_minimum_size = Vector2(200 if mid else 250, 0)
	_right.custom_minimum_size = Vector2(230 if mid else 300, 0)
	_advance.custom_minimum_size = Vector2(220 if mid else 280, 40)
	if changed and session != null and session.game != null:
		refresh()


func set_compact(v: bool) -> void:
	compact = v
	custom_minimum_size = Vector2(0, JwScale.DOCK_H_SHORT if v else JwScale.DOCK_H_TALL)


func refresh() -> void:
	if session == null or session.game == null:
		_advance.text = JwText.t("dock.no_game")
		return
	var m: JwReadModel = session.model
	var st: int = session.dock_state()
	var rs: Array = session.reasons()
	var c: Dictionary = JwReasons.counts(rs)
	# ① 政策草案
	JwUi.clear(_stage1)
	_stage1.add_child(JwUi.label(JwText.t("dock.stage1"), "caption", "text.muted"))
	_stage1.add_child(JwUi.label(JwText.render("dock.drafts", {"n": str(session.drafts.size()),
			"d": str(session.deferred.size())}), "body_bold", "text.primary"))
	var l1: Button = JwUi.link(JwText.t("dock.open_drafts"))
	l1.pressed.connect(func() -> void: _goto("policy"))
	_stage1.add_child(l1)
	# ② 预算审查
	JwUi.clear(_stage2)
	_stage2.add_child(JwUi.label(JwText.t("dock.stage2"), "caption", "text.muted"))
	var com: Dictionary = session.draft_commitments()
	_stage2.add_child(JwUi.label(JwText.render("dock.first_q", {"amount": JwFormat.u(int(com["first_q"]))}),
			"body_bold", "text.primary"))
	var cnt: HBoxContainer = JwUi.hbox(10)
	cnt.add_child(_count_badge(JwInfo.Sev.BLOCK, int(c["block"])))
	cnt.add_child(_count_badge(JwInfo.Sev.GAP, int(c["gap"])))
	cnt.add_child(_count_badge(JwInfo.Sev.NOTE, int(c["note"])))
	var l2: Button = JwUi.link(JwText.t("dock.open_review"))
	l2.pressed.connect(func() -> void: _open("budget", {}))
	if wband == JwScale.WBand.WIDE:
		cnt.add_child(l2)
		_stage2.add_child(cnt)
	else:
		# W-mid / 降级档：链接另起一行，避免三段计数把摘要区挤到只剩一字宽。
		_stage2.add_child(cnt)
		_stage2.add_child(l2)
	# 承诺摘要三行
	_build_summary(m, com)
	# ③ 推进按钮
	_advance.theme_type_variation = "PrimaryButton"
	match st:
		JwSession.Dock.IDLE, JwSession.Dock.DRAFT:
			_advance.text = JwText.t("dock.btn.advance")
		JwSession.Dock.WARN:
			_advance.text = JwText.render("dock.btn.warn", {"n": str(int(c["note"]))})
		JwSession.Dock.GAP_UNBOUND:
			_advance.text = JwText.t("dock.btn.gap_unbound")
			_advance.theme_type_variation = "AlertButton"
		JwSession.Dock.GAP_BOUND:
			_advance.text = JwText.t("dock.btn.gap_bound")
		JwSession.Dock.GAP_NOEXIT:
			_advance.text = JwText.t("dock.btn.gap_noexit")
			_advance.theme_type_variation = "AlertButton"
		JwSession.Dock.BLOCKED:
			var first: String = ""
			for r: Variant in rs:
				if int((r as Dictionary).get("severity", 0)) == JwInfo.Sev.BLOCK:
					first = JwText.t("reason.cat." + String((r as Dictionary).get("code", "")))
					break
			_advance.text = JwText.render("dock.btn.blocked", {"n": str(int(c["block"])), "first": first})
			_advance.theme_type_variation = "AlertButton"
		JwSession.Dock.SETTLING:
			_advance.text = JwText.t("dock.btn.settling")
		JwSession.Dock.SETTLED:
			_advance.text = JwText.t("dock.btn.settled")
	if m.terminated:
		_advance.text = JwText.t("dock.btn.ended")
		_advance.theme_type_variation = "PrimaryButton"
	_advance.set_meta("dock_state", st)
	_resort_later()
	var stat: String = JwText.t("dock.status.ended") if m.terminated else JwText.t("dock.status.%d" % st)
	if session.dry_busy():
		stat += JwText.t("dock.status.recalc")
	_status.text = stat


## 自动换行标签的最小高度随宽度变化，但变矮时 Godot 容器不会自动回缩：重建内容后下一帧让外壳重排一次。
var _resort_pending: bool = false


func _resort_later() -> void:
	if _resort_pending or not is_inside_tree():
		return
	_resort_pending = true
	await get_tree().process_frame
	_resort_pending = false
	update_minimum_size()
	var parent: Container = get_parent() as Container
	if parent != null:
		parent.queue_sort()


func _count_badge(sev: int, n: int) -> HBoxContainer:
	var tok: String = JwInfo.sev_color_token(sev) if n > 0 else "text.muted"
	var b: HBoxContainer = JwUi.hbox(4)
	b.set_meta("severity", sev)
	b.set_meta("icon_id", JwInfo.sev_icon(sev))
	b.set_meta("color_token", tok)
	b.add_child(JwIcon.make(JwInfo.sev_icon(sev), JwTheme.c(tok), 14))
	var t: String = JwText.render("dock.count", {"name": JwInfo.sev_name(sev), "n": str(n)})
	b.set_meta("risk_text", t)
	b.add_child(JwUi.label(t, "body", tok))
	return b


func _build_summary(m: JwReadModel, com: Dictionary) -> void:
	JwUi.clear(_summary)
	var alert: bool = false
	# 行 1：预 四季最窄余量（含本季草案）
	var row1: HBoxContainer = JwUi.hbox(8)
	row1.name = "HeadroomWithDraft"
	row1.set_meta("jw_id", "HeadroomWithDraft")
	row1.add_child(JwUi.badge(JwInfo.Cls.PROJECTED))
	var hr: Dictionary = session.headroom_with_draft()
	var txt1: String = ""
	if hr.is_empty():
		txt1 = JwText.t("dock.headroom.pending")
	else:
		txt1 = JwText.render("dock.headroom" if wband == JwScale.WBand.WIDE else "dock.headroom.short",
				{"range": JwFormat.range_u(int(hr["lo"]), int(hr["hi"])),
				"q": JwFormat.quarter(int(hr["q"])), "scen": JwText.t("scen.base.short")})
		if int(hr["lo"]) < int(session.catalog.cfg("cash_floor_uu", 0)):
			alert = true
	var l1: Label = JwUi.label(txt1, "dense", "text.primary", true)
	l1.custom_minimum_size = Vector2(180, 0)
	l1.set_meta("label_text", txt1)
	row1.add_child(l1)
	row1.set_meta("label_text", txt1)
	if alert:
		row1.add_child(JwIcon.make("warn", JwTheme.c("ochre.core"), 14))
		row1.add_child(JwUi.label(JwText.render("dock.headroom.alert", {"q": JwFormat.quarter(int(hr["q"]))}),
				"body_bold", "ochre.core"))
	if session.dry_busy():
		row1.add_child(JwUi.label(JwText.t("common.recalc"), "caption", "warm.text"))
	var lk1: Button = JwUi.link(JwText.t("dock.link.cash"))
	lk1.pressed.connect(func() -> void: _open_ledger("cash"))
	row1.add_child(lk1)
	_summary.add_child(row1)
	# 行 2：算 新增长期承诺累计
	var row2: HBoxContainer = JwUi.hbox(8)
	row2.add_child(JwUi.badge(JwInfo.Cls.DERIVED))
	var l2c: Label = JwUi.label(JwText.render("dock.commit", {"amount": JwFormat.u(int(com["cumulative"]))}),
			"dense", "text.primary", true)
	l2c.custom_minimum_size = Vector2(180, 0)
	row2.add_child(l2c)
	var lk2: Button = JwUi.link(JwText.t("dock.link.commit"))
	lk2.pressed.connect(func() -> void: _open_ledger("commit"))
	row2.add_child(lk2)
	_summary.add_child(row2)
	# 行 3：实 施工槽位占用
	var row3: HBoxContainer = JwUi.hbox(8)
	row3.add_child(JwUi.badge(JwInfo.Cls.ACTUAL))
	var parts: PackedStringArray = PackedStringArray()
	for r: int in JwReadModel.R:
		parts.append(JwText.render("dock.slot", {"region": session.catalog.region_label(r),
				"used": str(m.slots_used(r)), "total": str(m.slots_total(r))}))
	var l3q: Label = JwUi.label(JwText.render("dock.queue" if wband == JwScale.WBand.WIDE else "dock.queue.short",
			{"list": " · ".join(parts)}), "dense", "text.primary", true)
	l3q.custom_minimum_size = Vector2(180, 0)
	row3.add_child(l3q)
	var lk3: Button = JwUi.link(JwText.t("dock.link.project"))
	lk3.pressed.connect(func() -> void: _open_ledger("project"))
	row3.add_child(lk3)
	_summary.add_child(row3)
	add_theme_stylebox_override("panel", _style_alert if alert else _style_ok)
	set_meta("alert", alert)


func _on_advance() -> void:
	if session == null or session.game == null:
		_open("newgame", {})
		return
	if session.model.terminated:
		_open("archive", {})
		return
	var st: int = session.dock_state()
	match st:
		JwSession.Dock.BLOCKED, JwSession.Dock.GAP_UNBOUND:
			_open("budget", {"focus": "first_reason"})
		JwSession.Dock.SETTLING:
			pass
		JwSession.Dock.SETTLED:
			session.clear_settled_flag()
			_goto("report")
			refresh()
		_:
			_open("confirm", {})


func _open(o: String, ctx: Dictionary) -> void:
	if root_ui != null and root_ui.has_method("open_overlay"):
		root_ui.call("open_overlay", o, ctx)


func _open_ledger(l: String) -> void:
	if root_ui != null and root_ui.has_method("open_ledger"):
		root_ui.call("open_ledger", l, 0)


func _goto(p: String) -> void:
	if root_ui != null and root_ui.has_method("show_page"):
		root_ui.call("show_page", p, {})
