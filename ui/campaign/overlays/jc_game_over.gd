## 终局：为什么结束、走到了哪一年哪个时代、一生的几个大数；新开一局、读档、翻看纪事。
class_name JcGameOver
extends JcOverlay


func build() -> void:
	width_ratio = 0.5
	height_ratio = 0.72
	set_closable(true)
	var g: JCGame = game()
	var s: Dictionary = g.status()
	var reason: String = String(s.get("over_reason", ""))
	set_title(t("jc.go.title"))
	body.add_child(JwUi.title(t("jc.over." + reason) if reason != "" else t("jc.go.ended"), "title_page"))
	body.add_child(JwUi.para(rt("jc.go.when", {"date": JcFmt.date(g.st.q, g.st.start_year), "era": JcFmt.era_name(int(s["era"])),
			"world": JcFmt.era_name(int(s["world_era"]))}), "text.secondary"))
	body.add_child(JwUi.para(t("jc.go.explain." + reason) if JwText.has("jc.go.explain." + reason) else t("jc.go.explain_any"),
			"text.muted"))
	var tiles: HBoxContainer = JwUi.hbox(10)
	tiles.add_child(JcUi.tile(t("jc.ov.pop"), JcFmt.people(int(s["pop"]))))
	tiles.add_child(JcUi.tile(t("jc.ov.gdp"), JcFmt.money(int(s["gdp"]))))
	tiles.add_child(JcUi.tile(t("jc.ov.living"), JcFmt.pct(int(s["living"]), 0)))
	tiles.add_child(JcUi.tile(t("jc.ov.legit"), JcFmt.pct(int(s["legitimacy"]), 0)))
	body.add_child(tiles)
	var h: HBoxContainer = JwUi.hbox(10)
	h.add_child(JcUi.button(t("jc.go.new"), true, func() -> void:
		close()
		if root_ui != null:
			root_ui.call("open_overlay", "newgame", {})))
	h.add_child(JcUi.button(t("jc.go.load"), false, func() -> void:
		close()
		if root_ui != null:
			root_ui.call("open_overlay", "saves", {})))
	h.add_child(JcUi.button(t("jc.go.chronicle"), false, func() -> void:
		close()
		if root_ui != null:
			root_ui.call("show_page", "chronicle")))
	body.add_child(h)
