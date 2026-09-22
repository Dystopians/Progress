## 存档管理（docs/20 §10.3）：档名 / 季度 / 保存时间 / schema_version / content_hash 前 8 位 / 种子。
##
## 保存与覆盖（覆盖二次确认，写明将被覆盖的档名与季度）；读取失败以原因卡样式给出码与条目，不写「无法读取」；
## content_hash 不符的旧档由应用层以只读检视方式载入（INV-134）。导出调试日志（§18 发布清单）。
## 删除：应用层未提供删除接口，本版不提供（写明原因）。
class_name JwSaveManager
extends JwOverlay

var _name_edit: LineEdit = null
var _confirm_overwrite: String = ""
var _msg: VBoxContainer = null


func _init() -> void:
	modal = true
	width_ratio = 0.82
	height_ratio = 0.86


func build() -> void:
	_fill()


func _fill() -> void:
	JwUi.clear(body)
	set_title(JwText.t("sv.title"))
	_msg = JwUi.vbox(6)
	var rows: Array[Dictionary] = session.list_saves()
	var t: JwTable = JwTable.make([
		{"title": JwText.t("sv.col.slot"), "w": 160},
		{"title": JwText.t("sv.col.q"), "w": 90},
		{"title": JwText.t("sv.col.time"), "w": 200},
		{"title": JwText.t("sv.col.schema"), "w": 110},
		{"title": JwText.t("sv.col.hash"), "w": 120},
		{"title": JwText.t("sv.col.seed"), "w": 170},
		{"title": JwText.t("sv.col.state"), "w": 200, "expand": true, "wrap": true},
		{"title": JwText.t("sv.col.actions"), "w": 220},
	], false, false)
	JwUi.tag(t, "SaveList")
	body.add_child(t)
	for r: Dictionary in rows:
		var ok: bool = bool(r.get("manifest_ok", false))
		var state: String = JwText.t("sv.state.ok")
		var tok: String = "text.secondary"
		if not ok:
			state = JwText.t("sv.state.nomanifest")
			tok = "ochre.core"
		elif not bool(r.get("schema_ok", true)):
			state = JwText.t("sv.state.schema")
			tok = "ochre.core"
		elif not bool(r.get("content_match", true)):
			state = JwText.t("sv.state.content")
			tok = "ochre.core"
		var acts: HBoxContainer = JwUi.hbox(6)
		var slot: String = String(r.get("slot", ""))
		if ok:
			var lb: Button = JwUi.button(JwText.t("sv.act.load"))
			lb.pressed.connect(func() -> void: _load(slot))
			acts.add_child(lb)
			if session.game != null and slot != JwSession.AUTOSAVE_SLOT:
				var ob: Button = JwUi.button(JwText.t("sv.act.overwrite") if _confirm_overwrite != slot else JwText.t("sv.act.overwrite_confirm"),
						"AlertButton" if _confirm_overwrite == slot else "")
				ob.pressed.connect(func() -> void: _overwrite(slot, int(r.get("q", 0))))
				acts.add_child(ob)
		var hsh: String = String(r.get("content_hash", ""))
		t.add_row([slot,
			JwFormat.quarter(int(r.get("q", 0))) if ok else JwText.t("common.none"),
			String(r.get("created_utc", "")),
			str(int(r.get("schema_version", -1))) if ok else JwText.t("common.none"),
			{"text": hsh.substr(0, 8) if hsh != "" else JwText.t("common.none"), "role": "mono"},
			{"text": str(int(r.get("root_seed", 0))), "role": "mono"},
			{"text": state, "color": tok, "wrap": true},
			acts])
	if rows.is_empty():
		body.add_child(JwUi.label(JwText.t("sv.empty"), "body", "text.muted"))
	if _confirm_overwrite != "":
		body.add_child(JwUi.para(JwText.render("sv.overwrite_prompt", {"slot": _confirm_overwrite}), "ochre.core"))
	if session.game != null:
		var h: HBoxContainer = JwUi.hbox(10)
		h.add_child(JwUi.label(JwText.t("sv.new"), "body", "text.secondary"))
		_name_edit = LineEdit.new()
		_name_edit.placeholder_text = JwText.t("sv.name_hint")
		_name_edit.custom_minimum_size = Vector2(220, 34)
		_name_edit.text = "q%02d_%d" % [session.model.q + 1, session.seed_value % 10000]
		h.add_child(_name_edit)
		var sb: Button = JwUi.button(JwText.t("sv.act.save"), "PrimaryButton")
		sb.pressed.connect(_save_new)
		h.add_child(sb)
		var ex: Button = JwUi.button(JwText.t("sv.act.export"))
		ex.pressed.connect(_export)
		h.add_child(ex)
		body.add_child(h)
	body.add_child(_msg)
	body.add_child(JwUi.para(JwText.t("sv.note.delete"), "text.muted"))
	body.add_child(JwUi.para(JwText.t("sv.note.autosave"), "text.muted"))


