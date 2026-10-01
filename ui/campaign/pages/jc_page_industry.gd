## 产业：商品一览（带物资图的卡片，按部门分组；全部 / 紧缺 / 积压）＋ 选中商品的来龙去脉
## （产业链图、谁在产、用什么料、谁在用、能产它的建筑，都配图）与补缺口的办法。
class_name JcPageIndustry
extends JcPage

var list_box: VBoxContainer = null
var chain_box: VBoxContainer = null
var _filter: String = "all"
var _fbtns: Dictionary = {}
var _lp: PanelContainer = null


func build() -> void:
	var h: HBoxContainer = JwUi.hbox(12)
	add_child(h)
	var lp: PanelContainer = JwUi.panel("bg.panel", "line.hair", 10)
	lp.custom_minimum_size = Vector2(700, 0)
	lp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	h.add_child(lp)
	_lp = lp
	var lv: VBoxContainer = JwUi.vbox(8)
	lp.add_child(lv)
	var fb: HBoxContainer = JwUi.hbox(4)
	var grp: ButtonGroup = ButtonGroup.new()
	for id: String in ["all", "short", "glut"]:
		var b: Button = JwUi.button(JwText.t("jc.ind.filter." + id))
		b.toggle_mode = true
		b.button_group = grp
		b.pressed.connect(func() -> void:
			_filter = id
			refresh())
		fb.add_child(b)
		_fbtns[id] = b
	fb.add_child(JwUi.spacer())
	fb.add_child(JcUi.button(JwText.t("jc.ind.build"), true, func() -> void: open_overlay("build", {})))
	lv.add_child(fb)
	list_box = JwUi.vbox(8)
	lv.add_child(JwUi.scroll(list_box))
	var rp: PanelContainer = JwUi.panel("bg.panel", "line.hair", 12)
	rp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	h.add_child(rp)
	chain_box = JwUi.vbox(10)
	rp.add_child(JwUi.scroll(chain_box))


## 左边商品卡排几列：右边详情至少留 560 宽，剩下的放得下三列就三列，放不下就两列、一列。
func relayout(w: float) -> void:
	if _lp == null or w <= 0.0:
		return
	var cols: int = 3
	while cols > 1 and w - float(cols * 220 + 40) - 12.0 < 560.0:
		cols -= 1
	_lp.custom_minimum_size.x = float(cols * 220 + 40)


func _row_box() -> HBoxContainer:
	var h: HBoxContainer = JwUi.hbox(6)
	h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return h


func _cell(text: String, role: String, tok: String, wide: bool = false) -> Label:
	var l: Label = JwUi.label(text, role, tok)
	l.custom_minimum_size = Vector2(120 if wide else 100, 0)
	if not wide:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.clip_text = true
	return l


func refresh() -> void:
	if not session.has_game():
		return
	(_fbtns[_filter] as Button).set_pressed_no_signal(true)
	JwUi.clear(list_box)
	var goods: Array = views().goods()
	var last_sector: String = ""
	var flow: HFlowContainer = null
	for gv: Dictionary in goods:
		var state: String = String(gv["state"])
		if _filter != "all" and state != _filter:
			continue
		if String(gv["sector"]) != last_sector:
			last_sector = String(gv["sector"])
			var sh: HBoxContainer = JwUi.hbox(8)
			sh.add_child(JcUi.badge(JcUi.SECTOR_ICON % last_sector, 28.0, JwText.t("jc.sector." + last_sector), "line.strong"))
			sh.add_child(JwUi.label(JwText.t("jc.sector." + last_sector), "title_sub", "text.secondary"))
			list_box.add_child(sh)
			flow = JcUi.flow(8, 8)
			list_box.add_child(flow)
		flow.add_child(_good_tile(gv))
	if session.selected_good == "" and not goods.is_empty():
		for gv2: Dictionary in goods:
			if String(gv2["state"]) == "short":
				session.selected_good = String(gv2["id"])
				break
		if session.selected_good == "":
			session.selected_good = String(goods[0]["id"])
	_chain(session.selected_good)


