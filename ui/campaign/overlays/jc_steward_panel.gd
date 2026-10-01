## 托管：六个领域各选「手动 / 拟办 / 代办」与取向；一键预设；每个领域最近替你办了什么。
class_name JcStewardPanel
extends JcOverlay

const PRESETS: Dictionary = {
	"manual": {"research": 0, "build": 0, "modernize": 0, "fiscal": 0, "trade": 0, "events": 0},
	"recommended": {"research": 2, "build": 1, "modernize": 2, "fiscal": 1, "trade": 2, "events": 2},
	"ask": {"research": 1, "build": 1, "modernize": 1, "fiscal": 1, "trade": 1, "events": 1},
	"auto": {"research": 2, "build": 2, "modernize": 2, "fiscal": 2, "trade": 2, "events": 2},
}


func build() -> void:
	width_ratio = 0.7
	set_title(t("jc.stw_ov.title"))
	var g: JCGame = game()
	body.add_child(JwUi.para(t("jc.stw_ov.intro"), "text.secondary"))
	var ph: HBoxContainer = JwUi.hbox(8)
	ph.add_child(JwUi.label(t("jc.stw_ov.presets"), "body_bold", "text.primary"))
	for pid: String in ["recommended", "ask", "auto", "manual"]:
		var modes: Dictionary = PRESETS[pid]
		var b: Button = JcUi.button(t("jc.stw_ov.preset." + pid), pid == "recommended", func() -> void: _apply(modes))
		b.tooltip_text = t("jc.stw_ov.preset_tip." + pid)
		ph.add_child(b)
	body.add_child(ph)
	for d: String in JCSteward.DOMAINS:
		body.add_child(_domain_box(g, d))


func _apply(modes: Dictionary) -> void:
	var g: JCGame = game()
	for d: String in JCSteward.DOMAINS:
		g.set_steward(d, int(modes[d]))
	session.changed.emit()


func _domain_box(g: JCGame, d: String) -> PanelContainer:
	var mode: int = int(g.steward.mode[d])
	var p: PanelContainer = JwUi.panel_style(JwTheme.box_left_rule("bg.raised",
			JcUi.GOOD if mode == JCSteward.AUTO else (JcUi.WARN if mode == JCSteward.ASK else "line.hair"), 4, 12))
	var v: VBoxContainer = JwUi.vbox(6)
	p.add_child(v)
	var h: HBoxContainer = JwUi.hbox(10)
	h.add_child(JcUi.icon(String(JcUi.STEWARD_ART.get(d, "")), 52.0))
	var nv: VBoxContainer = JwUi.vbox(2)
	nv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nv.add_child(JwUi.label(t("jc.stw.domain." + d), "title_sub", "text.primary"))
	nv.add_child(JwUi.label(t("jc.stw_ov.desc." + d), "caption", "text.muted", true))
	h.add_child(nv)
	var grp: ButtonGroup = ButtonGroup.new()
	for m: int in [JCSteward.OFF, JCSteward.ASK, JCSteward.AUTO]:
		var b: Button = JwUi.button(t("jc.stw.mode.%d" % m), "TabBtn")
		b.toggle_mode = true
		b.button_group = grp
		b.set_pressed_no_signal(m == mode)
		b.tooltip_text = t("jc.stw_ov.mode_tip.%d" % m)
		var mm: int = m
		b.pressed.connect(func() -> void: session.set_steward(d, mm))
		h.add_child(b)
	v.add_child(h)
	# 取向
	var cur: String = String(g.steward.stance[d])
	var sh: HBoxContainer = JwUi.hbox(8)
	sh.add_child(JwUi.label(t("jc.stw_ov.stance"), "caption", "text.muted"))
	var ob: OptionButton = OptionButton.new()
	var stances: Array = JCSteward.STANCES[d]
	for i: int in stances.size():
		ob.add_item(t("jc.stw.stance." + String(stances[i])), i)
		if String(stances[i]) == cur:
			ob.select(i)
	ob.item_selected.connect(func(idx: int) -> void: session.set_steward(d, int(g.steward.mode[d]), String(stances[idx])))
	sh.add_child(ob)
	sh.add_child(JwUi.label(t("jc.stw_ov.stance_desc.%s.%s" % [d, cur]), "caption", "text.secondary", true))
	v.add_child(sh)
	# 最近
	var recent: Array = []
	for rec: Dictionary in session.views().steward_log(200):
		if String(rec["domain"]) == d:
			recent.append(rec)
		if recent.size() >= 3:
			break
	if not recent.is_empty():
		for rec2: Dictionary in recent:
			var txt: String = JcFmt.date(int(rec2["q"]), g.st.start_year) + "  " + JcFmt.r(String(rec2["reason"]),
					JcFmt.slots(g, rec2.get("slots", {})))
			v.add_child(JwUi.label(txt, "caption", "text.muted" if bool(rec2.get("ok", false)) else JcUi.WARN, true))
	return p
