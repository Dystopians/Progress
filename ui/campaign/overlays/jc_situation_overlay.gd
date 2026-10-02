## 政局的待决关口（改革推到关口、革命爆发、列强兵临城下、战事、经济危机）：配图、经过、各选项的后果与花费；选一个就办。
## 事件托管（代办）时不弹出；可以先关掉，到「政令 → 政治改革」里再定（截止前不定，按默认的那项办）。
class_name JcSituationOverlay
extends JcOverlay


func build() -> void:
	width_ratio = 0.62
	var g: JCGame = game()
	var sits: Array = session.views().pending_situations()
	if sits.is_empty():
		set_title(t("jc.pt.ov.none_title"))
		body.add_child(JwUi.para(t("jc.pt.ov.none"), "text.muted"))
		var b: Button = JcUi.button(t("jc.pt.ov.goto"), false, _goto)
		body.add_child(b)
		return
	set_title(rt("jc.pt.ov.title", {"n": str(sits.size())}))
	for sv: Dictionary in sits:
		body.add_child(JcSituationCard.build(session, g, sv, true))
	var h: HBoxContainer = JwUi.hbox(8)
	h.add_child(JwUi.spacer())
	h.add_child(JcUi.link(t("jc.pt.ov.goto"), _goto))
	body.add_child(h)


func _goto() -> void:
	JcPagePolicy.want_tab = "politics"
	if root_ui != null and root_ui.has_method("show_page"):
		root_ui.call("show_page", "policy")
	close()
