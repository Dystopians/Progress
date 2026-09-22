## 结算回放（docs/20 §5.5 TH-2；§14 削减后的三段形态）：结算已在 SimCore 一次跑完，
## 界面回放「审核与融资 / 生产与交易 / 财税与社会」三段，然后逐张展示中断卡（被拒命令、新增欠付、
## 预算审查与选举、执政结束）。回放不可回退。
class_name JwSettlementReplay
extends JwOverlay

var _steps: Array[Label] = []
var _t: float = 0.0
var _stage: int = 0
var _cards: VBoxContainer = null
var _done: bool = false


func _init() -> void:
	modal = true
	width_ratio = 0.7
	height_ratio = 0.8


func build() -> void:
	var q: int = int(ctx.get("q", session.model.q - 1))
	set_title(JwText.render("sr.title", {"quarter": JwFormat.quarter(q)}))
	if not bool(ctx.get("ok", true)):
		body.add_child(JwUi.class_line(JwInfo.Cls.ACTUAL, JwText.render("sr.fault", {"code": str(int(ctx.get("code", 0))),
				"dir": String(ctx.get("fault_dir", ""))}), false, "ochre.hot"))
	# R-CLOCK-01：批量推进的汇总（推进了几季、为什么停下）。回放本身只演示最后一季。
	if ctx.has("batch"):
		var b: Dictionary = ctx["batch"]
		body.add_child(JwUi.class_line(JwInfo.Cls.ACTUAL, JwText.render("batch.summary", {
				"done": str(int(b.get("done", 0))), "requested": str(int(b.get("requested", 0))),
				"reason": JwText.t("batch.reason.%d" % int(b.get("reason", 0)))}), false, "text.secondary"))
	for i: int in 3:
		var h: HBoxContainer = JwUi.hbox(10)
		h.add_child(JwIcon.make("settling", JwTheme.c("warm.text"), 16))
		var l: Label = JwUi.label(JwText.t("sr.step.%d" % i) + JwText.t("sr.pending"), "title_sub", "text.muted")
		h.add_child(l)
		_steps.append(l)
		body.add_child(h)
	_cards = JwUi.vbox(10)
	body.add_child(_cards)
	set_process(true)


func _process(delta: float) -> void:
	if _done:
		return
	_t += delta
	if _t >= 0.35:
		_t = 0.0
		if _stage < _steps.size():
			_steps[_stage].text = JwText.t("sr.step.%d" % _stage) + JwText.t("sr.done")
			_steps[_stage].add_theme_color_override("font_color", JwTheme.c("text.primary"))
			_stage += 1
		else:
			_done = true
			_show_cards()


## 测试与截图用：跳过回放动画。
func finish_now() -> void:
	for i: int in _steps.size():
		_steps[i].text = JwText.t("sr.step.%d" % i) + JwText.t("sr.done")
	_stage = _steps.size()
	if not _done:
		_done = true
		_show_cards()


func _show_cards() -> void:
	var m: JwReadModel = session.model
	var n_cards: int = 0
	for c: Variant in ctx.get("commands", []):
		var cd: Dictionary = c
		var acc: bool = int(cd.get("accepted", 0)) == 1 and bool(cd.get("submit_ok", true))
		if acc:
			_cards.add_child(JwUi.class_line(JwInfo.Cls.ACTUAL, JwText.render("sr.cmd.ok", {"label": String(cd["label"])})))
		else:
			var code: int = int(cd.get("reject_code", 0))
			if code == 0:
				code = int(cd.get("submit_code", 0))
			var r: Dictionary = JwReasons.from_code(code, {"kind": int(cd.get("kind", 0)), "p": int(cd.get("p", -1)),
					"draft": -1, "subject": "cmd", "subject_label": String(cd["label"])}, m, session.catalog)
			_cards.add_child(JwUi.class_line(JwInfo.Cls.ACTUAL, JwText.render("sr.cmd.rejected", {"label": String(cd["label"]),
					"cat": JwText.t("reason.cat." + String(r.get("code", "")))}), false, "ochre.core"))
			_cards.add_child(JwReasonView.make(r, session, root_ui))
		n_cards += 1
	if int(ctx.get("arrears_delta", 0)) > 0:
		_cards.add_child(JwUi.class_line(JwInfo.Cls.ACTUAL, JwText.render("sr.arrears", {"amount": JwFormat.u(int(ctx["arrears_delta"]))}),
				false, "ochre.core"))
		n_cards += 1
	if bool(ctx.get("review_quarter", false)):
		_cards.add_child(JwUi.class_line(JwInfo.Cls.ACTUAL, JwText.render("sr.review", {
				"status": JwText.t("mandate_status.%d" % m.sc("state.politics.mandate_status")),
				"fails": str(m.sc("state.politics.review_fail_streak"))})))
		n_cards += 1
	if bool(ctx.get("election_quarter", false)):
		_cards.add_child(JwUi.class_line(JwInfo.Cls.ACTUAL, JwText.render("sr.election", {"seats": str(m.sc("state.politics.seats_gov")),
				"total": str(m.sc("state.politics.seats_total"))})))
		n_cards += 1
	if bool(ctx.get("terminated", false)):
		_cards.add_child(JwUi.class_line(JwInfo.Cls.ACTUAL, JwText.render("sr.terminated", {
				"reason": JwText.t("termination.%d" % int(ctx.get("termination_reason", 0))),
				"rule": JwText.t("rule.termination.%d" % int(ctx.get("termination_reason", 0)))}), false, "ochre.hot"))
		n_cards += 1
	if n_cards == 0:
		_cards.add_child(JwUi.para(JwText.t("sr.no_interrupts"), "text.secondary"))
	var h: HBoxContainer = JwUi.hbox(12)
	var rep: Button = JwUi.button(JwText.t("sr.to_report"), "PrimaryButton")
	rep.pressed.connect(func() -> void:
		close()
		session.clear_settled_flag()
		_after()
		if root_ui != null:
			root_ui.call("show_page", "report", {}))
	h.add_child(rep)
	var cont: Button = JwUi.button(JwText.t("sr.continue"))
	cont.pressed.connect(func() -> void:
		close()
		_after())
	h.add_child(cont)
	_cards.add_child(h)


## 结算后的后续覆盖层：年度审查（审查季）、发展档案（执政结束）。
func _after() -> void:
	if root_ui == null:
		return
	if bool(ctx.get("terminated", false)):
		root_ui.call("open_overlay", "archive", {})
	elif bool(ctx.get("review_quarter", false)):
		root_ui.call("open_overlay", "annual", {})
