## 产业：商品一览（全部 / 紧缺 / 积压）＋ 选中商品的来龙去脉（谁在产、用什么料、谁在用）与补缺口的办法。
class_name JcPageIndustry
extends JcPage

var list_box: VBoxContainer = null
var chain_box: VBoxContainer = null
var _filter: String = "all"
var _fbtns: Dictionary = {}


func build() -> void:
	var h: HBoxContainer = JwUi.hbox(12)
	add_child(h)
	var lp: PanelContainer = JwUi.panel("bg.panel", "line.hair", 10)
	lp.custom_minimum_size = Vector2(700, 0)
	lp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	h.add_child(lp)
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
	var hdr: HBoxContainer = _row_box()
	for k: String in ["name", "price", "prod", "demand", "gap", "stock"]:
		hdr.add_child(_cell(JwText.t("jc.ind.col." + k), "caption", "text.muted", k == "name"))
	lv.add_child(hdr)
	list_box = JwUi.vbox(2)
	lv.add_child(JwUi.scroll(list_box))
	var rp: PanelContainer = JwUi.panel("bg.panel", "line.hair", 12)
	rp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	h.add_child(rp)
	chain_box = JwUi.vbox(10)
	rp.add_child(JwUi.scroll(chain_box))


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
	for gv: Dictionary in goods:
		var state: String = String(gv["state"])
		if _filter != "all" and state != _filter:
			continue
		if String(gv["sector"]) != last_sector:
			last_sector = String(gv["sector"])
			list_box.add_child(JwUi.label(JwText.t("jc.sector." + last_sector), "caption", "text.muted"))
		list_box.add_child(_good_row(gv))
	if session.selected_good == "" and not goods.is_empty():
		for gv2: Dictionary in goods:
			if String(gv2["state"]) == "short":
				session.selected_good = String(gv2["id"])
				break
		if session.selected_good == "":
			session.selected_good = String(goods[0]["id"])
	_chain(session.selected_good)


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
	h.add_child(_cell(JwText.render("jc.ind.stock_q", {"q": JcFmt._dec(int(gv["stock_q"]), 1_000_000, 1)}), "num", "text.muted"))
	var gid: String = String(gv["id"])
	b.pressed.connect(func() -> void:
		session.selected_good = gid
		refresh())
	return b


## 价格与常价比：「平价」「贵 30%」「贱 20%」。
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
	var head: HBoxContainer = JwUi.hbox(12)
	head.add_child(JcUi.art(String(gv.get("art", "")), Vector2(64, 64), false))
	var hv: VBoxContainer = JwUi.vbox(2)
	hv.add_child(JwUi.title(String(gv.get("name", gid)), "title_block"))
	var state: String = String(gv.get("state", "ok"))
	hv.add_child(JwUi.label(rt("jc.ind.head", {"price": JcFmt.money(int(gv.get("price", 0))), "unit": String(gv.get("unit", "")),
			"ratio": JcFmt.pct(int(gv.get("price_ppm", 0)), 0), "state": t("jc.ind.state." + state)}), "body",
			JcUi.BAD if state == "short" else (JcUi.WARN if state == "glut" else "text.secondary")))
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
		pb.add_child(JcUi.row(rt("jc.ind.producer", {"building": String(pr["building_name"]), "method": String(pr["method_name"]),
				"levels": str(int(pr["levels"]))}), JcFmt.pct(u, 0), "text.primary", u, JcUi.tone(u >= 850_000, u >= 500_000)))
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
		pb.add_child(JwUi.label(rt("jc.ind.seller", {"partner": String(sl["name"])}), "caption", "text.secondary"))
	chain_box.add_child(pc["root"])
	# 到哪去
	var cc: Dictionary = JcUi.card(t("jc.ind.to"))
	var cb: VBoxContainer = cc["body"]
	for n: Dictionary in ch["needs"]:
		cb.add_child(JwUi.label(rt("jc.ind.need", {"need": String(n["name"])}) + (t("jc.ind.essential") if bool(n["essential"]) else ""),
				"body", "text.secondary"))
	for cs: Dictionary in ch["consumers"]:
		var cid2: String = String(cs.get("out", ""))
		var lb: Button = JwUi.link(rt("jc.ind.consumer", {"building": String(cs["building_name"]), "method": String(cs["method_name"]),
				"levels": str(int(cs["levels"]))}))
		if cid2 != "":
			lb.pressed.connect(func() -> void:
				session.selected_good = cid2
				refresh())
		cb.add_child(lb)
	for by: Dictionary in ch["buyers"]:
		cb.add_child(JwUi.label(rt("jc.ind.buyer", {"partner": String(by["name"])}), "body", "text.secondary"))
	if (ch["needs"] as Array).is_empty() and (ch["consumers"] as Array).is_empty() and (ch["buyers"] as Array).is_empty():
		cb.add_child(JwUi.para(t("jc.ind.no_consumer"), "text.muted"))
	chain_box.add_child(cc["root"])
	# 能产它的建筑
	var oc: Dictionary = JcUi.card(t("jc.ind.options"))
	for op: Dictionary in ch["options"]:
		var bid: String = String(op["building"])
		var mid: String = String(op["method"])
		var row: HBoxContainer = JwUi.hbox(8)
		row.add_child(JwUi.label(rt("jc.ind.option", {"building": String(op["building_name"]), "method": String(op["method_name"])}),
				"body", "text.secondary", true))
		row.add_child(JcUi.button(t("jc.ind.go_build"), false, func() -> void: open_overlay("build", {"building": bid, "method": mid})))
		(oc["body"] as VBoxContainer).add_child(row)
	chain_box.add_child(oc["root"])
