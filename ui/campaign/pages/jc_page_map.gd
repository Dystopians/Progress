## 舆图：地图（图层、航线、悬停卡）+ 右侧选中地区的详情（配图、各阶层、用地、建筑与操作）。
class_name JcPageMap
extends JcPage

const LAYERS: PackedStringArray = ["terrain", "living", "unrest", "unemp", "logistics", "literacy", "industry", "pop"]

var map: JcMap = null
var side: VBoxContainer = null
var hover_card: PanelContainer = null
var _layer_btns: Dictionary = {}
var _regions: Array = []
var strip: HBoxContainer = null
var _sp: PanelContainer = null
var _narrow: bool = false


func build() -> void:
	var h: HBoxContainer = JwUi.hbox(12)
	add_child(h)
	var left: VBoxContainer = JwUi.vbox(8)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	h.add_child(left)
	var lb: HFlowContainer = JcUi.flow(4, 4)
	lb.add_child(JwUi.label(JwText.t("jc.map.layer"), "caption", "text.muted"))
	var grp: ButtonGroup = ButtonGroup.new()
	for id: String in LAYERS:
		var b: Button = JwUi.button(JwText.t("jc.map.layer." + id))
		b.toggle_mode = true
		b.button_group = grp
		b.pressed.connect(func() -> void: _set_layer(id))
		lb.add_child(b)
		_layer_btns[id] = b
	left.add_child(lb)
	left.add_child(JwUi.label(JwText.t("jc.map.legend"), "caption", "text.muted", true))
	# 地区一览：四个地区并排比一比，点一下选中
	strip = JwUi.hbox(8)
	strip.custom_minimum_size = Vector2(0, 92)
	left.add_child(strip)
	var holder: Control = Control.new()
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	holder.custom_minimum_size = Vector2(400, 380)
	left.add_child(holder)
	map = JcMap.new()
	map.name = "Map"
	map.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.add_child(map)
	map.region_selected.connect(_on_select)
	map.region_hovered.connect(_on_hover)
	hover_card = JwUi.panel_style(JwTheme.box4("bg.raised", "line.strong", 1, 8, 8, 8, 8))
	hover_card.visible = false
	hover_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(hover_card)
	var sp: PanelContainer = JwUi.panel("bg.panel", "line.hair", 12)
	sp.custom_minimum_size = Vector2(420, 0)
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	h.add_child(sp)
	_sp = sp
	side = JwUi.vbox(10)
	sp.add_child(JwUi.scroll(side))


## 窄的时候右侧详情收到 340 宽，地图多留一点；上面四张地区卡改成短行。
func relayout(w: float) -> void:
	if _sp == null or w <= 0.0:
		return
	var n: bool = w < 1150.0
	_sp.custom_minimum_size.x = 340.0 if n else 420.0
	if n != _narrow:
		_narrow = n
		if not _regions.is_empty():
			_fill_strip()


func refresh() -> void:
	if not session.has_game():
		return
	var g: JCGame = game()
	_regions = views().regions()
	var names: Dictionary = {}
	for rv: Dictionary in _regions:
		names[String(rv["id"])] = String(rv["name"])
	map.names = names
	map.routes = views().routes()
	map.selected = session.selected_region
	map.markers = marker_data(_regions)
	map.frame_title = rt("jc.map.frame_title", {"date": JcFmt.date(g.st.q, g.st.start_year)})
	(_layer_btns[session.map_layer] as Button).set_pressed_no_signal(true)
	_apply_layer()
	map.queue_redraw()
	_fill_strip()
	_side(g)


## 地图标记：每个地区前三样主要产业的配图、要紧的警示。
static func marker_data(regions: Array) -> Dictionary:
	var out: Dictionary = {}
	for rv: Dictionary in regions:
		var icons: Array = []
		for tp: Dictionary in (rv["top"] as Array).slice(0, 3):
			if String(tp.get("art", "")) != "":
				icons.append(String(tp["art"]))
		out[String(rv["id"])] = {"icons": icons, "alert": String(rv.get("alert", ""))}
	return out


