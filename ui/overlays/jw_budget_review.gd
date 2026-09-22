## 预算审查（docs/20 §8.3）：A1 四季现金预测、A2 情景对照、B 新增长期承诺、C 原因清单。
## A、B 两块不可折叠；BLOCK 与 GAP 永不折叠；缺口通过原因卡上的出口绑定处理路径（§8.5）。
class_name JwBudgetReview
extends JwOverlay


func _init() -> void:
	width_ratio = 0.9
	height_ratio = 0.9


func build() -> void:
	_fill()


func _fill() -> void:
	JwUi.clear(body)
	var m: JwReadModel = session.model
	set_title(JwText.render("br.title", {"quarter": JwFormat.quarter(m.q)}))
	var st: HBoxContainer = JwUi.hbox(8)
	if session.dry_busy() or not session.dry_is_current():
		st.add_child(JwIcon.make("loading", JwTheme.c("warm.text"), 14))
		st.add_child(JwUi.label(JwText.t("br.status.busy"), "body", "warm.text"))
	else:
		st.add_child(JwIcon.make("ok", JwTheme.c("teal.core"), 14))
		st.add_child(JwUi.label(JwText.render("br.status.done", {"ms": str(int(session.dry.get("ms", 0))),
				"runs": str((session.dry.get("runs", {}) as Dictionary).size())}), "body", "text.secondary"))
	body.add_child(st)
	var reasons: Control = JwFiscalTables.reason_list(session, root_ui, true)
	if String(ctx.get("focus", "")) == "first_reason":
		body.add_child(reasons)
	body.add_child(JwFiscalTables.a1(session))
	body.add_child(JwFiscalTables.a2(session))
	body.add_child(JwFiscalTables.b_table(session))
	if String(ctx.get("focus", "")) != "first_reason":
		body.add_child(reasons)
	var h: HBoxContainer = JwUi.hbox(12)
	var adv: Button = JwUi.button(JwText.t("br.to_confirm"), "PrimaryButton")
	adv.pressed.connect(func() -> void:
		close()
		if root_ui != null:
			root_ui.call("open_overlay", "confirm", {}))
	h.add_child(adv)
	var rec: Button = JwUi.button(JwText.t("br.recompute"))
	rec.pressed.connect(func() -> void: session.request_dryrun(true))
	h.add_child(rec)
	body.add_child(h)


func on_dryrun() -> void:
	_fill()


func on_state_refresh() -> void:
	_fill()
