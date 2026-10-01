## 国情：大数、迈向下一时代的清单（每项能直接去办）、三条危机、近年走势、各阶层民心。
class_name JcPageOverview
extends JcPage

## 页面宽度不到这个数（界面放大、窗口小）就把并排的两块改成上下排，走势改两列。
const NARROW_W: float = 1100.0

var _narrow: bool = false


func relayout(w: float) -> void:
	var n: bool = w > 0.0 and w < NARROW_W
	if n != _narrow:
		_narrow = n
		refresh()


## 并排的两块：宽的时候左右放，窄的时候上下放。
func _pair(sep: int) -> BoxContainer:
	if _narrow:
		return JwUi.vbox(sep)
	return JwUi.hbox(sep)


func refresh() -> void:
	clear()
	if not session.has_game():
		return
	var g: JCGame = game()
	var v: Dictionary = views().overview()
	var hist: Array = v["hist"]
	var ago: Dictionary = hist[maxi(0, hist.size() - 2)] if hist.size() >= 2 else {}
	# ── 大数 ──
	var tiles: HBoxContainer = JwUi.hbox(10)
	tiles.add_child(JcUi.tile(t("jc.ov.pop"), JcFmt.people(int(v["pop"])), _delta_people(int(v["pop"]), int(ago.get("pop", 0))),
			JcUi.MUTED, t("jc.ov.pop_tip")))
	tiles.add_child(JcUi.tile(t("jc.ov.gdp"), JcFmt.money(int(v["gdp"])), _delta_pct(int(v["gdp"]), int(ago.get("gdp", 0))),
			JcUi.MUTED, t("jc.ov.gdp_tip")))
	var bal: int = int(v["balance"])
	tiles.add_child(JcUi.tile(t("jc.ov.treasury"), JcFmt.money(int(v["treasury"])),
			rt("jc.ov.balance", {"v": JcFmt.money_signed(bal)}), JcUi.tone(bal >= 0), t("jc.ov.treasury_tip")))
	var liv: int = int(v["living"])
	tiles.add_child(JcUi.tile(t("jc.ov.living"), JcFmt.pct(liv, 0), rt("jc.ov.expect", {"v": JcFmt.times(int(v["expect"]))}),
			JcUi.tone(liv >= 950_000, liv >= 850_000), t("jc.ov.living_tip")))
	var un: int = int(v["unemp"])
	tiles.add_child(JcUi.tile(t("jc.ov.unemp"), JcFmt.pct(un), "", JcUi.MUTED, t("jc.ov.unemp_tip")))
	var leg: int = int(v["legitimacy"])
	tiles.add_child(JcUi.tile(t("jc.ov.legit"), JcFmt.pct(leg, 0), rt("jc.ov.prestige", {"v": str(int(v["prestige"]))}),
			JcUi.tone(leg >= 450_000, leg >= 300_000), t("jc.ov.legit_tip")))
	content.add_child(tiles)
	# ── 时代与危机 ──
	var two: BoxContainer = _pair(14)
	two.add_child(_era_card(g, v))
	two.add_child(_crisis_card(v))
	content.add_child(two)
	# ── 走势 ──
	var tr: Dictionary = JcUi.card(t("jc.ov.trend"), t("jc.ov.trend_sub"))
	var sg: GridContainer = JcUi.grid(2 if _narrow else 4, 16, 8)
	var series: Array = [["gdp", "jc.ov.gdp", JcUi.GOOD], ["pop", "jc.ov.pop", "series.3"], ["living", "jc.ov.living", JcUi.WARN],
			["treasury", "jc.ov.treasury", "series.4"]]
	for s: Array in series:
		var vals: Array = []
		for h: Dictionary in hist.slice(maxi(0, hist.size() - 60)):
			vals.append(float(h.get(String(s[0]), 0)))
		var col: VBoxContainer = JwUi.vbox(4)
		col.add_child(JwUi.label(t(String(s[1])), "caption", "text.muted"))
		var sp: JcSpark = JcUi.spark(vals, String(s[2]), Vector2(200, 60))
		sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_child(sp)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sg.add_child(col)
	(tr["body"] as VBoxContainer).add_child(sg)
	if hist.size() < 2:
		(tr["body"] as VBoxContainer).add_child(JwUi.para(t("jc.ov.trend_empty"), "text.muted"))
	content.add_child(tr["root"])
	# ── 小舆图 + 民心 ──
	var row3: BoxContainer = _pair(14)
	row3.add_child(_mini_map())
	var sc: Dictionary = JcUi.card(t("jc.ov.support"), t("jc.ov.support_sub"))
	var sb: GridContainer = JcUi.grid(2, 24, 6)
	var classes: Array = v["classes"]
	var sup: Array = v["support"]
	for i: int in classes.size():
		var sv: int = int(sup[i])
		sb.add_child(JcUi.row(g.name_of("class", String(classes[i])), JcFmt.pct(sv, 0), "text.primary", sv,
				JcUi.tone(sv >= 500_000, sv >= 350_000)))
	(sc["body"] as VBoxContainer).add_child(sb)
	_urgent(sc["body"])
	(sc["root"] as Control).size_flags_stretch_ratio = 0.8
	row3.add_child(sc["root"])
	content.add_child(row3)


