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
	# 界面大小：100%—200%，立即生效
	body.add_child(JwUi.hsep())
	var sc: HBoxContainer = JwUi.hbox(8)
	sc.add_child(JwUi.label(t("jc.sv.scale"), "body_bold", "text.primary"))
	var win: Window = get_window()
	var cur: float = JwScale.snap(win.content_scale_factor) if win != null else 1.0
	var top: float = float(root_ui.call("max_ui_scale")) if root_ui != null and root_ui.has_method("max_ui_scale") else 2.0
	for v: float in JwScale.STEPS:
		var vv: float = v
		var sb: Button = JcUi.button("%d%%" % int(round(v * 100.0)), is_equal_approx(v, cur), func() -> void:
			if root_ui != null and root_ui.has_method("set_ui_scale"):
				root_ui.call("set_ui_scale", vv)
			else:
				get_window().content_scale_factor = vv
				JwScale.save_scale(vv)
			on_changed())
		# 屏幕放不下的档（放大后不到 1280×720）不让选
		if v > top + 0.001:
			sb.disabled = true
			sb.tooltip_text = t("jc.sv.scale_too_big")
		sc.add_child(sb)
	body.add_child(sc)
	body.add_child(JwUi.label(t("jc.sv.scale_tip"), "caption", "text.muted", true))
	# 退出：每年春天自动存档；想从这一季接着玩，先存一个档
	body.add_child(JwUi.hsep())
	var q: HBoxContainer = JwUi.hbox(10)
	var qn: Label = JwUi.label(t("jc.sv.quit_note"), "caption", "text.muted", true)
	qn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	q.add_child(qn)
	q.add_child(JcUi.button(t("jc.sv.quit"), false, func() -> void: get_tree().quit()))
	body.add_child(q)


## 存档名去掉文件名里不能用的字符（斜杠、冒号、问号等），最长 40 字。
static func _clean(s: String) -> String:
	var out: String = ""
	for ch: String in s.strip_edges():
		if ch.unicode_at(0) < 32 or "/\\:*?\"<>|.".contains(ch):
			continue
		out += ch
	return out.substr(0, 40)
