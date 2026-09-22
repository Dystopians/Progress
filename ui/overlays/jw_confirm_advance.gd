## 推进季度确认框（docs/20 §8.4：显示义务的唯一落点）。
##
## 本体渲染六块，全部不可折叠（NOTE 可折叠）：A1 四季现金预测、A2 基线/不利对照、B 新增长期承诺与三项合计、
## 将提交的命令清单、本季全部不可逆动作、全部 BLOCK/GAP/NOTE 原因。与预算审查是否展开过无关。
## WARN 需勾选「我已阅读全部 N 项提示」；GAP_NOEXIT 需二次确认；有 BLOCK 不可确认（按钮带原因）。
## 不响应裸 Enter：确认按钮只接受鼠标或 Ctrl+Shift+Enter。
class_name JwConfirmAdvance
extends JwOverlay

var _ack: CheckBox = null
var _confirm: Button = null
var _second: bool = false
var _why: Label = null


func _init() -> void:
	modal = true
	width_ratio = 0.92
	height_ratio = 0.92


func build() -> void:
	_fill()
	if session != null:
		session.log_event("ev.confirm_opened", {"q": session.model.q})


func _fill() -> void:
	JwUi.clear(body)
	var m: JwReadModel = session.model
	set_title(JwText.render("ca.title", {"quarter": JwFormat.quarter(m.q)}))
	var ready: bool = session.dry_is_current() and not session.dry_busy()
	if not ready:
		var st: HBoxContainer = JwUi.hbox(8)
		st.add_child(JwIcon.make("loading", JwTheme.c("warm.text"), 14))
		st.add_child(JwUi.label(JwText.t("ca.wait"), "body", "warm.text"))
		body.add_child(st)
	body.add_child(JwFiscalTables.a1(session))
	body.add_child(JwFiscalTables.a2(session))
	body.add_child(JwFiscalTables.b_table(session))
	body.add_child(JwFiscalTables.command_list(session))
	body.add_child(JwFiscalTables.irreversible_list(session))
	body.add_child(JwFiscalTables.reason_list(session, root_ui, true))
	var st2: int = session.dock_state()
	var c: Dictionary = JwReasons.counts(session.reasons())
	var foot: VBoxContainer = JwUi.vbox(8)
	JwUi.tag(foot, "ConfirmFooter")
	if st2 == JwSession.Dock.WARN or int(c["note"]) > 0:
		_ack = CheckBox.new()
		_ack.name = "AckNotes"
		_ack.text = JwText.render("ca.ack", {"n": str(int(c["note"]))})
		_ack.toggled.connect(func(_on: bool) -> void: _update_button())
		foot.add_child(_ack)
	else:
		_ack = null
	if st2 == JwSession.Dock.GAP_NOEXIT:
		foot.add_child(JwUi.para(JwText.t("ca.noexit"), "ochre.core"))
	var h: HBoxContainer = JwUi.hbox(12)
	_confirm = JwUi.button(JwText.t("ca.confirm"), "PrimaryButton")
	_confirm.name = "ConfirmAdvance"
	_confirm.focus_mode = Control.FOCUS_CLICK
	_confirm.custom_minimum_size = Vector2(240, 44)
	_confirm.pressed.connect(_on_confirm)
	h.add_child(_confirm)
	var back: Button = JwUi.button(JwText.t("ca.back"))
	back.pressed.connect(close)
	h.add_child(back)
	_why = JwUi.label("", "body", "ochre.core", true)
	h.add_child(_why)
	foot.add_child(h)
	body.add_child(foot)
	_update_button()


## 确认按钮：有原因才不可用，原因写在旁边（B-13 同一纪律）。
func _update_button() -> void:
	if _confirm == null:
		return
	var st: int = session.dock_state()
	var c: Dictionary = JwReasons.counts(session.reasons())
	var why: String = ""
	if not session.dry_is_current() or session.dry_busy():
		why = JwText.t("ca.why.wait")
	elif st == JwSession.Dock.BLOCKED:
		why = JwText.render("ca.why.block", {"n": str(int(c["block"]))})
	elif st == JwSession.Dock.GAP_UNBOUND:
		why = JwText.t("ca.why.gap")
	elif _ack != null and not _ack.button_pressed:
		why = JwText.render("ca.why.ack", {"n": str(int(c["note"]))})
	_confirm.disabled = why != ""
	_why.text = why
	if st == JwSession.Dock.GAP_NOEXIT and not _second and why == "":
		_confirm.text = JwText.t("ca.confirm_noexit")
	else:
		_confirm.text = JwText.t("ca.confirm")


func _on_confirm() -> void:
	var st: int = session.dock_state()
	if st == JwSession.Dock.GAP_NOEXIT and not _second:
		_second = true
		_confirm.text = JwText.t("ca.confirm_second")
		return
	close()
	session.advance()


func on_dryrun() -> void:
	_fill()


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and (event as InputEventKey).pressed:
		var k: InputEventKey = event
		if k.keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			close()
		elif k.keycode == KEY_ENTER and k.ctrl_pressed and k.shift_pressed and _confirm != null and not _confirm.disabled:
			get_viewport().set_input_as_handled()
			_on_confirm()