## 眼下最要紧：缺口最大的几样货、民怨最重的几处，点一下直达。
func _urgent(box: VBoxContainer) -> void:
	box.add_child(JwUi.hsep())
	box.add_child(JwUi.label(t("jc.ov.urgent"), "title_sub", "text.primary"))
	var shorts: Array = []
	for gv: Dictionary in views().goods():
		if String(gv["state"]) == "short" and int(gv["demand"]) > 0:
			shorts.append(gv)
	shorts.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["short_ppm"]) > int(b["short_ppm"]) or (int(a["short_ppm"]) == int(b["short_ppm"]) and int(a["g"]) < int(b["g"])))
	var n: int = 0
	for gv2: Dictionary in shorts.slice(0, 3):
		var gid: String = String(gv2["id"])
		var gap: int = int(gv2["short_ppm"])
		box.add_child(JcUi.link(rt("jc.ov.urgent_good", {"good": String(gv2["name"]), "gap": JcFmt.pct(gap, 0)}), func() -> void:
			session.selected_good = gid
			goto_page("industry")))
		n += 1
	for h: Dictionary in views().society()["hotspots"]:
		if int(h["unrest"]) < 300_000 or n >= 5:
			continue
		var rid: String = String(h["region"])
		box.add_child(JcUi.link(rt("jc.ov.urgent_place", {"region": game().name_of("region", rid),
				"class": game().name_of("class", String(h["class"])), "unrest": JcFmt.pct(int(h["unrest"]), 0),
				"cause": JcFmt.k(String(h["cause"]))}), func() -> void:
			session.selected_region = rid
			goto_page("map")))
		n += 1
	if n == 0:
		box.add_child(JwUi.para(t("jc.ov.urgent_none"), JcUi.GOOD))


func _mini_map() -> PanelContainer:
	var c: Dictionary = JcUi.card(t("jc.ov.map"), t("jc.ov.map_sub"))
	var holder: Control = Control.new()
	holder.custom_minimum_size = Vector2(0, 340)
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var m: JcMap = JcMap.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.add_child(m)
	var regions: Array = views().regions()
	var names: Dictionary = {}
	for rv: Dictionary in regions:
		names[String(rv["id"])] = String(rv["name"])
		m.labels_sub[String(rv["id"])] = rt("jc.ov.map_line", {"living": JcFmt.pct(int(rv["living"]), 0)})
	m.names = names
	m.routes = views().routes()
	m.markers = JcPageMap.marker_data(regions)
	m.region_selected.connect(func(rid: String) -> void:
		session.selected_region = rid
		goto_page("map"))
	(c["body"] as VBoxContainer).add_child(holder)
	(c["root"] as Control).size_flags_stretch_ratio = 1.4
	return c["root"]


func _delta_pct(now: int, before: int) -> String:
	if before <= 0:
		return ""
	return rt("jc.ov.vs_last_year", {"v": JcFmt.pct_signed(JCMath.ratio_ppm(now - before, before))})