## 一样货的卡片：物资图、名字、较常价、产需比的细条、一行状态（缺多少 / 够几季）；紧缺描红、积压描赭。
func _good_tile(gv: Dictionary) -> Control:
	var state: String = String(gv["state"])
	var tok: String = JcUi.BAD if state == "short" else (JcUi.WARN if state == "glut" else "line.hair")
	var sel: bool = String(gv["id"]) == session.selected_good
	var box: StyleBoxFlat = JwTheme.box4("bg.raised" if sel else "bg.panel", "ochre.core" if sel else tok, 2 if (sel or state != "ok") else 1,
			8, 6, 8, 6)
	box.set_corner_radius_all(8)
	var b: Button = Button.new()
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(212, 70)
	b.tooltip_text = JwText.t("jc.chain.tip." + state)
	var p: PanelContainer = PanelContainer.new()
	p.add_theme_stylebox_override("panel", box)
	p.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(p)
	var h: HBoxContainer = JwUi.hbox(8)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(h)
	var ic: Control = JcUi.badge(JcUi.res(String(gv.get("art", ""))), 44.0, String(gv["name"]), tok)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(ic)
	var v: VBoxContainer = JwUi.vbox(2)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(v)
	var top: HBoxContainer = JwUi.hbox(4)
	top.add_child(JwUi.label(String(gv["name"]), "body_bold", JcUi.BAD if state == "short" else "text.primary"))
	top.add_child(JwUi.spacer())
	var pp: int = int(gv["price_ppm"])
	top.add_child(JwUi.label(price_word(pp), "caption", JcUi.BAD if pp > 1_250_000 else (JcUi.WARN if pp < 800_000 else "text.muted")))
	v.add_child(top)
	var d: int = int(gv["demand"])
	var fill: int = JcUi.PPM_ONE if d <= 0 else mini(JcUi.PPM_ONE, JCMath.ratio_ppm(int(gv["prod"]) + int(gv["imp"]), d))
	v.add_child(JcUi.meter(fill, JcUi.BAD if state == "short" else (JcUi.WARN if state == "glut" else JcUi.GOOD), 140.0, 5.0))
	var gap: int = int(gv["unmet"]) + int(gv["imp"])
	var unit: String = String(gv["unit"])
	var sq: int = int(gv["stock_q"])
	var line: String = ""
	if state == "short" and gap > 0:
		line = JwText.render("jc.ind.tile_short", {"v": JcFmt.qty(gap, unit), "pct": JcFmt.pct(int(gv.get("short_ppm", 0)), 0)})
	else:
		line = t("jc.ind.stock_lots") if sq > 100_000_000 else JwText.render("jc.ind.stock_q", {"q": JcFmt._dec(sq, 1_000_000, 1)})
	v.add_child(JcUi.icon_label(JcUi.STATUS_ICON % ("status_" + state), line, "caption",
			JcUi.BAD if state == "short" else "text.muted", 16.0))
	var gid: String = String(gv["id"])
	b.pressed.connect(func() -> void:
		session.selected_good = gid
		refresh())
	return b


func _good_row(gv: Dictionary) -> Control:
	var b: Button = Button.new()
	b.flat = true
	b.custom_minimum_size = Vector2(0, 30)
	b.focus_mode = Control.FOCUS_NONE
	var h: HBoxContainer = _row_box()
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	b.add_child(h)
	var state: String = String(gv["state"])
	var tok: String = "text.primary" if state == "ok" else (JcUi.BAD if state == "short" else JcUi.WARN)
	var sel: bool = String(gv["id"]) == session.selected_good
	var nm: Label = _cell(("▸ " if sel else "") + String(gv["name"]), "body_bold" if sel else "body", tok, true)
	h.add_child(nm)
	var pp: int = int(gv["price_ppm"])
	h.add_child(_cell(price_word(pp), "body", JcUi.BAD if pp > 1_250_000 else (JcUi.WARN if pp < 800_000 else "text.secondary")))
	var unit: String = String(gv["unit"])
	h.add_child(_cell(JcFmt.qty(int(gv["prod"]), unit), "num", "text.secondary"))
	h.add_child(_cell(JcFmt.qty(int(gv["demand"]), unit), "num", "text.secondary"))
	var gap: int = int(gv["unmet"]) + int(gv["imp"])
	h.add_child(_cell(JcFmt.qty(gap, unit) if gap > 0 else "—", "num", JcUi.BAD if gap > 0 else "text.muted"))
	# 需求几乎为零时，库存季数会算出几十万季：一百季以上一律写「够百季以上」
	var sq: int = int(gv["stock_q"])
	var sq_txt: String = t("jc.ind.stock_lots") if sq > 100_000_000 else JwText.render("jc.ind.stock_q", {"q": JcFmt._dec(sq, 1_000_000, 1)})
	h.add_child(_cell(sq_txt, "num", "text.muted"))
	var gid: String = String(gv["id"])
	b.pressed.connect(func() -> void:
		session.selected_good = gid
		refresh())
	return b


