## 顾问：五部的全部建议（右侧栏只显示最要紧的三条），按部分组；每条可「照此办理」或「不必再提」。
class_name JcAdvisorPanel
extends JcOverlay


func build() -> void:
	width_ratio = 0.62
	set_title(t("jc.adv_ov.title"))
	var g: JCGame = game()
	body.add_child(JwUi.para(t("jc.adv_ov.intro"), "text.secondary"))
	var items: Array = g.advisors.items
	if items.is_empty():
		body.add_child(JwUi.para(t("jc.rail.no_advice"), "text.muted"))
		return
	for m: String in JCAdvisors.MINISTRIES:
		var mine: Array = []
		for it: Dictionary in items:
			if String(it["ministry"]) == m:
				mine.append(it)
		var h: HBoxContainer = JwUi.hbox(10)
		h.add_child(JwUi.label(t("jc.adv.m." + m), "title_sub", "text.primary"))
		h.add_child(JwUi.label(t("jc.adv_ov.duty." + m), "caption", "text.muted", true))
		body.add_child(h)
		if mine.is_empty():
			body.add_child(JwUi.label(t("jc.adv_ov.quiet"), "caption", "text.muted"))
			continue
		for it2: Dictionary in mine:
			body.add_child(JcRail.advice_card(session, it2, false))
