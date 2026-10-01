## 政令与财政：顶上是「国家形态」（按政体与施政给一句评语，配徽记与四个取向的刻度条）；
## 收支一览、四种税（加减一档）、七项拨款（加减一成）；政令按六类分组、做成带配图的卡片（开关 / 档位 / 发起）；借贷。
class_name JcPagePolicy
extends JcPage

## 政令分组（界面上的分类；内容表里新加的政令没写进来时归到「其他」）
const CATEGORIES: Array = [
	["state", ["regime", "labor_policy"]],
	["fiscal", ["single_whip", "land_survey", "tax_remission", "sell_titles", "salt_policy", "income_tax", "banking_license",
			"central_bank"]],
	["welfare", ["ever_normal_granary", "famine_relief", "reclamation", "corvee_works", "social_insurance"]],
	["culture", ["promote_schools", "official_press", "compulsory_school", "foreign_learning"]],
	["trade", ["sea_policy", "commerce_policy", "tea_horse", "navigation_act", "protective_tariff"]],
	["industry", ["industrial_charter", "factory_act", "railway_policy", "environment_law"]],
]
const CARD_W: float = 360.0
const ART_H: float = 150.0

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
	content.add_child(_regime_card(g, v["regime"]))
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


# ── 国家形态 ─────────────────────────────────────────────────────────────
func _regime_card(g: JCGame, rp: Dictionary) -> PanelContainer:
	var card: PanelContainer = JwUi.panel("bg.panel", "line.hair", 16)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var h: HBoxContainer = JwUi.hbox(20)
	card.add_child(h)
	var tone: String = String(rp["tone"])
	var tone_tok: String = JcUi.GOOD if tone == "benevolent" else (JcUi.BAD if tone == "harsh" else "line.strong")
	var title: String = t(String(rp["title"]))
	var em: Control = JcUi.badge(JcUi.REGIME_ART % [String(rp["regime"]), tone], 150.0, title, tone_tok)
	em.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(em)
	var v: VBoxContainer = JwUi.vbox(6)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	v.add_child(JwUi.label(t("jc.regime.head"), "caption", "text.muted"))
	v.add_child(JwUi.label(title, "title_page", tone_tok if tone != "steady" else "text.primary"))
	v.add_child(JwUi.label(rt("jc.regime.sub", {"regime": String(rp["regime_name"]), "era": JcFmt.era_name(g.st.era)}),
			"body", "text.secondary"))
	var lines: PackedStringArray = PackedStringArray()
	var good: Array = rp["good"]
	var harsh: Array = rp["harsh"]
	# 君主国说「朝廷」，共和国与工人国家说「政府」
	var gov: String = t("jc.regime.gov.state" if String(rp["regime"]) in ["republic", "socialist"] else "jc.regime.gov.court")
	if not good.is_empty():
		lines.append(rt("jc.regime.s.good", {"list": t("jc.name_sep").join(PackedStringArray(good)), "gov": gov}))
	if not harsh.is_empty():
		lines.append(rt("jc.regime.s.harsh", {"list": t("jc.name_sep").join(PackedStringArray(harsh))}))
	for n: Dictionary in rp["notes"]:
		var sl: Dictionary = (n["slots"] as Dictionary).duplicate()
		sl["gov"] = gov
		if sl.has("v"):
			sl["v"] = JcFmt._dec(absi(int(sl["v"])), 10_000, 1)
		lines.append(rt(String(n["key"]), sl))
	if good.is_empty() and harsh.is_empty() and (rp["notes"] as Array).is_empty():
		lines.append(t("jc.regime.s.none"))
	lines.append(rt("jc.regime.s.econ", {"v": t("jc.regime.econ." + String(rp["economy"]))}))
	v.add_child(JwUi.label("".join(lines), "body", "text.secondary", true))
	# 四个取向：左边是负的一头，右边是正的一头
	var axes: Dictionary = rp["axes"]
	var gr: GridContainer = JcUi.grid(4, 10, 6)
	gr.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	for ax: Array in [["benevolent", "harsh", "benevolent", JcUi.BAD, JcUi.GOOD], ["central", "laissez", "central", JcUi.WARN, JcUi.WARN],
			["open", "closed", "open", JcUi.WARN, JcUi.GOOD], ["reform", "traditional", "reform", JcUi.WARN, JcUi.GOOD]]:
		# 左：负的一头（严苛、放任、闭关、守旧）；右：正的一头
		var neg: String = String(ax[1])
		var pos: String = String(ax[2])
		var lh: HBoxContainer = JwUi.hbox(6)
		lh.add_child(JcUi.badge(JcUi.POLICY_ICON % ("axis_" + neg), 24.0, t("jc.regime.ax." + neg), "line.strong"))
		var ll: Label = JwUi.label(t("jc.regime.ax." + neg), "caption", "text.secondary")
		ll.custom_minimum_size = Vector2(44, 0)
		lh.add_child(ll)
		gr.add_child(lh)
		var am: JcAxis = JcAxis.new()
		am.value = int(axes[String(ax[0])])
		am.left_tone = String(ax[3])
		am.right_tone = String(ax[4])
		am.custom_minimum_size = Vector2(260, 20)
		gr.add_child(am)
		var rh: HBoxContainer = JwUi.hbox(6)
		var rl: Label = JwUi.label(t("jc.regime.ax." + pos), "caption", "text.secondary")
		rl.custom_minimum_size = Vector2(44, 0)
		rh.add_child(rl)
		rh.add_child(JcUi.badge(JcUi.POLICY_ICON % ("axis_" + pos), 24.0, t("jc.regime.ax." + pos), "line.strong"))
		gr.add_child(rh)
		gr.add_child(JwUi.spacer())
	v.add_child(gr)
	var ec: HBoxContainer = JwUi.hbox(8)
	ec.add_child(JwUi.label(t("jc.regime.ec_head"), "caption", "text.muted"))
	var econ: Dictionary = rp["econ"]
	for k: String in ["agrarian", "mercantile", "industrial"]:
		var on: bool = String(rp["economy"]) == k
		var item: HBoxContainer = JwUi.hbox(4)
		item.add_child(JcUi.badge(JcUi.POLICY_ICON % ("axis_" + k), 22.0, t("jc.regime.ec." + k), JcUi.GOOD if on else "line.hair"))
		item.add_child(JwUi.label(rt("jc.regime.ec_item", {"name": t("jc.regime.ec." + k), "v": str(int(econ[k]))}), "caption",
				JcUi.GOOD if on else "text.muted"))
		ec.add_child(item)
	v.add_child(ec)
	return card


