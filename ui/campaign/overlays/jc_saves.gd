## 存档：存到新档（起个名字）或覆盖旧档；读任一存档（内容改过的旧档会按命令簿重演到当时）。
class_name JcSaves
extends JcOverlay

var _name_edit: LineEdit = null


func build() -> void:
	width_ratio = 0.5
	height_ratio = 0.76
	set_title(t("jc.sv.title"))
	if session.has_game():
		var g: JCGame = game()
		var h: HBoxContainer = JwUi.hbox(8)
		h.add_child(JwUi.label(t("jc.sv.new"), "body_bold", "text.primary"))
		_name_edit = LineEdit.new()
		_name_edit.text = "y%d" % g.st.year()
		_name_edit.custom_minimum_size = Vector2(180, 0)
		_name_edit.tooltip_text = t("jc.sv.name_tip")
		h.add_child(_name_edit)
		h.add_child(JcUi.button(t("jc.sv.save"), true, func() -> void:
			var nm: String = _clean(_name_edit.text)
			if nm != "" and session.save_slot(nm):
				on_changed()))
		body.add_child(h)
		body.add_child(JwUi.hsep())
	var saves: Array = JCGame.list_saves()
	if saves.is_empty():
		body.add_child(JwUi.para(t("jc.sv.none"), "text.muted"))
	for sv: Dictionary in saves:
		var slot: String = String(sv["slot"])
		var row: HBoxContainer = JwUi.hbox(10)
		var nv: VBoxContainer = JwUi.vbox(0)
		nv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nv.add_child(JwUi.label(t("jc.sv.auto") if slot == "autosave" else slot, "body_bold", "text.primary"))
		nv.add_child(JwUi.label(rt("jc.sv.line", {"date": rt("jc.u.date", {"year": str(int(sv["year"])),
				"season": t("jc.u.season.%d" % int(sv["season"]))}), "era": JcFmt.era_name(int(sv["era"])),
				"saved": String(sv["saved_at"]).replace("T", " ")}), "caption", "text.muted"))
		row.add_child(nv)
		if session.has_game() and slot != "autosave":
			row.add_child(JcUi.button(t("jc.sv.overwrite"), false, func() -> void:
				if session.save_slot(slot):
					on_changed()))
		row.add_child(JcUi.button(t("jc.sv.load"), true, func() -> void:
			if session.load_slot(slot):
				close()))
		body.add_child(row)


## 存档名去掉文件名里不能用的字符（斜杠、冒号、问号等），最长 40 字。
static func _clean(s: String) -> String:
	var out: String = ""
	for ch: String in s.strip_edges():
		if ch.unicode_at(0) < 32 or "/\\:*?\"<>|.".contains(ch):
			continue
		out += ch
	return out.substr(0, 40)
