## 术语定义卡（docs/20 §10.4 术语首见；ModalLayer）：术语、一句定义、本局实例、规则手册锚点。
## 打开即视为「看过」，页面上该术语的「新」角标随之消失。
class_name JwTermCard
extends JwOverlay


func _init() -> void:
	modal = true
	width_ratio = 0.46
	height_ratio = 0.4


func build() -> void:
	var id: String = String(ctx.get("term", ""))
	if not JwGlossary.has(id):
		set_title(JwText.t("gloss.card.missing"))
		return
	set_title(JwGlossary.term(id))
	var d: Label = JwUi.label(JwGlossary.definition(id), "body", "text.primary", true)
	JwUi.tag(d, "TermDefinition")
	body.add_child(d)
	body.add_child(JwUi.label(JwText.t("gloss.card.instance"), "body_bold", "text.secondary"))
	var inst: HBoxContainer = JwUi.class_line(JwInfo.Cls.ACTUAL, JwGlossary.instance(id, session))
	JwUi.tag(inst, "TermInstance")
	body.add_child(inst)
	var n: int = JwGlossary.anchor(id)
	var lk: Button = JwUi.link(JwText.render("gloss.card.rule", {"section": JwText.t("rb.s%d" % n)}))
	JwUi.tag(lk, "TermRuleLink")
	lk.pressed.connect(func() -> void:
		close()
		if root_ui != null:
			root_ui.call("open_overlay", "rules", {"anchor": n}))
	body.add_child(lk)