func _valid(slot: String) -> bool:
	if slot == "" or slot.length() > 40:
		return false
	for i: int in slot.length():
		var c: String = slot[i]
		if not ((c >= "a" and c <= "z") or (c >= "0" and c <= "9") or c == "_"):
			return false
	return true


func _save_new() -> void:
	var slot: String = _name_edit.text.strip_edges().to_lower()
	if not _valid(slot):
		_note(JwText.render("sv.bad_name", {"slot": slot}), true)
		return
	for r: Dictionary in session.list_saves():
		if String(r.get("slot", "")) == slot:
			_overwrite(slot, int(r.get("q", 0)))
			return
	_do_save(slot)


func _overwrite(slot: String, q: int) -> void:
	if _confirm_overwrite != slot:
		_confirm_overwrite = slot
		_fill()
		_note(JwText.render("sv.overwrite_detail", {"slot": slot, "q": JwFormat.quarter(q)}), true)
		return
	_confirm_overwrite = ""
	_do_save(slot)


func _do_save(slot: String) -> void:
	var r: Dictionary = session.save_slot(slot)
	_fill()
	if bool(r.get("ok", false)):
		_note(JwText.render("sv.saved", {"slot": slot, "q": JwFormat.quarter(session.model.q)}), false)
	else:
		_note(JwText.render("sv.save_fail", {"slot": slot, "code": str(int(r.get("code", 0))),
				"name": JwText.t_or("load.code.%d" % int(r.get("code", 0)), "load.code.other")}), true)


func _load(slot: String) -> void:
	var r: Dictionary = session.load_slot(slot)
	if bool(r.get("ok", false)):
		close()
		if root_ui != null:
			root_ui.call("close_all_overlays")
			root_ui.call("show_page", "overview", {})
		return
	_fill()
	var code: int = int(r.get("code", 0))
	var p: PanelContainer = JwUi.panel_style(JwTheme.box_left_rule("bg.raised", "ochre.hot", 3, 12))
	JwUi.tag(p, "LoadRejectCard")
	var v: VBoxContainer = JwUi.vbox(4)
	p.add_child(v)
	v.add_child(JwUi.risk_badge(JwInfo.Sev.BLOCK, JwText.t("sv.reject.title")))
	v.add_child(JwUi.label(JwText.render("sv.reject.line", {"slot": slot, "code": str(code),
			"name": JwText.t_or("load.code.%d" % code, "load.code.other"), "detail": str(int(r.get("a", 0)))}), "body", "text.secondary", true))
	v.add_child(JwUi.label(JwText.t("sv.reject.exits"), "body", "text.secondary", true))
	_msg.add_child(p)


func _export() -> void:
	DirAccess.make_dir_recursive_absolute("user://logs/")
	var path: String = "user://logs/jw_debug_q%02d.json" % (session.model.q + 1)
	var d: Dictionary = {"q": session.model.q, "seed": session.seed_value, "commands": session.model.cmdlog,
			"last_receipt": session.last_receipt, "history": session.history, "events": session.events.slice(maxi(session.events.size() - 500, 0))}
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(JwSession._jsonable(d), "  "))
		f.close()
		_note(JwText.render("sv.exported", {"path": ProjectSettings.globalize_path(path)}), false)
	else:
		_note(JwText.t("sv.export_fail"), true)


func _note(t: String, bad: bool) -> void:
	if _msg == null:
		return
	_msg.add_child(JwUi.label(t, "body_bold", "ochre.core" if bad else "teal.core", true))