# ── 政令：按六类分组的卡片 ───────────────────────────────────────────────
func _decree_card(g: JCGame, v: Dictionary) -> PanelContainer:
	var c: Dictionary = JcUi.card(t("jc.pol.decrees"), t("jc.pol.decrees_sub"))
	var body: VBoxContainer = c["body"]
	var by_id: Dictionary = {}
	for dv: Dictionary in v["decrees"]:
		by_id[String(dv["id"])] = dv
	var used: Dictionary = {}
	var q: int = g.st.q
	var groups: Array = CATEGORIES.duplicate(true)
	var rest: Array = []
	for dv2: Dictionary in v["decrees"]:
		var found: bool = false
		for cat: Array in CATEGORIES:
			if (cat[1] as Array).has(String(dv2["id"])):
				found = true
		if not found:
			rest.append(String(dv2["id"]))
	if not rest.is_empty():
		groups.append(["other", rest])
	for cat2: Array in groups:
		var cid: String = String(cat2[0])
		var shown: Array = []
		for id: Variant in cat2[1]:
			if not by_id.has(String(id)):
				continue
			var dv3: Dictionary = by_id[String(id)]
			# 还远的（下下个时代以后）先不列，免得一屏全是锁着的
			if bool(dv3["locked"]) and int(dv3["era"]) > g.st.era + 1:
				continue
			shown.append(dv3)
		if shown.is_empty():
			continue
		var hh: HBoxContainer = JwUi.hbox(10)
		hh.add_child(JcUi.badge(JcUi.POLICY_ICON % ("cat_" + cid), 32.0, t("jc.pol.cat." + cid), "line.strong"))
		hh.add_child(JwUi.label(t("jc.pol.cat." + cid), "title_sub", "text.primary"))
		var sub: Label = JwUi.label(t("jc.pol.cat_sub." + cid), "caption", "text.muted")
		sub.size_flags_vertical = Control.SIZE_SHRINK_END
		hh.add_child(sub)
		body.add_child(hh)
		var fl: HFlowContainer = JcUi.flow(12, 12)
		for dv4: Dictionary in shown:
			fl.add_child(_decree_box(g, dv4, q))
		body.add_child(fl)
	return c["root"]


