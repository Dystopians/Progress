## 三类信息图例（docs/20 §5.1 顶栏常驻入口）：徽章字 + 图标 + 标尺 + 一句定义 + 一个本局实例。
class_name JwClassLegend
extends JwOverlay


func _init() -> void:
	modal = true
	width_ratio = 0.6
	height_ratio = 0.62


func build() -> void:
	set_title(JwText.t("cl.title"))
	var m: JwReadModel = session.model
	var examples: Array = []
	if session.game != null:
		examples = [
			JwText.render("cl.ex.actual", {"cash": JwFormat.u(m.gov_cash()), "q": JwFormat.quarter(maxi(m.q - 1, -1))}),
			JwText.render("cl.ex.derived", {"due": JwFormat.u(m.headroom_nodraft(4)["committed_4q"])}),
			JwText.render("cl.ex.projected", {"range": _proj_example()}),
		]
	else:
		examples = [JwText.t("cl.ex.none"), JwText.t("cl.ex.none"), JwText.t("cl.ex.none")]
	var classes: Array = [JwInfo.Cls.ACTUAL, JwInfo.Cls.DERIVED, JwInfo.Cls.PROJECTED]
	for i: int in 3:
		var c: int = int(classes[i])
		var row: PanelContainer = JwUi.panel("bg.panel", "line.hair", 12)
		var h: HBoxContainer = JwUi.hbox(12)
		row.add_child(h)
		var rule: JwClassRule = JwClassRule.make(c)
		rule.custom_minimum_size = Vector2(3, 60)
		h.add_child(rule)
		h.add_child(JwUi.badge(c))
		var v: VBoxContainer = JwUi.vbox(2)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.add_child(JwUi.label(JwInfo.cls_name(c) + " · " + JwInfo.prefix(c), "title_sub"))
		v.add_child(JwUi.label(JwText.t("cl.def.%d" % c), "body", "text.secondary", true))
		v.add_child(JwUi.label(String(examples[i]), "body", "text.primary", true))
		h.add_child(v)
		body.add_child(row)
	body.add_child(JwUi.para(JwText.t("cl.channels"), "text.muted"))


func _proj_example() -> String:
	var hr: Dictionary = session.headroom_with_draft()
	if hr.is_empty():
		return JwText.t("common.recalc")
	return JwFormat.range_u(int(hr["lo"]), int(hr["hi"]))
