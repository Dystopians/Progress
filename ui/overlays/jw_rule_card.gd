## 规则卡（docs/20 §3.6：不隐藏当前规则）：公式原文 / 当前参数值与单位 / 参数来源类型 / 代入展开 / 生效范围。
## 三类外生冲击：列出类别、影响科目、强度与持续期的取值范围；本局的抽样值写「本局未披露」。
class_name JwRuleCard
extends JwOverlay


func _init() -> void:
	modal = true
	width_ratio = 0.56
	height_ratio = 0.72


func build() -> void:
	var key: String = String(ctx.get("rule", ""))
	if key == "" or not JwText.has("rule." + key + ".formula"):
		key = "generic"
	set_title(JwText.render("rc.title", {"name": JwText.t("rule." + key + ".name")}))
	var slots: Dictionary = _slots()
	var parts: Array = [["rc.formula", "formula", "mono"], ["rc.params", "params", "body"], ["rc.source", "source", "body"],
			["rc.expansion", "expansion", "body"], ["rc.scope", "scope", "body"]]
	for p: Array in parts:
		var sec: VBoxContainer = JwUi.vbox(2)
		JwUi.tag(sec, "Rule_" + String(p[1]))
		sec.add_child(JwUi.label(JwText.t(String(p[0])), "body_bold", "text.secondary"))
		var txt: String = JwText.render("rule." + key + "." + String(p[1]), slots)
		if txt == "":
			txt = JwText.t("rc.none")
		sec.add_child(JwUi.label(txt, String(p[2]), "text.primary", true))
		body.add_child(sec)
	var lk: Button = JwUi.link(JwText.t("rc.book"))
	lk.pressed.connect(func() -> void:
		close()
		if root_ui != null:
			root_ui.call("open_overlay", "rules", {}))
	body.add_child(lk)


## 规则卡槽位：当前参数值（来自 JWGame.rule_params 与读模型，已格式化）。
func _slots() -> Dictionary:
	var m: JwReadModel = session.model
	var un: Dictionary = m.unemployment()
	return {
		"cash": JwFormat.u(m.gov_cash()), "debt": JwFormat.u(m.debt_total()),
		"receipts": JwFormat.u(m.receipts_total()), "primary": JwFormat.u(m.sc("flow.gov.primary_paid_uu")),
		"interest": JwFormat.u(m.sc("flow.gov.interest_paid_uu")), "principal": JwFormat.u(m.sc("flow.gov.principal_paid_uu")),
		"borrow": JwFormat.u(m.sc("flow.gov.new_borrowing_uu")),
		"rate": JwFormat.pct(m.sc("state.world.sovereign_rate_ppm_per_q")),
		"coupon_min": JwFormat.pct(m.rule("param.coupon_min_ppm", 0)), "coupon_max": JwFormat.pct(m.rule("param.coupon_max_ppm", 0)),
		"batch_cap": str(m.rule("param.bond_batch_cap", 0)),
		"lf": JwFormat.persons(int(un["labor_force"])), "unemp": JwFormat.persons(int(un["unemployed"])),
		"urate": JwFormat.pct(int(un["rate_ppm"])),
		"gdp_real": JwFormat.u(m.dv("derived.gdp.real_uu")), "gdp_nom": JwFormat.u(m.dv("derived.gdp.production_uu")),
		"pop": JwFormat.persons(m.national_population()),
		"grace": JwFormat.quarters(m.rule("param.default_grace_q", 0)), "noconf": JwFormat.quarters(m.rule("param.no_confidence_q", 0)),
		"deficit_lim": JwFormat.pct(m.rule("politics.budget_review_deficit_limit_ppm", 0)),
		"arrears_lim": JwFormat.u(m.rule("politics.budget_review_arrears_limit_uu", 0)),
		"veto": JwFormat.pct(m.rule("politics.veto_stance_threshold_ppm", 0)),
		"seats": str(m.sc("state.politics.seats_gov")), "seats_total": str(m.sc("state.politics.seats_total")),
		"living_w_house": JwFormat.pct(m.rule("param.living_weight_house_ppm", 0)),
		"living_w_service": JwFormat.pct(m.rule("param.living_weight_service_ppm", 0)),
		"trust_drop": JwFormat.pct(m.rule("param.trust_drop_ppm", 0)), "trust_recover": JwFormat.pct(m.rule("param.trust_recover_ppm", 0)),
		"tax_capacity": JwFormat.pct(m.sc("state.gov.tax_capacity_ppm")),
		"q": JwFormat.quarter(m.q),
	}