## 一道政令的卡片：配图、名字与状态、说明、对各阶层民心的加减、花费、按钮。
func _decree_box(g: JCGame, dv: Dictionary, q: int) -> PanelContainer:
	var id: String = String(dv["id"])
	var kind: String = String(dv["kind"])
	var lvl: int = int(dv["level"])
	var locked: bool = bool(dv["locked"])
	var active: bool = lvl > 0 and kind != "level" and (kind != "campaign" or int(dv["until"]) > q)
	var rule: String = JcUi.GOOD if active else ("line.hair" if locked else "line.strong")
	var box: StyleBoxFlat = JwTheme.box4("bg.raised" if not locked else "bg.panel", rule, 2 if active else 1, 0, 0, 0, 10)
	box.set_corner_radius_all(8)
	var p: PanelContainer = PanelContainer.new()
	p.add_theme_stylebox_override("panel", box)
	p.custom_minimum_size = Vector2(CARD_W, 0)
	if locked:
		p.modulate = Color(1, 1, 1, 0.7)
	var vb: VBoxContainer = JwUi.vbox(6)
	p.add_child(vb)
	# 配图：分档的用当前那一档的图，没有就用这道政令的总图；都没有时是一块底色加圆章
	var path: String = JcUi.decree_art(id, lvl if kind == "level" else -1)
	if kind == "level" and not JcUi.has_art(path):
		path = JcUi.DECREE_ART % id
	if JcUi.has_art(path):
		vb.add_child(JcUi.art(path, Vector2(CARD_W, ART_H)))
	else:
		var ph: PanelContainer = JwUi.panel("bg.abyss", "", 0)
		ph.custom_minimum_size = Vector2(CARD_W, ART_H)
		var cc: CenterContainer = CenterContainer.new()
		cc.add_child(JcUi.badge("", 72.0, String(dv["name"]), rule))
		ph.add_child(cc)
		vb.add_child(ph)
	var inner: VBoxContainer = JwUi.vbox(5)
	var mc: MarginContainer = MarginContainer.new()
	for side: String in ["margin_left", "margin_right"]:
		mc.add_theme_constant_override(side, 12)
	mc.add_child(inner)
	vb.add_child(mc)
	var h: HBoxContainer = JwUi.hbox(8)
	h.add_child(JwUi.label(String(dv["name"]), "body_bold", "text.primary" if not locked else "text.muted"))
	if kind == "campaign":
		h.add_child(JcUi.chip(t("jc.pol.kind_campaign"), JcUi.MUTED))
	if active:
		h.add_child(JcUi.chip(t("jc.pol.in_force") if kind != "campaign" else rt("jc.pol.running",
				{"n": JcFmt.quarters(int(dv["until"]) - q)}), JcUi.GOOD))
	if kind == "level":
		var levels0: Array = dv["levels"]
		if lvl >= 0 and lvl < levels0.size():
			h.add_child(JcUi.chip(rt("jc.pol.level_now", {"level": String(levels0[lvl])}), JcUi.GOOD))
	inner.add_child(h)
	var desc: Label = JwUi.label(String(dv["desc"]), "caption", "text.secondary", true)
	desc.custom_minimum_size = Vector2(CARD_W - 24.0, 0)
	inner.add_child(desc)
	# 对各阶层民心的加减（分档的看当前一档；开关与运动看施行后）
	var sups: Array = dv["support"]
	var si: int = lvl if kind == "level" else 0
	if si >= 0 and si < sups.size() and not (sups[si] as Dictionary).is_empty():
		var sf: HFlowContainer = JcUi.flow(6, 4)
		sf.add_child(JwUi.label(t("jc.pol.sup_now") if (kind == "level" or active) else t("jc.pol.sup_after"), "caption", "text.muted"))
		for ck: Variant in (sups[si] as Dictionary).keys():
			var dvv: int = int((sups[si] as Dictionary)[ck])
			sf.add_child(JcUi.chip(rt("jc.pol.sup_item", {"class": g.name_of("class", String(ck)),
					"v": ("+%d" % dvv) if dvv > 0 else ("−%d" % -dvv)}), JcUi.GOOD if dvv > 0 else JcUi.BAD))
		inner.add_child(sf)
	var costs: PackedStringArray = PackedStringArray()
	if int(dv["cost_once"]) > 0:
		costs.append(rt("jc.pol.cost_once", {"v": JcFmt.money(int(dv["cost_once"]))}))
	if int(dv["cost_q"]) > 0:
		costs.append(rt("jc.pol.cost_q", {"v": JcFmt.money(int(dv["cost_q"]))}))
	if kind == "campaign" and int(dv["duration"]) > 0:
		costs.append(rt("jc.pol.duration", {"n": JcFmt.quarters(int(dv["duration"]))}))
	if not costs.is_empty():
		inner.add_child(JwUi.label(t("jc.list_sep").join(costs), "caption", "text.muted", true))
	if locked:
		var why: String = rt("jc.pol.locked_era", {"era": JcFmt.era_name(int(dv["era"]))}) if g.st.era < int(dv["era"]) \
				else rt("jc.pol.locked_tech", {"tech": g.name_of("tech", String(dv["tech"]))})
		inner.add_child(JwUi.label(why, "caption", JcUi.WARN, true))
		return p
	var cooling: bool = int(dv["cool"]) > q
	var act: HFlowContainer = JcUi.flow(6, 6)
	match kind:
		"level":
			var levels: Array = dv["levels"]
			var gates: Array = dv.get("level_gate", [])
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
				var gl: bool = i < gates.size() and bool((gates[i] as Dictionary).get("locked", false))
				b.disabled = i != lvl and ((cooling and i > 0) or gl)
				var tip: PackedStringArray = PackedStringArray()
				if i < sups.size():
					for ck2: Variant in (sups[i] as Dictionary).keys():
						var d2: int = int((sups[i] as Dictionary)[ck2])
						tip.append(rt("jc.pol.sup_item", {"class": g.name_of("class", String(ck2)),
								"v": ("+%d" % d2) if d2 > 0 else ("−%d" % -d2)}))
				if gl:
					var gd: Dictionary = gates[i]
					tip.append(rt("jc.pol.level_locked_era", {"era": JcFmt.era_name(int(gd["era"]))}) if g.st.era < int(gd["era"])
							else rt("jc.pol.level_locked_tech", {"tech": g.name_of("tech", String(gd["tech"]))}))
				b.tooltip_text = "\n".join(tip)
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
	inner.add_child(act)
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
