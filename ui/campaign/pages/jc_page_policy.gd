## 政令与财政：收支一览、四种税（加减一档）、七项拨款（加减一成）、政令（开关 / 档位 / 发起）、借贷。
class_name JcPagePolicy
extends JcPage

## 每按一下调多少：地丁、商税按千分之五，盐课按五十厘，关税按一个百分点
const TAX_STEP: Dictionary = {"land": 5_000, "salt": 50, "commerce": 5_000, "customs": 10_000}
const BUDGET_STEP: int = 100_000


func refresh() -> void:
	clear()
	if not session.has_game():
		return
	var g: JCGame = game()
	var v: Dictionary = views().policy()
	var f: Dictionary = v["fiscal"]
	# ── 收支 ──
	var tiles: HBoxContainer = JwUi.hbox(10)
	tiles.add_child(JcUi.tile(t("jc.pol.rev"), JcFmt.money(int(f["rev"])), t("jc.pol.per_q"), JcUi.MUTED, t("jc.pol.rev_tip")))
	tiles.add_child(JcUi.tile(t("jc.pol.exp"), JcFmt.money(int(f["exp"])), t("jc.pol.per_q"), JcUi.MUTED, t("jc.pol.exp_tip")))
	var bal: int = int(f["balance"])
	var runway: int = int(f["runway_q"])
	tiles.add_child(JcUi.tile(t("jc.pol.balance"), JcFmt.money_signed(bal),
			rt("jc.pol.runway", {"n": JcFmt.quarters(runway)}) if bal < 0 else t("jc.pol.surplus"), JcUi.tone(bal >= 0, runway > 12)))
	tiles.add_child(JcUi.tile(t("jc.pol.debt"), JcFmt.money(int(v["debt"])),
			rt("jc.pol.interest", {"v": JcFmt.money(int(f["interest_q"]))}) if int(v["debt"]) > 0 else t("jc.pol.no_debt"), JcUi.MUTED))
	tiles.add_child(JcUi.tile(t("jc.pol.hidden"), JcFmt.pct(int(f["hidden_ppm"]), 0), t("jc.pol.hidden_sub"),
			JcUi.tone(int(f["hidden_ppm"]) < 100_000, int(f["hidden_ppm"]) < 160_000), t("jc.pol.hidden_tip")))
	content.add_child(tiles)
	var two: HBoxContainer = JwUi.hbox(14)
	two.add_child(_tax_card(v))
	two.add_child(_budget_card(v))
	content.add_child(two)
	content.add_child(_decree_card(g, v))
	content.add_child(_loan_card(v))


func _stepper(value_text: String, dec: Callable, inc: Callable, can_dec: bool, can_inc: bool) -> HBoxContainer:
	var h: HBoxContainer = JwUi.hbox(4)
	var bd: Button = JcUi.button(t("jc.pol.less"), false, dec)
	bd.disabled = not can_dec
	bd.custom_minimum_size = Vector2(34, 0)
	h.add_child(bd)
	var l: Label = JwUi.label(value_text, "num_bold", "text.primary")
	l.custom_minimum_size = Vector2(96, 0)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	h.add_child(l)
	var bi: Button = JcUi.button(t("jc.pol.more"), false, inc)
	bi.disabled = not can_inc
	bi.custom_minimum_size = Vector2(34, 0)
	h.add_child(bi)
	return h


func _tax_value(tax: String, v: int) -> String:
	return JcFmt.money(v) + t("jc.u.per_dan") if tax == "salt" else JcFmt.pct(v, 1)