func _delta_people(now: int, before: int) -> String:
	if before <= 0:
		return ""
	return rt("jc.ov.vs_last_year", {"v": ("+" if now >= before else "") + JcFmt.people(now - before)})


func _era_card(g: JCGame, v: Dictionary) -> PanelContainer:
	var plan: Dictionary = v["era_plan"]
	var era: int = int(v["era"])
	var world: int = int(v["world_era"])
	var title: String = rt("jc.ov.era_title", {"era": JcFmt.era_name(mini(4, era + 1))}) if era < 4 else t("jc.ov.era_final")
	var c: Dictionary = JcUi.card(title, rt("jc.ov.era_now", {"era": JcFmt.era_name(era), "world": JcFmt.era_name(world)}))
	var body: VBoxContainer = c["body"]
	(c["head"] as HBoxContainer).add_child(JcUi.link(t("jc.ov.era_book"), func() -> void: open_overlay("era", {"kind": "book"})))
	if era >= 4:
		body.add_child(JwUi.para(t("jc.ov.era_final_body"), "text.secondary"))
		return c["root"]
	body.add_child(JwUi.para(t("jc.ov.era_hint_lead") if world <= era else t("jc.ov.era_hint_behind"), "text.muted"))
	var items: Array = plan.get("items", [])
	if items.is_empty():
		body.add_child(JwUi.para(t("jc.ov.era_ready"), JcUi.GOOD))
	for it: Dictionary in items:
		var row: HBoxContainer = JwUi.hbox(10)
		var txt: String = ""
		match String(it["kind"]):
			"tech":
				txt = rt("jc.ov.need_tech", {"tech": g.name_of("tech", String(it["id"]))})
				if String(it.get("next", "")) != String(it["id"]):
					txt += rt("jc.ov.need_tech_first", {"tech": g.name_of("tech", String(it["next"]))})
			"building":
				txt = rt("jc.ov.need_building", {"building": g.name_of("building", String(it["id"])),
						"have": str(int(it["have"])), "need": str(int(it["need"]))})
				if bool(it.get("locked", false)):
					txt += rt("jc.ov.need_locked", {"tech": g.name_of("tech", String(it.get("tech", "")))})
			"social":
				txt = rt("jc.ov.need_social." + String(it["id"]), {"have": JcFmt.pct(int(it["have"])), "need": JcFmt.pct(int(it["need"]))})
		var l: Label = JwUi.label(txt, "body", "text.secondary", true)
		row.add_child(l)
		if it.has("cmd"):
			var cmd: Dictionary = it["cmd"]
			var lab: String = t("jc.ov.do")
			if int(it.get("cost", 0)) > 0:
				lab = rt("jc.ov.do_cost", {"cost": JcFmt.money(int(it["cost"]))})
			row.add_child(JcUi.button(lab, false, func() -> void: session.order(cmd)))
		body.add_child(row)
	return c["root"]


func _crisis_card(v: Dictionary) -> PanelContainer:
	var c: Dictionary = JcUi.card(t("jc.ov.crisis"), t("jc.ov.crisis_sub"))
	var body: VBoxContainer = c["body"]
	for cr: Dictionary in v["crisis"]:
		var tr: int = int(cr["track"])
		var stg: int = int(cr["stage"])
		var h: HBoxContainer = JwUi.hbox(10)
		var nm: Label = JwUi.label(t("jc.crisis.%d" % tr), "body_bold", "text.primary")
		nm.custom_minimum_size = Vector2(90, 0)
		h.add_child(nm)
		var m: JcMeter = JcUi.meter(int(cr["severity"]), JcUi.GOOD if stg == 0 else (JcUi.WARN if stg == 1 else JcUi.BAD), 160.0, 10.0)
		m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(m)
		h.add_child(JcUi.chip(t("jc.stage.%d" % stg), JcUi.GOOD if stg == 0 else (JcUi.WARN if stg == 1 else JcUi.BAD)))
		body.add_child(h)
		body.add_child(JwUi.para(t("jc.crisis.explain.%d" % tr), "text.muted"))
	return c["root"]
