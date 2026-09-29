## 外贸：海运、陆运的运力用了多少；各国（交情、商约、要什么、卖什么、比家里贵还是便宜）；关税一键调。
class_name JcPageTrade
extends JcPage

const CUSTOMS_STEP: int = 10_000
const PPM_I: int = 1_000_000


func refresh() -> void:
	clear()
	if not session.has_game():
		return
	var g: JCGame = game()
	var v: Dictionary = views().trade()
	# ── 运力与关税 ──
	var top: HBoxContainer = JwUi.hbox(10)
	top.add_child(_cap_tile(t("jc.trd.sea"), int(v["sea_used"]), int(v["sea_cap"]), t("jc.trd.sea_tip")))
	top.add_child(_cap_tile(t("jc.trd.land"), int(v["land_used"]), int(v["land_cap"]), t("jc.trd.land_tip")))
	var cus: int = int(v["customs"])
	var ct: PanelContainer = JwUi.panel_style(JwTheme.box4("bg.panel", "line.hair", 1, 14, 10, 14, 10))
	ct.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var cvb: VBoxContainer = JwUi.vbox(4)
	ct.add_child(cvb)
	cvb.add_child(JwUi.label(t("jc.tax.customs"), "caption", "text.muted"))
	var ch: HBoxContainer = JwUi.hbox(6)
	var bd: Button = JcUi.button(t("jc.pol.less"), false, func() -> void:
		session.order({"kind": "tax", "tax": "customs", "value": maxi(0, cus - CUSTOMS_STEP)}, true))
	bd.disabled = cus <= 0
	ch.add_child(bd)
	ch.add_child(JwUi.label(JcFmt.pct(cus, 0), "block_num", "text.primary"))
	var bi: Button = JcUi.button(t("jc.pol.more"), false, func() -> void:
		session.order({"kind": "tax", "tax": "customs", "value": mini(300_000, cus + CUSTOMS_STEP)}, true))
	bi.disabled = cus >= 300_000
	ch.add_child(bi)
	cvb.add_child(ch)
	cvb.add_child(JwUi.label(t("jc.trd.customs_sub"), "caption", "text.muted", true))
	top.add_child(ct)
	content.add_child(top)
	content.add_child(JwUi.para(t("jc.trd.intro"), "text.muted"))
	# ── 各国 ──
	for pv: Dictionary in v["partners"]:
		if not bool(pv["active"]) and int(pv["appear_era"]) > int(v["world_era"]) + 1:
			continue
		content.add_child(_partner_card(g, pv))


func _cap_tile(label: String, used: int, cap: int, tip: String) -> PanelContainer:
	var p: PanelContainer = JwUi.panel_style(JwTheme.box4("bg.panel", "line.hair", 1, 14, 10, 14, 10))
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.tooltip_text = tip
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	var vb: VBoxContainer = JwUi.vbox(4)
	p.add_child(vb)
	vb.add_child(JwUi.label(label, "caption", "text.muted"))
	var r: int = JCMath.ratio_ppm(used, maxi(1, cap))
	vb.add_child(JwUi.label(rt("jc.trd.cap_line", {"used": JcFmt.money(used), "cap": JcFmt.money(cap)}), "num_bold", "text.primary"))
	var m: JcMeter = JcUi.meter(r, JcUi.tone(r < 850_000, r < 980_000), 220.0, 8.0)
	m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_child(m)
	vb.add_child(JwUi.label(t("jc.trd.cap_full") if r >= 980_000 else rt("jc.trd.cap_room", {"v": JcFmt.pct(PPM_I - r, 0)}),
			"caption", JcUi.BAD if r >= 980_000 else "text.muted"))
	return p