func _tax_card(v: Dictionary) -> PanelContainer:
	var c: Dictionary = JcUi.card(t("jc.pol.taxes"), t("jc.pol.taxes_sub"))
	var body: VBoxContainer = c["body"]
	for tx: Dictionary in v["taxes"]:
		var tax: String = String(tx["tax"])
		var val: int = int(tx["value"])
		var lo: int = int(tx["lo"])
		var hi: int = int(tx["hi"])
		var step: int = int(TAX_STEP[tax])
		var row: HBoxContainer = JwUi.hbox(10)
		var nv: VBoxContainer = JwUi.vbox(0)
		nv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nv.add_child(JwUi.label(t("jc.tax." + tax), "body_bold", "text.primary"))
		nv.add_child(JwUi.label(rt("jc.pol.tax_line", {"base": _tax_value(tax, int(tx["base"])), "rev": JcFmt.money(int(tx["rev"]))}),
				"caption", "text.muted", true))
		nv.tooltip_text = t("jc.pol.tax_tip." + tax)
		nv.mouse_filter = Control.MOUSE_FILTER_STOP
		row.add_child(nv)
		row.add_child(_stepper(_tax_value(tax, val),
				func() -> void: session.order({"kind": "tax", "tax": tax, "value": maxi(lo, val - step)}, true),
				func() -> void: session.order({"kind": "tax", "tax": tax, "value": mini(hi, val + step)}, true),
				val > lo, val < hi))
		body.add_child(row)
	return c["root"]


func _budget_card(v: Dictionary) -> PanelContainer:
	var c: Dictionary = JcUi.card(t("jc.pol.budget"), t("jc.pol.budget_sub"))
	var body: VBoxContainer = c["body"]
	var spent_arr: Array = v["exp"]
	for bl: Dictionary in v["budget"]:
		var line: int = int(bl["line"])
		var lvl: int = int(bl["level"])
		# 设施类拨款（衙署、办学、医药、工程）超过足额也没用；军饷、赈济、宫廷可加到一倍半
		var hi: int = 1_500_000 if line in [1, 5, 6] else 1_000_000
		var row: HBoxContainer = JwUi.hbox(10)
		var nv: VBoxContainer = JwUi.vbox(0)
		nv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nv.add_child(JwUi.label(t("jc.budget.%d" % line), "body_bold", "text.primary"))
		nv.add_child(JwUi.label(rt("jc.pol.budget_line", {"spent": JcFmt.money(int(spent_arr[line]) if spent_arr.size() > line else 0)}),
				"caption", "text.muted", true))
		nv.tooltip_text = t("jc.budget.tip.%d" % line)
		nv.mouse_filter = Control.MOUSE_FILTER_STOP
		row.add_child(nv)
		row.add_child(_stepper(JcFmt.pct(lvl, 0),
				func() -> void: session.order({"kind": "budget", "line": line, "level": maxi(0, lvl - BUDGET_STEP)}, true),
				func() -> void: session.order({"kind": "budget", "line": line, "level": mini(hi, lvl + BUDGET_STEP)}, true),
				lvl > 0, lvl < hi))
		body.add_child(row)
	return c["root"]


func _decree_card(g: JCGame, v: Dictionary) -> PanelContainer:
	var c: Dictionary = JcUi.card(t("jc.pol.decrees"), t("jc.pol.decrees_sub"))
	var gr: GridContainer = JcUi.grid(2, 12, 12)
	var q: int = g.st.q
	for dv: Dictionary in v["decrees"]:
		if bool(dv["locked"]) and int(dv["era"]) > g.st.era + 1:
			continue
		gr.add_child(_decree_box(g, dv, q))
	(c["body"] as VBoxContainer).add_child(gr)
	return c["root"]