func _fill_strip() -> void:
	JwUi.clear(strip)
	for rv: Dictionary in _regions:
		var rid: String = String(rv["id"])
		var sel: bool = rid == session.selected_region
		var b: Button = Button.new()
		b.flat = true
		b.focus_mode = Control.FOCUS_NONE
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 92)
		var p: PanelContainer = JwUi.panel_style(JwTheme.box_left_rule("bg.raised" if sel else "bg.panel",
				"focus.ring" if sel else "line.hair", 4, 8))
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		b.add_child(p)
		var v: VBoxContainer = JwUi.vbox(2)
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p.add_child(v)
		v.add_child(JwUi.label(String(rv["name"]), "body_bold", "text.primary"))
		var liv: int = int(rv["living"])
		var unr: int = int(rv["unrest"])
		var unr_s: Dictionary = {"unrest": JcFmt.pct(unr, 0), "unemp": JcFmt.pct(int(rv["unemp"]), 0)}
		if _narrow:
			v.add_child(JwUi.label(JcFmt.people(int(rv["pop"])), "caption", "text.secondary"))
			v.add_child(JwUi.label(rt("jc.map.strip_living", {"living": JcFmt.pct(liv, 0)}), "caption",
					JcUi.tone(liv >= 950_000, liv >= 850_000)))
			v.add_child(JwUi.label(rt("jc.map.strip_unrest", unr_s), "caption", JcUi.tone(unr < 250_000, unr < 450_000)))
		else:
			v.add_child(JwUi.label(rt("jc.map.strip_line", {"pop": JcFmt.people(int(rv["pop"])), "living": JcFmt.pct(liv, 0)}),
					"caption", JcUi.tone(liv >= 950_000, liv >= 850_000)))
			v.add_child(JwUi.label(rt("jc.map.strip_line2", unr_s), "caption", JcUi.tone(unr < 250_000, unr < 450_000)))
		if String(rv.get("alert", "")) != "":
			v.add_child(JwUi.label(t("jc.map.alert." + String(rv["alert"])), "caption", JcUi.BAD))
		var tops: PackedStringArray = PackedStringArray()
		for tp: Dictionary in (rv["top"] as Array).slice(0, 3):
			tops.append(String(tp["name"]))
		if not tops.is_empty() and not _narrow:
			var l: Label = JwUi.label(t("jc.name_sep").join(tops), "caption", "text.muted")
			l.clip_text = true
			v.add_child(l)
		b.pressed.connect(func() -> void:
			session.selected_region = rid
			map.selected = rid
			map.queue_redraw()
			_fill_strip()
			_side(game()))
		strip.add_child(b)


func _set_layer(id: String) -> void:
	session.map_layer = id
	_apply_layer()
	map.queue_redraw()


func _apply_layer() -> void:
	var layer: String = session.map_layer
	map.layer = layer
	map.layer_vals = {}
	map.labels_sub = {}
	if layer == "terrain":
		for rv: Dictionary in _regions:
			map.labels_sub[String(rv["id"])] = JcFmt.people(int(rv["pop"]))
		return
	for lv: Dictionary in views().map_layer(layer):
		var rid: String = String(lv["id"])
		map.layer_vals[rid] = lv
		var raw: int = int(lv["raw"])
		var txt: String = ""
		match layer:
			"pop":
				txt = JcFmt.people(raw)
			"industry":
				txt = rt("jc.map.share", {"v": JcFmt.pct(raw, 0)})
			_:
				txt = JcFmt.pct(raw, 0 if absi(raw) >= 100_000 else 1)
		map.labels_sub[rid] = JwText.t("jc.map.layer." + layer) + " " + txt


func _on_select(rid: String) -> void:
	session.selected_region = rid
	_fill_strip()
	_side(game())