## 价格与常价比：「持平」「+30%」「−20%」（列名是「较常价」）。
func price_word(pp: int) -> String:
	var d: int = pp - 1_000_000
	if absi(d) < 50_000:
		return t("jc.ind.price_normal")
	if d > 0:
		return rt("jc.ind.price_high", {"v": JcFmt.pct(d, 0)})
	return rt("jc.ind.price_low", {"v": JcFmt.pct(-d, 0)})


func _chain(gid: String) -> void:
	JwUi.clear(chain_box)
	if gid == "":
		return
	var g: JCGame = game()
	var ch: Dictionary = views().goods_chain(gid)
	if ch.is_empty():
		return
	var gv: Dictionary = ch["good"]
	# 这一行业在本时代的横幅（农林牧渔、手工与制造、能源、服务各四个时代）
	var sec: String = String(gv.get("sector", ""))
	var banner: String = JcUi.SECTOR_ART % [sec, clampi(g.st.era, 1, 4)]
	if sec != "" and JcUi.has_art(banner):
		chain_box.add_child(JcUi.art(banner, Vector2(0, 96)))
	var head: HBoxContainer = JwUi.hbox(12)
	head.add_child(JcUi.art(String(gv.get("art", "")), Vector2(64, 64), false))
	var hv: VBoxContainer = JwUi.vbox(2)
	hv.add_child(JwUi.title(String(gv.get("name", gid)), "title_block"))
	var state: String = String(gv.get("state", "ok"))
	hv.add_child(JwUi.label(rt("jc.ind.head", {"price": JcFmt.money(int(gv.get("price", 0))), "unit": String(gv.get("unit", "")),
			"ratio": JcFmt.pct(int(gv.get("price_ppm", 0)), 0), "state": t("jc.ind.state." + state)}), "body",
			JcUi.BAD if state == "short" else (JcUi.WARN if state == "glut" else "text.secondary")))
	# 货的层级（原料 / 半成品 / 成品 / 机器）与供需状况的小标签
	var tags: HBoxContainer = JwUi.hbox(6)
	var tier: int = int(gv.get("tier", -1))
	if tier >= 0:
		tags.add_child(JcUi.chip(t("jc.ind.tier.%d" % clampi(tier, 0, 3)), "text.secondary", false, JcUi.TIER_ICON % clampi(tier, 0, 3)))
	tags.add_child(JcUi.chip(t("jc.ind.state." + state), JcUi.BAD if state == "short" else (JcUi.WARN if state == "glut" else JcUi.GOOD),
			false, JcUi.STATUS_ICON % ("status_" + state)))
	hv.add_child(tags)
	head.add_child(hv)
	chain_box.add_child(head)
	# 产业链图：上下游一眼看清，点格子跳过去
	var graph: JcChainGraph = JcChainGraph.new()
	graph.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chain_box.add_child(graph)
	graph.set_data(views().chain_graph(gid))
	graph.picked.connect(func(pick: String) -> void:
		session.selected_good = pick
		refresh())
	# 补缺口
	var fix: Dictionary = ch.get("fix", {})
	if state == "short" and not fix.is_empty():
		var fc: PanelContainer = JwUi.panel_style(JwTheme.box_left_rule("bg.raised", JcUi.WARN, 4, 10))
		var fv: VBoxContainer = JwUi.vbox(6)
		fc.add_child(fv)
		var via: String = String(fix.get("input", ""))
		var txt: String = rt("jc.ind.fix", {"building": g.name_of("building", String(fix["building"])),
				"region": g.name_of("region", String(fix["region"])), "cost": JcFmt.money(int(fix["cost"]))})
		if via != "":
			txt = rt("jc.ind.fix_via", {"good": String(gv.get("name", "")), "input": g.name_of("good", via)}) + txt
		fv.add_child(JwUi.para(txt, "text.primary"))
		var cmd: Dictionary = fix["cmd"]
		fv.add_child(JcUi.button(t("jc.ind.fix_do"), true, func() -> void: session.order(cmd)))
		chain_box.add_child(fc)
	# 从哪来
	var pc: Dictionary = JcUi.card(t("jc.ind.from"))
	var pb: VBoxContainer = pc["body"]
	if (ch["producers"] as Array).is_empty():
		pb.add_child(JwUi.para(t("jc.ind.no_producer"), "text.muted"))
	for pr: Dictionary in ch["producers"]:
		var u: int = int(pr["u"])
		var prh: HBoxContainer = JwUi.hbox(10)
		prh.add_child(JcUi.badge(JcUi.res(String(pr.get("art", ""))), 48.0, String(pr["building_name"]), "line.strong"))
		var prr: HBoxContainer = JcUi.row(rt("jc.ind.producer", {"building": String(pr["building_name"]), "method": String(pr["method_name"]),
				"levels": str(int(pr["levels"]))}), JcFmt.pct(u, 0), "text.primary", u, JcUi.tone(u >= 850_000, u >= 500_000))
		prr.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		prh.add_child(prr)
		pb.add_child(prh)
		var ins: Array = pr["inputs"]
		if not ins.is_empty():
			var fl: HFlowContainer = JcUi.flow(6, 4)
			fl.add_child(JwUi.label(t("jc.ind.uses"), "caption", "text.muted"))
			for inp: Dictionary in ins:
				var f: int = int(inp["fill"])
				var tokn: String = JcUi.GOOD if f >= 900_000 else (JcUi.WARN if f >= 600_000 else JcUi.BAD)
				var cid: String = String(inp["id"])
				var chip_b: Button = JwUi.link(rt("jc.ind.input", {"name": String(inp["name"]), "fill": JcFmt.pct(f, 0)}))
				chip_b.add_theme_color_override("font_color", JwTheme.c(tokn))
				chip_b.pressed.connect(func() -> void:
					session.selected_good = cid
					refresh())
				fl.add_child(chip_b)
			pb.add_child(fl)
	for sl: Dictionary in ch["sellers"]:
		pb.add_child(JcUi.icon_label(JcUi.STATUS_ICON % "status_import", rt("jc.ind.seller", {"partner": String(sl["name"])}),
				"caption", "text.secondary", 18.0))
	chain_box.add_child(pc["root"])
	# 到哪去
	var cc: Dictionary = JcUi.card(t("jc.ind.to"))
	var cb: VBoxContainer = cc["body"]
	for n: Dictionary in ch["needs"]:
		var nh: HBoxContainer = JwUi.hbox(8)
		nh.add_child(JcUi.badge(JcUi.NEED_ICON % String(n["need"]), 36.0, String(n["name"]), "line.hair"))
		nh.add_child(JwUi.label(rt("jc.ind.need", {"need": String(n["name"])}) + (t("jc.ind.essential") if bool(n["essential"]) else ""),
				"body", "text.secondary"))
		cb.add_child(nh)
	for cs: Dictionary in ch["consumers"]:
		var cid2: String = String(cs.get("out", ""))
		var lb: Button = JwUi.link(rt("jc.ind.consumer", {"building": String(cs["building_name"]), "method": String(cs["method_name"]),
				"levels": str(int(cs["levels"]))}))
		if cid2 != "":
			lb.pressed.connect(func() -> void:
				session.selected_good = cid2
				refresh())
		var csh: HBoxContainer = JwUi.hbox(8)
		csh.add_child(JcUi.badge(JcUi.res(String(cs.get("art", ""))), 36.0, String(cs["building_name"]), "line.hair"))
		csh.add_child(lb)
		cb.add_child(csh)
	for by: Dictionary in ch["buyers"]:
		cb.add_child(JcUi.icon_label(JcUi.STATUS_ICON % "status_export", rt("jc.ind.buyer", {"partner": String(by["name"])}),
				"body", "text.secondary", 20.0))
	if (ch["needs"] as Array).is_empty() and (ch["consumers"] as Array).is_empty() and (ch["buyers"] as Array).is_empty():
		cb.add_child(JwUi.para(t("jc.ind.no_consumer"), "text.muted"))
	chain_box.add_child(cc["root"])
	# 能产它的建筑
	var oc: Dictionary = JcUi.card(t("jc.ind.options"))
	for op: Dictionary in ch["options"]:
		var bid: String = String(op["building"])
		var mid: String = String(op["method"])
		var row: HBoxContainer = JwUi.hbox(8)
		row.add_child(JcUi.badge(JcUi.res(String(op.get("art", ""))), 48.0, String(op["building_name"]), "line.strong"))
		row.add_child(JwUi.label(rt("jc.ind.option", {"building": String(op["building_name"]), "method": String(op["method_name"])}),
				"body", "text.secondary", true))
		row.add_child(JcUi.button(t("jc.ind.go_build"), false, func() -> void: open_overlay("build", {"building": bid, "method": mid})))
		(oc["body"] as VBoxContainer).add_child(row)
	chain_box.add_child(oc["root"])