func _decree_box(g: JCGame, dv: Dictionary, q: int) -> PanelContainer:
	var id: String = String(dv["id"])
	var kind: String = String(dv["kind"])
	var lvl: int = int(dv["level"])
	var locked: bool = bool(dv["locked"])
	var active: bool = lvl > 0 and kind != "level" and (kind != "campaign" or int(dv["until"]) > q)
	var rule: String = JcUi.GOOD if active else ("line.hair" if locked else "line.strong")
	var p: PanelContainer = JwUi.panel_style(JwTheme.box_left_rule("bg.raised" if not locked else "bg.panel", rule, 4, 10))
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var vb: VBoxContainer = JwUi.vbox(4)
	p.add_child(vb)
	var h: HBoxContainer = JwUi.hbox(8)
	h.add_child(JwUi.label(String(dv["name"]), "body_bold", "text.primary" if not locked else "text.muted"))
	if kind == "campaign":
		h.add_child(JcUi.chip(t("jc.pol.kind_campaign"), JcUi.MUTED))
	if active:
		h.add_child(JcUi.chip(t("jc.pol.in_force") if kind != "campaign" else rt("jc.pol.running",
				{"n": JcFmt.quarters(int(dv["until"]) - q)}), JcUi.GOOD))
	vb.add_child(h)
	vb.add_child(JwUi.label(String(dv["desc"]), "caption", "text.secondary", true))
	var costs: PackedStringArray = PackedStringArray()
	if int(dv["cost_once"]) > 0:
		costs.append(rt("jc.pol.cost_once", {"v": JcFmt.money(int(dv["cost_once"]))}))
	if int(dv["cost_q"]) > 0:
		costs.append(rt("jc.pol.cost_q", {"v": JcFmt.money(int(dv["cost_q"]))}))
	if kind == "campaign" and int(dv["duration"]) > 0:
		costs.append(rt("jc.pol.duration", {"n": JcFmt.quarters(int(dv["duration"]))}))
	if not costs.is_empty():
		vb.add_child(JwUi.label(t("jc.list_sep").join(costs), "caption", "text.muted", true))
	if locked:
		var why: String = rt("jc.pol.locked_era", {"era": JcFmt.era_name(int(dv["era"]))}) if g.st.era < int(dv["era"]) \
				else rt("jc.pol.locked_tech", {"tech": g.name_of("tech", String(dv["tech"]))})
		vb.add_child(JwUi.label(why, "caption", JcUi.WARN, true))
		return p
	var cooling: bool = int(dv["cool"]) > q
	var act: HBoxContainer = JwUi.hbox(6)
	match kind:
		"level":
			var levels: Array = dv["levels"]
			for i: int in levels.size():
				var li: int = i
				var b: Button = JwUi.button(String(levels[i]), "TabBtn")
				b.toggle_mode = true
				b.set_pressed_no_signal(i == lvl)
				b.pressed.connect(func() -> void:
					if li != lvl:
						session.order({"kind": "decree", "decree": id, "level": li}, true)
					else:
						b.set_pressed_no_signal(true))
				b.disabled = i != lvl and cooling and i > 0
				act.add_child(b)
		"campaign":
			var b2: Button = JcUi.button(t("jc.pol.launch"), false, func() -> void:
				session.order({"kind": "decree", "decree": id, "level": 1}, true))
			b2.disabled = active or cooling
			act.add_child(b2)
		_:
			var b3: Button = JcUi.button(t("jc.pol.stop") if lvl > 0 else t("jc.pol.enact"), false, func() -> void:
				session.order({"kind": "decree", "decree": id, "level": 0 if lvl > 0 else 1}, true))
			b3.disabled = cooling and lvl == 0
			act.add_child(b3)
	if cooling:
		act.add_child(JwUi.label(rt("jc.pol.cooling", {"n": JcFmt.quarters(int(dv["cool"]) - q)}), "caption", "text.muted"))
	vb.add_child(act)
	return p


func _loan_card(v: Dictionary) -> PanelContainer:
	var c: Dictionary = JcUi.card(t("jc.pol.loans"), t("jc.pol.loans_sub"))
	var body: VBoxContainer = c["body"]
	var lim: int = int(v["loan_limit"])
	var debt: int = int(v["debt"])
	body.add_child(JwUi.para(rt("jc.pol.loan_line", {"limit": JcFmt.money(lim), "rate": JcFmt.pct(int(v["rate"]), 1),
			"debt": JcFmt.money(debt)}), "text.secondary"))
	var h: HBoxContainer = JwUi.hbox(8)
	for part: int in [100_000, 250_000, 500_000]:
		var amt: int = JCMath.mulppm(lim, part)
		var b: Button = JcUi.button(rt("jc.pol.borrow", {"v": JcFmt.money(amt)}), false, func() -> void:
			session.order({"kind": "loan", "amount": amt}))
		b.disabled = amt <= 0
		h.add_child(b)
	h.add_child(JwUi.spacer())
	if debt > 0:
		var tr: int = game().st.treasury
		var pay: int = mini(debt, tr)
		var b2: Button = JcUi.button(rt("jc.pol.repay", {"v": JcFmt.money(pay)}), false, func() -> void:
			session.order({"kind": "repay", "amount": pay}))
		b2.disabled = pay <= 0
		h.add_child(b2)
	body.add_child(h)
	return c["root"]