func _on_hover(rid: String, at: Vector2) -> void:
	if rid == "":
		hover_card.visible = false
		return
	var rv: Dictionary = {}
	for x: Dictionary in _regions:
		if String(x["id"]) == rid:
			rv = x
	if rv.is_empty():
		return
	JwUi.clear(hover_card)
	var v: VBoxContainer = JwUi.vbox(4)
	hover_card.add_child(v)
	v.add_child(JcUi.art(String(rv["art"]), Vector2(240, 135)))
	v.add_child(JwUi.label(String(rv["name"]), "body_bold", "text.primary"))
	v.add_child(JwUi.label(rt("jc.map.hover", {"pop": JcFmt.people(int(rv["pop"])), "living": JcFmt.pct(int(rv["living"]), 0),
			"unemp": JcFmt.pct(int(rv["unemp"]))}), "caption", "text.secondary"))
	if String(rv.get("alert", "")) != "":
		v.add_child(JwUi.label(t("jc.map.alert." + String(rv["alert"])), "caption", JcUi.BAD))
	hover_card.visible = true
	hover_card.reset_size()
	var pos: Vector2 = at + Vector2(18, 18)
	var holder: Control = hover_card.get_parent() as Control
	if pos.x + hover_card.size.x > holder.size.x:
		pos.x = at.x - hover_card.size.x - 18
	if pos.y + hover_card.size.y > holder.size.y:
		pos.y = at.y - hover_card.size.y - 18
	hover_card.position = pos


func _side(g: JCGame) -> void:
	JwUi.clear(side)
	var d: Dictionary = views().region_detail(session.selected_region)
	if d.is_empty():
		return
	var rv: Dictionary = d["region"]
	side.add_child(JcUi.art(String(rv["art"]), Vector2(396, 220)))
	var hh: HBoxContainer = JwUi.hbox(8)
	hh.add_child(JwUi.title(String(rv["name"]), "title_block"))
	if bool(rv["capital"]):
		hh.add_child(JcUi.chip(t("jc.map.capital"), JcUi.WARN))
	if bool(rv["coast"]):
		hh.add_child(JcUi.chip(t("jc.map.coast"), JcUi.GOOD))
	if bool(rv["river"]):
		hh.add_child(JcUi.chip(t("jc.map.river"), JcUi.GOOD))
	side.add_child(hh)
	side.add_child(JwUi.para(String(rv["desc"]), "text.muted"))
	var grid: GridContainer = JcUi.grid(2, 16, 4)
	grid.add_child(JcUi.row(t("jc.map.pop"), JcFmt.people(int(rv["pop"]))))
	grid.add_child(JcUi.row(t("jc.map.living"), JcFmt.pct(int(rv["living"]), 0)))
	grid.add_child(JcUi.row(t("jc.map.unrest"), JcFmt.pct(int(rv["unrest"]), 0)))
	grid.add_child(JcUi.row(t("jc.map.unemp"), JcFmt.pct(int(rv["unemp"]))))
	grid.add_child(JcUi.row(t("jc.map.literacy"), JcFmt.pct(int(rv["literacy"]))))
	grid.add_child(JcUi.row(t("jc.map.logistics"), JcFmt.pct(int(rv["logistics"]))))
	grid.add_child(JcUi.row(t("jc.map.harvest"), JcFmt.pct(int(rv["harvest"]), 0)))
	grid.add_child(JcUi.row(t("jc.map.hidden"), JcFmt.pct(int(rv["hidden"]), 0)))
	side.add_child(grid)
	var bb: HBoxContainer = JwUi.hbox(8)
	var rid: String = String(rv["id"])
	bb.add_child(JcUi.button(t("jc.map.build_here"), true, func() -> void: open_overlay("build", {"region": rid})))
	side.add_child(bb)
	# 各阶层
	var cc: Dictionary = JcUi.card(t("jc.map.classes"))
	for cl: Dictionary in d["classes"]:
		var key: String = "jc.map.class_line_gentry" if String(cl["class"]) == "gentry" else "jc.map.class_line"
		var line: String = rt(key, {"class": String(cl["name"]), "pop": JcFmt.people(int(cl["pop"])),
				"income": JcFmt.money(JCMath.muldiv(int(cl["income_pc"]), 4, 1000)), "living": JcFmt.pct(int(cl["living"]), 0),
				"unemp": JcFmt.pct(int(cl["unemp"]))})
		(cc["body"] as VBoxContainer).add_child(JwUi.label(line, "body", "text.secondary", true))
	side.add_child(cc["root"])
	# 用地
	var lc: Dictionary = JcUi.card(t("jc.map.land"))
	for ld: Dictionary in d["land"]:
		var cap: int = maxi(1, int(ld["cap"]))
		var used: int = int(ld["used"])
		(lc["body"] as VBoxContainer).add_child(JcUi.row(t("jc.land." + String(ld["type"])),
				rt("jc.map.land_used", {"used": str(used), "cap": str(cap)}), "text.primary", JCMath.ratio_ppm(used, cap),
				JcUi.tone(used * 10 < cap * 9, used < cap)))
	side.add_child(lc["root"])
	# 建筑
	var bc: Dictionary = JcUi.card(t("jc.map.buildings"), t("jc.map.buildings_sub"))
	for gr: Dictionary in d["buildings"]:
		(bc["body"] as VBoxContainer).add_child(_bgroup(g, rid, gr))
	side.add_child(bc["root"])