func _partner_card(g: JCGame, pv: Dictionary) -> PanelContainer:
	var active: bool = bool(pv["active"])
	var p: PanelContainer = JwUi.panel("bg.panel", "line.hair", 12)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var h: HBoxContainer = JwUi.hbox(14)
	p.add_child(h)
	var art: String = String(pv["art"])
	if art != "" and not art.begins_with("res://"):
		art = "res://" + art
	h.add_child(JcUi.art(art, Vector2(150, 110), true))
	var vb: VBoxContainer = JwUi.vbox(6)
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(vb)
	var hh: HBoxContainer = JwUi.hbox(8)
	hh.add_child(JwUi.label(String(pv["name"]), "title_sub", "text.primary"))
	hh.add_child(JcUi.chip(t("jc.trd.route." + String(pv["route"])), JcUi.MUTED))
	hh.add_child(JcUi.chip(rt("jc.trd.their_era", {"era": JcFmt.era_name(int(pv["era"]))}), JcUi.MUTED))
	if bool(pv["treaty"]):
		hh.add_child(JcUi.chip(t("jc.trd.has_treaty"), JcUi.GOOD))
	hh.add_child(JwUi.spacer())
	if active:
		var rel: int = int(pv["relation"])
		hh.add_child(JwUi.label(rt("jc.trd.relation", {"v": t(_rel_key(rel))}), "body", JcUi.tone(rel >= 20, rel >= 0)))
	vb.add_child(hh)
	vb.add_child(JwUi.label(String(pv["desc"]), "caption", "text.secondary", true))
	if not active:
		vb.add_child(JwUi.label(rt("jc.trd.not_yet", {"era": JcFmt.era_name(int(pv["appear_era"]))}), "caption", "text.muted"))
		return p
	vb.add_child(JwUi.label(rt("jc.trd.flow", {"exp": JcFmt.money(int(pv["exports"])), "imp": JcFmt.money(int(pv["imports"]))}),
			"body", "text.primary"))
	var two: HBoxContainer = JwUi.hbox(16)
	two.add_child(_goods_list(t("jc.trd.wants"), pv["wants"], true))
	two.add_child(_goods_list(t("jc.trd.offers"), pv["offers"], false))
	vb.add_child(two)
	if not bool(pv["treaty"]):
		var pid: String = String(pv["partner"])
		var row: HBoxContainer = JwUi.hbox(8)
		var b: Button = JcUi.button(rt("jc.trd.sign", {"cost": JcFmt.money(int(pv["treaty_cost"]))}), false, func() -> void:
			session.order({"kind": "treaty", "partner": pid}))
		b.disabled = int(pv["relation"]) < 0
		row.add_child(b)
		row.add_child(JwUi.label(t("jc.trd.sign_note") if int(pv["relation"]) >= 0 else t("jc.trd.sign_low"), "caption",
				"text.muted", true))
		vb.add_child(row)
	return p


func _rel_key(rel: int) -> String:
	if rel >= 50:
		return "jc.trd.rel.close"
	if rel >= 20:
		return "jc.trd.rel.good"
	if rel >= 0:
		return "jc.trd.rel.plain"
	if rel >= -30:
		return "jc.trd.rel.cool"
	return "jc.trd.rel.hostile"


func _goods_list(title: String, items: Array, selling: bool) -> VBoxContainer:
	var vb: VBoxContainer = JwUi.vbox(2)
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_child(JwUi.label(title, "caption", "text.muted"))
	if items.is_empty():
		vb.add_child(JwUi.label(t("jc.trd.nothing"), "caption", "text.muted"))
	for it: Dictionary in items:
		var price: int = int(it["price"])
		var home: int = maxi(1, int(it["home"]))
		var diff: int = JCMath.ratio_ppm(price - home, home)
		# 他们买：比家里贵是好事；他们卖：比家里便宜是好事
		var good: bool = diff > 50_000 if selling else diff < -50_000
		var dkey: String = "jc.trd.dearer" if diff > 0 else "jc.trd.cheaper"
		var dtxt: String = t("jc.trd.same") if absi(diff) < 20_000 else rt(dkey, {"v": JcFmt.pct(absi(diff), 0)})
		var txt: String = rt("jc.trd.item", {"name": String(it["name"]), "diff": dtxt})
		vb.add_child(JwUi.label(txt, "caption", JcUi.GOOD if good else "text.secondary"))
	return vb