func _bgroup(g: JCGame, rid: String, gr: Dictionary) -> Control:
	var v: VBoxContainer = JwUi.vbox(3)
	var h: HBoxContainer = JwUi.hbox(8)
	h.add_child(JwUi.label(rt("jc.map.bline", {"name": String(gr["name"]), "levels": str(int(gr["levels"]))}), "body_bold", "text.primary"))
	if int(gr["pending"]) > 0:
		h.add_child(JcUi.chip(rt("jc.map.pending", {"n": str(int(gr["pending"]))}), JcUi.WARN))
	h.add_child(JwUi.spacer())
	var u: int = int(gr["u"])
	var m: JcMeter = JcUi.meter(u, JcUi.tone(u >= 850_000, u >= 500_000), 80.0)
	h.add_child(m)
	h.add_child(JwUi.label(JcFmt.pct(u, 0), "num", "text.secondary"))
	v.add_child(h)
	for sv: Dictionary in gr["stacks"]:
		var row: HBoxContainer = JwUi.hbox(6)
		var desc: String = rt("jc.map.stack", {"method": String(sv["method_name"]), "level": str(int(sv["level"])),
				"owner": t("jc.owner." + String(sv["owner"])), "profit": JcFmt.money_signed(int(sv["profit"]))})
		row.add_child(JwUi.label(desc, "caption", "text.secondary", true))
		var bind: int = int(sv["bind"])
		if int(sv["status"]) == JCState.ST_MOTHBALL:
			row.add_child(JcUi.chip(t("jc.status.mothball"), JcUi.MUTED))
		elif int(sv["status"]) == JCState.ST_UPGRADE:
			row.add_child(JcUi.chip(rt("jc.status.upgrading", {"method": g.name_of("method", String(sv["target"]))}), JcUi.WARN))
		elif bind != 0 and int(sv["u"]) < 950_000:
			row.add_child(JcUi.chip(t("jc.bind.%d" % bind), JcUi.WARN))
		var uid: int = int(sv["uid"])
		if String(sv["newer"]) != "" and int(sv["status"]) == JCState.ST_ACTIVE:
			var cmd: Dictionary = {"kind": "upgrade", "uid": uid, "method": String(sv["newer"])}
			var chk: Dictionary = session.check(cmd)
			var b: Button = JcUi.button(rt("jc.map.upgrade_to", {"method": g.name_of("method", String(sv["newer"])),
					"cost": JcFmt.money(int(chk.get("cost", 0)))}), false, func() -> void: session.order(cmd))
			b.tooltip_text = t("jc.map.upgrade_tip")
			row.add_child(b)
		if String(sv["owner"]) == "gov":
			if int(sv["status"]) == JCState.ST_ACTIVE:
				row.add_child(JcUi.link(t("jc.map.mothball"), func() -> void: session.order({"kind": "mothball", "uid": uid})))
			elif int(sv["status"]) == JCState.ST_MOTHBALL:
				row.add_child(JcUi.link(t("jc.map.reopen"), func() -> void: session.order({"kind": "reopen", "uid": uid})))
			row.add_child(JcUi.link(t("jc.map.demolish"), func() -> void: session.order({"kind": "demolish", "uid": uid, "levels": 1})))
		v.add_child(row)
	return v
